-- Reads a single- or double-quoted scalar starting at the opening quote.
-- The parser joins a scalar left open across physical lines with a raw
-- newline byte per break before handing it here, so a caller never sees
-- more than one logical line; {fold_break} is what turns those back into
-- the space or literal newline YAML's own line-folding rule calls for.
local M = {}

local DOUBLE_ESCAPES = {
  ["\\"] = "\\", ['"'] = '"', ["n"] = "\n", ["t"] = "\t", ["r"] = "\r",
  ["0"] = "\0", ["a"] = "\a", ["b"] = "\b", ["f"] = "\f", ["v"] = "\v",
  ["e"] = "\27", [" "] = " ", ["/"] = "/",
}

-- The code point a \xXX, \uXXXX or \UXXXXXXXX escape names, or a raised
-- error when those digits are not there. `hex` comes straight off a fixed
-- width slice of the input, so it can be short (the scalar ended mid
-- escape), it can hold something that is not a hex digit at all, and it can
-- hold a sign; left unchecked, tonumber hands back nil or a negative and
-- the arithmetic below fails with a Lua error rather than a parse one.
local function escape_code(escape, width, hex)
  if #hex ~= width or not hex:match("^%x+$") then
    error("yamlcamel: \\" .. escape .. " needs " .. width
      .. " hex digits in a double-quoted scalar, found '" .. hex .. "'")
  end
  local code = tonumber(hex, 16)
  -- 5.1: a YAML stream is Unicode, so an escape naming something outside
  -- it, or naming half a surrogate pair, has no encoding to produce.
  if code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then
    error(string.format("yamlcamel: \\%s%s is not a Unicode code point", escape, hex))
  end
  return code
end

-- Encodes a Unicode code point as UTF-8 bytes, for \xXX, \uXXXX and \UXXXXXXXX.
local function utf8_encode(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return string.char(
      0xE0 + math.floor(code / 0x1000),
      0x80 + math.floor(code / 0x40) % 0x40,
      0x80 + code % 0x40
    )
  else
    return string.char(
      0xF0 + math.floor(code / 0x40000),
      0x80 + math.floor(code / 0x1000) % 0x40,
      0x80 + math.floor(code / 0x40) % 0x40,
      0x80 + code % 0x40
    )
  end
end

-- A run of raw newline bytes the tokenizer spliced in at a physical line
-- break inside a quoted scalar that spans more than one line (the joiner
-- the parser uses is described in yamlcamel.parser, right where it feeds a
-- multi-line quote back through {read_double}/{read_single}). YAML folds a
-- single break to a space and n breaks to n-1 literal newlines.
local function fold_break(str, i)
  local j = i
  while str:sub(j, j) == "\n" do j = j + 1 end
  local run = j - i
  return (run == 1 and " " or string.rep("\n", run - 1)), j
end

-- str[pos] is the opening double quote. Returns the resolved value and the
-- index one past the closing quote.
function M.read_double(str, pos)
  local out, i, len = {}, pos + 1, #str
  while i <= len do
    local c = str:sub(i, i)
    if c == '"' then
      return table.concat(out), i + 1
    elseif c == "\n" then
      local folded
      folded, i = fold_break(str, i)
      out[#out + 1] = folded
    elseif c == "\\" then
      local esc = str:sub(i + 1, i + 1)
      if esc == "\n" then
        -- Line continuation: the break is elided entirely, no space or newline.
        i = i + 2
      elseif esc == "x" then
        out[#out + 1] = utf8_encode(escape_code("x", 2, str:sub(i + 2, i + 3)))
        i = i + 4
      elseif esc == "u" then
        out[#out + 1] = utf8_encode(escape_code("u", 4, str:sub(i + 2, i + 5)))
        i = i + 6
      elseif esc == "U" then
        out[#out + 1] = utf8_encode(escape_code("U", 8, str:sub(i + 2, i + 9)))
        i = i + 10
      elseif DOUBLE_ESCAPES[esc] then
        out[#out + 1] = DOUBLE_ESCAPES[esc]
        i = i + 2
      else
        error("yamlcamel: unsupported escape \\" .. esc .. " in double-quoted scalar")
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  error("yamlcamel: unterminated double-quoted scalar")
end

-- str[pos] is the opening single quote. '' is the only escape, a literal '.
function M.read_single(str, pos)
  local out, i, len = {}, pos + 1, #str
  while i <= len do
    local c = str:sub(i, i)
    if c == "'" then
      if str:sub(i + 1, i + 1) == "'" then
        out[#out + 1] = "'"
        i = i + 2
      else
        return table.concat(out), i + 1
      end
    elseif c == "\n" then
      local folded
      folded, i = fold_break(str, i)
      out[#out + 1] = folded
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  error("yamlcamel: unterminated single-quoted scalar")
end

-- Folds every run of raw newline bytes in `str` per the same rule, for a
-- plain (unquoted) scalar the parser pulled continuation lines into the
-- same way.
function M.fold_line_breaks(str)
  local out, i, len = {}, 1, #str
  while i <= len do
    local c = str:sub(i, i)
    if c == "\n" then
      local folded
      folded, i = fold_break(str, i)
      out[#out + 1] = folded
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

return M
