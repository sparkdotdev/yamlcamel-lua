local yaml = require("yamlcamel")

describe("null mapping keys", function()
  for _, text in ipairs({ "?\n: value\n", ": value\n", "null: value\n", "{null: value}\n" }) do
    it("preserves null as a distinct key across an encode/decode round trip", function()
      local first = yaml.decode(text)
      assert.are.equal("value", first[yaml.null])
      local second = yaml.decode(yaml.encode(first))
      assert.are.equal("value", second[yaml.null])
      assert.is_nil(second["yaml.null"])
    end)
  end
end)
