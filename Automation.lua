local addonName, addon = ...
local W, UI, L, Console = addon.Workspace, addon.UI, addon.L, addon.Query.Console
local function pack(...) return { n = select('#', ...), ... } end
local A = { environments = {}, running = {}, initialized = false }
addon.Automation = A

function A:ValidateEvent(value)
 local event = (value or ''):match('^%s*(.-)%s*$'):upper()
 if not event:match('^[A-Z][A-Z0-9_]*$') then return nil end
 self.probe = self.probe or CreateFrame('Frame')
 local ok, result = pcall(self.probe.RegisterEvent, self.probe, event)
 self.probe:UnregisterAllEvents()
 if ok and result ~= false then return event end
end

function A:Options(id)
 local options = W.db.autoRun[id]
 if not options then options = {}; W.db.autoRun[id] = options end
 if not options.events then
  options.events = {}
  if type(options.event) == 'string' and options.event ~= '' then
   options.events[1] = { name = options.event, enabled = options.eventEnabled == true }
  end
 end
 options.event, options.eventEnabled = nil, nil
 return options
end

function A:HasEvent(options, event)
 for _, entry in ipairs(options.events or {}) do
  if entry.enabled and entry.name == event then return true end
 end
 return false
end

function A:Summary(id)
 local options = W.db.autoRun[id]
 if not options then return '' end
 local parts = {}
 if options.startup then parts[#parts + 1] = L.triggerStartup end
 if options.login then parts[#parts + 1] = L.triggerLogin end
 local count = 0
 for _, entry in ipairs(options.events or {}) do if entry.enabled then count = count + 1 end end
 if count > 0 then parts[#parts + 1] = string.format(L.triggerEvents, count) end
 return table.concat(parts, ' + ')
end

function A:Tooltip(id)
 local options = self:Options(id)
 local lines = { L.automaticRun }
 if options.startup then lines[#lines + 1] = L.runOnStartup end
 if options.login then lines[#lines + 1] = L.runOnLogin end
 for _, entry in ipairs(options.events) do if entry.enabled then lines[#lines + 1] = entry.name end end
 lines[#lines + 1] = '\n' .. (W.db.snippets[id] and L.savedCodeOnly or L.saveBeforeAutoRun)
 return table.concat(lines, '\n')
end

function A:Refresh()
 if not W.db then return end
 self.frame:UnregisterAllEvents()
 for _, event in ipairs({ 'ADDON_LOADED', 'PLAYER_LOGIN', 'PLAYER_LOGOUT' }) do self.frame:RegisterEvent(event) end
 for id in pairs(W.db.autoRun) do
  if not W.db.snippets[id] and not W.db.drafts[id] then
   W.db.autoRun[id], self.environments[id] = nil, nil
  else
   local options = self:Options(id)
   for _, entry in ipairs(options.events) do
    if entry.enabled then
     local event = self:ValidateEvent(entry.name)
     if event then
      entry.name = event
      if W.db.snippets[id] then self.frame:RegisterEvent(event) end
     else
      entry.enabled = false
      Console:Write(L.invalidEvent, entry.name)
     end
    end
   end
  end
 end
end

function A:Changed()
 self:Refresh()
 self:UpdateControls()
 W:RefreshTree()
end

function A:AddEvent(id, value)
 local event = self:ValidateEvent(value)
 if not event then return false, L.invalidEvent .. ' ' .. value end
 local options = self:Options(id)
 for _, entry in ipairs(options.events) do
  if entry.name == event then return false, L.eventAlreadyAdded end
 end
 options.events[#options.events + 1] = { name = event, enabled = true }
 self:Changed()
 return true
end

function A:RemoveEvent(id, index)
 table.remove(self:Options(id).events, index)
 self:Changed()
end

function A:Run(id, snippet, event, ...)
 -- The debugger owns event delivery for its snapshot; never run the saved script twice.
 if addon.Debugger and ((addon.Debugger.armed and addon.Debugger.scriptId == id) or addon.Debugger.startupOwnedId == id) then return end
 if self.running[id] or not snippet.source:find('%S') then return end
 self.running[id] = true
 if W.db.clearOnRun[id] then Console:Clear() end
 local prefix = '[' .. snippet.name .. '] '
 local environment = self.environments[id]
 if not environment then
  environment = setmetatable({ addon = addon, editor = addon,
  }, { __index = _G })
  self.environments[id] = environment
 end
 environment.print = function(...) Console:Write(prefix, ...) end
 environment.DevTools_Dump = function(value, startKey) Console:Dump(value, startKey, prefix) end
 environment.dump = function(...) Console:DumpArguments(prefix, ...) end
 environment.event = event
 environment.requireHelper = addon.Helpers:Loader({ print = environment.print, dump = environment.dump, DevTools_Dump = environment.DevTools_Dump, event = event })
 local chunk, message
 if _G.loadstring and _G.setfenv then
  chunk, message = _G.loadstring(W:NormalizeSource(snippet.source), '=LuaWorkbench[' .. snippet.name .. ']')
 else message = L.queryLuaUnavailable end
 local ok, stackTrace = false, nil
 if chunk then
  _G.setfenv(chunk, environment)
  -- A closure forwards event arguments on Lua 5.1, preserving nil arguments.
  local arguments = { n = select('#', ...), ... }
  local results = pack(xpcall(function() return chunk(unpack(arguments, 1, arguments.n)) end, function(value)
   if type(_G.debugstack) == 'function' then
    local captured, trace = pcall(_G.debugstack, 2, 20, 20)
    if captured then stackTrace = Console:Format(trace) end
   end
   return Console:Format(value)
  end))
  if results[1] and results.n > 1 then Console:Write(prefix .. 'return', unpack(results, 2, results.n)) end
  ok, message = results[1], results[2]
 end
 if not ok then
  addon.Diagnostics:Record(message, stackTrace, id, snippet.name, event)
  Console:Write(prefix .. L.queryLuaError, message)
 end
 Console:SetStatus(prefix .. (ok and L.queryLuaComplete or (L.queryLuaError .. ' ' .. Console:Format(message))), not ok)
 self.running[id] = nil
end

function A:Dispatch(event, startup, ...)
 local jobs = {}
 for id, snippet in pairs(W.db.snippets) do
  local options = W.db.autoRun[id]
  if options and ((startup and options.startup) or (event == 'PLAYER_LOGIN' and options.login)
   or self:HasEvent(options, event)) then
   jobs[#jobs + 1] = { id = id, name = snippet.name, source = snippet.source }
  end
 end
 table.sort(jobs, function(a, b) return a.id < b.id end)
 for _, job in ipairs(jobs) do self:Run(job.id, job, event, ...) end
end

function A:OnEvent(event, ...)
 local startup = event == 'ADDON_LOADED' and (...) == addonName
 if startup then
  if self.initialized then return end
  W:Initialize()
  self.initialized = true
  self:Refresh()
  W:UpdateMinimap()
  if addon.Debugger then addon.Debugger:RestoreStartup() end
 end
 if not self.initialized then return end
 if addon.Debugger then addon.Debugger:DispatchStartup(event, startup, ...) end
 self:Dispatch(event, startup, ...)
 if event == 'PLAYER_LOGOUT' then
  W:Capture(); W:SaveGeometry('window'); W:SaveGeometry('minibar')
  if W.db.options.restoreDrafts == false then W:DiscardSessionDrafts() end
 end
end

function A:SetOption(key, value)
 if not W.current then return end
 self:Options(W.current)[key] = value
 self:Changed()
end

function A:UpdateControls()
 if not self.controls or not W.current then return end
 local options = self:Options(W.current)
 local summary = self:Summary(W.current)
 self.summary:SetText(summary ~= '' and (L.automaticRun .. ': ' .. summary) or '')
 self.name:SetText(((W.currentName or L.newSnippet):gsub('|', '||')))
 if self.controlID ~= W.current then
  self.controlID = W.current
  self.controls.event:ClearFocus()
  self.controls.event:SetText('')
  self.error:SetText('')
  self.panel:Hide()
 end
 for _, key in ipairs({ 'startup', 'login' }) do self.controls[key]:SetChecked(options[key] == true) end
 W.clearOnRun:SetChecked(W.db.clearOnRun[W.current] == true)
 W:UpdateClearOnRunIndicator()
 self.notice:SetText(W.db.snippets[W.current] and L.savedCodeOnly or L.saveBeforeAutoRun)
 addon.Helpers:UpdateControls()
 if self.panel:IsShown() then self:UpdateEventRows() end
end

function A:UpdateEventRows()
 local events = self:Options(W.current).events
 for index, entry in ipairs(events) do
  local row = self.eventRows[index]
  if not row then
   row = UI:Check(self.content, '', function(button)
    local current = self:Options(W.current).events[index]
    current.enabled = button:GetChecked() == true
    self:Changed()
   end)
   row:SetHeight(28)
   row.remove = UI:Button(row, 'close', L.removeEvent, function() self:RemoveEvent(W.current, index) end)
   row.remove:SetPoint('RIGHT'); row.remove:SetSize(24, 24)
   row.label:SetPoint('RIGHT', -30, 0)
   self.eventRows[index] = row
  end
  row:SetPoint('TOPLEFT', 0, -self.eventsTop - (index - 1) * 30)
  row:SetPoint('TOPRIGHT', 0, -self.eventsTop - (index - 1) * 30)
  row.label:SetText(entry.name); row:SetChecked(entry.enabled == true); row:Show()
 end
 for index = #events + 1, #self.eventRows do self.eventRows[index]:Hide() end
 local y = self.eventsTop + #events * 30 + 16
 self.outputHeading:SetPoint('TOPLEFT', 0, -y)
 W.clearOnRun:SetPoint('TOPLEFT', 0, -y - 24)
 y = addon.Helpers:LayoutControls(y + 64)
 self.notice:SetPoint('TOPLEFT', 0, -y)
 self.content:SetHeight(y + self.notice:GetStringHeight() + 16)
 self.scroll:UpdateScrollChildRect()
end

function A:Toggle(owner)
 W:HidePanels(self.panel)
 if self.panel:IsShown() and self.owner == owner then self.panel:Hide(); return end
 if W.optionsFrame then W.optionsFrame:Hide() end
 if W.syntaxFrame then W.syntaxFrame:Hide() end
 if addon.Diagnostics.panel then addon.Diagnostics.panel:Hide() end
 if W.helpFrame then W.helpFrame:Hide() end
 if W.contextMenu then W.contextMenu:Hide() end
 Console.input:ClearFocus()
 self.owner = owner
 self.panel:SetSize(math.min(420, W.window:GetWidth() - 32), math.min(520, W.window:GetHeight() - 70))
 self.panel:ClearAllPoints(); self.panel:SetPoint('TOPLEFT', self.gear, 'BOTTOMLEFT', 0, -4)
 self.panel:RestorePanelPosition()
 self.content:SetWidth(self.panel:GetWidth() - 42)
 self:UpdateControls()
 self.panel:Show()
 self:UpdateEventRows()
 self.scroll:SetVerticalScroll(0)
end

function A:BuildControls(parent)
 self.gear = UI:Button(parent, 'options', L.scriptSettings, function() self:Toggle(self.gear) end)
 self.gear:SetPoint('TOPLEFT', 6, -2)
 W.saveCurrentButton = UI:Button(parent, 'save', L.save .. addon.ShortcutText('  (Ctrl+S)'), function() W:Save() end)
 W.saveCurrentButton:SetPoint('LEFT', self.gear, 'RIGHT', 2, 0)
 self.name = UI:Text(parent, '', 12)
 self.name:SetPoint('TOPLEFT', 80, -10); self.name:SetPoint('TOPRIGHT', -178, -10)
 self.name:SetHeight(14); self.name:SetWordWrap(false)
 self.summary = UI:Text(parent, '', 10)
 self.summary:SetPoint('TOPLEFT', parent, 'TOP', 0, -34); self.summary:SetPoint('TOPRIGHT', -12, -34)
 self.summary:SetJustifyH('RIGHT'); self.summary:SetHeight(14); self.summary:SetWordWrap(false)
 self.summary:SetTextColor(0.55, 0.76, 1)
 local panel = CreateFrame('Frame', 'LuaWorkbenchScriptSettings', W.window)
 self.panel = panel
 UI:MovablePanel(panel, 'scriptSettings')
 panel:SetFrameLevel(W.window:GetFrameLevel() + 40); panel:SetClampedToScreen(true); panel:EnableMouse(true)
 UI:Background(panel, { 0.09, 0.11, 0.15, 1 })
 UI:Border(panel, { 0.28, 0.34, 0.43, 1 })
 _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchScriptSettings'
 local title = UI:Text(panel, L.scriptSettings, 15); title:SetPoint('TOPLEFT', 14, -14)
 local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -5, -6)
 self.scroll = UI:Scroll(panel); self.scroll:SetPoint('TOPLEFT', 16, -48); self.scroll:SetPoint('BOTTOMRIGHT', -22, 14)
 local content = CreateFrame('Frame', nil, self.scroll); self.content = content
 self.scroll:SetScrollChild(content)
 self.controls, self.eventRows = {}, {}
 local y = 0
 local function text(value, size, gap)
  local label = UI:Text(content, value, size)
  label:SetPoint('TOPLEFT', 0, -y); label:SetWidth(370); label:SetWordWrap(true)
  y = y + math.max(16, label:GetStringHeight()) + (gap or 12)
  return label
 end
 text(L.automaticRun, 13)
 for _, item in ipairs({ { 'startup', L.runOnStartup, L.startupDescription }, { 'login', L.runOnLogin, L.loginDescription } }) do
  local key = item[1]
  local control = UI:Check(content, item[2], function(button) self:SetOption(key, button:GetChecked() == true) end)
  control:SetPoint('TOPLEFT', 0, -y); control:SetPoint('TOPRIGHT', 0, -y)
  self.controls[key] = control; y = y + 27
  text(item[3], 11, 16)
 end
 text(L.customEvents, 13)
 local input = CreateFrame('EditBox', nil, content); self.controls.event = input
 input:SetAutoFocus(false); input:SetFontObject(GameFontHighlightSmall); input:SetTextInsets(7, 7, 0, 0)
 input:SetHeight(26); input:SetMaxLetters(100)
 input:SetPoint('TOPLEFT', 0, -y); input:SetPoint('TOPRIGHT', -32, -y)
 UI:Background(input, UI.colors.hover); UI:Tooltip(input, L.customEventHelp)
 local hint = UI:Text(input, L.eventName, 11); hint:SetPoint('LEFT', 7, 0); hint:SetTextColor(0.5, 0.57, 0.68)
 input:SetScript('OnTextChanged', function() hint:SetShown(input:GetText() == ''); self.error:SetText('') end)
 local function add()
  if not W.current or input:GetText() == '' then return end
  local ok, message = self:AddEvent(W.current, input:GetText())
  self.error:SetText(message or '')
  if ok then input:SetText(''); input:SetFocus() end
 end
 self.addButton = UI:Button(content, 'new', L.addEvent, add)
 self.addButton:SetPoint('TOPRIGHT', 0, -y); self.addButton:SetSize(28, 26)
 input:SetScript('OnEnterPressed', add)
 input:SetScript('OnEscapePressed', function() input:ClearFocus(); panel:Hide() end)
 input:SetScript('OnKeyDown', function(_, key) W:RunShortcut(key) end)
 input:SetScript('OnKeyUp', function(_, key) if key == 'F5' then W.f5Held = nil end end)
 y = y + 30
 self.error = text('', 11, 8); self.error:SetTextColor(1, 0.4, 0.4); self.error:SetHeight(30)
 y = y + 14
 self.eventsTop = y
 self.outputHeading = UI:Text(content, L.queryLuaOutput, 13)
 W.clearOnRun = UI:Check(content, L.clearOnRun, function(button)
  if W.current then W.db.clearOnRun[W.current] = button:GetChecked() == true end
  W:UpdateClearOnRunIndicator()
 end)
 W.clearOnRun:SetPoint('RIGHT', content, 'RIGHT', 0, 0)
 addon.Helpers:BuildControls(content)
 self.notice = UI:Text(content, '', 11); self.notice:SetWidth(370); self.notice:SetWordWrap(true)
 panel:SetScript('OnHide', function() input:ClearFocus(); addon.Helpers.name:ClearFocus(); GameTooltip:Hide() end)
 panel:SetScript('OnUpdate', function()
  if IsMouseButtonDown() and not panel:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then panel:Hide() end
 end)
 panel:Hide()
 self:UpdateControls()
end

A.frame = CreateFrame('Frame')
A.frame:RegisterEvent('ADDON_LOADED')
A.frame:SetScript('OnEvent', function(_, event, ...) A:OnEvent(event, ...) end)
