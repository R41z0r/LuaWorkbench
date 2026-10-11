local _, addon = ...
local L, UI, Console = addon.L, addon.UI, addon.Query.Console
local Workspace = {}
addon.Workspace = Workspace
_G.LuaWorkbench = Workspace

function Workspace:Initialize()
 if self.db then return end
 local db = _G.LuaWorkbenchDB or {}
 _G.LuaWorkbenchDB = db
 db.snippets, db.drafts = db.snippets or {}, db.drafts or {}
 db.folders, db.folderBySnippet = db.folders or {}, db.folderBySnippet or {}
 db.options = db.options or {}
 db.clearOnRun = db.clearOnRun or {}
 db.autoRun = db.autoRun or {}
 db.helperModules = db.helperModules or {}
 db.textSnippets = db.textSnippets or {}
 db.serial = db.serial or 0
 db.split = db.split or 0.65
 db.minimap = db.minimap or { hide = db.showMinimap == false }
 db.showMinimap = nil
 self.db = db
 if db.options.restoreDrafts == false then self:DiscardSessionDrafts() end
 if not next(db.drafts) and not next(db.snippets) then self:New() end
end

function Workspace:HidePanels(except)
 for _, panel in ipairs({ addon.KnowledgeBase and addon.KnowledgeBase.panel or false, self.optionsFrame or false, self.syntaxFrame or false, self.helpFrame or false,
  addon.Automation and addon.Automation.panel or false, addon.Diagnostics and addon.Diagnostics.panel or false,
  addon.Snippets and addon.Snippets.panel or false, addon.Navigation and addon.Navigation.snapshot or false,
 }) do if panel and panel ~= except then panel:Hide() end end
end

function Workspace:UpdateStatus()
 self:UpdateSaveButtons()
 if addon.Automation then addon.Automation:UpdateControls() end
 if not self.status then return end
 self.status:SetText(((Console.statusText or L.ready):gsub('|', '||')))
 if Console.statusFailed then self.status:SetTextColor(1, 0.35, 0.38)
 elseif Console.statusText then self.status:SetTextColor(0.4, 0.85, 0.57)
 else self.status:SetTextColor(0.6, 0.65, 0.73) end
 self.dirtyDot:SetShown(self.dirty and not self.db.options.dirtyText)
 Console:UpdateEditorLabel()
end

function Workspace:UpdateSaveButtons()
 local currentDirty = self.current and self:IsSnippetDirty(self.current) or false
 local anyDirty = currentDirty
 if not anyDirty then
  for id in pairs(self.db.drafts) do if self:IsSnippetDirty(id) then anyDirty = true; break end end
 end
 local function update(button, enabled)
  if button and button.saveEnabled ~= enabled then
   button.saveEnabled = enabled
   button:SetEnabled(enabled); button:SetAlpha(enabled and 1 or 0.35)
  end
 end
 update(self.saveCurrentButton, currentDirty)
 update(self.saveAllButton, anyDirty)
end

function Workspace:IsSnippetDirty(id)
 local draft, saved = self.db.drafts[id], self.db.snippets[id]
 if not draft then return false end
 local source = self:NormalizeSource(draft.source)
 if not saved then return source ~= '' end
 return draft.name ~= saved.name or source ~= self:NormalizeSource(saved.source)
end

function Workspace:Capture()
 if self.selecting or not self.current or not self.currentName then return end
 local name, source = self.currentName, self:StoreSource(Console.source or '')
 self.db.drafts[self.current] = { name = name, source = source }
 self.dirty = self:IsSnippetDirty(self.current)
 self:UpdateStatus()
end

function Workspace:New()
 self:Capture()
 self.db.serial = self.db.serial + 1
 local id = tostring(self.db.serial)
 self.db.drafts[id] = { name = L.newSnippet .. ' ' .. id, source = '' }
 self.db.selected = id
 if self.selectedFolder and self.db.folders[self.selectedFolder] then
  self.db.folderBySnippet[id] = self.selectedFolder
  self.db.folders[self.selectedFolder].collapsed = nil
 end
 if self.window then
  self.snippetSearch:SetText('')
  self:Select(id)
  self:BeginRename(id)
 end
 return id
end

function Workspace:Save()
 self:Capture()
 local draft = self.db.drafts[self.current]
 if not draft then return end
 local name = draft.name:match('^%s*(.-)%s*$')
 if name == '' then name = L.newSnippet .. ' ' .. self.current end
 draft.name = name
 self.db.snippets[self.current] = { name = name, source = draft.source }
 self.currentName = name
 addon.Automation:Refresh()
 self:Capture()
 self:RefreshTree()
end

function Workspace:SaveAll()
 self:Capture()
 for id, draft in pairs(self.db.drafts) do
  if self:IsSnippetDirty(id) then
   local name = draft.name:match('^%s*(.-)%s*$')
   if name == '' then name = L.newSnippet .. ' ' .. id end
   draft.name = name
   self.db.snippets[id] = { name = name, source = draft.source }
   if id == self.current then self.currentName = name end
  end
 end
 addon.Automation:Refresh()
 self:Capture(); self:RefreshTree()
end

function Workspace:Delete(id)
 if self.current ~= id then return end
 if type(self.db.startupDebug) == 'table' and self.db.startupDebug.id == id then self.db.startupDebug = nil end
 if addon.Debugger then
  if addon.Debugger.scriptId == id or (addon.Debugger.sources and addon.Debugger.sources[id]) then addon.Debugger:Stop() end
  addon.Debugger:RemoveBreakpoints(id)
 end
 self.current = nil
 self.db.clearOnRun[id], self.db.autoRun[id], self.db.helperModules[id] = nil, nil, nil
 addon.Automation.environments[id] = nil
 addon.Automation:Refresh()
 self.db.snippets[id], self.db.drafts[id], self.db.folderBySnippet[id] = nil, nil, nil
 local nextID = next(self.db.drafts) or next(self.db.snippets)
 if nextID then self:Select(nextID) else self:New() end
end

function Workspace:UpdateClearOnRunIndicator()
 if not self.clearOnRunHint then return end
 local enabled = self.current and self.db.clearOnRun[self.current] == true
 self.clearOnRunHint:SetShown(enabled == true)
 local extra = 0
 if self.outputAutoScroll then
  local needed = 12 + 110 + 14 + self.outputClear:GetWidth() + 20 + self.outputAutoScroll:GetWidth() + 12 + self.outputCopy:GetWidth() + 40
  extra = self.output.frame:GetWidth() < needed and 28 or 0
  self.outputCopy:ClearAllPoints(); self.outputCopy:SetPoint('TOPRIGHT', -40, -2 - extra)
  self.outputAutoScroll:SetChecked(Console:AutoScrollEnabled())
 end
 self.clearOnRunHint:ClearAllPoints()
 self.clearOnRunHint:SetPoint('TOPLEFT', 12, -32 - extra); self.clearOnRunHint:SetPoint('TOPRIGHT', -16, -32 - extra)
 self.output.scrollBG:SetPoint('TOPLEFT', self.output.frame, 'TOPLEFT', 6, (enabled and -52 or -34) - extra)
end

function Workspace:RefreshTree()
 self:UpdateSaveButtons()
 if not self.list then return end
 self.rows = self:TreeRows()
 local offset = 0
 for _, row in ipairs(self.rows) do
  row.dirty = not row.folder and self:IsSnippetDirty(row.id)
  row.detail = not row.folder and (#row.matches > 0 and string.format(L.matches, #row.matches) or (row.dirty and self.db.options.dirtyText and L.unsaved)) or nil
  row.offset, row.height = offset, row.detail and 40 or 26
  offset = offset + row.height
 end
 self.list:SetHeight(math.max(1, offset))
 self.rowButtons = self.rowButtons or {}
 for index, row in ipairs(self.rows) do
  local button = self.rowButtons[index]
  if not button then
   button = CreateFrame('Button', nil, self.list)
   button.background = UI:Background(button)
   button.folderMarker = UI:FolderMarker(button)
   button.guide = button:CreateTexture(nil, 'ARTWORK')
   button.guide:SetColorTexture(0.28, 0.33, 0.4, 1)
   button.guide:SetWidth(1)
   button.title = UI:Text(button, '', 12)
   button.title:SetPoint('TOPLEFT', 10, -5)
   button.title:SetPoint('TOPRIGHT', -22, -5)
   button.title:SetHeight(14)
   button.automatic = UI:Button(button, 'automatic', L.automaticRun, function()
    self:Select(button.row.id)
    addon.Automation:Toggle(button.automatic)
   end, { 0.55, 0.76, 1, 1 }, true)
   button.automatic:SetSize(22, 24); button.automatic:SetPoint('TOPRIGHT', -18, -1)
   button.automatic:HookScript('OnEnter', function()
    GameTooltip:ClearLines(); GameTooltip:AddLine(addon.Automation:Tooltip(button.row.id), 0.85, 0.9, 1, true); GameTooltip:Show()
   end)
   UI:Background(button.automatic, { 0.12, 0.24, 0.37, 1 })
   button.helper = UI:Button(button, '{}', L.helperModule, function()
    self:Select(button.row.id)
    addon.Automation:Toggle(button.helper)
   end, nil, true)
   button.helper:SetSize(22, 24)
   UI:Background(button.helper, { 0.23, 0.17, 0.34, 1 })
   button.helper:HookScript('OnEnter', function()
    local options = self.db.helperModules[button.row.id]
    GameTooltip:ClearLines(); GameTooltip:AddLine(L.helperModule, 0.85, 0.9, 1)
    GameTooltip:AddLine((options and options.name or ''):gsub('|', '||'), 0.75, 0.67, 1)
    GameTooltip:Show()
   end)
   button.dot = UI:Dot(button, 7); button.dot:SetPoint('TOPRIGHT', -7, -8)
   button.subtitle = UI:Text(button, '', 10)
   button.subtitle:SetPoint('BOTTOMLEFT', 10, 5)
   button.subtitle:SetPoint('BOTTOMRIGHT', -8, 5)
   button.subtitle:SetHeight(12)
   button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
   button:SetScript('OnClick', function(_, mouse)
    if mouse == 'RightButton' then self:ShowSnippetMenu(button); return end
    local selected = button.row
    if selected.folder then
     self:EndRename(false)
     self.selectedFolder = selected.id
     local folder = self.db.folders[selected.id]
     folder.collapsed = not folder.collapsed
     self:RefreshTree()
     return
    end
    self:Select(selected.id)
    if #selected.matches > 0 and self.snippetSearch:GetText() ~= '' then
     self:OpenFind(self.snippetSearch:GetText())
     self:Find(1, true)
    end
   end)
   self.rowButtons[index] = button
  end
  button.row = row
  local automatic = not row.folder and addon.Automation:Summary(row.id) ~= ''
  button.automatic:SetShown(automatic)
  local helper = not row.folder and self.db.helperModules[row.id] and self.db.helperModules[row.id].enabled == true
  button.helper:SetShown(helper == true)
  button.helper:ClearAllPoints(); button.helper:SetPoint('TOPRIGHT', automatic and -42 or -18, -1)
  button.title:SetPoint('TOPRIGHT', -22 - (automatic and 24 or 0) - (helper and 24 or 0), -5)
  button:ClearAllPoints()
  button:SetPoint('TOPLEFT', 0, -row.offset)
  button:SetPoint('TOPRIGHT', 0, -row.offset)
  button:SetHeight(row.height)
  button.title:SetPoint('TOPLEFT', row.folder and 36 or (row.indent and 42 or 10), -6)
  button.title:SetText(((row.name ~= '' and row.name or L.newSnippet):gsub('|', '||')))
  button.folderMarker:SetShown(row.folder == true)
  if row.folder then button.folderMarker:SetExpanded(row.expanded) end
  button.guide:ClearAllPoints()
  button.guide:SetPoint('TOPLEFT', 11, row.folder and -21 or 0)
  button.guide:SetHeight(row.folder and math.max(1, row.height - 21) or row.height)
  button.guide:SetShown(row.indent == true or (row.folder and row.expanded and row.hasChildren) or false)
  button.dot:SetShown(row.dirty and not self.db.options.dirtyText)
  button.subtitle:SetText(row.detail or '')
  button.subtitle:SetShown(row.detail ~= nil and row.detail ~= false)
  button.subtitle:SetPoint('BOTTOMLEFT', row.indent and 42 or 10, 5)
  button.subtitle:SetTextColor(0.5, 0.57, 0.68)
  button.background:SetColorTexture(unpack(row.id == self.current and { 0.12, 0.24, 0.38, 1 } or UI.colors.panel))
  button:Show()
 end
 for i = #self.rows + 1, #self.rowButtons do self.rowButtons[i]:Hide() end
 self.noResults:SetShown(#self.rows == 0)
 self:AnchorRename()
end

function Workspace:Select(id)
 if addon.Automation.panel then addon.Automation.panel:Hide() end
 self:EndRename(false)
 if self.contextMenu then self.contextMenu:Hide() end
 self:Capture()
 local snippet = self.db.drafts[id] or self.db.snippets[id]
 if not snippet then return end
 self.selecting = true
 self.current, self.db.selected = id, id
 self.currentName = snippet.name
 self.selectedFolder = self.db.folderBySnippet[id]
 Console.source, Console.lastError = self:NormalizeSource(snippet.source), nil
 Console:SetStatus(nil)
 addon.Query.Editor:SetSource(Console.input, Console.source, 0)
 Console.input.scrollFrame:SetVerticalScroll(0)
 self.selecting = nil
 Console:UpdateLineNumbers()
 self:Capture()
 self:RefreshTree()
 if self.findBar:IsShown() then self:Find(0, true) end
end

function Workspace:Find(direction, reset)
 if not self.findText then return end
 local matches = addon.Search:Matches(Console.source, self.findText:GetText(), self.matchCase, self.wholeWord)
 self.matches = matches
 if reset then self.matchIndex = nil end
 if #matches == 0 then
  self.matchIndex = nil
  self.findCount:SetText(L.noResults)
  Console.input:HighlightText(0, 0)
  return
 end
 self.matchIndex = ((self.matchIndex and (self.matchIndex - 1 + direction) or 0) % #matches) + 1
 self.findCount:SetText(string.format(L.matchPosition, self.matchIndex, #matches))
 if direction == 0 and not reset then return end
 local match = matches[self.matchIndex]
 Console.input:SetCursorPosition(match.first - 1)
 Console.input:HighlightText(match.first - 1, match.last)
end

function Workspace:OpenFind(text)
 self.findBar:Show()
 if text then
  self.matchCase, self.wholeWord = false, false
  self:UpdateFindOptions()
  self.findText:SetText(text)
 end
 self:Layout()
 self.findText:SetFocus()
 self.findText:HighlightText()
 self:Find(0, true)
end

function Workspace:RunShortcut(key)
 if addon.DebugUI and addon.DebugUI:Shortcut(key) then return true end
 if addon.Navigation and addon.Navigation:Shortcut(key) then return true end
 if key ~= 'F5' or not self.window or not self.window:IsShown() or self.db.options.runWithF5 == false then return false end
 if IsControlKeyDown() or IsShiftKeyDown() or (_G.IsAltKeyDown and IsAltKeyDown()) or (_G.IsMetaKeyDown and _G.IsMetaKeyDown()) then return false end
 local active = self.window:IsMouseOver()
 for _, box in ipairs({ Console.input.editBox, self.output.editBox, self.snippetSearch, self.findText, self.renameInput or self.snippetSearch, addon.Automation.controls and addon.Automation.controls.event or self.snippetSearch }) do
  if box:HasFocus() then active = true end
 end
 if not active and not self.f5Held then return false end
 if not self.f5Held then self.f5Held = true; self:Run() end
 return true
end

function Workspace:Shortcut(key)
 if self:RunShortcut(key) then return end
 if not UI:PrimaryModifier() then return end
 if key == 'F' then
  if IsShiftKeyDown() then
   self.codeOnly = false; self:Layout(); self.snippetSearch:SetFocus(); self.snippetSearch:HighlightText()
  else self:OpenFind() end
 elseif key == 'S' then self:Save()
 elseif key == 'ENTER' or key == 'NUMPADENTER' then self:Run() end
end

function Workspace:Run()
 if addon.Debugger and addon.Debugger.armed and addon.Debugger.scriptId == self.current then
  if addon.Debugger.paused then addon.Debugger:Continue() else addon.Debugger:Enqueue(nil) end
  return
 end
 if self.db.clearOnRun[self.current] then Console:Clear() end
 Console.input:ClearFocus()
 Console:Run(Console.input:GetText())
end

function Workspace:Layout()
 if not self.window then return end
 local width, height = self.window:GetWidth(), self.window:GetHeight()
 local left, top, bottom = self.codeOnly and 8 or 238, 42, 32
 self.sidebar:SetShown(not self.codeOnly)
 local detached = addon.OutputWindow and addon.OutputWindow:Mode() ~= 'embedded'
 self.output.frame:SetShown(not self.codeOnly or detached)
 self.divider:SetShown(not self.codeOnly and not detached)
 local available = math.max(140, height - top - bottom)
 local codeHeight = (self.codeOnly or detached) and available or math.max(180, math.min(available - 100, available * self.db.split))
 if addon.Debugger and addon.Debugger.armed and not self.codeOnly and not detached then codeHeight = math.min(available - 80, math.max(codeHeight, 330)) end
 local code = Console.input.frame
 code:ClearAllPoints()
 code:SetPoint('TOPLEFT', left, -top)
 code:SetSize(math.max(200, width - left - 8), codeHeight)
 self.findBar:ClearAllPoints()
 self.findBar:SetPoint('TOPRIGHT', code, 'TOPRIGHT', -10, -56)
 Console.input.scrollBG:SetPoint('TOPLEFT', code, 'TOPLEFT', 6, self.findBar:IsShown() and -96 or -56)
 self.divider:ClearAllPoints()
 self.divider:SetPoint('TOPLEFT', code, 'BOTTOMLEFT', 0, 0)
 self.divider:SetSize(code:GetWidth(), 8)
 if addon.OutputWindow then addon.OutputWindow:Apply()
 else
  self.output.frame:ClearAllPoints()
  self.output.frame:SetPoint('TOPLEFT', code, 'BOTTOMLEFT', 0, -8)
  self.output.frame:SetSize(code:GetWidth(), math.max(50, available - codeHeight - 8))
 end
 if addon.DebugUI then addon.DebugUI:Layout() end
 Console:UpdateLineNumbers()
end

function Workspace:SaveGeometry(key)
 local frame = key == 'window' and self.window or self.minibar
 if not frame or (key == 'window' and self.fullscreen) then return end
 local x, y = frame:GetCenter()
 if not x or not y then return end
 self.db[key .. 'Geometry'] = {
  x = x - UIParent:GetWidth() / 2, y = y - UIParent:GetHeight() / 2,
  width = frame:GetWidth(), height = frame:GetHeight(),
 }
end

function Workspace:RestoreGeometry(key)
 local frame = key == 'window' and self.window or self.minibar
 local saved = self.db[key .. 'Geometry']
 frame:ClearAllPoints()
 if key == 'window' then
  frame:SetSize(math.min(saved and saved.width or 1180, UIParent:GetWidth()), math.min(saved and saved.height or 800, UIParent:GetHeight()))
 end
 frame:SetPoint('CENTER', UIParent, 'CENTER', saved and saved.x or 0, saved and saved.y or (key == 'window' and 0 or -200))
end

function Workspace:ApplyWindowClamp()
 local enabled = self.db.options.windowClamp ~= false
 if self.window then self.window:SetClampedToScreen(enabled) end
 if self.minibar then self.minibar:SetClampedToScreen(enabled) end
end

function Workspace:RecoverWindow()
 local frame = self.window
 if not frame or self.fullscreen then return end
 local x, y = frame:GetCenter()
 if not x or not y then return end
 local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
 local halfWidth, halfHeight = frame:GetWidth() * scale / 2, frame:GetHeight() * scale / 2
 x, y = x * scale, y * scale
 if x + halfWidth <= 0 or y + halfHeight <= 0 or x - halfWidth >= UIParent:GetWidth() or y - halfHeight >= UIParent:GetHeight() then
  frame:ClearAllPoints(); frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
  local saved = self.db.windowGeometry
  if saved then saved.x, saved.y = 0, 0 end
 end
end

function Workspace:ToggleFullscreen()
 local window = self.window
 if not self.fullscreen then
  self:SaveGeometry('window')
  self.fullscreen = true
  window:ClearAllPoints()
  window:SetPoint('TOPLEFT', UIParent, 'TOPLEFT', 0, 0)
  window:SetPoint('BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', 0, 0)
 else
  self.fullscreen = nil
  self:RestoreGeometry('window')
 end
 self:Layout()
end

function Workspace:Show(recover)
 if addon.Diagnostics then addon.Diagnostics:ResetPreview() end
 self:Initialize()
 if addon.APIHelp then addon.APIHelp:Load() end
 if self.minibar then self.minibar:Hide() end
 self.minimized = nil
 if self.window then self.window:Show(); if recover ~= false then self:RecoverWindow() end; return end
 self:Build()
 if recover ~= false then self:RecoverWindow() end
 local id = self.db.selected
 if not id or not (self.db.drafts[id] or self.db.snippets[id]) then id = next(self.db.drafts) or next(self.db.snippets) end
 self:Select(id)
 self:Layout()
end

function Workspace:Build()
 local window = CreateFrame('Frame', 'LuaWorkbenchWindow', UIParent)
 self.window = window
 self:RestoreGeometry('window')
 window:SetFrameStrata('DIALOG')
 window:SetClampedToScreen(self.db.options.windowClamp ~= false)
 window:SetMovable(true)
 window:SetResizable(true)
 window:EnableMouse(true)
 UI:KeyboardPropagation(window, true, true)
 window:SetScript('OnKeyDown', function(_, key)
  if UI:InCombat() then UI:KeyboardPropagation(window, true); return end
  UI:KeyboardPropagation(window, not self:RunShortcut(key))
 end)
 window:SetScript('OnKeyUp', function(_, key)
  if key == 'F5' then self.f5Held = nil end
  if addon.DebugUI then addon.DebugUI.held = nil end
  if addon.Navigation then addon.Navigation.held = nil end
  UI:KeyboardPropagation(window, true)
 end)
 if window.SetResizeBounds then window:SetResizeBounds(820, 500) else window:SetMinResize(820, 500) end
 UI:Background(window)
 window:SetScript('OnSizeChanged', function() if self.output then self:Layout() end end)
 window:SetScript('OnHide', function()
  self.f5Held = nil
  if addon.DebugUI then addon.DebugUI.held = nil end
  if addon.Navigation then addon.Navigation.held = nil end
  UI:KeyboardPropagation(window, true)
  self:EndRename(false)
  if self.contextMenu then self.contextMenu:Hide() end
  if addon.Automation.panel then addon.Automation.panel:Hide() end
  for _, panel in ipairs({ addon.KnowledgeBase and addon.KnowledgeBase.panel or false, self.optionsFrame or false, self.helpFrame or false, self.syntaxFrame or false, addon.Diagnostics.panel or false, addon.Snippets and addon.Snippets.panel or false, addon.Navigation and addon.Navigation.snapshot or false }) do
   if panel then panel:Hide() end
  end
  self:Capture(); GameTooltip:Hide()
  window:StopMovingOrSizing()
  self:SaveGeometry('window')
  if self.divider then self.divider:SetScript('OnUpdate', nil) end
 end)
 _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchWindow'
 local titlebar = CreateFrame('Frame', nil, window)
 titlebar:SetPoint('TOPLEFT'); titlebar:SetPoint('TOPRIGHT'); titlebar:SetHeight(34)
 titlebar:EnableMouse(true)
 titlebar:RegisterForDrag('LeftButton')
 titlebar:SetScript('OnDragStart', function() if not self.fullscreen then window:StartMoving() end end)
 titlebar:SetScript('OnDragStop', function() window:StopMovingOrSizing(); self:SaveGeometry('window') end)
 UI:Background(titlebar, { 0.11, 0.12, 0.15, 1 })
 local title = UI:Text(titlebar, 'LuaWorkbench', 12); title:SetPoint('LEFT', 14, 0)
 local close = UI:Button(titlebar, 'close', _G.CLOSE, function() window:Hide() end)
 close:SetPoint('RIGHT', -5, 0)
 local full = UI:Button(titlebar, 'expand', L.fullscreen, function() self:ToggleFullscreen() end)
 full:SetPoint('RIGHT', close, 'LEFT', -3, 0)
 local minimize = UI:Button(titlebar, 'minimize', L.minimize, function() self:Minimize() end)
 minimize:SetPoint('RIGHT', full, 'LEFT', -3, 0)
 local minimap = UI:Button(titlebar, 'options', L.options, function() self:ShowOptions() end)
 minimap:SetPoint('RIGHT', minimize, 'LEFT', -3, 0)
 local help = UI:Button(titlebar, '?', L.help, function() self:ShowHelp() end)
 help:SetPoint('RIGHT', minimap, 'LEFT', -3, 0)
 self.helpButton = help
 addon.Diagnostics:BuildDeveloperButtons(titlebar, addon.Diagnostics:BuildButton(titlebar, help))
 local function field(parent, width)
  local frame = CreateFrame('EditBox', nil, parent)
  frame:SetSize(width, 26)
  frame:SetAutoFocus(false)
  frame:SetFontObject(GameFontHighlightSmall)
  frame:SetTextInsets(8, 8, 0, 0)
  UI:Background(frame, { 0.12, 0.14, 0.18, 1 })
  frame:SetScript('OnEscapePressed', function() frame:ClearFocus() end)
  frame:SetScript('OnKeyDown', function(_, key) self:Shortcut(key) end)
  frame:SetScript('OnKeyUp', function(_, key) if key == 'F5' then self.f5Held = nil end end)
  return frame
 end
 local sidebar = CreateFrame('Frame', nil, window)
 self.sidebar = sidebar
 sidebar:SetPoint('TOPLEFT', 8, -42); sidebar:SetPoint('BOTTOMLEFT', 8, 32); sidebar:SetWidth(222)
 UI:Background(sidebar)
 local snippetLabel = UI:Text(sidebar, L.snippets, 12); snippetLabel:SetPoint('TOPLEFT', 10, -10); snippetLabel:SetWidth(76); snippetLabel:SetWordWrap(false)
 local folder = UI:Button(sidebar, 'folder', L.newFolder, function() self:NewFolder() end); folder:SetPoint('TOPRIGHT', -99, -2)
 local new = UI:Button(sidebar, 'new', L.newSnippet, function() self:New() end); new:SetPoint('TOPRIGHT', -67, -2)
 local save = UI:Button(sidebar, 'saveAll', L.saveAll, function() self:SaveAll() end)
 self.saveAllButton = save
 save:SetPoint('TOPRIGHT', -35, -2)
 local delete = UI:Button(sidebar, 'clear', L.delete, function() StaticPopup_Show('LUAWORKBENCH_DELETE', nil, nil, self.current) end)
 delete:SetPoint('TOPRIGHT', -3, -2)
 self.snippetSearch = field(sidebar, 200); self.snippetSearch:SetPoint('TOPLEFT', 10, -34)
 self.snippetSearch:SetText('')
 UI:Tooltip(self.snippetSearch, L.searchSnippets .. addon.ShortcutText('  (Ctrl+Shift+F)'))
 self.snippetSearch:SetScript('OnTextChanged', function() self:RefreshTree() end)
 UI:SearchClear(self.snippetSearch)
 self.snippetSearch:SetScript('OnEnterPressed', function()
  if self.rows and self.rows[1] then
   if self.rows[1].folder then return end
   self:Select(self.rows[1].id)
   self:OpenFind(self.snippetSearch:GetText())
  end
 end)
 local hint = UI:Text(sidebar, L.searchSnippets, 10); hint:SetPoint('TOPLEFT', 10, -64); hint:SetWidth(202)
 local scroll = UI:Scroll(sidebar)
 scroll:SetPoint('TOPLEFT', 4, -91)
 self.snippetScroll = scroll; scroll:SetPoint('BOTTOMRIGHT', -15, 5)
 local library = UI:Action(sidebar, 'fragment', L.textSnippets, L.textSnippets, function() addon.Snippets:ShowLibrary() end)
 library:SetPoint('BOTTOMLEFT', 10, 40)
 local knowledge = UI:Action(sidebar, 'search', L.knowledgeBase, L.knowledgeBase, function() addon.KnowledgeBase:Show() end)
 knowledge:SetPoint('BOTTOMLEFT', 10, 8)
 scroll:SetPoint('BOTTOMRIGHT', -15, 76)
 self.list = CreateFrame('Frame', nil, scroll); self.list:SetSize(200, 1); scroll:SetScrollChild(self.list)
 scroll:SetScript('OnSizeChanged', function(_, width) self.list:SetWidth(width) end)
 self.noResults = UI:Text(sidebar, L.noResults, 11); self.noResults:SetPoint('TOPLEFT', 10, -100); self.noResults:Hide()
 Console.input = UI:Editor(window, L.queryLuaCode)
 local input = Console.input
 input.changed = function(text)
  local sourceChanged = Console.source ~= text
  Console.source, Console.lastError = text, nil
  if sourceChanged and addon.DebugUI then addon.DebugUI:SourceChanged(text) end
  self:Capture()
  Console:UpdateLineNumbers()
  if not self.searchPending then
   self.searchPending = true
   C_Timer.After(0.12, function()
    self.searchPending = nil
    self:RefreshTree()
    if self.findBar:IsShown() then self:Find(0, false) end
   end)
  end
 end
 input.editBox:SetScript('OnKeyDown', function(_, key) self:Shortcut(key) end)
 input.editBox:SetScript('OnKeyUp', function(_, key) if addon.DebugUI then addon.DebugUI:KeyUp(key) end; if key == 'F5' then self.f5Held = nil end; if addon.Navigation then addon.Navigation.held = nil end end)
 Console:AttachLineNumbers(input)
 addon.Query.Editor:Attach(input)
 self.output = UI:Editor(window, L.queryLuaOutput, true)
 self.output.editBox:SetScript('OnKeyDown', function(_, key) self:RunShortcut(key) end)
 self.output.editBox:SetScript('OnKeyUp', function(_, key) if key == 'F5' then self.f5Held = nil end end)
 Console.output = self.output
 self.output.scrollFrame:HookScript('OnScrollRangeChanged', function(outputScroll)
  if Console:AutoScrollEnabled() then outputScroll:SetVerticalScroll(outputScroll:GetVerticalScrollRange()) end
 end)
 self:ApplyOptions()
 Console:Refresh()
 local copy = UI:Action(self.output.frame, 'copy', L.copyOutputAction, L.copyOutputHint, function() self.output:SetFocus(); self.output:HighlightText() end)
 copy:SetPoint('TOPRIGHT', -40, -2)
 self.outputCopy = copy
 self.outputAutoScroll = UI:Check(self.output.frame, L.outputAutoScroll, function(button)
  Console:SetAutoScroll(button:GetChecked() == true)
 end)
 self.outputAutoScroll:SetWidth(self.outputAutoScroll.label:GetStringWidth() + 32)
 self.outputAutoScroll:SetPoint('RIGHT', copy, 'LEFT', -12, 0)
 self.outputAutoScroll:SetChecked(Console:AutoScrollEnabled())
 UI:Tooltip(self.outputAutoScroll, L.outputAutoScrollHelp)
 local clear = UI:Action(self.output.frame, 'clear', L.clearOutputAction, L.queryLuaClear, function() Console:Clear(true) end)
 clear:SetPoint('TOPLEFT', self.output.label, 'TOPRIGHT', 14, 8)
 self.outputClear = clear
 self.output.label:ClearAllPoints(); self.output.label:SetPoint('TOPLEFT', 12, -10)
 self.output.label:SetWidth(110); self.output.label:SetWordWrap(false)
 self.clearOnRunHint = UI:Text(self.output.frame, L.clearOnRun, 11)
 self.clearOnRunHint:SetPoint('TOPLEFT', 12, -32); self.clearOnRunHint:SetPoint('TOPRIGHT', -16, -32)
 self.clearOnRunHint:SetHeight(14); self.clearOnRunHint:SetWordWrap(false)
 self.clearOnRunHint:SetTextColor(0.95, 0.75, 0.42); self.clearOnRunHint:Hide()
 self.output.frame:HookScript('OnSizeChanged', function() self:UpdateClearOnRunIndicator() end)
 self.undoOutput = UI:Action(self.output.frame, 'previous', L.undo, L.undoClearOutput, function() Console:UndoClear() end)
 self.undoOutput:SetPoint('BOTTOMLEFT', 12, 8)
 self.undoOutput:SetFrameLevel(self.output.frame:GetFrameLevel() + 12)
 UI:Background(self.undoOutput, UI.colors.hover)
 self.undoOutput:Hide()
 local maximize = UI:Button(input.frame, 'expand', L.maximizeCode, function() self.codeOnly = not self.codeOnly; self:Layout() end)
 maximize:SetPoint('TOPRIGHT', -6, -2)
 local search = UI:Button(input.frame, 'search', L.findCode .. addon.ShortcutText('  (Ctrl+F)'), function() self:OpenFind() end)
 search:SetPoint('RIGHT', maximize, 'LEFT', -2, 0)
 local format = UI:Button(input.frame, '{}', L.queryLuaFormat .. addon.ShortcutText(' (Shift+Alt+F)'), function() addon.Query.Editor:FormatInput(input) end)
 format:SetPoint('RIGHT', search, 'LEFT', -2, 0)
 local play = UI:Button(input.frame, 'play', L.queryLuaRun .. addon.ShortcutText('  (Ctrl+Enter)'), function() self:Run() end, { 0.4, 0.88, 0.58, 1 })
 play:SetPoint('RIGHT', format, 'LEFT', -2, 0)
 self.runButton = play
 input.label:SetPoint('TOPRIGHT', input.frame, 'TOP', -10, -34)
 input.label:SetWordWrap(false)
 addon.Automation:BuildControls(input.frame)
 local findBar = CreateFrame('Frame', nil, input.frame)
 self.findBar = findBar
 findBar:SetSize(480, 32)
 findBar:SetFrameLevel(input.frame:GetFrameLevel() + 10)
 UI:Background(findBar, { 0.13, 0.15, 0.19, 1 })
 self.findText = field(findBar, 205); self.findText:SetPoint('LEFT', 4, 0); self.findText:SetText('')
 UI:Tooltip(self.findText, L.findCode)
 self.findText:SetScript('OnTextChanged', function() self:Find(0, true) end)
 UI:SearchClear(self.findText)
 self.findText:SetScript('OnEnterPressed', function() self:Find(IsShiftKeyDown() and -1 or 1) end)
 self.findText:SetScript('OnEscapePressed', function() findBar:Hide(); self.findText:ClearFocus(); self:Layout(); input:SetFocus() end)
 local case = UI:Button(findBar, 'Aa', L.matchCase, function() self.matchCase = not self.matchCase; self:UpdateFindOptions(); self:Find(0, true) end, nil, true)
 case:SetPoint('LEFT', 212, 0); self.caseButton = case
 local word = UI:Button(findBar, 'ab', L.wholeWord, function() self.wholeWord = not self.wholeWord; self:UpdateFindOptions(); self:Find(0, true) end, nil, true)
 word:SetPoint('LEFT', 242, 0); self.wordButton = word
 self.findCount = UI:Text(findBar, '', 10); self.findCount:SetPoint('LEFT', 280, 0); self.findCount:SetWidth(95)
 local previous = UI:Button(findBar, 'previous', L.previousMatch, function() self:Find(-1) end); previous:SetPoint('RIGHT', -64, 0)
 local nextMatch = UI:Button(findBar, 'next', L.nextMatch, function() self:Find(1) end); nextMatch:SetPoint('RIGHT', -34, 0)
 local hide = UI:Button(findBar, 'close', _G.CLOSE, function() findBar:Hide(); self.findText:ClearFocus(); self:Layout() end)
 hide:SetPoint('RIGHT', -2, 0)
 findBar:Hide()
 local divider = CreateFrame('Button', nil, window)
 self.divider = divider
 UI:Background(divider, { 0.15, 0.18, 0.23, 1 })
 UI:Tooltip(divider, L.resizePanes)
 divider:SetScript('OnMouseDown', function(_, mouse)
  if mouse ~= 'LeftButton' then return end
  divider:SetScript('OnUpdate', function()
   local _, y = GetCursorPosition()
   local top = input.frame:GetTop()
   local available = math.max(1, window:GetHeight() - 74)
   self.db.split = math.max(0.2, math.min(0.85, (top - y / window:GetEffectiveScale()) / available))
   self:Layout()
  end)
 end)
 divider:SetScript('OnMouseUp', function() divider:SetScript('OnUpdate', nil) end)
 self.status = UI:Text(window, '', 11)
 self.status:SetPoint('BOTTOMLEFT', 14, 11); self.status:SetPoint('BOTTOMRIGHT', -30, 11); self.status:SetHeight(14); self.status:SetWordWrap(false)
 self.dirtyDot = UI:Dot(input.frame, 7); self.dirtyDot:SetPoint('TOPLEFT', 38, -13); self.dirtyDot:Hide()
 local resize = CreateFrame('Button', nil, window)
 resize:SetSize(20, 20); resize:SetPoint('BOTTOMRIGHT')
 local grip = UI:Text(resize, '//', 13); grip:SetPoint('CENTER')
 resize:SetScript('OnMouseDown', function(_, mouse) if mouse == 'LeftButton' and not self.fullscreen then window:StartSizing('BOTTOMRIGHT') end end)
 resize:SetScript('OnMouseUp', function() window:StopMovingOrSizing(); self:SaveGeometry('window') end)
 if addon.DebugUI then addon.DebugUI:Build(play) end
end

function Workspace:UpdateFindOptions()
 for _, option in ipairs({ { self.caseButton, self.matchCase }, { self.wordButton, self.wholeWord } }) do
  if not option[1].active then option[1].active = UI:Background(option[1], UI.colors.accent) end
  option[1].active:SetShown(option[2] == true)
 end
end

StaticPopupDialogs.LUAWORKBENCH_DELETE = {
 text = L.confirmDelete, button1 = _G.DELETE, button2 = _G.CANCEL,
 OnAccept = function(_, id) Workspace:Delete(id) end,
 timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
SLASH_LUAWORKBENCH1 = '/luaworkbench'
SLASH_LUAWORKBENCH2 = '/luaeditor'
SLASH_LUAWORKBENCH3 = '/lua'
SLASH_LUAWORKBENCH4 = '/le'
SlashCmdList.LUAWORKBENCH = function(message)
 if message and message:lower():match('^%s*minimap%s*$') then Workspace:ToggleMinimap() else Workspace:Show() end
end

function Workspace:Minimize()
 if not self.minibar then
  local bar = CreateFrame('Frame', nil, UIParent)
  self.minibar = bar
  bar:SetSize(208, 32)
  self:RestoreGeometry('minibar')
  bar:SetFrameStrata('DIALOG')
  bar:SetMovable(true)
  bar:SetClampedToScreen(self.db.options.windowClamp ~= false)
  bar:EnableMouse(true)
  bar:RegisterForDrag('LeftButton')
  bar:SetScript('OnDragStart', function() bar:StartMoving() end)
  bar:SetScript('OnDragStop', function() bar:StopMovingOrSizing(); self:SaveGeometry('minibar') end)
  bar:SetScript('OnHide', function() bar:StopMovingOrSizing(); self:SaveGeometry('minibar'); addon.Diagnostics:ResetPreview() end)
  UI:Background(bar, { 0.1, 0.16, 0.23, 1 })
  local text = UI:Text(bar, 'LuaWorkbench', 11); text:SetPoint('LEFT', 10, 0)
  local restore = UI:Button(bar, 'expand', L.restore, function() self:Show() end)
  restore:SetPoint('RIGHT', -32, 0)
  local errors = UI:Button(bar, '!', L.sessionErrors, function() addon.Diagnostics:ShowErrors() end)
  errors:SetPoint('RIGHT', restore, 'LEFT', -2, 0)
  addon.Diagnostics.miniBadge = UI:Text(errors, '', 9); addon.Diagnostics.miniBadge:SetPoint('BOTTOMRIGHT', 2, 0)
  addon.Diagnostics:UpdateBadge()
  local close = UI:Button(bar, 'close', _G.CLOSE, function()
   bar:Hide(); self.minimized = nil
  end)
  close:SetPoint('RIGHT', -2, 0)
 end
 self.minimized = true
 self.window:Hide()
 self.minibar:Show()
 if addon.DebugUI then addon.DebugUI:UpdateMinibar() end
end

function Workspace:UpdateMinimap()
 local icons = LibStub('LibDBIcon-1.0')
 if not icons:IsRegistered('LuaWorkbench') then
  self.broker = LibStub('LibDataBroker-1.1'):NewDataObject('LuaWorkbench', {
   type = 'launcher',
   label = 'LuaWorkbench',
   icon = 'Interface\\AddOns\\!!!LuaWorkbench\\Assets\\Icon.tga',
   OnClick = function() self:Show() end,
   OnTooltipShow = function(tooltip)
    tooltip:AddLine('LuaWorkbench', 0.85, 0.9, 1)
    tooltip:AddLine(L.minimapHint, 1, 1, 1, true)
   end,
  })
  icons:Register('LuaWorkbench', self.broker, self.db.minimap)
 end
 if self.db.minimap.hide then icons:Hide('LuaWorkbench') else icons:Show('LuaWorkbench') end
end

function Workspace:ToggleMinimap()
 self:Initialize()
 self.db.minimap.hide = not self.db.minimap.hide
 self:UpdateMinimap()
end

function Workspace:AnchorRename()
 if not self.renameID then return end
 for index, row in ipairs(self.rows) do
  if row.id == self.renameID then
   self.renameInput:ClearAllPoints()
   self.renameInput:SetPoint('TOPLEFT', self.list, 'TOPLEFT', row.folder and 34 or (row.indent and 40 or 5), -row.offset - 2)
   self.renameInput:SetPoint('TOPRIGHT', self.list, 'TOPRIGHT', -5, -row.offset - 2)
   return index
  end
 end
 self:EndRename(false)
end

function Workspace:BeginRename(id)
 if not self.db.folders[id] and self.current ~= id then self:Select(id) end
 self:EndRename(false)
 self.codeOnly = false
 self:Layout()
 if not self.renameInput then
  local input = CreateFrame('EditBox', nil, self.list)
  self.renameInput = input
  input:SetHeight(23)
  input:SetFrameLevel(self.list:GetFrameLevel() + 5)
  input:SetAutoFocus(false)
  input:SetFontObject(GameFontHighlightSmall)
  input:SetTextInsets(5, 5, 0, 0)
  UI:Background(input, { 0.12, 0.24, 0.38, 1 })
  input:SetScript('OnEnterPressed', function() self:EndRename(true) end)
  input:SetScript('OnEscapePressed', function() self:EndRename(false) end)
  input:SetScript('OnEditFocusLost', function() self:EndRename(false) end)
  input:SetScript('OnKeyDown', function(_, key) self:RunShortcut(key) end)
  input:SetScript('OnKeyUp', function(_, key) if key == 'F5' then self.f5Held = nil end end)
 end
 self.renameID = id
 local snippet = self.db.folders[id] or self.db.drafts[id] or self.db.snippets[id]
 self.renameInput:SetText(snippet.name)
 local index = self:AnchorRename()
 if not index then return end
 self.snippetScroll:SetVerticalScroll(math.max(0, math.min(self.snippetScroll:GetVerticalScrollRange(), self.rows[index].offset)))
 self.renameInput:Show()
 self.renameInput:SetFocus()
 self.renameInput:HighlightText()
end

function Workspace:EndRename(commit)
 local id = self.renameID
 if not id then return end
 local name = self.renameInput:GetText():match('^%s*(.-)%s*$')
 if commit and name == '' then self.renameInput:SetFocus(); return end
 self.renameID = nil
 self.renameInput:ClearFocus()
 self.renameInput:Hide()
 if commit then
  self:Capture()
  if self.db.folders[id] then self.db.folders[id].name = name end
  if self.db.drafts[id] then self.db.drafts[id].name = name end
  if self.db.snippets[id] then self.db.snippets[id].name = name end
  if self.current == id then self.currentName = name; self:Capture() end
  self:RefreshTree()
 end
end
