local yamlcamel = require("yamlcamel")

describe("yamlcamel.decode_all", function()
  it("reads a stream of two explicit documents", function()
    local docs = yamlcamel.decode_all("---\na: 1\n---\nb: 2\n")
    assert.are.equal(2, #docs)
    assert.are.equal(1, docs[1].a)
    assert.are.equal(2, docs[2].b)
  end)

  it("reads a stream separated by an explicit end-of-document marker", function()
    local docs = yamlcamel.decode_all("---\na: 1\n...\n---\nb: 2\n...\n")
    assert.are.equal(2, #docs)
    assert.are.equal(1, docs[1].a)
    assert.are.equal(2, docs[2].b)
  end)

  it("reads three documents, mixing scalar and mapping roots", function()
    local docs = yamlcamel.decode_all("--- 1\n---\nname: two\n---\n- a\n- b\n")
    assert.are.equal(3, #docs)
    assert.are.equal(1, docs[1])
    assert.are.equal("two", docs[2].name)
    assert.are.same({ "a", "b" }, docs[3])
  end)

  it("reads a single document the same as decode, when there is no second marker", function()
    local docs = yamlcamel.decode_all("---\na: 1\nb: 2\n")
    assert.are.equal(1, #docs)
    assert.are.equal(1, docs[1].a)
  end)

  it("reads an implicit document with no leading marker at all", function()
    local docs = yamlcamel.decode_all("a: 1\n")
    assert.are.equal(1, #docs)
    assert.are.equal(1, docs[1].a)
  end)

  it("resolves an empty document between two markers to null", function()
    local docs = yamlcamel.decode_all("---\n---\na: 1\n")
    assert.are.equal(2, #docs)
    assert.is_true(yamlcamel.is_null(docs[1]))
    assert.are.equal(1, docs[2].a)
  end)

  it("returns an empty array for a blank or entirely commented stream", function()
    assert.are.same({}, yamlcamel.decode_all(""))
    assert.are.same({}, yamlcamel.decode_all("   \n# just a comment\n"))
  end)

  it("does not carry an anchor from one document into the next", function()
    assert.has_error(function() yamlcamel.decode_all("---\na: &x 1\n---\nb: *x\n") end)
  end)

  it("tolerates a %YAML directive ahead of a document", function()
    local docs = yamlcamel.decode_all("%YAML 1.2\n---\na: 1\n")
    assert.are.equal(1, #docs)
    assert.are.equal(1, docs[1].a)
  end)

  it("tolerates a %TAG directive ahead of a document", function()
    local docs = yamlcamel.decode_all("%TAG ! tag:example.com,2000:\n---\na: 1\n")
    assert.are.equal(1, #docs)
    assert.are.equal(1, docs[1].a)
  end)

  it("raises on an unsupported major YAML version", function()
    assert.has_error(function() yamlcamel.decode_all("%YAML 2.0\n---\na: 1\n") end)
  end)

  it("still gathers a block scalar's lines correctly across a multi-document stream", function()
    local docs = yamlcamel.decode_all("---\nbody: |\n  first\n---\nbody: |\n  second\n")
    assert.are.equal(2, #docs)
    assert.are.equal("first\n", docs[1].body)
    assert.are.equal("second\n", docs[2].body)
  end)

  it("strips a byte order mark opening a document past the first, not only the stream itself", function()
    -- 5.2 allows a BOM to open any document, not only the stream as a whole. Left in place
    -- past the first, it used to glue itself onto that document's own first key instead of
    -- being recognized as a marker: "\239\187\191b: 2" decoded to a mapping with the key
    -- "\239\187\191b", not "b".
    local BOM = "\239\187\191"
    local docs = yamlcamel.decode_all("a: 1\n---\n" .. BOM .. "b: 2\n---\n" .. BOM .. "c: 3\n")
    assert.are.equal(3, #docs)
    assert.are.equal(1, docs[1].a)
    assert.are.equal(2, docs[2].b)
    assert.is_nil(docs[2][BOM .. "b"])
    assert.are.equal(3, docs[3].c)
    assert.is_nil(docs[3][BOM .. "c"])
  end)

  it("does not strip three ordinary content bytes off a document that opens inline on the same line as ---", function()
    -- A document's content can start right on the "--- " line itself; there is no separate
    -- fresh line there for a BOM to open, so nothing should be stripped from it.
    local docs = yamlcamel.decode_all("--- one\n--- two\n")
    assert.are.equal(2, #docs)
    assert.are.equal("one", docs[1])
    assert.are.equal("two", docs[2])
  end)
end)

describe("yamlcamel.decode against a multi-document stream", function()
  it("decodes just the first document, silently", function()
    local v = yamlcamel.decode("---\na: 1\n---\nb: 2\n")
    assert.are.equal(1, v.a)
    assert.is_nil(v.b)
  end)
end)

describe("yamlcamel.encode_all", function()
  it("round-trips a stream of documents through decode_all", function()
    local text = yamlcamel.encode_all({ { a = 1 }, { b = 2 }, "plain" })
    local docs = yamlcamel.decode_all(text)
    assert.are.equal(3, #docs)
    assert.are.equal(1, docs[1].a)
    assert.are.equal(2, docs[2].b)
    assert.are.equal("plain", docs[3])
  end)

  it("encodes an empty array as an empty stream", function()
    assert.are.equal("", yamlcamel.encode_all({}))
  end)
end)
