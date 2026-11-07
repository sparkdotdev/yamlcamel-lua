-- What a YAML stream is allowed to be made of (5.1, 5.2), checked once up
-- front rather than trusted, so a malformed UTF-8 sequence, an embedded
-- NUL or any other control byte never reaches a decoded key or value.
-- Byte 0x01 matters most: yamlcamel.parser hides a resolved block scalar
-- body behind a sentinel built from it, so that byte in the input can
-- make a mapping entry disappear or hand one node another node's block
-- scalar, even across a document boundary.
local M = {}

local BOM = "\239\187\191"

-- Exposed so yamlcamel.parser can strip the same three bytes at the start of every document
-- in a stream, not only the start of the stream as a whole: 5.2 allows a byte order mark to
-- open any document, and M.check here only ever sees the whole stream's own first byte.
M.BOM = BOM

-- The C0 controls c-printable (5.1) excludes: everything below space
-- except tab, line feed and carriage return. No byte of a
-- multi-byte UTF-8 sequence can land in this range, so matching bytes
-- directly is the same answer as decoding first would give.
local FORBIDDEN = "[%z\1-\8\11\12\14-\31]"

-- Checks `text` and returns it with a leading byte order mark removed
-- (5.2: one may open a stream, and it is not part of the document that
-- follows; left in place it becomes part of the first key instead, so
-- "\239\187\191admin:" decodes to a key no caller ever looks up).
function M.check(text)
  if text:sub(1, #BOM) == BOM then text = text:sub(#BOM + 1) end

  local at = text:find(FORBIDDEN)
  if at then
    error(string.format(
      "yamlcamel: byte 0x%02X at offset %d is not allowed in a YAML stream", text:byte(at), at))
  end

  -- utf8.len in its strict (non-lax) mode is exactly the check wanted
  -- here: it rejects a truncated or stray continuation byte, an overlong
  -- encoding, a surrogate half, and anything past U+10FFFF.
  local ok, bad = utf8.len(text)
  if not ok then
    error("yamlcamel: invalid UTF-8 byte sequence at offset " .. bad)
  end

  return text
end

-- Whether `str` is something encode can legally write, the same rule read
-- back the other way: a Lua string holding bytes that are not valid UTF-8
-- has no YAML spelling in this subset, and writing it anyway would produce
-- a document decode then refuses.
function M.is_valid_utf8(str)
  return utf8.len(str) ~= nil
end

-- Quoted scalars use nb-json; every unquoted raw context uses c-printable.
function M.check_printable(text)
  for _, code in utf8.codes(text) do
    if (code >= 0x7f and code <= 0x9f and code ~= 0x85) or code == 0xfffe or code == 0xffff then
      error("yamlcamel: non-printable characters must be quoted or escaped")
    end
  end
  return text
end

return M
