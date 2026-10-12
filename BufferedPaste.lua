local _, addon = ...
local Buffer = {}
addon.BufferedPaste = Buffer

-- Keep native paste insertion cheap by draining the growing EditBox. The first
-- drain observes the native selection replacement, so no guessed selection or
-- clipboard access is needed. Only the completed edit reaches consumer scripts.
function Buffer:Finish(box)
 local owner = box._bufferedPaste
 local paste = owner and owner.paste
 if not paste or owner.internal then return end
 owner.internal = true
 if paste.chunks then
  paste.chunks[#paste.chunks + 1] = box:GetText()
  local left = table.concat(paste.chunks)
  box:SetText(left .. paste.suffix)
  box:SetCursorPosition(#left)
 end
 owner.internal, owner.paste = nil, nil
 if box:GetText() ~= paste.source and owner.original.OnTextChanged then
  owner.original.OnTextChanged(box, true)
 end
 if paste.cursor and owner.original.OnCursorChanged then
  owner.original.OnCursorChanged(box, unpack(paste.cursor))
 end
end

function Buffer:Detach(box)
 local owner = box and box._bufferedPaste
 if not owner then return end
 self:Finish(box)
 for event, wrapper in pairs(owner.wrappers) do
  if box:GetScript(event) == wrapper then box:SetScript(event, owner.original[event]) end
 end
 box._bufferedPaste = nil
end

function Buffer:Attach(box, canPaste)
 self:Detach(box)
 local owner = {original = {}, wrappers = {}}
 box._bufferedPaste = owner
 local function wrap(event, handler)
  owner.original[event] = box:GetScript(event)
  owner.wrappers[event] = handler
  box:SetScript(event, handler)
 end
 local function call(event, ...)
  local original = owner.original[event]
  if original then return original(box, ...) end
 end
 wrap('OnKeyDown', function(_, key)
  self:Finish(box)
  local result = call('OnKeyDown', key)
  local mac = _G.IsMacClient and _G.IsMacClient()
  local modifier = mac and _G.IsMetaKeyDown and _G.IsMetaKeyDown()
   or not mac and _G.IsControlKeyDown and _G.IsControlKeyDown()
  if key ~= 'V' or not modifier or (_G.IsAltKeyDown and _G.IsAltKeyDown())
   or (canPaste and not canPaste()) then return result end
  -- Do not bypass native length restrictions by repeatedly emptying the field.
  for _, method in ipairs({'GetMaxLetters', 'GetMaxBytes', 'GetVisibleTextByteLimit'}) do
   if box[method] and box[method](box) > 0 then return result end
  end
  local paste = {source = box:GetText(), count = 0}
  owner.paste = paste
  C_Timer.After(0, function()
   if box._bufferedPaste == owner and owner.paste == paste then self:Finish(box) end
  end)
  return result
 end)
 wrap('OnChar', function(_, char)
  if owner.internal then return end
  local paste = owner.paste
  if not paste then return call('OnChar', char) end
  paste.count = paste.count + 1
  if paste.count < 256 then return end
  paste.count = 0
  local text = box:GetText()
  if text == '' then return end
  if not paste.chunks then
   local cursor = box:GetCursorPosition()
   paste.chunks, paste.suffix = {text:sub(1, cursor)}, text:sub(cursor + 1)
  else
   paste.chunks[#paste.chunks + 1] = text
  end
  owner.internal = true
  box:SetText('')
  box:SetCursorPosition(0)
  owner.internal = nil
 end)
 wrap('OnTextChanged', function(_, user)
  if owner.internal or owner.paste then return end
  return call('OnTextChanged', user)
 end)
 wrap('OnCursorChanged', function(_, x, y, width, height)
  if owner.paste then owner.paste.cursor = {x, y, width, height}; return end
  if not owner.internal then return call('OnCursorChanged', x, y, width, height) end
 end)
 for _, event in ipairs({'OnKeyUp', 'OnEditFocusLost', 'OnHide', 'OnMouseDown', 'OnEnterPressed', 'OnEscapePressed', 'OnUpdate'}) do
  wrap(event, function(_, ...)
   self:Finish(box)
   return call(event, ...)
  end)
 end
end
