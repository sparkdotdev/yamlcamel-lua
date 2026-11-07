-- Trimming, done by walking in from the two ends rather than with Lua's
-- own "^%s*(.-)%s*$" and "%s+$" patterns. Those look right and are a trap
-- on hostile input: both retry from every position in the string, so one
-- long run of spaces costs time quadratic in that run's length. A 125 kB
-- line of "a: x" then spaces then "y" never finished when the tokenizer
-- trimmed it with a pattern; the same line takes microseconds here.
local M = {}

-- The bytes Lua's own %s class covers: space, and the tab through carriage
-- return block.
local function is_space(b)
  return b == 32 or (b >= 9 and b <= 13)
end

function M.rstrip(str)
  local last = #str
  while last > 0 and is_space(str:byte(last)) do last = last - 1 end
  if last == #str then return str end
  return str:sub(1, last)
end

function M.trim(str)
  local first, last = 1, #str
  while first <= last and is_space(str:byte(first)) do first = first + 1 end
  while last >= first and is_space(str:byte(last)) do last = last - 1 end
  if first == 1 and last == #str then return str end
  return str:sub(first, last)
end

-- The index of the last non-whitespace byte at or before `last`, for a
-- caller that already knows where a slice ends and only wants to back off
-- its trailing whitespace without copying the slice first.
function M.rstrip_to(str, first, last)
  while last >= first and is_space(str:byte(last)) do last = last - 1 end
  return last
end

return M
