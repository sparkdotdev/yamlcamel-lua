local yamlcamel = require("yamlcamel")

describe("yamlcamel.decode scalars", function()
  it("resolves null spellings", function()
    for _, text in ipairs({ "--- null", "--- Null", "--- NULL", "--- ~" }) do
      assert.is_true(yamlcamel.is_null(yamlcamel.decode(text)))
    end
  end)

  it("resolves booleans", function()
    assert.is_true(yamlcamel.decode("--- true"))
    assert.is_true(yamlcamel.decode("--- True"))
    assert.is_false(yamlcamel.decode("--- false"))
    assert.is_false(yamlcamel.decode("--- FALSE"))
  end)

  it("resolves integers and floats", function()
    assert.are.equal(42, yamlcamel.decode("--- 42"))
    assert.are.equal(-7, yamlcamel.decode("--- -7"))
    assert.are.equal(3.5, yamlcamel.decode("--- 3.5"))
    assert.are.equal(1500.0, yamlcamel.decode("--- 1.5e3"))
  end)

  it("resolves a leading-zero decimal as the plain number, per the 1.2 core schema", function()
    -- 10.3.2: the base-10 int regex has no exception for a leading zero.
    -- 1.2 moved octal to the 0o prefix specifically so this is unambiguous.
    assert.are.equal(7, yamlcamel.decode("--- 007"))
    assert.are.equal(10, yamlcamel.decode("--- 010"))
  end)

  it("resolves octal (0o) and hex (0x) integers", function()
    assert.are.equal(7, yamlcamel.decode("--- 0o7"))
    assert.are.equal(58, yamlcamel.decode("--- 0x3A"))
  end)

  it("leaves a signed octal or hex literal as a string, matching the spec grammar", function()
    -- 10.3.2 gives 0o and 0x no [-+]? in front, unlike the base-10 form.
    assert.are.equal("-0x3A", yamlcamel.decode("--- -0x3A"))
    assert.are.equal("+0o7", yamlcamel.decode("--- +0o7"))
  end)

  it("reads plain, single- and double-quoted strings", function()
    assert.are.equal("hello world", yamlcamel.decode("--- hello world"))
    assert.are.equal("it's fine", yamlcamel.decode([[--- 'it''s fine']]))
    assert.are.equal('a "quote" here', yamlcamel.decode([[--- "a \"quote\" here"]]))
  end)

  it("decodes double-quoted escapes", function()
    assert.are.equal("line one\nline two", yamlcamel.decode([[--- "line one\nline two"]]))
    assert.are.equal("a\tb", yamlcamel.decode([[--- "a\tb"]]))
  end)

  it("elides a backslash line continuation in a double-quoted scalar", function()
    local v = yamlcamel.decode([[
body: "some very long text that needs \
  continuation"
]])
    assert.are.equal("some very long text that needs continuation", v.body)
  end)

  it("still folds the remaining breaks after an elided continuation", function()
    local v = yamlcamel.decode([[
body: "one\


  two"
]])
    assert.are.equal("one\ntwo", v.body)
  end)

  it("resolves an empty document to null", function()
    assert.is_true(yamlcamel.is_null(yamlcamel.decode("")))
    assert.is_true(yamlcamel.is_null(yamlcamel.decode("   \n# just a comment\n")))
  end)
end)

describe("yamlcamel.decode block mappings", function()
  it("reads a flat mapping", function()
    local doc = "---\nslug: acme\nname: Acme\nstatus: active\n"
    local v = yamlcamel.decode(doc)
    assert.are.equal("acme", v.slug)
    assert.are.equal("Acme", v.name)
    assert.are.equal("active", v.status)
  end)

  it("reads a nested mapping", function()
    local doc = "---\nfeature: word_filter\nconfig:\n  limit: 5\n  strict: true\n"
    local v = yamlcamel.decode(doc)
    assert.are.equal("word_filter", v.feature)
    assert.are.equal(5, v.config.limit)
    assert.is_true(v.config.strict)
  end)

  it("reads a null value left blank after the colon", function()
    local v = yamlcamel.decode("---\nlabel:\n")
    assert.is_true(yamlcamel.is_null(v.label))
  end)

  it("reads a plain scalar value moved to its own more-indented line", function()
    -- Spec Example 6.9: a value doesn't have to stay inline after "key:";
    -- an ordinary plain scalar can move to the next line same as a block
    -- scalar can, with nothing marking it beyond the extra indentation.
    local v = yamlcamel.decode("key:    # Comment\n  value\n")
    assert.are.equal("value", v.key)
  end)

  it("reads a quoted scalar value moved to its own more-indented line", function()
    local v = yamlcamel.decode('key:\n  "value"\nnext: ok\n')
    assert.are.equal("value", v.key)
    assert.are.equal("ok", v.next)
  end)

  it("reads a moved-down scalar value as a sequence item", function()
    local v = yamlcamel.decode("- key:\n    value\n")
    assert.are.equal("value", v[1].key)
  end)

  it("raises when something follows a moved-down scalar value at the same depth", function()
    assert.has_error(function() yamlcamel.decode("key:\n  word1 word2\n  no: key\n") end)
  end)

  it("reads an unquoted key carrying an apostrophe", function()
    local v = yamlcamel.decode("don't panic: value\n")
    assert.are.equal("value", v["don't panic"])
  end)
end)

describe("yamlcamel.decode block sequences", function()
  it("reads a sequence indented deeper than its key, the ordinary style", function()
    local doc = "---\nchannels:\n  - tg-general\n  - dc-general\n"
    local v = yamlcamel.decode(doc)
    assert.are.equal(2, #v.channels)
    assert.are.equal("tg-general", v.channels[1])
  end)

  it("reads a sequence at the SAME indentation as its key, Psych's own style", function()
    local doc = "---\nchannels:\n- tg-general\n- dc-general\n"
    local v = yamlcamel.decode(doc)
    assert.are.equal(2, #v.channels)
    assert.are.equal("dc-general", v.channels[2])
  end)

  it("reads a sequence of mappings written with the compact dash form", function()
    local doc = table.concat({
      "---",
      "messages:",
      "- id: 1",
      "  origin: tg-general",
      '  body: "hi there: cool"',
      "  kind: chat",
      "- id: 2",
      "  origin: null",
      "  body: second",
      "  kind: chat",
    }, "\n")
    local v = yamlcamel.decode(doc)
    assert.are.equal(2, #v.messages)
    assert.are.equal(1, v.messages[1].id)
    assert.are.equal("hi there: cool", v.messages[1].body)
    assert.is_true(yamlcamel.is_null(v.messages[2].origin))
    assert.are.equal("second", v.messages[2].body)
  end)

  it("reads a root-level sequence", function()
    local v = yamlcamel.decode("---\n- one\n- two\n- three\n")
    assert.are.same({ "one", "two", "three" }, v)
  end)
end)

describe("yamlcamel.decode flow style", function()
  it("reads a flow sequence", function()
    assert.are.same({ 1, 2, 3 }, yamlcamel.decode("--- [1, 2, 3]"))
  end)

  it("reads a flow mapping", function()
    local v = yamlcamel.decode("--- {a: 1, b: true}")
    assert.are.equal(1, v.a)
    assert.is_true(v.b)
  end)

  it("reads flow collections nested inside each other", function()
    local v = yamlcamel.decode("--- {list: [1, 2, {x: 1}], flag: false}")
    assert.are.equal(2, v.list[2])
    assert.are.equal(1, v.list[3].x)
    assert.is_false(v.flag)
  end)

  it("reads a flow mapping key with no colon at all as an implicit null value", function()
    local v = yamlcamel.decode("--- {single line, a: b}")
    assert.is_true(yamlcamel.is_null(v["single line"]))
    assert.are.equal("b", v.a)
  end)

  -- 7.4.3, ns-flow-pair: a single "key: value" pair standing directly
  -- inside a flow sequence (no braces of its own) is one element holding
  -- a one-entry mapping, not two separate elements.
  it("reads a single-pair implicit entry (plain key) inside a flow sequence", function()
    local v = yamlcamel.decode("--- [ YAML : separate ]")
    assert.are.equal("separate", v[1].YAML)
  end)

  it("reads a single-pair implicit entry (quoted key) inside a flow sequence", function()
    local v = yamlcamel.decode('--- [ "JSON like":adjacent ]')
    assert.are.equal("adjacent", v[1]["JSON like"])
  end)

  it("does not split an ordinary plain scalar containing a bare colon", function()
    -- No space (or flow terminator) after the ':', so it stays literal
    -- content rather than being read as a key separator.
    local v = yamlcamel.decode("--- [http://example.com, b]")
    assert.are.equal("http://example.com", v[1])
    assert.are.equal("b", v[2])
  end)

  it("reads a flow collection as a mapping value on its own line", function()
    local v = yamlcamel.decode("---\nconfig: {a: 1, b: [1, 2]}\n")
    assert.are.equal(1, v.config.a)
    assert.are.same({ 1, 2 }, v.config.b)
  end)
end)

describe("yamlcamel.decode comments", function()
  it("strips a trailing comment outside quotes", function()
    local v = yamlcamel.decode("---\nname: Acme # the display name\n")
    assert.are.equal("Acme", v.name)
  end)

  it("keeps a hash character inside a quoted scalar", function()
    local v = yamlcamel.decode([[--- "room #1"]])
    assert.are.equal("room #1", v)
  end)
end)

describe("yamlcamel.decode error handling", function()
  it("raises on an unterminated flow sequence", function()
    assert.has_error(function() yamlcamel.decode("--- [1, 2") end)
  end)

  it("raises on an unterminated double-quoted scalar", function()
    assert.has_error(function() yamlcamel.decode('--- "unterminated') end)
  end)

  it("raises on a tab used for indentation", function()
    assert.has_error(function() yamlcamel.decode("---\na:\n\t- x\n") end)
  end)
end)

-- 1.2's core schema bool regex (10.3.2) is exactly
-- true|True|TRUE|false|False|FALSE. yes/no/on/off are YAML 1.1 words this
-- library used to accept (#5); reading them as booleans instead of strings
-- is exactly the Psych "Norway problem" (Psych.load('NO: yes') on current
-- stable Ruby returns {false=>true}), and this library needs to not have
-- that bug regardless of what the Ruby side does.
describe("yamlcamel.decode YAML 1.1 boolean spellings are plain strings under 1.2", function()
  it("leaves yes/no as strings", function()
    assert.are.equal("yes", yamlcamel.decode("--- yes"))
    assert.are.equal("no", yamlcamel.decode("--- no"))
  end)

  it("leaves on/off as strings in a mapping value", function()
    local v = yamlcamel.decode("enabled: on\nstrict: Off\n")
    assert.are.equal("on", v.enabled)
    assert.are.equal("Off", v.strict)
  end)

  it("still resolves true/false in every listed capitalization", function()
    assert.is_true(yamlcamel.decode("--- true"))
    assert.is_true(yamlcamel.decode("--- True"))
    assert.is_true(yamlcamel.decode("--- TRUE"))
    assert.is_false(yamlcamel.decode("--- false"))
    assert.is_false(yamlcamel.decode("--- False"))
    assert.is_false(yamlcamel.decode("--- FALSE"))
  end)
end)

describe("yamlcamel.decode special float spellings", function()
  it("resolves .inf and -.inf", function()
    assert.are.equal(math.huge, yamlcamel.decode("--- .inf"))
    assert.are.equal(-math.huge, yamlcamel.decode("--- -.inf"))
  end)

  it("resolves .nan", function()
    local n = yamlcamel.decode("--- .nan")
    assert.is_true(n ~= n)
  end)
end)

describe("yamlcamel.decode block scalars", function()
  it("reads a literal block with clip chomping", function()
    local v = yamlcamel.decode("body: |\n  line one\n  line two\n")
    assert.are.equal("line one\nline two\n", v.body)
  end)

  it("reads a literal block with strip chomping", function()
    local v = yamlcamel.decode("body: |-\n  line one\n  line two\n")
    assert.are.equal("line one\nline two", v.body)
  end)

  it("reads a literal block with keep chomping", function()
    local v = yamlcamel.decode("body: |+\n  line one\n\n\nnext: ok\n")
    assert.are.equal("line one\n\n\n", v.body)
    assert.are.equal("ok", v.next)
  end)

  it("folds a folded block's line breaks into spaces", function()
    local v = yamlcamel.decode("body: >\n  line one\n  line two\n")
    assert.are.equal("line one line two\n", v.body)
  end)

  it("keeps a blank line inside a folded block as a literal break", function()
    local v = yamlcamel.decode("body: >\n  line one\n\n  line two\n")
    assert.are.equal("line one\nline two\n", v.body)
  end)

  it("keeps a more-indented line inside a folded block literal", function()
    local v = yamlcamel.decode("body: >\n  normal line\n    indented line\n  normal line\n")
    assert.are.equal("normal line\n  indented line\nnormal line\n", v.body)
  end)

  it("keeps consecutive more-indented lines each on their own break", function()
    local v = yamlcamel.decode("body: >\n  normal line\n    indented one\n    indented two\n  normal line\n")
    assert.are.equal("normal line\n  indented one\n  indented two\nnormal line\n", v.body)
  end)

  it("reads a block scalar as a sequence item", function()
    local v = yamlcamel.decode("items:\n  - |\n    first\n  - second\n")
    assert.are.equal("first\n", v.items[1])
    assert.are.equal("second", v.items[2])
  end)

  it("reads a block scalar nested inside a sequence item's mapping", function()
    local v = yamlcamel.decode("items:\n  - name: a\n    text: |\n      hello\n      world\n  - name: b\n")
    assert.are.equal("hello\nworld\n", v.items[1].text)
    assert.are.equal("b", v.items[2].name)
  end)

  it("reads two block scalars back to back under different keys", function()
    local v = yamlcamel.decode("a: |\n  x\nb: |\n  y\n")
    assert.are.equal("x\n", v.a)
    assert.are.equal("y\n", v.b)
  end)

  it("reads a whole document that is directly a block scalar, with no key or dash", function()
    local v = yamlcamel.decode("|\n  hello\n  world\n")
    assert.are.equal("hello\nworld\n", v)
  end)

  it("ends a compact sequence entry's block scalar at the key's column, not the dash's", function()
    -- The dash sits at column 0 here but "a" sits at column 2, and this
    -- mapping's other entries line up with "a". "e: x" is therefore a
    -- sibling key, which the block used to swallow as its own content.
    local v = yamlcamel.decode("- a: |\n  e: x\n- y\n")
    assert.are.equal("", v[1].a)
    assert.are.equal("x", v[1].e)
    assert.are.equal("y", v[2])
  end)

  it("still reads a compact sequence entry's block scalar content past that column", function()
    local v = yamlcamel.decode("- a: |\n    first\n    second\n- y\n")
    assert.are.equal("first\nsecond\n", v[1].a)
    assert.are.equal("y", v[2])
  end)

  it("counts an explicit indentation indicator from the key's column too", function()
    -- 8.1.1.1: the indicator is relative to the parent node, which here is
    -- the mapping "a" opens at column 2, so the content starts at column 4.
    local v = yamlcamel.decode("- a: |2\n    x\n  e: q\n")
    assert.are.equal("x\n", v[1].a)
    assert.are.equal("q", v[1].e)
  end)

  it("rejects an explicit indentation indicator of 0", function()
    -- c-indentation-indicator excludes 0 on purpose: an explicit indent of
    -- zero is meaningless, and tolerating it used to leave block_indent
    -- stuck at 0, a value no line's indentation can ever fall short of, so
    -- the block reader never stopped and swallowed every sibling after it.
    assert.has_error(function() yamlcamel.decode("a: |0\nx\nb: 2\n") end)
  end)

  it("rejects a folded block's explicit indentation indicator of 0 too", function()
    assert.has_error(function() yamlcamel.decode("a: >0\nx\nb: 2\n") end)
  end)

  it("reads a block header with the indentation digit before the chomp indicator", function()
    local v = yamlcamel.decode("a: |1-\n x\n  y\nb: 2\n")
    assert.are.equal("x\n y", v.a)
    assert.are.equal(2, v.b)
  end)

  it("reads a block header with the chomp indicator before the indentation digit the same way", function()
    local v = yamlcamel.decode("a: |-1\n x\n  y\nb: 2\n")
    assert.are.equal("x\n y", v.a)
    assert.are.equal(2, v.b)
  end)

  it("keeps reading a compact sequence entry's block scalar correctly two levels deep", function()
    -- Pins header_node_offset's peeling loop past the single level the
    -- existing compact-entry tests exercise, since that offset math has to
    -- stay in lockstep with the indent bumps parse_sequence and
    -- parse_mapping apply for each nested compact level.
    local v = yamlcamel.decode("- - a: |\n    e: x\n  - y\n")
    assert.are.equal("", v[1][1].a)
    assert.are.equal("x", v[1][1].e)
    assert.are.equal("y", v[1][2])
  end)

  it("keeps reading an explicit-key compact sequence entry's block scalar two levels deep", function()
    local v = yamlcamel.decode("? - a: |\n    e: x\n  - y\n: z\n")
    local count = 0
    for _, value in pairs(v) do
      count = count + 1
      assert.are.equal("z", value)
    end
    assert.are.equal(1, count)
  end)
end)

describe("yamlcamel.decode multi-line flow collections", function()
  it("reads a flow sequence that wraps onto a following line", function()
    local v = yamlcamel.decode("items: [1, 2,\n  3, 4]\n")
    assert.are.same({ 1, 2, 3, 4 }, v.items)
  end)

  it("reads a flow mapping that wraps onto a following line, and finds the next sibling key", function()
    local v = yamlcamel.decode("obj: {a: 1,\n  b: 2}\nnext: ok\n")
    assert.are.equal(1, v.obj.a)
    assert.are.equal(2, v.obj.b)
    assert.are.equal("ok", v.next)
  end)

  it("reads a flow sequence spanning more than two physical lines", function()
    local v = yamlcamel.decode("items: [1, 2,\n  3, 4,\n  5, 6]\n")
    assert.are.same({ 1, 2, 3, 4, 5, 6 }, v.items)
  end)
end)

-- Psych wraps any scalar past its own line width, quoted or not, so a
-- message body or an FAQ response coming back from a real server using
-- Psych is routinely spread across more than one physical line this way.
describe("yamlcamel.decode scalars Psych wraps across lines", function()
  it("reads a double-quoted scalar that wraps, folding the break to a space", function()
    local doc = table.concat({
      "body: \"This is a longer message. And has punctuation: commas,",
      "  periods. Final line.\"",
    }, "\n")
    local v = yamlcamel.decode(doc)
    assert.are.equal("This is a longer message. And has punctuation: commas, periods. Final line.", v.body)
  end)

  it("reads a single-quoted scalar that wraps, folding a blank line to one newline", function()
    local v = yamlcamel.decode("body: 'hello\n\n  '\n")
    assert.are.equal("hello\n", v.body)
  end)

  it("reads a double-quoted scalar whose opening line is just the quote itself", function()
    -- A speculative "is this line a quoted mapping key" check used to
    -- call quoted.read_double/read_single directly and let its
    -- "unterminated" error escape, rather than treating a quote that
    -- doesn't close on this one line as "not a key here after all".
    -- Matches yaml-test-suite 6WPF (Spec Example 7.10, tested with an
    -- extra segment there): the break right after the opening quote,
    -- with nothing between them, still folds to a space like any other
    -- single break would.
    local doc = table.concat({ '"', "  foo", "", "  bar", '"' }, "\n")
    local v = yamlcamel.decode(doc)
    assert.are.equal(" foo\nbar ", v)
  end)

  it("reads a plain scalar that wraps, folding the break to a space", function()
    local doc = table.concat({
      "body: Hey everyone, just a heads up that the event starts tonight,",
      "  don't be late!",
      "kind: chat",
    }, "\n")
    local v = yamlcamel.decode(doc)
    assert.are.equal("Hey everyone, just a heads up that the event starts tonight, don't be late!", v.body)
    assert.are.equal("chat", v.kind)
  end)

  it("does not swallow an apostrophe in a plain scalar as an open quote", function()
    local v = yamlcamel.decode("body: don't stop believing\nnext: ok\n")
    assert.are.equal("don't stop believing", v.body)
    assert.are.equal("ok", v.next)
  end)

  it("stops a wrapped plain scalar at a blank line rather than swallowing the next key", function()
    local v = yamlcamel.decode("body: this is plain text\n\nnext: ok\n")
    assert.are.equal("this is plain text", v.body)
    assert.are.equal("ok", v.next)
  end)

  it("wraps the first, compact-written key of a sequence item's mapping without swallowing its sibling", function()
    local doc = table.concat({
      "- body: This is a message that needs to be long enough to wrap",
      "    across more than one physical line for sure.",
      "  id: 1",
    }, "\n")
    local v = yamlcamel.decode(doc)
    assert.are.equal("This is a message that needs to be long enough to wrap across more than one physical line for sure.", v[1].body)
    assert.are.equal(1, v[1].id)
  end)
end)
