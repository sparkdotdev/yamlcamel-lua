-- The ceilings one decode or encode call is held to, so a small hostile
-- document cannot cost unbounded time, memory or Lua stack. A
-- recursive-descent parser has no natural floor of its own here: without a
-- count, deep nesting runs until Lua raises its own "stack overflow", which
-- is neither a yamlcamel error a caller can read nor reached before the
-- document has already allocated far more than it cost to write (a 64 kB
-- line of nothing but "- " markers reaches about a gigabyte of heap, since
-- every level holds its own copy of the rest of the line).
local M = {}

-- How deep mappings and sequences may nest, block and flow style together,
-- since a document can hand off from one to the other partway down. Real
-- documents live nowhere near this: the deepest thing in this repository's
-- own conformance corpus is seven levels.
M.MAX_DEPTH = 200

-- Bounds applied before tokenization and conversion, independent of the input's source.
M.MAX_INPUT_BYTES = 16 * 1024 * 1024
M.MAX_SCALAR_BYTES = 4 * 1024 * 1024
M.MAX_NUMBER_DIGITS = 4096
M.MAX_OUTPUT_BYTES = 16 * 1024 * 1024

-- How many values a single encode call may write. Decode resolves an alias
-- to the very same table rather than a copy, so an anchor referenced from
-- several places costs nothing on the way in, but the emitter has no
-- anchors of its own to write and walks each of those places separately.
-- That turns the classic alias expansion bomb into an encode-side problem:
-- without this, a 336-byte document takes longer than ten seconds to
-- encode.
M.MAX_EMIT_NODES = 200000

-- Largest HTTP response body yamlcamel.http accepts, checked before any decompression or
-- parsing runs against it, since a bound checked on a body already in memory has not
-- prevented anything.
M.MAX_HTTP_RESPONSE_BYTES = 16 * 1024 * 1024

-- Largest decompressed output yamlcamel.io.compression accepts, checked while inflating rather
-- than after: a few kilobytes of gzip can expand to gigabytes.
M.MAX_GZIP_OUTPUT_BYTES = 64 * 1024 * 1024

-- Largest compressed input accepted before inflating any of it.
M.MAX_GZIP_INPUT_BYTES = 16 * 1024 * 1024

-- Longest prefix a %TAG directive may register against a handle. A real tag prefix is a
-- URI, at most a few hundred bytes long; without a bound here, one directive line can carry
-- an arbitrarily large prefix that every short tag using its handle re-concatenates onto the
-- suffix in full, turning a handful of characters per use into unbounded work: a
-- one-megabyte prefix used three thousand times over a one-megabyte document already costs
-- five seconds of CPU, checked here before that prefix is ever registered at all, not after
-- it has already been multiplied out.
M.MAX_TAG_PREFIX_BYTES = 2048

-- The nesting count for the decode currently running. Kept here rather
-- than threaded through every parse function's arguments because block
-- style (yamlcamel.parser) and flow style (yamlcamel.flow) recurse into
-- each other and have to share one budget.
local depth

function M.reset()
  depth = 0
end

function M.enter()
  depth = depth + 1
  if depth > M.MAX_DEPTH then
    error("yamlcamel: input nests deeper than " .. M.MAX_DEPTH .. " levels")
  end
end

function M.leave()
  depth = depth - 1
end

return M
