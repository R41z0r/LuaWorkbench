local _, addon = ...
local P, W, UI, L, C = {}, addon.Workspace, addon.UI, addon.L, addon.Query.Console
addon.DebugProbe = P
P.queue, P.dropped, P.generation = {}, 0, 0

function P:Refresh()
 if not self.panel then return end
 self.panel.status:SetText((self.status or L.debugProbeWaiting) .. '\n' .. string.format(L.debugProbeQueue, #self.queue)
  .. (self.dropped > 0 and ('\n' .. string.format(L.debugProbeOverflow, self.dropped)) or ''))
 self.panel.step:SetEnabled(self.paused == true)
end

local function secret(value) return _G.issecretvalue and _G.issecretvalue(value) end
local function scalar(value)
 if secret(value) then return '<secret>' end
 local kind = type(value)
 if kind == 'string' or kind == 'number' or kind == 'boolean' or kind == 'nil' then return C:Format(value):sub(1, 180) end
 return '<' .. kind .. '>'
end
local function preview(value, full)
 local seen, budget = {}, 32
 local function atom(item)
  if secret(item) then return '<secret>' end
  local kind = type(item)
  if kind ~= 'string' and kind ~= 'number' and kind ~= 'boolean' and kind ~= 'nil' then return '<' .. kind .. '>' end
  local text = tostring(item):gsub('\t', '    ')
  if not full and #text > 240 then text = text:sub(1, 240) .. '...' end
  return text
 end
 -- Iterative traversal avoids a Lua stack overflow for deeply nested tables.
 local output, stack = {}, { { value = value, depth = 0 } }
 while #stack > 0 do
  local node = stack[#stack]
  if node.open then
   local ok, key, item = pcall(next, node.value, node.key)
   if not ok or secret(key) then
    output[#output + 1] = ok and '<secret>' or '<unavailable>'
    output[#output + 1] = ' }'; table.remove(stack)
   elseif key == nil then
    output[#output + 1] = ' }'; table.remove(stack)
   elseif not full and budget <= 0 then
    output[#output + 1] = '... }'; table.remove(stack)
   else
    node.key = key
    budget = budget - 1
    output[#output + 1] = (node.count > 0 and ',' or '') .. '\n' .. string.rep(' ', math.min(node.depth + 1, 20) * 2) .. atom(key) .. ' = '
    node.count = node.count + 1
    stack[#stack + 1] = { value = item, depth = node.depth + 1 }
   end
  elseif secret(node.value) or type(node.value) ~= 'table' then
   output[#output + 1] = atom(node.value); table.remove(stack)
  elseif seen[node.value] then
   output[#output + 1] = '<reference>'; table.remove(stack)
  elseif not full and node.depth >= 3 then
   output[#output + 1] = '{ ... }'; table.remove(stack)
  else
   seen[node.value] = true; node.open, node.count = true, 0
   output[#output + 1] = '{ '
  end
 end
 local text = table.concat(output)
 if not full and #text > 2400 then text = text:sub(1, 2400) .. '\n...' end
 return text
end

function P:FormatPreview(value) return preview(value) end
function P:FormatScalar(value) return scalar(value) end

function P:SecretTooltip(tooltip, label, value)
 if type(value) == 'number' then
  tooltip:SetText(label, 0.85, 0.9, 1)
  -- Format only in the native text sink; never convert or inspect the secret.
  local name = tooltip:GetName()
  local line = name and _G[name .. 'TextLeft1']
  if line then pcall(line.SetFormattedText, line, '%s %s', label, value) end
 else
  local ok = pcall(function() tooltip:SetText(label .. ' ' .. value, 0.85, 0.9, 1) end)
  if not ok then tooltip:SetText(label, 0.85, 0.9, 1) end
 end
end

function P:CaptureVariables(values)
 self.variables = {}
 if not secret(values) and type(values) == 'table' then
  local key
  for _ = 1, 8 do
   local ok, nextKey, value = pcall(next, values, key)
   if not ok or secret(nextKey) then break end
   if nextKey == nil then break end
   key = nextKey
   self.variables[#self.variables + 1] = { name = scalar(key), value = scalar(value), preview = preview(value), hasSecretText = secret(value) and (type(value) == 'string' or type(value) == 'number'), secretText = value }
  end
 end
 for index, row in ipairs(self.variableRows or {}) do
  local item = self.variables[index]
  if item then
   row.text:SetText((item.name .. ' = ' .. item.value):gsub('|', '||'))
   row.preview = (item.name .. ' = ' .. item.preview):gsub('|', '||')
   row.secretLabel = item.name:gsub('|', '||') .. ' = |cff88ff88<secret>|r'
   row.hasSecretText, row.secretText = item.hasSecretText, item.secretText
  end
  if not item then row.hasSecretText, row.secretText, row.secretLabel = nil, nil, nil end
  row:SetShown(item ~= nil)
 end
end

function P:ValidateBindings()
 local source = self.checkpointBindings
 if secret(source) then error(L.debugProbeBindingsError, 0) end
 if source == nil then return {} end
 if type(source) ~= 'table' then error(L.debugProbeBindingsError, 0) end
 local bindings, key = {}, nil
 while true do
  local name, item = next(source, key)
  if secret(name) then error(L.debugProbeBindingsError, 0) end
  if name == nil then break end
  key = name
  if type(name) ~= 'string' or not name:match('^[%a_][%w_]*$') or secret(item) or type(item) ~= 'table' then error(L.debugProbeBindingsError, 0) end
  local getter, setter = rawget(item, 'get'), rawget(item, 'set')
  if secret(getter) or secret(setter) or type(getter) ~= 'function' or (setter ~= nil and type(setter) ~= 'function') then error(L.debugProbeBindingsError, 0) end
  bindings[name] = { get = getter, set = setter }
 end
 return bindings
end

function P:RefreshBoundVariables(token, bindings, overlay, written)
 local display = {}
 if not secret(self.capturedValues) and type(self.capturedValues) == 'table' then
  local key
  for _ = 1, 8 do
   local ok, name, value = pcall(next, self.capturedValues, key)
   if not ok then break end
   if secret(name) or name == nil then break end
   key = name; display[name] = value
  end
 end
 for key in pairs(written or {}) do display[key] = overlay[key] end
 local count = 0
 for name, binding in pairs(bindings) do
  if count == 8 then break end
  count = count + 1
  local ok, value = pcall(binding.get)
  if self.evalToken ~= token or not self.paused then return end
  -- Nil remains visible in the inspector even though Lua tables cannot store it.
  if not ok then display[name] = L.debugProbeError
  elseif secret(value) then display[name] = value
  elseif value == nil then display[name] = 'nil'
  else display[name] = value end
 end
 self:CaptureVariables(display)
end

function P:ClearEvaluation()
 self.capturedValues, self.invocationEnvironment, self.evaluationEnvironment, self.evalToken = nil, nil, nil, nil
 self.checkpointBindings, self.liveBindings, self.evalOverlay, self.evalWritten = nil, nil, nil, nil
end

function P:TerminalWrite(...)
 self.terminalLines = self.terminalLines or {}
 local parts = {}
 for index = 1, select('#', ...) do parts[index] = preview(select(index, ...), true) end
 local text = table.concat(parts, '    '):gsub('|', '||')
 for line in (text .. '\n'):gmatch('(.-)\n') do
  self.terminalLines[#self.terminalLines + 1] = line
  if #self.terminalLines > 100 then table.remove(self.terminalLines, 1) end
 end
 if self.terminal then
  local joined = table.concat(self.terminalLines, '\n')
  self.terminal.output:SetText(joined)
  if self.terminal.output.SetCursorPosition then self.terminal.output:SetCursorPosition(#joined) end
  local scroll = self.terminal.output.scrollFrame
  if scroll then scroll:UpdateScrollChildRect(); scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end
 end
end

function P:TerminalDump(value, startKey)
 C:Dump(value, startKey, nil, function(text)
  if secret(text) or type(text) ~= 'string' then self:TerminalWrite(text); return end
  -- Strip native dump colors before escaping plain terminal text. Decode
  -- escaped pipes once so literal color-like strings remain literal.
  local parts, cursor = {}, 1
  while cursor <= #text do
   local at = text:find('|', cursor, true)
   if not at then parts[#parts + 1] = text:sub(cursor); break end
   parts[#parts + 1] = text:sub(cursor, at - 1)
   local pair = text:sub(at, at + 1)
   if pair == '||' then parts[#parts + 1] = '|'; cursor = at + 2
   elseif pair == '|r' then cursor = at + 2
   elseif text:sub(at, at + 9):match('^|c%x%x%x%x%x%x%x%x$') then cursor = at + 10
   else parts[#parts + 1] = '|'; cursor = at + 1 end
  end
  self:TerminalWrite(table.concat(parts))
 end)
end

function P:ShowTerminal()
 if not self.terminal then
  local panel = CreateFrame('Frame', nil, UIParent)
  self.terminal = panel
  panel:SetSize(560, 330); panel:SetPoint('CENTER'); panel:SetFrameStrata('DIALOG'); panel:SetClampedToScreen(true)
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag('LeftButton')
  panel:SetScript('OnDragStart', function() panel:StartMoving() end)
  panel:SetScript('OnDragStop', function() panel:StopMovingOrSizing() end)
  UI:Background(panel, UI.colors.panel)
  local title = UI:Text(panel, L.debugProbeTerminal, 14); title:SetPoint('TOPLEFT', 12, -12)
  panel.help = UI:Button(panel, '?', L.debugProbeTerminalHelp, function() end)
  panel.help:SetPoint('LEFT', title, 'RIGHT', 4, 0); panel.help:SetSize(22, 22)
  local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -3, -3)
  panel.output = UI:Editor(panel, L.queryLuaOutput, true)
  panel.output.frame:SetPoint('TOPLEFT', 8, -36); panel.output.frame:SetPoint('BOTTOMRIGHT', -8, 70)
  if panel.output.scrollFrame then
   panel.output.scrollFrame:HookScript('OnScrollRangeChanged', function(scroll)
    scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
   end)
  end
  panel.input = CreateFrame('EditBox', nil, panel); panel.input:SetAutoFocus(false); panel.input:SetFontObject(ChatFontNormal)
  panel.input:SetTextInsets(8, 8, 0, 0); panel.input:SetMaxLetters(4000)
  panel.input:SetHistoryLines(100); panel.input:SetAltArrowKeyMode(true)
  panel.input:SetPoint('BOTTOMLEFT', 12, 32); panel.input:SetPoint('BOTTOMRIGHT', -12, 32); panel.input:SetHeight(28)
  UI:Background(panel.input, UI.colors.hover)
  panel.input:SetScript('OnEnterPressed', function(box)
   self:Evaluate(box:GetText())
   box:SetText('')
  end)
  panel.input:SetScript('OnEscapePressed', function(box) box:ClearFocus() end)
  local hint = UI:Text(panel, L.debugProbeInput, 11); hint:SetPoint('BOTTOMLEFT', 12, 12)
  panel:SetScript('OnHide', function() panel.input:ClearFocus(); panel:StopMovingOrSizing() end)
 end
 self.terminal.output:SetText(table.concat(self.terminalLines or {}, '\n'))
 self.terminal:Show(); self.terminal.input:SetFocus()
 local scroll = self.terminal.output.scrollFrame
 if scroll then scroll:UpdateScrollChildRect(); scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end
end

function P:Evaluate(source)
 if self.evaluating or not self.paused or not self.thread or not self.evalToken then self:TerminalWrite(L.debugProbeNotPaused); return false end
 if type(source) ~= 'string' or not source:find('%S') then return false end
 if self.terminal then self.terminal.input:AddHistoryLine(source) end
 self:TerminalWrite('> ' .. source)
 local token, generation = self.evalToken, self.generation
 local function active() return self.paused and self.thread and self.evalToken == token and self.generation == generation end
 if not self.evaluationEnvironment then
  local ok, bindings = pcall(self.ValidateBindings, self)
  if not ok then self:TerminalWrite(L.debugProbeBindingsError); return false end
  local overlay, written = {}, {}
  self.liveBindings, self.evalOverlay, self.evalWritten = bindings, overlay, written
  local function output(...) if active() then self:TerminalWrite(...) end end
  local function dump(...)
   if not active() then return end
   local count = select('#', ...)
   for index = 1, count do local value = select(index, ...); self:TerminalDump(value, count > 1 and ('arg[' .. index .. ']') or nil) end
  end
  local builtins = { print = output, dump = dump,
   DevTools_Dump = function(value, startKey) if active() then self:TerminalDump(value, startKey) end end,
   breakpoint = function() error(L.debugProbeTerminalHelp, 0) end }
  local environment = setmetatable({}, {
   __index = function(_, key)
    if not active() then error(L.debugProbeNotPaused, 0) end
    if bindings[key] then return bindings[key].get() end
    if written[key] then return overlay[key] end
    if builtins[key] then return builtins[key] end
    if not secret(self.capturedValues) and type(self.capturedValues) == 'table' then
     local value = rawget(self.capturedValues, key)
     if secret(value) then return value end
     if value ~= nil then return value end
    end
    return self.invocationEnvironment and self.invocationEnvironment[key]
   end,
   __newindex = function(_, key, value)
    if not active() then error(L.debugProbeNotPaused, 0) end
    if bindings[key] then
     if not bindings[key].set then error(L.debugProbeReadOnly .. ': ' .. key, 0) end
     bindings[key].set(value)
    else written[key], overlay[key] = true, value end
   end,
  })
  self.evaluationEnvironment = environment
 end
 local chunk, failure = _G.loadstring('return ' .. source, '=LuaWorkbench debug terminal')
 if not chunk then chunk, failure = _G.loadstring(source, '=LuaWorkbench debug terminal') end
 if not chunk then self:TerminalWrite(L.debugProbeError, failure); return false end
 _G.setfenv(chunk, self.evaluationEnvironment)
 local function pack(...) return { n = select('#', ...), ... } end
 self.evaluating = token
 local result = pack(pcall(chunk))
 if active() then pcall(self.RefreshBoundVariables, self, token, self.liveBindings, self.evalOverlay, self.evalWritten) end
 self.evaluating = nil
 if not active() then self:TerminalWrite(L.debugProbeNotPaused); return false end
 if not result[1] then self:TerminalWrite(L.debugProbeError, result[2]); return false end
 if result.n > 1 then self:TerminalWrite(unpack(result, 2, result.n)) end
 return true
end

function P:ShowSnapshot()
 if not self.source then return end
 if not self.snapshot then
  local panel = CreateFrame('Frame', nil, UIParent)
  self.snapshot = panel
  panel:SetSize(650, 440); panel:SetPoint('CENTER'); panel:SetFrameStrata('DIALOG'); panel:SetClampedToScreen(true)
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag('LeftButton')
  panel:SetScript('OnDragStart', function() panel:StartMoving() end)
  panel:SetScript('OnDragStop', function() panel:StopMovingOrSizing() end)
  UI:Background(panel, UI.colors.panel)
  local title = UI:Text(panel, L.debugProbeSnapshot, 11)
  title:SetPoint('TOPLEFT', 12, -10); title:SetPoint('TOPRIGHT', -36, -10); title:SetHeight(42); title:SetWordWrap(true)
  local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -3, -3)
  panel.code = UI:Editor(panel, L.debugProbeShow, true)
  panel.code.frame:SetPoint('TOPLEFT', 8, -58); panel.code.frame:SetPoint('BOTTOMRIGHT', -8, 8)
 end
 self.snapshot.code:SetText(self.source)
 self.snapshot:Show()
 if self.line and self.snapshot.code.SetCursorPosition then
  local offset = 0
  for _ = 2, self.line do local stop = self.source:find('\n', offset + 1, true); if not stop then break end; offset = stop end
  self.snapshot.code:SetCursorPosition(offset)
  self.snapshot.code:HighlightText(offset, (self.source:find('\n', offset + 1, true) or (#self.source + 1)) - 1)
 end
end

function P:BuildPanel()
 if self.panel then self.panel:Show(); return end
 local panel = CreateFrame('Frame', nil, UIParent)
 self.panel = panel
 panel:SetSize(430, 450); panel:SetPoint('CENTER'); panel:SetFrameStrata('DIALOG'); panel:SetClampedToScreen(true)
 panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag('LeftButton')
 panel:SetScript('OnDragStart', function() panel:StartMoving() end)
 panel:SetScript('OnDragStop', function() panel:StopMovingOrSizing() end)
 UI:Background(panel, UI.colors.panel); UI:Border(panel, { 0.35, 0.55, 0.7, 1 })
 local title = UI:Text(panel, L.debugProbeTitle, 14); title:SetPoint('TOPLEFT', 12, -12)
 panel.status = UI:Text(panel, '', 12); panel.status:SetPoint('TOPLEFT', 12, -40); panel.status:SetWidth(356); panel.status:SetHeight(80)
 panel.status:SetWordWrap(true)
 panel.step = UI:Action(panel, 'next', L.debugProbeStep, L.debugProbeHelp, function() self:Step() end)
 panel.step:SetPoint('TOPLEFT', 12, -126)
 local show = UI:Action(panel, 'copy', L.debugProbeShow, L.debugProbeHelp, function() self:ShowSnapshot() end)
 show:SetPoint('TOPLEFT', 12, -162)
 local terminal = UI:Action(panel, '{}', L.debugProbeTerminal, L.debugProbeTerminalHelp, function() self:ShowTerminal() end)
 terminal:SetPoint('LEFT', show, 'RIGHT', 8, 0)
 local stop = UI:Action(panel, 'clear', L.debugProbeStop, L.debugProbeHelp, function() self:Stop() end)
 stop:SetPoint('BOTTOMRIGHT', -12, 12)
 local variables = UI:Text(panel, L.debugProbeVariables, 12); variables:SetPoint('TOPLEFT', 12, -205)
 self.variableRows = {}
 for index = 1, 8 do
  local row = CreateFrame('Button', nil, panel)
  row:SetSize(404, 22); row:SetPoint('TOPLEFT', 12, -225 - (index - 1) * 22)
  row.text = UI:Text(row, '', 11); row.text:SetAllPoints(); row.text:SetWordWrap(false)
  row:SetScript('OnEnter', function()
   GameTooltip:SetOwner(row, 'ANCHOR_CURSOR'); GameTooltip:ClearLines()
   if row.hasSecretText then
    self:SecretTooltip(GameTooltip, row.secretLabel, row.secretText)
   else GameTooltip:AddLine((row.preview or ''):gsub('<secret>', '|cff88ff88<secret>|r'), 0.85, 0.9, 1, true) end
   GameTooltip:Show()
  end)
  row:SetScript('OnLeave', function() GameTooltip:Hide() end)
  row:Hide(); self.variableRows[index] = row
 end
 UI:KeyboardPropagation(panel, true, true)
 panel:SetScript('OnKeyDown', function(_, key)
  if UI:InCombat() then UI:KeyboardPropagation(panel, true); return end
  local input = C.input and C.input.editBox
  local focused = panel:IsMouseOver() or (W.window and W.window:IsShown() and input and input:HasFocus())
  local modified = (_G.IsControlKeyDown and _G.IsControlKeyDown()) or (_G.IsShiftKeyDown and _G.IsShiftKeyDown())
   or (_G.IsAltKeyDown and _G.IsAltKeyDown()) or (_G.IsMetaKeyDown and _G.IsMetaKeyDown())
  local consume = key == 'F10' and self.paused and focused and not modified
  UI:KeyboardPropagation(panel, not consume)
  if consume and not self.held then self.held = true; self:Step() end
 end)
 panel:SetScript('OnKeyUp', function(_, key) if key == 'F10' then self.held = nil end; UI:KeyboardPropagation(panel, true) end)
 panel:SetScript('OnHide', function() self.held = nil; UI:KeyboardPropagation(panel, true) end)
end

function P:Stop()
 self.generation = self.generation + 1
 if self.events then self.events:UnregisterAllEvents() end
 self.thread, self.paused, self.running, self.armed = nil, nil, nil, nil
 self.queue, self.held = {}, nil
 self:ClearEvaluation()
 if self.terminal then self.terminal:Hide() end
 self:CaptureVariables(nil)
 if self.panel then self.panel:Hide() end
 if self.snapshot then self.snapshot:Hide() end
end

function P:Fail(value)
 self:ClearEvaluation()
 self.status = L.debugProbeError .. ': ' .. C:Format(value)
 C:Write(self.status)
 self.thread, self.paused = nil, nil
 self:CaptureVariables(nil)
 self:Refresh()
end

function P:Resume(...)
 local thread = self.thread
 local ok, value = coroutine.resume(thread, ...)
 if self.thread ~= thread then return end
 if not ok then self:Fail(value)
 elseif coroutine.status(self.thread) == 'dead' then
  self.thread, self.paused = nil, nil
  self:CaptureVariables(nil)
  self:ClearEvaluation()
  self.status = L.debugProbeFinished
 elseif not (_G.issecretvalue and _G.issecretvalue(value)) and value == self.checkpoint then
  self.paused = true
  local valid, bindings = pcall(self.ValidateBindings, self)
  if valid then
   self.evaluating = self.evalToken
   pcall(self.RefreshBoundVariables, self, self.evalToken, bindings)
   self.evaluating = nil
  else self:TerminalWrite(L.debugProbeBindingsError) end
 else self:Fail(L.debugProbeHelp) end
 self:Refresh()
end

function P:StartInvocation(item)
 local chunk, failure = _G.loadstring(self.source, '=LuaWorkbench debugger test')
 if not chunk then self:Fail(failure); return end
 local generation = self.generation
 local function current() return self.armed and self.generation == generation and coroutine.running() == self.thread end
 local function output(...)
  if self.generation == generation and self.evaluating and self.evaluating == self.evalToken then self:TerminalWrite(...)
  elseif current() then C:Write(...) end
 end
 local function devtools(value, startKey)
  if self.generation == generation and self.evaluating and self.evaluating == self.evalToken then self:TerminalDump(value, startKey)
  elseif current() then C:Dump(value, startKey) end
 end
 local function dump(...)
  local count = select('#', ...)
  for index = 1, count do local value = select(index, ...); devtools(value, count > 1 and ('arg[' .. index .. ']') or nil) end
 end
 local environment
 environment = setmetatable({ addon = addon, editor = addon, event = item.event, print = output,
  dump = dump, DevTools_Dump = devtools,
  requireHelper = function() error(L.debugProbeHelp, 0) end,
  breakpoint = function(label, values, bindings)
   if not current() then error(L.debugProbeError, 0) end
   self.status = L.debugProbePaused .. ': ' .. C:Format(label)
   self.line = nil
   if _G.debugstack then
    local ok, stack = pcall(_G.debugstack, 2, 3, 0)
    if ok and not secret(stack) and type(stack) == 'string' then self.line = tonumber(stack:match('LuaWorkbench debugger test:(%d+)')) end
   end
   self.invocationEnvironment = environment
   self.capturedValues, self.evalToken, self.evaluationEnvironment = values, {}, nil
   self.checkpointBindings, self.liveBindings, self.evalOverlay, self.evalWritten = bindings, nil, nil, nil
   self:CaptureVariables(values)
   self:Refresh()
   return coroutine.yield(self.checkpoint)
  end,
 }, { __index = _G })
 self.invocationEnvironment = environment
 _G.setfenv(chunk, environment)
 self.thread = coroutine.create(chunk)
 self:Resume(unpack(item.args, 1, item.args.n))
end

function P:Pump()
 if self.running or self.thread or not self.armed then return end
 self.running = true
 while self.armed and not self.thread and #self.queue > 0 do
  self:StartInvocation(table.remove(self.queue, 1))
 end
 self.running = nil
 self:Refresh()
end

function P:Enqueue(event, ...)
 if not self.armed or event ~= self.event then return false end
 if #self.queue >= 50 then self.dropped = self.dropped + 1; self:Refresh(); return false end
 self.queue[#self.queue + 1] = { event = event, args = { n = select('#', ...), ... } }
 self:Pump()
 self:Refresh()
 return true
end

function P:Step()
 if self.evaluating then return false end
 if not self.paused or not self.thread then return false end
 self.paused = nil
 self:ClearEvaluation()
 self:Resume()
 self:Pump()
 return true
end

function P:Arm(event)
 self:Stop()
 self.terminalLines = {}
 if self.terminal then self.terminal.output:SetText('') end
 W:Show()
 self:BuildPanel()
 self.source = W:NormalizeSource(C.input:GetText())
 self.scriptId = W.current
 self.dropped, self.checkpoint = 0, {}
 self:CaptureVariables(nil)
 if not (_G.coroutine and coroutine.create and coroutine.resume and coroutine.yield and _G.loadstring and _G.setfenv) then
  self:Fail(L.debugProbeHelp); return false
 end
 local chunk, failure = _G.loadstring(self.source, '=LuaWorkbench debugger test')
 if not chunk then self:Fail(failure); return false end
 event = type(event) == 'string' and event:match('^%s*([%u%d_]+)%s*$') or nil
 if not event then self:Fail(L.invalidEvent); return false end
 if not self.events then
  self.events = CreateFrame('Frame')
  self.events:SetScript('OnEvent', function(_, name, ...) self:Enqueue(name, ...) end)
 end
 local ok, result = pcall(self.events.RegisterEvent, self.events, event)
 if not ok or result == false then self.events:UnregisterAllEvents(); self:Fail(L.invalidEvent); return false end
 self.event, self.armed, self.status = event, true, L.debugProbeWaiting
 self:Refresh()
 return true
end

_G.SLASH_LUAWORKBENCHDEBUG1 = '/lwdebug'
_G.SlashCmdList.LUAWORKBENCHDEBUG = function(message)
 local command = (message or ''):match('^%s*(.-)%s*$')
 if command == 'stop' then P:Stop()
 elseif command == 'step' then P:Step()
 elseif command:match('^eval%s') then P:ShowTerminal(); P:Evaluate(command:match('^eval%s+(.*)$'))
 elseif command == 'fire' then if P.armed then P:Enqueue(P.event) end
 elseif command == '' then C:Write(L.debugProbeHelp)
 else P:Arm(command) end
end
