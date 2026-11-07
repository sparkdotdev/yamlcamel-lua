local yamlcamel = require("yamlcamel")
local compression = require("yamlcamel.io.compression")

local function read_bytes(path)
  local file = io.open(path, "rb")
  local content = file:read("a")
  file:close()
  return content
end

local function write_bytes(path, content)
  local file = io.open(path, "wb")
  file:write(content)
  file:close()
end

describe("yamlcamel.decode_gzip_file and yamlcamel.encode_gzip_file", function()
  it("round-trips a value through a real gzip-compressed file", function()
    local path = os.tmpname()
    yamlcamel.encode_gzip_file(path, { name = "test", tags = { "one", "two" } })
    local decoded = yamlcamel.decode_gzip_file(path)
    os.remove(path)
    assert.are.equal("test", decoded.name)
    assert.are.same({ "one", "two" }, decoded.tags)
  end)

  it("actually writes gzip bytes, not plain YAML text", function()
    local path = os.tmpname()
    yamlcamel.encode_gzip_file(path, { a = 1 })
    local raw = read_bytes(path)
    os.remove(path)
    assert.are.equal(0x1f, raw:byte(1))
    assert.are.equal(0x8b, raw:byte(2))
  end)

  it("raises when the file cannot be opened for reading", function()
    assert.has_error(function() yamlcamel.decode_gzip_file("/nonexistent/path/for/sure.yaml.gz") end)
  end)

  it("raises for a file that is not actually gzip", function()
    local path = os.tmpname()
    write_bytes(path, "not gzip data at all")
    local ok, err = pcall(yamlcamel.decode_gzip_file, path)
    os.remove(path)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
  end)

  it("rejects a decompression bomb while inflating it, not after", function()
    -- Built through the streaming compressor so building the fixture itself never holds the
    -- whole logical payload in memory: 1.5 GB of zero bytes compresses down to about 1.5 MB.
    -- The one-shot decompress() helper used to hand that whole compressed blob to a single
    -- push() call, which inflates everything it is given before returning regardless of size,
    -- so the output ceiling only ever got checked once the entire 1.5 GB was already sitting
    -- in memory: decompressing this same file used to take about a second of CPU and reach
    -- several gigabytes of resident memory. Chunked internally now, the same call rejects it
    -- in milliseconds, never inflating more than a couple of chunks past the ceiling.
    local mb = 1500
    local c = compression.default.new_compressor()
    local parts = {}
    local chunk = string.rep("\0", 1024 * 1024)
    for _ = 1, mb do parts[#parts + 1] = assert(c:push(chunk)) end
    parts[#parts + 1] = assert(c:finish())
    local bomb = table.concat(parts)

    local t0 = os.clock()
    local out, err = compression.default.decompress(bomb)
    local elapsed = os.clock() - t0

    assert.is_nil(out)
    assert.is_truthy(tostring(err):find("exceeds", 1, true))
    assert.is_true(elapsed < 0.5, "took " .. elapsed .. "s")
  end)

  it("rejects a decompression bomb read from disk the same bounded way", function()
    -- decode_file used to read the whole compressed file through file.read (one unbounded
    -- slurp) and hand it to the one-shot decompress() above in a single call, so a bomb
    -- sitting on disk was exactly as unbounded as one already in memory: rejecting it still
    -- took about a fifth of a second at this size, since the whole thing was inflated first
    -- regardless. It now streams the file in chunks the same way yamlcamel.stream always
    -- has, so the same file rejects in milliseconds instead.
    local mb = 1500
    local c = compression.default.new_compressor()
    local path = os.tmpname()
    local f = io.open(path, "wb")
    local chunk = string.rep("\0", 1024 * 1024)
    for _ = 1, mb do
      local out = assert(c:push(chunk))
      f:write(out)
    end
    local tail = assert(c:finish())
    f:write(tail)
    f:close()

    local t0 = os.clock()
    local ok, err = pcall(yamlcamel.decode_gzip_file, path)
    local elapsed = os.clock() - t0
    os.remove(path)

    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("exceeds", 1, true))
    assert.is_true(elapsed < 0.5, "took " .. elapsed .. "s")
  end)

  it("raises for a gzip stream truncated before its trailer", function()
    local compressed = compression.default.compress("a: 1\n")
    local path = os.tmpname()
    write_bytes(path, compressed:sub(1, #compressed - 5))
    local ok, err = pcall(yamlcamel.decode_gzip_file, path)
    os.remove(path)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
  end)

  it("uses an injected file and compression implementation instead of the defaults", function()
    local store = {}
    -- yamlcamel.gzip.decode_file drives the streaming shape of both contracts (open_read,
    -- new_decompressor), not the whole-file/one-shot shape (read, decompress), so a
    -- compressed file too large to trust whole can still be rejected while reading it
    -- rather than only after it is already in memory. A complete injected implementation
    -- provides both; see yamlcamel.io.file and yamlcamel.io.compression's own module
    -- comments for the full four-function shape each contract expects.
    local fake_file = {
      read = function(path) return store[path] end,
      write = function(path, content) store[path] = content; return true end,
      open_read = function(path)
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
    local fake_compression = {
      compress = function(data) return "FAKE[" .. data .. "]" end,
      decompress = function(data) return data:match("^FAKE%[(.*)%]$") end,
      new_compressor = function()
        local parts = {}
        return {
          push = function(_, chunk) parts[#parts + 1] = chunk or ""; return "" end,
          finish = function(_) return "FAKE[" .. table.concat(parts) .. "]" end,
        }
      end,
      new_decompressor = function()
        local parts = {}
        return {
          push = function(_, chunk) parts[#parts + 1] = chunk or ""; return "" end,
          finish = function(_) return table.concat(parts):match("^FAKE%[(.*)%]$") or "" end,
        }
      end,
    }
    yamlcamel.encode_gzip_file("virtual.yaml.gz", { hi = "there" },
      { file = fake_file, compression = fake_compression })
    assert.is_truthy(store["virtual.yaml.gz"]:find("FAKE[", 1, true))
    local decoded = yamlcamel.decode_gzip_file("virtual.yaml.gz",
      { file = fake_file, compression = fake_compression })
    assert.are.equal("there", decoded.hi)
  end)
end)
