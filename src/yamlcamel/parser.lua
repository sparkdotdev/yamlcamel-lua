-- Block-style YAML: mappings and sequences built from indentation, plus the
-- Psych quirk this whole library exists to read comfortably: a sequence
-- nested under a mapping key is emitted at the SAME indentation as the key,
-- not one level deeper.
local scalar = require("yamlcamel.scalar")
local quoted = require("yamlcamel.quoted")
local flow = require("yamlcamel.flow")
local null = require("yamlcamel.null")
local anchors = require("yamlcamel.anchors")
local props = require("yamlcamel.props")
local tags = require("yamlcamel.tags")
local limits = require("yamlcamel.limits")
local charset = require("yamlcamel.charset")
local whitespace = require("yamlcamel.whitespace")

local M = {}

-- Resolved block-scalar bodies, keyed by an index a sentinel in a line's
-- content points at. Reset once per {M.parse} call, since scalar values
-- never cross calls.
local block_bodies

-- A sentinel content can never collide with, since it is built from a byte
-- yamlcamel.charset rejects before any of this runs. That check is what
-- makes the guarantee real: while the stream was taken on trust, a document
-- carrying a raw 0x01 could forge one of these and make its own mapping
-- entry vanish, or point at a block scalar belonging to another node
-- entirely, another document in the same stream included.
local BLOCK_SENTINEL = "\1"

-- Whether a quote character at position i of str can plausibly begin a new
-- quoted token, rather than being an apostrophe inside an already-started
-- plain scalar ("don't", "it's"). YAML never opens a quote mid-word, so
-- this only says yes at the start of the string or right after a
-- non-word character.
local function quote_can_open(str, i)
  if i == 1 then return true end
  return not str:sub(i - 1, i - 1):match("[%w_]")
end

local function strip_comment(raw)
  -- The overwhelmingly common line carries neither a quote nor a "#" at
  -- all, and the scan below costs a string allocation per byte, enough on
  -- its own to make a megabyte of ordinary indented YAML take seconds.
  if not raw:find("[#'\"]") then return raw end

  local in_single, in_double = false, false
  local i, len = 1, #raw
  while i <= len do
    local c = raw:sub(i, i)
    if in_single then
      if c == "'" then
        if raw:sub(i + 1, i + 1) == "'" then i = i + 1 else in_single = false end
      end
    elseif in_double then
      if c == "\\" then
        i = i + 1
      elseif c == '"' then
        in_double = false
      end
    else
      if c == "'" and quote_can_open(raw, i) then
        in_single = true
      elseif c == '"' and quote_can_open(raw, i) then
        in_double = true
      elseif c == "#" and (i == 1 or raw:sub(i - 1, i - 1):match("%s")) then
        charset.check_printable(raw:sub(i))
        return raw:sub(1, i - 1)
      end
    end
    i = i + 1
  end
  return raw
end

-- Net bracket depth opened by `str`, plus whether it ends still inside an
-- open quote, ignoring bracket and quote characters that are themselves
-- inside a quote (or, for a quote character, ones that cannot open a fresh
-- token per {quote_can_open}). Tells an ordinary one-line flow collection
-- or quoted scalar apart from one left open at end of line.
local function scan_line(str)
  -- Same fast path as {strip_comment}: with none of the six characters
  -- this looks for present, the answer is always "balanced, nothing open".
  if not str:find("[%[%]{}'\"]") then return 0, false, false end

  local depth, i, len, in_single, in_double = 0, 1, #str, false, false
  while i <= len do
    local c = str:sub(i, i)
    if in_single then
      if c == "'" then
        if str:sub(i + 1, i + 1) == "'" then i = i + 1 else in_single = false end
      end
    elseif in_double then
      if c == "\\" then
        i = i + 1
      elseif c == '"' then
        in_double = false
      end
    else
      if c == "'" and quote_can_open(str, i) then
        in_single = true
      elseif c == '"' and quote_can_open(str, i) then
        in_double = true
      elseif c == "[" or c == "{" then
        depth = depth + 1
      elseif c == "]" or c == "}" then
        depth = depth - 1
      end
    end
    i = i + 1
  end
  return depth, in_single, in_double
end

local function flow_open_depth(str)
  local depth = scan_line(str)
  return depth
end

-- `line` (already trimmed) begins already inside a quote of type
-- `quote_char`, continuing one opened on an earlier physical line. Returns
-- the raw text up to (not including) the closing quote and the index right
-- after it, or nil when the quote does not close on this line.
local function find_quote_close(line, quote_char)
  local i, len = 1, #line
  while i <= len do
    local c = line:sub(i, i)
    if quote_char == "'" then
      if c == "'" then
        if line:sub(i + 1, i + 1) == "'" then i = i + 2 else return line:sub(1, i - 1), i + 1 end
      else
        i = i + 1
      end
    else
      if c == "\\" then
        i = i + 2
      elseif c == '"' then
        return line:sub(1, i - 1), i + 1
      else
        i = i + 1
      end
    end
  end
  return nil
end

local function is_seq_item_content(content)
  return content == "-" or content:sub(1, 2) == "- "
end

local function seq_item_remainder(content)
  if content == "-" then return "" end
  return content:sub(3)
end

-- "?" marks an explicit mapping key (7.4.4, 8.2.3): the more general form
-- that lets a key be something other than a single scalar token safe to
-- write ahead of a bare ":" ("? key" / ": value" on separate lines, rather
-- than the ordinary "key: value" one split_mapping_line reads). Mirrors
-- {is_seq_item_content}/{seq_item_remainder}'s own "-" handling: a lone "?"
-- or ":" is never a valid plain scalar start on its own either (the same
-- indicator-character rule that rules out a lone "-"), so recognizing it
-- this way never collides with an ordinary scalar.
local function is_explicit_key_content(content)
  return content == "?" or content:sub(1, 2) == "? "
end

local function explicit_key_remainder(content)
  if content == "?" then return "" end
  return content:sub(3)
end

local function is_explicit_value_content(content)
  return content == ":" or content:sub(1, 2) == ": "
end

local function explicit_value_remainder(content)
  if content == ":" then return "" end
  return content:sub(3)
end

-- Splits "key: value" into its resolved key and the (still raw) value text,
-- or returns nil when +content+ is not a mapping entry at all. The key may
-- be quoted; a plain key stops at the first ": " or a trailing ":" that
-- sits outside any flow collection or quote, so a line that is really just
-- a flow mapping ("{a: 1}") is never mistaken for a "key: value" pair.
local function split_mapping_line(content)
  local c0 = content:sub(1, 1)
  local key, colon_pos

  if c0 == '"' or c0 == "'" then
    local reader = c0 == '"' and quoted.read_double or quoted.read_single
    -- A speculative read: `content` may be a quoted scalar's opening line
    -- with the close on a later physical line (a multi-line value, not a
    -- key at all), which reader() has no way to know here and would
    -- otherwise raise "unterminated" for. That's not a mapping line
    -- either way, so treat the raise the same as "no colon found".
    local ok, raw_key, after_key = pcall(reader, content, 1)
    if not ok then return nil end
    local j = after_key
    while content:sub(j, j) == " " do j = j + 1 end
    if content:sub(j, j) ~= ":" then return nil end
    key, colon_pos = raw_key, j
  else
    -- No ":" anywhere means no mapping entry, without paying a string
    -- allocation per byte to find that out on a long line.
    if not content:find(":", 1, true) then return nil end

    local len = #content
    local j, depth, in_single, in_double = 1, 0, false, false
    while j <= len do
      local c = content:sub(j, j)
      if in_single then
        if c == "'" then
          if content:sub(j + 1, j + 1) == "'" then j = j + 1 else in_single = false end
        end
      elseif in_double then
        if c == "\\" then
          j = j + 1
        elseif c == '"' then
          in_double = false
        end
      else
        if c == "'" and quote_can_open(content, j) then
          in_single = true
        elseif c == '"' and quote_can_open(content, j) then
          in_double = true
        elseif c == "[" or c == "{" then
          depth = depth + 1
        elseif c == "]" or c == "}" then
          depth = depth - 1
        elseif c == ":" and depth == 0 and (j == len or content:sub(j + 1, j + 1) == " ") then
          colon_pos = j
          break
        end
      end
      j = j + 1
    end
    if not colon_pos then return nil end
    local raw_key = whitespace.trim(content:sub(1, colon_pos - 1))
    if raw_key == "" then return nil end
    key = scalar.resolve(raw_key)
  end

  local value_str = whitespace.trim(content:sub(colon_pos + 1))
  return key == null and null or tostring(key), value_str
end

-- Whether `content` opens a block mapping: an ordinary "key: value" entry, or
-- either half of the explicit "? key" / ": value" form (8.2.3), a ": value"
-- with no "? key" ahead of it being an entry under a null key.
local function opens_mapping(content)
  return split_mapping_line(content) ~= nil
    or is_explicit_key_content(content)
    or is_explicit_value_content(content)
end

-- Parses a full block scalar header ("|", "|-1", "|1-", ">2", ...) into its
-- style, chomping indicator and explicit indentation depth. YAML 8.1.1's
-- c-b-block-header doesn't privilege chomp-then-indent over indent-then-
-- chomp, so both "|-1" and "|1-" are accepted. The indentation digit is
-- restricted to 1-9: c-indentation-indicator excludes 0 on purpose, since an
-- explicit indent of zero is meaningless, and a caller that tolerated it
-- would end up with block_indent stuck at 0, a value no line's indentation
-- can ever fall short of, so the block reader would never stop. Nil when
-- `header` isn't a valid header at all.
local function parse_block_header(header)
  local style, text = header:match("^([|>])(.*)$")
  if not style then return nil end
  if text == "" then return style, nil, nil end
  local chomp_only = text:match("^([%-%+])$")
  if chomp_only then return style, chomp_only, nil end
  local indent_only = text:match("^([1-9])$")
  if indent_only then return style, nil, tonumber(indent_only) end
  local chomp, indent = text:match("^([%-%+])([1-9])$")
  if chomp then return style, chomp, tonumber(indent) end
  indent, chomp = text:match("^([1-9])([%-%+])$")
  if indent then return style, chomp, tonumber(indent) end
  return nil
end

-- The prefix ("key:" or "-", or "" when the whole document is directly a
-- block scalar with no key or dash at all), any &anchor and/or !tag
-- between the prefix and the indicator, and the block-scalar indicator
-- itself, when `content` is exactly a mapping or sequence value standing
-- alone as one of the four header forms ("|", "|-", "|+", ">", with an
-- optional trailing explicit indentation digit in either order around the
-- chomping indicator). Nil when `content` is not a block scalar header at
-- all, which is the ordinary case for every other line.
local function block_indicator_split(content)
  local prefix, rest
  local key, value_str = split_mapping_line(content)
  if key then
    prefix = whitespace.trim(content:sub(1, #content - #value_str))
    rest = value_str
  elseif is_seq_item_content(content) then
    prefix, rest = "-", seq_item_remainder(content)
  elseif is_explicit_key_content(content) then
    prefix, rest = "?", explicit_key_remainder(content)
  elseif is_explicit_value_content(content) then
    prefix, rest = ":", explicit_value_remainder(content)
  else
    prefix, rest = "", content
  end

  local anchor, tag, indicator = props.strip(rest)
  if not parse_block_header(indicator) then return nil end
  return prefix, indicator, anchor, tag
end

-- How far past a line's own indentation the node owning a block scalar
-- header sits: 0 for the ordinary "key: |", and 2 for the compact
-- "- key: |", where the dash is at the line's indentation while the key
-- holding the header is two columns deeper. A block scalar's content has
-- to clear its parent node's indentation (8.1.1.1), so measuring it
-- against the line swallows the mapping's next entry, which is written at
-- exactly the key's own column. Each peel counts the same two columns
-- {parse_sequence}/{parse_mapping} nest a compact child at, keeping the
-- block's baseline and the column its siblings are read at together.
local function header_node_offset(content)
  local i, offset, len = 1, 0, #content
  local peeled = false
  -- `i` only ever moves forward and nothing is copied per marker, so a line
  -- of nothing but "- " stays linear.
  while i <= len do
    local c = content:sub(i, i)
    if (c == "-" or c == "?" or c == ":") and (i == len or content:sub(i + 1, i + 1) == " ") then
      if peeled then offset = offset + 2 end
      peeled = true
      i = i + 2
      while content:sub(i, i) == " " do i = i + 1 end
    else
      break
    end
  end
  -- A key written after those markers owns the header in place of the last
  -- marker, at the cost of one tail copy for the whole line.
  if peeled and i <= len and split_mapping_line(content:sub(i)) then offset = offset + 2 end
  return offset
end

-- Whether a folded block's raw content line (block indent already stripped)
-- sits deeper than the block's own indentation. YAML keeps such a line
-- literal instead of folding it into the surrounding paragraph.
local function is_more_indented(line)
  return line:sub(1, 1) == " " or line:sub(1, 1) == "\t"
end

-- Joins the captured raw content lines of a block scalar into the string it
-- resolves to, applying literal ("|") or folded (">") line handling and the
-- chomping indicator ("-" strip, "+" keep, clip by default).
local function resolve_block_scalar(raw_lines, style, chomp, ended_with_break)
  local trailing_blanks = 0
  local n = #raw_lines
  while n > 0 and raw_lines[n] == "" do
    n = n - 1
    trailing_blanks = trailing_blanks + 1
  end

  local body
  if n == 0 then
    body = ""
  elseif style == "|" then
    local content = {}
    for i = 1, n do content[i] = raw_lines[i] end
    body = table.concat(content, "\n")
  else
    local parts = {}
    for i = 1, n do
      local line = raw_lines[i]
      if line == "" then
        parts[#parts + 1] = "\n"
      elseif i > 1 and raw_lines[i - 1] ~= "" then
        if is_more_indented(line) or is_more_indented(raw_lines[i - 1]) then
          parts[#parts + 1] = "\n" .. line
        else
          parts[#parts + 1] = " " .. line
        end
      else
        parts[#parts + 1] = line
      end
    end
    body = table.concat(parts)
  end

  if chomp == "-" then return body end
  if chomp == "+" then
    return body .. string.rep("\n", trailing_blanks + ((n > 0 and ended_with_break) and 1 or 0))
  end
  return n == 0 and "" or (body .. (ended_with_break and "\n" or ""))
end

-- The scalar text a "key:", "- ", "? " or ": " line (or a bare root
-- scalar) actually carries, peeling off any such prefix to reach it, and
-- the indentation a continuation line has to clear: unchanged right after
-- a "- ", "? " or ": " peel on its own (the value lines up with its
-- sibling markers), but shifted two deeper when ANOTHER such one-character
-- marker follows compact-written on that same peel's own remainder ("-
-- key: value", "? - a", "- ? k"...), since that inner marker sits at the
-- outer one's indent plus two, exactly where {parse_mapping}/
-- {parse_sequence}/{parse_explicit_remainder} nest its own siblings. A
-- "key:" peel never triggers that shift for whatever follows it, since
-- nothing can compact-nest directly onto an ordinary mapping value's own
-- line the way it can onto "-", "?" or ":". Nil when the line's own
-- inline value is empty, since that means a nested block follows on later
-- lines rather than a scalar continuing onto them.
--
-- The third return value, `had_peel`, tells the caller which of the two
-- indentation rules a continuation line has to clear (6.5, 6.6): when a
-- peel happened, `indent` is the PREFIX's own column, and a continuation
-- has to be indented MORE than it, clearing the prefix and the scalar's
-- own text alongside it ("key: first\n  second" continues at indent+2,
-- past "key: "). When nothing was peeled at all, this scalar started
-- bare on its own line to begin with (the "key:"/"-"/"?"/":" that
-- introduces it, if any, is a separate, earlier line entirely), so
-- `indent` is already the scalar's own first-line column, and a
-- continuation only has to match or clear THAT, not exceed it: real YAML
-- lets a scalar's later lines sit at the SAME indentation as its first
-- one, not only deeper, unlike the block-scalar "more-indented stays
-- literal" rule this library also has, which does not apply here.
local function plain_value_text(content, indent)
  local prev_needs_bump = false
  local had_peel = false
  -- Every peel is one more level of compact nesting written onto a single
  -- line, so the same ceiling the parse itself is held to applies here.
  -- Without it a line of nothing but markers costs a fresh copy of its own
  -- tail per marker: "a: " and then ": " half a million times is a
  -- megabyte of input and six seconds of substring copying.
  local peels = 0
  while true do
    peels = peels + 1
    if peels > limits.MAX_DEPTH then
      error("yamlcamel: input nests deeper than " .. limits.MAX_DEPTH .. " levels")
    end
    if is_seq_item_content(content) then
      if prev_needs_bump then indent = indent + 2 end
      local remainder = seq_item_remainder(content)
      if remainder == "" then return nil end
      content = remainder
      prev_needs_bump = true
      had_peel = true
    elseif is_explicit_key_content(content) then
      if prev_needs_bump then indent = indent + 2 end
      local remainder = explicit_key_remainder(content)
      if remainder == "" then return nil end
      content = remainder
      prev_needs_bump = true
      had_peel = true
    elseif is_explicit_value_content(content) then
      if prev_needs_bump then indent = indent + 2 end
      local remainder = explicit_value_remainder(content)
      if remainder == "" then return nil end
      content = remainder
      prev_needs_bump = true
      had_peel = true
    else
      local key, value_str = split_mapping_line(content)
      if key then
        if prev_needs_bump then indent = indent + 2 end
        if value_str == "" then return nil end
        content = value_str
        prev_needs_bump = false
        had_peel = true
      else
        return content, indent, had_peel
      end
    end
  end
end

-- Whether `text` (a would-be same-indentation continuation line, already
-- stripped of its own comment, leading and trailing whitespace) is
-- actually something structurally significant rather than more scalar
-- text: a document/stream marker, or the start of a new mapping entry,
-- sequence item, or explicit key/value. Only matters for a
-- same-indentation continuation candidate: a plain scalar has no way to
-- unambiguously contain one of these at the START of one of its own
-- lines (7.1, 8.2.1), unlike a MORE-indented line, which is already
-- unambiguously inside the scalar regardless of what it looks like.
local function looks_like_new_node(text)
  return text == "---" or text:match("^%-%-%-%s") or text == "..." or text:match("^%%")
    or is_seq_item_content(text)
    or split_mapping_line(text) ~= nil
    or is_explicit_key_content(text)
    or is_explicit_value_content(text)
end

-- A directive line ahead of a `---`: `%YAML major.minor` (9.1.3, checked
-- against the major version only, since this library's schema behavior
-- doesn't switch on the minor one) or `%TAG handle prefix` (7.1.7),
-- registered into `handles` for yamlcamel.tags to expand a named or
-- primary tag handle against once this document starts parsing.
local function check_directive(stripped, lineno, handles)
  charset.check_printable(stripped)
  local major = stripped:match("^%%YAML%s+(%d+)%.%d+%s*$")
  if major then
    if major ~= "1" then
      error("yamlcamel: unsupported YAML version directive on line " .. lineno .. ": " .. stripped)
    end
    return
  end
  if stripped:match("^%%YAML%s") then
    error("yamlcamel: malformed %YAML directive on line " .. lineno .. ": " .. stripped)
  end

  local handle, prefix = stripped:match("^%%TAG%s+(%S+)%s+(%S+)%s*$")
  if handle then
    if not (handle == "!" or handle == "!!" or handle:match("^!.+!$")) then
      error("yamlcamel: malformed %TAG handle on line " .. lineno .. ": " .. stripped)
    end
    -- Bounded on its own raw byte length here, before it is ever registered, let alone
    -- concatenated onto a suffix: yamlcamel.tags re-concatenates this prefix in full at
    -- every single use of the handle, so an unbounded one turns a short document into an
    -- unbounded amount of work at decode time instead of at the (much smaller) cost of
    -- writing the %TAG line itself. See {yamlcamel.limits}.MAX_TAG_PREFIX_BYTES.
    if #prefix > limits.MAX_TAG_PREFIX_BYTES then
      error("yamlcamel: %TAG prefix longer than " .. limits.MAX_TAG_PREFIX_BYTES
        .. " bytes on line " .. lineno)
    end
    handles[handle] = prefix
    return
  end
  if stripped:match("^%%TAG%s") then
    error("yamlcamel: malformed %TAG directive on line " .. lineno .. ": " .. stripped)
  end

  -- Any other directive (6.8.1: "a YAML processor should ignore unknown
  -- directives with an appropriate warning"). Tolerated, not acted on.
end

-- Splits `text` into one { lines, handles } table per document in the
-- stream, honoring `---` and `...` as real document boundaries (9.1, 9.2)
-- rather than swallowing them into a single flat parse. Each line carries
-- its indentation depth and its comment-stripped content; blank and
-- comment-only lines are dropped outright. Four shapes swallow more than
-- their own physical line within a document: a flow collection left open
-- at end of line pulls in following lines until its brackets balance, a
-- quoted scalar left open the same way pulls in lines until its closing
-- quote, a block scalar header pulls in every following line indented
-- past it (storing the resolved string behind a sentinel
-- {parse_inline_value} reads back rather than re-parsing as YAML syntax),
-- and a plain scalar Psych's own line width wrapped across lines, which no
-- header marks, so it's recognised by what is left once the other three
-- are ruled out and pulled in the same way a block scalar is, by
-- indentation alone. None of the four ever crosses a document boundary,
-- since `---`/`...` always sit at indentation 0, at or below every open
-- construct's own starting indentation.
local function tokenize_stream(text)
  if #text > limits.MAX_INPUT_BYTES then
    error("yamlcamel: input exceeds " .. limits.MAX_INPUT_BYTES .. " bytes")
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local raw = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    raw[#raw + 1] = line
  end

  -- The appended separator terminates an unterminated last line; it must not create
  -- an additional empty content line when the source already ends in a newline.
  local ended_with_break = text:sub(-1) == "\n"
  if ended_with_break then table.remove(raw) end
  local documents = {}
  local lines = {}
  local handles = {}
  -- Directives sit between the end of one document and the "---" that
  -- starts the next, so they can't register straight into `handles`:
  -- that still belongs to whichever document is currently accumulating
  -- (or just finished). They land here instead, and {finish_document}
  -- hands them off to `handles` once a new document actually begins.
  local pending_handles = {}
  local started = false
  -- {yamlcamel.charset}.check already stripped a byte order mark at the very start of
  -- `text`, but 5.2 allows one to open any document in a stream, not only the first, and
  -- that whole-stream check never looks past its own first byte. Left in place, a BOM
  -- before document two lands on that document's own first line as three ordinary bytes,
  -- gluing itself onto whatever key or scalar starts there instead of being recognized as
  -- a marker at all: M.decode_all and M.decode_file_stream used to disagree on the exact
  -- same input for this reason, since the latter parses each document through a fresh call
  -- to M.parse, which strips its own leading BOM independently.
  local at_document_start = true

  local function finish_document()
    if #lines > 0 or started then
      documents[#documents + 1] = { lines = lines, handles = handles }
    end
    lines = {}
    handles = pending_handles
    pending_handles = {}
    started = false
    at_document_start = true
  end

  local i, total = 1, #raw
  while i <= total do
    if at_document_start then
      if raw[i]:sub(1, #charset.BOM) == charset.BOM then
        raw[i] = raw[i]:sub(#charset.BOM + 1)
      end
      at_document_start = false
    end
    local lineno = i
    local comment_stripped = strip_comment(raw[i])
    -- Whether raw[i] itself carried a trailing comment: a comment ends
    -- whatever plain-scalar content precedes it on that physical line for
    -- good (6.9), so a line like this can never fold into a following one
    -- the way an uncommented line can; see the same-indentation
    -- continuation check below.
    local line_had_comment = #comment_stripped < #raw[i]
    local stripped = whitespace.rstrip(comment_stripped)
    if stripped:match("^%%") then
      -- A directive precedes a document, it doesn't complete one, so it
      -- must not make the "---" that follows it think a (phantom, empty)
      -- document just ended.
      check_directive(stripped, lineno, pending_handles)
      i = i + 1
    elseif stripped:match("^%s*$") then
      -- blank or comment-only, skip
      i = i + 1
    elseif stripped == "---" then
      finish_document()
      started = true
      i = i + 1
    elseif stripped:match("^%-%-%-%s") then
      finish_document()
      -- Unlike the bare "---" case, this document's content starts right here on the same
      -- line rather than on the next one, so there is no fresh line left for a BOM to open;
      -- finish_document's own at_document_start = true would otherwise wrongly reach past
      -- this line and strip three ordinary content bytes off whatever follows it instead.
      at_document_start = false
      started = true
      local inline = stripped:match("^%-%-%-%s+(.*)$")
      if inline and inline ~= "" then
        lines[#lines + 1] = { indent = 0, content = inline, lineno = lineno }
      end
      i = i + 1
    elseif stripped == "..." then
      finish_document()
      i = i + 1
    else
      local indent_str = stripped:match("^( *)")
      if stripped:sub(#indent_str + 1, #indent_str + 1) == "\t" then
        error("yamlcamel: tab used for indentation on line " .. lineno)
      end
      local indent = #indent_str
      local content = stripped:sub(#indent_str + 1)
      local next_i = i + 1

      local prefix, indicator, block_anchor, block_tag = block_indicator_split(content)
      if prefix then
        local style, chomp, explicit_indent = parse_block_header(indicator)
        local node_indent = indent + header_node_offset(content)
        local block_indent = explicit_indent and (node_indent + explicit_indent) or nil
        local block_lines = {}
        local content_ended_with_break = false
        local k = next_i
        while k <= total do
          local raw_k = raw[k]
          local spaces = #(raw_k:match("^( *)"))
          if raw_k:sub(spaces + 1) == "" then
            local text = block_indent and spaces > block_indent and raw_k:sub(block_indent + 1) or ""
            local has_break = k < total or ended_with_break
            if text ~= "" or has_break then block_lines[#block_lines + 1] = text end
            if text ~= "" then content_ended_with_break = has_break end
            k = k + 1
          else
            local this_indent = #(raw_k:match("^( *)"))
            if not block_indent then
              if this_indent <= node_indent then break end
              block_indent = this_indent
            end
            if this_indent < block_indent then break end
            block_lines[#block_lines + 1] = raw_k:sub(block_indent + 1)
            content_ended_with_break = k < total or ended_with_break
            k = k + 1
          end
        end
        local resolved = resolve_block_scalar(block_lines, style, chomp, content_ended_with_break)
        block_bodies[#block_bodies + 1] = resolved
        local sentinel = BLOCK_SENTINEL .. #block_bodies .. BLOCK_SENTINEL
        -- Re-serialize any node properties ahead of the sentinel, in
        -- canonical anchor-then-tag order regardless of how they were
        -- written, so {parse_inline_value} picks them up like any other
        -- value's properties once this line is parsed for real.
        local block_props = (block_anchor and ("&" .. block_anchor .. " ") or "")
          .. (block_tag and (block_tag .. " ") or "")
        content = (prefix == "" and "" or (prefix .. " ")) .. block_props .. sentinel
        next_i = k
      else
        local depth, in_single, in_double = scan_line(content)
        local candidate, baseline, had_peel = plain_value_text(content, indent)
        -- What this line's own value actually starts with, past any
        -- "key:"/"-"/"?"/":" prefix and any node properties. Whether a
        -- quote or a bracket is left open at end of line only means the
        -- node continues onto the following lines when the node BEGINS
        -- with that quote or bracket. Reading an unbalanced one anywhere
        -- else as an open construct is how a stray "[" in the middle of an
        -- ordinary plain scalar ("name: foo[bar") used to swallow every
        -- line after it, silently dropping whatever keys were down there.
        local inline = candidate and select(3, props.strip(candidate)) or ""
        local opener = inline:sub(1, 1)
        local quote_char = in_single and "'" or '"'
        if depth == 0 and (in_single or in_double) and opener == quote_char then
          -- A quoted scalar left open at end of line: Psych wraps any long
          -- quoted string at its own line width, so this is the ordinary
          -- case for message bodies and the like, not an edge case. Gather
          -- the lines that follow, joined with a literal newline byte per
          -- physical break for {quoted} to fold back per YAML's rule (a
          -- single break folds to a space, more become n-1 real breaks).
          -- Pieces go into a table rather than onto the end of `content`,
          -- since concatenating per physical line makes gathering a long
          -- scalar cost a fresh copy of everything gathered so far.
          local parts = { content }
          local k = i
          local closed = false
          while not closed and k < total do
            k = k + 1
            local raw_k = raw[k]
            if raw_k:match("^%s*$") then
              parts[#parts + 1] = "\n"
            else
              local trimmed = whitespace.trim(raw_k)
              local before, after = find_quote_close(trimmed, quote_char)
              if before then
                parts[#parts + 1] = "\n" .. before .. quote_char
                closed = true
                local tail = whitespace.trim(strip_comment(trimmed:sub(after)))
                if tail ~= "" then parts[#parts + 1] = " " .. tail end
              else
                parts[#parts + 1] = "\n" .. trimmed
              end
            end
          end
          if not closed then
            error("yamlcamel: unterminated " .. (in_single and "single" or "double")
              .. "-quoted scalar starting on line " .. lineno)
          end
          content = table.concat(parts)
          next_i = k + 1
        elseif depth > 0 and (opener == "[" or opener == "{") then
          local parts = { content }
          local k = i
          while depth > 0 and k < total do
            k = k + 1
            local continuation = whitespace.trim(strip_comment(raw[k]))
            if continuation ~= "" then
              parts[#parts + 1] = " " .. continuation
              depth = depth + flow_open_depth(continuation)
            end
          end
          content = table.concat(parts)
          next_i = k + 1
        else
          -- Nothing left open on this line at all. It may still be a plain
          -- scalar wrapped across more than one physical line, Psych's own
          -- line-width wrapping being the common case but not the only
          -- one real YAML allows: a continuation line just has to clear
          -- {plain_value_text}'s own indentation threshold, `>` a peeled
          -- prefix's column or `>=` a bare scalar's own first-line column
          -- (see there for why those differ). A blank line never
          -- continues one, since Psych only wraps at word boundaries and
          -- switches a string with a real embedded break to block style
          -- instead, and real YAML folds a blank line to a literal break
          -- rather than treating it as more scalar text either way. Nor
          -- does a line whose own comment already ended it (6.9): a
          -- comment can only trail a node, never sit inside one, so
          -- nothing folds onward from a commented line regardless of
          -- indentation. A same-indentation candidate (the "unchanged"
          -- side of the `>`/`>=` split above) gets one more check a
          -- more-indented one does not need: whether the candidate line
          -- is itself a document marker or a new entry rather than more
          -- text, since at EQUAL indentation those are genuinely
          -- ambiguous with scalar continuation by indentation alone,
          -- where a deeper line never is.
          local k = i
          local parts = { content }
          if candidate and candidate ~= "" and inline ~= ""
              and not candidate:match("^[\"'%[{]") and not (not had_peel and line_had_comment) then
            while k < total do
              local raw_k = raw[k + 1]
              if raw_k:match("^%s*$") then break end
              local next_indent = #(raw_k:match("^( *)"))
              local trimmed_k
              if had_peel then
                if next_indent <= baseline then break end
              else
                if next_indent < baseline then break end
                trimmed_k = whitespace.trim(strip_comment(raw_k))
                if next_indent == baseline and looks_like_new_node(trimmed_k) then break end
              end
              k = k + 1
              parts[#parts + 1] = "\n" .. (trimmed_k or whitespace.trim(strip_comment(raw_k)))
            end
            content = table.concat(parts)
          end
          next_i = k + 1
        end
      end

      lines[#lines + 1] = { indent = indent, content = content, lineno = lineno }
      started = true
      i = next_i
    end
  end
  finish_document()
  return documents
end

-- A value string that stands alone on the "key:" line or a "- " line: an
-- alias, a flow collection, a quoted scalar, or a plain scalar, optionally
-- preceded by an &anchor and/or a !tag (6.9, 7.1). Never a nested block;
-- that comes from subsequent, more-indented lines instead, via
-- {parse_mapping}/{parse_sequence} calling {parse_nested_value} directly
-- so a placeholder can be registered before recursing, which is what lets
-- an anchored node refer to itself.
local function parse_inline_value(str)
  local alias_name = str:match("^%*(" .. props.NAME .. ")$")
  if alias_name then return anchors.resolve(alias_name) end

  local anchor, tag, rest = props.strip(str)
  if rest:match("^%*") then
    -- An alias node is a pure reference (6.9.2): it can't also carry an
    -- anchor or a tag of its own the way an ordinary node can.
    error("yamlcamel: an alias cannot also carry an anchor or a tag: " .. str)
  end

  local value
  local block_index = rest:match("^" .. BLOCK_SENTINEL .. "(%d+)" .. BLOCK_SENTINEL .. "$")
  if block_index then
    -- A block scalar's body is already unambiguously a string; an
    -- explicit tag can still force a different core type or wrap it.
    value = tags.resolve_string(tag, block_bodies[tonumber(block_index)], true)
  else
    local c0 = rest:sub(1, 1)
    if c0 == "[" or c0 == "{" then
      local collection, next_pos = flow.parse_value(rest, 1)
      if not rest:sub(next_pos):match("^%s*$") then
        error("yamlcamel: unexpected trailing content after flow collection: " .. rest)
      end
      value = tags.resolve_collection(tag, collection)
    elseif c0 == '"' or c0 == "'" then
      local reader = c0 == '"' and quoted.read_double or quoted.read_single
      local str_value, next_pos = reader(rest, 1)
      if not rest:sub(next_pos):match("^%s*$") then
        error("yamlcamel: unexpected trailing content after quoted scalar: " .. rest)
      end
      value = tags.resolve_string(tag, str_value)
    else
      -- Plain scalar (rest == "" counts as one too, an empty implicit
      -- value): the only shape where an explicit tag can actually change
      -- which core type the text becomes, since the raw text is still
      -- available here, ahead of any implicit resolution committing to one.
      local text = rest
      if text:find("\n", 1, true) then
        -- a plain scalar the tokenizer pulled continuation lines into; fold
        -- those physical breaks the same way a multi-line quoted scalar does
        text = quoted.fold_line_breaks(text)
      end
      value = tags.resolve_plain(tag, text)
    end
  end

  if anchor then value = anchors.register(anchor, value) end
  return value
end

local parse_mapping, parse_sequence

-- What a "key:" or "- " line with an empty inline value points at: nothing
-- (a null), a nested sequence, or a nested mapping. A sequence is accepted at
-- the SAME indentation as the line that introduces it, which is what makes
-- Psych's own YAML.dump output parse correctly; a mapping needs to be
-- indented strictly deeper, since two mapping keys at equal indentation are
-- ordinary siblings. `into`, when given, is filled in place and returned
-- rather than building a fresh table, so a placeholder registered under an
-- anchor before recursing is the very table a self-referencing alias
-- inside it resolves to.
local function parse_nested_value(lines, i, parent_indent, into)
  local line = lines[i]
  if not line then return null, i end
  if is_seq_item_content(line.content) and line.indent >= parent_indent then
    return parse_sequence(lines, i, line.indent, nil, into)
  elseif line.indent > parent_indent then
    if opens_mapping(line.content) then
      return parse_mapping(lines, i, line.indent, nil, into)
    end

    -- A node property (an &anchor and/or a !tag) standing alone on its own
    -- line, with the collection it belongs to starting on the very next
    -- line at the SAME indentation as the property itself, rather than
    -- attached directly to a "key:" or "-" the way {nested_props} and
    -- {parse_sequence}'s own remainder handling already read it. Reads the
    -- collection at that shared indentation the same way a bare "key:"
    -- already lets a sequence sit at its own indentation (the Psych
    -- quirk), just with the property line standing in for the "key:".
    local anchor, tag, rest = props.strip(line.content)
    if rest == "" and (anchor or tag) then
      local next_line = lines[i + 1]
      if next_line and next_line.indent == line.indent then
        local is_seq = is_seq_item_content(next_line.content)
        local is_map = not is_seq and opens_mapping(next_line.content)
        if is_seq or is_map then
          -- Register the placeholder only once the next line is confirmed
          -- to actually be a collection start, so a property line that
          -- turns out NOT to be followed by one (falls through below)
          -- never leaves a stale, never-filled placeholder behind.
          local placeholder = anchor and anchors.register(anchor, {}) or into
          local value, next_i
          if is_seq then
            value, next_i = parse_sequence(lines, i + 1, line.indent, nil, placeholder)
          else
            value, next_i = parse_mapping(lines, i + 1, line.indent, nil, placeholder)
          end
          value = tags.resolve_collection(tag, value)
          if anchor then anchors.register(anchor, value) end
          return value, next_i
        end
      end
    end

    -- A more-indented line that is neither a sequence item nor a mapping
    -- entry: a plain, quoted or flow scalar value moved to its own line
    -- rather than staying inline after "key:", which is common enough in
    -- hand-written YAML (a block scalar's "|"/">" is not the only way to
    -- do this). Nothing else may follow at that same depth or deeper: a
    -- scalar has no siblings of its own the way a mapping or sequence
    -- does, so a further line there is not this value continuing, it is
    -- malformed input.
    local next_line = lines[i + 1]
    if next_line and next_line.indent >= line.indent then
      error("yamlcamel: unexpected content after a scalar value on line "
        .. next_line.lineno .. ": " .. next_line.content)
    end
    return parse_inline_value(line.content), i + 1
  else
    return null, i
  end
end

-- A "key:" value's properties (&anchor and/or !tag) and, when there is
-- nothing else on the line, the placeholder its anchor should register
-- against before the nested block that follows is parsed. Returns nil for
-- `rest` when the value is an ordinary inline one (including a bare
-- alias), which is the caller's cue to use {parse_inline_value} instead.
local function nested_props(value_str)
  local anchor, tag, rest = props.strip(value_str)
  if rest ~= "" then return nil end
  local placeholder = anchor and anchors.register(anchor, {}) or nil
  return rest, anchor, tag, placeholder
end

-- Resolves the text past a "key:", "? key" or ": value" marker into a
-- value: the nested block starting on the following, more-indented lines
-- when `remainder` is empty or holds nothing but node properties
-- (registering a bare anchor's placeholder first, same as {nested_props}
-- always did, so a self-reference inside the block can resolve), or
-- `remainder`'s own inline value otherwise. `i` is the index of the line
-- `remainder` itself came from; returns the value and the index of the
-- first line not yet consumed. Shared by parse_mapping's ordinary entries
-- and {parse_explicit_entry}'s key and value sides alike, so the three
-- don't carry their own copies of the same anchor/tag-then-recurse logic.
local function parse_remainder_value(lines, i, indent, remainder)
  local rest, anchor, tag, placeholder = nested_props(remainder)
  if rest then
    local value, next_i = parse_nested_value(lines, i + 1, indent, placeholder)
    value = tags.resolve_collection(tag, value)
    if anchor then anchors.register(anchor, value) end
    return value, next_i
  end
  return parse_inline_value(remainder), i + 1
end

-- Same as {parse_remainder_value}, but for a "? key" or ": value" marker
-- specifically: 8.2.3 additionally lets either side open a nested sequence
-- or mapping compactly, right on the marker's own line ("? - a" / ": - a"),
-- not only on the lines that follow it the way an ordinary "key: value"
-- entry requires. {parse_mapping}'s own compact-nesting checks in
-- {parse_sequence} are the model this follows.
local function parse_explicit_remainder(lines, i, indent, remainder)
  if is_seq_item_content(remainder) then
    return parse_sequence(lines, i, indent + 2, remainder)
  end
  if opens_mapping(remainder) then
    return parse_mapping(lines, i, indent + 2, remainder)
  end
  return parse_remainder_value(lines, i, indent, remainder)
end

-- Parses one "? key" / ": value" explicit mapping entry (7.4.4, 8.2.3),
-- `content` (already known to satisfy {is_explicit_key_content}) being the
-- line at index `i`, both the key and value markers expected at `indent`.
-- Unlike the compact "key: value" form, either side can span a whole
-- nested block of its own (a block scalar, a sequence, another mapping),
-- so this has to track its own line count rather than always advancing by
-- one. The ": value" line is optional; omitting it (or the value on it)
-- means an explicit null, same as an ordinary "key:" with nothing after.
-- The "? key" line is optional too: a ": value" reached with no key line
-- ahead of it is an entry whose key is null.
local function parse_explicit_entry(lines, i, indent, content)
  if is_explicit_value_content(content) then
    local value, value_next_i =
      parse_explicit_remainder(lines, i, indent, explicit_value_remainder(content))
    return null, value, value_next_i
  end

  local key_value, next_i = parse_explicit_remainder(lines, i, indent, explicit_key_remainder(content))
  local key = key_value == null and null or tostring(key_value)

  local vline = lines[next_i]
  if vline and vline.indent == indent and is_explicit_value_content(vline.content) then
    local value, value_next_i =
      parse_explicit_remainder(lines, next_i, indent, explicit_value_remainder(vline.content))
    return key, value, value_next_i
  end
  return key, null, next_i
end

function parse_mapping(lines, i, indent, first_content, into)
  limits.enter()
  local result = into or {}
  local content = first_content
  -- A ": value" with no "? key" ahead of it is only read as a null-keyed entry
  -- where this mapping actually starts. Reached partway through, it is instead
  -- an explicit value line that has dedented away from its own key, which stays
  -- an error rather than quietly attaching itself to the wrong mapping.
  local opening = true
  while true do
    if not content then
      local line = lines[i]
      if not line or line.indent ~= indent then break end
      content = line.content
    end
    if is_seq_item_content(content) then
      error("yamlcamel: expected a mapping entry, found a sequence item: " .. content)
    end

    local key, value
    if is_explicit_key_content(content) or (opening and is_explicit_value_content(content)) then
      key, value, i = parse_explicit_entry(lines, i, indent, content)
    else
      local value_str
      key, value_str = split_mapping_line(content)
      if not key then
        error("yamlcamel: expected 'key: value', found: " .. content)
      end
      value, i = parse_remainder_value(lines, i, indent, value_str)
    end
    result[key] = value
    content = nil
    opening = false
  end
  limits.leave()
  return result, i
end

-- A sequence item's remainder past "- " may itself start another sequence
-- ("- - x", a nested list flattened onto the dash's own line) or a mapping
-- ("- key: value", by far the most common shape here: a list of records).
-- Node properties are stripped and checked against the remainder that is
-- left, not the raw text, so "- &a key: value" anchors the {key = value}
-- mapping itself rather than folding "&a key" into the mapping's own key.
function parse_sequence(lines, i, indent, first_content, into)
  limits.enter()
  local result = into or {}
  local content = first_content
  while true do
    if not content then
      local line = lines[i]
      if not line or line.indent ~= indent or not is_seq_item_content(line.content) then break end
      content = line.content
    end
    local remainder = seq_item_remainder(content)

    local value
    if remainder == "" then
      value, i = parse_nested_value(lines, i + 1, indent)
    else
      local anchor, tag, rest = props.strip(remainder)
      if rest == "" then
        local placeholder = anchor and anchors.register(anchor, {}) or nil
        value, i = parse_nested_value(lines, i + 1, indent, placeholder)
        value = tags.resolve_collection(tag, value)
        if anchor then anchors.register(anchor, value) end
      elseif is_seq_item_content(rest) then
        value, i = parse_sequence(lines, i, indent + 2, rest)
        value = tags.resolve_collection(tag, value)
        if anchor then anchors.register(anchor, value) end
      elseif opens_mapping(rest) then
        value, i = parse_mapping(lines, i, indent + 2, rest)
        value = tags.resolve_collection(tag, value)
        if anchor then anchors.register(anchor, value) end
      else
        value = parse_inline_value(remainder)
        i = i + 1
      end
    end
    result[#result + 1] = value
    content = nil
  end
  limits.leave()
  return result, i
end

-- Parses one already-tokenized document ({ lines, handles }) into its
-- root value. An empty document, or one holding only `null`, both resolve
-- to {yamlcamel.null}. Anchors reset per document (6.9.2), and so does the
-- %TAG handle table (7.1.7): neither an anchor's namespace nor a tag
-- handle's meaning crosses from one document into another.
local function parse_document(document)
  anchors.reset()
  tags.reset(document.handles)
  limits.reset()
  local lines = document.lines
  if #lines == 0 then return null end

  local first = lines[1]
  if #lines == 1 and not is_seq_item_content(first.content) and not opens_mapping(first.content) then
    return parse_inline_value(first.content)
  end

  local value, next_line = parse_nested_value(lines, 1, -1)
  if next_line <= #lines then
    error("yamlcamel: unexpected content after document root on line " .. lines[next_line].lineno)
  end
  return value
end

-- Parses `text` as a single document and returns its root value. A stream
-- of more than one document decodes just the first, silently; see
-- {M.parse_all} for every document in stream order. `block_bodies` is
-- reset once here (not per document) since {tokenize_stream} resolves
-- every document's block scalars in one pass, ahead of parsing any of
-- them, and each sentinel's index is unique across the whole stream.
function M.parse(text)
  block_bodies = {}
  limits.reset()
  local documents = tokenize_stream(charset.check(text))
  if #documents == 0 then return null end
  return parse_document(documents[1])
end

-- Parses every document in `text` and returns their root values as a Lua
-- array, one entry per document, in stream order. A blank or entirely
-- commented-out stream has zero documents, so this returns an empty
-- array rather than a single null the way {M.parse} does for the same
-- input, since there is nothing to decode "the first document" of.
function M.parse_all(text)
  block_bodies = {}
  limits.reset()
  local documents = tokenize_stream(charset.check(text))
  local values = {}
  for idx, document in ipairs(documents) do
    values[idx] = parse_document(document)
  end
  return values
end

return M
