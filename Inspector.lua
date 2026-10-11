local _, addon = ...
local I = { refs = {}, serial = 0 }
addon.Inspector = I
local W, UI, L, C = addon.Workspace, addon.UI, addon.L, addon.Query.Console

function I:Secret(value) return _G.issecretvalue and _G.issecretvalue(value) or false end

function I:Widget(value)
 if self:Secret(value) then return false end
 if not (_G.C_Widget and _G.C_Widget.IsWidget) then return false end
 local ok, widget = pcall(_G.C_Widget.IsWidget, value)
 if not ok or self:Secret(widget) or not widget then return false end
 local access, allowed = pcall(function() return value:CanBeAccessedInContext() end)
 return access and not self:Secret(allowed) and allowed == true
end

function I:Readable(value)
 if self:Secret(value) then return false end
 if _G.C_Widget and _G.C_Widget.IsWidget then
  local ok, widget = pcall(_G.C_Widget.IsWidget, value)
  if not ok or self:Secret(widget) then return false end
  if widget then return self:Widget(value) end
 end
 return true
end

function I:Call(value, method)
 if not self:Widget(value) then return nil end
 local ok, result = pcall(function() return value[method](value) end)
 if ok and not self:Secret(result) then return result end
end

function I:Text(value)
 if self:Secret(value) then return '<secret>' end
 if not self:Readable(value) then return '<restricted>' end
 local kind = type(value)
 if kind == 'string' then return value end
 if kind == 'number' or kind == 'boolean' or kind == 'nil' then return tostring(value) end
 local name = self:Call(value, 'GetDebugName')
 return type(name) == 'string' and name or '<' .. kind .. '>'
end

function I:Literal(value)
 if self:Secret(value) then return nil end
 local kind = type(value)
 if kind == 'string' then return string.format('%q', value) end
 if kind == 'boolean' then return tostring(value) end
 if kind == 'number' and value == value and value ~= math.huge and value ~= -math.huge then return tostring(value) end
end

function I:Ref(id) return self.refs[id] end

-- Debug names are hints, not executable expressions. Resolve only raw fields.
function I:GlobalPath(value, name)
 if type(name) ~= 'string' or not name:match('^[%a_][%w_%.]*$') or name:find('..', 1, true) or name:sub(-1) == '.' then return nil end
 local object, path = _G, '_G'
 for key in name:gmatch('[^.]+') do
  if not key:match('^[%a_][%w_]*$') or not self:Readable(object) or type(object) ~= 'table' then return nil end
  local ok, field = pcall(rawget, object, key)
  if not ok or self:Secret(field) then return nil end
  object = field
  -- Bracket notation also handles identifiers that are Lua keywords.
  path = path .. '[' .. string.format('%q', key) .. ']'
 end
 if rawequal(object, value) then return path end
end

function I:Path(value)
 if not self:Readable(value) then return nil end
 local name = self:Call(value, 'GetName')
 if type(name) == 'string' and rawequal(rawget(_G, name), value) then return '_G[' .. string.format('%q', name) .. ']' end
 local globalPath = self:GlobalPath(value, name) or self:GlobalPath(value, self:Call(value, 'GetDebugName'))
 if globalPath then return globalPath end
 if type(value) ~= 'table' and not self:Widget(value) then return self:Literal(value) end
 for id, item in pairs(self.refs) do if rawequal(item, value) then return 'editor.Inspector:Ref(' .. string.format('%q', id) .. ')' end end
 self.serial = self.serial + 1
 local id = 'object' .. self.serial
 self.refs[id] = value
 return 'editor.Inspector:Ref(' .. string.format('%q', id) .. ')'
end

function I:Node(label, value, path, parent)
 local expandable = self:Readable(value) and (type(value) == 'table' or self:Widget(value))
 if expandable then
  local globalPath = self:GlobalPath(value, self:Call(value, 'GetName')) or self:GlobalPath(value, self:Call(value, 'GetDebugName'))
  path = globalPath or path or self:Path(value)
 end
 local ancestor, cycle = parent, false
 while expandable and ancestor do
  if rawequal(ancestor.value, value) then cycle = true; break end
  ancestor = ancestor.parent
 end
 return { label = label, value = value, path = path, parent = parent, expandable = expandable and not cycle, cycle = cycle }
end

function I:Expand(node)
 if node.children then return end
 node.children = {}
 if not node.expandable then return end
 local function add(label, value, path)
  node.children[#node.children + 1] = self:Node(label, value, path, node)
 end
 if self:Widget(node.value) then
  for _, method in ipairs({ 'GetName', 'GetObjectType', 'IsShown', 'IsVisible', 'GetWidth', 'GetHeight', 'GetScale', 'GetAlpha', 'GetFrameStrata', 'GetFrameLevel', 'GetParent' }) do
   local value = self:Call(node.value, method)
   if value ~= nil then add(method .. '()', value, node.path and node.path .. ':' .. method .. '()') end
  end
  local points = self:Call(node.value, 'GetNumPoints')
  if type(points) == 'number' then
   for index = 1, math.min(points, 20) do
    local ok, values = pcall(function() return { node.value:GetPoint(index) } end)
    if ok then add('GetPoint(' .. index .. ')', values) end
   end
  end
  for _, method in ipairs({ 'GetChildren', 'GetRegions' }) do
   local ok, values = pcall(function() return { node.value[method](node.value) } end)
   if ok then add(method .. '()', values) end
  end
 end
 if type(node.value) == 'table' then
  local key, count = nil, 0
  while count < 500 do
   local ok, nextKey, value = pcall(next, node.value, key)
   if not ok or self:Secret(nextKey) or nextKey == nil then break end
   key, count = nextKey, count + 1
   local literal = self:Literal(key)
   add(self:Text(key), value, node.path and literal and node.path .. '[' .. literal .. ']')
  end
  if count == 500 then add(L.inspectorLimit, nil) end
 end
 table.sort(node.children, function(a, b) return a.label:lower() < b.label:lower() end)
end

function I:Rows()
 local rows, query = {}, (self.panel.search:GetText() or ''):lower()
 local function visit(node, depth)
  local match = query == '' or (node.label .. ' ' .. self:Text(node.value)):lower():find(query, 1, true)
  if match then rows[#rows + 1] = { node = node, depth = depth } end
  if node.open and node.children and depth < 20 then
   for _, child in ipairs(node.children) do if #rows >= 1000 then break end; visit(child, depth + 1) end
  end
 end
 if self.root then visit(self.root, 0) end
 return rows
end

function I:RowText(node)
 local function color(text, kind)
  return '|c' .. addon.Query.Editor:Color(kind) .. text:gsub('|', '||') .. '|r'
 end
 local hidden, kind = self:Secret(node.value), type(node.value)
 local object = not hidden and (kind == 'table' or self:Widget(node.value))
 local valueKind = hidden and 'comment' or object and 'blizzardFunction'
  or kind == 'string' and 'string' or kind == 'number' and 'number'
  or (kind == 'boolean' or kind == 'nil') and 'literal' or kind == 'function' and 'functionName' or 'identifier'
 local labelKind = node.label:match('%(.*%)$') and 'functionName' or object and 'blizzardFunction' or 'globalVariable'
 return color(node.expandable and (node.open and '- ' or '+ ') or '  ', 'comment')
  .. color(node.label, labelKind) .. color(' = ', 'operator')
  .. color(self:Text(node.value):sub(1, 180), valueKind) .. (node.cycle and color(' [<]', 'comment') or '')
end

function I:Tooltip(row)
 local node = row.node
 local hidden = self:Secret(node.value) and (type(node.value) == 'number' or type(node.value) == 'string')
 addon.DebugUI:ValueTooltip(row, self:RowText(node), hidden, node.value, node.label:gsub('|', '||') .. ' = |cff88ff88<secret>|r')
end

function I:Render()
 if not self.panel then return end
 self.rows = self:Rows()
 local scroll, content = self.panel.scroll, self.panel.content
 content:SetHeight(math.max(1, #self.rows * 22))
 local first = math.floor(scroll:GetVerticalScroll() / 22)
 for index = 1, math.min(80, math.ceil(scroll:GetHeight() / 22) + 2) do
  local row = self.buttons[index]
  if not row then
   row = CreateFrame('Button', nil, content); self.buttons[index] = row
   row:SetHeight(22); row:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
   row.text = UI:Text(row, '', 11); row.text:SetAllPoints(); row.text:SetJustifyH('LEFT'); row.text:SetWordWrap(false)
   row:SetScript('OnClick', function(_, button)
    local node = row.node
    if button == 'RightButton' then self:Menu(row, node)
    elseif node.cycle or node.label == 'GetParent()' then self:Navigate(node.value, self:Text(node.value))
    elseif node.expandable then node.open = not node.open; if node.open then self:Expand(node) end; self:Render() end
   end)
   row:SetScript('OnEnter', function() self:Tooltip(row) end)
   row:SetScript('OnLeave', function() addon.DebugUI:HideTooltip(row) end)
  end
  local item = self.rows[first + index]
  if item then
   row.node = item.node
   row:ClearAllPoints(); row:SetPoint('TOPLEFT', item.depth * 12, -(first + index - 1) * 22); row:SetPoint('RIGHT')
   local node = item.node
   row.text:SetText(self:RowText(node))
   row:Show()
  else row:Hide() end
 end
 local visible = math.min(80, math.ceil(scroll:GetHeight() / 22) + 2)
 for index = visible + 1, #self.buttons do self.buttons[index]:Hide() end
end

function I:Copy(text)
 local box = self.panel.copy
 box:Show(); box:SetText(text); box:SetFocus(); box:HighlightText()
end

function I:Insert(node, declaration)
 if addon.Query.Editor:IsReadOnly(C.input) then return end
 local path = node.path or self:Path(node.value)
 if not path then return end
 local text = (declaration and ('local inspected = ' .. path) or path) .. '\n'
 if addon.Snippets:Insert(text, self.target) then self.target = addon.Snippets:Capture(C.input) end
end

function I:Menu(owner, node)
 self.target = addon.Snippets:Capture(C.input)
 local entries = { { text = L.apiCopyName, action = function() self:Copy(node.label) end } }
 if self:Readable(node.value) and (type(node.value) == 'table' or self:Widget(node.value)) then
  entries[#entries + 1] = { text = L.inspectorOpen, action = function() self:Navigate(node.value, self:Text(node.value)) end }
 end
 local path = node.path or self:Path(node.value)
 if path and self:Readable(node.value) then
  entries[#entries + 1] = { text = L.inspectorCopyPath, action = function() self:Copy(path) end }
  if not addon.Query.Editor:IsReadOnly(C.input) then
   entries[#entries + 1] = { text = L.inspectorInsert, action = function() self:Insert(node) end }
   entries[#entries + 1] = { text = L.inspectorLocal, action = function() self:Insert(node, true) end }
  end
 end
 local literal = self:Literal(node.value)
 if literal then entries[#entries + 1] = { text = L.inspectorCopyValue, action = function() self:Copy(literal) end } end
 W:OpenMenu(owner, entries)
end

function I:UpdateNavigation()
 local parent = self.root and self:Call(self.root.value, 'GetParent')
 self.parentValue = parent
 self.panel.parent:SetShown(parent ~= nil and not rawequal(parent, self.root.value))
 self.panel.back:SetShown(self.history and #self.history > 0 or false)
end

function I:Navigate(value, label)
 if not self:Readable(value) or not self.root or rawequal(value, self.root.value) then return end
 self.history = self.history or {}
 self.history[#self.history + 1] = { root = self.root, search = self.panel.search:GetText(), scroll = self.panel.scroll:GetVerticalScroll() }
 self:Show(value, label, true)
end

function I:Back()
 local entry = self.history and table.remove(self.history)
 if not entry then return end
 self.root = entry.root
 self.panel.search:SetText(entry.search)
 self.panel.scroll:SetVerticalScroll(entry.scroll)
 self:UpdateNavigation(); self:Render()
end

function I:Show(value, label, keepHistory)
 if not self:Readable(value) then return end
 self:StopPicking()
 if not keepHistory then self.history = {} end
 W:Show()
 if not self.panel then self:Build() end
 self.target = addon.Snippets:Capture(C.input)
 self.root = self:Node(label or self:Text(value), value, self:Path(value))
 self.root.open = true; self:Expand(self.root)
 self.panel.search:SetText(''); self.panel.scroll:SetVerticalScroll(0)
 self:UpdateNavigation()
 self.panel:Show(); self:Render()
 C.input:ClearFocus()
end

function I:Build()
 local panel = CreateFrame('Frame', 'LuaWorkbenchInspector', UIParent); self.panel = panel; self.buttons = {}
 panel:SetSize(math.min(460, UIParent:GetWidth() - 32), math.min(570, UIParent:GetHeight() - 32))
 panel:SetFrameStrata('DIALOG'); panel:EnableMouse(true)
 UI:Background(panel, UI.colors.background); UI:Border(panel, { 0.3, 0.4, 0.5, 1 })
 if W.window:GetRight() + panel:GetWidth() + 8 < UIParent:GetWidth() then panel:SetPoint('TOPLEFT', W.window, 'TOPRIGHT', 8, 0)
 else panel:SetPoint('TOPRIGHT', UIParent, 'TOPRIGHT', -16, -80) end
 UI:MovablePanel(panel, 'inspector')
 local title = UI:Text(panel, L.inspectorTitle, 14); title:SetPoint('TOPLEFT', 12, -12)
 UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end):SetPoint('TOPRIGHT', -4, -4)
 panel.back = UI:Button(panel, 'previous', L.navigationBack, function() self:Back() end)
 panel.back:SetPoint('TOPRIGHT', -36, -4)
 panel.parent = UI:Button(panel, '^', L.inspectorParent, function() if self.parentValue then self:Navigate(self.parentValue, self:Text(self.parentValue)) end end)
 panel.parent:SetPoint('TOPRIGHT', -68, -4)
 panel.dragHandle:SetPoint('TOPRIGHT', panel.parent, 'TOPLEFT', -4, 4)
 local pick = UI:Action(panel, 'frameStack', L.inspectorPick, L.inspectorPickHelp, function() self:Pick() end); pick:SetPoint('TOPLEFT', 10, -38)
 local refresh = UI:Action(panel, 'refresh', L.inspectorRefresh, L.inspectorRefresh, function()
  if self.root then self:Show(self.root.value, self.root.label, true) end
 end); refresh:SetPoint('LEFT', pick, 'RIGHT', 10, 0)
 local hint = UI:Text(panel, L.inspectorSearch, 10); hint:SetPoint('TOPLEFT', 12, -76)
 local search = CreateFrame('EditBox', nil, panel); panel.search = search
 search:SetPoint('TOPLEFT', 12, -94); search:SetPoint('TOPRIGHT', -12, -94); search:SetHeight(26)
 search:SetFontObject(ChatFontNormal); search:SetAutoFocus(false); UI:Background(search, UI.colors.hover)
 search:SetScript('OnTextChanged', function() if self.root then panel.scroll:SetVerticalScroll(0); self:Render() end end)
 search:SetScript('OnEscapePressed', function() search:ClearFocus() end); UI:SearchClear(search)
 local scroll = UI:Scroll(panel); panel.scroll = scroll
 scroll:SetPoint('TOPLEFT', 12, -130); scroll:SetPoint('BOTTOMRIGHT', -24, 74)
 local content = CreateFrame('Frame', nil, scroll); panel.content = content; content:SetSize(panel:GetWidth() - 36, 1); scroll:SetScrollChild(content)
 scroll:HookScript('OnVerticalScroll', function() self:Render() end)
 panel:SetResizable(true); panel:SetResizeBounds(340, 300, math.max(340, UIParent:GetWidth() - 32), math.max(300, UIParent:GetHeight() - 32))
 local grip = CreateFrame('Button', nil, panel); grip:SetSize(18, 18); grip:SetPoint('BOTTOMRIGHT')
 grip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
 grip:SetScript('OnMouseDown', function() panel:StartSizing('BOTTOMRIGHT') end)
 grip:SetScript('OnMouseUp', function() panel:StopMovingOrSizing() end)
 panel:SetScript('OnSizeChanged', function() content:SetWidth(panel:GetWidth() - 36); if self.root then self:Render() end end)
 local note = UI:Text(panel, L.inspectorSession, 10); note:SetPoint('BOTTOMLEFT', 12, 42); note:SetPoint('RIGHT', -12, 0); note:SetWordWrap(true)
 local copy = CreateFrame('EditBox', nil, panel); panel.copy = copy
 copy:SetPoint('BOTTOMLEFT', 12, 10); copy:SetPoint('BOTTOMRIGHT', -12, 10); copy:SetHeight(26)
 copy:SetFontObject(ChatFontNormal); copy:SetAutoFocus(false); UI:Background(copy, UI.colors.hover)
 copy:SetScript('OnEscapePressed', function() copy:ClearFocus() end)
 UI:Tooltip(copy, L.copyOutputHint)
 panel:SetScript('OnHide', function() panel:StopMovingOrSizing(); search:ClearFocus(); copy:ClearFocus(); addon.DebugUI:HideTooltip(); if W.contextMenu then W.contextMenu:Hide() end end)
 _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchInspector'
end

function I:StopPicking()
 self.picking = nil
 if self.pickerDriver then self.pickerDriver:Hide() end
 if self.picker then self.picker:Hide() end
 if self.highlight then self.highlight:Hide() end
 self.selected, self.highlightTarget = nil, nil
end

function I:Pick()
 if self.picking then self:StopPicking(); return end
 local loader = _G.C_AddOns and _G.C_AddOns.LoadAddOn or _G.LoadAddOn
 if not loader or not loader('Blizzard_DebugTools') or not _G.KeyCommand_Create then C:SetStatus(L.developerToolUnavailable, true); return end
 C.input:ClearFocus()
 addon.DebugUI:HideTooltip(nil, 'frame-picker')
 if self.panel then self.panel:Hide() end
 if not self.picker then
  local picker = CreateFrame('GameTooltip', 'LuaWorkbenchFramePicker', UIParent, 'SharedTooltipTemplate'); self.picker = picker
  picker:SetFrameStrata('TOOLTIP'); picker:EnableMouse(false); picker:SetClampedToScreen(true)
  self.highlight = CreateFrame('Frame', nil, UIParent); self.highlight:SetFrameStrata('TOOLTIP'); self.highlight:EnableMouse(false)
  UI:Border(self.highlight, { 1, 0.8, 0.1, 1 })
  picker.commands = {
   _G.KeyCommand_Create(function() self.delta = 1 end, _G.KeyCommand.RUN_ON_DOWN, _G.KeyCommand_CreateKey('LALT')),
   _G.KeyCommand_Create(function() self.delta = -1 end, _G.KeyCommand.RUN_ON_DOWN, _G.KeyCommand_CreateKey('RALT')),
   _G.KeyCommand_Create(function() local value = self.selected; if value then self:Show(value) end end, _G.KeyCommand.RUN_ON_UP, _G.KeyCommand_CreateKey('CTRL')),
   _G.KeyCommand_Create(function() self:StopPicking() end, _G.KeyCommand.RUN_ON_DOWN, _G.KeyCommand_CreateKey('ESCAPE')),
  }
  self.pickerDriver = CreateFrame('Frame', nil, UIParent)
  self.pickerDriver:Hide()
  self.pickerDriver:SetScript('OnUpdate', function(_, elapsed)
   _G.KeyCommand_Update(picker.commands)
   if not self.picking then return end
   self.elapsed = (self.elapsed or 0) + elapsed
   if self.elapsed < 0.1 and not self.delta then return end
   self.elapsed = 0
   self:UpdatePicker()
  end)
 end
 self.picker:SetOwner(UIParent, 'ANCHOR_NONE'); self.picker:ClearAllPoints(); self.picker:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 24, 100)
 self.elapsed, self.delta, self.picking = 0, nil, true
 self:UpdatePicker()
 if self.picking then self.pickerDriver:Show() end
end

function I:UpdatePicker()
 local picker = self.picker
 -- These visible regions must not become candidates in their own frame stack.
 -- Hide/query/show runs synchronously, before the next rendered frame.
 picker:Hide()
 self.highlight:Hide()
 picker:SetOwner(UIParent, 'ANCHOR_NONE')
 picker:ClearAllPoints(); picker:SetPoint('BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 24, 100)
 local ok, value = pcall(picker.SetFrameStack, picker, false, true, self.delta or 0)
 self.delta = nil
 if not ok then
  self:StopPicking()
  C:SetStatus(L.developerToolUnavailable, true)
  C:Write(L.inspectorTitle, C:Format(value))
  return
 end
 self.selected = not self:Secret(value) and value or nil
 picker:AddLine(L.inspectorPickHelp, 1, 0.8, 0.3, true)
 picker:Show()
 if self:Widget(self.selected) then
  local anchored = pcall(function()
   if not rawequal(self.highlightTarget, self.selected) then
    self.highlight:ClearAllPoints(); self.highlight:SetAllPoints(self.selected)
    self.highlightTarget = self.selected
   end
   self.highlight:Show()
  end)
  if not anchored then self.highlightTarget = nil; self.highlight:Hide() end
 else self.highlightTarget = nil end
end
