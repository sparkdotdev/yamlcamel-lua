local yamlcamel = require("yamlcamel")

describe("yamlcamel.decode explicit core schema tags", function()
  it("forces !!str onto a plain scalar that would otherwise become a number", function()
    local v = yamlcamel.decode("--- !!str 42")
    assert.are.equal("42", v)
  end)

  it("forces !!str onto a plain scalar that would otherwise become a boolean", function()
    local v = yamlcamel.decode("--- !!str true")
    assert.are.equal("true", v)
  end)

  it("forces !!int onto a quoted scalar", function()
    local v = yamlcamel.decode('--- !!int "42"')
    assert.are.equal(42, v)
  end)

  it("forces !!float onto a plain integer-looking scalar", function()
    local v = yamlcamel.decode("--- !!float 3")
    assert.are.equal(3.0, v)
  end)

  it("forces !!bool, but still only accepts the 1.2 spellings", function()
    assert.is_true(yamlcamel.decode("--- !!bool true"))
    assert.has_error(function() yamlcamel.decode("--- !!bool yes") end)
  end)

  it("forces !!null regardless of surrounding content", function()
    assert.is_true(yamlcamel.is_null(yamlcamel.decode("--- !!null ~")))
  end)

  it("raises when the tagged text does not fit the forced type", function()
    assert.has_error(function() yamlcamel.decode("--- !!int not a number") end)
  end)

  it("resolves the secondary handle (!!) the same as tag:yaml.org,2002:", function()
    local v = yamlcamel.decode("--- !<tag:yaml.org,2002:str> 42")
    assert.are.equal("42", v)
  end)

  it("treats the bare non-specific ! tag as forcing string, per its kind", function()
    local v = yamlcamel.decode("--- ! 42")
    assert.are.equal("42", v)
  end)

  it("!!map and !!seq confirm a collection's own kind without changing it", function()
    local v = yamlcamel.decode("body: !!map\n  a: 1\n")
    assert.are.equal(1, v.body.a)
    local seq = yamlcamel.decode("body: !!seq\n  - a\n  - b\n")
    assert.are.same({ "a", "b" }, seq.body)
  end)
end)

describe("yamlcamel.decode application-specific tags", function()
  it("wraps a plain scalar with an unrecognized local tag", function()
    local v = yamlcamel.decode("--- !Point 1,2")
    assert.is_true(yamlcamel.is_tagged(v))
    assert.are.equal("!Point", v.tag)
    assert.are.equal("1,2", v.value)
  end)

  it("wraps a mapping with an unrecognized local tag", function()
    local v = yamlcamel.decode("point: !Point\n  x: 1\n  y: 2\n")
    assert.is_true(yamlcamel.is_tagged(v.point))
    assert.are.equal("!Point", v.point.tag)
    assert.are.equal(1, v.point.value.x)
    assert.are.equal(2, v.point.value.y)
  end)

  it("wraps a sequence item written with the compact dash form", function()
    local v = yamlcamel.decode("shapes:\n- !Circle\n  r: 5\n")
    assert.is_true(yamlcamel.is_tagged(v.shapes[1]))
    assert.are.equal("!Circle", v.shapes[1].tag)
    assert.are.equal(5, v.shapes[1].value.r)
  end)

  it("wraps a value inside a flow collection", function()
    local v = yamlcamel.decode("--- [!Point pair, plain]")
    assert.is_true(yamlcamel.is_tagged(v[1]))
    assert.are.equal("!Point", v[1].tag)
    assert.are.equal("pair", v[1].value)
    assert.are.equal("plain", v[2])
  end)

  it("wraps a value tagged with a verbatim URI", function()
    local v = yamlcamel.decode("--- !<tag:example.com,2000:custom> hi")
    assert.is_true(yamlcamel.is_tagged(v))
    assert.are.equal("tag:example.com,2000:custom", v.tag)
    assert.are.equal("hi", v.value)
  end)

  it("expands a named handle declared by a %TAG directive", function()
    local v = yamlcamel.decode("%TAG !e! tag:example.com,2000:\n---\n!e!custom hi\n")
    assert.is_true(yamlcamel.is_tagged(v))
    assert.are.equal("tag:example.com,2000:custom", v.tag)
    assert.are.equal("hi", v.value)
  end)

  it("raises on a named handle with no %TAG directive to define it", function()
    assert.has_error(function() yamlcamel.decode("--- !e!custom hi") end)
  end)

  it("expands the primary handle when a %TAG ! directive redefines it", function()
    local v = yamlcamel.decode("%TAG ! tag:example.com,2000:\n---\n!custom hi\n")
    assert.are.equal("tag:example.com,2000:custom", v.tag)
  end)

  it("expands the secondary handle against a %TAG !! directive, not the yaml.org default", function()
    -- Spec Example 6.19: once !! is redefined, !!int is a custom tag, not
    -- tag:yaml.org,2002:int, so "1 - 3" is legal content for it (an
    -- interval, per the document's own comment, not an integer at all).
    local v = yamlcamel.decode("%TAG !! tag:example.com,2000:app/\n---\n!!int 1 - 3\n")
    assert.is_true(yamlcamel.is_tagged(v))
    assert.are.equal("tag:example.com,2000:app/int", v.tag)
    assert.are.equal("1 - 3", v.value)
  end)

  it("wraps a block scalar with an unrecognized tag", function()
    local v = yamlcamel.decode("body: !Reason |\n  because\n")
    assert.is_true(yamlcamel.is_tagged(v.body))
    assert.are.equal("!Reason", v.body.tag)
    assert.are.equal("because\n", v.body.value)
  end)
end)

describe("yamlcamel.decode tags composed with anchors", function()
  it("anchors a tagged value and resolves the alias to the same wrapper", function()
    local v = yamlcamel.decode("a: &x !Point 1,2\nb: *x\n")
    assert.is_true(yamlcamel.is_tagged(v.b))
    assert.are.equal("!Point", v.b.tag)
    assert.are.equal(v.a, v.b)
  end)

  it("accepts the tag and the anchor in either order", function()
    local v = yamlcamel.decode("--- !Point &x 1,2")
    assert.is_true(yamlcamel.is_tagged(v))
    assert.are.equal("!Point", v.tag)
  end)

  it("resolves !!str tagging a flow mapping key the plain way, same as any other value", function()
    local v = yamlcamel.decode("--- {!!str a: 1}")
    assert.are.equal(1, v.a)
  end)
end)

describe("yamlcamel.decode %TAG directives across a multi-document stream", function()
  it("does not carry a handle from one document into the next", function()
    local docs = yamlcamel.decode_all("%TAG !e! tag:example.com,2000:\n---\n!e!custom hi\n---\nplain\n")
    assert.are.equal(2, #docs)
    assert.are.equal("tag:example.com,2000:custom", docs[1].tag)
    assert.are.equal("plain", docs[2])
  end)

  it("raises when a second document reuses a handle only the first one declared", function()
    assert.has_error(function()
      yamlcamel.decode_all("%TAG !e! tag:example.com,2000:\n---\na: 1\n---\nb: !e!custom hi\n")
    end)
  end)
end)

describe("yamlcamel.decode malformed directives", function()
  it("raises on a %TAG line with a handle that is not !, !!, or !name!", function()
    assert.has_error(function() yamlcamel.decode("%TAG e! tag:example.com,2000:\n---\na: 1\n") end)
  end)

  it("raises on a %TAG prefix longer than the ceiling, before it is ever registered", function()
    local limits = require("yamlcamel.limits")
    local text = "%TAG ! " .. string.rep("a", limits.MAX_TAG_PREFIX_BYTES + 1) .. "\n---\na: 1\n"
    local ok, err = pcall(yamlcamel.decode, text)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
    assert.is_truthy(tostring(err):find("%TAG prefix", 1, true))
  end)

  it("still accepts a %TAG prefix right at the ceiling", function()
    local limits = require("yamlcamel.limits")
    local text = "%TAG ! " .. string.rep("a", limits.MAX_TAG_PREFIX_BYTES) .. "\n---\n!x hi\n"
    local v = yamlcamel.decode(text)
    assert.is_true(yamlcamel.is_tagged(v))
    assert.are.equal("hi", v.value)
  end)

  it("rejects an oversized %TAG prefix quickly rather than paying for every later use of it", function()
    -- A one-megabyte prefix used three thousand times over a one-megabyte document used to
    -- cost about five seconds of CPU, since every use re-concatenated the whole prefix onto
    -- its own suffix. The prefix is now bounded before it is registered at all, so a
    -- document built the same way fails in well under a second instead.
    local lines = { "%TAG ! " .. string.rep("a", 1000000), "---" }
    for i = 1, 3000 do lines[#lines + 1] = "- !x v" .. i end
    local text = table.concat(lines, "\n") .. "\n"

    local t0 = os.clock()
    local ok, err = pcall(yamlcamel.decode, text)
    local elapsed = os.clock() - t0

    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("%TAG prefix", 1, true))
    assert.is_true(elapsed < 2, "took " .. elapsed .. "s")
  end)

  -- 6.8.1: "A YAML processor should ignore unknown directives with an
  -- appropriate warning." %YAML and %TAG are the only two this library
  -- knows the grammar of, so anything else is tolerated, not an error.
  it("tolerates an unrecognized % directive rather than raising", function()
    local v = yamlcamel.decode("%NOPE 1\n---\na: 1\n")
    assert.are.equal(1, v.a)
  end)

  it("still raises on a malformed %YAML directive", function()
    assert.has_error(function() yamlcamel.decode("%YAML oops\n---\na: 1\n") end)
  end)
end)

describe("yamlcamel.encode a tagged value", function()
  it("round-trips a tagged scalar", function()
    local text = yamlcamel.encode(yamlcamel.tagged("!Point", "1,2"))
    local v = yamlcamel.decode(text)
    assert.is_true(yamlcamel.is_tagged(v))
    assert.are.equal("!Point", v.tag)
    assert.are.equal("1,2", v.value)
  end)

  it("round-trips a tagged mapping nested under a key", function()
    local text = yamlcamel.encode({ point = yamlcamel.tagged("!Point", { x = 1, y = 2 }) })
    local v = yamlcamel.decode(text)
    assert.is_true(yamlcamel.is_tagged(v.point))
    assert.are.equal(1, v.point.value.x)
  end)

  it("still quotes a tagged string that would otherwise resolve as another type", function()
    local text = yamlcamel.encode(yamlcamel.tagged("!Weird", "42"))
    assert.are.equal("--- !Weird '42'\n", text)
  end)
end)
