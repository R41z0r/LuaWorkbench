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

function Editor:ScanTokens(source, maxTokens, firstSource, lastSource, scanStart, checkpoints)
 local tokens, index, length, count = {}, scanStart or 1, #source, 0
 local function add(kind, finish, closed)
  count = count + 1
  if not firstSource or finish >= firstSource then
   tokens[#tokens + 1] = { kind = kind, text = source:sub(index, finish), start = index, finish = finish, closed = closed }
  end
  index = finish + 1
  if checkpoints and kind == 'newline' and index-(checkpoints[#checkpoints] or 1) >= 4096 then
   checkpoints[#checkpoints+1]=index
  end
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
 while index <= length and (not lastSource or index <= lastSource) do
  if maxTokens and count >= maxTokens then
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

-- Newline token boundaries carry no string/comment state. Sparse checkpoints let
-- viewport coloring resume safely without retaining a token for the whole file.
function Editor:ViewportTokens(source, firstSource, lastSource)
 local cache=self.viewportLexicalCache
 if not cache then cache={source='', points={1}};self.viewportLexicalCache=cache end
 local points=cache.points
 if cache.source ~= source then
  local prefix,high=0,math.min(#cache.source,#source)
  while prefix < high do
   local middle=math.floor((prefix+high+1)/2)
   if cache.source:sub(1,middle)==source:sub(1,middle) then prefix=middle else high=middle-1 end
  end
  while #points>1 and points[#points]>prefix do points[#points]=nil end
  cache.source=source
 end
 local low,high=1,#points
 while low<high do
  local middle=math.floor((low+high+1)/2)
  if points[middle]<=firstSource then low=middle else high=middle-1 end
 end
 -- Keep checkpoints ordered when revisiting an earlier viewport.
 local additions=low==#points and points or nil
 return self:ScanTokens(source,nil,firstSource,lastSource,points[low],additions)
end

-- Only lexical data is shared. Analysis owns and may annotate its returned tokens.
-- Keep one bounded source snapshot; edits invalidate from a token boundary, including
-- preceding whitespace because an identifier can look ahead to a call parenthesis.
function Editor:Tokenize(source, maxTokens, firstSource, lastSource)
 if #source > 200000 then
  local tokens=self:ScanTokens(source,maxTokens,firstSource,lastSource)
  if lastSource then for _,token in ipairs(tokens) do token.text=source:sub(token.start,math.min(token.finish,lastSource)) end end
  return tokens
 end
 local cache = self.lexicalCache
 if not cache then cache = {source='', tokens={}}; self.lexicalCache = cache end
 local raw = cache.tokens
 if cache.source ~= source then
  local prefix, high = 0, math.min(#cache.source, #source)
  while prefix < high do
   local middle = math.floor((prefix+high+1)/2)
   if cache.source:sub(1,middle) == source:sub(1,middle) then prefix=middle else high=middle-1 end
  end
  local low, upper = 1, #raw+1
  while low < upper do
   local middle = math.floor((low+upper)/2)
   if raw[middle].finish < prefix then low=middle+1 else upper=middle end
  end
  local restart = math.min(low, #raw)
  -- Restart the changed line as delimiters and numeric literals can span several
  -- formerly separate tokens (for example an unfinished long-bracket opener).
  while restart > 1 and raw[restart-1].kind ~= 'newline' do restart=restart-1 end
  while restart > 1 and (raw[restart-1].kind == 'space' or raw[restart-1].kind == 'newline') do restart=restart-1 end
  if restart > 1 then restart=restart-1 end
  while restart > 1 and (raw[restart].kind == 'space' or raw[restart].kind == 'newline') do restart=restart-1 end
  for i=#raw,math.max(1,restart),-1 do raw[i]=nil end
  cache.source = source
 end
 local limit = math.min(maxTokens or 50000, 50000)
 local start = #raw > 0 and raw[#raw].finish+1 or 1
 if start <= #source and (not lastSource or start <= lastSource) and #raw < limit then
  local tail = self:ScanTokens(source, limit-#raw, nil, lastSource, start)
  for _,token in ipairs(tail) do
   if not token.truncated then raw[#raw+1]=token end
  end
 end
 local result = {}
 local first, upper = 1, math.min(#raw,limit)+1
 if firstSource then
  while first < upper do
   local middle=math.floor((first+upper)/2)
   if raw[middle].finish < firstSource then first=middle+1 else upper=middle end
  end
 end
 for i=first,math.min(#raw,limit) do
  local token=raw[i]
  if lastSource and token.start > lastSource then break end
  if not firstSource or token.finish >= firstSource then
   result[#result+1]={kind=token.kind, text=source:sub(token.start,math.min(token.finish,lastSource or token.finish)), start=token.start, finish=token.finish, closed=token.closed}
  end
 end
 local finish = limit == 0 and 0 or (raw[limit] and raw[limit].finish or (#raw > 0 and raw[#raw].finish or 0))
 if finish < #source and (not lastSource or finish < lastSource) then
  if not maxTokens or maxTokens > limit then
   -- Unbounded formatting/debug callers retain their original full-source behavior.
   local tail=self:ScanTokens(source,maxTokens and maxTokens-limit,firstSource,lastSource,finish+1)
   for _,token in ipairs(tail) do result[#result+1]=token end
  else
   result[#result+1]={kind='plain',text=source:sub(finish+1,lastSource),start=finish+1,finish=#source,truncated=true}
  end
 end
 return result
end

-- Retain presentation only, never symbol-resolution data, across an ordinary edit.
function Editor:RetainedColors(previous, source, spans)
 local colors = {}
 if not previous or not spans then return colors end
 local prefix, high = previous == source and #source or 0, math.min(#previous, #source)
 while prefix < high do
  local middle = math.floor((prefix + high + 1) / 2)
  if previous:sub(1, middle) == source:sub(1, middle) then prefix = middle else high = middle - 1 end
 end
 local suffix = 0
 high = math.min(#previous, #source) - prefix
 while suffix < high do
  local middle = math.floor((suffix + high + 1) / 2)
  if previous:sub(#previous-middle+1) == source:sub(#source-middle+1) then suffix = middle else high = middle - 1 end
 end
 for _, span in ipairs(spans) do
  if span.colorKind and (span.kind == 'identifier' or span.kind == 'call') then
   local start, finish = span.source, span.source + #span.text - 1
   if finish <= prefix then colors[start] = span
   elseif start > #previous - suffix then colors[start + #source - #previous] = span end
  end
 end
 return colors
end

function Editor:Render(source, firstSource, lastSource, deferred)
 local result, spans, offset = {}, {}, 0
 local analysis
 if addon.Analysis then
  if deferred then analysis = addon.Analysis.cache[source]
  else analysis = addon.Analysis:Get(source) end
 end
 if analysis and analysis.limited then analysis=nil end
 local viewportOnly = firstSource and lastSource and #source > 100000
 if viewportOnly then analysis=nil end
 local tokens = viewportOnly and self:ViewportTokens(source, firstSource, lastSource)
  or (analysis and analysis.tokens or self:Tokenize(source, nil, firstSource, lastSource))
 local apiPaths = analysis and addon.APIHelp and addon.APIHelp:Paths(source) or {}
 for _, token in ipairs(tokens) do
  if (not firstSource or token.finish >= firstSource) and (not lastSource or token.start <= lastSource) then
  local start = math.max(token.start, firstSource or token.start)
  local finish = math.min(token.finish, lastSource or token.finish)
  local raw = source:sub(start, finish)
  local text = raw:gsub('|', '||')
  local retained = not analysis and type(deferred) == 'table' and deferred.colors and deferred.colors[start]
  local retainedKind = retained and retained.kind == token.kind and retained.text == raw and retained.colorKind
  local colorKind = apiPaths[token.start] and 'blizzardFunction' or token.semanticKind or retainedKind or token.kind
  local color = self:Color(colorKind)
  local rendered = color and ('|c' .. color .. text .. '|r') or text
  local first = offset + (color and 10 or 0) + 1
  spans[#spans + 1] = { first = first, last = first + #text - 1, source = start, text = raw, kind = token.kind, colorKind = colorKind }
  result[#result + 1] = rendered
  offset = offset + #rendered
  end
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
 local layout=input.queryLineNumbers
 if layout and layout.source ~= state.renderSource then return end
 local scroll=input.scrollFrame
 local scrollOffset=scroll and scroll:GetVerticalScroll()
 local viewport=scroll and scroll:GetHeight()
 local positions=layout and layout.source == state.renderSource and layout.positions
 local firstSource,lastSource
 if positions and scrollOffset and viewport then
  for _,line in ipairs(positions) do
   if line.offset+line.height >= scrollOffset and line.offset < scrollOffset+viewport then
    firstSource=firstSource or line.sourceStart
    lastSource=line.sourceEnd
   end
  end
 end
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
  or cache.lines ~= lines or cache.textHeight ~= textHeight or cache.scale ~= scale
  or cache.firstSource ~= firstSource or cache.lastSource ~= lastSource then
  cache = { firstSource=firstSource, lastSource=lastSource, spans = state.renderSpans, height = height, width = width, face = face, size = size, flags = flags, spacing = spacing, lines = lines, textHeight = textHeight, scale = scale, entries = {} }
  for _, span in ipairs(state.renderSpans or {}) do
   if (span.kind == 'identifier' or span.kind == 'call')
    and (not firstSource or not lastSource or span.source >= firstSource and span.source <= lastSource) then
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

function Editor:VisibleRange(input, source)
 local layout, scroll = input.queryLineNumbers, input.scrollFrame
 if not layout or layout.source ~= source or not scroll then return end
 local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
 local first, last, y
 local positions = layout.positions or {}
 local low, high = 1, #positions
 while low <= high do
  local middle = math.floor((low + high) / 2)
  local line = positions[middle]
  if line.offset + line.height < offset then low = middle + 1 else high = middle - 1 end
 end
 for index = low, #positions do
  local line = positions[index]
  if line.offset >= offset + height then break end
  first, y = first or line.sourceStart, y or line.offset
  last = line.sourceEnd
 end
 return first, last, y
end

function Editor:Paint(input)
 local state = input.queryEditor
 if not state then return end
 local box, overlay = input.editBox, state.overlay
 local font, size, flags = box:GetFont()
 local left, right, top = box:GetTextInsets()
 local width, spacing, source = math.max(1, box:GetWidth() - left - right), box:GetSpacing(), box:GetText()
 local first, last, offset = self:VisibleRange(input, source)
 -- Native cursor/layout callbacks can precede the source-change notification.
 -- Wait for that notification to refresh line geometry instead of rendering
 -- the complete document with missing viewport bounds.
 if input.queryLineNumbers and not first then
  state.pending = true
  return
 end
 offset = offset or 0
 if state.paintFont ~= font or state.paintSize ~= size or state.paintFlags ~= flags then
  overlay:SetFont(font, size, flags)
  state.paintFont, state.paintSize, state.paintFlags = font, size, flags
 end
 if state.paintSpacing ~= spacing then overlay:SetSpacing(spacing); state.paintSpacing = spacing end
 if state.paintWidth ~= width or state.paintLeft ~= left or state.paintTop ~= top or state.paintOffset ~= offset then
  overlay:ClearAllPoints()
  overlay:SetPoint('TOPLEFT', box, 'TOPLEFT', left, -top-offset)
  overlay:SetWidth(width)
  state.paintWidth, state.paintLeft, state.paintTop, state.paintOffset = width, left, top, offset
 end
 -- Let the font string calculate its full height before drawing a new snippet.
 -- Reusing the previous edit box height briefly clips newly wrapped lines.
 overlay:SetHeight(0)
 local deferred = #source > 20000
 local analysis = addon.Analysis and addon.Analysis.cache[source]
 if state.renderSource ~= source or state.colorRevision ~= self.colorRevision or state.renderFirst ~= first or state.renderLast ~= last
  or (deferred and state.renderAnalysis ~= analysis) then
  local owner = addon.Workspace and addon.Workspace.current
  local options = deferred and {colors = not analysis and state.colorOwner == owner and self:RetainedColors(state.renderSource, source, state.renderSpans) or {}}
  state.colorOwner = owner
  state.colorRevision = self.colorRevision
  state.renderSource, state.renderFirst, state.renderLast = source, first, last
  local rendered
  rendered, state.renderSpans = self:Render(source, first, last, options)
  state.renderAnalysis = analysis
  -- Keep pathological single lines and editors without a viewport fully readable.
  state.nativeText = #rendered > 16000
  if state.nativeText then
   state.renderSpans = nil
   if state.renderedText ~= '' then overlay:SetText('') end
   state.renderedText = ''
   overlay:Hide()
   box:SetTextColor(0.8, 0.84, 0.92, 1)
  else
   if state.renderedText ~= rendered then overlay:SetText(rendered) end
   state.renderedText = rendered
   overlay:Show()
   box:SetTextColor(1, 1, 1, 0)
  end
 end
 state.pending = nil
end

-- Large documents paint lexical colors immediately; semantic work waits for quiet input.
function Editor:UpdateAnalysis(input, elapsed)
 local state = input.queryEditor
 local source = input:GetText()
 if #source <= 20000 or #source > 100000 or not addon.Analysis then return end
 if state.analysisSource ~= source then
  state.analysisSource, state.analysisElapsed = source, 0
 else state.analysisElapsed = (state.analysisElapsed or 0) + elapsed end
 local analysis = addon.Analysis.cache[source]
 if not analysis and state.analysisElapsed >= 0.45 then analysis = addon.Analysis:Get(source) end
 if analysis and state.renderSource == source and state.renderAnalysis ~= analysis then self:Paint(input) end
end

function Editor:IsReadOnly(input)
 if input.readonly then return true end
 local workspace, debugger = addon.Workspace, addon.Debugger
 return input == addon.Query.Console.input and debugger and debugger.armed == true
  and workspace and workspace.db and workspace.db.options.debugReadOnly ~= false or false
end

-- Track generated delimiters through edits without treating existing source as auto-paired.
function Editor:UpdateAutoPairs(input, source, hint)
 local state=input.queryEditor
 local previous=state.autoPairSource
 state.autoPairSource=source
 if not previous or previous == source or not state.autoPairs then return end
 local first, oldEnd, newEnd=0,#previous,#source
 local edit=hint or state.keyEdit
 local added=#source-#previous
 if edit and edit.source == previous and added>0
  and source:sub(1,edit.cursor) == previous:sub(1,edit.cursor)
  and source:sub(edit.cursor+added+1) == previous:sub(edit.cursor+1) then
  first,oldEnd,newEnd=edit.cursor,edit.cursor,edit.cursor+added
 else
  while first<oldEnd and first<newEnd and previous:byte(first+1)==source:byte(first+1) do first=first+1 end
  while oldEnd>first and newEnd>first and previous:byte(oldEnd)==source:byte(newEnd) do oldEnd=oldEnd-1;newEnd=newEnd-1 end
 end
 for index=#state.autoPairs,1,-1 do
  local pair=state.autoPairs[index]
  if (pair.open>=first and pair.open<oldEnd) or (pair.close>=first and pair.close<oldEnd) then
   table.remove(state.autoPairs,index)
  else
   if pair.open>=oldEnd then pair.open=pair.open+newEnd-oldEnd end
   if pair.close>=oldEnd then pair.close=pair.close+newEnd-oldEnd end
  end
 end
end

function Editor:SetSource(input, source, cursor, preservePairs)
 if self:IsReadOnly(input) and not (addon.Workspace and addon.Workspace.selecting) then return false end
 local state = input.queryEditor
 if not state then return end
 if preservePairs then self:UpdateAutoPairs(input,source)
 else state.autoPairs, state.autoPairSource = nil, source end
 state.lineBlock = nil
 state.selectionStart, state.selectionEnd, state.selectionUnknown = nil, nil, nil
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
   if event ~= 'OnTextChanged' or not state.busy then return callback(original, ...) end
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
  state.lineBlock = nil
  if state.keyEdit and state.keyEdit.enter and not state.breakpointEdit then
   state.breakpointEdit = {oldCursor=state.keyEdit.cursor, oldSource=state.keyEdit.source}
  end
  if user and addon.EditorActions then
   local normalized, cursor = addon.EditorActions:Text(input, text)
   if normalized then state.busy = true; frame:SetText(normalized); frame:SetCursorPosition(cursor); state.busy = nil; text = normalized end
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
  if input.setting then state.autoPairs, state.autoPairSource=nil,text
  else self:UpdateAutoPairs(input,text) end
  state.source, state.pending, state.elapsed = text, true, 0
  if original then original(frame, user) end
  state.breakpointEdit = nil
 end)
 state.changed = state.scripts[#state.scripts].original
 wrap('OnKeyDown', function(original, frame, key)
  state.formatEdit = nil
  if addon.EditorActions and addon.EditorActions:Key(input, key) then state.keyEdit = nil; return end
  if addon.Autocomplete and addon.Autocomplete:Key(input, key) then state.keyEdit = nil; return end
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
  if (key == 'BACKSPACE' or key == 'DELETE') and not (addon.EditorActions and addon.EditorActions:Selection(input)) then
   local source, cursor = frame:GetText(), frame:GetCursorPosition()
   local at = key == 'BACKSPACE' and cursor or cursor+1
   if source:sub(at,at) == '\n' then
    state.breakpointEdit = {oldCursor=cursor, oldSource=source, joinAt=at-1,
     expectedSource=source:sub(1,at-1)..source:sub(at+1)}
   end
  end
  local ignored = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true,
   INSERT = true, DELETE = true, BACKSPACE = true, LEFT = true, RIGHT = true, UP = true, DOWN = true,
   HOME = true, END = true, PAGEUP = true, PAGEDOWN = true, TAB = true, ESCAPE = true }
  if not ignored[key] then
   state.keyEdit = { source = frame:GetText(), cursor = frame:GetCursorPosition(), enter = key == 'ENTER' or key == 'NUMPADENTER' }
  end
 end)
 wrap('OnArrowPressed', function(original, frame, key)
  if state.navigationKey == key then addon.EditorActions:RestoreNavigation(input); return true end
  -- Alt line actions already restored their selection in OnKeyDown. Do not let
  -- the native Shift-arrow handler extend or replace that restored block.
  if state.actionLock and (key == 'UP' or key == 'DOWN') and _G.IsAltKeyDown and _G.IsAltKeyDown() then return true end
  if addon.Autocomplete and addon.Autocomplete:Arrow(input, key) then return true end
  if original then return original(frame, key) end
 end)
 wrap('OnKeyUp', function(original, ...)
  if addon.EditorActions then addon.EditorActions:KeyUp(input) end
  if addon.Autocomplete then
   addon.Autocomplete:RestoreCursor(input)
   addon.Autocomplete.keySource, addon.Autocomplete.keyCursor = nil, nil
   addon.Autocomplete.arrowKey, addon.Autocomplete.arrowOrigin = nil, nil
  end
  state.formatEdit = nil
  if original then original(...) end
  state.keyEdit = nil
 end)
 wrap('OnSizeChanged', function(original, frame, width, height)
  if original then original(frame, width, height) end
  if state.boxWidth ~= width then state.boxWidth = width; state.pending = true end
 end)
 wrap('OnCursorChanged', function(original, frame, x, y, width, height)
  if state.actionLock and not state.busy and frame:GetCursorPosition() ~= state.actionLock then
   if state.navigationKey then addon.EditorActions:RestoreNavigation(input)
   else state.busy = true; frame:SetCursorPosition(state.actionLock); state.busy = nil end
   return
  end
  if addon.EditorActions then addon.EditorActions:Cursor(input) end
  local completion = addon.Autocomplete
  if completion and completion.keyCursor and completion.input == input and not state.busy
   and frame:GetText() == completion.keySource and frame:GetCursorPosition() ~= completion.keyCursor then
   state.busy = true; frame:SetCursorPosition(completion.keyCursor); state.busy = nil; return
  end
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
  self:UpdateAnalysis(input, elapsed)
  if addon.Autocomplete then addon.Autocomplete:Tick(input, elapsed) end
  state.elapsed = state.elapsed + elapsed
  local first, last = self:VisibleRange(input, frame:GetText())
  if first ~= state.renderFirst or last ~= state.renderLast then state.pending = true end
  if state.pending and (#frame:GetText() > 20000 or state.elapsed >= 0.08 or state.renderSource == frame:GetText()) then self:Paint(input) end
  state.caret:SetShown(frame:HasFocus() and state.elapsed % 1 < 0.5)
  state.active:SetShown(frame:HasFocus())
 end)
 wrap('OnEscapePressed', function(original, frame)
  local completion = addon.Autocomplete
  if completion and completion.input == input and ((completion.panel and completion.panel:IsShown())
   or (completion.signaturePanel and completion.signaturePanel:IsShown())) then completion:Hide(); return end
  if original then original(frame) end
 end)
 wrap('OnEnterPressed', function(original, frame)
  local modified = (_G.IsControlKeyDown and _G.IsControlKeyDown()) or (_G.IsAltKeyDown and _G.IsAltKeyDown())
   or (_G.IsMetaKeyDown and _G.IsMetaKeyDown()) or (_G.IsShiftKeyDown and _G.IsShiftKeyDown())
  if not modified and addon.Autocomplete and addon.Autocomplete:Accept(input) then
   state.keyEdit = nil
   return true
  end
  if original then return original(frame) end
  if self:IsReadOnly(input) or (_G.IsControlKeyDown and _G.IsControlKeyDown())
   or (_G.IsAltKeyDown and _G.IsAltKeyDown()) or (_G.IsMetaKeyDown and _G.IsMetaKeyDown()) then return end
  -- Installing this handler replaces the EditBox's native newline behavior.
  local previous = frame:GetText()
  state.breakpointEdit = {oldCursor=frame:GetCursorPosition(), oldSource=previous}
  state.keyEdit = nil
  frame:Insert('\n')
  -- Native OnTextChanged may arrive after Insert returns. Keep the hint until
  -- SourceChanged consumes it, tied to the exact result of this Enter operation.
  if state.breakpointEdit then
   state.breakpointEdit.expectedSource = frame:GetText()
   if frame:GetText() == previous then state.breakpointEdit = nil end
  end
  if addon.Workspace.db.options.autoIndent ~= false then
   local indented, cursor = self:NewlineIndent(previous, frame:GetText(), frame:GetCursorPosition())
   if indented then
    if state.breakpointEdit then state.breakpointEdit.expectedSource = indented end
    self:SetSource(input, indented, cursor)
   end
  end
 end)
 wrap('OnTabPressed', function(_, frame)
  if addon.Autocomplete and addon.Autocomplete:Accept(input) then return end
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
  if state.navigationKey then state.navigationKey, state.navigationRange, state.actionLock = nil,nil,nil end
  state.backwardDelete = nil
  if addon.EditorActions and input == addon.Query.Console.input then addon.EditorActions.lineClipboard = nil end
  if addon.Autocomplete and addon.Autocomplete.input == input then addon.Autocomplete:Hide() end
  state.formatEdit = nil
  if original then original(...) end
 end)
 wrap('OnHide', function(original, ...)
  if state.navigationKey then state.navigationKey, state.navigationRange, state.actionLock = nil,nil,nil end
  state.backwardDelete = nil
  if addon.EditorActions and input == addon.Query.Console.input then addon.EditorActions.lineClipboard = nil end
  if addon.Autocomplete and addon.Autocomplete.input == input then addon.Autocomplete:Hide() end
  state.formatEdit = nil
  if original then original(...) end
 end)
 wrap('OnChar', function(original, frame, char)
  local completion = addon.Autocomplete
  if completion and completion.keySource and char == ' ' then
   local source, cursor = completion.keySource, completion.keyCursor
   completion.keySource, completion.keyCursor = nil, nil
   if frame:GetText() == source:sub(1, cursor) .. char .. source:sub(cursor+1) then self:SetSource(input, source, cursor); return end
  end
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
  local source, cursor = frame:GetText(), frame:GetCursorPosition()
  -- Only pair a single character inserted by this keypress. Paste callbacks can
  -- arrive after the whole clipboard has already been placed at the cursor.
  if #source ~= #edit.source + #char or source:sub(cursor - #char + 1, cursor) ~= char then return end
  if source:sub(1, cursor - #char) .. source:sub(cursor + 1) ~= edit.source then return end
  self:UpdateAutoPairs(input,source,edit)
  for index,pair in ipairs(state.autoPairs or {}) do
   if pair.close == cursor and pair.char == char then
    -- Escaped quotes are content, never a request to leave the string.
    local slashes, position=0,cursor-1
    while position>0 and source:sub(position,position)=='\\' do slashes=slashes+1;position=position-1 end
    if (char ~= '"' and char ~= "'") or slashes%2 == 0 then
     table.remove(state.autoPairs,index)
     self:SetSource(input,edit.source,cursor,true)
     return
    end
   end
  end
  if not closing then return end
  -- Only the token at the caret is needed. Preserve prefix-only semantics for
  -- unfinished strings/delimiters while reusing safe lexical checkpoints.
  local tokens = self:ViewportTokens(source:sub(1, cursor), cursor, cursor)
  local last = tokens[#tokens]
  if last and (last.kind == 'comment' or (last.kind == 'string' and last.start ~= cursor)) then return end
  local nextChar = source:sub(cursor + 1, cursor + 1)
  if nextChar ~= '' and not nextChar:match('[%s%)%]%},;]') then return end
  self:SetSource(input, source:sub(1, cursor) .. closing .. source:sub(cursor + 1), cursor, true)
  state.autoPairs=state.autoPairs or {}
  state.autoPairs[#state.autoPairs+1]={open=cursor-1,close=cursor,char=closing}
  if #state.autoPairs>128 then table.remove(state.autoPairs,1) end
 end)
 if addon.EditorActions then addon.EditorActions:Track(input) end
 wrap('OnMouseDown', function(original, frame, button)
  if addon.Autocomplete and addon.Autocomplete.input == input then addon.Autocomplete:Hide() end
  if button == 'LeftButton' then
   state.lineBlock = nil
   local now = _G.GetTime and _G.GetTime() or 0
   state.doubleClick = state.lastMouseDown and now - state.lastMouseDown < 0.35
   state.lastMouseDown = now
   state.mouseX, state.mouseY = GetCursorPosition()
   state.mouseAnchor = nil
   if _G.IsShiftKeyDown and IsShiftKeyDown() then state.mouseAnchor = state.selectionStart or frame:GetCursorPosition() end
   state.mouseSelecting = true
  end
  if original then original(frame, button) end
 end)
 wrap('OnMouseUp', function(original, frame, button)
  if button == 'LeftButton' then
   local x, y = GetCursorPosition()
   state.mouseSelecting = nil
   local dragged = state.mouseX and (math.abs(x-state.mouseX)>3 or math.abs(y-state.mouseY)>3)
   state.selectionUnknown = state.doubleClick or false
   if dragged or (_G.IsShiftKeyDown and IsShiftKeyDown()) then
    state.selectionStart, state.selectionEnd = state.mouseAnchor, frame:GetCursorPosition()
   elseif not state.selectionUnknown then state.selectionStart, state.selectionEnd = nil, nil end
  end
  if original then original(frame, button) end
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
