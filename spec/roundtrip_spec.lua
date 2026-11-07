local yamlcamel = require("yamlcamel")

-- Encode then decode a representative body, and check what comes back
-- matches what went in field by field. This is a typical REST API
-- request body shape: a mapping of scalars, a nested mapping, and
-- an array of mappings.
describe("yamlcamel round-tripping", function()
  it("preserves a feature write body", function()
    local input = {
      enabled = true,
      config = {
        limit = 5,
        label = "needs: quoting, and a # too",
        strict = false,
        tags = { "one", "two", "three" },
      },
    }
    local decoded = yamlcamel.decode(yamlcamel.encode(input))
    assert.is_true(decoded.enabled)
    assert.are.equal(5, decoded.config.limit)
    assert.are.equal("needs: quoting, and a # too", decoded.config.label)
    assert.is_false(decoded.config.strict)
    assert.are.same({ "one", "two", "three" }, decoded.config.tags)
  end)

  it("preserves a list of records, the room list shape", function()
    local input = {
      { room_key = "general", label = "General", channels = { "tg-general" } },
      { room_key = "off-topic", label = yamlcamel.null, channels = {} },
    }
    local decoded = yamlcamel.decode(yamlcamel.encode(input))
    assert.are.equal(2, #decoded)
    assert.are.equal("general", decoded[1].room_key)
    assert.are.same({ "tg-general" }, decoded[1].channels)
    assert.is_true(yamlcamel.is_null(decoded[2].label))
  end)

  it("preserves numbers, including a value that looks like a leading-zero string", function()
    local input = { count = 42, ratio = 3.5, code = "007" }
    local decoded = yamlcamel.decode(yamlcamel.encode(input))
    assert.are.equal(42, decoded.count)
    assert.are.equal(3.5, decoded.ratio)
    assert.are.equal("007", decoded.code)
  end)

  it("preserves an explicit null distinctly from an empty string", function()
    local input = { a = yamlcamel.null, b = "" }
    local decoded = yamlcamel.decode(yamlcamel.encode(input))
    assert.is_true(yamlcamel.is_null(decoded.a))
    assert.are.equal("", decoded.b)
  end)

  it("preserves an infinite or NaN float", function()
    local decoded = yamlcamel.decode(yamlcamel.encode({ up = math.huge, down = -math.huge }))
    assert.are.equal(math.huge, decoded.up)
    assert.are.equal(-math.huge, decoded.down)
    local nan = yamlcamel.decode(yamlcamel.encode(0 / 0))
    assert.is_true(nan ~= nan)
  end)
end)

describe("yamlcamel.decode_file and yamlcamel.encode_file", function()
  it("round-trips a value through a real file", function()
    local path = os.tmpname()
    yamlcamel.encode_file(path, { name = "test", count = 3 })
    local decoded = yamlcamel.decode_file(path)
    os.remove(path)
    assert.are.equal("test", decoded.name)
    assert.are.equal(3, decoded.count)
  end)

  it("raises when the file cannot be opened for reading", function()
    assert.has_error(function() yamlcamel.decode_file("/nonexistent/path/for/sure.yaml") end)
  end)

  it("uses an injected file implementation instead of the default", function()
    local store = {}
    local fake_file = {
      read = function(path) return store[path] end,
      write = function(path, content) store[path] = content; return true end,
    }
    yamlcamel.encode_file("virtual.yaml", { count = 7 }, { file = fake_file })
    assert.is_truthy(store["virtual.yaml"])
    local decoded = yamlcamel.decode_file("virtual.yaml", { file = fake_file })
    assert.are.equal(7, decoded.count)
  end)
end)
