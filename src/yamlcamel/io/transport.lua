-- The HTTP transport contract yamlcamel.http reads and writes through, rather than calling an
-- HTTP client directly, so a caller can pass its own `opts.transport` (a game engine's own
-- networking layer, say) without forking this library. An implementation is a plain table with
-- one function, using Lua's own nil-plus-error-message convention:
--
--   request(req) -> response, or nil, err
--
-- `req` is { method, url, headers (name -> value, or nil), body (a string, or nil), timeout (a
-- number of seconds, or nil for no timeout), max_response_bytes (a number, or nil for
-- yamlcamel.limits.MAX_HTTP_RESPONSE_BYTES) }.
--
-- `response` is { status (a number), headers (name -> value, lower-cased names), body (a
-- string) }. A transport that never reaches the server at all (DNS failure, connection refused,
-- timeout) returns nil, err instead of a response; a transport that DOES reach the server
-- always returns a response table, whatever the status code, since a non-2xx status is
-- yamlcamel.http's concern to raise on, not the transport's. A body already over
-- `max_response_bytes` is itself a nil-plus-error case, not a response: an implementation is
-- expected to stop reading and reject it as it arrives, the same way yamlcamel.io.compression's
-- decompressor checks its own output bound while inflating rather than after, since a bound only
-- checked once the whole body is already sitting in memory has not protected the process an
-- oversized or endlessly-drip-fed response was aimed at.
--
-- The default implementation below wraps daurnimator/http (LuaRocks package `http`), a
-- full-featured client and server supporting HTTP/1.1 and HTTP/2 with TLS, and the Lua HTTP
-- library this project standardizes on elsewhere. It is required lazily, only once a default
-- transport call is actually made, so a caller that injects its own `opts.transport` (or never
-- makes an HTTP call at all) never needs the rock, or its own dependency chain (cqueues,
-- luaossl and the rest), installed.
local limits = require("yamlcamel.limits")

local M = {}

local function request(req)
  local ok, http_request = pcall(require, "http.request")
  if not ok then
    error("yamlcamel: HTTP support needs the 'http' rock (luarocks install http): " .. tostring(http_request))
  end

  local r = http_request.new_from_uri(req.url)
  r.headers:upsert(":method", req.method or "GET")
  for name, value in pairs(req.headers or {}) do
    r.headers:upsert(name:lower(), value)
  end
  if req.body then
    r:set_body(req.body)
  end

  local headers, stream = r:go(req.timeout)
  if not headers then
    return nil, tostring(stream)
  end

  -- get_body_as_string would read the whole response into one string before ever handing it
  -- back, however large the server (or whatever sits between it and this process) decides to
  -- make it. Reading chunk by chunk instead, and checking the running total against
  -- `max_response_bytes` after each one, means a body that is already too large gets rejected
  -- somewhere around one chunk past the bound rather than once it has all been buffered.
  local max_bytes = req.max_response_bytes or limits.MAX_HTTP_RESPONSE_BYTES
  local parts, total = {}, 0
  while true do
    local chunk, err = stream:get_next_chunk(req.timeout)
    if chunk == nil then
      if err then return nil, tostring(err) end
      break
    end
    total = total + #chunk
    if total > max_bytes then
      return nil, "response body exceeds " .. max_bytes .. " bytes"
    end
    parts[#parts + 1] = chunk
  end
  local body = table.concat(parts)

  local resp_headers = {}
  for name, value in pairs(headers) do
    if name:sub(1, 1) ~= ":" then
      resp_headers[name] = value
    end
  end

  return { status = tonumber(headers:get(":status")), headers = resp_headers, body = body }
end

M.default = { request = request }

return M
