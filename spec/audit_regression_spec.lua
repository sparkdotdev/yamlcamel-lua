local y = require("yamlcamel")
local limits = require("yamlcamel.limits")
local compression = require("yamlcamel.io.compression").default
local function stream(text, chunk_size)
  local pos, out = 1, {}
  local file = { open_read = function() return {
    read = function(_, n)
      if pos > #text then return nil end
      local part = text:sub(pos, pos + n - 1); pos = pos + #part; return part
    end,
    close = function() end,
  } end }
  y.decode_file_stream("synthetic", function(v) out[#out + 1] = v end, {file=file, chunk_size=chunk_size})
  return out
end

describe("input integrity and numeric round trips", function()
  it("refuses trailing content after a root sequence", function()
    for _, text in ipairs({"- 1\nkey: ignored\n", "a:\n  - 1\n  trailing: ignored\n"}) do
      assert.has_error(function() y.decode(text) end)
    end
  end)
  it("preserves doubles and signed zero exactly", function()
    for _, n in ipairs({1.2345678901234567, 2.2250738585072014e-308, 1e20, 1.0, -0.0}) do
      local back = y.decode(y.encode(n))
      assert.are.equal(n, back)
      assert.are.equal("float", math.type(back))
      assert.are.equal(1/n, 1/back)
    end
  end)
  it("preserves quoted and byte-order-mark keys", function()
    for _, key in ipairs({"a 'b", 'a "b', utf8.char(0xFEFF).."value"}) do
      assert.are.equal(1, y.decode(y.encode({[key]=1}))[key])
    end
  end)
  it("bounds numeric conversion without treating long numeric strings as numbers", function()
    assert.has_error(function() y.decode(string.rep("9", limits.MAX_NUMBER_DIGITS+1)) end)
    local text = string.rep("9", limits.MAX_NUMBER_DIGITS+1)
    assert.are.equal(text, y.decode(y.encode(text)))
    assert.are.equal(text, y.decode("!!str "..text))
    assert.has_error(function() y.decode(string.rep("x",limits.MAX_INPUT_BYTES+1)) end)
  end)
  it("bounds output while walking an alias-expanded mapping", function()
    local old = limits.MAX_OUTPUT_BYTES
    limits.MAX_OUTPUT_BYTES = 100
    local ok, err = pcall(y.encode, {a=string.rep("x",200)})
    limits.MAX_OUTPUT_BYTES = old
    assert.is_false(ok)
    assert.is_truthy(tostring(err):find("output exceeds",1,true))
  end)
  it("scans many short flow tags without copying all remaining text", function()
    local text = "["..string.rep("!t x,",40000).."]"
    local started = os.clock()
    assert.are.equal(40000,#y.decode(text))
    assert.is_true(os.clock()-started < 3)
  end)
  it("preserves block and quoted scalar content at every stream split", function()
    for _, text in ipairs({"x: |+\n  a\n\n  b\n", "x: >-\n  a\n\n  b", "x: \"a\n\n  b\"", "%TAG !t! tag:example.test,2026:\n---\nx: !t!kind value\n"}) do
      local whole = y.decode_all(text)
      for _, size in ipairs({1,2,7,65536}) do assert.are.same(whole,stream(text,size)) end
    end
    assert.are.equal("a",y.decode("x: |\n  a").x)
    assert.are.equal("a\n",y.decode("x: |+\n  a\n").x)
  end)
  it("escapes nonprintable Unicode values", function()
    for _,code in ipairs({0x80,0x9f,0xfffe,0xffff}) do
      local value=utf8.char(code)
      local text=y.encode(value)
      assert.is_truthy(text:find("\\u",1,true))
      assert.are.equal(value,y.decode(text))
    end
  end)
  it("applies the requested response bound in the transport", function()
    local request
    local transport = {request=function(req) request=req;return {status=200,headers={["content-type"]="application/yaml"},body="1"} end}
    assert.are.equal(1,y.http_get("https://example.invalid",{transport=transport,max_response_bytes=5}))
    assert.are.equal(5,request.max_response_bytes)
  end)
  it("validates gzip members and suffixes across all push boundaries", function()
    local first = assert(compression.compress("a: 1\n"))
    local second = assert(compression.compress("b: 2\n"))
    local bytes = first..second
    for split=0,#bytes do
      local d=compression.new_decompressor()
      local a=assert(d:push(bytes:sub(1,split)))
      local b=assert(d:push(bytes:sub(split+1)))
      assert.are.equal("a: 1\nb: 2\n",a..b..assert(d:finish()))
    end
    for _,suffix in ipairs({"admin: true\n",second:sub(1,-3)}) do
      local text = compression.decompress(first..suffix)
      assert.is_nil(text)
    end
  end)
  it("bounds plain file reads before holding the full file", function()
    local old, read_bytes, closed = limits.MAX_INPUT_BYTES, 0, false
    limits.MAX_INPUT_BYTES = 64
    local file={open_read=function() return {
      read=function(_,n) read_bytes=read_bytes+n;return string.rep("x",n) end,
      close=function() closed=true end,
    } end}
    local ok=pcall(y.decode_file,"synthetic",{file=file})
    limits.MAX_INPUT_BYTES=old
    assert.is_false(ok)
    assert.is_true(closed)
    assert.is_true(read_bytes<=65)
  end)
  it("closes a gzip file if the injected codec cannot start", function()
    local closed=false
    local file={open_read=function() return {close=function() closed=true end} end}
    local codec={new_decompressor=function() error("codec unavailable") end}
    assert.has_error(function() y.decode_gzip_file("synthetic",{file=file,compression=codec}) end)
    assert.is_true(closed)
  end)

  it("distinguishes printable raw contexts from quoted JSON characters", function()
    for _,code in ipairs({0x7f,0x80,0x9f,0xfffe,0xffff}) do
      local raw=utf8.char(code)
      for _,input in ipairs({raw,"key: "..raw,"key: |\n  "..raw.."\n","# "..raw,"&a"..raw.." value","!tag"..raw.." value","%TAG !t! tag:"..raw.."\n---\nvalue"}) do
        assert.has_error(function() y.decode(input) end)
      end
      assert.are.equal(raw,y.decode('"'..raw..'"'))
      assert.are.equal(raw,y.decode("'"..raw.."'"))
      assert.are.equal(raw,y.decode(string.format('"\\u%04X"',code)))
    end
    assert.are.equal("a"..utf8.char(0x85).."b",y.decode("a"..utf8.char(0x85).."b"))
  end)
  it("keeps tabs as block content after explicit indentation", function()
    assert.are.equal("\tcontent\n",y.decode("key: |2\n  \tcontent\n").key)
    assert.are.equal("\t\n",y.decode("key: |2+\n  \t\n").key)
  end)

  it("counts actual block breaks while ignoring unterminated EOF indentation", function()
    for _,style in ipairs({"|",">"}) do
      for _,chomp in ipairs({"","+","-"}) do
        local head="key: "..style..chomp.."\n"
        assert.are.equal("a",y.decode(head.."  a").key)
        assert.are.equal(chomp=="+" and "a\n\n" or chomp=="-" and "a" or "a\n",y.decode(head.."  a\n\n  ").key)
        assert.are.equal("",y.decode(head.."  ").key)
      end
    end
  end)

end)
