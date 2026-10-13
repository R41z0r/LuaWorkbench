local _, addon = ...
local L = addon.L
addon.Query = addon.Query or {}
local Console = { lines = {}, characters = 0, source = "" }
addon.Query.Console = Console

local function pack(...)
	return { n = select("#", ...), ... }
end

function Console:Format(value, colorSecrets)
 local hidden = colorSecrets and "|cff88ff88<secret>|r" or "<secret>"
	if _G.issecretvalue and _G.issecretvalue(value) then return hidden end
	local ok, text = pcall(tostring, value)
	if not ok then return "<unprintable>" end
	if _G.issecretvalue and _G.issecretvalue(text) then return hidden end
	return (text:sub(1, 4000):gsub("\t", "    "))
end

function Console:SetStatus(text, failed)
 self.statusText, self.statusFailed = text, failed
 if addon.Workspace then addon.Workspace:UpdateStatus() end
end

function Console:OutputLimit()
 local db = addon.Workspace and addon.Workspace.db
 local value = db and tonumber(db.options.outputLimit) or 500
 if not value or value ~= value then value = 500 end
 return math.max(50, math.min(5000, math.floor(value)))
end

function Console:TrimOutput()
 if self.dumpBatch then return end
 local limit = math.max(self:OutputLimit(), self.dumpLineLimit or 0)
 while #self.lines > limit or self.characters > math.max(64000, self.dumpCharacterLimit or 0) do
  self.characters = self.characters - #self.lines[1] - 1
  table.remove(self.lines, 1)
 end
end

function Console:AutoScrollEnabled()
 local db = addon.Workspace and addon.Workspace.db
 return not db or db.options.outputAutoScroll ~= false
end

function Console:SetAutoScroll(enabled)
 addon.Workspace.db.options.outputAutoScroll = enabled == true
 if enabled and self.output then
  local scroll = self.output.scrollFrame
  scroll:UpdateScrollChildRect(); scroll:SetVerticalScroll(scroll:GetVerticalScrollRange())
 end
end

function Console:Refresh()
 self:TrimOutput()
	if self.output then
  self.output.label:SetText(L.queryLuaOutput .. " (" .. self:OutputLimit() .. ")")
  local scroll = self.output.scrollFrame
  local offset = scroll:GetVerticalScroll()
  local follow = self:AutoScrollEnabled()
  self.output:SetText(table.concat(self.lines, "\n"))
  scroll:UpdateScrollChildRect()
  scroll:SetVerticalScroll(follow and scroll:GetVerticalScrollRange() or math.min(offset, scroll:GetVerticalScrollRange()))
 end
end

function Console:Write(...)
	local values = {}
	for i = 1, select("#", ...) do
		values[i] = self:Format(select(i, ...), true)
	end
	local text = table.concat(values, "  "):sub(1, 8000)
 if addon.Diagnostics then addon.Diagnostics:QueueOutput(text) end
	-- Bound both multiline messages and the entire session's retained output.
	for line in (text .. "\n"):gmatch("(.-)\n") do
		self.lines[#self.lines + 1] = line
		self.characters = self.characters + #line + 1
		self:TrimOutput()
	end
	if not self.refreshPending then
		self.refreshPending = true
		C_Timer.After(0, function()
			self.refreshPending = nil
			self:Refresh()
		end)
	end
end

function Console:Clear(undoable)
 self.undoLines = undoable and #self.lines > 0 and self.lines or nil
 self.undoDumpLineLimit, self.undoDumpCharacterLimit = self.dumpLineLimit, self.dumpCharacterLimit
 self.lines, self.characters = {}, 0
 self.dumpLineLimit, self.dumpCharacterLimit = nil, nil
 local workspace = addon.Workspace
 if workspace and workspace.undoOutput then workspace.undoOutput:SetShown(self.undoLines ~= nil) end
 self:Refresh()
 if undoable and self.undoLines then
  self:SetStatus(L.outputCleared)
  local snapshot = self.undoLines
  C_Timer.After(10, function()
   if self.undoLines == snapshot then
    self.undoLines = nil
    if workspace and workspace.undoOutput then workspace.undoOutput:Hide() end
   end
  end)
 end
end

function Console:UndoClear()
 if not self.undoLines then return end
 self.dumpLineLimit = math.max(self.dumpLineLimit or 0, self.undoDumpLineLimit or 0)
 self.dumpCharacterLimit = math.max(self.dumpCharacterLimit or 0, self.undoDumpCharacterLimit or 0)
 local restored = self.undoLines
 self.undoLines = nil
 for _, line in ipairs(self.lines) do restored[#restored + 1] = line end
 self.lines, self.characters = restored, 0
 for _, line in ipairs(restored) do self.characters = self.characters + #line + 1 end
 if addon.Workspace.undoOutput then addon.Workspace.undoOutput:Hide() end
 self:Refresh()
 self:SetStatus(nil)
end

function Console:GetLinePosition(source, cursor)
 local cache = self.linePositionCache
 if not cache or cache.source ~= source then
  cache = {source=source, starts={0}}
  local position = source:find("\n", 1, true)
  while position do
   cache.starts[#cache.starts+1] = position
   position = source:find("\n", position+1, true)
  end
  self.linePositionCache = cache
 end
 local low, high = 1, #cache.starts
 while low < high do
  local middle = math.floor((low+high+1)/2)
  if cache.starts[middle] <= cursor then low=middle else high=middle-1 end
 end
 return low, #cache.starts, cache.starts[low]
end

function Console:UpdateEditorLabel()
	if not self.input then return end
	local line = self.lastError and self.lastError.line
	local position = ""
	if self.input.editBox then
		local cursor = self.input.editBox:GetCursorPosition()
  local current, _, lineStart = self:GetLinePosition(self.source or "", cursor)
  local prefix = (self.source or ""):sub(lineStart+1, cursor)
  local _, characters = prefix:gsub("[^\128-\191]", "")
  position = " - " .. string.format(L["cursorPosition"], current, characters + 1)
	end
 local workspace = addon.Workspace
 local dirty = workspace and workspace.dirty
 local showText = dirty and workspace.db.options.dirtyText
 self.input.label:SetPoint('TOPLEFT', self.input.frame, 'TOPLEFT', 12, -34)
 -- Keep the dirty state alongside the code position, away from the window footer.
	self.input.label:SetText(L["queryLuaCode"] .. (addon.Query.Editor:IsReadOnly(self.input) and (" - " .. L.debugWriteProtected) or "") .. position .. (showText and (" - " .. L.unsaved) or "") .. (line and (" - " .. string.format(L["queryLuaErrorLine"], line)) or ""))
	self.input.label:SetTextColor(1, line and 0.3 or 0.8, line and 0.3 or 0.9)
end

function Console:ShowError()
	if not self.input then return end
	self:UpdateEditorLabel()
	local line = self.lastError and self.lastError.line
	if not line then return end
	local source = self.source or ""
	local start = 1
	for _ = 2, line do
		local newline = source:find("\n", start, true)
		if not newline then break end
		start = newline + 1
	end
	local finish = source:find("\n", start, true) or (#source + 1)
	self.input:SetFocus()
	self.input:SetCursorPosition(start - 1)
	self.input:HighlightText(start - 1, finish - 1)
	local state = self.input.queryLineNumbers
	if state and state.cursorY then
		local scroll = self.input.scrollFrame
		local offset = math.max(0, -state.cursorY - scroll:GetHeight() * 0.25)
		scroll:SetVerticalScroll(math.min(offset, scroll:GetVerticalScrollRange()))
	end
	self:UpdateLineNumbers()
end

function Console:ReportError(value, stack)
	local message = self:Format(value)
 if addon.Diagnostics then
  local workspace = addon.Workspace
  addon.Diagnostics:Record(message, stack, workspace.current, workspace.currentName)
 end
	local location = message:match("LuaWorkbench:(%d+):") or (stack and stack:match("LuaWorkbench:(%d+):"))
	self.lastError = { line = tonumber(location), message = message }
 self:SetStatus(L["queryLuaError"] .. " " .. message, true)
	self:Write(L["queryLuaError"], message)
	if stack then self:Write(stack) end
	self:ShowError()
	local input, source = self.input, self.source
	-- Apply focus after the button's click handling and pending frame layout have finished.
	if input then
		C_Timer.After(0, function()
			if self.input == input and self.source == source and self.lastError then self:ShowError() end
		end)
	end
end

function Console:UpdateLineNumbers()
	local input = self.input
	local state = input and input.queryLineNumbers
	if not state then return end
	local editBox, scroll = input.editBox, input.scrollFrame
	local source = self.source or ""
	local width = editBox:GetWidth()
	local font, size, flags = editBox:GetFont()
	local spacing = editBox:GetSpacing()
	if state.source ~= source or state.width ~= width or state.font ~= font or state.size ~= size or state.flags ~= flags or state.spacing ~= spacing then
		local previousHeights = state.width == width and state.font == font and state.size == size and state.flags == flags and state.spacing == spacing and state.lineHeights or {}
		local heights = {}
		state.lineHeights = heights
		state.source, state.width, state.font, state.size, state.flags, state.spacing = source, width, font, size, flags, spacing
		state.measure:SetFont(font, size, flags)
		state.measure:SetSpacing(spacing)
		state.measure:SetWidth(math.max(1, width))
		state.positions = state.positions or {}
		local offset, sourceStart, line = 0, 1, 0
		for text in (source .. "\n"):gmatch("(.-)\n") do
			local height = heights[text] or previousHeights[text]
			if not height then
				state.measure:SetText(text ~= "" and text or " ")
				height = math.max(size + spacing, state.measure:GetStringHeight())
			end
			heights[text] = height
			line = line + 1
			local position = state.positions[line] or {}
			state.positions[line] = position
			position.offset, position.height = offset, height
			position.sourceStart, position.sourceEnd = sourceStart, sourceStart+#text
			sourceStart=sourceStart+#text+1
			offset = offset + height
		end
		for index = #state.positions, line+1, -1 do state.positions[index] = nil end
	end
	local current = self:GetLinePosition(source, editBox:GetCursorPosition())
	local errorLine = self.lastError and self.lastError.line
	local scrollOffset, viewport = scroll:GetVerticalScroll(), scroll:GetHeight()
	state.measure:SetText(tostring(#state.positions))
	state.numberWidth = state.measure:GetStringWidth()
	local used, visible = 0, {}
 -- Positions are ordered by vertical offset. Cursor and scroll callbacks only
 -- need the visible rows, not a traversal of the entire document.
 local first, high = 1, #state.positions+1
 while first < high do
  local middle = math.floor((first+high)/2)
  local position = state.positions[middle]
  if position.offset+position.height < scrollOffset then first=middle+1 else high=middle end
 end
 for line = first, #state.positions do
  local position = state.positions[line]
  if position.offset >= scrollOffset+viewport then break end
		if position.offset + position.height >= scrollOffset and position.offset < scrollOffset + viewport then
			used = used + 1
			local row = state.rows[used]
			if not row then
				row = state.gutter:CreateFontString(nil, "OVERLAY")
				row:SetJustifyH("RIGHT")
				row:SetJustifyV("TOP")
				state.rows[used] = row
			end
			row:SetFont(font, size, flags)
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", state.gutter, "TOPLEFT", 0, scrollOffset - position.offset)
			row:SetWidth(state.gutter:GetWidth() - 2)
			row:SetHeight(size + spacing + 2)
			row:SetText(line)
   visible[#visible + 1] = { line = line, y = scrollOffset - position.offset, height = position.height, textHeight = row:GetStringHeight() }
			if line == errorLine then
				row:SetTextColor(1, 0.25, 0.25)
			elseif line == current then
				row:SetTextColor(1, 0.82, 0)
			else
				row:SetTextColor(0.6, 0.6, 0.6)
			end
			row:Show()
		end
	end
	for index = used + 1, #state.rows do state.rows[index]:Hide() end
 if addon.DebugUI then addon.DebugUI:UpdateGutter(state, visible) end
	self:UpdateEditorLabel()
end

function Console:AttachLineNumbers(input)
	local scroll, editBox = input.scrollFrame, input.editBox
	local state = input.queryLineNumberCache or { rows = {} }
	input.queryLineNumberCache = state
	state.scripts, state.scrollPoint, state.source = {}, { scroll:GetPoint(1) }, nil
	state.cursorY = nil
	input.queryLineNumbers = state
	if not state.gutter then
		state.gutter = CreateFrame("Frame", nil, input.scrollBG)
		state.gutter:SetPoint("TOPLEFT", input.scrollBG, "TOPLEFT", 4, -6)
		state.gutter:SetPoint("BOTTOMLEFT", input.scrollBG, "BOTTOMLEFT", 4, 4)
		state.gutter:SetWidth(54)
		state.gutter:SetClipsChildren(true)
		state.measure = state.gutter:CreateFontString(nil, "OVERLAY")
		state.measure:SetWordWrap(true)
		state.measure:SetNonSpaceWrap(true)
		state.measure:Hide()
	end
	state.gutter:Show()
	local function wrap(frame, event)
		local original = frame:GetScript(event)
		state.scripts[#state.scripts + 1] = { frame = frame, event = event, original = original }
		frame:SetScript(event, function(...)
			if event == "OnCursorChanged" then state.cursorY = select(3, ...) end
			if original then original(...) end
			if self.input == input then self:UpdateLineNumbers() end
		end)
	end
	wrap(editBox, "OnCursorChanged")
	wrap(scroll, "OnVerticalScroll")
	wrap(scroll, "OnSizeChanged")
	scroll:SetPoint("TOPLEFT", input.scrollBG, "TOPLEFT", 61, -6)
	self:UpdateLineNumbers()
end

function Console:DetachLineNumbers()
	local input = self.input
	local state = input and input.queryLineNumbers
	if not state then return end
	for _, script in ipairs(state.scripts) do script.frame:SetScript(script.event, script.original) end
	state.gutter:Hide()
	input.scrollFrame:SetPoint(unpack(state.scrollPoint))
	input.queryLineNumbers = nil
end

-- A fresh Blizzard dump context keeps routing local to this invocation.
function Console:Dump(value, startKey, prefix, writer)
 if type(_G.DevTools_CreateDumpContext) ~= "function" or type(_G.DevTools_RunDump) ~= "function" then
  error(L.queryLuaUnavailable, 2)
 end
 local context = _G.DevTools_CreateDumpContext(startKey)
 local hasSecret = _G.issecretvalue and _G.issecretvalue(value)
 context.Write = function(_, text)
  if _G.issecretvalue and _G.issecretvalue(text) then hasSecret = true end
  if writer then writer(text)
  elseif prefix then self:Write(prefix, text) else self:Write(text) end
 end
 -- Dump traversal is synchronous. Restore the shared cutoff even on errors.
 local cutoff = _G.DEVTOOLS_MAX_ENTRY_CUTOFF
 local previousBatch = self.dumpBatch
 local firstLine, firstCharacter = #self.lines, self.characters
 self.dumpBatch = true
 _G.DEVTOOLS_MAX_ENTRY_CUTOFF = 0
 local ok, failure = pcall(_G.DevTools_RunDump, value, context)
 _G.DEVTOOLS_MAX_ENTRY_CUTOFF = cutoff
 self.dumpBatch = previousBatch
 -- Keep enough room for a complete dump until Output is cleared. Ordinary
 -- output still uses a bounded buffer, including after a failed dump.
 self.dumpLineLimit = math.max(self.dumpLineLimit or 0, #self.lines - firstLine)
 self.dumpCharacterLimit = math.max(self.dumpCharacterLimit or 0, self.characters - firstCharacter)
 self:TrimOutput()
 if not ok then error(failure, 0) end
 local db = addon.Workspace and addon.Workspace.db
 if hasSecret and db and db.options.secretDumpChat and type(_G.DevTools_Dump) == "function" then
  -- Use Blizzard's own message dispatch, once for the whole dump, without inspecting secret text.
  _G.DevTools_Dump(value, startKey)
 end
end

function Console:DumpArguments(prefix, ...)
 local count = select('#', ...)
 for index = 1, count do
  local value = select(index, ...)
  self:Dump(value, count > 1 and ('arg[' .. index .. ']') or nil, prefix)
 end
end

function Console:Run(source)
	self.source = source
	self.lastError = nil
	self:ShowError()
	if not source or not source:find("%S") then self:SetStatus(nil); return end
	if not _G.loadstring or not _G.setfenv then
		self:SetStatus(L["queryLuaUnavailable"], true)
		self:Write(L["queryLuaUnavailable"])
		return
	end
	local chunk, compileError = _G.loadstring(source, "=LuaWorkbench")
	if not chunk then
		self:ReportError(compileError)
		return
	end
	-- Keep snippet globals and callback closures for this session without replacing global print.
	if not self.environment then
		self.environment = setmetatable({
			addon = addon,
			editor = addon,
			print = function(...) self:Write(...) end,
			DevTools_Dump = function(value, startKey) self:Dump(value, startKey) end,
		}, { __index = _G })
		self.environment.dump = function(...) self:DumpArguments(nil, ...) end
	end
	self.environment.requireHelper = addon.Helpers:Loader({ print = self.environment.print, dump = self.environment.dump, DevTools_Dump = self.environment.DevTools_Dump })
	_G.setfenv(chunk, self.environment)
	local stackTrace
	local results = pack(xpcall(chunk, function(value)
		if type(_G.debugstack) == "function" then
			local ok, stack = pcall(_G.debugstack, 2, 20, 20)
			if ok then stackTrace = self:Format(stack) end
		end
		return value
	end))
	if not results[1] then
		self:ReportError(results[2], stackTrace)
	else
		if results.n > 1 then self:Write("return", unpack(results, 2, results.n)) end
		self:SetStatus(L["queryLuaComplete"], false)
	end
end
