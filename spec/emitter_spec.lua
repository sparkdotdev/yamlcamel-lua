local yamlcamel = require("yamlcamel")

describe("yamlcamel.encode scalars", function()
  it("encodes null, booleans and numbers", function()
    assert.are.equal("--- null\n", yamlcamel.encode(yamlcamel.null))
    assert.are.equal("--- null\n", yamlcamel.encode(nil))
    assert.are.equal("--- true\n", yamlcamel.encode(true))
    assert.are.equal("--- 42\n", yamlcamel.encode(42))
  end)

  it("encodes a plain string bare", function()
    assert.are.equal("--- hello\n", yamlcamel.encode("hello"))
  end)

  it("quotes a string that would otherwise resolve as another type", function()
    assert.are.equal("--- 'true'\n", yamlcamel.encode("true"))
    assert.are.equal("--- '42'\n", yamlcamel.encode("42"))
    assert.are.equal("--- ''\n", yamlcamel.encode(""))
  end)

  it("quotes a string carrying a colon-space, which would otherwise read as a key", function()
    assert.are.equal("--- 'needs: quoting'\n", yamlcamel.encode("needs: quoting"))
  end)

  it("double-quotes and escapes a string with a control character", function()
    assert.are.equal('--- "a\\nb"\n', yamlcamel.encode("a\nb"))
  end)

  it("rejects a value this subset cannot represent", function()
    assert.has_error(function() yamlcamel.encode(print) end)
  end)
end)

describe("yamlcamel.encode collections", function()
  it("encodes an empty table as an empty sequence by default", function()
    assert.are.equal("--- []\n", yamlcamel.encode({}))
  end)

  it("encodes yamlcamel.EMPTY_MAPPING as an empty mapping", function()
    assert.are.equal("--- {}\n", yamlcamel.encode(yamlcamel.EMPTY_MAPPING))
  end)

  it("encodes a flat sequence", function()
    assert.are.equal("---\n- a\n- b\n- c\n", yamlcamel.encode({ "a", "b", "c" }))
  end)

  it("encodes a flat mapping with keys sorted for a stable diff", function()
    assert.are.equal("---\na: 1\nb: 2\n", yamlcamel.encode({ b = 2, a = 1 }))
  end)

  it("encodes a nested mapping under a sequence item", function()
    local text = yamlcamel.encode({ { id = 1, body = "hi" } })
    assert.are.equal("---\n-\n  body: hi\n  id: 1\n", text)
  end)
end)
