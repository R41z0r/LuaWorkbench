local _, addon = ...
local UI = {}
addon.UI = UI
UI.colors = { background = { 0.055, 0.065, 0.085, 1 }, panel = { 0.085, 0.095, 0.12, 1 }, hover = { 0.16, 0.19, 0.24, 1 }, accent = { 0.22, 0.56, 0.96, 1 } }

function UI:InCombat()
 return _G.InCombatLockdown and _G.InCombatLockdown() or false
end

function UI:KeyboardPropagation(frame, propagate, initialize)
 if self:InCombat() then
  self.keyboardPending = self.keyboardPending or {}
  self.keyboardPending[frame] = initialize or self.keyboardPending[frame] or false
  if not self.keyboardRecovery then
   self.keyboardRecovery = CreateFrame('Frame')
   self.keyboardRecovery:SetScript('OnEvent', function()
    if self:InCombat() then return end
    self.keyboardRecovery:UnregisterEvent('PLAYER_REGEN_ENABLED')
    local pending = self.keyboardPending
    self.keyboardPending = {}
    for owner, enable in pairs(pending) do self:KeyboardPropagation(owner, true, enable) end
   end)
  end
  self.keyboardRecovery:RegisterEvent('PLAYER_REGEN_ENABLED')
  return false
 end
 if initialize then frame:EnableKeyboard(true) end
 frame:SetPropagateKeyboardInput(propagate)
 return true
end

function UI:Background(frame, color)
 local texture = frame:CreateTexture(nil, "BACKGROUND")
 texture:SetAllPoints()
 texture:SetColorTexture(unpack(color or self.colors.panel))
 return texture
end

function UI:Text(parent, text, size)
 local label = parent:CreateFontString(nil, "OVERLAY")
 label:SetFontObject(GameFontHighlightSmall)
 if size then local font, _, flags = label:GetFont(); label:SetFont(font, size, flags) end
 label:SetJustifyH("LEFT")
 label:SetText(text)
 label:SetTextColor(0.78, 0.82, 0.9)
 return label
end

function UI:Tooltip(frame, text)
 frame:SetScript("OnEnter", function()
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  GameTooltip:AddLine(text, 0.85, 0.9, 1, true)
  GameTooltip:Show()
 end)
 frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI:SearchClear(box, refresh)
 if box.clearButton then return box.clearButton end
 local left, right, top, bottom = box:GetTextInsets()
 box:SetTextInsets(left, math.max(right, 28), top, bottom)
 local button = self:Button(box, 'close', addon.L.clearSearch, function()
  box:SetText('')
  if refresh then refresh() end
  box:SetFocus()
 end)
 box.clearButton = button
 button:SetSize(24, 24); button:SetPoint('RIGHT', -2, 0)
 local function update() button:SetShown(box:GetText() ~= '') end
 box:HookScript('OnTextChanged', update)
 update()
 return button
end

function UI:Button(parent, icon, tooltip, callback, color, borderHover)
 local button = CreateFrame("Button", nil, parent)
 button:SetSize(30, 28)
 local highlight
 if borderHover then
  highlight = CreateFrame("Frame", nil, button)
  highlight:SetAllPoints()
  for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
   local stroke = highlight:CreateTexture(nil, "ARTWORK")
   stroke:SetColorTexture(0.76, 0.81, 0.9, 1)
   if edge == "TOP" or edge == "BOTTOM" then
    stroke:SetHeight(1)
    stroke:SetPoint(edge .. "LEFT"); stroke:SetPoint(edge .. "RIGHT")
   else
    stroke:SetWidth(1)
    stroke:SetPoint("TOP" .. edge); stroke:SetPoint("BOTTOM" .. edge)
   end
  end
 else
  highlight = button:CreateTexture(nil, "BACKGROUND", nil, 1)
  highlight:SetAllPoints()
  highlight:SetColorTexture(unpack(self.colors.hover))
 end
 highlight:Hide()
 button.iconStrokes = {}
 local function line(x1, y1, x2, y2)
  -- Axis-aligned strokes need a nonzero rectangular area on every client.
  if x1 == x2 or y1 == y2 then
   local stroke = button:CreateTexture(nil, "ARTWORK")
   stroke:SetColorTexture(unpack(color or { 0.76, 0.81, 0.9, 1 }))
   button.iconStrokes[#button.iconStrokes + 1] = stroke
   stroke:SetSize(math.max(1.5, math.abs(x2 - x1)), math.max(1.5, math.abs(y2 - y1)))
   stroke:SetPoint("CENTER", button, "CENTER", (x1 + x2) / 2, (y1 + y2) / 2)
   return
  end
  local stroke = button:CreateLine(nil, "ARTWORK")
  button.iconStrokes[#button.iconStrokes + 1] = stroke
  stroke:SetThickness(1.5)
  stroke:SetColorTexture(unpack(color or { 0.76, 0.81, 0.9, 1 }))
  stroke:SetStartPoint("CENTER", button, x1, y1)
  stroke:SetEndPoint("CENTER", button, x2, y2)
 end
 if icon == "search" or icon == "options" then
  local texture = button:CreateTexture(nil, "ARTWORK")
  texture:SetSize(18, 18); texture:SetPoint("CENTER")
  texture:SetTexture(icon == "search" and "Interface\\Common\\UI-Searchbox-Icon" or "Interface\\Buttons\\UI-OptionsButton")
  if icon == "options" then texture:SetDesaturated(true); texture:SetVertexColor(0.78, 0.82, 0.9, 1) end
 elseif icon == "frameStack" then
  line(-7, 3, 3, 3); line(3, 3, 3, -7); line(3, -7, -7, -7); line(-7, -7, -7, 3)
  line(-3, 7, 7, 7); line(7, 7, 7, -3); line(5, -3, 7, -3)
 elseif icon == "tableInspect" then
  line(-7, 7, 7, 7); line(7, 7, 7, -7); line(7, -7, -7, -7); line(-7, -7, -7, 7)
  line(-7, 2, 7, 2); line(-7, -3, 7, -3); line(-2, 7, -2, -7)
 elseif icon == "eventTrace" then
  line(-8, 0, -4, 0); line(-4, 0, -1, 6); line(-1, 6, 2, -6); line(2, -6, 5, 0); line(5, 0, 8, 0)
 elseif icon == "debug" then
  line(-4, 5, 4, 5); line(-4, 5, -4, -5); line(4, 5, 4, -5); line(-4, -5, 4, -5)
  line(0, 4, 0, -4); line(-2, 7, 2, 7)
  line(-6, 8, -3, 5); line(6, 8, 3, 5)
  for _, y in ipairs({ 3, 0, -3 }) do line(-8, y, -4, y); line(4, y, 8, y) end
 elseif icon == "stepInto" then
  line(0, 8, 0, -3); line(-4, 1, 0, -3); line(0, -3, 4, 1); line(-5, -7, 5, -7)
 elseif icon == "windowOptions" then
  line(-8, 7, 6, 7); line(-8, 7, -8, -6); line(-8, -6, -2, -6)
  line(-8, 3, 6, 3); line(6, 7, 6, 1)
  local gear = button:CreateTexture(nil, "ARTWORK")
  gear:SetTexture("Interface\\Buttons\\UI-OptionsButton")
  gear:SetSize(14, 14); gear:SetPoint("CENTER", 4, -4)
  gear:SetDesaturated(true); gear:SetVertexColor(0.78, 0.82, 0.9, 1)
 elseif icon == "fragment" then
  line(-7, 8, 4, 8); line(4, 8, 7, 5); line(7, 5, 7, -8)
  line(7, -8, -7, -8); line(-7, -8, -7, 8)
  line(-3, 3, -5, 0); line(-5, 0, -3, -3)
  line(3, 3, 5, 0); line(5, 0, 3, -3)
 elseif icon == "folder" then
  line(-7, 4, -2, 4); line(-2, 4, 0, 2); line(0, 2, 7, 2)
  line(7, 2, 7, -6); line(7, -6, -7, -6); line(-7, -6, -7, 4)
 elseif icon == "automatic" then
  -- Two opposing arrows built from opaque rectangles, without line primitives.
  line(-5, 4, 4, 4); line(-5, 0, -5, 4)
  line(-4, -4, 5, -4); line(5, -4, 5, 0)
  for step = 0, 3 do
   local upper = button:CreateTexture(nil, "ARTWORK")
   upper:SetColorTexture(unpack(color or { 0.76, 0.81, 0.9, 1 }))
   upper:SetSize(1, 1 + step * 2); upper:SetPoint("CENTER", button, "CENTER", 6 - step, 4)
   local lower = button:CreateTexture(nil, "ARTWORK")
   lower:SetColorTexture(unpack(color or { 0.76, 0.81, 0.9, 1 }))
   lower:SetSize(1, 1 + step * 2); lower:SetPoint("CENTER", button, "CENTER", -6 + step, -4)
  end
 elseif icon == "play" then
  line(-4, 6, 6, 0); line(6, 0, -4, -6); line(-4, -6, -4, 6)
 elseif icon == "stop" then
  line(-5, 5, 5, 5); line(5, 5, 5, -5); line(5, -5, -5, -5); line(-5, -5, -5, 5)
 elseif icon == "clear" then
  line(-6, 4, 6, 4); line(-3, 7, 3, 7); line(-4, 2, -3, -6); line(-3, -6, 3, -6); line(3, -6, 4, 2)
 elseif icon == "expand" then
  line(-6, 2, -6, 6); line(-6, 6, -2, 6); line(2, 6, 6, 6); line(6, 6, 6, 2)
  line(-6, -2, -6, -6); line(-6, -6, -2, -6); line(2, -6, 6, -6); line(6, -6, 6, -2)
 elseif icon == "minimize" then
  line(-5, -3, 5, -3)
 elseif icon == "copy" then
  line(-2, 3, 6, 3); line(6, 3, 6, -6); line(6, -6, -2, -6); line(-2, -6, -2, 3)
  line(-6, -2, -6, 7); line(-6, 7, 2, 7); line(2, 7, 2, 5)
 elseif icon == "search" or icon == "minimap" then
  local radius = icon == "search" and 4 or 6
  for index = 0, 11 do
   local a, b = index * math.pi / 6, (index + 1) * math.pi / 6
   line(math.cos(a) * radius - 1, math.sin(a) * radius + 1, math.cos(b) * radius - 1, math.sin(b) * radius + 1)
  end
  if icon == "search" then line(2, -2, 7, -7)
  else line(-1, 5, -3, -1); line(-3, -1, 2, 1); line(2, 1, -1, 5) end
 elseif icon == "previous" then
  line(3, 5, -2, 0); line(-2, 0, 3, -5)
 elseif icon == "next" then
  line(-3, 5, 2, 0); line(2, 0, -3, -5)
 elseif icon == "close" then
  line(-4, 4, 4, -4); line(-4, -4, 4, 4)
 elseif icon == "new" then
  line(-5, 0, 5, 0); line(0, -5, 0, 5)
 elseif icon == "saveAll" then
  line(-3, 8, 7, 8); line(7, 8, 7, -3); line(5, -3, 7, -3)
  line(-3, 6, -3, 8); line(0, 8, 0, 5); line(0, 5, 4, 5); line(4, 5, 4, 8)
  line(-7, 3, 3, 3); line(3, 3, 3, -8); line(3, -8, -7, -8); line(-7, -8, -7, 3)
  line(-4, 3, -4, -1); line(-4, -1, 0, -1); line(0, -1, 0, 3)
 elseif icon == "save" then
  line(-6, 6, 4, 6); line(4, 6, 6, 4); line(6, 4, 6, -6); line(6, -6, -6, -6); line(-6, -6, -6, 6)
  line(-3, 6, -3, 1); line(-3, 1, 3, 1); line(3, 1, 3, 6)
 else
  local label = self:Text(button, icon, 12); label:SetPoint("CENTER")
 end
 self:Tooltip(button, tooltip)
 button:HookScript("OnEnter", function() highlight:Show() end)
 button:HookScript("OnLeave", function() highlight:Hide() end)
 button:HookScript("OnHide", function() highlight:Hide() end)
 button:SetScript("OnClick", function() GameTooltip:Hide(); callback() end)
 return button
end

function UI:ButtonColor(button, color)
 for _, stroke in ipairs(button.iconStrokes or {}) do stroke:SetColorTexture(unpack(color)) end
end

function UI:Scroll(parent)
 local scroll = CreateFrame("ScrollFrame", nil, parent)
 local bar = CreateFrame("Slider", nil, parent)
 bar:SetWidth(7)
 bar:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 10, 0)
 bar:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 10, 0)
 bar:SetOrientation("VERTICAL")
 bar:SetMinMaxValues(0, 0)
 bar:SetValueStep(18)
 bar:SetObeyStepOnDrag(false)
 self:Background(bar, { 0.08, 0.09, 0.11, 1 })
 bar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
 bar:GetThumbTexture():SetVertexColor(0.3, 0.35, 0.43, 1)
 bar:GetThumbTexture():SetSize(7, 35)
 bar:SetScript("OnValueChanged", function(_, value) scroll:SetVerticalScroll(value) end)
 scroll:EnableMouseWheel(true)
 scroll:SetScript("OnMouseWheel", function(_, delta)
  bar:SetValue(math.max(0, math.min(scroll:GetVerticalScrollRange(), scroll:GetVerticalScroll() - delta * 48)))
 end)
 scroll:SetScript("OnScrollRangeChanged", function(_, _, range)
  bar:SetMinMaxValues(0, range)
  local offset = math.max(0, math.min(range, scroll:GetVerticalScroll()))
  bar:SetValue(offset)
  -- A clamped slider may already have this value and emit no value change.
  scroll:SetVerticalScroll(offset)
  bar:SetShown(range > 0)
 end)
 scroll:SetScript("OnVerticalScroll", function(_, value)
  if bar:GetValue() ~= value then bar:SetValue(value) end
 end)
 scroll.bar = bar
 return scroll
end

function UI:Editor(parent, labelText, readonly)
 local panel = CreateFrame("Frame", nil, parent)
 self:Background(panel, self.colors.background)
 local label = self:Text(panel, labelText, 11)
 label:SetPoint("TOPLEFT", 12, -10)
 label:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -85, -10)
 label:SetHeight(14)
 local scrollBG = CreateFrame("Frame", nil, panel)
 scrollBG:SetPoint("TOPLEFT", 6, -34)
 scrollBG:SetPoint("BOTTOMRIGHT", -16, 8)
 local scroll = self:Scroll(scrollBG)
 scroll:SetPoint("TOPLEFT", scrollBG, "TOPLEFT", 6, -6)
 scroll:SetPoint("BOTTOMRIGHT", scrollBG, "BOTTOMRIGHT", -4, 4)
 local box = CreateFrame("EditBox", nil, scroll)
 box:SetMultiLine(true)
 box:SetAutoFocus(false)
 box:SetFontObject(ChatFontNormal)
 box:SetSpacing(2)
 box:SetTextInsets(0, 0, 0, 0)
 box:SetMaxLetters(0)
 box:SetCountInvisibleLetters(true)
 box:SetTextColor(0.8, 0.84, 0.92)
 box:SetHeight(1)
 scroll:SetScrollChild(box)
 local input = { frame = panel, editBox = box, scrollFrame = scroll, scrollBG = scrollBG, label = label, readonly = readonly }
 function input:GetText() return self.editBox:GetText() end
 function input:SetText(text)
  self.rawText = text
  self.setting = true
  self.editBox:SetText(text)
  self.editBox:SetCursorPosition(0)
  self.setting = nil
 end
 function input:SetFocus() self.editBox:SetFocus() end
 function input:ClearFocus() self.editBox:ClearFocus() end
 function input:SetCursorPosition(position) self.editBox:SetCursorPosition(position) end
 function input:HighlightText(...) self.editBox:HighlightText(...) end
 scroll:SetScript("OnSizeChanged", function(_, width) box:SetWidth(math.max(1, width)) end)
 scroll:EnableMouse(true)
 scroll:SetScript("OnMouseDown", function(_, button)
  if button == "LeftButton" then box:SetFocus(); box:SetCursorPosition(#box:GetText()) end
 end)
 local function codeMenu(_, button)
  if button == 'RightButton' and input.queryEditor and not readonly and addon.Snippets then addon.Snippets:OpenCodeMenu(input) end
 end
 box:SetScript('OnMouseUp', codeMenu)
 scroll:SetScript('OnMouseUp', codeMenu)
 box:SetScript("OnEditFocusLost", function() box:HighlightText(0, 0) end)
 box:SetScript("OnCursorChanged", function(frame, x, y, _, height)
  -- Layout/scroll notifications can repeat without moving the text cursor.
  -- Only an actual caret move should override a manually chosen viewport.
  local position = frame:GetCursorPosition()
  if input.cursorPosition == position and input.cursorX == x and input.cursorY == y then return end
  input.cursorPosition, input.cursorX, input.cursorY = position, x, y
  local offset = scroll:GetVerticalScroll()
  if -y < offset then scroll:SetVerticalScroll(math.max(0, -y))
  elseif -y + height > offset + scroll:GetHeight() then
   scroll:SetVerticalScroll(math.min(scroll:GetVerticalScrollRange(), -y + height - scroll:GetHeight()))
  end
 end)
 box:SetScript("OnEscapePressed", function() box:ClearFocus() end)
 box:SetScript("OnTextChanged", function(_, user)
  if input.setting then return end
  if readonly then
   if user then input:SetText(input.rawText or "") end
  elseif input.changed then input.changed(box:GetText()) end
 end)
 return input
end

function UI:Dot(parent, size)
 local dot = parent:CreateTexture(nil, "OVERLAY")
 dot:SetSize(size or 7, size or 7)
 dot:SetColorTexture(0.82, 0.85, 0.9, 1)
 local mask = parent:CreateMaskTexture(nil, "OVERLAY")
 mask:SetAllPoints(dot)
 mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
 dot:AddMaskTexture(mask)
 return dot
end

function UI:FolderMarker(parent)
 local frame = CreateFrame('Frame', nil, parent)
 frame:SetSize(32, 24); frame:SetPoint('TOPLEFT', 0, 0)
 local function rectangle(x, y, width, height)
  local texture = frame:CreateTexture(nil, 'ARTWORK')
  texture:SetColorTexture(0.68, 0.76, 0.87, 1)
  texture:SetSize(width, height); texture:SetPoint('TOPLEFT', x, -y)
  return texture
 end
 -- Folder outline and tab, independent of glyph availability.
 rectangle(18, 8, 5, 1); rectangle(18, 8, 1, 10)
 rectangle(22, 9, 8, 1); rectangle(29, 9, 1, 9); rectangle(18, 17, 12, 1)
 frame.right, frame.down = {}, {}
 for i = 0, 3 do
  frame.right[#frame.right + 1] = rectangle(8 + i, 9 + i, 1, 2)
  frame.right[#frame.right + 1] = rectangle(8 + i, 15 - i, 1, 2)
  frame.down[#frame.down + 1] = rectangle(7 + i, 11 + i, 2, 1)
  frame.down[#frame.down + 1] = rectangle(13 - i, 11 + i, 2, 1)
 end
 function frame:SetExpanded(expanded)
  for _, texture in ipairs(self.right) do texture:SetShown(not expanded) end
  for _, texture in ipairs(self.down) do texture:SetShown(expanded) end
 end
 return frame
end

function UI:Border(frame, color)
 for _, edge in ipairs({ 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' }) do
  local line = frame:CreateTexture(nil, 'BORDER')
  line:SetColorTexture(unpack(color))
  if edge == 'TOP' or edge == 'BOTTOM' then
   line:SetHeight(1); line:SetPoint(edge .. 'LEFT'); line:SetPoint(edge .. 'RIGHT')
  else
   line:SetWidth(1); line:SetPoint('TOP' .. edge); line:SetPoint('BOTTOM' .. edge)
  end
 end
end

function UI:Check(parent, text, callback)
 local button = CreateFrame('CheckButton', nil, parent)
 button:SetSize(370, 24)
 local square = button:CreateTexture(nil, 'BACKGROUND'); square:SetSize(16, 16); square:SetPoint('LEFT')
 square:SetColorTexture(0.2, 0.25, 0.32, 1)
 local check = button:CreateTexture(nil, 'ARTWORK')
 check:SetTexture('Interface\\Buttons\\UI-CheckBox-Check'); check:SetSize(20, 20); check:SetPoint('CENTER', square, 'CENTER'); check:SetDesaturated(true)
 button:SetCheckedTexture(check)
 button.label = self:Text(button, text, 11)
 button.label:SetPoint('LEFT', 24, 0); button.label:SetPoint('RIGHT', -4, 0); button.label:SetWordWrap(false)
 local hover = button:CreateTexture(nil, 'HIGHLIGHT'); hover:SetAllPoints(square); hover:SetColorTexture(1, 1, 1, 0.12)
 button:SetScript('OnClick', callback)
 return button
end

function UI:Action(parent, icon, text, tooltip, callback)
 local button = self:Button(parent, '', tooltip, callback, nil, true)
 button.label = self:Text(button, text, 11); button.label:SetPoint('LEFT', 29, 0)
 button:SetWidth(40 + button.label:GetStringWidth())
 local symbol = self:Button(button, icon, tooltip, callback)
 symbol:SetPoint('LEFT'); symbol:SetSize(26, 26); symbol:EnableMouse(false)
 return button
end

-- Keep auxiliary panels anchored to the screen while retaining editor visibility.
function UI:MovablePanel(panel, key)
 panel:SetMovable(true)
 panel:SetClampedToScreen(true)
 local function scale() return panel:GetEffectiveScale() / UIParent:GetEffectiveScale() end
 local function restore()
  local saved = addon.Workspace.db.panelPositions and addon.Workspace.db.panelPositions[key]
  local ratio = scale()
  local x, y = panel:GetCenter()
  x = x and x * ratio - UIParent:GetWidth() / 2 or 0
  y = y and y * ratio - UIParent:GetHeight() / 2 or 0
  if saved then x, y = saved.x, saved.y end
  local width, height = panel:GetSize()
  panel:ClearAllPoints()
  panel:SetSize(width, height)
  panel:SetPoint('CENTER', UIParent, 'CENTER', x / ratio, y / ratio)
 end
 local function stop()
  if not panel.dragging then return end
  panel.dragging = nil
  panel:StopMovingOrSizing()
  local x, y = panel:GetCenter()
  if not x or not y then return end
  local db, ratio = addon.Workspace.db, scale()
  db.panelPositions = db.panelPositions or {}
  db.panelPositions[key] = { x = x * ratio - UIParent:GetWidth() / 2, y = y * ratio - UIParent:GetHeight() / 2 }
  restore()
 end
 local handle = CreateFrame('Frame', nil, panel)
 handle:SetPoint('TOPLEFT'); handle:SetPoint('TOPRIGHT', -42, 0); handle:SetHeight(34)
 handle:EnableMouse(true); handle:RegisterForDrag('LeftButton')
 handle:SetScript('OnDragStart', function() panel.dragging = true; panel:StartMoving() end)
 handle:SetScript('OnDragStop', stop)
 panel:HookScript('OnHide', stop)
 panel:HookScript('OnShow', restore)
 panel.RestorePanelPosition = restore
 panel.dragHandle = handle
end
