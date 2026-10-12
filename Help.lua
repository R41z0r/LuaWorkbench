local _, addon = ...
local W, UI, L = addon.Workspace, addon.UI, addon.L

function W:ShowHelp()
 self:HidePanels(self.helpFrame)
 if self.syntaxFrame then self.syntaxFrame:Hide() end
 if addon.Diagnostics.panel then addon.Diagnostics.panel:Hide() end
 if addon.Automation.panel then addon.Automation.panel:Hide() end
 if self.optionsFrame then self.optionsFrame:Hide() end
 if self.contextMenu then self.contextMenu:Hide() end
 if self.helpFrame then self.helpFrame:SetShown(not self.helpFrame:IsShown()); return end
 local panel = CreateFrame('Frame', nil, self.window)
 self.helpFrame = panel
 panel:SetSize(560, 420)
 panel:SetPoint('CENTER')
 panel:SetFrameLevel(self.window:GetFrameLevel() + 30)
 panel:EnableMouse(true)
 UI:MovablePanel(panel, 'help'); panel:RestorePanelPosition()
 panel:SetResizable(true)
 local function restoreSize()
  local ratio = UIParent:GetEffectiveScale() / panel:GetEffectiveScale()
  local maxWidth = math.max(1, UIParent:GetWidth() * ratio - 32)
  local maxHeight = math.max(1, UIParent:GetHeight() * ratio - 32)
  local minWidth, minHeight = math.min(420, maxWidth), math.min(280, maxHeight)
  panel:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
  local saved = self.db.panelSizes and self.db.panelSizes.help
  panel:SetSize(math.max(minWidth, math.min(maxWidth, saved and saved.width or 560)), math.max(minHeight, math.min(maxHeight, saved and saved.height or 420)))
 end
 local function stopSizing()
  if not panel.sizing then return end
  panel.sizing = nil
  panel:StopMovingOrSizing()
  self.db.panelSizes = self.db.panelSizes or {}
  self.db.panelSizes.help = { width = panel:GetWidth(), height = panel:GetHeight() }
  local x, y = panel:GetCenter()
  if x and y then
   local ratio = panel:GetEffectiveScale() / UIParent:GetEffectiveScale()
   self.db.panelPositions = self.db.panelPositions or {}
   self.db.panelPositions.help = { x = x * ratio - UIParent:GetWidth() / 2, y = y * ratio - UIParent:GetHeight() / 2 }
  end
  panel:RestorePanelPosition()
 end
 local grip = CreateFrame('Button', nil, panel)
 grip:SetSize(18, 18); grip:SetPoint('BOTTOMRIGHT', -2, 2)
 grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
 grip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
 grip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
 grip:SetScript('OnMouseDown', function(_, button)
  if button == 'LeftButton' then panel.sizing = true; panel:StartSizing('BOTTOMRIGHT') end
 end)
 grip:SetScript('OnMouseUp', stopSizing)
 panel:HookScript('OnHide', stopSizing)
 panel:HookScript('OnShow', restoreSize)
 panel.resizeGrip, panel.RestoreHelpSize = grip, restoreSize
 restoreSize()
 UI:Background(panel, { 0.09, 0.11, 0.15, 1 })
 local title = UI:Text(panel, L.help, 16); title:SetPoint('TOPLEFT', 16, -15)
 local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end)
 close:SetPoint('TOPRIGHT', -6, -7)
 local scroll = UI:Scroll(panel)
 scroll:SetPoint('TOPLEFT', 16, -48); scroll:SetPoint('BOTTOMRIGHT', -28, 58)
 local content = CreateFrame('Frame', nil, scroll)
 scroll:SetScrollChild(content)
 local rows, tabs, section = {}, {}, 1
 panel.helpRows, panel.helpTabs = rows, tabs
 panel.helpTab = 1
 local function inlineCode(value)
  local kinds = { requireHelper = 'call', DevTools_Dump = 'call', dump = 'call', print = 'call', _G = 'globalVariable' }
  return (value:gsub('[%a_][%w_]*', function(word)
   local kind = kinds[word]
   return kind and ('|c' .. addon.Query.Editor:Color(kind) .. word .. '|r') or word
  end))
 end
 local function text(value, size, key)
  local row = { text = UI:Text(content, value, size), key = key and UI:Text(content, key, 12), section = section, value = value, heading = size == 15 }
  row.text:SetWordWrap(true); row.text:SetNonSpaceWrap(true)
  if size == 15 then row.text:SetTextColor(0.4, 0.86, 1)
  else row.text:SetTextColor(0.86, 0.89, 0.95) end
  if row.key then row.key:SetTextColor(0.65, 0.82, 1) end
  rows[#rows + 1] = row
 end
 local function code(source)
  local box = CreateFrame('Frame', nil, content)
  UI:Background(box, { 0.045, 0.055, 0.075, 1 })
  local label = UI:Text(box, '', 12)
  label:SetWordWrap(true); label:SetNonSpaceWrap(true)
  rows[#rows + 1] = { text = label, box = box, source = source, section = section }
 end
 text(L.helpShortcuts, 15)
 for _, entry in ipairs({
  { '/lua  /le  /luaeditor  /luaworkbench', L.restore },
  { 'Ctrl+Enter', L.queryLuaRun },
  { 'F5', L.runWithF5 },
  { 'Shift+Alt+F', L.queryLuaFormat },
  { 'Ctrl+S', L.save },
  { 'F9', L.debugBreakpoint },
  { 'F10', L.debugStepOver },
  { 'F11', L.debugStepInto },
  { 'Shift+F5', L.debugStop },
  { 'F5', L.debugContinue },
  { 'F12', L.goToDefinition },
  { 'Shift+F12', L.navigationBack },
  { 'Ctrl+F', L.findCode },
  { 'Ctrl+Shift+F', L.searchSnippets },
  { 'Enter / Shift+Enter', L.nextMatch .. ' / ' .. L.previousMatch },
 }) do text(entry[2], 12, addon.ShortcutText(entry[1])) end
 section = 2
 text(L.helpEditing, 12)
 text(L.snippets .. ' / ' .. L.save .. ' / ' .. L.saveAll, 15)
 text(L.helpStorage, 12)
 section = 4
 text(L.queryLuaRun .. ' / ' .. L.queryLuaOutput .. ' / ' .. L.options, 15)
 text(L.helpDebug, 12)
 text(L.debugTitle, 15)
 text(L.debugHelp, 12)
 text(L.debugScheduleMenu, 15)
 text(L.debugScheduleHelp, 12)
 text(L.debugEventsHelp, 12)
 text(L.debugCallbackHelp, 12)
 code('local frame = CreateFrame("Frame")\nframe:RegisterEvent("UNIT_HEALTH")\nframe:SetScript("OnEvent", function(self, event, unit)\n    dump(event, unit)\nend)')
 text(L.debugHelperHelp, 12)
 text(L.debugSnapshotHelp, 12)
 text(L.debugTerminal, 15)
 text(L.debugTerminalHelp, 12)
 text(L.debugLimits, 12)
 text(L.outputWindow, 15)
 text(L.outputWindowHelp, 12)
 text(L.helpDump, 12)
 code('dump("value", nil, false)\ndump({ count = 3, enabled = true })\nDevTools_Dump({ count = 3 }, "state")')
 text(L.helpSecretDump, 12)
 text(L.queryLuaHelp, 12)
 section = 3
 text(L.runOnEvent, 15)
 text(L.autoRunHelp, 12)
 text(L.customEventHelp, 12)
 text(L.scriptSettingsHelp, 12)
 text(L.textSnippets, 15)
 text(L.textSnippetsHelp, 12)
 text(L.helperModule, 15)
 text(L.helperHelp, 12)
 code('local tools = {}\nfunction tools.ABC(value)\n    return value * 2\nend\nreturn tools')
 text(L.helperConsumerHelp, 12)
 code('local tools = requireHelper("MyTools")\nlocal function ABC(value) return value + 1 end\nprint(ABC(3), tools.ABC(3))')
 section = 2
 text(L.goToDefinition, 15)
 text(L.navigationHelp, 12)
 text(L.syntaxColors, 15)
 text(L.syntaxHelp, 12)
 section = 4
 text(L.sessionErrors, 15)
 text(L.errorHistoryHelp, 12)
 text(L.minimizedOutputHelp, 12)
 local function layout()
  local width, y = math.max(200, scroll:GetWidth()), 0
  content:SetWidth(width)
  for _, row in ipairs(rows) do
   local shown = row.section == panel.helpTab
   row.text:SetShown(shown)
   if row.key then row.key:SetShown(shown) end
   if row.box then row.box:SetShown(shown) end
   if shown then
    local inset = row.key and math.min(255, width * 0.45) or 0
    row.text:ClearAllPoints()
    if row.box then
     row.box:ClearAllPoints(); row.box:SetPoint('TOPLEFT', 0, -y); row.box:SetWidth(width)
     row.text:SetPoint('TOPLEFT', 12, -12)
     row.text:SetText(addon.Query.Editor:Render(row.source))
    else
     row.text:SetPoint('TOPLEFT', inset, -y)
     row.text:SetText(row.heading and row.value or inlineCode(row.value))
    end
    row.text:SetWidth(math.max(1, width - inset - (row.box and 24 or 0))); row.text:SetHeight(0)
    local height = row.text:GetStringHeight()
    if row.key then
     row.key:ClearAllPoints(); row.key:SetPoint('TOPLEFT', 0, -y)
     row.key:SetWidth(inset - 12); row.key:SetHeight(0)
     height = math.max(height, row.key:GetStringHeight())
    end
    if row.box then height = height + 24; row.box:SetHeight(height) end
    y = y + height + (row.key and 12 or 20)
   end
  end
  local tabWidth = (panel:GetWidth() - 32) / 4
  for index, tab in ipairs(tabs) do
   tab:ClearAllPoints(); tab:SetPoint('BOTTOMLEFT', 16 + (index - 1) * tabWidth, 12)
   tab:SetSize(tabWidth - 4, 32)
   tab.active:SetShown(index == panel.helpTab)
   tab.label:SetTextColor(index == panel.helpTab and 0.4 or 0.8, index == panel.helpTab and 0.86 or 0.84, 1)
  end
  content:SetHeight(y)
  scroll:UpdateScrollChildRect()
  scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
 end
 function panel:SelectHelpTab(index)
  self.helpTab = index
  scroll:SetVerticalScroll(0)
  layout()
 end
 for index, name in ipairs({ L.helpTabShortcuts, L.helpTabEditor, L.helpTabScripts, L.helpTabDebug }) do
  local tab = UI:Button(panel, '', name, function() panel:SelectHelpTab(index) end, nil, true)
  tab.label = UI:Text(tab, name, 11)
  tab.label:SetPoint('LEFT', 5, 0); tab.label:SetPoint('RIGHT', -5, 0)
  tab.label:SetJustifyH('CENTER'); tab.label:SetWordWrap(true)
  tab.active = tab:CreateTexture(nil, 'OVERLAY')
  tab.active:SetColorTexture(0.4, 0.86, 1, 1)
  tab.active:SetPoint('BOTTOMLEFT'); tab.active:SetPoint('BOTTOMRIGHT'); tab.active:SetHeight(2)
  tabs[#tabs + 1] = tab
 end
 scroll:SetScript('OnSizeChanged', layout)
 panel:HookScript('OnShow', layout)
 layout()
end
