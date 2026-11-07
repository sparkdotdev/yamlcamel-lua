-- Reads and writes gzip-compressed YAML on disk, going through yamlcamel.io.file and
-- yamlcamel.io.compression rather than calling Lua's io library or a zlib binding directly.
-- Depends on yamlcamel.parser and yamlcamel.emitter directly rather than on the top-level
-- yamlcamel module, which requires this one, to avoid a require cycle.
local parser = require("yamlcamel.parser")
local emitter = require("yamlcamel.emitter")
local file_mod = require("yamlcamel.io.file")
local compression_mod = require("yamlcamel.io.compression")

local M = {}

-- Read size for M.decode_file below. Matches yamlcamel.stream's own default: reading the
-- whole compressed file in one file.read call, the way this function used to, means neither
-- opts.compression's max_input_bytes nor its max_output_bytes gets checked until after the
-- entire file already sits in memory and (with the input bound checked only that late) has
-- already been fully inflated too, a bound that has by then not actually prevented anything.
local DEFAULT_READ_CHUNK_BYTES = 64 * 1024

-- Reads and decodes the gzip-compressed document at `path`. `opts.file`/`opts.compression`
-- substitute for the defaults. Raises a yamlcamel error if the file cannot be opened or does
-- not inflate, the same way {yamlcamel.decode_file} raises on a plain file.
function M.decode_file(path, opts)
  opts = opts or {}
  local file = opts.file or file_mod.default
  local compression = opts.compression or compression_mod.default
  local chunk_size = opts.chunk_size or DEFAULT_READ_CHUNK_BYTES

  local handle, err = file.open_read(path)
  if not handle then error("yamlcamel: cannot open " .. path .. ": " .. tostring(err)) end

  local ok, text = pcall(function()
    local decompressor = compression.new_decompressor(opts)
    local parts = {}
    local limits = require("yamlcamel.limits")
    local input_bytes, output_bytes = 0, 0
    local function collect(out)
      output_bytes = output_bytes + #out
      if output_bytes > (opts.max_output_bytes or limits.MAX_GZIP_OUTPUT_BYTES) then
        error("yamlcamel: decompressed output exceeds byte limit")
      end
      parts[#parts + 1] = out
    end
    while true do
      local raw = handle:read(chunk_size)
      if not raw or raw == "" then break end
      input_bytes = input_bytes + #raw
      if input_bytes > (opts.max_input_bytes or limits.MAX_GZIP_INPUT_BYTES) then
        error("yamlcamel: compressed input exceeds byte limit")
      end
      local out, derr = decompressor:push(raw)
      if not out then error("yamlcamel: cannot decompress " .. path .. ": " .. tostring(derr)) end
      collect(out)
    end
    local tail, derr = decompressor:finish()
    if not tail then error("yamlcamel: cannot decompress " .. path .. ": " .. tostring(derr)) end
    collect(tail)
    return table.concat(parts)
  end)
  handle:close()
  if not ok then error(text, 0) end
  return parser.parse(text)
end

-- Encodes `value` and writes it to `path` gzip-compressed, overwriting anything already there.
-- `opts.file`/`opts.compression` substitute for the defaults.
function M.encode_file(path, value, opts)
  opts = opts or {}
  local file = opts.file or file_mod.default
  local compression = opts.compression or compression_mod.default

  local text = emitter.encode(value)
  local compressed, err = compression.compress(text, opts)
  if not compressed then error("yamlcamel: cannot compress " .. path .. ": " .. tostring(err)) end
  local ok, werr = file.write(path, compressed)
  if not ok then error("yamlcamel: cannot open " .. path .. " for writing: " .. tostring(werr)) end
end

return M
