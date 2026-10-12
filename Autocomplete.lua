local _, addon = ...
local A = { limit = 8 }
addon.Autocomplete = A
local E, UI, L = addon.Query.Editor, addon.UI, addon.L

function A:Enabled(input)
 return input == addon.Query.Console.input and addon.Workspace.db.options.autocomplete ~= false and not E:IsReadOnly(input)
end

function A:Names()
 local api = addon.APIHelp
 if self.revision == api.revision then return self.names end
 local names, seen = {}, {}
 for name in pairs(api.index) do
  seen[name] = true
  local namespace = name:match('^([%w_]+)%.')
  if namespace then seen[namespace] = true end
 end
 for name in pairs(seen) do names[#names + 1] = name end
 table.sort(names)
 self.names, self.revision = names, api.revision
 return names
end

function A:Visible(analysis, cursor)
 local names = {}
 for _, def in ipairs(analysis.definitions) do
  local scope = def.scope
  local position = def.position0 or def.visible0
  if position < cursor and (def.visible0 or position) <= cursor
   and scope and scope.start0 <= cursor and (not scope.finish0 or cursor < scope.finish0) then
   local old = names[def.name]
   if not old or (old.position0 or old.visible0) < position then names[def.name] = def end
  end
 end
 for name, definitions in pairs(analysis.globals) do
  if not names[name] then
   for _, def in ipairs(definitions) do if def.position0 < cursor then names[name] = def end end
  end
 end
 return names
end

function A:Context(source, cursor)
 if #source > 100000 then return end
 local analysis = addon.Analysis:Get(source)
 if analysis.limited then return end
 for _, token in ipairs(analysis.tokens) do
  if cursor >= token.start and cursor <= token.finish and (token.kind == 'comment' or token.kind == 'string') then
   if cursor < token.finish or token.closed ~= true then return end
  end
 end
 local prefix = source:sub(1, cursor):match('([%a_][%w_%.]*)$') or ''
 local previous = source:sub(cursor - #prefix, cursor - #prefix)
 if previous == ':' or previous == '.' then return end
 return { source=source, cursor=cursor, prefix=prefix, start=cursor-#prefix, analysis=analysis, visible=self:Visible(analysis, cursor) }
end

function A:Suggest(context, manual)
 local prefix, found = context.prefix, {}
 if prefix == '' and not manual then return found end
 if #prefix < 2 and not manual and not prefix:find('.', 1, true) then return found end
 local function add(name, kind)
  if name:sub(1, #prefix) == prefix and name ~= prefix then found[#found + 1] = { name=name, kind=kind } end
 end
 local namespace = prefix:match('^([%w_]+)%.')
 if not namespace then
  for name, def in pairs(context.visible) do add(name, def.kind) end
  table.sort(found, function(a,b) return a.name < b.name end)
 end
 if not namespace or not context.visible[namespace] then
  local names = self:Names()
  local lo, hi = 1, #names + 1
  while lo < hi do local mid = math.floor((lo + hi) / 2); if names[mid] and names[mid] < prefix then lo = mid + 1 else hi = mid end end
  for index = lo, #names do
   local name = names[index]
   if name:sub(1, #prefix) ~= prefix then break end
   local root = name:match('^([%w_]+)%.')
   if not context.visible[name] and not (root and context.visible[root]) then add(name, 'blizzardFunction') end
   if #found >= self.limit then break end
  end
 end
 while #found > self.limit do table.remove(found) end
 return found
end

function A:Signature(context)
 local stack, tokens = {}, {}
 for _, token in ipairs(context.analysis.tokens) do
  if token.start > context.cursor then break end
  if token.kind ~= 'space' and token.kind ~= 'newline' and token.kind ~= 'comment' and token.kind ~= 'string' then
   local text = token.text
   if text == '(' or text == '{' or text == '[' then
    local name = ''
    if text == '(' then
     local index = #tokens
     if tokens[index] and tokens[index].text:match('^[%a_][%w_]*$') then
      name = tokens[index].text; index = index - 1
      while tokens[index] and tokens[index].text == '.' and tokens[index-1] do name = tokens[index-1].text .. '.' .. name; index = index-2 end
      if tokens[index] and (tokens[index].text == ':' or tokens[index].text == 'function') then name = '' end
     end
    end
    stack[#stack + 1] = { opening=text, name=name, argument=1 }
   elseif text == ')' or text == '}' or text == ']' then table.remove(stack)
   elseif text == ',' and stack[#stack] then stack[#stack].argument = stack[#stack].argument + 1 end
   tokens[#tokens+1] = token
  end
 end
 for index = #stack, 1, -1 do
  local call = stack[index]
  local root = call.name:match('^[%w_]+')
  local info = addon.APIHelp.index[call.name]
  if info and not context.visible[root] then
   local args = {}
   for n, arg in ipairs(info.Arguments or {}) do
    local text = arg.Name .. ((arg.Nilable or arg.Default ~= nil) and '?' or '') .. ': ' .. (arg.Type == 'bool' and 'boolean' or arg.Type or '?')
    if arg.Default ~= nil then text = text .. ' = ' .. tostring(arg.Default) end
    args[#args+1] = '|c' .. E:Color(n == call.argument and 'functionName' or 'parameter') .. text:gsub('|','||') .. '|r'
   end
   return call.name .. '(' .. table.concat(args, ', ') .. ')'
  end
 end
end

function A:RestoreArrows()
 if self.arrowBox then self.arrowBox:SetAltArrowKeyMode(self.savedArrowMode); self.arrowBox = nil end
 self.arrowKey, self.arrowOrigin = nil, nil
end

function A:Hide()
 self:RestoreArrows()
 if self.panel then self.panel:Hide() end
 self.context, self.items, self.input, self.pending = nil, nil, nil, nil
end

function A:Build()
 if self.panel then return end
 local panel = CreateFrame('Frame', nil, UIParent); self.panel = panel
 panel:SetFrameStrata('TOOLTIP'); panel:SetClampedToScreen(true); panel:EnableMouse(false)
 UI:Background(panel, UI.colors.panel); UI:Border(panel, {0.3,0.4,0.5,1})
 self.rows = {}
 for index = 1, self.limit do
  local text = UI:Text(panel, '', 12); text:SetPoint('TOPLEFT', 8, -8-(index-1)*20); text:SetPoint('RIGHT', -8, 0); text:SetWordWrap(false)
  self.rows[index] = text
 end
 self.selection = panel:CreateTexture(nil, 'ARTWORK'); self.selection:SetColorTexture(0.15,0.3,0.48,1)
 self.hint = UI:Text(panel, '', 11); self.hint:SetWordWrap(true); self.hint:SetJustifyH('LEFT')
end

function A:Draw()
 self:Build()
 local count = #self.items
 if count > 0 then
  if self.arrowBox ~= self.input.editBox then
   self:RestoreArrows()
   self.arrowBox = self.input.editBox
   self.savedArrowMode = self.arrowBox:GetAltArrowKeyMode() == true
  end
  self.arrowBox:SetAltArrowKeyMode(false)
 else self:RestoreArrows() end
 for index, row in ipairs(self.rows) do
  local item = self.items[index]
  row:SetText(item and ('|c' .. E:Color(item.kind or 'identifier') .. item.name .. '|r') or ''); row:SetShown(item ~= nil)
 end
 self.selection:ClearAllPoints(); self.selection:SetPoint('TOPLEFT', 4, -6-((self.selected or 1)-1)*20); self.selection:SetSize(412,20); self.selection:SetShown(count>0)
 self.hint:ClearAllPoints(); self.hint:SetPoint('TOPLEFT', 8, -10-count*20); self.hint:SetWidth(404)
 self.hint:SetText((self.signature or '') .. (count>0 and ('\n' .. L.autocompleteHelp) or ''))
 self.panel:SetSize(420, 20+count*20+self.hint:GetStringHeight())
 local input = self.input
 self.panel:ClearAllPoints(); self.panel:SetPoint('TOPLEFT', input.editBox, 'TOPLEFT', input.cursorX or 0, (input.cursorY or 0)-20)
 self.panel:Show()
end

function A:Update(input, manual)
 if not self:Enabled(input) or not input.editBox:HasFocus() then self:Hide(); return end
 if not addon.APIHelp.ready and not self.loadTried then self.loadTried = true; addon.APIHelp:Load(true) end
 local context = self:Context(input:GetText(), input.editBox:GetCursorPosition())
 if not context then self:Hide(); return end
 self.lastSource, self.lastCursor, self.lastScript = context.source, context.cursor, addon.Workspace.current
 self.pending = nil
 self.input, self.context, self.selected = input, context, 1
 self.items, self.signature = self:Suggest(context, manual), self:Signature(context)
 if #self.items == 0 and not self.signature then self:Hide(); return end
 self:Draw()
end

function A:Tick(input, elapsed)
 if not self:Enabled(input) or not input.editBox:HasFocus() then if self.input == input then self:Hide() end; return end
 local source, cursor = input:GetText(), input.editBox:GetCursorPosition()
 if source ~= self.lastSource or cursor ~= self.lastCursor or addon.Workspace.current ~= self.lastScript then
  self.lastSource, self.lastCursor, self.lastScript = source, cursor, addon.Workspace.current
  self.pending = 0
  if self.panel then self.panel:Hide() end
 end
 if self.pending then
  self.pending = self.pending + elapsed
  if self.pending >= 0.15 then self.pending = nil; self:Update(input) end
 end
end

function A:Accept(input)
 if self.input ~= input or not self.panel or not self.panel:IsShown() or not self.context or not self.items or not self.items[self.selected] then return false end
 local context, name = self.context, self.items[self.selected].name
 if input:GetText() ~= context.source or input.editBox:GetCursorPosition() ~= context.cursor or E:IsReadOnly(input) then self:Hide(); return false end
 local finish = context.cursor
 local suffix = context.source:sub(finish+1):match('^[%w_]*') or ''
 E:SetSource(input, context.source:sub(1, context.start) .. name .. context.source:sub(finish+#suffix+1), context.start+#name)
 self:Hide(); return true
end

function A:Key(input, key)
 if not self:Enabled(input) then return end
 if self:Arrow(input, key, 'key') then return true end
 if key == 'SPACE' and _G.IsControlKeyDown and IsControlKeyDown() then
  addon.APIHelp:Load(true); self:Update(input, true)
  self.keySource, self.keyCursor = input:GetText(), input.editBox:GetCursorPosition()
  return true
 end
end

function A:Arrow(input, key, origin)
 if not self:Enabled(input) then return end
 if self.input == input and self.panel and self.panel:IsShown() and #self.items>0 and (key == 'UP' or key == 'DOWN')
  and not (_G.IsAltKeyDown and IsAltKeyDown()) and not (_G.IsShiftKeyDown and IsShiftKeyDown()) then
  origin = origin or 'native'
  -- Some EditBoxes dispatch both callbacks for one press; consume the second.
  if self.arrowKey == key and self.arrowOrigin and self.arrowOrigin ~= origin then
   self.arrowKey, self.arrowOrigin = nil, nil
   return true
  end
  self.arrowKey, self.arrowOrigin = key, origin
  self.selected = (self.selected-1+(key=='UP' and -1 or 1)) % #self.items+1
  self.keySource, self.keyCursor = self.context.source, self.context.cursor
  input.editBox:SetCursorPosition(self.keyCursor)
  self.lastSource, self.lastCursor, self.pending = self.keySource, self.keyCursor, nil
  self:Draw(); return true
 end
end
