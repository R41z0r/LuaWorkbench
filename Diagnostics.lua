local _, addon = ...
local W, UI, L, Console = addon.Workspace, addon.UI, addon.L, addon.Query.Console
local D = { errors = {}, previewLines = {}, previewCount = 0 }
addon.Diagnostics = D

function D:Record(message, stack, id, name, event)
 message = Console:Format(message)
 local entry
 for index, item in ipairs(self.errors) do
  if item.id == id and item.event == event and item.message == message then
   entry = table.remove(self.errors, index); break
  end
 end
 entry = entry or { id = id, name = name or L.newSnippet, event = event, message = message, count = 0 }
 entry.name = name or L.newSnippet
 entry.count = entry.count + 1
 entry.time = _G.date and _G.date('%H:%M:%S') or ''
 entry.stack = stack and Console:Format(stack) or nil
 table.insert(self.errors, 1, entry)
 if #self.errors > 100 then table.remove(self.errors) end
 self.nextOutputError = true
 self:UpdateBadge()
 if self.panel and self.panel:IsShown() and not self.refreshPending then
  self.refreshPending = true
  C_Timer.After(0.2, function()
   self.refreshPending = nil
   if self.panel:IsShown() then self:RefreshErrors() end
  end)
 end
end

function D:ClearErrors()
 self.errors, self.selected = {}, nil
 self:UpdateBadge()
 self:RefreshErrors()
end

function D:UpdateBadge()
 if self.badge then self.badge:SetText(#self.errors > 0 and tostring(#self.errors) or '') end
 if self.miniBadge then self.miniBadge:SetText(#self.errors > 0 and tostring(#self.errors) or '') end
end

function D:BuildButton(parent, anchor)
 local button = UI:Button(parent, '!', L.sessionErrors, function() self:ShowErrors() end, { 1, 0.5, 0.45, 1 })
 button:SetPoint('RIGHT', anchor, 'LEFT', -10, 0)
 self.badge = UI:Text(button, '', 9); self.badge:SetPoint('BOTTOMRIGHT', 3, 1)
 self:UpdateBadge()
 return button
end

-- Blizzard tools are loaded only when requested, and external toggles stay observable.
function D:RefreshDeveloperTools()
 if not self.developerButtons then return end
 for _, name in ipairs({ 'FrameStackTooltip', 'EventTrace' }) do
  local frame = _G[name]
  if frame and not self.developerHooks[frame] then
   self.developerHooks[frame] = true
   frame:HookScript('OnShow', function() self:RefreshDeveloperTools() end)
   frame:HookScript('OnHide', function() self:RefreshDeveloperTools() end)
  end
 end
 local getBool = _G.C_CVar and _G.C_CVar.GetCVarBool or _G.GetCVarBool
 local stack = getBool and getBool('fstack_enabled') or false
 local trace = _G.EventTrace and _G.EventTrace:IsShown() or false
 for key, active in pairs({ frameStack = stack, eventTrace = trace }) do
  local button = self.developerButtons[key]
  button.active:SetShown(active)
  UI:ButtonColor(button, active and { 0.35, 0.9, 0.5, 1 } or { 0.76, 0.81, 0.9, 1 })
 end
end

function D:ToggleDeveloperTool(kind)
 if kind == 'tableInspect' then
  local inspect = _G.SlashCmdList and _G.SlashCmdList.TABLEINSPECT
  if inspect then inspect('')
  elseif _G.UIErrorsFrame then _G.UIErrorsFrame:AddMessage(L.developerToolUnavailable, 1, 0.3, 0.3) end
  return
 end
 -- Loading Event Trace creates a visible frame; toggle from the pre-load state.
 local traceWasShown = kind == 'eventTrace' and _G.EventTrace and _G.EventTrace:IsShown() or false
 local loader = _G.C_AddOns and _G.C_AddOns.LoadAddOn or _G.LoadAddOn
 local loaded = loader and loader(kind == 'frameStack' and 'Blizzard_DebugTools' or 'Blizzard_EventTrace')
 if loaded then
  if kind == 'frameStack' and _G.FrameStackTooltip_ToggleDefaults then
   _G.FrameStackTooltip_ToggleDefaults()
  elseif kind == 'frameStack' and _G.FrameStackTooltip_Toggle then
   _G.FrameStackTooltip_Toggle()
  elseif kind == 'eventTrace' and _G.EventTrace then
   _G.EventTrace:SetShown(not traceWasShown)
  else
   loaded = false
  end
 end
 if not loaded and _G.UIErrorsFrame then _G.UIErrorsFrame:AddMessage(L.developerToolUnavailable, 1, 0.3, 0.3) end
 self:RefreshDeveloperTools()
end

function D:BuildDeveloperButtons(parent, anchor)
 self.developerButtons, self.developerHooks = {}, {}
 for _, kind in ipairs({ 'tableInspect', 'eventTrace', 'frameStack' }) do
  local button = UI:Button(parent, kind, L[kind .. 'Tool'], function() self:ToggleDeveloperTool(kind) end)
  button:SetPoint('RIGHT', anchor, 'LEFT', -3, 0)
  button.active = UI:Background(button, { 0.08, 0.25, 0.14, 1 })
  button.active:Hide()
  self.developerButtons[kind], anchor = button, button
 end
 local events = CreateFrame('Frame')
 events:RegisterEvent('CVAR_UPDATE')
 events:RegisterEvent('ADDON_LOADED')
 events:SetScript('OnEvent', function(_, event, name)
  if (event == 'CVAR_UPDATE' and name == 'fstack_enabled') or
   (event == 'ADDON_LOADED' and (name == 'Blizzard_DebugTools' or name == 'Blizzard_EventTrace')) then
   self:RefreshDeveloperTools()
  end
 end)
 parent:HookScript('OnShow', function() self:RefreshDeveloperTools() end)
 self:RefreshDeveloperTools()
end

function D:RefreshErrors()
 if not self.panel then return end
 local previous = self.displayedEntry
 local found = false
 for _, entry in ipairs(self.errors) do if entry == self.selected then found = true; break end end
 if not found then self.selected = self.errors[1] end
 local offset = self.detail.scrollFrame:GetVerticalScroll()
 for index, entry in ipairs(self.errors) do
  local row = self.rows[index]
  if not row then
   row = CreateFrame('Button', nil, self.content); row:SetHeight(30)
   row.label = UI:Text(row, '', 11); row.label:SetPoint('LEFT', 6, 0); row.label:SetPoint('RIGHT', -6, 0); row.label:SetWordWrap(false)
   row.background = UI:Background(row)
   row:SetScript('OnClick', function() self.selected = row.entry; self:RefreshErrors() end)
   self.rows[index] = row
  end
  row.entry = entry
  row.label:SetText((entry.time .. '  ' .. entry.name .. '  [' .. (entry.event or L.manualRun) .. ']  ×' .. entry.count):gsub('|', '||'))
  row:SetPoint('TOPLEFT', 0, -(index - 1) * 32); row:SetPoint('TOPRIGHT', 0, -(index - 1) * 32)
  row.background:SetColorTexture(unpack(self.selected == entry and { 0.12, 0.24, 0.38, 1 } or UI.colors.panel))
  row:Show()
 end
 for index = #self.errors + 1, #self.rows do self.rows[index]:Hide() end
 self.content:SetHeight(math.max(1, #self.errors * 32))
 local entry = self.selected
 local detailText
 if entry then
  detailText = (entry.name .. '\n' .. entry.time .. '  [' .. (entry.event or L.manualRun) .. ']  ×' .. entry.count .. '\n\n' .. entry.message .. (entry.stack and ('\n\n' .. entry.stack) or '')):gsub('|', '||')
 else detailText = L.noSessionErrors end
 if detailText ~= self.displayedText then self.detail:SetText(detailText); self.displayedText = detailText end
 self.displayedEntry = entry
 self.detail.scrollFrame:SetVerticalScroll(previous == entry and offset or 0)
end

function D:ShowErrors()
 W:HidePanels(self.panel)
 W:Show()
 if addon.Automation.panel then addon.Automation.panel:Hide() end
 for _, panel in ipairs({ W.optionsFrame or false, W.helpFrame or false, W.syntaxFrame or false }) do if panel then panel:Hide() end end
 if self.panel then self.panel:SetShown(not self.panel:IsShown()); self:RefreshErrors(); return end
 local panel = CreateFrame('Frame', 'LuaWorkbenchSessionErrors', W.window); self.panel = panel
 panel:SetSize(math.max(320, W.window:GetWidth() - 48), math.max(360, W.window:GetHeight() - 72)); panel:SetPoint('CENTER')
 panel:SetFrameLevel(W.window:GetFrameLevel() + 40); panel:EnableMouse(true)
 UI:MovablePanel(panel, 'errors'); panel:RestorePanelPosition()
 UI:Background(panel, { 0.09, 0.11, 0.15, 1 }); UI:Border(panel, { 0.28, 0.34, 0.43, 1 })
 _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchSessionErrors'
 local title = UI:Text(panel, L.sessionErrors, 15); title:SetPoint('TOPLEFT', 16, -14)
 local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -6, -7)
 local clear = UI:Action(panel, 'clear', L.clearErrors, L.clearErrors, function() self:ClearErrors() end)
 clear:SetPoint('TOPLEFT', 16, -42)
 local hint = UI:Text(panel, L.errorHistoryHelp, 11); hint:SetPoint('TOPLEFT', 16, -80); hint:SetPoint('TOPRIGHT', -20, -80); hint:SetWordWrap(true)
 local scroll = UI:Scroll(panel); scroll:SetPoint('TOPLEFT', 16, -126); scroll:SetPoint('RIGHT', -28, 0); scroll:SetHeight(112)
 self.content = CreateFrame('Frame', nil, scroll); self.content:SetSize(650, 1); scroll:SetScrollChild(self.content)
 scroll:SetScript('OnSizeChanged', function(_, width) self.content:SetWidth(width) end)
 self.rows = {}
 self.detail = UI:Editor(panel, L.errorDetails, true)
 self.detail.frame:SetPoint('TOPLEFT', 12, -252); self.detail.frame:SetPoint('BOTTOMRIGHT', -12, 12)
 local copy = UI:Action(self.detail.frame, 'copy', L.copyOutputAction, L.copyOutputHint, function() self.detail:SetFocus(); self.detail:HighlightText() end)
 copy:SetPoint('TOPRIGHT', -8, -2)
 self:RefreshErrors()
end

function D:PreviewLineLimit()
 local value = tonumber(W.db.options.minimizedOutputLines) or 3
 return math.max(1, math.min(20, math.floor(value)))
end

function D:RefreshPreview()
 local limit = self:PreviewLineLimit()
 while #self.previewLines > limit do table.remove(self.previewLines, 1) end
 if not self.preview then return end
 local count = #self.previewLines
 self.previewTitle:SetText(count < self.previewCount and string.format(L.previewShowingLines, count, self.previewCount)
  or string.format(L.newOutputLines, self.previewCount))
 self.previewTitle:SetTextColor(self.previewFailed and 1 or 0.55, self.previewFailed and 0.4 or 0.76, self.previewFailed and 0.4 or 1)
 local top, rowHeight = 16 + self.previewTitle:GetStringHeight(), 17
 for index, text in ipairs(self.previewLines) do
  local row = self.previewRows[index]
  if not row then
   row = UI:Text(self.preview, '', 11); self.previewRows[index] = row
   row:SetJustifyV('TOP'); row:SetWordWrap(false)
  end
  row:ClearAllPoints(); row:SetPoint('TOPLEFT', 10, -top - (index - 1) * rowHeight)
  row:SetPoint('TOPRIGHT', -10, -top - (index - 1) * rowHeight); row:SetHeight(rowHeight)
  row:SetText(text:gsub('|', '||')); row:Show()
 end
 for index = count + 1, #self.previewRows do self.previewRows[index]:Hide() end
 self.preview:SetHeight(top + count * rowHeight + 8)
 self.previewDirty, self.previewTick = nil, 0
end

function D:ResetPreview()
 self.previewLines, self.previewCount, self.previewFailed, self.previewDirty = {}, 0, nil, nil
 self.previewAge, self.previewTick = 0, 0
 if self.preview then
  self.preview:Hide()
  for _, row in ipairs(self.previewRows) do row:Hide() end
 end
end

function D:QueueOutput(text)
 local failed = self.nextOutputError
 self.nextOutputError = nil
 if not W.db or not W.db.options.minimizedOutput or not W.minimized or not W.minibar or not W.minibar:IsShown() then return end
 local first, limit = self.previewCount == 0, self:PreviewLineLimit()
 -- Display text has already passed through Console:Format; no secret values are inspected here.
 for sourceLine in (text .. '\n'):gmatch('(.-)\n') do
  local line = sourceLine:gsub('|c%x%x%x%x%x%x%x%x', ''):gsub('|r', ''):gsub('||', '|')
  if #line > 180 then line = line:sub(1, 180):gsub('[\194-\244][\128-\191]*$', '') .. '…' end
  self.previewLines[#self.previewLines + 1] = line
  if #self.previewLines > limit then table.remove(self.previewLines, 1) end
  self.previewCount = self.previewCount + 1
 end
 self.previewFailed = self.previewFailed or failed
 self.previewDirty, self.previewAge = true, 0
 if not self.preview then self:BuildPreview() end
 if first then self:RefreshPreview() end
 self.preview:SetAlpha(1)
 self.preview:ClearAllPoints(); self.preview:SetPoint('TOPLEFT', W.minibar, 'BOTTOMLEFT', 0, addon.Debugger and addon.Debugger.paused and -34 or -4)
 self.preview:Show()
end

function D:BuildPreview()
 local preview = CreateFrame('Button', nil, W.minibar); self.preview = preview
 preview:SetSize(320, 55); preview:SetPoint('TOPLEFT', W.minibar, 'BOTTOMLEFT', 0, -4)
 preview:SetClampedToScreen(true)
 UI:Background(preview, { 0.07, 0.09, 0.13, 0.96 }); UI:Border(preview, { 0.25, 0.32, 0.42, 1 })
 self.previewTitle = UI:Text(preview, '', 11); self.previewTitle:SetPoint('TOPLEFT', 10, -8); self.previewTitle:SetPoint('TOPRIGHT', -10, -8)
 self.previewTitle:SetHeight(0); self.previewTitle:SetWordWrap(true)
 self.previewRows = {}
 preview:SetScript('OnClick', function() W:Show() end)
 preview:SetScript('OnUpdate', function(_, elapsed)
  if not W.minimized or not W.db.options.minimizedOutput then self:ResetPreview(); return end
  self.previewAge = (self.previewAge or 0) + elapsed
  self.previewTick = (self.previewTick or 0) + elapsed
  if self.previewDirty and self.previewTick >= 0.2 then
   self:RefreshPreview()
  end
  local fade = math.max(0, math.min(1, (self.previewAge - 4) / 1.5))
  preview:SetAlpha(1 - fade)
  preview:ClearAllPoints(); preview:SetPoint('TOPLEFT', W.minibar, 'BOTTOMLEFT', 0, -4 - (addon.Debugger and addon.Debugger.paused and 30 or 0) + fade * 8)
  if fade >= 1 then self:ResetPreview() end
 end)
 preview:SetScript('OnHide', function() preview:SetAlpha(1) end)
end
