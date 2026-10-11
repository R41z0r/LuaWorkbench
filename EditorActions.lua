local _, addon = ...
local A = {}
addon.EditorActions = A
local E = addon.Query.Editor

function A:Bounds(source, cursor)
 local first = (source:sub(1, cursor):match('.*\n()') or 1) - 1
 local last = source:find('\n', cursor+1, true) or #source
 return first, last
end

function A:Move(source, cursor, direction, selectionStart, selectionEnd)
 local first, last = self:Bounds(source, cursor)
 if selectionStart and selectionEnd and selectionStart ~= selectionEnd then
  local low, high = math.min(selectionStart, selectionEnd), math.max(selectionStart, selectionEnd)
  first = self:Bounds(source, low)
  local _, blockEnd = self:Bounds(source, high-1)
  last = blockEnd
 end
 local hasNewline = last > first and source:sub(last, last) == '\n'
 local line = source:sub(first+1, hasNewline and last-1 or last)
 local column = cursor-first
 if direction < 0 then
  if first == 0 then return source, cursor end
  local previous = (source:sub(1, first-1):match('.*\n()') or 1)-1
  local above = source:sub(previous+1, first-1)
  return source:sub(1, previous) .. line .. '\n' .. above .. (hasNewline and '\n' or '') .. source:sub(last+1), previous+column
 end
 if not hasNewline then return source, cursor end
 local nextEnd = source:find('\n', last+1, true) or #source
 local nextNewline = nextEnd > last and source:sub(nextEnd,nextEnd)=='\n'
 local below = source:sub(last+1, nextNewline and nextEnd-1 or nextEnd)
 return source:sub(1,first) .. below .. '\n' .. line .. (nextNewline and '\n' or '') .. source:sub(nextEnd+1), first+#below+1+column
end

function A:Cursor(input)
 local state, box = input.queryEditor, input.editBox
 if state.busy then return end
 local cursor = box:GetCursorPosition()
 if cursor == state.actionCursor and not state.mouseSelecting then return end
 if state.mouseSelecting then
  state.selectionStart = state.mouseAnchor or state.actionCursor or cursor
  state.selectionEnd = cursor
  state.selectionUnknown = nil
 elseif _G.IsShiftKeyDown and IsShiftKeyDown() then
  state.selectionStart = state.selectionStart or state.actionCursor or cursor
  state.selectionEnd = cursor

 elseif not ((_G.IsControlKeyDown and IsControlKeyDown()) or (_G.IsMetaKeyDown and _G.IsMetaKeyDown())) then state.selectionStart, state.selectionEnd, state.selectionUnknown = nil, nil, nil end
 state.actionCursor = cursor
end

function A:Key(input, key)
 if input ~= addon.Query.Console.input then return end
 local state, box = input.queryEditor, input.editBox
 local ctrl = _G.IsControlKeyDown and IsControlKeyDown()
 local alt = _G.IsAltKeyDown and IsAltKeyDown()
 local shift = _G.IsShiftKeyDown and IsShiftKeyDown()
 local source, cursor = input:GetText(), box:GetCursorPosition()
 if alt and not ctrl and not shift and (key=='UP' or key=='DOWN') and not E:IsReadOnly(input) then
  if state.selectionUnknown then return end
  local first, last = state.selectionStart, state.selectionEnd
  local text, position = self:Move(source,cursor,key=='UP' and -1 or 1,first,last)
  E:SetSource(input,text,position)
  state.actionLock, state.actionCursor = math.min(position,#text), math.min(position,#text)
  if first and last and first ~= last then
   local delta = position-cursor
   state.selectionStart, state.selectionEnd = math.min(first+delta,#text), math.min(last+delta,#text)
   box:HighlightText(math.min(math.min(first,last)+delta,#text),math.min(math.max(first,last)+delta,#text))
  end
  return true
 end
 if ctrl and key == 'A' then state.selectionStart, state.selectionEnd = 0, #source end
end

function A:KeyUp(input) input.queryEditor.actionLock = nil end

function A:Track(input)
 local box,state=input.editBox,input.queryEditor
 if state.selectionHook or not _G.hooksecurefunc then return end
 state.selectionHook=true
 _G.hooksecurefunc(box,'HighlightText',function(_,first,last)
  state.selectionStart,state.selectionEnd=first or 0,last and last>=0 and last or #box:GetText()
  state.selectionUnknown=nil
 end)
end
