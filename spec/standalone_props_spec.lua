local yamlcamel = require("yamlcamel")

describe("yamlcamel.decode a node property standing alone before a collection", function()
  it("reads a root-level anchor standing alone before a sequence", function()
    local v = yamlcamel.decode("&s\n- a\n- b\n")
    assert.are.same({ "a", "b" }, v)
  end)

  it("reads a root-level anchor standing alone before a mapping", function()
    local v = yamlcamel.decode("&m\na: 1\nb: 2\n")
    assert.are.equal(1, v.a)
    assert.are.equal(2, v.b)
  end)

  it("resolves an alias to a sequence anchored this way", function()
    local v = yamlcamel.decode("key:\n  &a\n  - one\n  - two\nref: *a\n")
    assert.are.same({ "one", "two" }, v.key)
    assert.are.equal(v.key, v.ref)
  end)

  it("resolves an alias to a mapping anchored this way", function()
    local v = yamlcamel.decode("key:\n  &a\n  x: 1\n  y: 2\nref: *a\n")
    assert.are.equal(1, v.key.x)
    assert.are.equal(v.key, v.ref)
  end)

  it("supports a self-reference through an anchor standing alone before a mapping", function()
    local v = yamlcamel.decode("key:\n  &a\n  self: *a\n")
    assert.are.equal(v.key, v.key.self)
  end)

  it("reads a sequence anchored this way as a sequence item's own value", function()
    local v = yamlcamel.decode("list:\n-\n  &a\n  - one\n  - two\nother: *a\n")
    assert.are.same({ "one", "two" }, v.list[1])
    assert.are.equal(v.list[1], v.other)
  end)

  it("reads a mapping anchored this way as a sequence item's own value", function()
    local v = yamlcamel.decode("list:\n-\n  &a\n  x: 1\nother: *a\n")
    assert.are.equal(1, v.list[1].x)
    assert.are.equal(v.list[1], v.other)
  end)

  it("reads a mapping anchored this way that uses an explicit key entry", function()
    local v = yamlcamel.decode("key:\n  &a\n  ? k\n  : 1\nref: *a\n")
    assert.are.equal(1, v.key.k)
    assert.are.equal(v.key, v.ref)
  end)

  it("forces the core schema map type on a mapping tagged this way", function()
    local v = yamlcamel.decode("key:\n  !!map\n  a: 1\nnext: ok\n")
    assert.are.equal(1, v.key.a)
    assert.are.equal("ok", v.next)
  end)

  it("wraps a mapping tagged this way with a custom tag", function()
    local v = yamlcamel.decode("key:\n  !Point\n  x: 1\n  y: 2\n")
    assert.is_true(yamlcamel.is_tagged(v.key))
    assert.are.equal("!Point", v.key.tag)
    assert.are.equal(1, v.key.value.x)
  end)

  it("still errors when the property sits at the SAME indentation as its key, not nested under it", function()
    -- The Psych same-indentation quirk only ever applies to a sequence's
    -- own dashes, never to a property line standing in for one; a
    -- property this shallow is a malformed sibling, not this key's value.
    assert.has_error(function() yamlcamel.decode("---\nseq:\n&anchor\n- a\n- b\n") end)
  end)

  it("still errors when nothing recognizable as a collection follows the property", function()
    assert.has_error(function() yamlcamel.decode("key: &x\n!!map\n  a: b\n") end)
  end)

  it("still errors on an anchor standing alone before a plain scalar (out of scope, collections only)", function()
    assert.has_error(function() yamlcamel.decode("key:\n  &a\n  plain value\n") end)
  end)
end)
