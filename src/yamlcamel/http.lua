-- GET and POST over HTTP for a YAML body, plain or gzip-encoded, going through the
-- yamlcamel.io.transport and yamlcamel.io.compression contracts rather than a fixed HTTP or
-- zlib library, so a caller can inject its own of either without forking this module. Depends
-- on yamlcamel.parser and yamlcamel.emitter directly rather than on the top-level yamlcamel
-- module, which requires this one, to avoid a require cycle.
local parser = require("yamlcamel.parser")
local emitter = require("yamlcamel.emitter")
local transport_mod = require("yamlcamel.io.transport")
local compression_mod = require("yamlcamel.io.compression")
local limits = require("yamlcamel.limits")

local M = {}

-- RFC 9512's registered media type for YAML, and the one this module sends.
M.MEDIA_TYPE = "application/yaml"

-- Types accepted on a response, since a server predating RFC 9512 uses an older spelling.
local ACCEPTED_MEDIA_TYPES = {
  ["application/yaml"] = true,
  ["text/yaml"] = true,
  ["application/x-yaml"] = true,
  ["text/x-yaml"] = true,
}

local function is_yaml_content_type(content_type)
  if not content_type then return false end
  local base = content_type:match("^%s*([^;]+)")
  return base ~= nil and ACCEPTED_MEDIA_TYPES[base:lower()] or false
end

local function find_header(headers, name)
  name = name:lower()
  for k, v in pairs(headers or {}) do
    if k:lower() == name then return v end
  end
  return nil
end

-- Turns a transport response into decoded YAML text: checks the size bound, the status, and the
-- content type, and only THEN believes a Content-Encoding: gzip header if the body's own first
-- bytes actually start with the gzip magic number, since a proxy that already decoded the body,
-- or a server that simply lied about the encoding, leaves bytes that are not gzip either way.
local function response_text(response, opts)
  local body = response.body
  local max_bytes = opts.max_response_bytes or limits.MAX_HTTP_RESPONSE_BYTES
  if #body > max_bytes then
    return nil, "response body exceeds " .. max_bytes .. " bytes"
  end
  if response.status < 200 or response.status >= 300 then
    return nil, "server responded with status " .. tostring(response.status)
  end

  local encoding = (find_header(response.headers, "content-encoding") or ""):lower()
  local text = body
  if (encoding == "gzip" or encoding == "x-gzip") and compression_mod.has_gzip_magic(body) then
    local compression = opts.compression or compression_mod.default
    local decoded, err = compression.decompress(body, opts)
    if not decoded then return nil, err end
    if #decoded > (opts.max_output_bytes or limits.MAX_GZIP_OUTPUT_BYTES) then
      return nil, "decompressed output exceeds byte limit"
    end
    text = decoded
  elseif encoding ~= "" and encoding ~= "identity" and encoding ~= "gzip" and encoding ~= "x-gzip" then
    return nil, "unsupported content-encoding: " .. encoding
  end

  if not is_yaml_content_type(find_header(response.headers, "content-type")) then
    return nil, "unexpected content type: " .. tostring(find_header(response.headers, "content-type"))
  end
  return text
end

-- Fetches `url` and decodes the YAML response. `opts.transport`/`opts.compression` substitute
-- for the defaults; `opts.headers` adds request headers; `opts.timeout` bounds the whole
-- exchange in seconds (30 by default). Raises a yamlcamel error for a failing status, an
-- unexpected content type, a response over `opts.max_response_bytes`, or a transport or
-- decompression failure; raises a yamlcamel parse error for a response that is not valid YAML.
function M.get(url, opts)
  opts = opts or {}
  local transport = opts.transport or transport_mod.default
  local response, err = transport.request({
    method = "GET",
    url = url,
    headers = opts.headers,
    timeout = opts.timeout or 30,
    max_response_bytes = opts.max_response_bytes or limits.MAX_HTTP_RESPONSE_BYTES,
  })
  if not response then error("yamlcamel: HTTP request failed: " .. tostring(err)) end
  local text, derr = response_text(response, opts)
  if not text then error("yamlcamel: " .. derr) end
  return parser.parse(text)
end

-- Sends `value` as YAML to `url` (POST by default; pass `opts.method` for another verb).
-- `opts.compress_body` gzips the outgoing request and sets Content-Encoding accordingly. The
-- response is decoded the same way {M.get} decodes one, gzip or plain either way, and is
-- expected to itself be a YAML body (an empty or non-YAML success response is not treated
-- specially). Raises the same errors {M.get} does.
function M.post(url, value, opts)
  opts = opts or {}
  local transport = opts.transport or transport_mod.default
  local text = emitter.encode(value)

  local headers = {}
  for k, v in pairs(opts.headers or {}) do headers[k] = v end
  headers["content-type"] = M.MEDIA_TYPE

  local body = text
  if opts.compress_body then
    local compression = opts.compression or compression_mod.default
    local compressed, err = compression.compress(text, opts)
    if not compressed then error("yamlcamel: " .. err) end
    body = compressed
    headers["content-encoding"] = "gzip"
  end

  local response, rerr = transport.request({
    method = opts.method or "POST",
    url = url,
    headers = headers,
    body = body,
    timeout = opts.timeout or 30,
    max_response_bytes = opts.max_response_bytes or limits.MAX_HTTP_RESPONSE_BYTES,
  })
  if not response then error("yamlcamel: HTTP request failed: " .. tostring(rerr)) end
  local rtext, derr = response_text(response, opts)
  if not rtext then error("yamlcamel: " .. derr) end
  return parser.parse(rtext)
end

return M
