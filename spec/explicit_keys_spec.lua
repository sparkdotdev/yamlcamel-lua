local yamlcamel = require("yamlcamel")

describe("yamlcamel.decode explicit mapping keys (? key / : value)", function()
  it("reads a single inline explicit entry", function()
    local v = yamlcamel.decode("? explicit key\n: explicit value\n")
    assert.are.equal("explicit value", v["explicit key"])
  end)

  it("reads an explicit entry mixed with ordinary ones in the same mapping", function()
    local v = yamlcamel.decode("a: 4.2\n? d\n: 23\nz: last\n")
    assert.are.equal(4.2, v.a)
    assert.are.equal(23, v.d)
    assert.are.equal("last", v.z)
  end)

  it("resolves an explicit key with no ': value' line to null, same as a bare 'key:'", function()
    local v = yamlcamel.decode("? onlykey\n")
    assert.is_true(yamlcamel.is_null(v.onlykey))
  end)

  it("moves on to the next entry when an explicit key isn't followed by its ':' line", function()
    local v = yamlcamel.decode("? a\n? b\nc: value\n")
    assert.is_true(yamlcamel.is_null(v.a))
    assert.is_true(yamlcamel.is_null(v.b))
    assert.are.equal("value", v.c)
  end)

  it("reads a whole document that is a single root-level explicit entry", function()
    local v = yamlcamel.decode("? onlykey\n: onlyvalue\n")
    assert.are.equal("onlyvalue", v.onlykey)
  end)

  it("reads explicit entries nested under an ordinary key", function()
    local v = yamlcamel.decode("outer:\n  ? k1\n  : v1\n  ? k2\n  : v2\n")
    assert.are.equal("v1", v.outer.k1)
    assert.are.equal("v2", v.outer.k2)
  end)

  it("reads the compact dash form, an explicit entry as a sequence item", function()
    local v = yamlcamel.decode("- ? key\n  : value\n")
    assert.are.equal("value", v[1].key)
  end)

  it("reads a nested block mapping as an explicit value, on its own more-indented lines", function()
    local v = yamlcamel.decode("? key\n:\n  a: 1\n  b: 2\n")
    assert.are.equal(1, v.key.a)
    assert.are.equal(2, v.key.b)
  end)

  it("reads a nested block mapping as an explicit key, on its own more-indented lines", function()
    local v = yamlcamel.decode("?\n  a: 1\n  b: 2\n: value\n")
    local found
    for k, val in pairs(v) do
      found = k
      assert.are.equal("value", val)
    end
    assert.is_not_nil(found)
  end)

  it("resolves an anchor attached to explicit key text and reads it back through an alias", function()
    local v = yamlcamel.decode("? &k key\n: value\nref: *k\n")
    assert.are.equal("value", v.key)
    assert.are.equal("key", v.ref)
  end)

  it("folds explicit key text Psych-style wrapped across more-indented lines", function()
    local v = yamlcamel.decode("? this is a long key that\n  wraps across lines\n: value\n")
    assert.are.equal("value", v["this is a long key that wraps across lines"])
  end)

  it("folds explicit value text Psych-style wrapped across more-indented lines", function()
    local v = yamlcamel.decode("? key\n: this is a long value that\n  wraps across lines\n")
    assert.are.equal("this is a long value that wraps across lines", v.key)
  end)

  it("reads the compact 'explicit key : - item' sequence form on the marker's own line", function()
    local v = yamlcamel.decode("? |\n  block key\n: - one\n  - two\n")
    assert.are.same({ "one", "two" }, v["block key\n"])
  end)

  it("reads a block scalar as the explicit key itself", function()
    local v = yamlcamel.decode("? |\n  block key\n: plain value\n")
    assert.are.equal("plain value", v["block key\n"])
  end)

  it("reads a flow collection as an inline explicit value", function()
    local v = yamlcamel.decode("? key\n: [1, 2, 3]\n")
    assert.are.same({ 1, 2, 3 }, v.key)
  end)

  it("reads consecutive explicit entries with no ordinary entries at all", function()
    local v = yamlcamel.decode("? a\n: 1\n? b\n: 2\n? c\n: 3\n")
    assert.are.equal(1, v.a)
    assert.are.equal(2, v.b)
    assert.are.equal(3, v.c)
  end)

  it("opens a mapping under a null key from a ':' line with no '? key' ahead of it", function()
    local v = yamlcamel.decode(": x\n")
    assert.are.equal("x", v[yamlcamel.null])
  end)

  it("resolves a null-keyed entry with nothing after the ':' to null", function()
    local v = yamlcamel.decode(":\n")
    assert.is_true(yamlcamel.is_null(v[yamlcamel.null]))
  end)

  it("reads the compact dash form of a null-keyed entry without eating the next item", function()
    local v = yamlcamel.decode("- : x\n- z\n")
    assert.are.equal(2, #v)
    assert.are.equal("x", v[1][yamlcamel.null])
    assert.are.equal("z", v[2])
  end)

  it("keeps reading a compact null-keyed entry's siblings and the items after it", function()
    local v = yamlcamel.decode("- : x\n  e: y\n- z\n")
    assert.are.equal(2, #v)
    assert.are.equal("x", v[1][yamlcamel.null])
    assert.are.equal("y", v[1].e)
    assert.are.equal("z", v[2])
  end)

  it("reads a null-keyed entry that opens a nested mapping under an ordinary key", function()
    local v = yamlcamel.decode("a:\n  : x\n  e: y\n")
    assert.are.equal("x", v.a[yamlcamel.null])
    assert.are.equal("y", v.a.e)
  end)

  it("resolves a block scalar opened on a null-keyed entry's own ':' line", function()
    local v = yamlcamel.decode("- : |\n   e: x\n- y\n")
    assert.are.equal(2, #v)
    assert.are.equal("e: x\n", v[1][yamlcamel.null])
    assert.are.equal("y", v[2])
  end)

  it("raises when a ':' line dedents past its explicit key's own mapping", function()
    -- The ":" belongs to "? a" only at the SAME indentation; one that
    -- dedents back to the root isn't a value line at all here, and a bare
    -- ":" is never a mapping entry on its own.
    assert.has_error(function() yamlcamel.decode("outer:\n  ? a\n: 1\n") end)
  end)
end)
