local yamlcamel = require("yamlcamel")

-- Psych's own `YAML.dump` always indents a moved-down scalar value deeper
-- than the key that introduces it, which is the shape parser_spec.lua's
-- own "moved to its own more-indented line" tests already cover. Real
-- YAML additionally allows a scalar's later lines to sit at the SAME
-- indentation as its own first line, not only deeper; that's what these
-- cover, alongside the cases that have to keep raising instead of folding.
describe("yamlcamel.decode plain scalar folding at the same indentation", function()
  it("folds a value moved to its own line across same-indentation continuations", function()
    local v = yamlcamel.decode("key:\n  first line\n  second line\n")
    assert.are.equal("first line second line", v.key)
  end)

  it("folds three or more same-indentation continuation lines", function()
    local v = yamlcamel.decode("key:\n  a b\n  c d\n  e f\n")
    assert.are.equal("a b c d e f", v.key)
  end)

  it("folds a root-level bare scalar across same-indentation lines", function()
    local v = yamlcamel.decode("first line\nsecond line\n")
    assert.are.equal("first line second line", v)
  end)

  it("folds a sequence item's own-line value across same-indentation lines", function()
    local v = yamlcamel.decode("-\n  first line\n  second line\n")
    assert.are.equal("first line second line", v[1])
  end)

  it("stops folding at a genuine sibling key back at the enclosing indentation", function()
    local v = yamlcamel.decode("outer:\n  key1:\n    first line\n    second line\n  key2: value2\n")
    assert.are.equal("first line second line", v.outer.key1)
    assert.are.equal("value2", v.outer.key2)
  end)

  it("stops folding at a blank line", function()
    local v = yamlcamel.decode("key:\n  first line\n  second line\n\nnext: ok\n")
    assert.are.equal("first line second line", v.key)
    assert.are.equal("ok", v.next)
  end)

  it("still folds the Psych deeper-indentation style unchanged", function()
    local v = yamlcamel.decode("key: first line\n  second line\n")
    assert.are.equal("first line second line", v.key)
  end)

  it("still folds a wrapped inline value at the same indentation as its own first continuation", function()
    local v = yamlcamel.decode("key: first line\n  second line\n  third line\n")
    assert.are.equal("first line second line third line", v.key)
  end)

  it("raises rather than folding when a comment interrupts the scalar's own line", function()
    -- 6.9: a comment ends whatever precedes it for good; nothing folds
    -- onward from a commented line even at the same indentation.
    assert.has_error(function() yamlcamel.decode("word1  # comment\nword2\n") end)
  end)

  it("raises rather than folding a same-indentation line shaped like a new mapping entry", function()
    assert.has_error(function() yamlcamel.decode("key:\n  word1 word2\n  no: key\n") end)
  end)

  it("raises rather than folding a same-indentation line shaped like a sequence item", function()
    assert.has_error(function() yamlcamel.decode("key:\n  word1 word2\n  - item\n") end)
  end)

  it("does not swallow a document marker as same-indentation continuation", function()
    local docs = yamlcamel.decode_all("Document\n---\nnext: doc\n")
    assert.are.equal(2, #docs)
    assert.are.equal("Document", docs[1])
    assert.are.equal("doc", docs[2].next)
  end)

  it("does not swallow a directive as same-indentation continuation", function()
    local docs = yamlcamel.decode_all("first\n%YAML 1.2\n---\nsecond\n")
    assert.are.equal(2, #docs)
    assert.are.equal("first", docs[1])
    assert.are.equal("second", docs[2])
  end)
end)
