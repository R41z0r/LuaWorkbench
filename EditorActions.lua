local _, addon = ...
local A = {}
addon.EditorActions = A
local E = addon.Query.Editor

function A:Bounds(source, cursor)
 local first = (source:sub(1, cursor):match('.*\n()') or 1) - 1
 local last = source:find('\n', cursor+1, true) or #source
 return first, last
end

function A:Move(source, cursor, direction, duplicate, selectionStart, selectionEnd, block)
 local first, last = self:Bounds(source, cursor)
 if selectionStart and selectionEnd and selectionStart ~= selectionEnd then
  local low, high = math.min(selectionStart, selectionEnd), math.max(selectionStart, selectionEnd)
  first = self:Bounds(source, low)
  local _, blockEnd = self:Bounds(source, high-1)
  last = blockEnd
 end
 if block then first, last = block.first, block.last end
 local hasNewline = last > first and source:sub(last, last) == '\n'
 if block then hasNewline = block.separated end
 local function bounds(at, separated)
  return {first=at, last=at+(last-first)-(hasNewline and 1 or 0)+(separated and 1 or 0), separated=separated}
 end
 local line = source:sub(first+1, hasNewline and last-1 or last)
 local column = cursor-first
 if duplicate then
  local at = direction < 0 and first or last
  local text = direction < 0 and (line .. '\n') or (hasNewline and (line .. '\n') or ('\n' .. line))
  local result = source:sub(1, at) .. text .. source:sub(at+1)
  local position = direction < 0 and (first+column) or (last+(hasNewline and 0 or 1)+column)
  return result, position, bounds(direction < 0 and first or (last+(hasNewline and 0 or 1)), direction < 0 or hasNewline)
 end
 if direction < 0 then
  if first == 0 then return source, cursor, bounds(first,hasNewline) end
  local previous = (source:sub(1, first-1):match('.*\n()') or 1)-1
  local above = source:sub(previous+1, first-1)
  return source:sub(1, previous) .. line .. '\n' .. above .. (hasNewline and '\n' or '') .. source:sub(last+1), previous+column, bounds(previous,true)
 end
 if not hasNewline then return source, cursor, bounds(first,hasNewline) end
 local nextEnd = source:find('\n', last+1, true) or #source
 local nextNewline = nextEnd > last and source:sub(nextEnd,nextEnd)=='\n'
 local below = source:sub(last+1, nextNewline and nextEnd-1 or nextEnd)
 return source:sub(1,first) .. below .. '\n' .. line .. (nextNewline and '\n' or '') .. source:sub(nextEnd+1), first+#below+1+column, bounds(first+#below+1,nextNewline)
end

function A:Selection(input)
 local state = input.queryEditor
 return state.selectionUnknown or (state.selectionStart and state.selectionEnd and state.selectionStart ~= state.selectionEnd)
end

function A:Cursor(input)
 local state, box = input.queryEditor, input.editBox
 if state.busy then return end
 local cursor = box:GetCursorPosition()
 if cursor ~= state.actionCursor and not state.actionLock then state.lineBlock = nil end
 if cursor == state.actionCursor and not state.mouseSelecting then return end
 if state.mouseSelecting then
  -- Mouse-down runs before the native EditBox places its cursor at the click.
  -- The first cursor callback supplies the actual start of a new mouse selection.
  if state.mouseAnchor == nil then state.mouseAnchor = cursor end
  state.selectionStart = state.mouseAnchor
  state.selectionEnd = cursor
  state.selectionUnknown = nil
 elseif _G.IsShiftKeyDown and IsShiftKeyDown() then
  state.selectionStart = state.selectionStart or state.actionCursor or cursor
  state.selectionEnd = cursor

 elseif not state.clipboard and not ((_G.IsControlKeyDown and IsControlKeyDown()) or (_G.IsMetaKeyDown and _G.IsMetaKeyDown())) then state.selectionStart, state.selectionEnd, state.selectionUnknown = nil, nil, nil end
 state.actionCursor = cursor
end

function A:BackwardRange(source, cursor, mode)
 local function previous(at)
  at = math.max(0, at-1)
  while at > 0 do
   local byte = source:byte(at+1)
   if not byte or byte < 128 or byte >= 192 then break end
   at = at-1
  end
  return at
 end
 if mode == 'character' then return previous(cursor) end
 local first = self:Bounds(source,cursor)
 if mode == 'line' then return first end
 if cursor == first then return previous(cursor) end
 local at = cursor
 while at > first and source:sub(at,at):match('[ \t]') do at=at-1 end
 if at == first then return first end
 local function word(pos)
  local byte = source:byte(pos)
  return byte and (byte >= 128 or source:sub(pos,pos):match('[%w_]') ~= nil)
 end
 local isWord = word(at)
 while at > first and not source:sub(at,at):match('[ \t]') and word(at) == isWord do at=previous(at) end
 return at
end

function A:BackwardWord(source, cursor)
 local target = self:BackwardRange(source,cursor,'word')
 local first = self:Bounds(source,cursor)
 local at = cursor
 while at > first and source:sub(at,at):match('[ \t]') do at=at-1 end
 local byte = source:byte(at)
 -- Backward navigation includes separators with the preceding word. Deletion
 -- keeps its own boundaries, and forward navigation still stops before a dot.
 if target > first and byte and byte < 128 and not source:sub(at,at):match('[%w_]') then
  local preceding = source:byte(target)
  if preceding and (preceding >= 128 or source:sub(target,target):match('[%w_]')) then
   target = self:BackwardRange(source,target,'word')
  end
 end
 return target
end

function A:ForwardWord(source, cursor)
 local _, last = self:Bounds(source,cursor)
 local finish = source:sub(last,last) == '\n' and last-1 or last
 if cursor >= finish then return math.min(#source,cursor+1) end
 local at = cursor
 while at < finish and source:sub(at+1,at+1):match('[ \t]') do at=at+1 end
 local function word(pos)
  local byte = source:byte(pos)
  return byte and (byte >= 128 or source:sub(pos,pos):match('[%w_]') ~= nil)
 end
 local isWord = word(at+1)
 while at < finish and not source:sub(at+1,at+1):match('[ \t]') and word(at+1) == isWord do at=at+1 end
 -- Starting on a separator includes the following word, but starting within
 -- a word still stops at its end so reversing a selection can leave punctuation.
 if not isWord then
  while at < finish and word(at+1) do at=at+1 end
 end
 return at
end

function A:RestoreNavigation(input)
 local state, box = input.queryEditor, input.editBox
 local range = state.navigationRange
 if not range or state.busy then return end
 if range.source ~= input:GetText() then
  state.navigationRange, state.navigationKey, state.actionLock = nil,nil,nil
  return
 end
 state.busy = true
 box:SetCursorPosition(range.target)
 if range.anchor then box:HighlightText(math.min(range.anchor,range.target),math.max(range.anchor,range.target))
 else box:HighlightText(0,0) end
 state.selectionStart, state.selectionEnd, state.selectionUnknown = range.anchor, range.anchor and range.target or nil, nil
 state.actionCursor = range.target
 state.busy = nil
end

function A:Navigate(input, key, line, extend)
 local state, box = input.queryEditor, input.editBox
 if extend and state.selectionUnknown then return end
 local source, cursor = input:GetText(), box:GetCursorPosition()
 local target
 if key == 'UP' or key == 'DOWN' then target = key == 'UP' and 0 or #source
 elseif line then
  local first,last = self:Bounds(source,cursor)
  target = key == 'LEFT' and first or (source:sub(last,last)=='\n' and last-1 or last)
 else target = key == 'LEFT' and self:BackwardWord(source,cursor) or self:ForwardWord(source,cursor) end
 local anchor = extend and (self:Selection(input) and state.selectionStart or cursor) or nil
 if addon.Autocomplete then
  addon.Autocomplete:Hide()
  addon.Autocomplete.keySource, addon.Autocomplete.keyCursor = nil,nil
 end
 state.lineBlock = nil
 state.actionLock, state.navigationKey = target,key
 state.navigationRange = {source=source,anchor=anchor,target=target}
 self:RestoreNavigation(input)
 return true
end

function A:Key(input, key)
 if input ~= addon.Query.Console.input then return end
 local state, box = input.queryEditor, input.editBox
 local ctrl = _G.IsControlKeyDown and IsControlKeyDown()
 local alt = _G.IsAltKeyDown and IsAltKeyDown()
 local shift = _G.IsShiftKeyDown and IsShiftKeyDown()
 local source, cursor = input:GetText(), box:GetCursorPosition()
 local meta = _G.IsMetaKeyDown and _G.IsMetaKeyDown()
 if _G.IsMacClient and _G.IsMacClient() and not ctrl and ((alt or meta) and (key=='LEFT' or key=='RIGHT') or meta and not alt and (key=='UP' or key=='DOWN')) then
  return self:Navigate(input,key,meta,shift)
 end
 if key == 'BACKSPACE' and _G.IsMacClient and _G.IsMacClient() and (ctrl or alt or meta)
  and not E:IsReadOnly(input) and not self:Selection(input) then
  local first = self:BackwardRange(source,cursor,meta and 'line' or (alt and 'word' or 'character'))
  local expected = source:sub(1,first)..source:sub(cursor+1)
  state.backwardDelete = {source=source, expected=expected, cursor=first}
  if source:sub(first+1,cursor) == '\n' then
   state.breakpointEdit = {oldSource=source,oldCursor=cursor,joinAt=first,expectedSource=expected}
  end
  if first ~= cursor then box:HighlightText(first,cursor) end
  if addon.Autocomplete then addon.Autocomplete:Hide() end
  return true
 end
 if alt and not ctrl and (key=='UP' or key=='DOWN') and not E:IsReadOnly(input) then
  if state.selectionUnknown then return end
  local first, last = state.selectionStart, state.selectionEnd
  local block = state.lineBlock
  if block and (block.source ~= source or block.actualCursor ~= cursor or block.selectionStart ~= first or block.selectionEnd ~= last) then block = nil end
  if block then first, last, cursor = block.logicalStart, block.logicalEnd, block.logicalCursor end
  local text, position, moved = self:Move(source,cursor,key=='UP' and -1 or 1,shift,first,last,block)
  E:SetSource(input,text,position)
  state.actionLock, state.actionCursor = math.min(position,#text), math.min(position,#text)
  if first and last and first ~= last then
   local delta = position-cursor
   state.selectionStart, state.selectionEnd = math.min(first+delta,#text), math.min(last+delta,#text)
   box:HighlightText(math.min(math.min(first,last)+delta,#text),math.min(math.max(first,last)+delta,#text))
   moved.source, moved.actualCursor = text, state.actionCursor
   moved.selectionStart, moved.selectionEnd = state.selectionStart, state.selectionEnd
   moved.logicalStart, moved.logicalEnd, moved.logicalCursor = first+delta, last+delta, position
   state.lineBlock = moved
  end
  if addon.Autocomplete then addon.Autocomplete:Hide() end
  return true
 end
 local nativeModifier = meta or (ctrl and not (_G.IsMacClient and _G.IsMacClient()))
 if not nativeModifier or alt then return end
 if key=='A' then state.selectionStart, state.selectionEnd=0,#source; return end
 if key=='C' or key=='X' then
  self.lineClipboard = nil
  if key=='X' and E:IsReadOnly(input) then return end
  if self:Selection(input) then
   -- Track native selection cuts so the consumed selection is cleared on key-up.
   if key=='X' then state.clipboard = {key=key, source=source, selection=true} end
   return
  end
  local first,last = self:Bounds(source,cursor)
  local text = source:sub(first+1,last)
  if text=='' then
   if key=='X' and first>0 and source:sub(-1)=='\n' then
    -- Select the preceding line break for native cut, including clipboard transfer.
    self.lineClipboard = '\n'
    state.clipboard = {key=key, source=source, cursor=cursor, first=first-1,last=first}
    box:HighlightText(first-1,first)
   end
   return
  end
  self.lineClipboard = text
  state.clipboard = {key=key, source=source, cursor=cursor, first=first,last=last}
  box:HighlightText(first,last)
 elseif key=='V' and not E:IsReadOnly(input) then
  state.nativePaste = true
  state.paste = {source=source,cursor=cursor,line=not self:Selection(input) and self.lineClipboard or nil}
 end
end

function A:Text(input, text)
 local state = input.queryEditor
 local backward = state.backwardDelete
 if backward then
  state.backwardDelete = nil
  if state.source == backward.source then
   state.selectionStart, state.selectionEnd, state.selectionUnknown = nil,nil,nil
   state.actionCursor = backward.cursor
   return backward.expected, backward.cursor
  end
 end
 local paste = state.paste
 state.paste = nil
 if paste then
  local inserted = #text - #paste.source
  local payload = inserted >= 0 and text:sub(paste.cursor+1,paste.cursor+inserted)
  if paste.line and payload == paste.line and text == paste.source:sub(1,paste.cursor)..payload..paste.source:sub(paste.cursor+1) then
   local first = self:Bounds(paste.source,paste.cursor)
   payload = payload:gsub('\r\n','\n'):gsub('\r','\n')
   if payload:sub(-1) ~= '\n' then payload=payload..'\n' end
   return paste.source:sub(1,first)..payload..paste.source:sub(first+1), paste.cursor+#payload
  end
 end
 if text:find('\r',1,true) then
  local cursor=input.editBox:GetCursorPosition()
  return text:gsub('\r\n','\n'):gsub('\r','\n'), #(text:sub(1,cursor):gsub('\r\n','\n'):gsub('\r','\n'))
 end
 local clip=state.clipboard
 if clip and clip.key=='X' and not clip.selection and clip.first>0 and clip.last==#clip.source and clip.source:sub(-1)~='\n'
  and text==clip.source:sub(1,clip.first) then return text:sub(1,-2), math.max(0,clip.first-1) end
end

function A:KeyUp(input)
 local state, box = input.queryEditor, input.editBox
 if state.navigationKey then self:RestoreNavigation(input) end
 state.navigationKey, state.navigationRange = nil,nil
 local clip=state.clipboard
 local backward = state.backwardDelete
 state.backwardDelete = nil
 if backward then
  box:HighlightText(0,0)
  state.selectionStart, state.selectionEnd, state.selectionUnknown = nil,nil,nil
 end
 local pasted = state.nativePaste
 state.clipboard, state.paste, state.actionLock, state.nativePaste = nil,nil,nil,nil
 if clip and clip.key=='C' and input:GetText()==clip.source then
  box:HighlightText(0,0); box:SetCursorPosition(clip.cursor)
 elseif clip and clip.key=='X' and input:GetText()~=clip.source then
  -- Native cut consumed the prepared selection; it is no longer a user selection.
  box:HighlightText(0,0)
 end
 -- Native paste finishes with a caret, even when it replaces identical text.
 if pasted then box:HighlightText(0,0) end
 if pasted or (clip and (clip.key=='C' or input:GetText()~=clip.source)) then
  state.selectionStart, state.selectionEnd, state.selectionUnknown = nil, nil, nil
  state.actionCursor = box:GetCursorPosition()
 end
end

function A:Track(input)
 local box,state=input.editBox,input.queryEditor
 if state.selectionHook or not _G.hooksecurefunc then return end
 state.selectionHook=true
 _G.hooksecurefunc(box,'HighlightText',function(_,first,last)
  state.lineBlock = nil
  state.selectionStart,state.selectionEnd=first or 0,last and last>=0 and last or #box:GetText()
  state.selectionUnknown=nil
 end)
end
