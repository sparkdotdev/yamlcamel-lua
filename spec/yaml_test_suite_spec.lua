-- Generated from a local checkout of yaml/yaml-test-suite (MIT license,
-- https://github.com/yaml/yaml-test-suite), data-2022-01-17 release. Each
-- fixture's own in.yaml lives under spec/fixtures/yaml-test-suite/<id>/,
-- copied verbatim; this file only holds the expected value or error per
-- case. Regenerate by re-running the suite through decode, not by hand.
local yamlcamel = require("yamlcamel")

local function fixture(id)
  local path = "spec/fixtures/yaml-test-suite/" .. id .. "/in.yaml"
  local f = assert(io.open(path, "r"), "missing fixture " .. path)
  local text = f:read("a")
  f:close()
  return text
end

describe("yamlcamel against the official yaml-test-suite (matches in.json)", function()
  it("Spec Example 2.4. Sequence of Mappings (229Q)", function()
    local expected = {
      {
        ["avg"] = 0.278,
        ["hr"] = 65,
        ["name"] = "Mark McGwire",
      },
      {
        ["avg"] = 0.288,
        ["hr"] = 63,
        ["name"] = "Sammy Sosa",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("229Q")))
  end)

  it("Spec Example 5.9. Directive Indicator (27NA)", function()
    local expected = "text"
    assert.are.same(expected, yamlcamel.decode(fixture("27NA")))
  end)

  it("Tags in Block Sequence (2AUY)", function()
    local expected = {
      "a",
      "b",
      42,
      "d",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("2AUY")))
  end)

  it("Spec Example 6.13. Reserved Directives [1.3] (2LFX)", function()
    local expected = "foo"
    assert.are.same(expected, yamlcamel.decode(fixture("2LFX")))
  end)

  it("Three explicit integers in a block sequence (33X3)", function()
    local expected = {
      1,
      -2,
      33,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("33X3")))
  end)

  it("Block Sequence in Block Sequence (3ALJ)", function()
    local expected = {
      {
        "s1_i1",
        "s1_i2",
      },
      "s2",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("3ALJ")))
  end)

  it("Spec Example 7.1. Alias Nodes (3GZX)", function()
    local expected = {
      ["First occurrence"] = "Foo",
      ["Override anchor"] = "Bar",
      ["Reuse anchor"] = "Bar",
      ["Second occurrence"] = "Foo",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("3GZX")))
  end)

  it("Plain Scalar looking like key, comment, anchor and tag (3MYT)", function()
    local expected = "k:#foo &a !t s"
    assert.are.same(expected, yamlcamel.decode(fixture("3MYT")))
  end)

  it("Single block sequence with anchor (3R3P)", function()
    local expected = {
      "a",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("3R3P")))
  end)

  it("Escaped slash in double quotes (3UYS)", function()
    local expected = {
      ["escaped slash"] = "a/b",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("3UYS")))
  end)

  it("Spec Example 2.18. Multi-line Flow Scalars (4CQQ)", function()
    local expected = {
      ["plain"] = "This unquoted scalar spans many lines.",
      ["quoted"] = "So does this quoted scalar.\n",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("4CQQ")))
  end)

  it("Spec Example 7.7. Single Quoted Characters (4GC6)", function()
    local expected = "here's to \"quotes\""
    assert.are.same(expected, yamlcamel.decode(fixture("4GC6")))
  end)

  it("Spec Example 8.2. Block Indentation Indicator [1.3] (4QFQ)", function()
    local expected = {
      "detected\
",
      "\
\
# detected\
",
      " explicit\
",
      "detected\
",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("4QFQ")))
  end)

  it("Trailing spaces after flow collection (4RWC)", function()
    local expected = {
      1,
      2,
      3,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("4RWC")))
  end)

  it("Colon in Double Quoted String (4UYU)", function()
    local expected = "foo: bar\": baz"
    assert.are.same(expected, yamlcamel.decode(fixture("4UYU")))
  end)

  it("Plain scalar with backslashes (4V8U)", function()
    local expected = "plain\\value\\with\\backslashes"
    assert.are.same(expected, yamlcamel.decode(fixture("4V8U")))
  end)

  it("Spec Example 6.4. Line Prefixes (4ZYM)", function()
    local expected = {
      ["block"] = "text\
 \9lines\
",
      ["plain"] = "text lines",
      ["quoted"] = "text lines",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("4ZYM")))
  end)

  it("Explicit Non-Specific Tag [1.3] (52DL)", function()
    local expected = "a"
    assert.are.same(expected, yamlcamel.decode(fixture("52DL")))
  end)

  it("Flow Mapping (54T7)", function()
    local expected = {
      ["bar"] = "far",
      ["foo"] = "you",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("54T7")))
  end)

  it("Spec Example 8.22. Block Collection Nodes (57H4)", function()
    local expected = {
      ["mapping"] = {
        ["foo"] = "bar",
      },
      ["sequence"] = {
        "entry",
        {
          "nested",
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("57H4")))
  end)

  it("Flow mapping edge cases (58MP)", function()
    local expected = {
      ["x"] = ":x",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("58MP")))
  end)

  it("Spec Example 5.7. Block Scalar Indicators (5BVJ)", function()
    local expected = {
      ["folded"] = "some text\
",
      ["literal"] = "some\
text\
",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5BVJ")))
  end)

  it("Spec Example 7.15. Flow Mappings (5C5M)", function()
    local expected = {
      {
        ["one"] = "two",
        ["three"] = "four",
      },
      {
        ["five"] = "six",
        ["seven"] = "eight",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5C5M")))
  end)

  it("Spec Example 6.5. Empty Lines (5GBF)", function()
    local expected = {
      ["Chomping"] = "Clipped empty lines\
",
      ["Folding"] = "Empty line\
as a line feed",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5GBF")))
  end)

  it("Spec Example 7.13. Flow Sequence (5KJE)", function()
    local expected = {
      {
        "one",
        "two",
      },
      {
        "three",
        "four",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5KJE")))
  end)

  it("Colon and adjacent value on next line (5MUD)", function()
    local expected = {
      ["foo"] = "bar",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5MUD")))
  end)

  it("Spec Example 6.9. Separated Comment (5NYZ)", function()
    local expected = {
      ["key"] = "value",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5NYZ")))
  end)

  it("Colon at the beginning of adjacent flow scalar (5T43)", function()
    local expected = {
      {
        ["key"] = "value",
      },
      {
        ["key"] = ":value",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5T43")))
  end)

  it("Spec Example 8.17. Explicit Block Mapping Entries (5WE3)", function()
    local expected = {
      ["explicit key"] = yamlcamel.null,
      ["block key\
"] = {
        "one",
        "two",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("5WE3")))
  end)

  it("Question mark at start of flow key (652Z)", function()
    local expected = {
      ["?foo"] = "bar",
      ["bar"] = 42,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("652Z")))
  end)

  it("Single Entry Block Sequence (65WH)", function()
    local expected = {
      "foo",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("65WH")))
  end)

  it("Backslashes in singlequotes (6H3V)", function()
    local expected = {
      ["foo: bar\\"] = "baz'",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("6H3V")))
  end)

  it("Spec Example 6.1. Indentation Spaces (6HB6)", function()
    local expected = {
      ["Not indented"] = {
        ["By one space"] = "By four\
  spaces\
",
        ["Flow style"] = {
          "By two",
          "Also by two",
          "Still by two",
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("6HB6")))
  end)

  it("Tags for Block Objects (6JWB)", function()
    local expected = {
      ["foo"] = {
        "a",
        {
          ["key"] = "value",
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("6JWB")))
  end)

  it("Spec Example 6.13. Reserved Directives (6LVF)", function()
    local expected = "foo"
    assert.are.same(expected, yamlcamel.decode(fixture("6LVF")))
  end)

  it("Allowed characters in quoted mapping key (6SLA)", function()
    local expected = {
      ["foo\
bar:baz\9x \\$%^&*()x"] = 23,
      ["x\\ny:z\\tx $%^&*()x"] = 24,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("6SLA")))
  end)

  it("Spec Example 6.8. Flow Folding [1.3] (6WPF)", function()
    local expected = " foo\
bar\
baz "
    assert.are.same(expected, yamlcamel.decode(fixture("6WPF")))
  end)

  it("Spec Example 9.6. Stream (6ZKB)", function()
    local expected = "Document"
    assert.are.same(expected, yamlcamel.decode(fixture("6ZKB")))
  end)

  it("Spec Example 8.20. Block Node Types (735Y)", function()
    local expected = {
      "flow in block",
      "Block scalar\
",
      {
        ["foo"] = "bar",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("735Y")))
  end)

  it("Spec Example 7.6. Double Quoted Lines (7A4E)", function()
    local expected = " 1st non-empty\
2nd non-empty 3rd non-empty "
    assert.are.same(expected, yamlcamel.decode(fixture("7A4E")))
  end)

  it("Spec Example 2.10. Node for “Sammy Sosa” appears twice in this document (7BUB)", function()
    local expected = {
      ["hr"] = {
        "Mark McGwire",
        "Sammy Sosa",
      },
      ["rbi"] = {
        "Sammy Sosa",
        "Ken Griffey",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("7BUB")))
  end)

  it("Comment in flow sequence before comma (7TMG)", function()
    local expected = {
      "word1",
      "word2",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("7TMG")))
  end)

  it("Block Mapping with Missing Values (7W2P)", function()
    local expected = {
      ["a"] = yamlcamel.null,
      ["b"] = yamlcamel.null,
      ["c"] = yamlcamel.null,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("7W2P")))
  end)

  it("Bare document after document end marker (7Z25)", function()
    local expected = "scalar1"
    assert.are.same(expected, yamlcamel.decode(fixture("7Z25")))
  end)

  it("Empty flow collections (7ZZ5)", function()
    local expected = {
      ["key1"] = {},
      ["key2"] = {},
      ["nested sequences"] = {
        {
          {
            {},
          },
        },
        {
          {
            {},
          },
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("7ZZ5")))
  end)

  it("Spec Example 7.8. Single Quoted Implicit Keys (87E4)", function()
    local expected = {
      ["implicit block key"] = {
        {
          ["implicit flow key"] = "value",
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("87E4")))
  end)

  it("Plain mapping key ending with colon (8CWC)", function()
    local expected = {
      ["key ends with two colons::"] = "value",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("8CWC")))
  end)

  it("Multiline plain flow mapping key without value (8KB6)", function()
    local expected = {
      {
        ["a"] = "b",
        ["single line"] = yamlcamel.null,
      },
      {
        ["a"] = "b",
        ["multi line"] = yamlcamel.null,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("8KB6")))
  end)

  it("Explicit Non-Specific Tag (8MK2)", function()
    local expected = "a"
    assert.are.same(expected, yamlcamel.decode(fixture("8MK2")))
  end)

  it("Block Sequence in Block Mapping (8QBE)", function()
    local expected = {
      ["key"] = {
        "item1",
        "item2",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("8QBE")))
  end)

  it("Spec Example 7.14. Flow Sequence Entries (8UDB)", function()
    local expected = {
      "double quoted",
      "single quoted",
      "plain text",
      {
        "nested",
      },
      {
        ["single"] = "pair",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("8UDB")))
  end)

  it("Anchor with unicode character (8XYN)", function()
    local expected = {
      "unicode anchor",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("8XYN")))
  end)

  it("Block Mappings in Block Sequence (93JH)", function()
    local expected = {
      {
        ["key"] = "value",
        ["key2"] = "value2",
      },
      {
        ["key3"] = "value3",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("93JH")))
  end)

  it("Multiline doublequoted flow mapping key without value (9BXH)", function()
    local expected = {
      {
        ["a"] = "b",
        ["single line"] = yamlcamel.null,
      },
      {
        ["a"] = "b",
        ["multi line"] = yamlcamel.null,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("9BXH")))
  end)

  it("Spec Example 9.6. Stream [1.3] (9DXL)", function()
    local expected = {
      ["Mapping"] = "Document",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("9DXL")))
  end)

  it("Multi-level Mapping Indent (9FMG)", function()
    local expected = {
      ["a"] = {
        ["b"] = {
          ["c"] = "d",
        },
        ["e"] = {
          ["f"] = "g",
        },
      },
      ["h"] = "i",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("9FMG")))
  end)

  it("Simple Mapping Indent (9J7A)", function()
    local expected = {
      ["foo"] = {
        ["bar"] = "baz",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("9J7A")))
  end)

  it("Multiline double quoted flow mapping key (9SA2)", function()
    local expected = {
      {
        ["single line"] = "value",
      },
      {
        ["multi line"] = "value",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("9SA2")))
  end)

  it("Spec Example 5.8. Quoted Scalar Indicators (9SHH)", function()
    local expected = {
      ["double"] = "text",
      ["single"] = "text",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("9SHH")))
  end)

  it("Spec Example 7.6. Double Quoted Lines [1.3] (9TFX)", function()
    local expected = " 1st non-empty\
2nd non-empty 3rd non-empty "
    assert.are.same(expected, yamlcamel.decode(fixture("9TFX")))
  end)

  it("Spec Example 2.12. Compact Nested Mapping (9U5K)", function()
    local expected = {
      {
        ["item"] = "Super Hoop",
        ["quantity"] = 1,
      },
      {
        ["item"] = "Basketball",
        ["quantity"] = 4,
      },
      {
        ["item"] = "Big Shoes",
        ["quantity"] = 1,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("9U5K")))
  end)

  it("Multiline Scalar in Mapping (A984)", function()
    local expected = {
      ["a"] = "b c",
      ["d"] = "e f",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("A984")))
  end)

  it("Sequence entry that looks like two with wrong indentation (AB8U)", function()
    local expected = {
      "single multiline - sequence entry",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("AB8U")))
  end)

  it("Sequence With Same Indentation as Parent Mapping (AZ63)", function()
    local expected = {
      ["four"] = 5,
      ["one"] = {
        2,
        3,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("AZ63")))
  end)

  it("Spec Example 6.14. “YAML” directive (BEC7)", function()
    local expected = "foo"
    assert.are.same(expected, yamlcamel.decode(fixture("BEC7")))
  end)

  it("Spec Example 7.18. Flow Mapping Adjacent Values (C2DT)", function()
    local expected = {
      ["adjacent"] = "value",
      ["empty"] = yamlcamel.null,
      ["readable"] = "value",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("C2DT")))
  end)

  it("Various location of anchors in flow sequence (CN3R)", function()
    local expected = {
      {
        ["a"] = "b",
      },
      {
        ["c"] = "d",
      },
      {
        ["e"] = "f",
      },
      {
        ["g"] = "h",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("CN3R")))
  end)

  it("Doublequoted scalar starting with a tab (CPZ3)", function()
    local expected = {
      ["tab"] = "\9string",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("CPZ3")))
  end)

  it("Flow Sequence in Block Mapping (D88J)", function()
    local expected = {
      ["a"] = {
        "b",
        "c",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("D88J")))
  end)

  it("Single Pair Block Mapping (D9TU)", function()
    local expected = {
      ["foo"] = "bar",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("D9TU")))
  end)

  it("Spec Example 7.10. Plain Characters (DBG4)", function()
    local expected = {
      "::vector",
      ": - ()",
      "Up, up, and away!",
      -123,
      "http://example.com/foo#bar",
      {
        "::vector",
        ": - ()",
        "Up, up and away!",
        -123,
        "http://example.com/foo#bar",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("DBG4")))
  end)

  it("Various trailing tabs (DC7X)", function()
    local expected = {
      ["a"] = "b",
      ["c"] = "d",
      ["seq"] = {
        "a",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("DC7X")))
  end)

  it("Flow Sequence (DHP8)", function()
    local expected = {
      "foo",
      "bar",
      42,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("DHP8")))
  end)

  it("Tags for Flow Objects (EHF6)", function()
    local expected = {
      ["k"] = {
        "a",
        "b",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("EHF6")))
  end)

  it("Anchors and Tags (F2C7)", function()
    local expected = {
      "a",
      2,
      4,
      "d",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("F2C7")))
  end)

  it("Nested flow collections on one line (F3CP)", function()
    local expected = {
      ["a"] = {
        "b",
        "c",
        {
          ["d"] = {
            "e",
            "f",
          },
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("F3CP")))
  end)

  it("More indented lines at the beginning of folded block scalars (F6MC)", function()
    local expected = {
      ["a"] = " more indented\
regular\
",
      ["b"] = "\
\
 more indented\
regular\
",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("F6MC")))
  end)

  it("Spec Example 8.5. Chomping Trailing Lines (F8F9)", function()
    local expected = {
      ["clip"] = "# text\
",
      ["keep"] = "# text\
\
",
      ["strip"] = "# text",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("F8F9")))
  end)

  it("Spec Example 2.1. Sequence of Scalars (FQ7F)", function()
    local expected = {
      "Mark McGwire",
      "Sammy Sosa",
      "Ken Griffey",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("FQ7F")))
  end)

  it("Flow Sequence in Flow Sequence (FUP4)", function()
    local expected = {
      "a",
      {
        "b",
        "c",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("FUP4")))
  end)

  it("Spec Example 2.17. Quoted Scalars (G4RS)", function()
    local expected = {
      ["control"] = "\0081998\0091999\0092000\
",
      ["hex esc"] = "\13\
 is \13\
",
      ["quoted"] = " # Not a 'comment'.",
      ["single"] = "\"Howdy!\" he cried.",
      ["tie-fighter"] = "|\\-*-/|",
      ["unicode"] = "Sosa did fine.☺",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("G4RS")))
  end)

  it("Spec Example 8.9. Folded Scalar (G992)", function()
    local expected = "folded text\
"
    assert.are.same(expected, yamlcamel.decode(fixture("G992")))
  end)

  it("Mixed Block Mapping (explicit to implicit) (GH63)", function()
    local expected = {
      ["a"] = 1.3,
      ["fifteen"] = "d",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("GH63")))
  end)

  it("Literal unicode (H3Z8)", function()
    local expected = {
      ["wanted"] = "love ♥ and peace ☮",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("H3Z8")))
  end)

  it("Spec Example 2.16. Indentation determines scope (HMK4)", function()
    local expected = {
      ["accomplishment"] = "Mark set a major league home run record in 1998.\
",
      ["name"] = "Mark McGwire",
      ["stats"] = "65 Home Runs\
0.278 Batting Average\
",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("HMK4")))
  end)

  it("Multiple Pair Block Mapping (J5UC)", function()
    local expected = {
      ["bar"] = "arrr",
      ["baz"] = "jazz",
      ["foo"] = "blue",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("J5UC")))
  end)

  it("Empty Lines Between Mapping Elements (J7VC)", function()
    local expected = {
      ["one"] = 2,
      ["three"] = 4,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("J7VC")))
  end)

  it("Spec Example 2.9. Single Document with Two Comments (J9HZ)", function()
    local expected = {
      ["hr"] = {
        "Mark McGwire",
        "Sammy Sosa",
      },
      ["rbi"] = {
        "Sammy Sosa",
        "Ken Griffey",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("J9HZ")))
  end)

  it("Spec Example 2.7. Two Documents in a Stream (JHB9)", function()
    local expected = {
      "Mark McGwire",
      "Sammy Sosa",
      "Ken Griffey",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("JHB9")))
  end)

  it("Spec Example 8.14. Block Sequence (JQ4R)", function()
    local expected = {
      ["block sequence"] = {
        "one",
        {
          ["two"] = "three",
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("JQ4R")))
  end)

  it("Question marks in scalars (JR7V)", function()
    local expected = {
      "a?string",
      "another ? string",
      {
        ["key"] = "value?",
      },
      {
        "a?string",
      },
      {
        "another ? string",
      },
      {
        ["key"] = "value?",
      },
      {
        ["key"] = "value?",
      },
      {
        ["key?"] = "value",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("JR7V")))
  end)

  it("Spec Example 6.29. Node Anchors (JS2J)", function()
    local expected = {
      ["First occurrence"] = "Value",
      ["Second occurrence"] = "Value",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("JS2J")))
  end)

  it("Block Mapping with Multiline Scalars (JTV5)", function()
    local expected = {
      ["a true"] = "null d",
      ["e 42"] = yamlcamel.null,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("JTV5")))
  end)

  it("Colon and adjacent value after comment on next line (K3WX)", function()
    local expected = {
      ["foo"] = "bar",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("K3WX")))
  end)

  it("Multiple Entry Block Sequence (K4SU)", function()
    local expected = {
      "foo",
      "bar",
      42,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("K4SU")))
  end)

  it("Spec Example 6.6. Line Folding (K527)", function()
    local expected = "trimmed\
\
\
as space"
    assert.are.same(expected, yamlcamel.decode(fixture("K527")))
  end)

  it("Tab after document header (K54U)", function()
    local expected = "scalar"
    assert.are.same(expected, yamlcamel.decode(fixture("K54U")))
  end)

  it("Block Submapping (KMK3)", function()
    local expected = {
      ["baz"] = 2,
      ["foo"] = {
        ["bar"] = 1,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("KMK3")))
  end)

  it("Two scalar docs with trailing comments (L383)", function()
    local expected = "foo"
    assert.are.same(expected, yamlcamel.decode(fixture("L383")))
  end)

  it("Tags in Explicit Mapping (L94M)", function()
    local expected = {
      ["a"] = 47,
      ["c"] = "d",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("L94M")))
  end)

  it("Spec Example 7.11. Plain Implicit Keys (L9U5)", function()
    local expected = {
      ["implicit block key"] = {
        {
          ["implicit flow key"] = "value",
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("L9U5")))
  end)

  it("Whitespace After Scalars in Flow (LP6E)", function()
    local expected = {
      {
        "a",
        "b",
        "c",
      },
      {
        ["a"] = "b",
        ["c"] = "d",
        ["e"] = "f",
      },
      {},
    }
    assert.are.same(expected, yamlcamel.decode(fixture("LP6E")))
  end)

  it("Spec Example 7.4. Double Quoted Implicit Keys (LQZ7)", function()
    local expected = {
      ["implicit block key"] = {
        {
          ["implicit flow key"] = "value",
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("LQZ7")))
  end)

  it("Literal Block Scalar (M29M)", function()
    local expected = {
      ["a"] = "ab\
\
cd\
ef\
",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("M29M")))
  end)

  it("Block sequence indentation (M6YH)", function()
    local expected = {
      "x\
",
      {
        ["foo"] = "bar",
      },
      {
        42,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("M6YH")))
  end)

  it("Nested flow collections (M7NX)", function()
    local expected = {
      ["a"] = {
        "b",
        "c",
        {
          ["d"] = {
            "e",
            "f",
          },
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("M7NX")))
  end)

  it("Spec Example 8.7. Literal Scalar (M9B4)", function()
    local expected = "literal\
\9text\
"
    assert.are.same(expected, yamlcamel.decode(fixture("M9B4")))
  end)

  it("Flow Mapping in Block Sequence (MXS3)", function()
    local expected = {
      {
        ["a"] = "b",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("MXS3")))
  end)

  it("Block Scalar Strip (MYW6)", function()
    local expected = "ab"
    assert.are.same(expected, yamlcamel.decode(fixture("MYW6")))
  end)

  it("Non-Specific Tags on Scalars (MZX3)", function()
    local expected = {
      "plain",
      "double quoted",
      "single quoted",
      "block\
",
      "plain again",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("MZX3")))
  end)

  it("Various empty or newline only quoted strings (NAT4)", function()
    local expected = {
      ["a"] = " ",
      ["b"] = " ",
      ["c"] = " ",
      ["d"] = " ",
      ["e"] = "\
",
      ["f"] = "\
",
      ["g"] = "\
\
",
      ["h"] = "\
\
",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("NAT4")))
  end)

  it("Multiline plain flow mapping key (NJ66)", function()
    local expected = {
      {
        ["single line"] = "value",
      },
      {
        ["multi line"] = "value",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("NJ66")))
  end)

  it("Spec Example 7.5. Double Quoted Line Breaks (NP9H)", function()
    local expected = "folded to a space,\
to a line feed, or \9 \9non-content"
    assert.are.same(expected, yamlcamel.decode(fixture("NP9H")))
  end)

  it("Spec Example 6.11. Multi-Line Comments (P94K)", function()
    local expected = {
      ["key"] = "value",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("P94K")))
  end)

  it("Spec Example 2.3. Mapping Scalars to Sequences (PBJ2)", function()
    local expected = {
      ["american"] = {
        "Boston Red Sox",
        "Detroit Tigers",
        "New York Yankees",
      },
      ["national"] = {
        "New York Mets",
        "Chicago Cubs",
        "Atlanta Braves",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("PBJ2")))
  end)

  it("Spec Example 7.9. Single Quoted Lines (PRH3)", function()
    local expected = " 1st non-empty\
2nd non-empty 3rd non-empty "
    assert.are.same(expected, yamlcamel.decode(fixture("PRH3")))
  end)

  it("Document start on last line (PUW8)", function()
    local expected = {
      ["a"] = "b",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("PUW8")))
  end)

  it("Spec Example 7.23. Flow Content (Q88A)", function()
    local expected = {
      {
        "a",
        "b",
      },
      {
        ["a"] = "b",
      },
      "a",
      "b",
      "c",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("Q88A")))
  end)

  it("Spec Example 7.5. Double Quoted Line Breaks [1.3] (Q8AD)", function()
    local expected = "folded to a space,\
to a line feed, or \9 \9non-content"
    assert.are.same(expected, yamlcamel.decode(fixture("Q8AD")))
  end)

  it("Spec Example 7.19. Single Pair Flow Mappings (QF4Y)", function()
    local expected = {
      {
        ["foo"] = "bar",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("QF4Y")))
  end)

  it("Nested flow mapping sequence and mappings (R52L)", function()
    local expected = {
      ["top1"] = {
        "item1",
        {
          ["key2"] = "value2",
        },
        "item3",
      },
      ["top2"] = "value2",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("R52L")))
  end)

  it("Sequence Indent (RLU9)", function()
    local expected = {
      ["bar"] = {
        44,
      },
      ["foo"] = {
        42,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("RLU9")))
  end)

  it("Mixed Block Mapping (implicit to explicit) (RR7F)", function()
    local expected = {
      ["a"] = 4.2,
      ["d"] = 23,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("RR7F")))
  end)

  it("Spec Example 9.2. Document Markers (RTP8)", function()
    local expected = "Document"
    assert.are.same(expected, yamlcamel.decode(fixture("RTP8")))
  end)

  it("Spec Example 2.28. Log File, first document (RZT7)", function()
    -- decode() only reads the first of this fixture's three documents;
    -- its "Warning" value is exactly the same-indentation plain scalar
    -- folding this fixture exists to check.
    local expected = {
      ["Time"] = "2001-11-23 15:01:42 -5",
      ["User"] = "ed",
      ["Warning"] = "This is an error message for the log file",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("RZT7")))
  end)

  it("Spec Example 6.28. Non-Specific Tags (S4JQ)", function()
    local expected = {
      "12",
      12,
      "12",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("S4JQ")))
  end)

  it("Document with footer (S4T7)", function()
    local expected = {
      ["aaa"] = "bbb",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("S4T7")))
  end)

  it("Colon followed by comma (S7BG)", function()
    local expected = {
      ":,",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("S7BG")))
  end)

  it("Spec Example 7.7. Single Quoted Characters [1.3] (SSW6)", function()
    local expected = "here's to \"quotes\""
    assert.are.same(expected, yamlcamel.decode(fixture("SSW6")))
  end)

  it("Spec Example 2.2. Mapping Scalars to Scalars (SYW4)", function()
    local expected = {
      ["avg"] = 0.278,
      ["hr"] = 65,
      ["rbi"] = 147,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("SYW4")))
  end)

  it("Spec Example 7.9. Single Quoted Lines [1.3] (T4YY)", function()
    local expected = " 1st non-empty\
2nd non-empty 3rd non-empty "
    assert.are.same(expected, yamlcamel.decode(fixture("T4YY")))
  end)

  it("Spec Example 8.16. Block Mappings (TE2A)", function()
    local expected = {
      ["block mapping"] = {
        ["key"] = "value",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("TE2A")))
  end)

  it("Spec Example 6.8. Flow Folding (TL85)", function()
    local expected = " foo\
bar\
baz "
    assert.are.same(expected, yamlcamel.decode(fixture("TL85")))
  end)

  it("Folded Block Scalar (TS54)", function()
    local expected = "ab cd\
ef\
\
gh\
"
    assert.are.same(expected, yamlcamel.decode(fixture("TS54")))
  end)

  it("Spec Example 6.16. “TAG” directive (U3C3)", function()
    local expected = "foo"
    assert.are.same(expected, yamlcamel.decode(fixture("U3C3")))
  end)

  it("Spec Example 2.8. Play by Play Feed from a Game (U9NS)", function()
    local expected = {
      ["action"] = "strike (miss)",
      ["player"] = "Sammy Sosa",
      ["time"] = "20:03:20",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("U9NS")))
  end)

  it("Plain URL in flow mapping (UDM2)", function()
    local expected = {
      {
        ["url"] = "http://example.org",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("UDM2")))
  end)

  it("Spec Example 5.4. Flow Collection Indicators (UDR7)", function()
    local expected = {
      ["mapping"] = {
        ["sea"] = "green",
        ["sky"] = "blue",
      },
      ["sequence"] = {
        "one",
        "two",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("UDR7")))
  end)

  it("Spec Example 9.4. Explicit Documents (UT92)", function()
    local expected = {
      ["matches %"] = 20,
    }
    assert.are.same(expected, yamlcamel.decode(fixture("UT92")))
  end)

  it("Legal tab after indentation (UV7Q)", function()
    local expected = {
      ["x"] = {
        "x x",
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("UV7Q")))
  end)

  it("Aliases in Block Sequence (V55R)", function()
    local expected = {
      "a",
      "b",
      "a",
      "b",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("V55R")))
  end)

  it("Explicit key and value separated by comment (X8DW)", function()
    local expected = {
      ["key"] = "value",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("X8DW")))
  end)

  it("Spec Example 6.5. Empty Lines [1.3] (XV9V)", function()
    local expected = {
      ["Chomping"] = "Clipped empty lines\
",
      ["Folding"] = "Empty line\
as a line feed",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("XV9V")))
  end)

  it("Anchor with colon in the middle (Y2GN)", function()
    local expected = {
      ["key"] = "value",
    }
    assert.are.same(expected, yamlcamel.decode(fixture("Y2GN")))
  end)

  it("Spec Example 2.5. Sequence of Sequences (YD5X)", function()
    local expected = {
      {
        "name",
        "hr",
        "avg",
      },
      {
        "Mark McGwire",
        65,
        0.278,
      },
      {
        "Sammy Sosa",
        63,
        0.288,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("YD5X")))
  end)

  it("Spec Example 2.6. Mapping of Mappings (ZF4X)", function()
    local expected = {
      ["Mark McGwire"] = {
        ["avg"] = 0.278,
        ["hr"] = 65,
      },
      ["Sammy Sosa"] = {
        ["avg"] = 0.288,
        ["hr"] = 63,
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("ZF4X")))
  end)

  it("Nested top level flow mapping (ZK9H)", function()
    local expected = {
      ["key"] = {
        {
          {
            "value",
          },
        },
      },
    }
    assert.are.same(expected, yamlcamel.decode(fixture("ZK9H")))
  end)

end)

describe("yamlcamel against the official yaml-test-suite (correctly rejects malformed input)", function()
  it("Invalid value after mapping (236B)", function()
    assert.has_error(function() yamlcamel.decode(fixture("236B")) end)
  end)

  it("Invalid value after mapping (236B)", function()
    assert.has_error(function() yamlcamel.decode(fixture("236B")) end)
  end)

  it("Invalid content after document end marker (3HFZ)", function()
    assert.has_error(function() yamlcamel.decode(fixture("3HFZ")) end)
  end)

  it("Invalid tabs as indendation in a mapping (4EJS)", function()
    assert.has_error(function() yamlcamel.decode(fixture("4EJS")) end)
  end)

  it("Flow sequence with invalid extra closing bracket (4H7K)", function()
    assert.has_error(function() yamlcamel.decode(fixture("4H7K")) end)
  end)

  it("Invalid escape in double quoted string (55WF)", function()
    assert.has_error(function() yamlcamel.decode(fixture("55WF")) end)
  end)

  it("Invalid block mapping key on same line as previous key (62EZ)", function()
    assert.has_error(function() yamlcamel.decode(fixture("62EZ")) end)
  end)

  it("Flow sequence without closing bracket (6JTT)", function()
    assert.has_error(function() yamlcamel.decode(fixture("6JTT")) end)
  end)

  it("Missing colon (7MNF)", function()
    assert.has_error(function() yamlcamel.decode(fixture("7MNF")) end)
  end)

  it("Invalid scalar at the end of mapping (9CWY)", function()
    assert.has_error(function() yamlcamel.decode(fixture("9CWY")) end)
  end)

  it("Invalid comment after end of flow sequence (9JBA)", function()
    assert.has_error(function() yamlcamel.decode(fixture("9JBA")) end)
  end)

  it("Invalid comment after end of flow sequence (9JBA)", function()
    assert.has_error(function() yamlcamel.decode(fixture("9JBA")) end)
  end)

  it("Comment between plain scalar lines (BS4K)", function()
    assert.has_error(function() yamlcamel.decode(fixture("BS4K")) end)
  end)

  it("Double quoted string without closing quote (CQ3W)", function()
    assert.has_error(function() yamlcamel.decode(fixture("CQ3W")) end)
  end)

  it("Invalid anchor in zero indented sequence (G9HC)", function()
    assert.has_error(function() yamlcamel.decode(fixture("G9HC")) end)
  end)

  it("Comment that looks like a mapping key (GDY7)", function()
    assert.has_error(function() yamlcamel.decode(fixture("GDY7")) end)
  end)

  it("Node anchor not indented (H7J7)", function()
    assert.has_error(function() yamlcamel.decode(fixture("H7J7")) end)
  end)

  it("Extra words on %YAML directive (H7TQ)", function()
    assert.has_error(function() yamlcamel.decode(fixture("H7TQ")) end)
  end)

  it("Double quoted scalar with escaped single quote (HRE5)", function()
    assert.has_error(function() yamlcamel.decode(fixture("HRE5")) end)
  end)

  it("Invalid Mapping in plain scalar (HU3P)", function()
    assert.has_error(function() yamlcamel.decode(fixture("HU3P")) end)
  end)

  it("Trailing content that looks like a mapping (JY7Z)", function()
    assert.has_error(function() yamlcamel.decode(fixture("JY7Z")) end)
  end)

  it("Trailing content that looks like a mapping (JY7Z)", function()
    assert.has_error(function() yamlcamel.decode(fixture("JY7Z")) end)
  end)

  it("Invalid item after end of flow sequence (KS4U)", function()
    assert.has_error(function() yamlcamel.decode(fixture("KS4U")) end)
  end)

  it("Invalid tag (LHL4)", function()
    assert.has_error(function() yamlcamel.decode(fixture("LHL4")) end)
  end)

  it("Invalid sequene item on same line as previous item (P2EQ)", function()
    assert.has_error(function() yamlcamel.decode(fixture("P2EQ")) end)
  end)

  it("Trailing content after quoted value (Q4CL)", function()
    assert.has_error(function() yamlcamel.decode(fixture("Q4CL")) end)
  end)

  it("Tag shorthand used in documents but only defined in the first (QLJ7)", function()
    -- The defect here is in the SECOND document's tag, a %TAG handle that
    -- only the first document's directive defined; decode() alone never
    -- looks past the first document to find it, so this needs decode_all
    -- (7.1.7: a %TAG directive's scope is its own document only).
    assert.has_error(function() yamlcamel.decode_all(fixture("QLJ7")) end)
  end)

end)
