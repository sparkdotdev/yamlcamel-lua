-- One case per problem an adversarial fuzzing pass turned up: input built
-- to crash the parser, hang it, or make it hand back a value that is not
-- what the document says. Each of these either raised something other than
-- a yamlcamel error, ran until it was killed, or silently dropped data
-- before the fix that goes with it.
--
-- The few timing assertions here are deliberately loose. Every one of them
-- covers something that used to be quadratic and took minutes, or did not
-- finish at all, where the same input now takes milliseconds; the ceiling
-- is set high enough that a slow machine never trips it and low enough
-- that reintroducing the quadratic does.
local yamlcamel = require("yamlcamel")
local limits = require("yamlcamel.limits")

local function timed(fn)
  local t0 = os.clock()
  fn()
  return os.clock() - t0
end

describe("a byte stream that is not a legal YAML stream", function()
  it("rejects the block scalar sentinel byte rather than letting it forge a reference", function()
    -- 0x01 is what the tokenizer builds its block scalar sentinel from, so
    -- an input carrying one used to make the whole "a:" entry disappear.
    assert.has_error(function() yamlcamel.decode("a: \0011\1\nb: keep\n") end)
  end)

  it("rejects a sentinel byte aimed at another node's block scalar body", function()
    -- This one used to hand `leak` the body of `secret`, and the same
    -- trick reached across a document boundary in a stream.
    assert.has_error(function()
      yamlcamel.decode("secret: |\n  TOPSECRET\nleak: \0011\1\n")
    end)
    assert.has_error(function()
      yamlcamel.decode_all("secret: |\n  TOPSECRET\n---\nleak: \0011\1\n")
    end)
  end)

  it("rejects an embedded NUL byte", function()
    assert.has_error(function() yamlcamel.decode("a: b\0c\n") end)
    assert.has_error(function() yamlcamel.decode("\0: 1\n") end)
  end)

  it("rejects other C0 control bytes but keeps tab, newline and carriage return", function()
    assert.has_error(function() yamlcamel.decode("a: b\27c\n") end)
    assert.has_error(function() yamlcamel.decode("a: b\127c\n") end)
    assert.are.equal("b\tc", yamlcamel.decode("a: b\tc\n").a)
    assert.are.equal(1, yamlcamel.decode("a: 1\r\n").a)
  end)

  it("rejects malformed UTF-8", function()
    assert.has_error(function() yamlcamel.decode("a: \255\254\n") end)         -- stray bytes
    assert.has_error(function() yamlcamel.decode("a: \192\175\n") end)         -- overlong "/"
    assert.has_error(function() yamlcamel.decode("a: \237\160\128\n") end)     -- lone surrogate
    assert.has_error(function() yamlcamel.decode("a: \244\144\128\128\n") end) -- past U+10FFFF
    assert.are.equal("\195\169\228\184\173", yamlcamel.decode("a: \195\169\228\184\173\n").a)
  end)

  it("strips a byte order mark instead of gluing it onto the first key", function()
    local v = yamlcamel.decode("\239\187\191admin: true\n")
    assert.is_true(v.admin)
    assert.is_nil(v["\239\187\191admin"])
  end)
end)

describe("nesting deeper than the ceiling", function()
  it("raises on a deep flow sequence rather than overflowing Lua's stack", function()
    local text = string.rep("[", 200000) .. string.rep("]", 200000)
    local ok, err = pcall(yamlcamel.decode, text)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
    assert.is_truthy(tostring(err):find("nests deeper", 1, true))
  end)

  it("raises on a deep flow mapping", function()
    local text = string.rep("{a: ", 200000) .. "1" .. string.rep("}", 200000)
    assert.has_error(function() yamlcamel.decode(text) end)
  end)

  it("raises on compact sequence markers instead of allocating a gigabyte", function()
    -- 32000 of these is 64 kB of input and used to reach about 990 MB of
    -- Lua heap, since every level held its own copy of the rest of the line.
    assert.has_error(function() yamlcamel.decode(string.rep("- ", 32000) .. "x\n") end)
  end)

  it("raises on compact explicit key markers", function()
    assert.has_error(function() yamlcamel.decode(string.rep("? ", 16000) .. "x\n") end)
  end)

  it("raises on a long run of explicit value markers quickly", function()
    local text = "a: " .. string.rep(": ", 500000) .. "b\n"
    local elapsed = timed(function()
      assert.has_error(function() yamlcamel.decode(text) end)
    end)
    assert.is_true(elapsed < 5, "took " .. elapsed .. "s")
  end)

  it("raises on a block sequence nested past the ceiling by indentation", function()
    local lines = {}
    for i = 0, 1000 do lines[#lines + 1] = string.rep("  ", i) .. "- " end
    assert.has_error(function() yamlcamel.decode(table.concat(lines, "\n") .. "\n") end)
  end)

  it("still decodes a document nested well inside the ceiling", function()
    local depth = 50
    local text = string.rep("[", depth) .. "1" .. string.rep("]", depth)
    local v = yamlcamel.decode(text)
    for _ = 1, depth - 1 do v = v[1] end
    assert.are.same({ 1 }, v)
    assert.is_true(limits.MAX_DEPTH > depth)
  end)
end)

describe("an unbalanced bracket or quote inside a plain scalar", function()
  it("does not swallow the lines under a mapping entry", function()
    local v = yamlcamel.decode("name: foo[bar\nadmin: true\nrole: user\n")
    assert.are.equal("foo[bar", v.name)
    assert.is_true(v.admin)
    assert.are.equal("user", v.role)
  end)

  it("does not swallow the items under a sequence entry", function()
    local v = yamlcamel.decode("- foo{bar\n- second\n- third\n")
    assert.are.same({ "foo{bar", "second", "third" }, v)
  end)

  it("does not swallow the lines under a scalar carrying a lone apostrophe", function()
    local v = yamlcamel.decode("a: it 'was\nb: fine' now\n")
    assert.are.equal("it 'was", v.a)
    assert.are.equal("fine' now", v.b)
  end)

  it("still reads a flow collection that really does wrap onto later lines", function()
    assert.are.same({ 1, 2, 3 }, yamlcamel.decode("a: [1,\n 2,\n 3]\n").a)
    assert.are.same({ x = 1, y = 2 }, yamlcamel.decode("a: {x: 1,\n y: 2}\n").a)
  end)

  it("still reads a quoted scalar that really does wrap onto later lines", function()
    assert.are.equal("one two", yamlcamel.decode('a: "one\n  two"\n').a)
    assert.are.equal("one two", yamlcamel.decode("a: 'one\n  two'\n").a)
  end)
end)

describe("a malformed escape in a double-quoted scalar", function()
  it("raises a yamlcamel error rather than a Lua one", function()
    for _, text in ipairs({
      'a: "\\x"\n', 'a: "\\xZZ"\n', 'a: "\\uZZZZ"\n', 'a: "\\UZZZZZZZZ"\n',
      'a: "\\x-1"\n', 'a: "\\u-100"\n',
    }) do
      local ok, err = pcall(yamlcamel.decode, text)
      assert.is_false(ok, text)
      assert.is_truthy(tostring(err):find("yamlcamel:", 1, true), text .. " -> " .. tostring(err))
    end
  end)

  it("raises for a code point outside Unicode or inside the surrogate range", function()
    assert.has_error(function() yamlcamel.decode('a: "\\UFFFFFFFF"\n') end)
    assert.has_error(function() yamlcamel.decode('a: "\\U7FFFFFFF"\n') end)
    assert.has_error(function() yamlcamel.decode('a: "\\ud800"\n') end)
    assert.has_error(function() yamlcamel.decode('a: "\\udfff"\n') end)
  end)

  it("still reads the escapes that are legal", function()
    assert.are.equal("A", yamlcamel.decode('a: "\\x41"\n').a)
    assert.are.equal("\195\169", yamlcamel.decode('a: "\\u00e9"\n').a)
    assert.are.equal("\240\159\152\128", yamlcamel.decode('a: "\\U0001F600"\n').a)
  end)
end)

describe("a plain scalar that only looks like a number", function()
  it("resolves a long run of digits followed by a letter without backtracking", function()
    -- The float grammar used to be matched with a pattern holding two
    -- "%d*" runs, which Lua retries at every split: 50 kB of this did not
    -- finish inside five seconds.
    local text = "a: " .. string.rep("9", 200000) .. "x\n"
    local value
    local elapsed = timed(function() value = yamlcamel.decode(text).a end)
    assert.are.equal(string.rep("9", 200000) .. "x", value)
    assert.is_true(elapsed < 5, "took " .. elapsed .. "s")
  end)

  it("resolves the same shape ending in an exponent marker or a sign", function()
    for _, tail in ipairs({ "e", "-", "+", "E-", "." }) do
      local text = "a: " .. string.rep("9", 100000) .. tail .. "\n"
      local elapsed = timed(function()
        if tail == "." then assert.has_error(function() yamlcamel.decode(text) end)
        else yamlcamel.decode(text) end
      end)
      assert.is_true(elapsed < 5, tail .. " took " .. elapsed .. "s")
    end
  end)

  it("degrades a hex or octal literal too big for a 64-bit integer to a float, not a wrapped one", function()
    -- Lua's own tonumber wraps a hex or octal literal through 64 bits rather than rejecting
    -- or degrading it the way it does a decimal one: tonumber("0x" .. ("f"):rep(40)) reads
    -- back as the same Lua integer, -1, that a genuine 64-bit all-ones pattern produces, with
    -- no way afterward to tell an honest bit pattern apart from a wraparound that erased
    -- everything past the first 16 digits.
    local v = yamlcamel.decode("a: 0x" .. string.rep("f", 40) .. "\n")
    assert.are.equal("number", type(v.a))
    assert.are.equal("float", math.type(v.a))
    assert.is_true(v.a > 1e30)

    v = yamlcamel.decode("a: 0x10000000000000000\n") -- 2^64 exactly, one past the 64-bit ceiling
    assert.are.equal("float", math.type(v.a))
    assert.is_true(v.a > 1.8e19)

    v = yamlcamel.decode("a: 0o" .. string.rep("7", 30) .. "\n")
    assert.are.equal("float", math.type(v.a))
    assert.is_true(v.a > 1e26)
  end)

  it("keeps unsigned radix magnitudes positive beyond the signed integer range", function()
    assert.is_true(yamlcamel.decode("a: 0x" .. string.rep("f", 16) .. "\n").a > 1.8e19)
    assert.is_true(yamlcamel.decode("a: 0o1777777777777777777777\n").a > 1.8e19)
    assert.are.equal(1, yamlcamel.decode("a: 0x0000000000000001\n").a)
    assert.are.equal(9223372036854775807, yamlcamel.decode("a: 0x7FFFFFFFFFFFFFFF\n").a)
  end)

  it("still resolves every core schema number form", function()
    local v = yamlcamel.decode(
      "a: 42\nb: -7\nc: 3.5\nd: .5\ne: 5.\nf: 1.5e-3\ng: 2E4\nh: 0x1f\ni: 0o17\n")
    assert.are.equal(42, v.a)
    assert.are.equal(-7, v.b)
    assert.are.equal(3.5, v.c)
    assert.are.equal(0.5, v.d)
    assert.are.equal(5.0, v.e)
    assert.are.equal(0.0015, v.f)
    assert.are.equal(20000.0, v.g)
    assert.are.equal(31, v.h)
    assert.are.equal(15, v.i)
    assert.are.equal("1.2.3", yamlcamel.decode("a: 1.2.3\n").a)
    assert.are.equal("e5", yamlcamel.decode("a: e5\n").a)
  end)
end)

describe("a line carrying a long run of whitespace", function()
  it("trims it without retrying the pattern at every position", function()
    -- 125 kB of this never finished when the tokenizer trimmed with
    -- "^%s*(.-)%s*$".
    for _, text in ipairs({
      "a: x" .. string.rep(" ", 500000) .. "y\n",
      "[x" .. string.rep(" ", 500000) .. "y]\n",
      string.rep(" ", 200000) .. "a: 1\n",
    }) do
      local elapsed = timed(function() yamlcamel.decode(text) end)
      assert.is_true(elapsed < 5, "took " .. elapsed .. "s")
    end
  end)

  it("still trims an ordinary line the same way it always did", function()
    assert.are.equal("x  y", yamlcamel.decode("a:    x  y   \n").a)
  end)
end)

describe("a scalar or collection wrapped across many physical lines", function()
  it("gathers it in one pass rather than one concatenation per line", function()
    -- All three of these used to build their line up by concatenation,
    -- which is quadratic in the total length: the plain one took 12.4 s
    -- over 3.4 MB.
    local plain = "a: start\n" .. string.rep("  more words here\n", 200000)
    local quoted = 'a: "start\n' .. string.rep("more\n", 200000) .. 'end"\n'
    local flow = "a: [\n" .. string.rep("1,\n", 200000) .. "]\n"
    for _, text in ipairs({ plain, quoted, flow }) do
      local elapsed = timed(function() yamlcamel.decode(text) end)
      assert.is_true(elapsed < 10, "took " .. elapsed .. "s")
    end
  end)
end)

describe("a block scalar header behind a long run of compact markers", function()
  it("finds the key's column by walking the line once", function()
    -- Every one of these markers moves the column the block is measured
    -- from, and reading that column by re-measuring the rest of the line
    -- per marker is quadratic in the line's own length.
    local text = string.rep("- ", 100000) .. "a: |\n"
    local elapsed = timed(function() pcall(yamlcamel.decode, text) end)
    assert.is_true(elapsed < 5, "took " .. elapsed .. "s")
  end)
end)

describe("yamlcamel.encode against a value that came out of a hostile document", function()
  it("quotes a string carrying a flow indicator so its siblings survive", function()
    local text = yamlcamel.encode({ ["x [y"] = "1", z = "2" })
    local back = yamlcamel.decode(text)
    assert.are.equal("1", back["x [y"])
    assert.are.equal("2", back.z)

    back = yamlcamel.decode(yamlcamel.encode({ ["a}"] = "1", b = "2" }))
    assert.are.equal("1", back["a}"])
    assert.are.equal("2", back.b)
  end)

  it("escapes a control character rather than writing the sentinel byte bare", function()
    local text = yamlcamel.encode({ a = "\0011\1" })
    assert.is_nil(text:find("\1", 1, true))
    assert.are.equal("\0011\1", yamlcamel.decode(text).a)
  end)

  it("raises for a string that is not valid UTF-8 instead of writing an unreadable document", function()
    assert.has_error(function() yamlcamel.encode({ a = "\255" }) end)
  end)

  it("raises rather than expanding an alias bomb forever", function()
    -- 272 bytes in, and encoding the decoded shape used to take 6.8 s and
    -- 200 MB, since every alias resolves to the same table and the emitter
    -- walks each reference separately.
    local lines = { "a0: &a0 [lol]" }
    for i = 1, 11 do
      local refs = {}
      for _ = 1, 4 do refs[#refs + 1] = "*a" .. (i - 1) end
      lines[#lines + 1] = "a" .. i .. ": &a" .. i .. " [" .. table.concat(refs, ",") .. "]"
    end
    local value = yamlcamel.decode(table.concat(lines, "\n") .. "\n")
    local ok, err = pcall(yamlcamel.encode, value)
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("yamlcamel:", 1, true))
  end)

  it("raises for a table nested past the ceiling", function()
    local root = {}
    local node = root
    for _ = 1, limits.MAX_DEPTH + 10 do
      local child = {}
      node.next = child
      node = child
    end
    node.leaf = 1
    assert.has_error(function() yamlcamel.encode(root) end)
  end)

  it("writes a decoded tag back in a form that reads as a tag again", function()
    for _, text in ipairs({
      "a: !!custom hello\n",
      "a: !<tag:example.com,2000:thing> hello\n",
      "a: !Point hello\n",
    }) do
      local v = yamlcamel.decode(text)
      local back = yamlcamel.decode(yamlcamel.encode(v))
      assert.is_true(yamlcamel.is_tagged(back.a), text)
      assert.are.equal(v.a.tag, back.a.tag)
      assert.are.equal("hello", back.a.value)
    end
  end)
end)
