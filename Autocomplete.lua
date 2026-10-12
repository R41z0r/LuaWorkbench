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
 local names, seen, kinds = {}, {}, {}
 for name in pairs(api.index) do
  seen[name], kinds[name] = true, 'blizzardFunction'
  local namespace = name:match('^([%w_]+)%.')
  if namespace then seen[namespace] = true end
 end
 for name,entry in pairs(api.catalog or {}) do
  if entry.kind == 'apiEnums' and name:match('^Enum%.[%a_][%w_]*$') then
   seen.Enum, seen[name], kinds.Enum, kinds[name] = true, true, 'identifier', 'identifier'
   for _,field in ipairs(entry.info.Fields or {}) do
    if type(field.Name) == 'string' and field.Name:match('^[%a_][%w_]*$') then
     local member=name..'.'..field.Name
     seen[member], kinds[member]=true,'identifier'
    end
   end
  end
 end
 for name in pairs(seen) do names[#names + 1] = name end
 table.sort(names)
 self.names, self.nameKinds, self.revision = names, kinds, api.revision
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

function A:Context(source, cursor, quick)
 if #source > 100000 then return end
 local prefix = source:sub(1, cursor):match('([%a_][%w_%.:]*)$') or ''
 -- Automatic completion needs declarations before the active name, not the
 -- unchanged document after it. The prefix analysis stays cached as it grows.
 local analysisSource, analysisCursor = source, cursor
 if quick and #source > 20000 then
  analysisCursor = cursor - #prefix
  analysisSource = source:sub(1, analysisCursor)
 end
 local analysis = addon.Analysis:Get(analysisSource)
 if analysis.limited then return end
 local inString=false
 for _, token in ipairs(analysis.tokens) do
  if analysisCursor >= token.start and analysisCursor <= token.finish and (token.kind == 'comment' or token.kind == 'string') then
   if analysisCursor < token.finish or token.closed ~= true then
    if token.kind == 'comment' then return end
    inString=true
   end
  end
 end
 local previous = source:sub(cursor - #prefix, cursor - #prefix)
 if not inString and (previous == ':' or previous == '.') then return end
 return { source=source, cursor=cursor, prefix=prefix, start=cursor-#prefix, analysis=analysis, visible=self:Visible(analysis, analysisCursor), inString=inString }
end

function A:Alias(context, name)
 local definition = context.visible[name]
 if not definition then return end
 local namespace
 for _,entry in ipairs(definition.apiAliases or {}) do
  if entry.position0 <= (context.lookupCursor or context.cursor) then namespace = entry.namespace end
 end
 return namespace or nil
end

-- Read only values established before the caret; aliases share table identity.
function A:HelperValue(value, cursor)
 local seen={}
 for _=1,8 do
  if not (value and value.module) then return value,cursor end
  if seen[value.module] then return end
  seen[value.module]=true
  local module=addon.Helpers:Resolve(value.module)
  if not module then return end
  local source=addon.Workspace:NormalizeSource(module.source)
  local analysis=addon.Analysis:Get(source)
  value,cursor=analysis.exportValue,#source+1
 end
end

function A:Value(context, path)
 local root = path:match('^[%a_][%w_]*')
 local definition = root and context.visible[root]
 local value
 for _,entry in ipairs(definition and definition.completionValues or {}) do
  if entry.position0 <= (context.lookupCursor or context.cursor) then value=entry.value end
 end
 local valueCursor
 value,valueCursor=self:HelperValue(value,context.lookupCursor or context.cursor)
 if value and value.completionInvalidated0 and value.completionInvalidated0 <= valueCursor then return end
 for name in path:sub(root and #root+1 or 1):gmatch('[%.:]([%a_][%w_]*)') do
  local history=value and value.completionMembers and value.completionMembers[name]
  value=nil
  for _,entry in ipairs(history or {}) do if entry.position0 <= valueCursor then value=entry.value end end
  value,valueCursor=self:HelperValue(value,valueCursor)
 end
 if value and value.completionInvalidated0 and value.completionInvalidated0 <= valueCursor then return end
 return value or nil,valueCursor
end

function A:Suggest(context, manual)
 if context.inString then return {} end
 local prefix, found = context.prefix, {}
 if prefix == '' and not manual then return found end
 if #prefix < 2 and not manual and not prefix:find('.', 1, true) then return found end
 local function add(name, kind)
  if name:sub(1, #prefix) == prefix and name ~= prefix then found[#found + 1] = { name=name, kind=kind } end
 end
 local path, separator = prefix:match('^(.*)([%.:])[%w_]*$')
 if path then
  local owner,valueCursor=self:Value(context,path)
  for name,history in pairs(owner and owner.completionMembers or {}) do
   local value
   for _,entry in ipairs(history) do if entry.position0 <= valueCursor then value=entry.value end end
   if value and (separator ~= ':' or value.parameters) then
    add(path..separator..name,value.parameters and 'functionName' or 'identifier')
   end
  end
  table.sort(found,function(a,b) return a.name<b.name end)
 end
 local namespace = prefix:match('^([%w_]+)[%.:]')
 local alias = namespace and self:Alias(context,namespace)
 local lookup = alias and (alias..prefix:sub(#namespace+1)) or prefix
 if not namespace then
  for name, def in pairs(context.visible) do add(name, def.kind) end
  table.sort(found, function(a,b) return a.name < b.name end)
 end
 if alias or not namespace or not context.visible[namespace] then
  local names = self:Names()
  local lo, hi = 1, #names + 1
  while lo < hi do local mid = math.floor((lo + hi) / 2); if names[mid] and names[mid] < lookup then lo = mid + 1 else hi = mid end end
  for index = lo, #names do
   local name = names[index]
   if name:sub(1, #lookup) ~= lookup then break end
   local root = name:match('^([%w_]+)%.')
   local parent=lookup:match('^(.*%.)')
   local direct=not parent or not name:sub(#parent+1):find('.',1,true)
   if direct then
    if alias then add(namespace..name:sub(#alias+1), self.nameKinds[name] or 'identifier')
    elseif not context.visible[name] and not (root and context.visible[root]) then add(name, self.nameKinds[name] or 'identifier') end
   end
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
      while tokens[index] and (tokens[index].text == '.' or tokens[index].text == ':') and tokens[index-1] do name = tokens[index-1].text .. tokens[index].text .. name; index = index-2 end
      if tokens[index] and (tokens[index].text == ':' or tokens[index].text == 'function') then name = '' end
     end
    end
    stack[#stack + 1] = { opening=text, name=name, argument=1, position0=token.start-1 }
   elseif text == ')' or text == '}' or text == ']' then table.remove(stack)
   elseif text == ',' and stack[#stack] then stack[#stack].argument = stack[#stack].argument + 1 end
   tokens[#tokens+1] = token
  end
 end
 for index = #stack, 1, -1 do
  local call = stack[index]
  local own=self:Value(context,call.name)
  if own and own.parameters then
   local args={}
   if own.method then args[1]='self' end
   for _,name in ipairs(own.parameters) do args[#args+1]=name end
   if call.name:find(':',1,true) then table.remove(args,1) end
   for n,name in ipairs(args) do
    args[n]='|c'..E:Color(n==call.argument and 'functionName' or 'parameter')..name..'|r'
   end
   return call.name..'('..table.concat(args,', ')..')', call.position0
  end
  local root = call.name:match('^[%w_]+')
  local alias = root and self:Alias(context,root)
  local canonical = alias and (alias..call.name:sub(#root+1)) or call.name
  local info = addon.APIHelp.index[canonical]
  if info and (alias or not context.visible[root]) then
   local args = {}
   for n, arg in ipairs(info.Arguments or {}) do
    local text = arg.Name .. ((arg.Nilable or arg.Default ~= nil) and '?' or '') .. ': ' .. (arg.Type == 'bool' and 'boolean' or arg.Type or '?')
    if arg.Default ~= nil then text = text .. ' = ' .. tostring(arg.Default) end
    args[#args+1] = '|c' .. E:Color(n == call.argument and 'functionName' or 'parameter') .. text:gsub('|','||') .. '|r'
   end
   return call.name .. '(' .. table.concat(args, ', ') .. ')', call.position0
  end
 end
end

function A:RestoreArrows()
 if self.arrowBox then self.arrowBox:SetAltArrowKeyMode(self.savedArrowMode); self.arrowBox = nil end
 self.arrowKey, self.arrowOrigin = nil, nil
end

function A:Hide()
 self.keySource, self.keyCursor = nil, nil
 self:RestoreArrows()
 if self.panel then self.panel:Hide() end
 if self.signaturePanel then self.signaturePanel:Hide() end
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
 local help=CreateFrame('Frame',nil,UIParent);self.signaturePanel=help
 help:SetFrameStrata('TOOLTIP');help:SetClampedToScreen(true);help:EnableMouse(false)
 UI:Background(help,UI.colors.panel);UI:Border(help,{0.3,0.4,0.5,1})
 self.signatureText=UI:Text(help,'',12)
 self.signatureText:SetPoint('TOPLEFT',8,-8);self.signatureText:SetWidth(504)
 self.signatureText:SetWordWrap(true);self.signatureText:SetJustifyH('LEFT')
 help:Hide()
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
  local text = item and ('|c' .. E:Color(item.kind or 'identifier') .. item.name .. '|r') or ''
  if row:GetText() ~= text then row:SetText(text) end
  if row:IsShown() ~= (item ~= nil) then row:SetShown(item ~= nil) end
 end
 self.selection:ClearAllPoints(); self.selection:SetPoint('TOPLEFT', 4, -6-((self.selected or 1)-1)*20); self.selection:SetSize(412,20); self.selection:SetShown(count>0)
 self.hint:ClearAllPoints(); self.hint:SetPoint('TOPLEFT', 8, -10-count*20); self.hint:SetWidth(404)
 self.hint:SetText(L.autocompleteHelp)
 self.panel:SetSize(420, 20+count*20+self.hint:GetStringHeight())
 local input = self.input
 self.panel:ClearAllPoints(); self.panel:SetPoint('TOPLEFT', input.editBox, 'TOPLEFT', input.cursorX or 0, (input.cursorY or 0)-20)
 self.panel:SetShown(count>0)
 if self.signature then
  if self.signatureText:GetText() ~= self.signature then self.signatureText:SetText(self.signature) end
  self.signaturePanel:SetSize(520,16+self.signatureText:GetStringHeight())
  self.signaturePanel:ClearAllPoints()
  self.signaturePanel:SetPoint('BOTTOMLEFT',input.editBox,'TOPLEFT',input.cursorX or 0,(input.cursorY or 0)+4)
  self.signaturePanel:Show()
 else self.signaturePanel:Hide() end
end

function A:Update(input, manual, signatureOnly)
 if not self:Enabled(input) or not input.editBox:HasFocus() then self:Hide(); return end
 if not addon.APIHelp.ready and not self.loadTried then self.loadTried = true; addon.APIHelp:Load(true) end
 local context = self:Context(input:GetText(), input.editBox:GetCursorPosition(), not manual)
 if not context then self:Hide(); return end
 self.lastSource, self.lastCursor, self.lastScript = context.source, context.cursor, addon.Workspace.current
 self.pending = nil
 context.manual, context.apiRevision = manual, addon.APIHelp.revision
 self.input, self.context, self.selected = input, context, 1
 local previousCall=self.signatureCall
 self.items=signatureOnly and {} or self:Suggest(context,manual)
 self.signature,self.signatureCall=self:Signature(context)
 if signatureOnly and previousCall ~= self.signatureCall then self.signature=nil end
 if #self.items == 0 and not self.signature then self:Hide(); return end
 self:Draw()
end

-- Only refine the active identifier when both surrounding source regions match.
-- Reuse scope data at the original position, never shifted future declarations.
function A:Refine(input, source, cursor)
 local old = self.context
 if self.input ~= input or not old or old.apiRevision ~= addon.APIHelp.revision or self.lastScript ~= addon.Workspace.current
  or not self.panel or not self.panel:IsShown() or source == old.source then return false end
 local prefix = source:sub(1,cursor):match('([%a_][%w_%.:]*)$') or ''
 local start = cursor - #prefix
 if prefix == '' or start ~= old.start
  or prefix:match('^(.*[%.:])') ~= old.prefix:match('^(.*[%.:])')
  or source:sub(1,start) ~= old.source:sub(1,old.start)
  or source:sub(cursor+1) ~= old.source:sub(old.cursor+1) then return false end
 local selected = self.items and self.items[self.selected or 1]
 local name = selected and selected.name
 local context = {source=source,cursor=cursor,prefix=prefix,start=start,
  analysis=old.analysis,visible=old.visible,inString=old.inString,
  lookupCursor=old.lookupCursor or old.cursor,manual=old.manual,apiRevision=old.apiRevision}
 local items = self:Suggest(context, context.manual)
 if selected and name ~= prefix and name:sub(1,#prefix) == prefix then
  local present = false
  for _,item in ipairs(items) do if item.name == name then present=true;break end end
  if not present then items[math.min(#items+1,self.limit)] = selected end
 end
 self.context, self.items, self.selected = context, items, 1
 for index,item in ipairs(items) do if item.name == name then self.selected=index;break end end
 self.lastSource, self.lastCursor, self.pending = source,cursor,nil
 self.keySource, self.keyCursor = nil,nil
 if #items == 0 and not self.signature then self:Hide() else self:Draw() end
 return true
end

function A:RestoreCursor(input)
 local state=input.queryEditor
 if self.input ~= input or self.keyCursor == nil or not state or state.busy
  or input:GetText() ~= self.keySource then return end
 if input.editBox:GetCursorPosition() ~= self.keyCursor then
  state.busy=true
  input.editBox:SetCursorPosition(self.keyCursor)
  state.busy=nil
  state.actionCursor=self.keyCursor
 end
end

function A:Tick(input, elapsed)
 if not self:Enabled(input) or not input.editBox:HasFocus() then if self.input == input then self:Hide() end; return end
 self:RestoreCursor(input)
 local source, cursor = input:GetText(), input.editBox:GetCursorPosition()
 if source ~= self.lastSource or cursor ~= self.lastCursor or addon.Workspace.current ~= self.lastScript then
  if self:Refine(input,source,cursor) then return end
  self.pendingSuggestions=self.lastSource ~= nil and source ~= self.lastSource
   and self.lastScript == addon.Workspace.current
  local keepSignature=self.input == input and self.signaturePanel and self.signaturePanel:IsShown() and self.signature
   and self.lastScript == addon.Workspace.current
  self.lastSource, self.lastCursor, self.lastScript = source, cursor, addon.Workspace.current
  self.pending = 0
  if keepSignature then
   -- Keep parameter help during debounce, but never accept stale suggestions.
   self.context, self.items, self.selected=nil,{},1
   self:Draw()
  else
   self:Hide()
   if self.pendingSuggestions then self.pending=0 end
  end
 end
 if self.pending then
  self.pending = self.pending + elapsed
  if self.pending >= (#source > 20000 and 0.12 or 0.15) then self.pending = nil; self:Update(input, false, not self.pendingSuggestions) end
 end
end

function A:Accept(input)
 if self.context and input:GetText() ~= self.context.source then self:Refine(input,input:GetText(),input.editBox:GetCursorPosition()) end
 if self.input ~= input or not self.panel or not self.panel:IsShown() or not self.context or not self.items or not self.items[self.selected] then return false end
 local context, name = self.context, self.items[self.selected].name
 if input:GetText() ~= context.source or input.editBox:GetCursorPosition() ~= context.cursor or E:IsReadOnly(input) then self:Hide(); return false end
 local finish = context.cursor
 local suffix = context.source:sub(finish+1):match('^[%w_]*') or ''
 E:SetSource(input, context.source:sub(1, context.start) .. name .. context.source:sub(finish+#suffix+1), context.start+#name)
 self.lastSource, self.lastCursor, self.lastScript = input:GetText(), input.editBox:GetCursorPosition(), addon.Workspace.current
 self.keySource,self.keyCursor=nil,nil
 self:RestoreArrows()
 self:Update(input,false,true)
 return true
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
 if (key == 'UP' or key == 'DOWN') and self.input == input and self.context
  and input:GetText() ~= self.context.source then
  if not self:Refine(input,input:GetText(),input.editBox:GetCursorPosition()) then self:Hide();return end
 end
 if self.input == input and self.panel and self.panel:IsShown() and #self.items>0 and (key == 'UP' or key == 'DOWN')
  and not (_G.IsAltKeyDown and IsAltKeyDown()) and not (_G.IsShiftKeyDown and IsShiftKeyDown()) then
  origin = origin or 'native'
  -- Some EditBoxes dispatch both callbacks for one press; consume the second.
  if self.arrowKey == key and self.arrowOrigin and self.arrowOrigin ~= origin then
   self:RestoreCursor(input)
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
