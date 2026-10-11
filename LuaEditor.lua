local _, addon = ...
local Editor = {}
addon.Query = addon.Query or {}
addon.Query.Editor = Editor

Editor.keywords = {}
for word in ("and break do else elseif end for function goto if in local not or repeat return then until while"):gmatch("%S+") do Editor.keywords[word] = true end
Editor.colors = { keyword = "ffc586c0", literal = "ff569cd6", number = "ffb5cea8", string = "ffce9178", comment = "ff6a9955", call = "ffdcdcaa", operator = "ffd4d4d4", identifier = "ffd4d4d4", punctuation = "ffd4d4d4" }

Editor.colors.localVariable = "ffd4d4d4"
Editor.colors.globalVariable = "ff9cdcfe"
Editor.colors.parameter = "ff9cdcfe"
Editor.colors.functionName = "ffdcdcaa"
Editor.colors.blizzardFunction = "ff4ec9b0"
function Editor:Color(kind)
 local db = addon.Workspace and addon.Workspace.db
 local colors = db and db.options.syntaxColors
 local value = colors and colors[kind]
 if type(value) == 'string' and value:match('^%x%x%x%x%x%x$') then return 'ff' .. value end
 return self.colors[kind]
end

function Editor:SetColor(kind, value)
 if not self.colors[kind] then return false end
 if value and not value:match('^%x%x%x%x%x%x$') then return false end
 local options = addon.Workspace.db.options
 options.syntaxColors = options.syntaxColors or {}
 options.syntaxColors[kind] = value and value:lower() or nil
 self.colorRevision = (self.colorRevision or 0) + 1
 if addon.Query.Console.input then self:Paint(addon.Query.Console.input) end
 return true
end

function Editor:ResetColors()
 addon.Workspace.db.options.syntaxColors = nil
 self.colorRevision = (self.colorRevision or 0) + 1
 if addon.Query.Console.input then self:Paint(addon.Query.Console.input) end
end

function Editor:IndentWidth()
 return addon.Workspace and addon.Workspace.db and addon.Workspace.db.options.indentWidth or 4
end

function Editor:Tokenize(source, maxTokens)
 local tokens, index, length = {}, 1, #source
 local function add(kind, finish, closed)
  tokens[#tokens + 1] = { kind = kind, text = source:sub(index, finish), start = index, finish = finish, closed = closed }
  index = finish + 1
 end
 local function ending(pattern, offset)
  local first, last = source:find(pattern, offset or index)
  if first == (offset or index) then return last end
 end
 local function longEnd(start)
  local head = ending('^%[=*%[', start)
  if not head then return end
  local close = ']' .. source:sub(start + 1, head - 1) .. ']'
  local position = source:find(close, head + 1, true)
  return position and position + #close - 1 or length, position ~= nil
 end
 while index <= length do
  if maxTokens and #tokens >= maxTokens then
   add('plain', length)
   tokens[#tokens].truncated = true
   break
  end
  local char, pair = source:sub(index, index), source:sub(index, index + 1)
  if char == '\n' then add('newline', index)
  elseif char:match('[ \t\r]') then add('space', ending('^[ \t\r]+'))
  elseif pair == '--' then
   local finish, closed = longEnd(index + 2)
   add('comment', finish or ((source:find('\n', index, true) or (length + 1)) - 1), closed)
  elseif char == '"' or char == "'" then
   local finish, closed = index + 1, false
   while finish <= length do
    local nextChar = source:sub(finish, finish)
    if nextChar == '\\' then finish = finish + 2
    elseif nextChar == char then finish = finish + 1; closed = true; break
    else finish = finish + 1 end
   end
   add('string', math.min(length, finish - 1), closed)
  elseif char == '[' and longEnd(index) then
   local finish, closed = longEnd(index); add('string', finish, closed)
  elseif char:byte() >= 128 then
   -- Never place color escapes between bytes of a UTF-8 character.
   -- Non-ASCII text is retained without treating it as a valid Lua identifier.
   add('plain', ending('^[\128-\255]+'))
  elseif char:match('[%a_]') then
   local finish = ending('^[%a_][%w_]*')
   local word = source:sub(index, finish)
   local kind = (word == 'nil' or word == 'true' or word == 'false') and 'literal' or (self.keywords[word] and 'keyword' or 'identifier')
   if kind == 'identifier' and ending('^%s*%(', finish + 1) then kind = 'call' end
   add(kind, finish)
  elseif char:match('%d') or (char == '.' and pair:sub(2, 2):match('%d')) then
   local finish = ending('^0[xX][%da-fA-F]+')
   if not finish then
    finish = ending('^%d+') or index - 1
    if source:sub(finish + 1, finish + 1) == '.' and source:sub(finish + 2, finish + 2) ~= '.' then finish = ending('^%.%d*', finish + 1) end
    finish = ending('^[eE][+-]?%d+', finish + 1) or finish
   end
   add('number', finish)
  else
   local operator = source:sub(index, index + 2) == '...' and '...' or (pair == '..' or pair == '::' or pair:match('^[~=<>]=$')) and pair or char
   add(operator:match('[+%-%*/%%%^#=<>~]') and 'operator' or 'punctuation', index + #operator - 1)
  end
 end
 return tokens
end

function Editor:Render(source)
 local result, spans, offset = {}, {}, 0
 local tokens = addon.Analysis and addon.Analysis:Get(source).tokens or self:Tokenize(source)
 local apiPaths = addon.APIHelp and addon.APIHelp:Paths(source) or {}
 for _, token in ipairs(tokens) do
  local text = token.text:gsub('|', '||')
  local color = self:Color(apiPaths[token.start] and 'blizzardFunction' or token.semanticKind or token.kind)
  local rendered = color and ('|c' .. color .. text .. '|r') or text
  local first = offset + (color and 10 or 0) + 1
  spans[#spans + 1] = { first = first, last = first + #text - 1, source = token.start, text = token.text, kind = token.kind }
  result[#result + 1] = rendered
  offset = offset + #rendered
 end
 return table.concat(result), spans
end

-- Native font-string indices include markup; editor/token offsets use source bytes.
function Editor:SourcePosition(input, position)
 local spans = input.queryEditor and input.queryEditor.renderSpans
 if not spans or type(position) ~= 'number' then return end
 local low, high = 1, #spans
 while low <= high do
  local middle = math.floor((low + high) / 2)
  local span = spans[middle]
  if position < span.first then high = middle - 1
  elseif position > span.last then low = middle + 1
  else
   local offset = position - span.first
   if not span.text:find('|', 1, true) then return span.source + offset end
   local rendered = 0
   for index = 1, #span.text do
    rendered = rendered + (span.text:sub(index, index) == '|' and 2 or 1)
    if rendered > offset then return span.source + index - 1 end
   end
   return
  end
 end
end

-- Use the same native character rectangles as visible text selection. This
-- avoids multiline coordinate-to-index results that select an adjacent row.
function Editor:HoverSourcePosition(input, x, y)
 local state = input.queryEditor
 local font = state and state.overlay
 if not font or type(font.CalculateScreenAreaFromCharacterSpan) ~= 'function' then return end
 local left, bottom = font:GetLeft(), font:GetBottom()
 if not left or not bottom then return end
 local cache = state.hoverAreas
 local height, width = font:GetHeight(), font:GetWidth()
 local face, size, flags = font:GetFont()
 local spacing = font:GetSpacing()
 local lines = font.GetNumLines and font:GetNumLines()
 local textHeight = font:GetStringHeight()
 local scale = font:GetEffectiveScale()
 local advance = type(lines) == 'number' and lines > 0 and (textHeight + spacing) / lines
 if not cache or cache.spans ~= state.renderSpans or cache.height ~= height or cache.width ~= width
  or cache.face ~= face or cache.size ~= size or cache.flags ~= flags or cache.spacing ~= spacing
  or cache.lines ~= lines or cache.textHeight ~= textHeight or cache.scale ~= scale then
  cache = { spans = state.renderSpans, height = height, width = width, face = face, size = size, flags = flags, spacing = spacing, lines = lines, textHeight = textHeight, scale = scale, entries = {} }
  for _, span in ipairs(state.renderSpans or {}) do
   if span.kind == 'identifier' or span.kind == 'call' then
    local areas = font:CalculateScreenAreaFromCharacterSpan(span.first, span.last)
    for _, area in ipairs(areas or {}) do
     -- Native selection rectangles can use a fractional row advance while the
     -- rendered text uses a rounded one. Normalize against the measured text
     -- height and visual line count (including wrapping), from the bottom up.
     local ratio = advance and area.height > 0 and advance / area.height or 1
     cache.entries[#cache.entries + 1] = { source = span.source, left = area.left,
      bottom = area.bottom * ratio + (advance and height - textHeight or 0), width = area.width, height = area.height * ratio }
    end
   end
  end
  state.hoverAreas = cache
 end
 x, y = x - left, y - bottom
 for _, area in ipairs(cache.entries) do
  if x >= area.left and x < area.left + area.width and y >= area.bottom and y < area.bottom + area.height then
   return area.source
  end
 end
end

-- Normalize only whitespace tokens; literal and comment contents remain byte-for-byte intact.
function Editor:FormatSpacing(source, cursor)
 local tokens, output, offset, mapped, lineStart = self:Tokenize(source), {}, 0, cursor, true
 for index, token in ipairs(tokens) do
  local text = token.text
  if token.kind == 'space' then
   local following = tokens[index + 1]
   if not following or following.kind == 'newline' then
    text = following and text:sub(-1) == '\r' and '\r' or ''
   elseif not lineStart then
    text = ' '
   end
  end
  if cursor and cursor >= token.start - 1 and cursor <= token.finish then
   mapped = offset + math.min(cursor - token.start + 1, #text)
  end
  output[#output + 1], offset = text, offset + #text
  if token.kind == 'newline' then lineStart = true
  elseif token.kind ~= 'space' then lineStart = false end
 end
 return table.concat(output), mapped
end

function Editor:Format(source, cursor)
 source, cursor = self:FormatSpacing(source, cursor)
 local lines, line = {}, 1
 for text in (source .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = { text = text, tokens = {} } end
 for _, token in ipairs(self:Tokenize(source)) do
  if token.kind ~= 'space' and token.kind ~= 'newline' then lines[line].tokens[#lines[line].tokens + 1] = token end
  local _, breaks = token.text:gsub('\n', '')
  if token.kind == 'string' or token.kind == 'comment' then
   for inner = line + 1, line + breaks do lines[inner].protected = true end
  end
  line = line + breaks
 end
 local depth, result, oldOffset, newOffset, newCursor = 0, {}, 0, 0, cursor
 local open = { ['function'] = true, ['then'] = true, ['do'] = true, ['repeat'] = true, ['{'] = true, ['('] = true, ['['] = true }
 local close = { ['end'] = true, ['until'] = true, ['}'] = true, [')'] = true, [']'] = true }
 for _, row in ipairs(lines) do
  local indent, branch = depth, false
  for _, token in ipairs(row.tokens) do
   if token.kind == 'comment' then break end
   if close[token.text] or token.text == 'else' or token.text == 'elseif' then indent = math.max(0, indent - 1) else break end
  end
  local text = row.text
  if not row.protected then
   local content = text:gsub('^[ \t]*', '')
   text = content == '' and '' or string.rep(' ', indent * self:IndentWidth()) .. content
  end
  if cursor and cursor >= oldOffset and cursor <= oldOffset + #row.text then
   local oldIndent = #(row.text:match('^[ \t]*') or '')
   local newIndent = #(text:match('^[ \t]*') or '')
   newCursor = newOffset + math.max(0, math.min(#text, cursor - oldOffset + newIndent - oldIndent))
  end
  result[#result + 1] = text
  oldOffset, newOffset = oldOffset + #row.text + 1, newOffset + #text + 1
  for _, token in ipairs(row.tokens) do
   if token.kind ~= 'string' and token.kind ~= 'comment' then
    if token.text == 'elseif' then branch = true
    elseif open[token.text] then
     if token.text ~= 'then' or not branch then depth = depth + 1 end
    elseif close[token.text] then depth = math.max(0, depth - 1) end
   end
  end
 end
 return table.concat(result, '\n'), newCursor
end

function Editor:Paint(input)
 local state = input.queryEditor
 if not state then return end
 local box, overlay = input.editBox, state.overlay
 local font, size, flags = box:GetFont()
 local left, right, top = box:GetTextInsets()
 local width, spacing, source = math.max(1, box:GetWidth() - left - right), box:GetSpacing(), box:GetText()
 if state.paintFont ~= font or state.paintSize ~= size or state.paintFlags ~= flags then
  overlay:SetFont(font, size, flags)
  state.paintFont, state.paintSize, state.paintFlags = font, size, flags
 end
 if state.paintSpacing ~= spacing then overlay:SetSpacing(spacing); state.paintSpacing = spacing end
 if state.paintWidth ~= width or state.paintLeft ~= left or state.paintTop ~= top then
  overlay:ClearAllPoints()
  overlay:SetPoint('TOPLEFT', box, 'TOPLEFT', left, -top)
  overlay:SetWidth(width)
  state.paintWidth, state.paintLeft, state.paintTop = width, left, top
 end
 -- Let the font string calculate its full height before drawing a new snippet.
 -- Reusing the previous edit box height briefly clips newly wrapped lines.
 overlay:SetHeight(0)
 if state.renderSource ~= source or state.colorRevision ~= self.colorRevision then
  state.colorRevision = self.colorRevision
  state.renderSource = source
  local rendered
  rendered, state.renderSpans = self:Render(source)
  overlay:SetText(rendered)
 end
 state.pending = nil
end

function Editor:IsReadOnly(input)
 if input.readonly then return true end
 local workspace, debugger = addon.Workspace, addon.Debugger
 return input == addon.Query.Console.input and debugger and debugger.armed == true
  and workspace and workspace.db and workspace.db.options.debugReadOnly ~= false or false
end

function Editor:SetSource(input, source, cursor)
 if self:IsReadOnly(input) and not (addon.Workspace and addon.Workspace.selecting) then return false end
 local state = input.queryEditor
 if not state then return end
 state.busy = true
 input.editBox:SetText(source)
 input.editBox:SetCursorPosition(math.min(cursor or #source, #source))
 state.source = source
 state.busy = nil
 if state.changed then state.changed(input.editBox, true) end
 self:Paint(input)
end

function Editor:FormatInput(input)
 local text, cursor = self:Format(input:GetText(), input.editBox:GetCursorPosition())
 self:SetSource(input, text, cursor)
end

function Editor:NewlineIndent(previous, source, cursor)
 if #source ~= #previous + 1 or cursor < 1 or source:sub(cursor, cursor) ~= '\n' then return end
 if source:sub(1, cursor - 1) .. source:sub(cursor + 1) ~= previous then return end
 local prefix = source:sub(1, cursor - 1)
 local tokens = self:Tokenize(prefix)
 local last = tokens[#tokens]
 if last and (last.kind == 'string' or last.kind == 'comment') and (last.closed == false or last.text:find('\n', 1, true)) then return end
 local line = prefix:match('([^\n]*)$') or ''
 local indentation = line:match('^[ \t]*') or ''
 local delta = 0
 local open = { ['function'] = true, ['then'] = true, ['do'] = true, ['repeat'] = true, ['else'] = true, ['{'] = true, ['('] = true, ['['] = true }
 local close = { ['end'] = true, ['until'] = true, ['}'] = true, [')'] = true, [']'] = true }
 for index = #tokens, 1, -1 do
  local token = tokens[index]
  if token.kind == 'newline' then break end
  if token.kind ~= 'comment' and token.kind ~= 'string' then
   if open[token.text] then delta = delta + 1 elseif close[token.text] then delta = delta - 1 end
  end
 end
 indentation = indentation .. string.rep(' ', math.max(0, delta) * self:IndentWidth())
 if indentation == '' then return end
 return source:sub(1, cursor) .. indentation .. source:sub(cursor + 1), cursor + #indentation
end

function Editor:Attach(input)
 local box = input.editBox
 local state = input.queryEditorCache or {}
 input.queryEditorCache, input.queryEditor = state, state
 state.boxWidth = box:GetWidth()
 state.renderSource = nil
 state.source, state.scripts, state.busy, state.elapsed, state.keyEdit = box:GetText(), {}, nil, 0, nil
 state.color = { box:GetTextColor() }
 if not state.overlay then
  state.overlay = box:CreateFontString(nil, 'OVERLAY')
  state.overlay:SetJustifyH('LEFT')
  state.overlay:SetJustifyV('TOP')
  state.overlay:SetWordWrap(true)
  state.overlay:SetNonSpaceWrap(true)
  state.caret = box:CreateTexture(nil, 'OVERLAY')
  state.caret:SetColorTexture(1, 0.85, 0.4, 1)
  state.caret:SetWidth(1)
  state.active = box:CreateTexture(nil, 'BACKGROUND')
  state.active:SetColorTexture(1, 1, 1, 0.06)
 end
 box:SetTextColor(1, 1, 1, 0)
 state.overlay:Show()
 local function wrap(event, callback)
  local original = box:GetScript(event)
  state.scripts[#state.scripts + 1] = { event = event, original = original }
  box:SetScript(event, function(...)
   if event ~= 'OnTextChanged' or not state.busy then callback(original, ...) end
  end)
 end
 wrap('OnTextChanged', function(original, frame, user)
  local text = frame:GetText()
  -- Native layout notifications can repeat without changing the source.
  if text == state.source then return end
  if self:IsReadOnly(input) and not input.setting and text ~= state.source then
   state.busy = true
   frame:SetText(state.source)
   frame:SetCursorPosition(math.min(state.lastCursor or 0, #state.source))
   state.busy, state.keyEdit, state.formatEdit = nil, nil, nil
   return
  end
  if user and state.keyEdit and state.keyEdit.enter and addon.Workspace.db.options.autoIndent ~= false then
   state.keyEdit.enter = nil
   local indented, cursor = self:NewlineIndent(state.source, text, frame:GetCursorPosition())
   if indented then
    state.busy = true
    frame:SetText(indented)
    frame:SetCursorPosition(cursor)
    state.busy = nil
    text = indented
   end
  end
  state.source, state.pending, state.elapsed = text, true, 0
  if original then original(frame, user) end
 end)
 state.changed = state.scripts[#state.scripts].original
 wrap('OnKeyDown', function(original, frame, key)
  state.formatEdit = nil
  if key == 'F' and frame:HasFocus() and not self:IsReadOnly(input) and _G.IsShiftKeyDown and _G.IsShiftKeyDown()
   and _G.IsAltKeyDown and _G.IsAltKeyDown() and not (_G.IsControlKeyDown and _G.IsControlKeyDown())
   and not (_G.IsMetaKeyDown and _G.IsMetaKeyDown()) then
   state.keyEdit = nil
   self:FormatInput(input)
   state.formatEdit = { source = frame:GetText(), cursor = frame:GetCursorPosition() }
   return
  end
  if original then original(frame, key) end
  state.keyEdit = nil
  if self:IsReadOnly(input) then return end
  local modified = (_G.IsControlKeyDown and _G.IsControlKeyDown()) or (_G.IsAltKeyDown and _G.IsAltKeyDown()) or (_G.IsMetaKeyDown and _G.IsMetaKeyDown())
  if modified then return end
  local ignored = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
   INSERT = true, DELETE = true, BACKSPACE = true, LEFT = true, RIGHT = true, UP = true, DOWN = true,
   HOME = true, END = true, PAGEUP = true, PAGEDOWN = true, TAB = true, ESCAPE = true }
  if not ignored[key] then
   state.keyEdit = { source = frame:GetText(), cursor = frame:GetCursorPosition(), enter = key == 'ENTER' or key == 'NUMPADENTER' }
  end
 end)
 wrap('OnKeyUp', function(original, ...)
  state.formatEdit = nil
  if original then original(...) end
  state.keyEdit = nil
 end)
 wrap('OnSizeChanged', function(original, frame, width, height)
  if original then original(frame, width, height) end
  if state.boxWidth ~= width then state.boxWidth = width; state.pending = true end
 end)
 wrap('OnCursorChanged', function(original, frame, x, y, width, height)
  if not state.busy and frame:GetText() == state.source then state.lastCursor = frame:GetCursorPosition() end
  if original then original(frame, x, y, width, height) end
  state.caret:ClearAllPoints()
  state.caret:SetPoint('TOPLEFT', box, 'TOPLEFT', x, y)
  state.caret:SetHeight(height)
  state.active:ClearAllPoints()
  state.active:SetPoint('TOPLEFT', box, 'TOPLEFT', 0, y)
  state.active:SetWidth(box:GetWidth())
  state.active:SetHeight(height)
  state.elapsed = 0
 end)
 wrap('OnUpdate', function(original, frame, elapsed)
  if original then original(frame, elapsed) end
  state.elapsed = state.elapsed + elapsed
  if state.pending and state.elapsed >= 0.08 then self:Paint(input) end
  state.caret:SetShown(frame:HasFocus() and state.elapsed % 1 < 0.5)
  state.active:SetShown(frame:HasFocus())
 end)
 wrap('OnTabPressed', function(_, frame)
  if self:IsReadOnly(input) then return end
  if _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
   local source, cursor = frame:GetText(), frame:GetCursorPosition()
   local before = source:sub(1, cursor)
   local start = (before:match('.*\n()') or 1)
   local indentation = (source:sub(start):match('^ *') or ''):sub(1, self:IndentWidth())
   self:SetSource(input, source:sub(1, start - 1) .. source:sub(start + #indentation), math.max(start - 1, cursor - #indentation))
  else frame:Insert(string.rep(' ', self:IndentWidth())) end
 end)
 wrap('OnEditFocusLost', function(original, ...)
  state.formatEdit = nil
  if original then original(...) end
 end)
 wrap('OnHide', function(original, ...)
  state.formatEdit = nil
  if original then original(...) end
 end)
 wrap('OnChar', function(original, frame, char)
  if self:IsReadOnly(input) then state.keyEdit, state.formatEdit = nil, nil; return end
  local formatEdit = state.formatEdit
  state.formatEdit = nil
  if formatEdit then
   -- Modifier shortcuts may also insert a keyboard-layout character natively.
   -- Remove only that exact insertion, preserving unrelated edits and pastes.
   local expected = formatEdit.source:sub(1, formatEdit.cursor) .. char .. formatEdit.source:sub(formatEdit.cursor + 1)
   if frame:GetText() == expected then
    self:SetSource(input, formatEdit.source, formatEdit.cursor)
    return
   end
  end
  if original then original(frame, char) end
  local edit = state.keyEdit
  state.keyEdit = nil
  if not edit or addon.Workspace.db.options.autoPairs == false then return end
  local pairs = { ['('] = ')', ['['] = ']', ['{'] = '}', ['"'] = '"', ["'"] = "'" }
  local closing = pairs[char]
  if not closing then return end
  local source, cursor = frame:GetText(), frame:GetCursorPosition()
  -- Only pair a single character inserted by this keypress. Paste callbacks can
  -- arrive after the whole clipboard has already been placed at the cursor.
  if #source ~= #edit.source + #char or source:sub(cursor - #char + 1, cursor) ~= char then return end
  if source:sub(1, cursor - #char) .. source:sub(cursor + 1) ~= edit.source then return end
  local tokens = self:Tokenize(source:sub(1, cursor))
  local last = tokens[#tokens]
  if last and (last.kind == 'comment' or (last.kind == 'string' and last.start ~= cursor)) then return end
  local nextChar = source:sub(cursor + 1, cursor + 1)
  if nextChar ~= '' and not nextChar:match('[%s%)%]%},;]') then return end
  self:SetSource(input, source:sub(1, cursor) .. closing .. source:sub(cursor + 1), cursor)
 end)
 self:Paint(input)
end

function Editor:Detach(input)
 local state = input and input.queryEditor
 if not state then return end
 for _, script in ipairs(state.scripts) do input.editBox:SetScript(script.event, script.original) end
 input.editBox:SetTextColor(unpack(state.color))
 state.overlay:Hide()
 state.caret:Hide()
 state.active:Hide()
 input.queryEditor = nil
end
