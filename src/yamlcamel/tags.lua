-- Resolves an explicit tag token (as captured verbatim by yamlcamel.props,
-- e.g. "!!str", "!<tag:example.com,2002:thing>", "!local", "!ns!local") to
-- what it means for a node's value: forcing one of the core schema's own
-- scalar types when the tag names one of those (10.3.1), or otherwise
-- wrapping the value so the caller can see the tag was there at all,
-- since Lua's own type system has no room for an arbitrary application
-- tag the way a real YAML representation graph does.
local null = require("yamlcamel.null")
local scalar = require("yamlcamel.scalar")

local M = {}
local limits = require("yamlcamel.limits")
local charset = require("yamlcamel.charset")
local function check_scalar(text)
  if #text > limits.MAX_SCALAR_BYTES then error("yamlcamel: scalar exceeds " .. limits.MAX_SCALAR_BYTES .. " bytes") end
end

-- The current document's %TAG handle -> prefix table (7.1.7, 9.1.3),
-- reset per document the same way yamlcamel.anchors resets its own table;
-- see yamlcamel.parser's tokenize_stream for where %TAG lines are parsed
-- into it in the first place.
local handles

function M.reset(document_handles)
  handles = document_handles or {}
end

function M.register_handle(handle, prefix)
  handles[handle] = prefix
end

local mt = {
  __tostring = function(t) return "yaml.tagged(" .. t.tag .. ")" end,
}

-- Wraps `value` with the tag that was attached to it, for a tag this
-- library doesn't resolve to one of the core schema's own types. `.tag`
-- is the tag exactly as expanded (a full URI, or a bare local tag like
-- "!thing" when nothing expands it); `.value` is the node's own value,
-- resolved as if the tag had not been there at all.
function M.tagged(tag, value)
  return setmetatable({ tag = tag, value = value }, mt)
end

function M.is_tagged(v)
  return type(v) == "table" and getmetatable(v) == mt
end

local CORE_SCALAR_URI = {
  ["tag:yaml.org,2002:str"] = true,
  ["tag:yaml.org,2002:int"] = true,
  ["tag:yaml.org,2002:float"] = true,
  ["tag:yaml.org,2002:bool"] = true,
  ["tag:yaml.org,2002:null"] = true,
}

-- Expands `tag_text` against the document's %TAG handles. Returns
-- "non-specific" for a bare "!" (resolved by the node's own kind at each
-- call site instead, per 10.3.2's convention for the "!" tag), a full URI
-- for !!str, !<...>, or a handle a %TAG directive defines, or `tag_text`
-- itself unchanged for a local tag nothing expands (!thing, with no %TAG
-- ! redefining the primary handle: 7.1, the tag IS that literal string).
local function expand(tag_text)
  charset.check_printable(tag_text)
  if tag_text == "!" then return "non-specific" end

  local verbatim = tag_text:match("^!<(.+)>$")
  if verbatim then return verbatim end

  -- The secondary handle "!!" defaults to tag:yaml.org,2002:, but a %TAG
  -- !! directive can still redefine it, same as any other handle (7.1.7,
  -- 6.19 "!!int 1 - 3" isn't tag:yaml.org,2002:int once a document has
  -- pointed !! somewhere else).
  local secondary_suffix = tag_text:match("^!!(.+)$")
  if secondary_suffix then return (handles["!!"] or "tag:yaml.org,2002:") .. secondary_suffix end

  local handle_name, named_suffix = tag_text:match("^(!.+!)(.+)$")
  if handle_name then
    local prefix = handles[handle_name]
    if not prefix then
      error("yamlcamel: tag handle " .. handle_name .. " used without a %TAG directive to define it")
    end
    return prefix .. named_suffix
  end

  local primary_suffix = tag_text:match("^!(.+)$")
  local primary_prefix = handles["!"]
  if primary_prefix then return primary_prefix .. primary_suffix end
  return tag_text
end

-- Forces `text` to read as the core schema type `uri` names, the same
-- grammar M.resolve for that type already recognizes, raising if `text`
-- isn't legal for it. Explicit or implicit, a bool tag here still only
-- accepts true/True/TRUE/false/False/FALSE (see yamlcamel.scalar's module
-- comment); an explicit !!bool is not a back door to the YAML 1.1 words.
local function force_core_scalar(uri, text)
  if uri == "tag:yaml.org,2002:str" then return text end
  if uri == "tag:yaml.org,2002:null" then
    if not scalar.is_null_word(text) then
      error("yamlcamel: !!null does not accept " .. text)
    end
    return null
  end
  if uri == "tag:yaml.org,2002:bool" then
    local b = scalar.parse_bool(text)
    if b == nil then error("yamlcamel: !!bool does not accept " .. text) end
    return b
  end
  if uri == "tag:yaml.org,2002:int" then
    local n = scalar.parse_int(text)
    if n == nil then error("yamlcamel: !!int does not accept " .. text) end
    return n
  end
  if uri == "tag:yaml.org,2002:float" then
    -- Lenient by one step: "3" isn't a legal *float* literal on its own
    -- (10.3.2 keeps int and float as separate productions), but rejecting
    -- an explicit `!!float 3` would be more surprising than useful, so an
    -- int-shaped text is accepted too and just converted.
    local n = scalar.parse_float(text)
    if n == nil then n = scalar.parse_int(text) end
    if n == nil then error("yamlcamel: !!float does not accept " .. text) end
    return n + 0.0
  end
end

-- Resolves a plain scalar's tag against its own raw text, which is what
-- makes forcing a type meaningful: by the time a value exists to inspect,
-- the implicit resolution has already committed to one. `tag_text` nil
-- means no tag at all, so `text` resolves the ordinary implicit way.
function M.resolve_plain(tag_text, text)
  check_scalar(text)
  charset.check_printable(text)
  if not tag_text then return scalar.resolve(text) end
  local uri = expand(tag_text)
  if uri == "non-specific" then return text end
  if CORE_SCALAR_URI[uri] then return force_core_scalar(uri, text) end
  return M.tagged(uri, text)
end

-- Resolves a tag against a value that is already unambiguously a string
-- regardless of its content (a quoted scalar, or a block scalar's
-- resolved body): implicit resolution never applies to either, so a nil
-- tag just means the string as-is, but an explicit tag can still force a
-- different core type, or wrap it under a custom one.
function M.resolve_string(tag_text, str, block)
  check_scalar(str)
  if block then charset.check_printable(str) end
  if not tag_text then return str end
  local uri = expand(tag_text)
  if uri == "non-specific" then return str end
  if CORE_SCALAR_URI[uri] then return force_core_scalar(uri, str) end
  return M.tagged(uri, str)
end

-- Resolves a tag against an already-parsed mapping or sequence. !!map and
-- !!seq (and the non-specific "!") just confirm what {value} already is;
-- anything else, core scalar tag or custom, wraps it, since a collection
-- can never actually become a scalar just by being tagged as one.
function M.resolve_collection(tag_text, value)
  if not tag_text then return value end
  local uri = expand(tag_text)
  if uri == "non-specific" or uri == "tag:yaml.org,2002:map" or uri == "tag:yaml.org,2002:seq" then
    return value
  end
  return M.tagged(uri, value)
end

return M
