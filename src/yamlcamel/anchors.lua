-- The per-document anchor table &name registers a node into and *name
-- looks a node up from (6.9.2, 7.1). Reset at the start of every document a
-- parser reads, since an anchor is only visible within the document that
-- defines it, never across a `---` boundary or between separate decode
-- calls.
local M = {}
local charset = require("yamlcamel.charset")

local anchors

function M.reset()
  anchors = {}
end

-- Registers `value` under `name` and returns it unchanged, so a caller can
-- both pre-register a placeholder container (for a node that may turn out
-- to reference itself) and register the final value in one call.
function M.register(name, value)
  charset.check_printable(name)
  anchors[name] = value
  return value
end

function M.resolve(name)
  charset.check_printable(name)
  local value = anchors[name]
  if value == nil then
    error("yamlcamel: undefined anchor referenced by alias *" .. name)
  end
  return value
end

return M
