local yamlcamel = require("yamlcamel")

describe("yamlcamel.decode anchors and aliases", function()
  it("resolves an alias to an anchored scalar mapping value", function()
    local v = yamlcamel.decode("base: &b tg-general\nother: *b\n")
    assert.are.equal("tg-general", v.base)
    assert.are.equal("tg-general", v.other)
  end)

  it("resolves an alias to an anchored root-level scalar", function()
    local v = yamlcamel.decode("- &b hello\n- *b\n")
    assert.are.equal("hello", v[1])
    assert.are.equal("hello", v[2])
  end)

  it("resolves an alias to an anchored nested mapping, as the same table", function()
    local v = yamlcamel.decode("defaults: &d\n  timeout: 30\n  retries: 3\nsame: *d\n")
    assert.are.equal(30, v.defaults.timeout)
    assert.are.equal(3, v.same.retries)
    assert.are.equal(v.defaults, v.same)
  end)

  it("resolves an alias to an anchored nested sequence", function()
    local v = yamlcamel.decode("channels: &c\n  - tg-general\n  - dc-general\nmirror: *c\n")
    assert.are.same({ "tg-general", "dc-general" }, v.mirror)
    assert.are.equal(v.channels, v.mirror)
  end)

  it("resolves an alias to an anchored sequence item's compact mapping", function()
    local v = yamlcamel.decode("rooms:\n- &r\n  key: general\n  label: General\nfeatured: *r\n")
    assert.are.equal("general", v.featured.key)
    assert.are.equal(v.rooms[1], v.featured)
  end)

  it("anchors a compact mapping written on the dash's own line", function()
    -- "- &a key: value" anchors the {key = value} record itself, not a
    -- key literally named "&a key".
    local v = yamlcamel.decode("rooms:\n- &r key: general\nfeatured: *r\n")
    assert.are.equal("general", v.rooms[1].key)
    assert.are.equal(v.rooms[1], v.featured)
  end)

  it("resolves an alias to an anchored block scalar", function()
    local v = yamlcamel.decode("body: &b |\n  hello\n  world\nsame: *b\n")
    assert.are.equal("hello\nworld\n", v.body)
    assert.are.equal("hello\nworld\n", v.same)
  end)

  it("resolves an alias to an anchored flow sequence, from block style", function()
    local v = yamlcamel.decode("tags: &t [one, two]\nsame: *t\n")
    assert.are.same({ "one", "two" }, v.same)
    assert.are.equal(v.tags, v.same)
  end)

  it("resolves an alias to a block-defined anchor from inside a flow collection", function()
    local v = yamlcamel.decode("tags: &t [one, two]\nref: [*t, done]\n")
    assert.are.same({ { "one", "two" }, "done" }, v.ref)
    assert.are.equal(v.tags, v.ref[1])
  end)

  -- Anchors have to compose with the Psych line-wrap fix (PR #10) and the
  -- block-scalar sentinel mechanism landed before this feature existed.
  it("anchors a plain scalar that Psych wrapped across physical lines", function()
    local doc = table.concat({
      "body: &b Hey everyone, just a heads up that the event starts tonight,",
      "  don't be late!",
      "same: *b",
    }, "\n")
    local v = yamlcamel.decode(doc)
    assert.are.equal("Hey everyone, just a heads up that the event starts tonight, don't be late!", v.body)
    assert.are.equal(v.body, v.same)
  end)

  it("anchors a double-quoted scalar that wrapped across physical lines", function()
    local doc = table.concat({
      "body: &b \"This is a longer message. And has punctuation: commas,",
      "  periods. Final line.\"",
      "same: *b",
    }, "\n")
    local v = yamlcamel.decode(doc)
    assert.are.equal("This is a longer message. And has punctuation: commas, periods. Final line.", v.body)
    assert.are.equal(v.body, v.same)
  end)

  it("resolves an anchor and alias both written inside a flow collection", function()
    local v = yamlcamel.decode("--- [&x 1, *x, *x]")
    assert.are.same({ 1, 1, 1 }, v)
  end)

  it("resolves an alias to an anchored flow mapping", function()
    local v = yamlcamel.decode("--- {base: &b {a: 1}, same: *b}")
    assert.are.equal(1, v.same.a)
    assert.are.equal(v.base, v.same)
  end)

  it("resolves an alias used as a flow mapping key", function()
    local v = yamlcamel.decode("--- {&k a: 1, *k: 2}")
    assert.are.equal(2, v.a)
  end)

  it("registers a null value for an anchor with nothing after it", function()
    local v = yamlcamel.decode("first: &n\nsecond: *n\n")
    assert.is_true(yamlcamel.is_null(v.first))
    assert.is_true(yamlcamel.is_null(v.second))
  end)

  it("lets a later anchor with the same name shadow an earlier one", function()
    local v = yamlcamel.decode("a: &x one\nb: *x\nc: &x two\nd: *x\n")
    assert.are.equal("one", v.b)
    assert.are.equal("two", v.d)
  end)

  it("raises on an alias to an anchor that was never defined", function()
    assert.has_error(function() yamlcamel.decode("--- *missing") end)
  end)

  it("raises when an alias also carries its own anchor", function()
    -- 6.9.2: an alias node is a pure reference, it can't itself be
    -- anchored under a new name at the same time.
    assert.has_error(function() yamlcamel.decode("key1: &a value\nkey2: &b *a\n") end)
  end)

  it("raises when an alias also carries a tag, in flow style", function()
    assert.has_error(function() yamlcamel.decode("--- {a: &x 1, b: [!!str *x]}") end)
  end)

  it("supports a self-referencing (cyclic) anchor", function()
    local v = yamlcamel.decode("a: &x\n  self: *x\n")
    assert.are.equal(v.a, v.a.self)
  end)

  it("keeps anchors from one decode call out of the next", function()
    yamlcamel.decode("a: &x one\n")
    assert.has_error(function() yamlcamel.decode("--- *x") end)
  end)
end)

describe("yamlcamel.encode a cyclic decoded structure", function()
  it("raises instead of recursing forever", function()
    local v = yamlcamel.decode("a: &x\n  self: *x\n")
    assert.has_error(function() yamlcamel.encode(v) end)
  end)
end)
