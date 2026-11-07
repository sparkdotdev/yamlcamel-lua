local yamlcamel = require("yamlcamel")
local compression = require("yamlcamel.io.compression")

local function write_file(path, content)
  local file = io.open(path, "wb")
  file:write(content)
  file:close()
end

local function collect(path, opts)
  local docs = {}
  yamlcamel.decode_file_stream(path, function(v) docs[#docs + 1] = v end, opts)
  return docs
end

describe("yamlcamel.decode_file_stream", function()
  it("matches decode_all for an ordinary multi-document stream", function()
    local text = "---\na: 1\n---\nb: 2\n---\nc: 3\n"
    local path = os.tmpname()
    write_file(path, text)
    local docs = collect(path)
    os.remove(path)
    local all = yamlcamel.decode_all(text)
    assert.are.equal(#all, #docs)
    assert.are.equal(1, docs[1].a)
    assert.are.equal(2, docs[2].b)
    assert.are.equal(3, docs[3].c)
  end)

  it("matches decode_all across explicit end-of-document markers and an empty document", function()
    local text = "---\n---\na: 1\n...\n---\nb: 2\n...\n"
    local path = os.tmpname()
    write_file(path, text)
    local docs = collect(path)
    os.remove(path)
    local all = yamlcamel.decode_all(text)
    assert.are.equal(#all, #docs)
    assert.is_true(yamlcamel.is_null(docs[1]))
    assert.are.equal(1, docs[2].a)
    assert.are.equal(2, docs[3].b)
  end)

  it("still gathers a block scalar's lines correctly split across small chunk reads", function()
    local text = "---\nbody: |\n  first line\n  second line\n---\nbody: |\n  third\n"
    local path = os.tmpname()
    write_file(path, text)
    -- A tiny chunk size forces the block scalar's own lines to arrive across several reads.
    local docs = collect(path, { chunk_size = 5 })
    os.remove(path)
    assert.are.equal("first line\nsecond line\n", docs[1].body)
    assert.are.equal("third\n", docs[2].body)
  end)

  it("reads an implicit single document with no leading marker at all", function()
    local path = os.tmpname()
    write_file(path, "a: 1\nb: 2\n")
    local docs = collect(path)
    os.remove(path)
    assert.are.equal(1, #docs)
    assert.are.equal(1, docs[1].a)
  end)

  it("calls the callback zero times for a blank stream", function()
    local path = os.tmpname()
    write_file(path, "\n\n")
    local docs = collect(path)
    os.remove(path)
    assert.are.equal(0, #docs)
  end)

  it("raises when the file cannot be opened", function()
    assert.has_error(function()
      yamlcamel.decode_file_stream("/nonexistent/for/sure.yaml", function() end)
    end)
  end)

  it("reads a gzip-compressed stream the same way, chunk by chunk", function()
    local text = "---\na: 1\n---\nb: 2\n"
    local compressed = compression.default.compress(text)
    local path = os.tmpname()
    write_file(path, compressed)
    local docs = collect(path, { gzip = true, chunk_size = 8 })
    os.remove(path)
    assert.are.equal(2, #docs)
    assert.are.equal(1, docs[1].a)
    assert.are.equal(2, docs[2].b)
  end)

  it("raises for a gzip stream that is not actually gzip", function()
    local path = os.tmpname()
    write_file(path, "not gzip data at all")
    local ok, err = pcall(collect, path, { gzip = true })
    os.remove(path)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
  end)

  it("agrees with decode_all on a byte order mark opening a document past the first", function()
    -- decode_all used to strip a BOM only at the very start of the whole stream, while this
    -- reader parses each document through its own fresh call to yamlcamel.decode, which
    -- strips a leading BOM off whatever text it is given. The two used to disagree on the
    -- exact same bytes: the key here came back as "\239\187\191b" from decode_all and "b"
    -- from decode_file_stream.
    local BOM = "\239\187\191"
    local text = "a: 1\n---\n" .. BOM .. "b: 2\n---\nc: 3\n"
    local path = os.tmpname()
    write_file(path, text)
    local docs = collect(path)
    os.remove(path)
    local all = yamlcamel.decode_all(text)
    assert.are.equal(#all, #docs)
    for i = 1, #all do
      for k, v in pairs(all[i]) do
        assert.are.equal(v, docs[i][k], "document " .. i .. " key " .. tostring(k))
      end
    end
    assert.are.equal(2, docs[2].b)
  end)

  it("uses an injected file implementation instead of the default", function()
    local chunks = { "---\n", "a: 1\n", "---\n", "b: 2\n" }
    local i = 0
    local fake_handle = {
      read = function() i = i + 1; return chunks[i] end,
      close = function() end,
    }
    local fake_file = {
      open_read = function(path)
        assert.are.equal("virtual.yaml", path)
        return fake_handle
      end,
    }
    local docs = {}
    yamlcamel.decode_file_stream("virtual.yaml", function(v) docs[#docs + 1] = v end, { file = fake_file })
    assert.are.equal(2, #docs)
    assert.are.equal(1, docs[1].a)
    assert.are.equal(2, docs[2].b)
  end)
end)
