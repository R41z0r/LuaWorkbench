local _, addon = ...
local D, P, C, L = {}, addon.DebugProbe, addon.Query.Console, addon.L
addon.Debugger = D
for name, method in pairs(P) do if type(method) == 'function' then D[name] = method end end
D.queue, D.breakpoints, D.breakpointSources, D.generation, D.dropped = {}, {}, {}, 0, 0
local function secret(value) return _G.issecretvalue and _G.issecretvalue(value) end

function D:Refresh()
 if addon.DebugUI then addon.DebugUI:Refresh() end
end

local function lineStarts(source)
 local starts = { 0 }
 for offset in source:gmatch('()\n') do starts[#starts + 1] = offset end
 return starts
end
local function lineAt(starts, offset)
 local low, high = 1, #starts
 while low < high do
  local middle = math.floor((low + high + 1) / 2)
  if starts[middle] <= offset then low = middle else high = middle - 1 end
 end
 return low
end

function D:RemapBreakpoints(points, previous, source, edit)
 local mapped = {}
 if previous == source or type(previous) ~= 'string' then
  for line in pairs(points) do mapped[line] = true end
  return mapped
 end
 -- Removing a single newline joins two surviving lines; it is not deletion
 -- of the lower line's breakpoint, even when that line was empty.
 local joinAt = edit and edit.joinAt
 if type(joinAt) == 'number' and edit.oldSource == previous and joinAt >= 0
  and previous:sub(joinAt+1,joinAt+1) == '\n'
  and source == previous:sub(1,joinAt)..previous:sub(joinAt+2) then
  local joinedLine = lineAt(lineStarts(previous), joinAt)
  for line in pairs(points) do mapped[line > joinedLine and line-1 or line] = true end
  return mapped
 end
 local prefix, oldLength, newLength = 0, #previous, #source
 local limit = math.min(oldLength, newLength)
 while prefix < limit and previous:byte(prefix + 1) == source:byte(prefix + 1) do prefix = prefix + 1 end
 local suffix = 0
 while suffix < limit - prefix and previous:byte(oldLength - suffix) == source:byte(newLength - suffix) do suffix = suffix + 1 end
 -- A native Enter amid identical blank lines is otherwise indistinguishable
 -- from insertion at the end of their common prefix. The pre-key cursor pins it.
 local cursor = edit and edit.oldCursor
 if type(cursor) == 'number' and cursor >= 0 and cursor <= oldLength and newLength > oldLength
  and (not edit.oldSource or edit.oldSource == previous)
  and previous:sub(1, cursor) == source:sub(1, cursor)
  and previous:sub(cursor + 1) == source:sub(cursor + newLength - oldLength + 1) then
  prefix, suffix = cursor, oldLength - cursor
 end
 local oldEnd, newEnd = oldLength - suffix, newLength - suffix
 local oldStarts, newStarts = lineStarts(previous), lineStarts(source)
 local deletedFirst, deletedLast
 if #newStarts < #oldStarts then
  local function textAt(text, starts, line) return text:sub(starts[line] + 1, (starts[line + 1] or (#text + 1)) - 1) end
  local first = 1
  while first <= #newStarts and textAt(previous, oldStarts, first) == textAt(source, newStarts, first) do first = first + 1 end
  local oldLast, nextLast = #oldStarts, #newStarts
  while nextLast >= first and textAt(previous, oldStarts, oldLast) == textAt(source, newStarts, nextLast) do oldLast, nextLast = oldLast - 1, nextLast - 1 end
  if nextLast < first then deletedFirst, deletedLast = first, oldLast end
 end
 local oldFirst, newFirst = lineAt(oldStarts, prefix), lineAt(newStarts, prefix)
 local newLast = lineAt(newStarts, newEnd)
 local unique, counts = {}, {}
 for line = newFirst, newLast do
  local text = source:sub(newStarts[line] + 1, (newStarts[line + 1] or (#source + 1)) - 1):match('^%s*(.-)%s*$')
  if text ~= '' then counts[text] = (counts[text] or 0) + 1; unique[text] = line end
 end
 for line in pairs(points) do
  -- A whole removed line cannot retain a breakpoint on its deleted code.
  if not (deletedFirst and line >= deletedFirst and line <= deletedLast) then
  if not oldStarts[line] then mapped[math.max(1, line + #newStarts - #oldStarts)] = true
  else
   local finish = (oldStarts[line + 1] or (#previous + 1)) - 1
   local text = previous:sub(oldStarts[line] + 1, finish)
   local anchor = oldStarts[line] + #(text:match('^%s*') or '')
   local destination
   if anchor < prefix then destination = lineAt(newStarts, anchor)
   elseif anchor >= oldEnd then destination = lineAt(newStarts, math.max(0, anchor + newLength - oldLength))
   else
    local trimmed = text:match('^%s*(.-)%s*$')
    if trimmed ~= '' and counts[trimmed] == 1 then destination = unique[trimmed]
    elseif newEnd == prefix and prefix <= oldStarts[line] and oldEnd >= (oldStarts[line + 1] or oldLength) then
     destination = nil -- The complete anchored line was deleted.
    else destination = math.min(newLast, newFirst + math.max(0, line - oldFirst)) end
   end
   if destination then mapped[math.max(1, destination)] = true end
  end
  end
 end
 return mapped
end

function D:PersistBreakpoints(id)
 local db = addon.Workspace and addon.Workspace.db
 if not db then return end
 db.debugBreakpoints = db.debugBreakpoints or {}
 local points = self.breakpoints[id]
 if points and next(points) then
  local record = db.debugBreakpoints[id]
  if type(record) ~= 'table' then record = {}; db.debugBreakpoints[id] = record end
  record.source, record.points = self.breakpointSources[id] or '', points
 else db.debugBreakpoints[id] = nil end
end

function D:GetBreakpoints(id, source, edit)
 if not id then return {} end
 local db = addon.Workspace and addon.Workspace.db
 if db ~= self.breakpointDB then self.breakpointDB, self.loadedBreakpointRecords = db, {} end
 self.loadedBreakpointRecords = self.loadedBreakpointRecords or {}
 if db and not self.loadedBreakpointRecords[id] then
  self.loadedBreakpointRecords[id] = true
  local record = db.debugBreakpoints and db.debugBreakpoints[id]
  if type(record) == 'table' and type(record.source) == 'string' and type(record.points) == 'table' then
   local points = {}
   for line, enabled in pairs(record.points) do
    if type(line) == 'number' and line >= 1 and line == math.floor(line) and enabled == true then points[line] = true end
   end
   self.breakpoints[id], self.breakpointSources[id] = points, record.source
  end
 end
 if source and self.breakpointSources[id] and self.breakpointSources[id] ~= source then
  self.breakpoints[id] = self:RemapBreakpoints(self.breakpoints[id] or {}, self.breakpointSources[id], source, edit)
  self.breakpointRevision = (self.breakpointRevision or 0) + 1
 end
 if source then self.breakpointSources[id] = source end
 local points = self.breakpoints[id]
 if not points then points = {}; self.breakpoints[id] = points end
 self:PersistBreakpoints(id)
 return points
end

function D:RuntimeBreakpoints(id, source)
 local points = self:GetBreakpoints(id)
 if not source or source == self.breakpointSources[id] then return points end
 local snapshot = self.sources and self.sources[id]
 if snapshot and snapshot.runtimePoints and snapshot.pointRevision == self.breakpointRevision and snapshot.pointSource == self.breakpointSources[id] then return snapshot.runtimePoints end
 local mapped = self:RemapBreakpoints(points, self.breakpointSources[id], source)
 if snapshot then snapshot.runtimePoints, snapshot.pointRevision, snapshot.pointSource = mapped, self.breakpointRevision, self.breakpointSources[id] end
 return mapped
end

function D:RemoveBreakpoints(id)
 if not id then return end
 self.breakpoints[id], self.breakpointSources[id] = nil, nil
 if self.loadedBreakpointRecords then self.loadedBreakpointRecords[id] = nil end
 local db = addon.Workspace and addon.Workspace.db
 if db and db.debugBreakpoints then db.debugBreakpoints[id] = nil end
 self.breakpointRevision = (self.breakpointRevision or 0) + 1
end

function D:ToggleBreakpoint(id, line, source)
 if not id or type(line) ~= 'number' or line < 1 then return false end
 if self.armed and self.sources and self.sources[id] and source ~= self.sources[id].source then self:Stop() end
 local points = self:GetBreakpoints(id, source)
 points[line] = not points[line] or nil
 self.breakpointRevision = (self.breakpointRevision or 0) + 1
 self:PersistBreakpoints(id)
 self:Refresh()
 return points[line] == true
end

function D:Stop()
 self.startupOwnedId, self.startupTrigger = nil, nil
 self:CleanupCallbacks()
 self.generation = self.generation + 1
 self.failedYieldPending, self.budgetExceeded = nil, nil
 if self.events then self.events:UnregisterAllEvents() end
 self.thread, self.paused, self.running, self.armed = nil, nil, nil, nil
 self.queue, self.held = {}, nil
 self:ClearEvaluation(); self:CaptureVariables(nil)
 self.frames, self.environment, self.compiled, self.metadata, self.mode = nil, nil, nil, nil, nil
 self.line, self.depth, self.status, self.budgetPending, self.protectedDepth = nil, nil, nil, nil, nil
 self.sources, self.currentSourceId, self.activeContext = nil, nil, nil
 self.hookSourceId, self.hookEnvironment, self.environmentBuiltinSets, self.helperRegistry = nil, nil, nil, nil
 self:Refresh()
end

function D:Fail(value)
 if self.activeContext then self.activeContext.loading, self.activeContext.chain = {}, {} end
 P.Fail(self, value)
 if C.SetStatus then C:SetStatus(self.status, true) end
 self.frames, self.environment = nil, nil
end

function D:Hook(operation, ...)
 -- Functions retained by the script may run later from Blizzard callbacks or
 -- the terminal. Only the owned execution coroutine may suspend.
 if self.evaluating or not self.armed or coroutine.running() ~= self.thread then
  if operation == 'return' then return select(2, ...) end
  return
 end
 if self.budgetExceeded then error(L.debuggerBudgetExceeded, 0) end
 if self.protectedDepth then
  if operation == 'step' then
   self.instructions = self.instructions + 1
   if self.instructions > 1000000 then self.budgetExceeded = true; error(L.debuggerBudgetExceeded, 0) end
  end
  if operation == 'return' then return select(2, ...) end
  return
 end
 if self.failedYieldPending then error(L.debugUnsupportedYield, 0) end
 if operation == 'enter' then
  local frame = { depth = #self.frames + 1, sourceId = self.hookSourceId or self.scriptId, environment = self.hookEnvironment or self.environment }
  self.frames[#self.frames + 1] = frame
  return frame
 elseif operation == 'leave' or operation == 'return' then
  local frame = ...
  if frame then for index = #self.frames, frame.depth, -1 do self.frames[index] = nil end end
  if operation == 'return' then return select(2, ...) end
  return
 end
 local line, bindings, frame = ...
 self.instructions = self.instructions + 1
 self.slice = self.slice + 1
 if self.instructions > 1000000 then self.budgetExceeded = true; error(L.debuggerBudgetExceeded, 0) end
 if self.slice >= 1000 then
  self.slice = 0
  self.failedYieldPending = true
  coroutine.yield(self.budgetToken)
  self.failedYieldPending = nil
 end
 local depth = frame and frame.depth or 1
 for index = #self.frames, depth + 1, -1 do self.frames[index] = nil end
 local sourceId = frame and frame.sourceId or self.scriptId
 self.environment = frame and frame.environment or self.environment
 local stop = self:RuntimeBreakpoints(sourceId, self.sources[sourceId].source)[line] or self.mode == 'into'
  or (self.mode == 'over' and depth <= (self.stepDepth or 1))
 if not stop then return end
 self.line, self.depth, self.currentSourceId = line, depth, sourceId
 self.status = L.debugPaused .. ': ' .. line
 self.invocationEnvironment = self.environment
 self.capturedValues, self.evalToken, self.evaluationEnvironment = {}, {}, nil
 -- Include globals assigned in this script's environment, retaining lexical
 -- locals when the same name is shadowed.
 for name in pairs(self.environment) do
  if not secret(name) and type(name) == 'string' and name:match('^[%a_][%w_]*$') and not (self.environmentBuiltinSets[self.environment] or {})[name] and not bindings[name] then
   local key = name
   bindings[key] = { get = function() return rawget(self.environment, key) end,
    set = function(value) rawset(self.environment, key, value) end }
  end
 end
 self.checkpointBindings, self.liveBindings, self.evalOverlay, self.evalWritten = bindings, nil, nil, nil
 self.failedYieldPending = true
 coroutine.yield(self.checkpoint)
 self.failedYieldPending = nil
end

function D:Resume(...)
 local thread, generation = self.thread, self.generation
 local ok, value = coroutine.resume(thread, ...)
 if self.thread ~= thread or generation ~= self.generation then return end
 if not ok then self:Fail(value)
 elseif coroutine.status(thread) == 'dead' and self.budgetExceeded then self:Fail(L.debuggerBudgetExceeded)
 elseif coroutine.status(thread) == 'dead' and self.failedYieldPending then self:Fail(L.debugUnsupportedYield)
 elseif coroutine.status(thread) == 'dead' then
  -- Stepping belongs to this invocation, never to the next queued event.
  self.mode, self.stepDepth = 'continue', nil
  self.thread, self.paused, self.frames = nil, nil, nil
  self:CaptureVariables(nil); self:ClearEvaluation()
  self.status = self.callbacks and #self.callbacks > 0 and L.debugWaitingCallbacks or L.debugProbeFinished
 elseif not secret(value) and value == self.checkpoint then
  self.paused = true
  local valid, bindings = pcall(self.ValidateBindings, self)
  if valid then
   self.liveBindings = bindings
   self.evaluating = self.evalToken
   pcall(self.RefreshBoundVariables, self, self.evalToken, bindings)
   self.evaluating = nil
  else self:Fail(L.debugProbeBindingsError) end
 elseif not secret(value) and value == self.budgetToken then
  if not (_G.C_Timer and _G.C_Timer.After) then self:Fail(L.debuggerBudgetExceeded)
  else
   self.budgetPending = true
   _G.C_Timer.After(0, function()
    if generation ~= self.generation or self.thread ~= thread then return end
    self.budgetPending = nil; self:Resume(); self:Pump()
   end)
  end
 else self:Fail(L.debugProbeError) end
 self:Refresh()
end

function D:StartInvocation(item)
 local workspace = addon.Workspace
 if workspace and workspace.db and workspace.db.clearOnRun and workspace.db.clearOnRun[self.scriptId] then C:Clear() end
 local context = item.context or { cache = {}, loading = {}, chain = {} }
 self.activeContext = context
 local source = self.sources[item.sourceId or self.scriptId]
 local environment = item.environment or self:MakeEnvironment(source, context, item.event)
 if item.callback then environment.event = item.args[2] end
 local chunk, failure = item.callback
 if not chunk then
  chunk, failure = _G.loadstring(source.compiled, '=LuaWorkbench debugger [' .. tostring(source.id) .. ']')
  if not chunk then self:Fail(failure); return end
  _G.setfenv(chunk, environment)
 end
 self.failedYieldPending, self.budgetExceeded = nil, nil
 self.environment, self.frames, self.instructions, self.slice = environment, {}, 0, 0
 self.thread = coroutine.create(chunk)
 self:Resume(unpack(item.args, 1, item.args.n))
end

function D:MakeEnvironment(source, context, event)
 local generation = self.generation
 local function output(...)
  if generation ~= self.generation then return end
  if self.evaluating then self:TerminalWrite(...) else C:Write(...) end
 end
 local function devtools(value, startKey)
  if generation ~= self.generation then return end
  if self.evaluating then self:TerminalDump(value, startKey) else C:Dump(value, startKey) end
 end
 local function dump(...)
  local count = select('#', ...)
  for index = 1, count do local value = select(index, ...); devtools(value, count > 1 and ('arg[' .. index .. ']') or nil) end
 end
 local environment = setmetatable({ addon = addon, editor = addon, event = event,
  print = output, dump = dump, DevTools_Dump = devtools,
 }, { __index = _G })
 environment.requireHelper = function(name) return self:LoadHelper(context, name, event, generation) end
 environment[source.metadata.helperName] = function(operation, ...)
  if operation == 'method' then
   local receiver, method = ...
   local original = receiver[method]
   return function(...)
    if generation ~= self.generation or not self.armed then return original(receiver, ...) end
    return self:InstallCallback(receiver, method, original, source.id, environment, context, ...)
   end
  end
  if generation ~= self.generation then
   if operation == 'return' then return select(2, ...) end
   return
  end
  self.hookSourceId, self.hookEnvironment = source.id, environment
  return self:Hook(operation, ...)
 end
 local function pack(...) return { n = select('#', ...), ... } end
 local function protectedCall(api, ...)
  local previous, chainDepth = self.protectedDepth, #context.chain
  self.protectedDepth = (previous or 0) + 1
  local results = pack(_G.pcall(api, ...))
  self.protectedDepth = previous
  -- A caught helper initialization error must not poison later imports.
  while #context.chain > chainDepth do
   local id = table.remove(context.chain); context.loading[id] = nil
  end
  if not results[1] then error(results[2], 0) end
  return unpack(results, 2, results.n)
 end
 environment.pcall = function(...) return protectedCall(_G.pcall, ...) end
 environment.xpcall = function(...) return protectedCall(_G.xpcall, ...) end
 local builtins = {}
 for name in pairs(environment) do builtins[name] = true end
 self.environmentBuiltinSets[environment] = builtins
 return environment
end

function D:LoadHelper(context, name, event, generation)
 if generation ~= self.generation or not self.armed then error(L.debugProbeNotPaused, 0) end
 local _, key = addon.Helpers:Normalize(name)
 if not key then error(L.helperInvalidName, 0) end
 local module = self.helperRegistry[key]
 if module == false then error(L.helperDuplicate .. ' ' .. name, 0) end
 if not module then error(L.helperMissing .. ' ' .. name, 0) end
 if module.blockedSelf then error(L.helperCycle .. ' ' .. module.name, 0) end
 if context.cache[module.id] then return context.cache[module.id] end
 if context.loading[module.id] then error(L.helperCycle .. ' ' .. module.name, 0) end
 if not module.compiled then
  local compiled, metadata = addon.DebugCompiler:Compile(module.source)
  if not compiled then error(L.helperLoadError .. ' ' .. module.name .. ': ' .. metadata, 0) end
  module.compiled, module.metadata = compiled, metadata
  self:RuntimeBreakpoints(module.id, module.source)
 end
 local chunk, failure = _G.loadstring(module.compiled, '=LuaWorkbench debugger helper [' .. module.name .. ']')
 if not chunk then error(failure, 0) end
 local environment = self:MakeEnvironment(module, context, event)
 _G.setfenv(chunk, environment)
 context.loading[module.id] = true; context.chain[#context.chain + 1] = module.id
 -- Deliberately no protected call here: helper breakpoints must be able to
 -- suspend the same owned coroutine. Resume owns the error boundary.
 local value = chunk()
 table.remove(context.chain); context.loading[module.id] = nil
 if secret(value) or type(value) ~= 'table' then error(L.helperMustReturnTable .. ' ' .. module.name, 0) end
 context.cache[module.id] = value
 return value
end

function D:InstallCallback(receiver, method, original, sourceId, environment, context, ...)
 local function pack(...) return { n = select('#', ...), ... } end
 local arguments = pack(...)
 local event, callback = arguments[1], arguments[2]
 if arguments.n < 2 or secret(event) or secret(callback) or event ~= 'OnEvent' or (callback ~= nil and type(callback) ~= 'function') then return original(receiver, ...) end
 if method ~= 'SetScript' and method ~= 'HookScript' then return original(receiver, ...) end
 if not callback and method == 'HookScript' then return original(receiver, ...) end
 if type(receiver.GetScript) ~= 'function' then return original(receiver, ...) end
 local generation = self.generation
 local record = { receiver = receiver, method = method, callback = callback, sourceId = sourceId, environment = environment, context = context }
 if method == 'SetScript' then record.previous = receiver:GetScript(event) end
 record.wrapper = callback and function(...)
  if generation ~= self.generation or not self.armed or not record.callback then return end
  if #self.queue >= 50 then self.dropped = self.dropped + 1; self:Refresh(); return end
  self.queue[#self.queue + 1] = { callback = record.callback, sourceId = record.sourceId, environment = record.environment,
   context = record.context, args = { n = select('#', ...), ... } }
  self:Pump(); self:Refresh()
 end
 arguments[2] = record.wrapper
 local results = pack(original(receiver, unpack(arguments, 1, arguments.n)))
 self.callbacks[#self.callbacks + 1] = record
 return unpack(results, 1, results.n)
end

function D:CleanupCallbacks()
 for index = #(self.callbacks or {}), 1, -1 do
  local record = self.callbacks[index]
  if record.method == 'SetScript' then
   local ok, current = pcall(record.receiver.GetScript, record.receiver, 'OnEvent')
   if ok and current == record.wrapper then pcall(record.receiver.SetScript, record.receiver, 'OnEvent', record.previous) end
  end
  record.callback, record.environment, record.context, record.receiver, record.previous = nil, nil, nil, nil, nil
 end
 self.callbacks = {}
end

function D:CurrentSource() return self.sources and self.sources[self.currentSourceId or self.scriptId] end

function D:Start(id, source, eventList, managedEvents)
 self:Stop()
 if C.SetStatus then C:SetStatus(nil) end
 local compiled, metadata = addon.DebugCompiler:Compile(source)
 if not compiled then self:Fail(metadata); return false end
 self.scriptId, self.source, self.compiled, self.metadata = id, source, compiled, metadata
 self.sources = { [id] = { id = id, name = addon.Workspace.db and addon.Workspace.db.snippets and addon.Workspace.db.snippets[id] and addon.Workspace.db.snippets[id].name or tostring(id), source = source, compiled = compiled, metadata = metadata } }
 self.currentSourceId, self.helperRegistry = id, {}
 self.environmentBuiltinSets = setmetatable({}, { __mode = 'k' })
 local db = addon.Workspace and addon.Workspace.db
 if db and addon.Helpers then
  for helperId, options in pairs(db.helperModules or {}) do
   local _, key = addon.Helpers:Normalize(options.name)
   local saved = db.snippets[helperId]
   if options.enabled and key and saved then
    local module = { id = helperId, name = options.name, source = addon.Workspace:NormalizeSource(saved.source) }
    if helperId == id then module.blockedSelf = true else self.sources[helperId] = module end
    if self.helperRegistry[key] ~= nil then self.helperRegistry[key] = false else self.helperRegistry[key] = module end
   end
  end
 end
 self.eventSet = {}
 for _, name in ipairs(eventList or {}) do
  local event = addon.Automation:ValidateEvent(name)
  if not event then self:Fail(L.invalidEvent); return false end
  self.eventSet[event] = true
 end
 self.checkpoint, self.budgetToken = {}, {}
 self.dropped, self.terminalLines = 0, {}
 local points = self:GetBreakpoints(id, source)
 local hasValidPoint = false
 for line in pairs(points) do if metadata.lines[line] then hasValidPoint = true; break end end
 self.mode = hasValidPoint and 'continue' or 'into'
 if self.terminal then self.terminal.output:SetText(''); self.terminal.input:SetText('') end
 if not self.events then
  self.events = CreateFrame('Frame')
  self.events:SetScript('OnEvent', function(_, event, ...) self:Enqueue(event, ...) end)
 end
 if not managedEvents then
  for event in pairs(self.eventSet) do
   local ok, result = pcall(self.events.RegisterEvent, self.events, event)
   if not ok or result == false then self.events:UnregisterAllEvents(); self:Fail(L.invalidEvent); return false end
  end
 end
 self.armed, self.status = true, L.debugProbeWaiting
 if not next(self.eventSet) then self:Enqueue(nil) end
 self:Refresh()
 return true
end

-- Only one saved script can own the next startup session.
function D:ScheduleStartup(id, event, persistent)
 local workspace = addon.Workspace
 if event ~= 'ADDON_LOADED' and event ~= 'PLAYER_LOGIN' then return false end
 if not workspace.db.snippets[id] then C:SetStatus(L.saveBeforeAutoRun, true); return false end
 workspace.db.startupDebug = { id = id, event = event, persistent = persistent == true }
 C:SetStatus(L.debugScheduleMenu .. ': ' .. workspace.db.snippets[id].name .. ' / ' .. event)
 return true
end

function D:RestoreStartup()
 local workspace = addon.Workspace
 local plan = workspace.db.startupDebug
 if plan == nil then return end
 if type(plan) ~= 'table' or (plan.event ~= 'ADDON_LOADED' and plan.event ~= 'PLAYER_LOGIN')
  or type(plan.id) ~= 'string' or not workspace.db.snippets[plan.id] then
  workspace.db.startupDebug = nil
  return
 end
 local saved = workspace.db.snippets[plan.id]
 -- Consume before compiling or running, so a failed once-only session cannot loop on reload.
 if plan.persistent ~= true then workspace.db.startupDebug = nil end
 if addon.DebugUI then addon.DebugUI.drawerOpen = true end
 workspace:Show(false)
 workspace:Select(plan.id)
 workspace:Minimize()
 if C.input then C.input:ClearFocus() end
 local started = self:Start(plan.id, workspace:NormalizeSource(saved.source), { plan.event }, true)
 -- Even compile failure must not fall back to an uninstrumented automatic run.
 self.startupOwnedId = plan.id
 if started then self.startupTrigger = plan.event end
 self:Refresh()
end

function D:DispatchStartup(event, startup, ...)
 if not self.armed or event ~= self.startupTrigger then return end
 if event == 'ADDON_LOADED' and not startup then return end
 self.startupTrigger = nil
 return self:Enqueue(event, ...)
end

function D:Enqueue(event, ...)
 if not self.armed or (event ~= nil and not self.eventSet[event]) then return false end
 if #self.queue >= 50 then self.dropped = self.dropped + 1; self:Refresh(); return false end
 self.queue[#self.queue + 1] = { event = event, args = { n = select('#', ...), ... } }
 self:Pump(); self:Refresh()
 return true
end

function D:Advance(mode)
 if self.evaluating or not self.paused or not self.thread then return false end
 self.mode, self.stepDepth, self.paused = mode, self.depth, nil
 self:ClearEvaluation(); self:Resume(); self:Pump()
 return true
end
function D:Continue() return self:Advance('continue') end
function D:StepInto() return self:Advance('into') end
function D:StepOver() return self:Advance('over') end
function D:Step() return self:StepOver() end

function D:ResolveVariable(path)
 if not self.paused or type(path) ~= 'string' or not path:match('^[%a_][%w_%.]*$') or path:find('%.%.') or path:sub(-1) == '.' then return nil, false end
 local head = path:match('^[%a_][%w_]*')
 local binding = self.liveBindings and self.liveBindings[head]
 local value
 if binding then
  local ok; ok, value = pcall(binding.get)
  if not ok then return nil, false end
 elseif self.evalWritten and self.evalWritten[head] then value = self.evalOverlay[head]
 else
  value = self.environment and rawget(self.environment, head)
  if not secret(value) and value == nil then value = rawget(_G, head) end
  if not secret(value) and value == nil then return nil, false end
 end
 for key in path:sub(#head + 1):gmatch('%.([%a_][%w_]*)') do
  if secret(value) or type(value) ~= 'table' then return nil, false end
  local ok; ok, value = pcall(rawget, value, key)
  if not ok then return nil, false end
 end
 return value, true
end

function D:BuildPanel() if addon.DebugUI then addon.DebugUI:ShowDrawer() end end
function D:ShowTerminal() if addon.DebugUI then addon.DebugUI:ShowDrawer() end end
function D:ShowSnapshot() if addon.DebugUI then addon.DebugUI:ShowLocation() end end

function D:SourceChanged(id, source, edit)
 if not id then return end
 self:GetBreakpoints(id, source, edit)
 if self.armed and self.sources and self.sources[id] and self.sources[id].source ~= source then self:Stop() end
 self:Refresh()
end

-- Keep inspector collection independent of pooled UI rows. Nil locals need a
-- record of their own rather than a values table, which would discard them.
function D:VariableRecord(name, value)
 return { name = name, value = P:FormatScalar(value), preview = P:FormatPreview(value),
  hasSecretText = secret(value) and (type(value) == 'string' or type(value) == 'number'), secretText = value }
end

function D:CaptureVariables(values)
 self.variables = {}
 if secret(values) or type(values) ~= 'table' then return end
 local key, records = nil, {}
 while true do
  local ok, name, value = pcall(next, values, key)
  if not ok or secret(name) or name == nil then break end
  key = name
  if type(name) == 'string' then records[#records + 1] = self:VariableRecord(name, value) end
 end
 table.sort(records, function(a, b) return a.name < b.name end)
 for index = 1, math.min(#records, 200) do self.variables[index] = records[index] end
end

function D:RefreshBoundVariables(token, bindings, overlay, written)
 local names, known = {}, {}
 local function collect(source)
  if secret(source) or type(source) ~= 'table' then return end
  local key
  while true do
   local ok, name = pcall(next, source, key)
   if not ok or secret(name) or name == nil then break end
   key = name
   if type(name) == 'string' and not known[name] then known[name] = true; names[#names + 1] = name end
  end
 end
 collect(bindings); collect(written); collect(self.capturedValues)
 table.sort(names)
 local records = {}
 for index = 1, math.min(#names, 200) do
  local name, value = names[index], nil
  local binding = rawget(bindings, name)
  if binding then
   local ok; ok, value = pcall(binding.get)
   if not ok then value = L.debugProbeError end
  elseif written and rawget(written, name) then value = rawget(overlay, name)
  elseif not secret(self.capturedValues) and type(self.capturedValues) == 'table' then value = rawget(self.capturedValues, name) end
  if self.evalToken ~= token or not self.paused then return end
  records[#records + 1] = self:VariableRecord(name, value)
 end
 self.variables = records
end

function D:Evaluate(source)
 local result = P.Evaluate(self, source)
 self:Refresh()
 return result
end
