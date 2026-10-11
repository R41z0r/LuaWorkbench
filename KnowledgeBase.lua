local _, addon = ...
local K = {}
addon.KnowledgeBase = K
local UI, L, A = addon.UI, addon.L, addon.APIHelp

function K:BuildIndex()
 if self.entries then self:ScheduleIndex(); return end
 if not A.ready then return end
 local catalog, names = A.catalog or A.index, {}
 for name in pairs(catalog) do names[#names + 1] = name end
 table.sort(names)
 self.entries = {}
 for _, name in ipairs(names) do
  local entry = catalog[name]
  self.entries[#self.entries + 1] = { name = name, kind = entry.kind or 'apiFunctions', lower = name:lower() }
 end
 if self.panel then
  self.indexing, self.nextIndex = true, 1
  self:ScheduleIndex()
 else
  for _, entry in ipairs(self.entries) do entry.body = A:SearchText(entry.name) end
 end
end

function K:IndexStatus()
 if self.indexing and self.panel then
  self.panel.status:SetText(string.format(L.apiIndexing, self.nextIndex - 1, #self.entries))
 end
end

function K:ScheduleIndex()
 if not self.indexing or self.indexTimer or not self.panel or not self.panel:IsShown() then return end
 local entries = self.entries
 self.indexTimer = entries
 C_Timer.After(0, function()
  if self.indexTimer ~= entries then return end
  self.indexTimer = nil
  if self.entries ~= entries or not self.panel:IsShown() then return end
  local clock = _G.debugprofilestop
  local started = clock and clock()
  -- Yield between batches; also bound work on clients without a profiling clock.
  for _ = 1, 100 do
   local entry = entries[self.nextIndex]
   if not entry then break end
   entry.body = A:SearchText(entry.name)
   self.nextIndex = self.nextIndex + 1
   if started and clock() - started >= 2 then break end
  end
  if self.nextIndex > #entries then
   self.indexing = nil
   -- A pending user query owns the next refresh. Otherwise retain navigation.
   if not self.panel.delay then self:Search(true) end
  else
   self:IndexStatus(); self:ScheduleIndex()
  end
 end)
end

function K:Find(query)
 self:BuildIndex()
 query = query:lower():match('^%s*(.-)%s*$')
 local compact, words = query:gsub('%s+', ''), {}
 for word in query:gmatch('%S+') do words[#words + 1] = word end
 -- Entries are already alphabetic. Stable score buckets avoid sorting and
 -- allocating a new result record for every match on every keystroke.
 local buckets = { {}, {}, {}, {} }
 for _, entry in ipairs(self.entries or {}) do
  if not self.category or entry.kind == self.category then
   local nameMatch = entry.lower:find(compact, 1, true)
   local found = true
   if not nameMatch then
    found = not self.indexing and entry.body ~= nil
    if found then
     for _, word in ipairs(words) do if not entry.body:find(word, 1, true) then found = false; break end end
    end
   end
   if found then
    local rank = entry.lower == compact and 1 or (nameMatch == 1 and 2 or (nameMatch and 3 or 4))
    local bucket = buckets[rank]; bucket[#bucket + 1] = entry
   end
  end
 end
 local matches = {}
 for _, bucket in ipairs(buckets) do
  for _, entry in ipairs(bucket) do matches[#matches + 1] = entry end
 end
 return matches
end

function K:Select(name, navigating)
 local panel = self.panel
 if not navigating then self.history = {} end
 if addon.DebugUI then addon.DebugUI:HideTooltip(panel.detailContent, 'knowledge-selection') end
 panel.selected = name
 panel.detail:SetText(A:FullDescription(name, true, true) or '')
 if panel.back then panel.back:SetShown(self.history and #self.history > 0 or false) end
 self:LayoutDetail()
 panel.detailScroll:SetVerticalScroll(0); panel.detailScroll.bar:SetValue(0)
 for _, row in ipairs(panel.rows) do
  row.selected:SetShown(row.name == name)
 end
end

function K:Follow(link)
 local name = type(link) == 'string' and link:match('^lwapi:(.+)$')
 if not name or not A.catalog[name] or name == self.panel.selected then return end
 self.history = self.history or {}
 self.history[#self.history + 1] = { name = self.panel.selected, scroll = self.panel.detailScroll:GetVerticalScroll() }
 self:Select(name, true)
end

function K:Back()
 local previous = self.history and table.remove(self.history)
 if not previous then return end
 self:Select(previous.name, true)
 self.panel.detailScroll:SetVerticalScroll(previous.scroll); self.panel.detailScroll.bar:SetValue(previous.scroll)
end

function K:Categories(owner)
 local items = {}
 local categories = { 'apiFunctions', 'apiSystems', 'apiStructures', 'apiEnums', 'apiEvents', 'apiCallbacks', 'apiConstants', 'apiOther' }
 table.sort(categories, function(a, b) return L[a]:lower() < L[b]:lower() end)
 table.insert(categories, 1, 'apiAll')
 for _, key in ipairs(categories) do
  local category = key
  items[#items + 1] = { text = L[key], selected = (self.category or 'apiAll') == key, action = function()
   self.category = category ~= 'apiAll' and category or nil
   self.panel.category.text:SetText(L[category]); self:Search()
  end }
 end
 addon.Workspace:OpenMenu(owner, items)
 self.menuOpen = true
end

function K:LayoutDetail()
 local panel = self.panel
 panel.detailContent:SetWidth(math.max(1, panel.detailScroll:GetWidth()))
 panel.detail:SetJustifyV('TOP')
 panel.detail:SetHeight(0)
 panel.detail:SetWidth(math.max(1, panel.detailScroll:GetWidth() - 12))
 local height = math.max(1, panel.detail:GetStringHeight())
 panel.detail:SetHeight(height)
 panel.detailContent:SetHeight(height + 12)
 panel.detailScroll:UpdateScrollChildRect()
end

function K:Search(preserve)
 local panel = self.panel
 if not panel then return end
 panel.delay = nil
 if not preserve then self.history = {}; if panel.back then panel.back:Hide() end end
 local listOffset = preserve and panel.list:GetVerticalScroll() or 0
 local matches = self:Find(panel.search:GetText())
 local shown = math.min(#matches, 100)
 panel.status:SetText(not A.ready and (A.pending and L.apiPending or L.apiUnavailable) or string.format(L.apiResults, #matches, shown))
 for index = 1, shown do
  local row = panel.rows[index]
  if not row then
   row = CreateFrame('Button', nil, panel.content)
   row:SetHeight(26); row:SetPoint('LEFT'); row:SetPoint('RIGHT')
   row.selected = UI:Background(row, { 0.12, 0.24, 0.38, 1 })
   local hover = row:CreateTexture(nil, 'HIGHLIGHT'); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.07)
   row.text = UI:Text(row, '', 11); row.text:SetPoint('LEFT', 6, 0); row.text:SetPoint('RIGHT', -6, 0); row.text:SetWordWrap(false)
   row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
   row:SetScript('OnClick', function(_, button)
    self:Select(row.name)
    if button == 'RightButton' then self:CopyMenu(row, row.name) end
   end)
   panel.rows[index] = row
  end
  row.name = matches[index].name
  row:ClearAllPoints(); row:SetPoint('TOPLEFT', 0, -(index - 1) * 28); row:SetPoint('RIGHT')
  row.text:SetText(row.name); row.selected:SetShown(row.name == panel.selected); row:Show()
 end
 for index = shown + 1, #panel.rows do panel.rows[index]:Hide() end
 panel.content:SetHeight(math.max(1, shown * 28)); panel.list:SetVerticalScroll(listOffset); panel.list.bar:SetValue(listOffset)
 panel.list:UpdateScrollChildRect()
 self:IndexStatus()
 if preserve and panel.selected then return end
 if shown > 0 then self:Select(matches[1].name)
 else panel.selected = nil; panel.detail:SetText(A.ready and L.noResults or panel.status:GetText()); self:LayoutDetail() end
end

function K:Show(name)
 if addon.DebugUI then addon.DebugUI:HideTooltip(nil, 'knowledge-base') end
 addon.Workspace:HidePanels(self.panel)
 A:Load(true)
 if not self.panel then self:Create() end
 if name then self.category = nil; self.panel.category.text:SetText(L.apiAll); self.panel.search:SetText(name) end
 self.panel:Show(); self:Search()
 if name then self:Select(name) end
 if addon.Query.Console.input then addon.Query.Console.input:ClearFocus() end
 self.panel.search:SetFocus()
end

function K:PositionDefault()
 local panel, W = self.panel, addon.Workspace
 if W.db.panelPositions and W.db.panelPositions.knowledgeBase then return end
 local parentScale = UIParent:GetEffectiveScale()
 local panelRatio = panel:GetEffectiveScale() / parentScale
 local windowRatio = W.window:GetEffectiveScale() / parentScale
 local right, top = W.window:GetRight(), W.window:GetTop()
 local width, height = panel:GetWidth() * panelRatio, panel:GetHeight() * panelRatio
 panel:ClearAllPoints()
 if right and top and right * windowRatio + 12 >= 12
  and right * windowRatio + 12 + width <= UIParent:GetWidth() - 12 then
  local desiredTop = math.max(height + 12, math.min(UIParent:GetHeight() - 12, top * windowRatio))
  panel:SetPoint('TOPLEFT', W.window, 'TOPRIGHT', 12 / panelRatio, (desiredTop - top * windowRatio) / panelRatio)
 else
  panel:SetPoint('CENTER', UIParent, 'CENTER')
 end
end

function K:RestoreSize()
 local panel = self.panel
 local ratio = UIParent:GetEffectiveScale() / panel:GetEffectiveScale()
 local maxWidth = math.max(1, (UIParent:GetWidth() - 32) * ratio)
 local maxHeight = math.max(1, (UIParent:GetHeight() - 32) * ratio)
 local minWidth, minHeight = math.min(480, maxWidth), math.min(280, maxHeight)
 panel:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
 local sizes = addon.Workspace.db.panelSizes
 local saved = sizes and sizes.knowledgeBase
 panel:SetSize(math.max(minWidth, math.min(maxWidth, saved and saved.width or 680)), math.max(minHeight, math.min(maxHeight, saved and saved.height or 430)))
end

function K:StopSizing()
 local panel, db = self.panel, addon.Workspace.db
 if not panel.sizing then return end
 panel.sizing = nil; panel:StopMovingOrSizing()
 db.panelSizes = db.panelSizes or {}
 db.panelSizes.knowledgeBase = { width = panel:GetWidth(), height = panel:GetHeight() }
 local x, y = panel:GetCenter()
 if x and y then
  local ratio = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
  db.panelPositions = db.panelPositions or {}
  db.panelPositions.knowledgeBase = { x = x * ratio - UIParent:GetWidth() / 2, y = y * ratio - UIParent:GetHeight() / 2 }
 end
 panel:RestorePanelPosition()
end

function K:Create()
 local W = addon.Workspace
 local panel = CreateFrame('Frame', 'LuaWorkbenchKnowledgeBase', W.window)
 self.panel = panel
 _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchKnowledgeBase'
 local ratio = UIParent:GetEffectiveScale() / panel:GetEffectiveScale()
 panel:SetSize(math.min(680, (UIParent:GetWidth() - 30) * ratio), math.min(430, (UIParent:GetHeight() - 40) * ratio))
 panel:SetPoint('CENTER'); panel:SetFrameLevel(W.window:GetFrameLevel() + 50); panel:EnableMouse(true)
 UI:MovablePanel(panel, 'knowledgeBase'); panel:RestorePanelPosition()
 panel:SetResizable(true)
 panel:HookScript('OnShow', function() self:RestoreSize(); self:PositionDefault() end)
 self:RestoreSize(); self:PositionDefault()
 UI:Background(panel, UI.colors.panel); UI:Border(panel, { 0.25, 0.3, 0.38, 1 })
 local title = UI:Text(panel, L.knowledgeBase, 15); title:SetPoint('TOPLEFT', 14, -14)
 local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -6, -7)
 panel.search = CreateFrame('EditBox', nil, panel)
 panel.search:SetPoint('TOPLEFT', 14, -44); panel.search:SetPoint('TOPRIGHT', -190, -44); panel.search:SetHeight(28)
 panel.search:SetFontObject(ChatFontNormal); panel.search:SetAutoFocus(false); panel.search:SetTextInsets(7, 7, 0, 0)
 UI:Background(panel.search, UI.colors.hover); UI:Tooltip(panel.search, L.apiSearch)
 panel.search:SetScript('OnTextChanged', function() panel.delay = 0.15 end)
 UI:SearchClear(panel.search, function() self:Search() end)
 panel.search:SetScript('OnEnterPressed', function() self:Search(); panel.search:ClearFocus() end)
 panel.search:SetScript('OnEscapePressed', function() panel.search:ClearFocus(); panel:Hide() end)
 panel.category = CreateFrame('Button', nil, panel)
 panel.category:SetPoint('TOPLEFT', panel.search, 'TOPRIGHT', 8, 0); panel.category:SetPoint('TOPRIGHT', -14, -44); panel.category:SetHeight(28)
 UI:Background(panel.category, UI.colors.hover)
 panel.category.text = UI:Text(panel.category, L[self.category or 'apiAll'], 11)
 panel.category.text:SetPoint('LEFT', 7, 0); panel.category.text:SetPoint('RIGHT', -16, 0)
 panel.category.text:SetWordWrap(false)
 local arrow = UI:Text(panel.category, 'v', 10); arrow:SetPoint('RIGHT', -5, 0)
 panel.category:SetScript('OnClick', function() self:Categories(panel.category) end)
 panel.back = UI:Button(panel, 'previous', L.navigationBack, function() self:Back() end)
 panel.back:SetPoint('RIGHT', close, 'LEFT', -6, 0); panel.back:Hide()
 -- Leave both title buttons outside the mouse-enabled drag surface.
 panel.dragHandle:SetPoint('TOPRIGHT', panel.back, 'TOPLEFT', -4, 7)
 panel.status = UI:Text(panel, '', 10); panel.status:SetPoint('BOTTOMLEFT', 14, 12); panel.status:SetPoint('RIGHT', -14, 0)
 panel.list = UI:Scroll(panel); panel.list:SetPoint('TOPLEFT', 14, -85); panel.list:SetPoint('BOTTOMLEFT', 14, 35); panel.list:SetWidth(math.floor(panel:GetWidth() * 0.38))
 panel.content = CreateFrame('Frame', nil, panel.list); panel.content:SetSize(panel.list:GetWidth(), 1); panel.list:SetScrollChild(panel.content)
 panel.rows = {}
 panel.detailScroll = UI:Scroll(panel); panel.detailScroll:SetPoint('TOPLEFT', panel.list, 'TOPRIGHT', 25, 0); panel.detailScroll:SetPoint('BOTTOMRIGHT', -25, 35)
 panel.detailContent = CreateFrame('Frame', nil, panel.detailScroll); panel.detailContent:SetSize(1, 1); panel.detailScroll:SetScrollChild(panel.detailContent)
 panel.detail = UI:Text(panel.detailContent, '', 12); panel.detail:SetPoint('TOPLEFT', 6, -6); panel.detail:SetWordWrap(true)
 panel.detailContent:EnableMouse(true)
 panel.detailContent:SetHyperlinksEnabled(true)
 panel.detailContent:SetScript('OnHyperlinkClick', function(_, link, _, button)
  if button == 'LeftButton' then self:Follow(link) end
 end)
 panel.detailContent:SetScript('OnHyperlinkEnter', function(_, link)
  local name = type(link) == 'string' and link:match('^lwapi:(.+)$')
  if name and A.catalog[name] and addon.DebugUI then
   addon.DebugUI:APITooltip(panel.detailContent, A:Preview(name))
  end
 end)
 panel.detailContent:SetScript('OnHyperlinkLeave', function()
  if addon.DebugUI then addon.DebugUI:HideTooltip(panel.detailContent, 'knowledge-link-leave') end
 end)
 panel.detailContent:SetScript('OnMouseUp', function(_, button)
  if button == 'RightButton' and panel.selected then self:CopyMenu(panel.detailContent, panel.selected) end
 end)
 panel.detail:SetSpacing(4)
 panel.detailScroll:SetScript('OnSizeChanged', function() self:LayoutDetail() end)
 panel:SetScript('OnUpdate', function(_, elapsed)
  if panel.delay then panel.delay = panel.delay - elapsed; if panel.delay <= 0 then self:Search() end end
 end)
 panel:SetScript('OnHide', function() panel.search:ClearFocus(); panel.delay = nil
  if self.copyPanel then self.copyPanel:Hide() end
  if self.menuOpen and W.contextMenu then W.contextMenu:Hide(); self.menuOpen = nil end
  if addon.DebugUI then addon.DebugUI:HideTooltip(panel.detailContent, 'knowledge-hidden') end
  self:StopSizing()
 end)
 panel:SetScript('OnSizeChanged', function()
  panel.list:SetWidth(math.floor(panel:GetWidth() * 0.38))
  panel.content:SetWidth(panel.list:GetWidth())
  self:LayoutDetail()
  if self.copyPanel then self.copyPanel:SetWidth(math.min(440, panel:GetWidth() - 24)) end
 end)
 local grip = CreateFrame('Button', nil, panel)
 panel.resizeGrip = grip
 grip:SetSize(18, 18); grip:SetPoint('BOTTOMRIGHT', -2, 2)
 grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
 grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
 grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
 grip:SetScript('OnMouseDown', function(_, button)
  if button == 'LeftButton' then panel.sizing = true; panel:StartSizing('BOTTOMRIGHT') end
 end)
 grip:SetScript('OnMouseUp', function() self:StopSizing() end)
end

function K:CopyMenu(owner, name)
 if not (A.catalog and A.catalog[name] or A.index[name]) then return end
 GameTooltip:Hide()
 self.menuOpen = true
 addon.Workspace:OpenMenu(owner, { { text = L.apiCopyName, action = function() self.menuOpen = nil; self:CopyFunction(name) end } })
end

function K:CopyFunction(name)
 if not (A.catalog and A.catalog[name] or A.index[name]) then return end
 -- Addons use selectable text; the native clipboard API has restricted access.
 if not self.copyPanel then
  local panel = CreateFrame('Frame', 'LuaWorkbenchCopyFunction', self.panel)
  self.copyPanel = panel
  panel:SetSize(math.min(440, self.panel:GetWidth() - 24), 130); panel:SetPoint('CENTER')
  panel:SetFrameLevel(self.panel:GetFrameLevel() + 20); panel:EnableMouse(true); panel:SetClampedToScreen(true)
  UI:Background(panel, UI.colors.background); UI:Border(panel, { 0.25, 0.3, 0.38, 1 })
  local title = UI:Text(panel, L.apiCopyName, 14); title:SetPoint('TOPLEFT', 14, -14)
  local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -5, -5)
  local box = CreateFrame('EditBox', nil, panel); panel.box = box
  box:SetPoint('TOPLEFT', 14, -45); box:SetPoint('TOPRIGHT', -14, -45); box:SetHeight(28)
  box:SetFontObject(ChatFontNormal); box:SetAutoFocus(false); box:SetTextInsets(7, 7, 0, 0)
  UI:Background(box, UI.colors.hover)
  box:SetScript('OnEscapePressed', function() panel:Hide() end)
  box:SetScript('OnEnterPressed', function() panel:Hide() end)
  panel:SetScript('OnHide', function() box:ClearFocus() end)
  local hint = UI:Text(panel, L.copyOutputHint, 11)
  hint:SetPoint('TOPLEFT', 14, -86); hint:SetPoint('TOPRIGHT', -14, -86); hint:SetWordWrap(true)
  _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchCopyFunction'
 end
 self.panel.search:ClearFocus()
 self.copyPanel:Show(); self.copyPanel.box:SetText(name)
 self.copyPanel.box:SetFocus(); self.copyPanel.box:HighlightText()
end
