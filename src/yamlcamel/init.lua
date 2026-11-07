-- yamlcamel: a pure-Lua reader and writer for a deliberately small subset of
-- YAML: mappings, sequences and scalars, in block and flow style, including
-- block scalars, multi-line flow collections, anchors and aliases,
-- multi-document streams, and explicit tags.
--
-- See the README for what's here, and the tracking issues on this
-- repository for what full YAML 1.2.2 support would still need, the way
-- this library's Swift sibling already has it.
local parser = require("yamlcamel.parser")
local emitter = require("yamlcamel.emitter")
local null = require("yamlcamel.null")
local tags = require("yamlcamel.tags")
local file_mod = require("yamlcamel.io.file")
local gzip = require("yamlcamel.gzip")
local stream = require("yamlcamel.stream")
local http = require("yamlcamel.http")

local M = {}

-- The pluggable I/O contracts {M.decode_file}, {M.encode_file}, {M.decode_gzip_file},
-- {M.encode_gzip_file}, {M.decode_file_stream}, {M.http_get} and {M.http_post} all go through
-- rather than calling Lua's io library, a zlib binding or an HTTP client directly, plus each
-- one's default implementation. Pass `opts.file`, `opts.compression` or `opts.transport` to any
-- of those functions to substitute your own; see the contract modules themselves for the shape
-- an implementation has to satisfy.
M.io = {
  file = file_mod,
  compression = require("yamlcamel.io.compression"),
  transport = require("yamlcamel.io.transport"),
}

M.VERSION = "0.1.0"

-- The sentinel for an explicit YAML null, since Lua's own nil cannot live
-- inside a table as a value.
M.null = null

-- Forces an empty Lua table to encode as `{}` rather than the default `[]`;
-- see yamlcamel.emitter for why an empty table is otherwise ambiguous.
M.EMPTY_MAPPING = emitter.EMPTY_MAPPING

function M.is_null(value)
  return value == null
end

-- Wraps `value` with an explicit YAML tag: `tag` is the tag text exactly
-- as it would appear in a document ("!!set", "!Point", "!<tag:example.com
-- ,2000:custom>"). decode returns exactly this shape for a node whose tag
-- isn't one of the core schema's own scalar or collection types, since a
-- plain Lua value has nowhere else to carry that tag; encode reads one
-- back the same way, writing the tag ahead of the value it wraps. Access
-- the pieces directly: `t.tag`, `t.value`.
function M.tagged(tag, value)
  return tags.tagged(tag, value)
end

function M.is_tagged(value)
  return tags.is_tagged(value)
end

-- Parses a YAML document into a Lua value: a table for a mapping or
-- sequence, or a boolean, number or string for a scalar root. Raises a Lua
-- error on malformed input; wrap a call in pcall to recover from that.
-- `text` may hold a stream of more than one `---`-separated document, in
-- which case only the first is decoded; see {M.decode_all} for the rest.
function M.decode(text)
  return parser.parse(text)
end

-- Encodes a Lua value as a complete YAML document. Raises a Lua error for a
-- value this subset cannot represent (a function or a userdata).
function M.encode(value)
  return emitter.encode(value)
end

-- Parses every document in a `---`-separated stream and returns their root
-- values as a Lua array, one entry per document, in stream order. A blank
-- or entirely commented-out stream decodes to an empty array, since there
-- is no document to hold a null. Each document has its own anchor
-- namespace; an alias cannot reach across a `---`/`...` boundary.
function M.decode_all(text)
  return parser.parse_all(text)
end

-- Encodes a Lua array of values as a stream of that many `---`-separated
-- documents, in order. {M.decode_all} reads back exactly this shape.
function M.encode_all(values)
  return emitter.encode_all(values)
end

-- Reads and decodes the whole file at `path`. Raises a Lua error if the file
-- cannot be opened, the same way {M.decode} raises on malformed content.
-- `opts.file` substitutes for the default yamlcamel.io.file implementation.
function M.decode_file(path, opts)
  local file = (opts and opts.file) or file_mod.default
  local limits = require("yamlcamel.limits")
  if not file.open_read then
    local text, err = file.read(path)
    if not text then error("yamlcamel: cannot open " .. path .. ": " .. tostring(err)) end
    return M.decode(text)
  end
  local handle, err = file.open_read(path)
  if not handle then error("yamlcamel: cannot open " .. path .. ": " .. tostring(err)) end
  local ok, text = pcall(function()
    local parts, total = {}, 0
    while true do
      local chunk = handle:read(math.min(65536, limits.MAX_INPUT_BYTES - total + 1))
      if not chunk or chunk == "" then break end
      total = total + #chunk
      if total > limits.MAX_INPUT_BYTES then error("yamlcamel: input exceeds byte limit") end
      parts[#parts + 1] = chunk
    end
    return table.concat(parts)
  end)
  handle:close()
  if not ok then error(text, 0) end
  return M.decode(text)
end

-- Encodes `value` and writes it to `path`, overwriting anything already
-- there. Raises a Lua error if the file cannot be opened for writing.
-- `opts.file` substitutes for the default yamlcamel.io.file implementation.
function M.encode_file(path, value, opts)
  local file = (opts and opts.file) or file_mod.default
  local ok, err = file.write(path, M.encode(value))
  if not ok then error("yamlcamel: cannot open " .. path .. " for writing: " .. tostring(err)) end
end

-- Reads and decodes the gzip-compressed document at `path`. `opts.file`/`opts.compression`
-- substitute for the defaults. Raises a yamlcamel error if the file cannot be opened or does
-- not inflate.
function M.decode_gzip_file(path, opts)
  return gzip.decode_file(path, opts)
end

-- Encodes `value` and writes it to `path` gzip-compressed, overwriting anything already there.
-- `opts.file`/`opts.compression` substitute for the defaults.
function M.encode_gzip_file(path, value, opts)
  return gzip.encode_file(path, value, opts)
end

-- Reads and decodes the `---`-separated document stream at `path`, calling
-- `on_document(value)` once per document in stream order, without holding more than one
-- document's text in memory at a time, for a file too large to read whole the way
-- {M.decode_all} does. `opts.gzip = true` reads a gzip-compressed stream instead of a raw one;
-- `opts.file`/`opts.compression` substitute for the defaults. See yamlcamel.stream for what
-- this minimal reader does and does not carry over from a whole-file decode.
function M.decode_file_stream(path, on_document, opts)
  return stream.decode_file(path, on_document, opts)
end

-- Fetches `url` and decodes the YAML response, gzip-compressed or plain depending on what the
-- server actually sent. `opts.transport`/`opts.compression` substitute for the defaults; see
-- yamlcamel.http for the rest of `opts` and the errors this can raise.
function M.http_get(url, opts)
  return http.get(url, opts)
end

-- Sends `value` as YAML to `url` (POST by default) and decodes the YAML response.
-- `opts.compress_body = true` gzips the request; `opts.transport`/`opts.compression` substitute
-- for the defaults; see yamlcamel.http for the rest of `opts` and the errors this can raise.
function M.http_post(url, value, opts)
  return http.post(url, value, opts)
end

return M
