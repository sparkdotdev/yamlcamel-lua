-- The gzip compression contract yamlcamel.gzip, yamlcamel.http and yamlcamel.stream read and
-- write through, rather than calling a zlib binding directly, so a caller can pass its own
-- `opts.compression` without forking this library. An implementation is a plain table with four
-- functions, using Lua's own nil-plus-error-message convention throughout:
--
--   compress(data, opts) -> bytes, or nil, err
--   decompress(data, opts) -> bytes, or nil, err
--   new_compressor(opts) -> a stream with :push(chunk) -> bytes, or nil, err
--                                     and :finish() -> bytes, or nil, err
--   new_decompressor(opts) -> a stream with :push(chunk) -> bytes, or nil, err
--                                       and :finish() -> bytes, or nil, err
--
-- The streaming pair exists for yamlcamel.stream, which never holds a whole large file in
-- memory; `compress`/`decompress` are the one-shot forms everything else uses, and are exactly
-- what a `new_compressor`/`new_decompressor` push-then-finish call already does under the hood.
--
-- `opts` may carry `max_output_bytes`/`max_input_bytes`, defaulting to yamlcamel.limits' own
-- ceilings; a decompressor checks the output bound as bytes come out rather than after
-- inflating everything, since a few kilobytes of gzip can expand to gigabytes.
--
-- The default implementation below wraps brimworks/lua-zlib (the `zlib` module, LuaRocks
-- package `lua-zlib`): a small, direct binding with no C library beyond zlib itself, actively
-- maintained, and the same one daurnimator/http already expects for its own gzip handling, so a
-- caller using both this module's HTTP default and its compression default is not carrying two
-- separate bindings to the same underlying library. It is required lazily, only once a default
-- compression call is actually made, so a caller that injects its own `opts.compression` (or
-- never touches gzip at all) never needs the rock installed.
local limits = require("yamlcamel.limits")

local M = {}

-- True when `bytes` begins with the gzip magic number. Proves nothing about the rest of the
-- stream; treat this as a hint for deciding whether to decompress at all; see yamlcamel.http.
function M.has_gzip_magic(bytes)
  return #bytes >= 2 and bytes:byte(1) == 0x1f and bytes:byte(2) == 0x8b
end

local function zlib()
  local ok, mod = pcall(require, "zlib")
  if not ok then
    error("yamlcamel: gzip support needs the 'lua-zlib' rock (luarocks install lua-zlib): " .. tostring(mod))
  end
  return mod
end

-- 15 window bits (the maximum) plus the 16-bit flag selects a gzip header and trailer rather
-- than a bare zlib one, both on the way in and the way out.
local function gzip_window_bits(z)
  return z.DEFAULT_WINDOWBITS + z.GZIP_WINDOWBITS
end

local function new_compressor(opts)
  opts = opts or {}
  local z = zlib()
  local stream = z.deflate(opts.level or z.DEFAULT_COMPRESSION, gzip_window_bits(z))
  local finished = false

  local function push(_, chunk)
    if finished then return nil, "compressor already finished" end
    local ok, out = pcall(stream, chunk or "")
    if not ok then return nil, out end
    return out
  end

  local function finish(_)
    if finished then return nil, "compressor already finished" end
    finished = true
    local ok, out = pcall(stream, "", "finish")
    if not ok then return nil, out end
    return out
  end

  return { push = push, finish = finish }
end

local function new_decompressor(opts)
  opts = opts or {}
  local z = zlib()
  local stream
  local max_output = opts.max_output_bytes or limits.MAX_GZIP_OUTPUT_BYTES
  local max_input = opts.max_input_bytes or limits.MAX_GZIP_INPUT_BYTES
  local total_in, total_out, member_in = 0, 0, 0
  local saw_input, reached_end = false, false

  local function push(_, chunk)
    chunk = chunk or ""
    total_in = total_in + #chunk
    if total_in > max_input then return nil, "compressed input exceeds " .. max_input .. " bytes" end
    if chunk == "" then return "" end
    saw_input = true
    local parts = {}
    local pos = 1
    while pos <= #chunk do
      if not stream then
        stream, member_in = z.inflate(gzip_window_bits(z)), 0
        reached_end = false
      end
      -- Bound each native inflate call, including direct streaming callers.
      local input = chunk:sub(pos, math.min(#chunk, pos + 4095))
      local ok, out, eof, consumed = pcall(stream, input)
      if not ok then return nil, out end
      local used = consumed - member_in
      member_in = consumed
      total_out = total_out + #out
      if total_out > max_output then return nil, "decompressed output exceeds " .. max_output .. " bytes" end
      parts[#parts + 1] = out
      pos = pos + used
      if eof then reached_end, stream = true, nil
      elseif used == 0 then return nil, "gzip decoder made no progress" end
    end
    return table.concat(parts)
  end

  local function finish(_)
    if not saw_input then return nil, "no gzip data was given" end
    if not reached_end then return nil, "gzip stream ended before its trailer" end
    return ""
  end

  return { push = push, finish = finish }
end

local function compress(data, opts)
  local c = new_compressor(opts)
  local head, err = c:push(data)
  if not head then return nil, err end
  local tail, err2 = c:finish()
  if not tail then return nil, err2 end
  return head .. tail
end

-- Compressed bytes fed to the decompressor per push() call below, so new_decompressor's own
-- max_output_bytes check actually gets to run while inflating rather than after: handing the
-- whole input to a single push() call defeats that check no differently than never having it
-- at all, since lua-zlib inflates everything it is given before returning regardless of how
-- much that turns out to be. A few kilobytes of gzip decompressing to two gigabytes reached
-- four-plus GB of resident memory this way despite a 64 MB output ceiling, the ceiling never
-- getting a chance to fire until the whole bomb already sat in RAM.
local DECOMPRESS_CHUNK_BYTES = 64 * 1024

local function decompress(data, opts)
  local d = new_decompressor(opts)
  local parts = {}
  local pos, len = 1, #data
  while pos <= len do
    local out, err = d:push(data:sub(pos, pos + DECOMPRESS_CHUNK_BYTES - 1))
    if not out then return nil, err end
    parts[#parts + 1] = out
    pos = pos + DECOMPRESS_CHUNK_BYTES
  end
  local tail, err2 = d:finish()
  if not tail then return nil, err2 end
  parts[#parts + 1] = tail
  return table.concat(parts)
end

M.default = {
  compress = compress,
  decompress = decompress,
  new_compressor = new_compressor,
  new_decompressor = new_decompressor,
}

return M
