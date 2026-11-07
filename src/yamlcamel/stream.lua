-- Reads a large, `---`-separated YAML stream from disk (raw or, with `opts.gzip = true`,
-- gzip-compressed) one document at a time, calling `on_document(value)` per document rather
-- than buffering the whole file the way {yamlcamel.decode_all} does. Goes through
-- yamlcamel.io.file and yamlcamel.io.compression rather than calling Lua's io library or a
-- zlib binding directly. Depends on yamlcamel.parser directly rather than on the top-level
-- yamlcamel module, which requires this one, to avoid a require cycle.
--
-- This is a minimal reader built for one job: a large multi-document export too big to hold in
-- memory at once. Each document's own text is still parsed by {yamlcamel.parser.parse} in one
-- piece, exactly as {yamlcamel.decode} does, once that document's boundary is found. Finding
-- the boundary is what streams: a document separator (7.1, 9.1, 9.2) is always a raw line that
-- is exactly "---", starts with "--- ", or is exactly "...", and none of those three shapes can
-- ever occur as content inside a block scalar, a quoted scalar, or a flow collection wrapped
-- across lines, since all three only ever swallow MORE-indented or already-open-quote/bracket
-- lines, and a document separator always sits at column 0. That is what {yamlcamel.parser}'s own
-- tokenizer relies on too (see the comment on tokenize_stream there), and it is what makes
-- splitting a raw byte stream into documents correct here without tracking quotes, brackets or
-- indentation at all.
--
-- Document prefixes and exact scalar bytes are preserved until the completed document is
-- parsed. In particular, blank lines inside a scalar and the absence of a final line break
-- cannot be discarded by the splitter.
local parser = require("yamlcamel.parser")
local file_mod = require("yamlcamel.io.file")
local compression_mod = require("yamlcamel.io.compression")
local limits = require("yamlcamel.limits")
local whitespace = require("yamlcamel.whitespace")
local bom = require("yamlcamel.charset").BOM

local M = {}

local DEFAULT_CHUNK_SIZE = 64 * 1024

-- Turns a chunk source (a function returning the next chunk of text, "" to mean "no data yet,
-- keep calling", or nil for true end of input) into a line source, so the splitter below can
-- work one line at a time regardless of how the bytes actually arrived off disk or out of a
-- decompressor.
local function line_reader(next_chunk)
  local chunk, pos, done = "", 1, false
  local parts = {}
  local bytes = 0
  return function()
    if done then return nil end
    while true do
      local nl = chunk:find("\n", pos, true)
      if nl then
        parts[#parts + 1] = chunk:sub(pos, nl - 1)
        local line = table.concat(parts)
        parts, pos = {}, nl + 1
        return line, true
      end
      if pos <= #chunk then parts[#parts + 1] = chunk:sub(pos) end
      chunk = next_chunk()
      if chunk then
        bytes = bytes + #chunk
        if bytes > limits.MAX_INPUT_BYTES then error("yamlcamel: input exceeds byte limit") end
      end
      pos = 1
      if chunk == nil then
        done = true
        if #parts == 0 then return nil end
        local line = table.concat(parts)
        parts = {}
        return line, false
      end
    end
  end
end

local function decode_stream(next_chunk, on_document)
  local read_line = line_reader(next_chunk)
  local parts = {}
  local prefix_only = true
  local total_bytes = 0
  local function finish_document()
    if #parts > 0 then
      for _, value in ipairs(parser.parse_all(table.concat(parts))) do on_document(value) end
    end
    parts = {}
  end
  while true do
    local line, has_break = read_line()
    if line == nil then break end
    local raw = line .. (has_break and "\n" or "")
    total_bytes = total_bytes + #raw
    if total_bytes > limits.MAX_INPUT_BYTES then error("yamlcamel: input exceeds " .. limits.MAX_INPUT_BYTES .. " bytes") end
    local normalized = line:gsub("\r$", "")
    local marker = normalized:gsub("^" .. bom, "")
    local start_marker = marker == "---" or marker:match("^%-%-%-[ \t]")
    local end_marker = marker == "..." or marker:match("^%.%.%.[ \t]")
    if start_marker then
      if not prefix_only then finish_document() end
      parts[#parts + 1] = raw
      prefix_only = false
    elseif end_marker then
      parts[#parts + 1] = raw
      finish_document()
      prefix_only = true
    else
      parts[#parts + 1] = raw
      local trimmed = whitespace.trim(normalized)
      if trimmed ~= "" and not trimmed:match("^[#%%]") then prefix_only = false end
    end
  end
  finish_document()
end

-- Reads and decodes the document stream at `path`, calling `on_document(value)` once per
-- document in stream order, the same values {yamlcamel.decode_all} would return as an array,
-- without ever holding more than one document's text at a time. `opts.gzip = true` reads a
-- gzip-compressed stream instead of a raw one; `opts.chunk_size` overrides the 64 KB read size;
-- `opts.file`/`opts.compression` substitute for the defaults. Raises a yamlcamel error if the
-- file cannot be opened or (with `opts.gzip`) does not inflate.
function M.decode_file(path, on_document, opts)
  opts = opts or {}
  local file = opts.file or file_mod.default
  local chunk_size = opts.chunk_size or DEFAULT_CHUNK_SIZE

  local handle, err = file.open_read(path)
  if not handle then error("yamlcamel: cannot open " .. path .. ": " .. tostring(err)) end

  local next_chunk
  if opts.gzip then
    local compression = opts.compression or compression_mod.default
    local initialized, decompressor = pcall(compression.new_decompressor, opts)
    if not initialized then handle:close(); error(decompressor, 0) end
    local raw_done = false
    next_chunk = function()
      if raw_done then return nil end
      local raw = handle:read(chunk_size)
      if not raw or raw == "" then
        raw_done = true
        local tail, derr = decompressor:finish()
        if not tail then error("yamlcamel: cannot decompress " .. path .. ": " .. tostring(derr)) end
        return tail ~= "" and tail or nil
      end
      local out, derr = decompressor:push(raw)
      if not out then error("yamlcamel: cannot decompress " .. path .. ": " .. tostring(derr)) end
      return out
    end
  else
    next_chunk = function() return handle:read(chunk_size) end
  end

  local ok, streamerr = pcall(decode_stream, next_chunk, on_document)
  handle:close()
  if not ok then error(streamerr, 0) end
end

return M
