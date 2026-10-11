local _, addon = ...
local S, UI, L = {}, addon.UI, addon.L
addon.Snippets = S

function S:Database()
 local db = addon.Workspace.db
 db.textSnippets = db.textSnippets or {}
 return db.textSnippets
end

function S:Save(id, name, source)
 name = tostring(name or ''):match('^%s*(.-)%s*$')
 if name == '' or not source or source == '' then return nil end
 local db = addon.Workspace.db
 if not id then
  db.textSnippetSerial = (db.textSnippetSerial or 0) + 1
  id = tostring(db.textSnippetSerial)
  while self:Database()[id] do
   db.textSnippetSerial = db.textSnippetSerial + 1
   id = tostring(db.textSnippetSerial)
  end
 end
 self:Database()[id] = { name = name, source = source }
 return id
end

function S:Delete(id) self:Database()[id] = nil end

function S:Entries(query)
 local entries = {}
 query = (query or ''):lower()
 for id, item in pairs(self:Database()) do
  if item.name:lower():find(query, 1, true) or item.source:lower():find(query, 1, true) then
   entries[#entries + 1] = { id = id, name = item.name, source = item.source }
  end
 end
 table.sort(entries, function(a, b) if a.name == b.name then return a.id < b.id end; return a.name < b.name end)
 return entries
end

function S:Capture(input)
 if not input then return nil end
 local box, source = input.editBox, input:GetText()
 local cursor = box:GetCursorPosition()
 return { input = input, source = source, start = cursor, finish = cursor, cursor = cursor, scriptId = addon.Workspace.current }
end

function S:Insert(text, target)
 target = target or self:Capture(addon.Query.Console.input)
 if target and addon.Query.Editor:IsReadOnly(target.input) then return false end
 if not target or target.scriptId ~= addon.Workspace.current or target.input:GetText() ~= target.source then
  addon.Query.Console:SetStatus(L.textSnippetTargetChanged, true)
  return false
 end
 local source = target.source:sub(1, target.start) .. text .. target.source:sub(target.finish + 1)
 addon.Query.Editor:SetSource(target.input, source, target.start + #text)
 target.input:SetFocus()
 return true
end

function S:OpenCodeMenu(input)
 if not input or input.readonly then return end
 local W, target = addon.Workspace, self:Capture(input)
 local function open(entries)
  W:OpenMenu(input.frame, entries)
  if _G.GetCursorPosition then
   local x, y = _G.GetCursorPosition()
   local scale = UIParent:GetEffectiveScale()
   W.contextMenu:ClearAllPoints(); W.contextMenu:SetPoint('TOPLEFT', UIParent, 'BOTTOMLEFT', x / scale, y / scale)
  end
 end
 local function valid()
  if target.scriptId == W.current and input:GetText() == target.source then return true end
  addon.Query.Console:SetStatus(L.textSnippetTargetChanged, true)
 end
 local entries = {
  { text = L.queryLuaFormat .. ' (Shift+Alt+F)', action = function() if valid() then addon.Query.Editor:FormatInput(input) end end },
  { text = L.textSnippetInsert, action = function()
   local items = {}
   for _, item in ipairs(self:Entries()) do
    local text = item.source
    items[#items + 1] = { text = item.name, action = function() self:Insert(text, target) end }
   end
   if #items == 0 then self:ShowLibrary(target) else open(items) end
  end },
  { text = L.helperModule, action = function()
   local items = {}
   for _, item in ipairs(addon.Helpers:Entries()) do
    local name = item.name
    items[#items + 1] = { text = name, action = function()
     self:Insert(addon.Helpers:ImportText(name, target.source, target.cursor), target)
    end }
   end
   if #items > 0 then open(items) else addon.Query.Console:SetStatus(L.helperMissing, true) end
  end },
 }
 if input == addon.Query.Console.input then
  entries[#entries + 1] = { text = L.goToDefinition .. ' (F12)', action = function() addon.Navigation:Go(target) end }
  if addon.Navigation:CanBack() then entries[#entries + 1] = { text = L.navigationBack .. ' (Alt+Left)', action = function() addon.Navigation:Back() end } end
 end
 open(entries)
end

function S:ShowLibrary(target)
 local W = addon.Workspace
 if not W.window then W:Show() end
 target = target or self:Capture(addon.Query.Console.input)
 W:HidePanels(self.panel)
 for _, key in ipairs({ 'optionsFrame', 'syntaxFrame', 'helpFrame', 'contextMenu' }) do
  if W[key] then W[key]:Hide() end
 end
 if addon.Diagnostics and addon.Diagnostics.panel then addon.Diagnostics.panel:Hide() end
 if addon.Automation and addon.Automation.panel then addon.Automation.panel:Hide() end
 if not self.panel then self:CreateLibrary() end
 local panel = self.panel
 panel.target = target
 panel.selected = nil
 panel.search:SetText('')
 panel.name:SetText('')
 panel.code:SetText('')
 panel.message:SetText('')
 panel.insert:SetShown(target ~= nil)
 panel.delete:SetShown(false)
 panel:Show()
 self:RefreshLibrary()
end

function S:RefreshLibrary()
 local panel = self.panel
 local entries = self:Entries(panel.search:GetText())
 for index, entry in ipairs(entries) do
  local button = panel.rows[index]
  if not button then
   button = CreateFrame('Button', nil, panel.content)
   button:SetHeight(30); button:SetPoint('LEFT', 0, 0); button:SetPoint('RIGHT', 0, 0)
   button.background = UI:Background(button, UI.colors.panel)
   local hover = button:CreateTexture(nil, 'HIGHLIGHT'); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.07)
   button.text = UI:Text(button, '', 12); button.text:SetPoint('LEFT', 8, 0); button.text:SetPoint('RIGHT', -8, 0); button.text:SetWordWrap(false)
   button:SetScript('OnClick', function()
    local item = self:Database()[button.id]
    if not item then return end
    panel.selected = button.id
    panel.name:SetText(item.name); panel.code:SetText(item.source); panel.message:SetText(''); panel.delete:SetShown(true)
    self:RefreshLibrary()
   end)
   panel.rows[index] = button
  end
  button.id = entry.id
  button:ClearAllPoints(); button:SetPoint('TOPLEFT', 0, -(index - 1) * 32); button:SetPoint('RIGHT', 0, 0)
  button.background:SetColorTexture(unpack(panel.selected == entry.id and { 0.12, 0.24, 0.38, 1 } or UI.colors.panel))
  button.text:SetText(entry.name:gsub('|', '||')); button:Show()
 end
 for index = #entries + 1, #panel.rows do panel.rows[index]:Hide() end
 panel.content:SetHeight(math.max(1, #entries * 32))
 panel.empty:SetShown(#entries == 0)
end

function S:CreateLibrary()
 local W = addon.Workspace
 local panel = CreateFrame('Frame', 'LuaWorkbenchTextSnippets', W.window)
 self.panel = panel
 _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchTextSnippets'
 panel:SetSize(math.min(730, W.window:GetWidth() - 24), math.min(510, W.window:GetHeight() - 30))
 panel:SetPoint('CENTER'); panel:SetFrameLevel(W.window:GetFrameLevel() + 40); panel:EnableMouse(true)
 UI:MovablePanel(panel, 'textSnippets'); panel:RestorePanelPosition()
 UI:Background(panel, { 0.09, 0.11, 0.15, 1 }); UI:Border(panel, { 0.25, 0.3, 0.38, 1 })
 local title = UI:Text(panel, L.textSnippets, 15); title:SetPoint('TOPLEFT', 16, -15)
 local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -6, -7)
 local function field(label, x, y, width)
  local text = UI:Text(panel, label, 11); text:SetPoint('TOPLEFT', x, y)
  local box = CreateFrame('EditBox', nil, panel); box:SetSize(width, 28); box:SetPoint('TOPLEFT', x, y - 18)
  box:SetFontObject(ChatFontNormal); box:SetAutoFocus(false); box:SetTextInsets(7, 7, 0, 0)
  UI:Background(box, UI.colors.hover)
  box:SetScript('OnEscapePressed', function() box:ClearFocus(); panel:Hide() end)
  return box
 end
 panel.search = field(L.textSnippetSearch, 14, -49, 205)
 panel.search:SetScript('OnTextChanged', function() self:RefreshLibrary() end)
 UI:SearchClear(panel.search)
 panel.name = field(L.textSnippetName, 234, -49, panel:GetWidth() - 248)
 panel.name:SetMaxLetters(120)
 local scroll = UI:Scroll(panel); scroll:SetPoint('TOPLEFT', 14, -102); scroll:SetPoint('BOTTOMLEFT', 14, 66); scroll:SetWidth(195)
 panel.content = CreateFrame('Frame', nil, scroll); panel.content:SetSize(195, 1); scroll:SetScrollChild(panel.content)
 panel.rows = {}
 panel.empty = UI:Text(panel.content, L.textSnippetEmpty, 11); panel.empty:SetPoint('TOPLEFT', 7, -8); panel.empty:SetWidth(180)
 panel.code = UI:Editor(panel, L.textSnippetCode)
 addon.Query.Editor:Attach(panel.code)
 W:ApplyOptions()
 panel.code.frame:SetPoint('TOPLEFT', 234, -102); panel.code.frame:SetPoint('BOTTOMRIGHT', -14, 72)
 panel.message = UI:Text(panel, '', 11); panel.message:SetPoint('BOTTOMLEFT', 234, 48); panel.message:SetPoint('RIGHT', -14, 0); panel.message:SetHeight(22)
 local new = UI:Button(panel, 'new', L.textSnippetNew, function()
  panel.selected = nil; panel.name:SetText(''); panel.code:SetText(''); panel.message:SetText(''); panel.delete:Hide(); panel.name:SetFocus(); self:RefreshLibrary()
 end); new:SetPoint('BOTTOMLEFT', 14, 16)
 panel.delete = UI:Button(panel, 'clear', L.textSnippetDelete, function()
  if not panel.selected then return end
  StaticPopup_Show('LUAWORKBENCH_DELETE_TEXT_SNIPPET', nil, nil, panel.selected)
 end); panel.delete:SetPoint('LEFT', new, 'RIGHT', 6, 0)
 local save = UI:Action(panel, 'save', L.textSnippetSave, L.textSnippetSave, function()
  local id = self:Save(panel.selected, panel.name:GetText(), panel.code:GetText())
  if not id then panel.message:SetText(L.textSnippetRequired); return end
  panel.selected = id; panel.delete:Show(); panel.message:SetText(''); self:RefreshLibrary()
 end); save:SetPoint('BOTTOMLEFT', 234, 14)
 panel.insert = UI:Action(panel, 'next', L.textSnippetInsert, L.textSnippetInsert, function()
  if panel.code:GetText() == '' then panel.message:SetText(L.textSnippetRequired); return end
  if self:Insert(panel.code:GetText(), panel.target) then panel:Hide() end
 end); panel.insert:SetPoint('BOTTOMRIGHT', -14, 14)
 panel:SetScript('OnHide', function() panel.name:ClearFocus(); panel.search:ClearFocus(); panel.code:ClearFocus() end)
 StaticPopupDialogs.LUAWORKBENCH_DELETE_TEXT_SNIPPET = {
  text = L.textSnippetDeleteConfirm, button1 = _G.DELETE, button2 = _G.CANCEL, timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(_, id)
   self:Delete(id)
   if panel.selected == id then panel.selected = nil; panel.name:SetText(''); panel.code:SetText(''); panel.delete:Hide() end
   self:RefreshLibrary()
  end,
 }
end
