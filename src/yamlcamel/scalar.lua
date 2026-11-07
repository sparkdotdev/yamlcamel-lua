-- Resolves a plain (unquoted) scalar's text to a null, boolean, number or
-- string value, per the YAML 1.2.2 core schema's tag resolution table
-- (10.3.2). This is a 1.2 schema, not 1.1: yes/no/on/off are ordinary
-- strings here, only true/false (in the listed capitalizations) are
-- booleans, matching what Psych 4+ does on the server side too.
local null = require("yamlcamel.null")

local M = {}
local limits = require("yamlcamel.limits")
local charset = require("yamlcamel.charset")

local TRUE_WORDS = { ["true"] = true, ["True"] = true, ["TRUE"] = true }
local FALSE_WORDS = { ["false"] = true, ["False"] = true, ["FALSE"] = true }
local NULL_WORDS = { [""] = true, ["~"] = true, ["null"] = true, ["Null"] = true, ["NULL"] = true }
local POS_INF_WORDS = { [".inf"] = true, [".Inf"] = true, [".INF"] = true, ["+.inf"] = true, ["+.Inf"] = true, ["+.INF"] = true }
local NEG_INF_WORDS = { ["-.inf"] = true, ["-.Inf"] = true, ["-.INF"] = true }
local NAN_WORDS = { [".nan"] = true, [".NaN"] = true, [".NAN"] = true }

-- Plain integers, base 10 (10.3.2): optional sign, digits only, no special
-- case for a leading zero. 1.2 moved octal to the explicit 0o prefix below
-- specifically so a bare "007" or "010" is unambiguous, so it resolves to
-- the number, same as any other run of digits.
local INTEGER_PATTERN = "^[-+]?%d+$"

-- Octal and hex ints (10.3.2). Neither takes a sign in the spec grammar,
-- unlike the base-10 form above.
local OCTAL_PATTERN = "^0o[0-7]+$"
local HEX_PATTERN = "^0x%x+$"

local DIGIT_ZERO, DIGIT_NINE = 48, 57
local DOT, PLUS, MINUS, LOWER_E, UPPER_E = 46, 43, 45, 101, 69

-- Whether `text` is a plain float: an optional sign, digits with at most
-- one decimal point among them and at least one digit, then either the end
-- (with the point required, since a run of digits alone is an int) or an
-- exponent of e/E, an optional sign and at least one more digit. ".5" and
-- "5." are both accepted, matching Psych.
--
-- Scanned a byte at a time rather than matched against
-- "^[-+]?%d*%.?%d*[eE][-+]?%d+$". That pattern is tidier to read and it is
-- a denial of service on hostile input: it holds two "%d*" runs with only
-- an optional "." between them, Lua offers no way to stop a quantifier
-- backtracking, so a long run of digits that turns out not to be a number
-- at all gets retried at every split of that run. A 50 kB scalar of
-- "999...9x" took longer to reject than a five second timeout allowed.
local function is_float_text(text)
  local i, len = 1, #text
  local b = text:byte(i)
  if b == PLUS or b == MINUS then i = i + 1 end

  local digits, dots = 0, 0
  while i <= len do
    b = text:byte(i)
    if b >= DIGIT_ZERO and b <= DIGIT_NINE then
      digits = digits + 1
    elseif b == DOT then
      dots = dots + 1
      if dots > 1 then return false end
    else
      break
    end
    i = i + 1
  end
  if digits == 0 then return false end
  if i > len then return dots == 1 end

  b = text:byte(i)
  if b ~= LOWER_E and b ~= UPPER_E then return false end
  i = i + 1
  b = text:byte(i)
  if b == PLUS or b == MINUS then i = i + 1 end
  if i > len then return false end
  while i <= len do
    b = text:byte(i)
    if b < DIGIT_ZERO or b > DIGIT_NINE then return false end
    i = i + 1
  end
  return true
end

-- Strips the leading zeros off a digit run, always leaving at least one character behind
-- ("000" -> "0", "0f" -> "f"), so the length checks below see a run's true significant
-- width rather than one padded out by a document that wrote extra zeros.
local function strip_leading_zeros(digits)
  local i = 1
  while i < #digits and digits:byte(i) == DIGIT_ZERO do i = i + 1 end
  return digits:sub(i)
end

-- The true unsigned magnitude of a digit run already known not to fit 64 bits, in floating
-- point rather than Lua's own wraparound integer arithmetic. tonumber("0x" ..
-- ("f"):rep(40), 16) (or the bare 0x literal form, which behaves the same way) reads back as
-- the Lua integer -1: the exact same value a genuine 64-bit all-ones pattern produces, with
-- nothing left afterward to tell an honest bit pattern apart from one that silently wrapped
-- through 128 bits of input to land there by chance.
local function magnitude_as_float(digits, base)
  local n = 0.0
  for i = 1, #digits do
    n = n * base + tonumber(digits:sub(i, i), base)
  end
  return n
end

-- Parses a hex or octal literal's digits (the raw text past its "0x"/"0o" marker) into the
-- integer they name, falling back to a float the same graceful way the plain decimal form
-- above already does via tonumber, for a literal too large for a 64-bit integer to hold at
-- all, rather than wrapping silently through it the way tonumber(text, base) does on its own.
local function check_number_length(text)
  if #text > limits.MAX_NUMBER_DIGITS then
    error("yamlcamel: number exceeds " .. limits.MAX_NUMBER_DIGITS .. " characters")
  end
end

local function parse_radix(raw_digits, base)
  local digits = strip_leading_zeros(raw_digits)
  -- Lua's radix tonumber interprets unsigned 64-bit patterns as signed two's complement.
  -- YAML's unsigned radix spelling still names a positive mathematical integer.
  local signed_max = base == 16 and "7fffffffffffffff" or "777777777777777777777"
  if #digits < #signed_max or (#digits == #signed_max and digits:lower() <= signed_max) then
    local n = tonumber(digits, base)
    return math.tointeger(n) or n
  end
  return magnitude_as_float(digits, base)
end

-- The core schema int forms only (10.3.2), independent of everything else
-- M.resolve also checks (words, floats). Used both for implicit plain
-- scalar resolution and, via yamlcamel.tags, for forcing an explicit
-- !!int tag onto text that would not otherwise become one on its own (a
-- quoted "42", say). Returns nil when `text` isn't a legal int at all.
function M.parse_int(text)
  if text:match(INTEGER_PATTERN) then
    check_number_length(text)
    return math.tointeger(tonumber(text)) or tonumber(text)
  end
  if text:match(OCTAL_PATTERN) then
    check_number_length(text)
    return parse_radix(text:sub(3), 8)
  end
  if text:match(HEX_PATTERN) then
    check_number_length(text)
    return parse_radix(text:sub(3), 16)
  end
  return nil
end

-- The core schema float forms only (10.3.2): a decimal float, or one of
-- the special .inf/-.inf/.nan spellings. Returns nil when `text` isn't a
-- legal float at all.
function M.parse_float(text)
  if POS_INF_WORDS[text] then return math.huge end
  if NEG_INF_WORDS[text] then return -math.huge end
  if NAN_WORDS[text] then return 0 / 0 end
  if is_float_text(text) then check_number_length(text); return tonumber(text) end
  return nil
end

-- The core schema bool spellings only (10.3.2): true/True/TRUE,
-- false/False/FALSE, nothing else (see the module comment for why not
-- yes/no/on/off too). Returns nil, not false, when `text` isn't one of them.
function M.parse_bool(text)
  if TRUE_WORDS[text] then return true end
  if FALSE_WORDS[text] then return false end
  return nil
end

-- The core schema null spellings only (10.3.2): ~, null, Null, NULL, or
-- empty. Returns true/false rather than the null sentinel itself, since a
-- caller forcing !!null wants to know whether `text` was legal, not what
-- to replace it with (always {yamlcamel.null} either way).
function M.is_null_word(text)
  return NULL_WORDS[text] == true
end

function M.resolve(text)
  charset.check_printable(text)
  if #text > limits.MAX_SCALAR_BYTES then error("yamlcamel: scalar exceeds " .. limits.MAX_SCALAR_BYTES .. " bytes") end
  if M.is_null_word(text) then return null end
  local b = M.parse_bool(text)
  if b ~= nil then return b end
  local n = M.parse_int(text)
  if n ~= nil then return n end
  n = M.parse_float(text)
  if n ~= nil then return n end
  return text
end

return M
