-- Encodes a Lua value as a YAML document: block style throughout, one value
-- per line, nesting by indentation. A table is a sequence when its keys are
-- exactly 1..n with no gaps and nothing else; otherwise it is a mapping.
local scalar = require("yamlcamel.scalar")
local null = require("yamlcamel.null")
local tags = require("yamlcamel.tags")
local limits = require("yamlcamel.limits")
local charset = require("yamlcamel.charset")

local M = {}

-- An empty Lua table cannot say whether it was a sequence or a mapping.
-- Left plain, it encodes as an empty sequence; wrap it in this to force an
-- empty mapping instead.
M.EMPTY_MAPPING = setmetatable({}, { __tostring = function() return "yaml.empty_mapping" end })

local function indent_of(n)
  return string.rep("  ", n)
end

-- The length of `t` read as an array (keys exactly 1..n), or nil when it
-- holds a non-integer key, a gap, or nothing at all. Emptiness is handled
-- separately by the caller, since an empty table is genuinely ambiguous.
local function array_length(t)
  local n = 0
  local any = false
  for k in pairs(t) do
    any = true
    if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then return nil end
    if k > n then n = k end
  end
  if not any then return nil end
  for i = 1, n do
    if t[i] == nil then return nil end
  end
  return n
end

local function format_number(n)
  if n ~= n then return ".nan" end
  if n == math.huge then return ".inf" end
  if n == -math.huge then return "-.inf" end
  if math.type and math.type(n) == "integer" then return tostring(n) end
  if n == 0 and 1 / n < 0 then return "-0.0" end
  local text = string.format("%.17g", n)
  if not text:find("[%.eE]") then text = text .. ".0" end
  return text
end

-- True when `s`, written bare, would not read back as itself: it looks like
-- null, a boolean or a number, it carries YAML's own punctuation, or it has
-- leading/trailing whitespace a bare scalar would lose.
local function needs_quoting(s)
  if s == "" then return true end
  local ok, resolved = pcall(scalar.resolve, s)
  if not ok or resolved ~= s then return true end
  if s:match("^%s") or s:match("%s$") then return true end
  if s:match("[\n\t]") then return true end
  if s:match(":%s") or s:match(":$") then return true end
  if s:match("%s#") then return true end
  if s:match("^[%-%?:,%[%]{}#&*!|>'\"%%@`]") then return true end
  -- A flow indicator anywhere, not only at the start: an unbalanced one
  -- mid-string is what the reader uses to decide a flow collection or a
  -- quoted scalar carries on onto the following lines, so a bare "x [y"
  -- key swallows whatever is written under it and a bare "a}" key breaks
  -- the document outright.
  if s:match("[%[%]{}\"']") or s:find(charset.BOM, 1, true) then return true end
  -- A control character is never bare either: 0x01 in particular is the
  -- sentinel the reader hides a block scalar body behind, so writing one
  -- unescaped hands the reader a forged reference.
  if s:match("[%z\1-\31\127]") then return true end
  for _, code in utf8.codes(s) do
    if (code >= 0x80 and code <= 0x9f and code ~= 0x85) or code == 0xfffe or code == 0xffff then return true end
  end
  return false
end

local DOUBLE_ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }

local function needs_unicode_escape(code)
  return (code >= 0x80 and code <= 0x9f and code ~= 0x85) or code == 0xfffe or code == 0xffff or code == 0xfeff
end
local function encode_double_quoted(s)
  local out = {}
  for _, code in utf8.codes(s) do
    local c = utf8.char(code)
    if DOUBLE_ESCAPES[c] then out[#out + 1] = DOUBLE_ESCAPES[c]
    elseif code < 0x20 or code == 0x7f then out[#out + 1] = string.format("\\x%02X", code)
    elseif needs_unicode_escape(code) then out[#out + 1] = string.format("\\u%04X", code)
    else out[#out + 1] = c end
  end
  return '\"' .. table.concat(out) .. '\"'
end

-- Control characters need a double-quoted escape; everything else that needs
-- quoting at all can use the plainer single-quoted style.
local function encode_string(s)
  -- A Lua string is bytes, and bytes that are not valid UTF-8 have no
  -- spelling in a YAML stream (5.1), so writing them would produce a
  -- document decode then refuses to read. Say so here instead.
  if not charset.is_valid_utf8(s) then
    error("yamlcamel: cannot encode a string that is not valid UTF-8")
  end
  if not needs_quoting(s) then return s end
  if s:match("[%z\1-\31\127]") then return encode_double_quoted(s) end
  for _, code in utf8.codes(s) do
    if needs_unicode_escape(code) then return encode_double_quoted(s) end
  end
  return "'" .. s:gsub("'", "''") .. "'"
end

-- A tagged value's tag, spelled the way a document writes one. decode hands
-- back the tag EXPANDED ("!!str" arrives as "tag:yaml.org,2002:str"), so
-- writing `.tag` straight out is only right for the local form that expands
-- to itself; anything else has to go back into the verbatim `!<...>` form
-- or it reads back as ordinary scalar text rather than as a tag at all.
local function tag_prefix(tag)
  if type(tag) ~= "string" or tag == "" or tag:match("%s") then
    error("yamlcamel: cannot encode " .. tostring(tag) .. " as a tag")
  end
  if tag:sub(1, 1) == "!" then return tag end
  if tag:find(">", 1, true) then
    error("yamlcamel: cannot encode a tag holding '>': " .. tag)
  end
  return "!<" .. tag .. ">"
end

local function emit_scalar(value)
  if value == nil or value == null then return "null" end
  local t = type(value)
  if t == "boolean" then return tostring(value) end
  if t == "number" then return format_number(value) end
  if t == "string" then return encode_string(value) end
  error("yamlcamel: cannot encode a " .. t .. " value")
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

local emit_mapping_lines, emit_sequence_lines

-- Tables currently being walked into, so a decoded structure that aliased
-- itself into a cycle (now possible now that decode understands &/*)
-- raises a clear error instead of recursing forever. Reset at the start of
-- every {M.encode} call.
local visiting

-- Values written so far by the encode call in progress, checked against
-- {yamlcamel.limits}.MAX_EMIT_NODES. An alias decodes to the very same
-- table it points at, so a document that references one anchor from
-- several places costs nothing to read and then costs the emitter a
-- separate full walk per reference, which is the alias expansion bomb
-- arriving one step later than usual.
local emitted
local output_bytes
local function append_line(out, text)
  output_bytes = output_bytes + #text + 1
  if output_bytes > limits.MAX_OUTPUT_BYTES then
    error("yamlcamel: output exceeds " .. limits.MAX_OUTPUT_BYTES .. " bytes")
  end
  out[#out + 1] = text
end

-- Appends the line(s) for one entry: `prefix` is "key:" or "-", already
-- indented. A scalar or an empty collection stays on that same line; any
-- other table becomes a nested block on the lines that follow, one level
-- deeper, which is plain enough to parse back and does not depend on the
-- Psych same-indentation quirk this library reads but never writes. A
-- yamlcamel.tagged wrapper inserts its tag right after `prefix`, then
-- encodes its own inner value exactly the same way as an untagged one.
local function append_entry(out, prefix, value, indent)
  emitted = emitted + 1
  if emitted > limits.MAX_EMIT_NODES then
    error("yamlcamel: value expands to more than " .. limits.MAX_EMIT_NODES .. " nodes to encode")
  end
  if indent > limits.MAX_DEPTH then
    error("yamlcamel: value nests deeper than " .. limits.MAX_DEPTH .. " levels")
  end

  if tags.is_tagged(value) then
    prefix = prefix .. " " .. tag_prefix(value.tag)
    value = value.value
  end

  if value == nil or value == null then
    append_line(out, prefix .. " null")
    return
  end
  if type(value) ~= "table" then
    append_line(out, prefix .. " " .. emit_scalar(value))
    return
  end

  if value == M.EMPTY_MAPPING then
    append_line(out, prefix .. " {}")
    return
  end
  if next(value) == nil then
    append_line(out, prefix .. " []")
    return
  end

  if visiting[value] then
    error("yamlcamel: cannot encode a cyclic structure")
  end
  visiting[value] = true

  append_line(out, prefix)
  local len = array_length(value)
  local nested = len and emit_sequence_lines(value, indent + 1) or emit_mapping_lines(value, indent + 1)
  for _, line in ipairs(nested) do
    out[#out + 1] = line
  end

  visiting[value] = nil
end

function emit_mapping_lines(t, indent)
  local out = {}
  for _, k in ipairs(sorted_keys(t)) do
    local prefix = indent_of(indent) .. (k == null and "null" or encode_string(tostring(k))) .. ":"
    append_entry(out, prefix, t[k], indent)
  end
  return out
end

function emit_sequence_lines(t, indent)
  local out = {}
  local n = array_length(t) or 0
  for i = 1, n do
    append_entry(out, indent_of(indent) .. "-", t[i], indent)
  end
  return out
end

-- Encodes any supported value as a complete YAML document, "---" marker
-- included (plus a root-level tag right after it, for a yamlcamel.tagged
-- value; note a *collection* root that's tagged this way can't actually
-- be read back, the same limitation a root-level anchor has, since there
-- is nowhere on the "---" line's own indentation to attach it to a block
-- that starts on the next line). A table with an integer key run of 1..n
-- is a sequence; any other table is a mapping; everything else is a scalar.
local function encode_document(value)
  emitted = 1
  if emitted > limits.MAX_EMIT_NODES then error("yamlcamel: value exceeds emit node limit") end
  output_bytes = 4 -- the document marker and newline
  local prefix = "---"
  if tags.is_tagged(value) then
    prefix = prefix .. " " .. tag_prefix(value.tag)
    value = value.value
  end

  if value == nil or value == null then return prefix .. " null\n" end

  if type(value) == "table" then
    if value == M.EMPTY_MAPPING then return prefix .. " {}\n" end
    if next(value) == nil then return prefix .. " []\n" end

    visiting = { [value] = true }
    local len = array_length(value)
    local lines = len and emit_sequence_lines(value, 0) or emit_mapping_lines(value, 0)
    return prefix .. "\n" .. table.concat(lines, "\n") .. "\n"
  end

  return prefix .. " " .. emit_scalar(value) .. "\n"
end

function M.encode(value)
  local text = encode_document(value)
  if #text > limits.MAX_OUTPUT_BYTES then
    error("yamlcamel: output exceeds " .. limits.MAX_OUTPUT_BYTES .. " bytes")
  end
  return text
end

-- Encodes `values` (a Lua array) as a stream of that many `---`-separated
-- documents. Each call to {M.encode} already starts with its own "---",
-- so concatenating them is already an unambiguous multi-document stream;
-- no explicit "..." separator is needed between them.
function M.encode_all(values)
  local parts, total = {}, 0
  for i, value in ipairs(values) do
    parts[i] = M.encode(value)
    total = total + #parts[i]
    if total > limits.MAX_OUTPUT_BYTES then error("yamlcamel: output exceeds byte limit") end
  end
  return table.concat(parts)
end

return M
