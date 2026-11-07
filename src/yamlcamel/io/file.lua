-- The file I/O contract yamlcamel.gzip and yamlcamel.stream read and write through, rather than
-- calling Lua's io library directly, so a caller can pass its own `opts.file` (a sandboxed
-- embed with a virtual filesystem, say) without forking this library. An implementation is a
-- plain table with four functions, using Lua's own nil-plus-error-message convention throughout,
-- the same one io.open itself already uses:
--
--   read(path) -> content, or nil, err
--   write(path, content) -> true, or nil, err
--   open_read(path) -> a handle with :read(n) and :close(), or nil, err
--   open_write(path) -> a handle with :write(chunk) and :close(), or nil, err
--
-- A Lua file handle from io.open already satisfies the handle shape directly, which is why
-- M.default below is little more than io.open itself.
local M = {}

local function default_read(path)
  local handle, err = io.open(path, "rb")
  if not handle then return nil, err end
  local content = handle:read("a")
  handle:close()
  return content
end

local function default_write(path, content)
  local handle, err = io.open(path, "wb")
  if not handle then return nil, err end
  local ok, werr = handle:write(content)
  handle:close()
  if not ok then return nil, werr end
  return true
end

local function default_open_read(path)
  return io.open(path, "rb")
end

local function default_open_write(path)
  return io.open(path, "wb")
end

M.default = {
  read = default_read,
  write = default_write,
  open_read = default_open_read,
  open_write = default_open_write,
}

return M
