-- Flow-style collections: `[a, b, c]` and `{a: 1, b: 2}`, nested arbitrarily.
-- Everything here stays on one line, matching the rest of this subset.
local quoted = require("yamlcamel.quoted")
local anchors = require("yamlcamel.anchors")
local props = require("yamlcamel.props")
local tags = require("yamlcamel.tags")
local null = require("yamlcamel.null")
local limits = require("yamlcamel.limits")
local whitespace = require("yamlcamel.whitespace")

local M = {}

local function skip_ws(str, i)
  while str:sub(i, i) == " " do
    i = i + 1
  end
  return i
end

-- A flow mapping key: an alias, a quoted scalar, or a plain scalar that
-- stops at ':' as well as ',' '}' ']' (the one way a key differs from an
-- ordinary flow value), optionally preceded by node properties the same
-- as any other node, even though a bare key is rarely anchored or tagged
-- in practice.
local function parse_key(str, pos)
  pos = skip_ws(str, pos)
  if str:sub(pos, pos) == "*" then
    local name, next_pos = props.read_name(str, pos + 1)
    return anchors.resolve(name), next_pos
  end

  local anchor, tag
  anchor, tag, pos = props.strip_at(str, pos)
  pos = skip_ws(str, pos)
  if str:sub(pos, pos) == "*" then
    error("yamlcamel: an alias cannot also carry an anchor or a tag: " .. str:sub(pos))
  end

  local c = str:sub(pos, pos)
  local key, next_pos
  if c == '"' then
    local str_value
    str_value, next_pos = quoted.read_double(str, pos)
    key = tags.resolve_string(tag, str_value)
  elseif c == "'" then
    local str_value
    str_value, next_pos = quoted.read_single(str, pos)
    key = tags.resolve_string(tag, str_value)
  else
    local i, len = pos, #str
    while i <= len do
      local ch = str:sub(i, i)
      if ch == ":" or ch == "," or ch == "}" or ch == "]" then break end
      i = i + 1
    end
    local text = str:sub(pos, whitespace.rstrip_to(str, pos, i - 1))
    if text == "" then error("yamlcamel: empty key in flow mapping") end
    key, next_pos = tags.resolve_plain(tag, text), i
  end
  if anchor then key = anchors.register(anchor, key) end
  return key, next_pos
end

-- One flow value: an alias, a nested collection, a quoted scalar, or a
-- plain scalar read up to the next ',', ']' or '}', optionally preceded
-- by node properties (6.9, 7.1). `as_entry`, true only for one of
-- {M.parse_sequence}'s own elements, also watches for the single-pair
-- shorthand (7.4.3): "[a: 1]" is one element holding {a = 1}, so a plain
-- scalar read this way stops early at a ':' that looks like a key
-- separator, the same way a flow mapping's own key does, and whatever
-- follows becomes the pair's value instead of a second element.
function M.parse_value(str, pos, as_entry)
  pos = skip_ws(str, pos)
  if str:sub(pos, pos) == "*" then
    local name, next_pos = props.read_name(str, pos + 1)
    return anchors.resolve(name), next_pos
  end

  local anchor, tag
  anchor, tag, pos = props.strip_at(str, pos)
  pos = skip_ws(str, pos)
  if str:sub(pos, pos) == "*" then
    error("yamlcamel: an alias cannot also carry an anchor or a tag: " .. str:sub(pos))
  end

  local c = str:sub(pos, pos)
  local value, next_pos
  if c == "[" then
    -- A placeholder is registered before recursing, not after, so a
    -- collection can alias itself from inside its own body. The depth
    -- count goes around the recursion for the same reason the block side
    -- carries one: "[" repeated far enough reaches Lua's own stack
    -- overflow, which is not an error a caller of this library can read.
    local collection
    limits.enter()
    collection, next_pos = M.parse_sequence(str, pos, anchor and anchors.register(anchor, {}) or nil)
    limits.leave()
    value = tags.resolve_collection(tag, collection)
  elseif c == "{" then
    local collection
    limits.enter()
    collection, next_pos = M.parse_mapping(str, pos, anchor and anchors.register(anchor, {}) or nil)
    limits.leave()
    value = tags.resolve_collection(tag, collection)
  elseif c == '"' then
    local str_value
    str_value, next_pos = quoted.read_double(str, pos)
    value = tags.resolve_string(tag, str_value)
  elseif c == "'" then
    local str_value
    str_value, next_pos = quoted.read_single(str, pos)
    value = tags.resolve_string(tag, str_value)
  elseif c == "" then
    error("yamlcamel: expected a value in flow collection, found end of input")
  else
    local i, len = pos, #str
    while i <= len do
      local ch = str:sub(i, i)
      if ch == "," or ch == "]" or ch == "}" then break end
      if as_entry and ch == ":" then
        local after = str:sub(i + 1, i + 1)
        if after == "" or after:match("[%s,%]}]") then break end
      end
      i = i + 1
    end
    local text = str:sub(pos, whitespace.rstrip_to(str, pos, i - 1))
    value, next_pos = tags.resolve_plain(tag, text), i
  end
  if anchor then value = anchors.register(anchor, value) end

  if as_entry then
    local after = skip_ws(str, next_pos)
    if str:sub(after, after) == ":" then
      local pair_value
      pair_value, next_pos = M.parse_value(str, skip_ws(str, after + 1))
      local pair = {}
      pair[tostring(value)] = pair_value
      value = pair
    end
  end

  return value, next_pos
end

function M.parse_sequence(str, pos, into)
  local result, i = into or {}, skip_ws(str, pos + 1)
  if str:sub(i, i) == "]" then return result, i + 1 end

  while true do
    local value
    value, i = M.parse_value(str, i, true)
    result[#result + 1] = value
    i = skip_ws(str, i)
    local c = str:sub(i, i)
    if c == "]" then
      return result, i + 1
    elseif c == "," then
      i = skip_ws(str, i + 1)
      if str:sub(i, i) == "]" then return result, i + 1 end
    else
      error("yamlcamel: expected ',' or ']' in flow sequence, found " .. (c == "" and "end of input" or c))
    end
  end
end

function M.parse_mapping(str, pos, into)
  local result, i = into or {}, skip_ws(str, pos + 1)
  if str:sub(i, i) == "}" then return result, i + 1 end

  while true do
    local key
    key, i = parse_key(str, i)
    i = skip_ws(str, i)
    local c = str:sub(i, i)
    -- "key" alone, with no ':' at all before the next ',' or '}', is a
    -- legal flow mapping entry (7.4.2) whose value is implicitly null,
    -- same as a block "key:" with nothing after the colon.
    local value
    if c == ":" then
      value, i = M.parse_value(str, skip_ws(str, i + 1))
    elseif c == "," or c == "}" then
      value = null
    else
      error("yamlcamel: expected ':', ',' or '}' after key in flow mapping, found " .. (c == "" and "end of input" or c))
    end
    result[key == null and null or tostring(key)] = value
    i = skip_ws(str, i)
    c = str:sub(i, i)
    if c == "}" then
      return result, i + 1
    elseif c == "," then
      i = skip_ws(str, i + 1)
      if str:sub(i, i) == "}" then return result, i + 1 end
    else
      error("yamlcamel: expected ',' or '}' in flow mapping, found " .. (c == "" and "end of input" or c))
    end
  end
end

return M
