-- Recognizes the &anchor and !tag node properties (6.9, 7.1) shared by
-- both block style (yamlcamel.parser) and flow style (yamlcamel.flow), so
-- the two don't carry their own separately-maintained copies of the rule.
local M = {}

-- Anchor, alias and tag names all stop at whitespace or a flow indicator
-- character, in block context as much as flow, since a name can appear
-- inside `[...]`/`{...}` too (6.9.1: ns-anchor-char excludes c-flow-indicator).
M.NAME = "[^%s,%[%]{}]+"

-- Peels a leading &anchor and/or !tag off `str`, in either order (a node
-- may carry one of each, but they can appear in either order), stopping
-- once neither prefix matches. Returns the anchor name (or nil), the tag
-- text verbatim (or nil, resolved elsewhere by the caller), and whatever
-- text is left after the properties and the whitespace following them.
function M.strip(str)
  local anchor, tag
  local again = true
  while again do
    again = false
    if not anchor then
      local name, rest = str:match("^&(" .. M.NAME .. ")%s*(.*)$")
      if name then anchor, str, again = name, rest, true end
    end
    if not tag then
      local text, rest = str:match("^(!<[^>]+>)%s*(.*)$")
      if not text then text, rest = str:match("^(!" .. "[^%s,%[%]{}]*" .. ")%s*(.*)$") end
      if text then tag, str, again = text, rest, true end
    end
  end
  return anchor, tag, str
end

-- Position-based variant for flow style, where scanning happens at a
-- position inside the enclosing `[...]`/`{...}` string rather than
-- against an already-isolated value string. Returns the anchor (or nil),
-- the tag (or nil), and the position right after the properties and the
-- whitespace following them (unchanged when neither is present).
function M.strip_at(str, pos)
  local anchor, tag
  while true do
    local c = str:sub(pos, pos)
    if c == "&" and not anchor then
      local first, last = str:find(M.NAME, pos + 1)
      if first ~= pos + 1 then error("yamlcamel: an anchor needs a name") end
      anchor = str:sub(first, last)
      pos = last + 1
    elseif c == "!" and not tag then
      local start = pos
      if str:sub(pos + 1, pos + 1) == "<" then
        local close = str:find(">", pos + 2, true)
        if not close or close == pos + 2 then error("yamlcamel: malformed verbatim tag") end
        pos = close + 1
      else
        pos = pos + 1
        while pos <= #str and not str:sub(pos, pos):match("[%s,%[%]{}]") do pos = pos + 1 end
      end
      tag = str:sub(start, pos - 1)
    else
      break
    end
    while str:sub(pos, pos):match("%s") do pos = pos + 1 end
  end
  return anchor, tag, pos
end

-- Reads a bare name (an alias's, right after the '*') starting at `pos`,
-- stopping at whitespace, a flow indicator, or ':' (an alias used as a
-- flow mapping key, "*k:", has no space before the colon that ends it).
-- Returns the name and the index right after it.
function M.read_name(str, pos)
  local i, len = pos, #str
  while i <= len and not str:sub(i, i):match("[%s,%[%]{}:]") do
    i = i + 1
  end
  return str:sub(pos, i - 1), i
end

return M
