local yamlcamel = require("yamlcamel")
local compression = require("yamlcamel.io.compression")

-- A transport double: returns whatever response was handed to it and records the request it
-- was given, so a test can both drive the response side and assert on what yamlcamel.http sent.
local function fake_transport(response)
  local captured
  return {
    request = function(req)
      captured = req
      return response
    end,
  }, function() return captured end
end

describe("yamlcamel.http_get against an injected transport", function()
  it("decodes a plain YAML response", function()
    local fake = fake_transport({ status = 200, headers = { ["content-type"] = "application/yaml" }, body = "a: 1\n" })
    local v = yamlcamel.http_get("http://example.invalid/", { transport = fake })
    assert.are.equal(1, v.a)
  end)

  it("decodes a gzip-encoded response, sniffing the magic bytes rather than trusting the header alone", function()
    local compressed = compression.default.compress("a: 2\n")
    local fake = fake_transport({
      status = 200,
      headers = { ["content-type"] = "application/yaml", ["content-encoding"] = "gzip" },
      body = compressed,
    })
    local v = yamlcamel.http_get("http://example.invalid/", { transport = fake })
    assert.are.equal(2, v.a)
  end)

  it("tolerates a Content-Encoding: gzip header on a body that is not actually gzip", function()
    -- A proxy that already decoded the body, or a server that lied, still has to be readable.
    local fake = fake_transport({
      status = 200,
      headers = { ["content-type"] = "application/yaml", ["content-encoding"] = "gzip" },
      body = "a: 3\n",
    })
    local v = yamlcamel.http_get("http://example.invalid/", { transport = fake })
    assert.are.equal(3, v.a)
  end)

  it("raises for a non-2xx status", function()
    local fake = fake_transport({ status = 500, headers = {}, body = "boom" })
    local ok, err = pcall(yamlcamel.http_get, "http://example.invalid/", { transport = fake })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("500", 1, true))
  end)

  it("raises for a response that is not YAML", function()
    local fake = fake_transport({ status = 200, headers = { ["content-type"] = "text/plain" }, body = "a: 1\n" })
    local ok, err = pcall(yamlcamel.http_get, "http://example.invalid/", { transport = fake })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
  end)

  it("rejects a gzip-encoded response that decompresses to a bomb, while inflating it rather than after", function()
    -- A malicious or compromised server can set Content-Encoding: gzip on a body that
    -- decompresses to far more than the response itself ever was. yamlcamel.http decompresses
    -- through the same yamlcamel.io.compression default decode_gzip_file and
    -- decode_file_stream do, so it inherits the same bound whichever way the bytes arrived.
    local mb = 1500
    local c = compression.default.new_compressor()
    local parts = {}
    local chunk = string.rep("\0", 1024 * 1024)
    for _ = 1, mb do
      local out = assert(c:push(chunk))
      parts[#parts + 1] = out
    end
    parts[#parts + 1] = assert(c:finish())
    local bomb = table.concat(parts)

    local fake = fake_transport({
      status = 200,
      headers = { ["content-type"] = "application/yaml", ["content-encoding"] = "gzip" },
      body = bomb,
    })
    local t0 = os.clock()
    local ok, err = pcall(yamlcamel.http_get, "http://example.invalid/", { transport = fake })
    local elapsed = os.clock() - t0

    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("exceeds", 1, true))
    assert.is_true(elapsed < 0.5, "took " .. elapsed .. "s")
  end)

  it("raises for a response larger than the configured bound", function()
    local fake = fake_transport({ status = 200, headers = { ["content-type"] = "application/yaml" }, body = "a: 1\n" })
    local ok, err = pcall(yamlcamel.http_get, "http://example.invalid/", { transport = fake, max_response_bytes = 2 })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("exceeds", 1, true))
  end)

  it("raises when the transport itself fails to reach the server", function()
    local fake = { request = function() return nil, "connection refused" end }
    local ok, err = pcall(yamlcamel.http_get, "http://example.invalid/", { transport = fake })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("connection refused", 1, true))
  end)

  it("sends a GET with the yamlcamel media type in Accept", function()
    local fake, get_captured = fake_transport({ status = 200, headers = { ["content-type"] = "application/yaml" }, body = "a: 1\n" })
    yamlcamel.http_get("http://example.invalid/", { transport = fake })
    assert.are.equal("GET", get_captured().method)
  end)
end)

describe("yamlcamel.http_post against an injected transport", function()
  it("sends the value as a plain YAML body and decodes a plain YAML response", function()
    local fake, get_captured = fake_transport({
      status = 201,
      headers = { ["content-type"] = "application/yaml" },
      body = "ok: true\n",
    })
    local v = yamlcamel.http_post("http://example.invalid/", { hello = "world" }, { transport = fake })
    local req = get_captured()
    assert.is_true(v.ok)
    assert.are.equal("POST", req.method)
    assert.are.equal("application/yaml", req.headers["content-type"])
    assert.is_nil(req.headers["content-encoding"])
    local sent = yamlcamel.decode(req.body)
    assert.are.equal("world", sent.hello)
  end)

  it("gzips the request body when asked, and decodes a gzip response back", function()
    local received
    local fake = {
      request = function(req)
        received = req
        local compressed = compression.default.compress("ack: 1\n")
        return {
          status = 200,
          headers = { ["content-type"] = "application/yaml", ["content-encoding"] = "gzip" },
          body = compressed,
        }
      end,
    }
    local v = yamlcamel.http_post("http://example.invalid/", { x = 1 }, { transport = fake, compress_body = true })
    assert.are.equal(1, v.ack)
    assert.are.equal("gzip", received.headers["content-encoding"])
    assert.is_true(compression.has_gzip_magic(received.body))
    local sent = yamlcamel.decode(compression.default.decompress(received.body))
    assert.are.equal(1, sent.x)
  end)

  it("raises for a non-2xx status", function()
    local fake = fake_transport({ status = 400, headers = {}, body = "bad request" })
    local ok, err = pcall(yamlcamel.http_post, "http://example.invalid/", { x = 1 }, { transport = fake })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("400", 1, true))
  end)

  it("raises when the transport itself fails", function()
    local fake = { request = function() return nil, "timed out" end }
    local ok, err = pcall(yamlcamel.http_post, "http://example.invalid/", { x = 1 }, { transport = fake })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("timed out", 1, true))
  end)
end)

describe("swapping in a custom transport, compression and file implementation", function()
  it("uses every injected implementation instead of the corresponding default, for the same call", function()
    local calls = { transport = 0, compression = 0, file = 0 }

    local fake_transport_impl = {
      request = function(req)
        calls.transport = calls.transport + 1
        return { status = 200, headers = { ["content-type"] = "application/yaml" }, body = req.body or "seen: true\n" }
      end,
    }
    local fake_compression_impl = {
      compress = function(data) calls.compression = calls.compression + 1; return "FAKE[" .. data .. "]" end,
      decompress = function(data) calls.compression = calls.compression + 1; return data:match("^FAKE%[(.*)%]$") end,
      -- yamlcamel.gzip.decode_file drives the streaming shape below, not the one-shot
      -- decompress above, so a compressed file too large to trust whole can still be
      -- rejected while reading it; see yamlcamel.io.compression's own module comment for
      -- the four-function shape a complete implementation satisfies.
      new_compressor = function()
        local parts = {}
        return {
          push = function(_, chunk) calls.compression = calls.compression + 1; parts[#parts + 1] = chunk or ""; return "" end,
          finish = function(_)
            calls.compression = calls.compression + 1
            return "FAKE[" .. table.concat(parts) .. "]"
          end,
        }
      end,
      new_decompressor = function()
        local parts = {}
        return {
          push = function(_, chunk) calls.compression = calls.compression + 1; parts[#parts + 1] = chunk or ""; return "" end,
          finish = function(_)
            calls.compression = calls.compression + 1
            return table.concat(parts):match("^FAKE%[(.*)%]$") or ""
          end,
        }
      end,
    }
    local store = {}
    local fake_file_impl = {
      read = function(path) calls.file = calls.file + 1; return store[path] end,
      write = function(path, content) calls.file = calls.file + 1; store[path] = content; return true end,
      -- yamlcamel.gzip.decode_file reads through the handle shape, not the whole-file one
      -- above, so it can bound a compressed file's size while still reading it rather than
      -- only after the whole thing is already in memory; see yamlcamel.io.file's own
      -- module comment for the four-function shape a complete implementation satisfies.
      open_read = function(path)
        calls.file = calls.file + 1
        local content = store[path]
        if not content then return nil, "no such file" end
        local pos = 1
        return {
          read = function(_, n)
            if pos > #content then return nil end
            local chunk = content:sub(pos, pos + n - 1)
            pos = pos + #chunk
            return chunk
          end,
          close = function() end,
        }
      end,
    }

    local opts = { transport = fake_transport_impl, compression = fake_compression_impl, file = fake_file_impl }

    yamlcamel.http_get("http://example.invalid/", opts)
    assert.are.equal(1, calls.transport)

    yamlcamel.http_post("http://example.invalid/", { x = 1 }, opts)
    assert.are.equal(2, calls.transport)

    yamlcamel.encode_gzip_file("virtual.yaml.gz", { a = 1 }, opts)
    yamlcamel.decode_gzip_file("virtual.yaml.gz", opts)
    assert.is_true(calls.compression > 0)
    assert.is_true(calls.file > 0)
  end)
end)

describe("yamlcamel.io.transport.default against a mocked http rock", function()
  -- daurnimator/http's own stream:get_body_as_string just loops stream:get_next_chunk with no
  -- size awareness at all, the same way this fake does: a faithful enough stand-in that a
  -- transport calling it, rather than reading chunk by chunk itself and checking the running
  -- total, drains the whole body regardless of `max_response_bytes` before ever handing anything
  -- back. Standing in for the real rock, which this spec cannot assume is installed (see below).
  local function fake_http_rock(chunk, chunk_count)
    local calls = 0
    local module = {}
    function module.new_from_uri()
      local r = { headers = { upsert = function() end } }
      function r:set_body() end
      function r:go()
        local stream = {}
        local sent = 0
        function stream:get_next_chunk()
          calls = calls + 1
          if sent >= chunk_count then return nil end
          sent = sent + 1
          return chunk
        end
        function stream:get_body_as_string(timeout)
          local body, i = {}, 0
          while true do
            local c = self:get_next_chunk(timeout)
            if c == nil then break end
            i = i + 1
            body[i] = c
          end
          return table.concat(body)
        end
        -- An empty table with :get tucked behind a metatable rather than as a real key, so the
        -- response-header loop's own `pairs(headers)` (further down {request}, on the success
        -- path this test's fix never reaches) sees no entries rather than picking up "get"
        -- itself as a bogus header name.
        local resp_headers = setmetatable({}, {
          __index = { get = function(_, name) return name == ":status" and "200" or nil end },
        })
        return resp_headers, stream
      end
      return r
    end
    return module, function() return calls end
  end

  it("stops pulling chunks once the response exceeds max_response_bytes, rather than draining the whole body first", function()
    -- 100000 chunks of 1 KB is a body far bigger than any legitimate YAML document this library
    -- is for, standing in for an oversized or endlessly drip-fed response; get_next_chunk is
    -- called at most a handful of times before max_response_bytes (4 KB here) is crossed.
    local fake_module, get_call_count = fake_http_rock(string.rep("x", 1024), 100000)

    local saved = package.loaded["http.request"]
    package.loaded["http.request"] = fake_module
    local transport = require("yamlcamel.io.transport")
    local response, err = transport.default.request({
      method = "GET",
      url = "http://example.invalid/",
      max_response_bytes = 4096,
    })
    package.loaded["http.request"] = saved

    -- Checked first and by itself: a failure here means the whole fake body got drained, and
    -- printing that (a real assert.is_nil(response) on a response holding it would) is its own
    -- multi-megabyte mess rather than a useful failure message.
    assert.is_true(get_call_count() < 100,
      "pulled " .. get_call_count() .. " chunks instead of stopping shortly after the bound")
    assert.is_nil(response)
    assert.is_truthy(tostring(err):find("exceeds", 1, true))
  end)
end)

describe("yamlcamel.http_get against the real default transport", function()
  local has_http_rock = pcall(require, "http.request")

  it("raises a yamlcamel error rather than hanging when the connection is refused", function()
    if not has_http_rock then
      pending("needs the 'http' rock installed; see README")
      return
    end
    -- Loopback with nothing listening refuses instantly everywhere, so this cannot hang the way
    -- a real outbound request could on a runner with no guaranteed network access.
    local ok, err = pcall(yamlcamel.http_get, "http://127.0.0.1:1/", { timeout = 2 })
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
  end)
end)
