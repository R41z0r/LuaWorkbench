local _, addon = ...
local W, UI, L, C = addon.Workspace, addon.UI, addon.L, addon.Query.Console
local U = { gutterButtons = {} }
addon.DebugUI = U

-- Temporary opt-in hover diagnostics. Never collect source, names or values.
function U:TraceHover(reason, ...)
 local trace = self.hoverTrace
 if not trace then return end
 local fields = { reason }
 for index = 1, select('#', ...) do
  local value = select(index, ...)
  if _G.issecretvalue and _G.issecretvalue(value) then fields[#fields + 1] = '<secret>'
  elseif type(value) == 'boolean' then fields[#fields + 1] = value and '1' or '0'
  elseif type(value) == 'number' then fields[#fields + 1] = string.format('%.2f', value)
  elseif value == nil then fields[#fields + 1] = '-'
  else fields[#fields + 1] = '?' end
 end
 local text = table.concat(fields, ' ')
 local now = _G.GetTime and _G.GetTime() or 0
 local last = trace.rows[#trace.rows]
 if last and last.text == text then last.count, last.last = last.count + 1, now
 else
  trace.rows[#trace.rows + 1] = { text = text, count = 1, first = now, last = now }
  if #trace.rows > 200 then table.remove(trace.rows, 1); trace.dropped = trace.dropped + 1 end
 end
end

function U:HoverTraceCommand(message)
 local command = (message or ''):match('^%s*(.-)%s*$'):lower()
 if command == 'on' then
  self.hoverTrace = { rows = {}, dropped = 0 }
  self:TraceHover('enabled', addon.Debugger.paused == true)
 elseif command == 'off' then self.hoverTrace = nil
 elseif command == 'dump' then
  local trace = self.hoverTrace
  self.hoverTrace = nil -- Freeze the report before writing to the output UI.
  C:Write('HoverTrace v5 rows=' .. (trace and #trace.rows or 0) .. ' dropped=' .. (trace and trace.dropped or 0))
  if trace then
   for _, row in ipairs(trace.rows) do C:Write(string.format('%.2f-%.2f x%d %s', row.first, row.last, row.count, row.text)) end
  end
  return
 else command = 'on | off | dump' end
 C:SetStatus(L.debugTitle .. ': /lwhover ' .. command)
end

_G.SLASH_LUAWORKBENCHHOVER1 = '/lwhover'
_G.SlashCmdList.LUAWORKBENCHHOVER = function(message) U:HoverTraceCommand(message) end

function U:Start(events)
 if not W.current then return end
 if addon.DebugProbe.armed then addon.DebugProbe:Stop() end
 local names, seen = {}, {}
 if events then
  local options = addon.Automation:Options(W.current)
  for _, entry in ipairs(options.events) do
   if entry.enabled and not seen[entry.name] then names[#names + 1] = entry.name; seen[entry.name] = true end
  end
  if options.login and not seen.PLAYER_LOGIN then names[#names + 1] = 'PLAYER_LOGIN' end
  if #names == 0 then C:SetStatus(L.debugNoEvents, true); addon.Automation:Toggle(W.debugButton); return end
 end
 self.drawerOpen = true
 addon.Debugger:Start(W.current, W:NormalizeSource(C.input:GetText()), names)
 self:Refresh()
end

function U:StartupMenu(owner)
 local entries, plan = {}, W.db.startupDebug
 for _, persistent in ipairs({ false, true }) do
  for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN' }) do
   local selectedEvent, repeatRun = event, persistent
   entries[#entries + 1] = {
    text = (persistent and L.debugScheduleAlways or L.debugScheduleOnce) .. ' · ' .. event,
    selected = type(plan) == 'table' and plan.id == W.current and plan.event == event and (plan.persistent == true) == persistent,
    action = function() addon.Debugger:ScheduleStartup(W.current, selectedEvent, repeatRun) end,
   }
  end
 end
 if plan then
  local saved = type(plan) == 'table' and W.db.snippets[plan.id]
  entries[#entries + 1] = { text = L.debugScheduleCancel .. (saved and (' · ' .. saved.name) or ''),
   action = function() W.db.startupDebug = nil; C:SetStatus(nil) end }
 end
 W:OpenMenu(owner, entries)
end

function U:Menu(owner)
 local D = addon.Debugger
 local entries = {
  { text = L.debugStart, action = function() self:Start(false) end },
  { text = L.debugEvents, action = function() self:Start(true) end },
  { text = L.debugScheduleMenu, action = function() self:StartupMenu(owner) end },
  { text = L.debugBreakpoint, action = function() self:ToggleLine(C:GetLinePosition(C.source, C.input.editBox:GetCursorPosition())) end },
  { text = L.debugClearBreakpoints, action = function()
   local points = D:GetBreakpoints(W.current)
   local lines = {}; for line in pairs(points) do lines[#lines + 1] = line end
   for _, line in ipairs(lines) do D:ToggleBreakpoint(W.current, line, C.source) end
   C:UpdateLineNumbers()
  end },
 }
 if D.armed or D.startupOwnedId then entries[#entries + 1] = { text = L.debugStop, action = function() D:Stop() end } end
 W:OpenMenu(owner, entries)
end

function U:ToggleLine(line)
 if not W.current then return end
 addon.Debugger:ToggleBreakpoint(W.current, line, C.source)
 C:UpdateLineNumbers()
end

function U:Build(play)
 if self.toolbar then return end
 local input = C.input
 W.debugButton = UI:Button(input.frame, 'debug', L.debugStart, function(button) self:Menu(button or W.debugButton) end, { 1, 0.7, 0.3, 1 })
 W.debugButton:SetPoint('RIGHT', play, 'LEFT', -2, 0)
 self.playButton = play
 self.stopButton = UI:Button(input.frame, 'stop', L.debugStop .. ' (Shift+F5)', function() addon.Debugger:Stop() end, { 1, 0.35, 0.3, 1 })
 self.stopButton:SetPoint('CENTER', play, 'CENTER'); self.stopButton:Hide()
 local toolbar = CreateFrame('Frame', nil, input.frame); self.toolbar = toolbar
 toolbar:SetPoint('TOPLEFT', 6, -56); toolbar:SetPoint('TOPRIGHT', -6, -56); toolbar:SetHeight(30)
 UI:Background(toolbar, { 0.12, 0.16, 0.21, 1 })
 local buttons = {}
 for index, item in ipairs({
  { 'play', L.debugContinue, function() addon.Debugger:Continue() end },
  { 'next', L.debugStepOver, function() addon.Debugger:StepOver() end },
  { 'stepInto', L.debugStepInto, function() addon.Debugger:StepInto() end },
  { 'close', L.debugStop, function() addon.Debugger:Stop() end },
  { '{}', L.debugDrawer, function() self.drawerOpen = not self.drawerOpen; self:Layout() end },
  { 'search', L.debugShow, function() self:ShowLocation() end },
 }) do
  local button = UI:Button(toolbar, item[1], item[2], item[3])
  button:SetPoint('LEFT', (index - 1) * 30, 0); buttons[index] = button
 end
 self.buttons = buttons
 self.status = UI:Text(toolbar, '', 10)
 self.status:SetPoint('LEFT', 184, 0); self.status:SetPoint('RIGHT', -8, 0); self.status:SetWordWrap(false)
 local dock = CreateFrame('Frame', nil, input.frame); self.dock = dock
 dock:SetPoint('BOTTOMLEFT', 6, 4); dock:SetPoint('BOTTOMRIGHT', -6, 4)
 UI:Background(dock, { 0.075, 0.09, 0.12, 1 }); UI:Border(dock, { 0.22, 0.3, 0.4, 1 })
 local terminal = UI:Editor(dock, L.debugTerminal, true)
 terminal.frame:SetPoint('TOPLEFT', 2, -2); terminal.frame:SetPoint('BOTTOMLEFT', 2, 34)
 terminal.scrollBG:SetPoint('TOPLEFT', terminal.frame, 'TOPLEFT', 6, -24)
 terminal.label:ClearAllPoints(); terminal.label:SetPoint('TOPLEFT', 12, -10)
 terminal.label:SetWidth(terminal.label:GetStringWidth())
 self.terminalHelp = UI:Button(terminal.frame, '?', L.debugTerminalHelp, function() W:ShowHelp(); if W.helpFrame.SelectHelpTab then W.helpFrame:SelectHelpTab(4) end end)
 self.terminalHelp:SetPoint('LEFT', terminal.label, 'RIGHT', 4, 0); self.terminalHelp:SetSize(22, 22)
 self.terminalHelp:HookScript('OnEnter', function()
  GameTooltip:ClearLines(); GameTooltip:AddLine(L.debugTerminal, 0.4, 0.86, 1)
  for paragraph in (L.debugTerminalHelp .. '\n\n'):gmatch('(.-)\n\n') do
   GameTooltip:AddLine(' '); GameTooltip:AddLine(paragraph, 0.85, 0.9, 1, true)
  end
  GameTooltip:SetMinimumWidth(320); GameTooltip:Show()
 end)
 local box = CreateFrame('EditBox', nil, dock)
 box:SetAutoFocus(false); box:SetFontObject(ChatFontNormal); box:SetTextInsets(6, 6, 0, 0)
 box:SetHistoryLines(100); box:SetAltArrowKeyMode(true); box:SetMaxLetters(4000)
 box:SetHeight(26); box:SetPoint('BOTTOMLEFT', 8, 6); box:SetPoint('RIGHT', terminal.frame, 'RIGHT', -8, 0)
 UI:Background(box, UI.colors.hover)
 box:SetScript('OnEnterPressed', function(edit)
  addon.Debugger:Evaluate(edit:GetText()); edit:SetText(''); self:HideTooltip(nil, 'terminal-submit')
 end)
 box:SetScript('OnEscapePressed', function(edit) edit:ClearFocus() end)
 box:SetScript('OnKeyDown', function(_, key) self:Shortcut(key) end)
 box:SetScript('OnKeyUp', function(_, key) self:KeyUp(key) end)
 terminal.scrollFrame:HookScript('OnScrollRangeChanged', function(scroll) scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end)
 self.terminalOutput, self.terminalInput = terminal, box
 addon.Debugger.terminal = { output = terminal, input = box }
 local inspector = CreateFrame('Frame', nil, dock); self.inspector = inspector
 inspector:SetPoint('TOPLEFT', terminal.frame, 'TOPRIGHT', 6, 0); inspector:SetPoint('BOTTOMRIGHT', -8, 6)
 local label = UI:Text(inspector, L.debugVariables, 11); label:SetPoint('TOPLEFT', 0, -10)
 local scroll = UI:Scroll(inspector); scroll:SetPoint('TOPLEFT', 0, -30); scroll:SetPoint('BOTTOMRIGHT', -10, 2)
 local content = CreateFrame('Frame', nil, scroll); scroll:SetScrollChild(content); content:SetSize(180, 176)
 scroll:SetScript('OnSizeChanged', function(_, width) content:SetWidth(width) end)
 self.variableContent, self.variableScroll = content, scroll
 addon.Debugger.variableRows = {}
 for index = 1, 8 do
  local row = CreateFrame('Button', nil, content)
  row:SetPoint('TOPLEFT', 0, -(index - 1) * 22); row:SetPoint('RIGHT', 0, 0); row:SetHeight(22)
  row.text = UI:Text(row, '', 11); row.text:SetAllPoints(); row.text:SetWordWrap(false)
  row:SetScript('OnEnter', function() self:ValueTooltip(row, row.preview, row.hasSecretText, row.secretText, row.secretLabel) end)
  row:SetScript('OnLeave', function()
   self:TraceHover('inspector-leave', row:IsMouseOver(), row:IsShown(), row:GetWidth(), row:GetHeight())
   self:HideTooltip(row, 'inspector-leave')
  end)
  addon.Debugger.variableRows[index] = row
 end
 dock:HookScript('OnHide', function() box:ClearFocus() end)
 self.pausedLine = input.editBox:CreateTexture(nil, 'BACKGROUND')
 self.pausedLine:SetColorTexture(1, 0.7, 0.15, 0.15); self.pausedLine:Hide()
 input.editBox:HookScript('OnUpdate', function(_, elapsed) self:HoverUpdate(elapsed) end)
 input.editBox:HookScript('OnHide', function() self:HideTooltip(nil, 'editor-hidden') end)
 self:Refresh()
end

function U:UpdateVariables()
 local D = addon.Debugger
 if not self.variableContent or self.renderedVariables == D.variables then return end
 self.renderedVariables = D.variables
 self:TraceHover('inspector-rebuild')
 for index, item in ipairs(D.variables or {}) do
  local row = D.variableRows[index]
  if not row then
   row = CreateFrame('Button', nil, self.variableContent)
   row:SetPoint('TOPLEFT', 0, -(index - 1) * 22); row:SetPoint('RIGHT', 0, 0); row:SetHeight(22)
   row.text = UI:Text(row, '', 11); row.text:SetAllPoints(); row.text:SetWordWrap(false)
   row:SetScript('OnEnter', function() self:ValueTooltip(row, row.preview, row.hasSecretText, row.secretText, row.secretLabel) end)
   row:SetScript('OnLeave', function()
    self:TraceHover('inspector-leave', row:IsMouseOver(), row:IsShown(), row:GetWidth(), row:GetHeight())
    self:HideTooltip(row, 'inspector-leave')
   end)
   D.variableRows[index] = row
  end
  row.text:SetText((item.name .. ' = ' .. item.value):gsub('|', '||'))
  row.preview = (item.name .. ' = ' .. item.preview):gsub('|', '||')
  row.secretLabel = item.name:gsub('|', '||') .. ' = |cff88ff88<secret>|r'
  row.hasSecretText, row.secretText = item.hasSecretText, item.secretText
  row:Show()
 end
 for index = #(D.variables or {}) + 1, #D.variableRows do
  local row = D.variableRows[index]; row:Hide(); row.secretText, row.hasSecretText = nil, nil
 end
 self.variableContent:SetHeight(math.max(1, #(D.variables or {}) * 22))
 self.variableScroll:UpdateScrollChildRect()
end

function U:ValueTooltip(owner, text, hidden, value, secretLabel)
 if not self.valueTooltip then
  local tooltip = CreateFrame('GameTooltip', 'LuaWorkbenchDebugValueTooltip', UIParent, 'GameTooltipTemplate')
  self.valueTooltip = tooltip
  tooltip:SetClampedToScreen(true); tooltip:EnableMouse(false)
  tooltip:HookScript('OnShow', function() self:TraceHover('tooltip-show') end)
  tooltip:HookScript('OnHide', function() self:TraceHover('tooltip-hide') end)
 end
 local tooltip = self.valueTooltip
 self:TraceHover('show-request', owner == C.input.editBox, hidden == true)
 self.tooltipOwner = owner
 if owner ~= C.input.editBox then self.hoverPath, self.hoverToken = nil, nil end
 tooltip:SetOwner(owner, 'ANCHOR_NONE'); tooltip:ClearLines()
 -- Keep the popup clear of the pointer and independent of other UI tooltips.
 local x, y = GetCursorPosition(); local scale = UIParent:GetEffectiveScale()
 tooltip:ClearAllPoints(); tooltip:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', x / scale + 16, y / scale + 20)
 if hidden then
  addon.DebugProbe:SecretTooltip(tooltip, secretLabel, value)
 else tooltip:SetText((text or ''):gsub('<secret>', '|cff88ff88<secret>|r'), 0.85, 0.9, 1, 1, true) end
 tooltip:Show(); self.tooltipVisible = true
 self:TraceHover('shown', tooltip:IsShown(), tooltip:IsVisible(), tooltip:GetAlpha(), tooltip:GetEffectiveAlpha())
end

function U:HideTooltip(owner, reason)
 if owner and self.tooltipOwner ~= owner then return end
 if self.valueTooltip and self.valueTooltip:IsShown() then self:TraceHover(reason or 'hide-unspecified'); self.valueTooltip:Hide() end
 self.tooltipVisible, self.tooltipOwner, self.hoverPath, self.hoverToken = nil, nil, nil, nil
end

function U:Layout()
 if not self.toolbar then return end
 local D, input = addon.Debugger, C.input
 local active = D.armed == true
 self.toolbar:SetShown(active)
 local find = W.findBar and W.findBar:IsShown()
 local top = (find and 96 or 56) + (active and 32 or 0)
 input.scrollBG:SetPoint('TOPLEFT', input.frame, 'TOPLEFT', 6, -top)
 if W.findBar then W.findBar:SetPoint('TOPRIGHT', input.frame, 'TOPRIGHT', -10, active and -88 or -56) end
 local height = math.min(200, math.max(100, input.frame:GetHeight() * 0.42))
 local drawer = active and self.drawerOpen and input.frame:GetHeight() - top - height >= 55
 self.dock:SetShown(drawer == true)
 self.dock:SetHeight(height)
 self.terminalOutput.frame:SetWidth(math.max(180, input.frame:GetWidth() * 0.62 - 16))
 input.scrollBG:SetPoint('BOTTOMRIGHT', input.frame, 'BOTTOMRIGHT', -16, drawer and height + 8 or 8)
end

function U:Refresh()
 if not self.toolbar then return end
 local D = addon.Debugger
 local active = D.armed == true
 local canStop = active or D.startupOwnedId ~= nil
 self.playButton:SetShown(not canStop); self.stopButton:SetShown(canStop)
 UI:ButtonColor(W.debugButton, active and { 0.4, 0.88, 0.58, 1 } or { 1, 0.7, 0.3, 1 })
 if self.layoutArmed ~= D.armed then self.layoutArmed = D.armed; W:Layout() end
 self.status:SetText(((D.status or L.debugTitle) .. '  ·  ' .. string.format(L.debugProbeQueue, #D.queue)):gsub('|', '||'))
 if D.dropped > 0 then self.status:SetText(self.status:GetText() .. '  ·  ' .. string.format(L.debugProbeOverflow, D.dropped)) end
 for index = 1, 3 do self.buttons[index]:SetEnabled(D.paused == true) end
 self.buttons[6]:SetEnabled(D.paused == true)
 self.terminalInput:SetEnabled(D.paused == true)
 self:UpdateVariables(); self:Layout(); self:UpdateMinibar(); C:UpdateLineNumbers()
 if not D.paused then self:HideTooltip(nil, 'not-paused'); if self.snapshot then self.snapshot:Hide() end end
 if D.paused and self.pauseToken ~= D.evalToken then
  self.pauseToken = D.evalToken
  if W.window:IsShown() and not W.minimized then self:ShowLocation(false) end
 end
end

function U:ShowDrawer()
 self.drawerOpen = true
 self:ShowLocation(); self:Layout()
 if self.terminalInput then self.terminalInput:SetFocus() end
end

function U:CurrentSource()
 local D = addon.Debugger
 return D.CurrentSource and D:CurrentSource() or { id = D.scriptId, source = D.source }
end

function U:ShowSourceSnapshot(record, offset, focus)
 if not self.snapshot then
  local panel = CreateFrame('Frame', nil, W.window); self.snapshot = panel
  panel:SetSize(math.min(640, UIParent:GetWidth() - 32), math.min(420, UIParent:GetHeight() - 32))
  panel:SetPoint('CENTER'); panel:SetFrameLevel(W.window:GetFrameLevel() + 55); panel:EnableMouse(true)
  UI:MovablePanel(panel, 'debugSnapshot'); panel:RestorePanelPosition()
  UI:Background(panel, UI.colors.panel); UI:Border(panel, { 0.28, 0.34, 0.43, 1 })
  self.snapshotTitle = UI:Text(panel, '', 12)
  self.snapshotTitle:SetPoint('TOPLEFT', 12, -12); self.snapshotTitle:SetPoint('RIGHT', -40, 0)
  local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -4, -4)
  local hint = UI:Text(panel, L.debugSnapshotHelp, 11)
  hint:SetPoint('TOPLEFT', 12, -38); hint:SetPoint('TOPRIGHT', -12, -38); hint:SetHeight(42); hint:SetWordWrap(true)
  local input = UI:Editor(panel, L.debugSnapshot, true); self.snapshotInput = input
  input.frame:SetPoint('TOPLEFT', 8, -82); input.frame:SetPoint('BOTTOMRIGHT', -8, 8)
  -- Use the syntax renderer without attaching the editable input handlers.
  local overlay = input.editBox:CreateFontString(nil, 'OVERLAY')
  overlay:SetJustifyH('LEFT'); overlay:SetJustifyV('TOP'); overlay:SetWordWrap(true); overlay:SetNonSpaceWrap(true)
  input.queryEditor = { overlay = overlay }; input.editBox:SetTextColor(0, 0, 0, 0)
  input.editBox:HookScript('OnUpdate', function(_, elapsed)
   addon.Query.Editor:Paint(input); self:PaintSnapshotLine(); self:HoverUpdate(elapsed, input, self.snapshotRecord)
  end)
  input.editBox:HookScript('OnKeyDown', function(_, key) self:Shortcut(key) end)
  input.editBox:HookScript('OnKeyUp', function(_, key) self:KeyUp(key) end)
  panel:HookScript('OnHide', function() input:ClearFocus(); self:HideTooltip(input.editBox, 'snapshot-hidden') end)
 end
 self.snapshotRecord = record
 self.snapshotLine = addon.Debugger.line
 self.snapshotTitle:SetText((L.debugSnapshot .. ': ' .. (record.name or tostring(record.id))):gsub('|', '||'))
 self.snapshotInput:SetText(record.source)
 addon.Query.Editor:Paint(self.snapshotInput); self:PaintSnapshotLine()
 self.snapshot:Show()
 addon.Navigation:Position(self.snapshotInput, offset, focus)
 local last = (record.source:find('\n', offset + 1, true) or (#record.source + 1)) - 1
 self.snapshotInput:HighlightText(offset, last)
end

function U:PaintSnapshotLine()
 local input, record = self.snapshotInput, self.snapshotRecord
 if not input or not record or not self.snapshotLine then return end
 local box = input.editBox
 if not self.snapshotMeasure then
  self.snapshotMeasure = box:CreateFontString(nil, 'OVERLAY')
  self.snapshotMeasure:SetWordWrap(true); self.snapshotMeasure:SetNonSpaceWrap(true); self.snapshotMeasure:Hide()
  self.snapshotHighlight = box:CreateTexture(nil, 'BACKGROUND')
  self.snapshotHighlight:SetColorTexture(1, 0.7, 0.15, 0.15)
 end
 local font, size, flags = box:GetFont()
 local width, spacing = box:GetWidth(), box:GetSpacing()
 local cache = self.snapshotMeasureCache
 if cache and cache.record == record and cache.line == self.snapshotLine and cache.font == font and cache.size == size and cache.flags == flags and cache.width == width and cache.spacing == spacing then return end
 self.snapshotMeasureCache = { record = record, line = self.snapshotLine, font = font, size = size, flags = flags, width = width, spacing = spacing }
 local measure, offset, height, line = self.snapshotMeasure, 0, size + spacing, 1
 measure:SetFont(font, size, flags); measure:SetSpacing(spacing); measure:SetWidth(math.max(1, width))
 for text in (record.source .. '\n'):gmatch('(.-)\n') do
  measure:SetText(text ~= '' and text:gsub('|', '||') or ' ')
  height = math.max(size + spacing, measure:GetStringHeight())
  if line == self.snapshotLine then break end
  offset, line = offset + height, line + 1
 end
 self.snapshotHighlight:ClearAllPoints(); self.snapshotHighlight:SetPoint('TOPLEFT', box, 'TOPLEFT', 0, -offset)
 self.snapshotHighlight:SetSize(width, height); self.snapshotHighlight:Show()
end

function U:ShowLocation(focus)
 local D, record = addon.Debugger, self:CurrentSource()
 if not record or not record.id or not record.source then return end
 W:Show(focus ~= false)
 local offset = 0
 for _ = 2, D.line or 1 do local stop = record.source:find('\n', offset + 1, true); if not stop then break end; offset = stop end
 local displayed = W.current == record.id and C.source or nil
 local stored = W.db.drafts[record.id] or W.db.snippets[record.id]
 if not displayed and stored then displayed = W:NormalizeSource(stored.source) end
 if displayed ~= record.source then self:ShowSourceSnapshot(record, offset, focus); return end
 if self.snapshot then self.snapshot:Hide() end
 if W.current ~= record.id then W:Select(record.id) end
 addon.Navigation:Position(C.input, offset, focus)
end

function U:UpdateMinibar()
 local bar, D = W.minibar, addon.Debugger
 if not bar then return end
 if not self.mini then
  self.mini = UI:Action(bar, 'debug', L.debugPaused, L.debugShow, function()
   C.input:ClearFocus()
   if self.terminalInput then self.terminalInput:ClearFocus() end
   if self.snapshotInput then self.snapshotInput:ClearFocus() end
   self:ShowLocation(false)
  end)
  self.mini:SetPoint('TOPLEFT', bar, 'BOTTOMLEFT', 0, -2); self.mini:SetPoint('RIGHT', bar, 'RIGHT', 0, 0)
  UI:Background(self.mini, { 0.28, 0.18, 0.07, 1 })
 end
 self.mini:SetShown(D.paused == true)
end

function U:SourceChanged(source)
 local D = addon.Debugger
 if W.selecting then return end
 local registered = D.sources and D.sources[W.current]
 local stopped = D.armed and ((registered and registered.source ~= source) or (D.scriptId == W.current and source ~= D.source))
 local state = C.input and C.input.queryEditor
 local keyEdit = state and state.keyEdit
 local edit = keyEdit and keyEdit.enter and { oldCursor = keyEdit.cursor, oldSource = keyEdit.source } or nil
 if W.current then D:SourceChanged(W.current, source, edit) end
 if stopped then C:SetStatus(L.debugSourceChanged, true) end
 self:HideTooltip(nil, 'source-changed')
end

function U:Shortcut(key)
 local D = addon.Debugger
 if not W.window or not W.window:IsShown() then return false end
 if IsControlKeyDown() or (_G.IsAltKeyDown and IsAltKeyDown()) or (_G.IsMetaKeyDown and _G.IsMetaKeyDown()) then return false end
 local focused = W.window:IsMouseOver() or C.input.editBox:HasFocus() or (self.terminalInput and self.terminalInput:HasFocus()) or (self.snapshot and self.snapshot:IsShown() and self.snapshotInput.editBox:HasFocus())
 if not focused then return false end
 if key == 'F9' and not IsShiftKeyDown() then
  if self.snapshot and self.snapshot:IsShown() and self.snapshotInput.editBox:HasFocus() then
   if not self.held then
    self.held = key
    local record = self.snapshotRecord
    D:ToggleBreakpoint(record.id, C:GetLinePosition(record.source, self.snapshotInput.editBox:GetCursorPosition()), record.source)
   end
   return true
  end
  if not self.held then self.held = key; self:ToggleLine(C:GetLinePosition(C.source, C.input.editBox:GetCursorPosition())) end
  return true
 end
 if not D.armed then return false end
 local action
 if key == 'F5' then action = IsShiftKeyDown() and D.Stop or D.Continue
 elseif key == 'F10' and not IsShiftKeyDown() then action = D.StepOver
 elseif key == 'F11' and not IsShiftKeyDown() then action = D.StepInto end
 if not action then return false end
 if not self.held then self.held = key; action(D) end
 return true
end

function U:KeyUp(key) if self.held == key then self.held = nil end end

function U:UpdateGutter(state, visible)
 local D = addon.Debugger
 local registered = D.armed and D.sources and D.sources[W.current]
 local differentDraft = registered and registered.source ~= C.source
 local points = W.current and not differentDraft and D:GetBreakpoints(W.current, C.source) or {}
 local record = self:CurrentSource()
 local paused = D.paused and record and record.id == W.current and record.source == C.source and D.line
 for index, entry in ipairs(visible) do
  local button = self.gutterButtons[index]
  if not button then
   button = CreateFrame('Button', nil, state.gutter); self.gutterButtons[index] = button
   button:SetFrameLevel(state.gutter:GetFrameLevel() + 3)
   button.dot = UI:Dot(button, 7); button.dot:SetColorTexture(1, 0.3, 0.3, 1)
   button.arrow = UI:Text(button, '>', 12); button.arrow:SetPoint('RIGHT', button.dot, 'LEFT', -3, 0); button.arrow:SetTextColor(1, 0.8, 0.2)
   button:SetScript('OnClick', function() self:ToggleLine(button.line) end)
   UI:Tooltip(button, L.debugBreakpoint)
  end
  button.line = entry.line
  button:ClearAllPoints(); button:SetPoint('TOPLEFT', state.gutter, 'TOPLEFT', 0, entry.y)
  button:SetSize(state.gutter:GetWidth(), entry.height); button:Show()
  -- Line numbers are top-aligned; spacing and wrapped-line height do not
  -- belong to the glyph centre used for the marker.
  button.dot:ClearAllPoints()
  button.dot:SetPoint('RIGHT', button, 'TOPRIGHT', -2 - state.numberWidth - 5, -entry.textHeight / 2)
  button.dot:SetShown(points[entry.line] == true); button.arrow:SetShown(paused == entry.line)
 end
 for index = #visible + 1, #self.gutterButtons do self.gutterButtons[index]:Hide() end
 if self.pausedLine then
  local position = paused and state.positions[paused]
  self.pausedLine:SetShown(position ~= nil)
  if position then
   self.pausedLine:ClearAllPoints(); self.pausedLine:SetPoint('TOPLEFT', C.input.editBox, 'TOPLEFT', 0, -position.offset)
   self.pausedLine:SetWidth(C.input.editBox:GetWidth()); self.pausedLine:SetHeight(position.height)
  end
 end
end

-- Resolve only names and raw dotted fields; hovering never evaluates Lua expressions.
function U:HoverPath(source, position)
 if self.tokenSource ~= source then self.tokenSource, self.hoverTokens = source, addon.Query.Editor:Tokenize(source) end
 local tokens = self.hoverTokens
 for index, token in ipairs(tokens) do
  if position >= token.start and position <= token.finish and (token.kind == 'identifier' or token.kind == 'call') then
   local first = index
   while first > 2 and tokens[first - 1].text == '.' and (tokens[first - 2].kind == 'identifier' or tokens[first - 2].kind == 'call') do first = first - 2 end
   local path = source:sub(tokens[first].start, token.finish)
   return path
  end
 end
end

function U:HoverUpdate(elapsed, target, record)
 local D, input = addon.Debugger, target or C.input
 record = record or self:CurrentSource()
 local source = target and record and record.source or C.source
 local matches = record and (target or record.id == W.current) and record.source == source
 -- A scroll child's geometric bounds may extend behind the inspector.
 if self.tooltipOwner and self.tooltipOwner ~= input.editBox and self.tooltipOwner:IsMouseOver() then self:TraceHover('other-owner'); return end
 if not D.paused or not matches or not input.editBox:IsMouseOver() or not input.scrollFrame:IsMouseOver() then
  self:TraceHover('gate', D.paused == true, matches ~= nil and matches ~= false, input.editBox:IsMouseOver(), input.scrollFrame:IsMouseOver())
  self:HideTooltip(input.editBox, 'code-gate')
  return
 end
 self.hoverElapsed = (self.hoverElapsed or 0) + elapsed
 if self.hoverElapsed < 0.1 then return end
 self.hoverElapsed = 0
 local state = input.queryEditor
 local font = state and state.overlay
 if not font or state.renderSource ~= source then return end
 if type(font.CalculateScreenAreaFromCharacterSpan) ~= 'function' then self:TraceHover('missing-area-api'); return end
 local actual, size, flags = font:GetFont()
 local width, spacing = font:GetWidth(), font:GetSpacing()
 local layout = input.debugHitLayout
 local changed = not layout or layout.font ~= actual or layout.size ~= size or layout.flags ~= flags
  or layout.width ~= width or layout.spacing ~= spacing or layout.source ~= source
 if changed then
  input.debugHitLayout = { font = actual, size = size, flags = flags, width = width, spacing = spacing, source = source }
  self:HideTooltip(input.editBox, 'code-layout')
  return -- Let the visible font layout settle after a change.
 end
 local x, y = GetCursorPosition(); local scale = font:GetEffectiveScale()
 local sourcePosition = addon.Query.Editor:HoverSourcePosition(input, x / scale, y / scale)
 local path = sourcePosition and self:HoverPath(source, sourcePosition)
 if self.hoverTrace then
  self:TraceHover('glyph-hit', sourcePosition, sourcePosition and C:GetLinePosition(source, sourcePosition - 1), x / scale, y / scale)
 end
 if not path then self:HideTooltip(input.editBox, 'code-no-token'); return end
 if self.hoverPath == path and self.hoverToken == D.evalToken and self.tooltipOwner == input.editBox and self.valueTooltip and self.valueTooltip:IsShown() then return end
 local value, found = D:ResolveVariable(path)
 self:TraceHover('resolve', found == true)
 if not found then self:HideTooltip(input.editBox, 'code-unresolved'); return end
 local hidden = _G.issecretvalue and _G.issecretvalue(value)
 local name = path:gsub('|', '||')
 self:ValueTooltip(input.editBox, name .. ' = ' .. D:FormatPreview(value):gsub('|', '||'), hidden and (type(value) == 'string' or type(value) == 'number'), value, name .. ' = |cff88ff88<secret>|r')
 self.hoverPath, self.hoverToken = path, D.evalToken
end
