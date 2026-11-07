-- The sentinel for an explicit YAML null. Lua's own nil cannot live inside a
-- table as a value, so a decoded mapping or sequence carries this instead
-- wherever the document said `null`, `~` or left a value empty.
local null = setmetatable({}, {
  __tostring = function() return "yaml.null" end,
})

return null
