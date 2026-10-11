local _, addon = ...
local W, UI, L = addon.Workspace, addon.UI, addon.L

function W:TreeRows()
 local snippets = addon.Search:SnippetRows(self.db, self.snippetSearch:GetText())
 local query = self.snippetSearch:GetText()
 local rows, folders = {}, {}
 for id, folder in pairs(self.db.folders) do folders[#folders + 1] = { id = id, name = folder.name, folder = true, matches = {} } end
 table.sort(folders, function(a, b) if a.name == b.name then return a.id < b.id end; return a.name < b.name end)
 for _, folder in ipairs(folders) do
  local children = {}
  for _, snippet in ipairs(snippets) do
   if self.db.folderBySnippet[snippet.id] == folder.id then snippet.indent = true; children[#children + 1] = snippet end
  end
  if query == '' or #children > 0 or folder.name:lower():find(query:lower(), 1, true) then
   folder.expanded = query ~= '' or not self.db.folders[folder.id].collapsed
   folder.hasChildren = #children > 0
   rows[#rows + 1] = folder
   if folder.expanded then for _, child in ipairs(children) do rows[#rows + 1] = child end end
  end
 end
 for _, snippet in ipairs(snippets) do
  if not self.db.folders[self.db.folderBySnippet[snippet.id]] then rows[#rows + 1] = snippet end
 end
 return rows
end

function W:NewFolder()
 self:EndRename(false)
 self.db.folderSerial = (self.db.folderSerial or 0) + 1
 local id = 'folder' .. self.db.folderSerial
 self.db.folders[id] = { name = L.newFolder .. ' ' .. self.db.folderSerial }
 self.selectedFolder = id
 self.snippetSearch:SetText('')
 self:RefreshTree()
 self:BeginRename(id)
 return id
end

function W:MoveSnippet(id, folder)
 self:Capture()
 self.db.folderBySnippet[id] = folder
 if folder then self.db.folders[folder].collapsed = nil end
 self:RefreshTree()
end

function W:RemoveFolder(id)
 for snippet, folder in pairs(self.db.folderBySnippet) do if folder == id then self.db.folderBySnippet[snippet] = nil end end
 self.db.folders[id] = nil
 if self.selectedFolder == id then self.selectedFolder = nil end
 self:RefreshTree()
end

function W:OpenMenu(owner, entries)
 if not self.contextMenu then
  local menu = CreateFrame('Frame', nil, self.window)
  self.contextMenu = menu
  menu:SetFrameStrata('TOOLTIP'); menu:SetClampedToScreen(true); menu:EnableMouse(true)
  UI:Background(menu, { 0.12, 0.14, 0.18, 1 })
  menu.scroll = UI:Scroll(menu)
  menu.scroll:SetPoint('TOPLEFT', 4, -4); menu.scroll:SetPoint('BOTTOMRIGHT', -15, 4)
  menu.content = CreateFrame('Frame', nil, menu.scroll); menu.content:SetWidth(220)
  menu.scroll:SetScrollChild(menu.content)
  function menu:RefreshScrollRange()
   local range = math.max(0, self.content:GetHeight() - (self:GetHeight() - 8))
   self.scrollRange = range
   self.scroll.bar:SetMinMaxValues(0, range)
   self.scroll.bar:SetValue(math.min(range, self.scroll:GetVerticalScroll()))
   self.scroll.bar:SetShown(range > 0)
  end
  menu.scroll:SetScript('OnScrollRangeChanged', function() menu:RefreshScrollRange() end)
  menu.scroll:SetScript('OnMouseWheel', function(_, delta)
   menu.scroll.bar:SetValue(math.max(0, math.min(menu.scrollRange or 0, menu.scroll:GetVerticalScroll() - delta * 48)))
  end)
  menu.measure = UI:Text(menu, '', 12)
  menu.measure:SetWordWrap(false); menu.measure:Hide()
  menu.buttons = {}
  menu:SetScript('OnUpdate', function()
   local down = IsMouseButtonDown()
   if menu.waitForMouseRelease then
    if not down then menu.waitForMouseRelease = nil end
    return
   end
   if down and not menu:IsMouseOver() then menu:Hide() end
  end)
 end
 local menu = self.contextMenu
 menu.waitForMouseRelease = IsMouseButtonDown()
 local width, measured = 242, {}
 for index, entry in ipairs(entries) do
  menu.measure:SetText(entry.text:gsub('|', '||'))
  measured[index] = menu.measure:GetStringWidth()
  width = math.max(width, math.ceil(measured[index]) + 38)
 end
 local screenWidth = UIParent:GetWidth() * UIParent:GetEffectiveScale() / menu:GetEffectiveScale()
 width = math.min(width, math.max(80, math.min(600, screenWidth - 24)))
 menu:SetSize(width, math.min(320, #entries * 28 + 8))
 menu.content:SetWidth(width - 22)
 menu.content:SetHeight(#entries * 28)
 for index, entry in ipairs(entries) do
  local button = menu.buttons[index]
  if not button then
   button = CreateFrame('Button', nil, menu.content); button:SetSize(220, 26)
   button.text = UI:Text(button, '', 12); button.text:SetPoint('LEFT', 8, 0); button.text:SetWidth(204); button.text:SetWordWrap(false)
   button.selected = UI:Background(button, { 0.12, 0.28, 0.46, 1 })
   button.selected:Hide()
   button.marker = button:CreateTexture(nil, 'ARTWORK')
   button.marker:SetColorTexture(0.4, 0.86, 1, 1)
   button.marker:SetPoint('TOPLEFT'); button.marker:SetPoint('BOTTOMLEFT'); button.marker:SetWidth(3)
   button.marker:Hide()
   local hover = button:CreateTexture(nil, 'HIGHLIGHT'); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.08); hover:Hide()
   button:SetScript('OnEnter', function()
    hover:Show()
    if button.tooltipText then
     GameTooltip:SetOwner(button, 'ANCHOR_RIGHT'); GameTooltip:ClearLines()
     GameTooltip:AddLine(button.tooltipText, 0.85, 0.9, 1, true); GameTooltip:Show()
    end
   end)
   local function leave()
    hover:Hide()
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
   end
   button:SetScript('OnLeave', leave); button:SetScript('OnHide', leave)
   button:SetScript('OnClick', function() menu:Hide(); button.action() end)
   menu.buttons[index] = button
  end
  button:SetWidth(width - 22); button.text:SetWidth(width - 38)
  button.tooltipText = measured[index] > width - 38 and entry.text:gsub('|', '||') or nil
  button.action = entry.action
  button.selected:SetShown(entry.selected == true)
  button.marker:SetShown(entry.selected == true)
  button.text:SetTextColor(entry.selected and 0.9 or 0.78, entry.selected and 0.95 or 0.82, entry.selected and 1 or 0.9)
  button.text:SetText((entry.text:gsub('|', '||')))
  button:SetPoint('TOPLEFT', 0, -(index - 1) * 28); button:Show()
 end
 for index = #entries + 1, #menu.buttons do menu.buttons[index]:Hide() end
 menu.rename = menu.buttons[1]
 menu:ClearAllPoints(); menu:SetPoint('TOPLEFT', owner, 'TOPRIGHT', 3, 0)
 menu.scroll:SetVerticalScroll(0); menu:Show()
 menu.scroll:UpdateScrollChildRect()
 menu:RefreshScrollRange()
end

function W:ShowSnippetMenu(button)
 self:EndRename(false)
 local id = button.row.id
 local entries = { { text = L.rename, action = function() self:BeginRename(id) end } }
 if button.row.folder then
  entries[#entries + 1] = { text = L.newSnippet, action = function() self.selectedFolder = id; self:New() end }
  entries[#entries + 1] = { text = L.removeFolder, action = function() self:RemoveFolder(id) end }
 else
  if self.db.snippets[id] and self:IsSnippetDirty(id) then
   entries[#entries + 1] = { text = L.revertSaved, action = function() StaticPopup_Show('LUAWORKBENCH_REVERT', nil, nil, id) end }
  end
  local destinations, folders = {}, {}
  local currentFolder = self.db.folderBySnippet[id]
  if currentFolder then destinations[#destinations + 1] = { text = L.rootFolder, action = function() self:MoveSnippet(id, nil) end } end
  for folderID, folder in pairs(self.db.folders) do
   if folderID ~= currentFolder then folders[#folders + 1] = { id = folderID, name = folder.name } end
  end
  table.sort(folders, function(a, b) return a.name < b.name end)
  for _, folder in ipairs(folders) do
   local target = folder.id
   destinations[#destinations + 1] = { text = folder.name, action = function() self:MoveSnippet(id, target) end }
  end
  if #destinations > 0 then
   entries[#entries + 1] = { text = L.moveTo, action = function() self:OpenMenu(button, destinations) end }
  end
  entries[#entries + 1] = { text = L.delete, action = function() self:Select(id); StaticPopup_Show('LUAWORKBENCH_DELETE', nil, nil, id) end }
 end
 self:OpenMenu(button, entries)
end

function W:DiscardSessionDrafts()
 for id in pairs(self.db.drafts) do
  if not self.db.snippets[id] then
   self.db.folderBySnippet[id], self.db.clearOnRun[id], self.db.autoRun[id], self.db.helperModules[id] = nil, nil, nil, nil
  end
 end
 self.db.drafts = {}
 if not self.db.snippets[self.db.selected] then self.db.selected = nil end
end

function W:RevertSaved(id)
 local saved = self.db.snippets[id]
 if not saved then return end
 self:EndRename(false)
 self.db.drafts[id] = { name = saved.name, source = saved.source }
 if self.current == id then
  -- Do not recapture the current editor over the restored snapshot in Select.
  self.current = nil
  self:Select(id)
 else
  self:RefreshTree()
 end
end

StaticPopupDialogs.LUAWORKBENCH_REVERT = {
 text = L.confirmRevert,
 button1 = _G.ACCEPT, button2 = _G.CANCEL,
 OnAccept = function(_, id) W:RevertSaved(id) end,
 timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
