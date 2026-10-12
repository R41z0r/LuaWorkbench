local _, addon = ...
local Analysis = { cache = {}, order = {}, tokenCount = 0, byteCount = 0 }
addon.Analysis = Analysis
local Parser = {}
Parser.__index = Parser
-- Static lexical analysis only: no execution, metatables, computed exports or inferred calls.
-- Import recognition requires a bare, unshadowed requireHelper with a plain string literal.
local binary = { ['or']=1, ['and']=2, ['<']=3, ['>']=3, ['<=']=3, ['>=']=3, ['~=']=3, ['==']=3, ['..']=4, ['+']=5, ['-']=5, ['*']=6, ['/']=6, ['%']=6, ['^']=8 }
function Parser:peek() return self.items[self.index] or self.eof end
function Parser:take()
 self.steps = self.steps + 1
 if self.steps > 80000 then error('budget', 0) end
 local token = self:peek(); self.index = self.index + 1; return token
end
function Parser:accept(text) if self:peek().text == text then return self:take() end end
function Parser:expect(text)
 local token = self:accept(text)
 if not token then self.result.incomplete=true end
 return token
end
function Parser:scope()
 self.scopeID=(self.scopeID or 0)+1
 self.current = { parent = self.current, names = {}, id=self.scopeID, start0=self:peek().start-1 }
end
function Parser:leave()
 local previous = self.items[self.index - 1]
 self.current.finish0 = previous and previous.text == 'end' and previous.finish or self:peek().start - 1
 if self:peek().kind == 'eof' and not (previous and previous.text == 'end') then self.current.finish0 = self.eof.start end
 self.current = self.current.parent
end
function Parser:lookup(name)
 local scope = self.current
 while scope do if scope.names[name] then return scope.names[name] end; scope = scope.parent end
end
function Parser:declare(token, kind, value)
 local definition = { name = token.text, position0 = token.start - 1, kind = kind or 'localVariable', value = value, scope=self.current, visible0=(self.items[self.index-1] or token).finish, scopeID=self.current.id, functionDepth=self.functionDepth or 0 }
 definition.apiAliases = {{position0=definition.visible0, namespace=value and value.apiNamespace or false}}
 self.current.names[token.text] = definition
 token.definition, token.semanticKind = definition, definition.kind
 self.result.definitions[#self.result.definitions + 1] = definition
 return definition
end
function Parser:reference(token)
 token.definition = self:lookup(token.text)
 token.semanticKind = token.definition and token.definition.kind or 'globalVariable'
 return token.definition and token.definition.value or nil
end
local function identifier(token) return token.kind == 'identifier' or token.kind == 'call' end
local function literal(token)
 if token.kind ~= 'string' or token.closed ~= true then return end
 local quote = token.text:sub(1, 1)
 if (quote == '"' or quote == "'") and not token.text:find('\\', 1, true) then return token.text:sub(2, -2) end
end
function Parser:body(method)
 self.functionDepth=(self.functionDepth or 0)+1
 self:scope()
 self:expect('(')
 if method then
  -- An implicit parameter has scope visibility but no navigable source declaration.
  local definition = {name='self', kind='parameter', synthetic=true, scope=self.current,
   visible0=self.current.start0, scopeID=self.current.id, functionDepth=self.functionDepth}
  self.current.names.self = definition
  self.result.definitions[#self.result.definitions+1] = definition
 end
 while self:peek().text ~= ')' and self:peek().kind ~= 'eof' do
  local token = self:take()
  if identifier(token) then self:declare(token, 'parameter') end
  if not self:accept(',') then break end
 end
 self:expect(')'); self:chunk({ ['end']=true }); self:expect('end'); self:leave()
 self.functionDepth=self.functionDepth-1
end
function Parser:expression(minimum)
 self.depth = self.depth + 1
 if self.depth > 80 then error('depth', 0) end
 local token = self:take()
 local value
 local bareHelper = token.text == 'requireHelper' and not self:lookup(token.text) and not self.result.globals.requireHelper
 if identifier(token) then
  value = self:reference(token)
  if not token.definition and not self.result.globals[token.text] and token.text:match('^C_[%w_]+$') then
   value = {apiNamespace=token.text}
  end
 elseif token.text == 'function' then value = { functionToken=token }; self:body()
 elseif token.text == '{' then
  value = { members={} }
  while self:peek().text ~= '}' and self:peek().kind ~= 'eof' do
   local key = self:peek()
   if identifier(key) and self.items[self.index + 1] and self.items[self.index + 1].text == '=' then
    self:take(); self:take()
    local field = self:expression(0)
    key.semanticKind = field and field.functionToken and 'functionName' or nil
    value.members[key.text] = { name=key.text, position0=key.start-1, kind=key.semanticKind or 'identifier' }
   elseif self:accept('[') then self:expression(0); self:expect(']'); self:accept('='); self:expression(0)
   else self:expression(0) end
   if not self:accept(',') and not self:accept(';') then break end
  end
  self:expect('}')
 elseif token.text == '(' then value = self:expression(0); self:expect(')')
 elseif token.text == '-' or token.text == '#' or token.text == 'not' then self:expression(7)
 elseif token.kind ~= 'number' and token.kind ~= 'string' and token.kind ~= 'literal' and token.text ~= '...' then self.result.incomplete=true
 end
 while true do
  local text = self:peek().text
  if text == '.' or text == ':' then
   bareHelper = false
   local method = self:take().text == ':'
   local member = self:take()
   if value and value.module then
    member.import = { module=value.module, member=member.text }; self.result.imports[member.start-1] = member.import
    if token.definition then
     token.definition.importReferences=token.definition.importReferences or {}
     table.insert(token.definition.importReferences, {token=member, captured=(self.functionDepth or 0)>token.definition.functionDepth})
    end
   end
   if value and value.members then member.definition = value.members[member.text] end
   local nextToken = self:peek()
   local called = method or nextToken.text == '(' or nextToken.text == '{' or nextToken.kind == 'string'
   member.semanticKind = member.definition and member.definition.kind == 'functionName' and 'functionName'
    or (called and 'call' or (member.definition and member.definition.kind or 'identifier'))
   value = nil
  elseif text == '[' then bareHelper = false; self:take(); self:expression(0); self:expect(']'); value = nil
  elseif text == '(' or text == '{' or self:peek().kind == 'string' then
   local module
   if text == '(' then
    self:take(); module = literal(self:peek())
    if self:peek().text ~= ')' then self:expressions() end
    self:expect(')')
   else module = literal(self:peek()); self:expression(9) end
   value = bareHelper and module and { module=module } or nil
   bareHelper = false
  else break end
 end
 while binary[self:peek().text] and binary[self:peek().text] >= (minimum or 0) do
  local operation = self:take().text
  self:expression(binary[operation] + ((operation == '^' or operation == '..') and 0 or 1)); value=nil
 end
 self.depth = self.depth - 1
 return value
end
function Parser:expressions()
 local values = { self:expression(0) or false }
 while self:accept(',') do values[#values + 1] = self:expression(0) or false end
 return values
end
function Parser:statement()
 local text = self:peek().text
 if text == 'local' then
  self:take()
  if self:accept('function') then
   local name = self:take(); self:declare(name, 'functionName'); self:body()
  else
   local names = { self:take() }
   while self:accept(',') do names[#names+1] = self:take() end
   local values = self:accept('=') and self:expressions() or {}
   for i, name in ipairs(names) do
    if identifier(name) then self:declare(name, values[i] and values[i].functionToken and 'functionName' or 'localVariable', values[i]) end
   end
  end
 elseif text == 'function' then
  self:take(); local name = self:take(); local value = self:reference(name); local member, method, pathDepth
  pathDepth = 0
  while self:peek().text == '.' or self:peek().text == ':' do
   method = self:take().text == ':'; member = self:take(); pathDepth = pathDepth + 1
   if value and value.members and self.current.parent then value.dynamic=true end
   if value and value.members and pathDepth == 1 and self:peek().text ~= '.' and self:peek().text ~= ':' and not self.current.parent then
    local definition = { name=member.text, position0=member.start-1, kind='functionName' }
    value.members[member.text] = definition; member.definition=definition
   end
   member.semanticKind='functionName'
  end
  if not member then
   name.semanticKind='functionName'
   if name.definition and name.definition.kind ~= 'parameter' then name.definition.kind='functionName' end
   if not name.definition then self.result.globals[name.text] = self.result.globals[name.text] or {}; table.insert(self.result.globals[name.text], { name=name.text, position0=name.start-1, kind='functionName' }) end
  end
  self:body(method)
 elseif text == 'if' then
  self:take(); self:expression(0); self:expect('then'); self:scope(); self:chunk({ ['elseif']=true, ['else']=true, ['end']=true }); self:leave()
  while self:accept('elseif') do self:expression(0); self:expect('then'); self:scope(); self:chunk({ ['elseif']=true, ['else']=true, ['end']=true }); self:leave() end
  if self:accept('else') then self:scope(); self:chunk({ ['end']=true }); self:leave() end
  self:expect('end')
 elseif text == 'for' then
  self:take(); local names={self:take()}
  while self:accept(',') do names[#names+1]=self:take() end
  if self:accept('=') or self:accept('in') then self:expressions() end
  self:expect('do'); self:scope()
  for _, name in ipairs(names) do if identifier(name) then self:declare(name) end end
  self:chunk({ ['end']=true }); self:expect('end'); self:leave()
 elseif text == 'while' then
  self:take(); self:expression(0); self:expect('do'); self:scope(); self:chunk({ ['end']=true }); self:expect('end'); self:leave()
 elseif text == 'repeat' then
  self:take(); self:scope(); self:chunk({ ['until']=true }); if self:expect('until') then self:expression(0) end; self:leave()
 elseif text == 'do' then
  self:take(); self:scope(); self:chunk({ ['end']=true }); self:expect('end'); self:leave()
 elseif text == 'return' then
  self:take()
  if self:peek().kind ~= 'eof' and not ({ ['end']=true, ['else']=true, ['elseif']=true, ['until']=true, [';']=true })[self:peek().text] then
   local values=self:expressions()
   if not self.current.parent and values[1] and values[1].members and not values[1].dynamic then self.result.exports=values[1].members end
  end
 elseif text == 'break' or text == ';' then self:take()
 else
  local targets = {}
  repeat
   local start = self.index
   local first, nextToken, member = self:peek(), self.items[self.index+1], self.items[self.index+2]
   self:expression(0)
   targets[#targets+1] = { token=first, direct=self.index == start+1,
    member=self.index == start+3 and nextToken and nextToken.text == '.' and member,
    computed=nextToken and nextToken.text == '[' }
  until not self:accept(',')
  if self:accept('=') then
   local values=self:expressions()
   for i, target in ipairs(targets) do
    local first, member, value=target.token, target.member, values[i]
    if member and self.current.parent and first.definition and first.definition.value then first.definition.value.dynamic=true
    elseif target.computed and first.definition and first.definition.value then first.definition.value.dynamic=true
    elseif member and not self.current.parent and first.definition and first.definition.value and first.definition.value.members then
     local definition = {name=member.text, position0=member.start-1, kind=value and value.functionToken and 'functionName' or 'identifier'}
     first.definition.value.members[member.text]=definition; member.definition=definition; member.semanticKind=definition.kind
    elseif target.direct and identifier(first) and first.definition then
     local definition=first.definition
     for _, reference in ipairs(definition.importReferences or {}) do
      if reference.captured then reference.token.import=nil; self.result.imports[reference.token.start-1]=nil end
     end
     definition.value=definition.scopeID == self.current.id and value or nil
     definition.apiAliases = definition.apiAliases or {}
     definition.apiAliases[#definition.apiAliases+1] = {position0=(self.items[self.index-1] or first).finish,
      namespace=definition.value and definition.value.apiNamespace or false}
     if value and value.functionToken and first.definition.kind ~= 'parameter' then first.definition.kind='functionName' end
    elseif target.direct and identifier(first) then
     self.result.globals[first.text]=self.result.globals[first.text] or {}
     table.insert(self.result.globals[first.text], {name=first.text, position0=first.start-1, kind='globalVariable'})
    end
   end
  end
 end
end
function Parser:chunk(stops)
 self.blocks = (self.blocks or 0) + 1
 if self.blocks > 80 then error('depth', 0) end
 while self:peek().kind ~= 'eof' and not stops[self:peek().text] do
  local before=self.index; self:statement(); if self.index == before then self:take() end
 end
 self.blocks = self.blocks - 1
end
function Analysis:Get(source)
 if self.cache[source] then return self.cache[source] end
 local result={tokens={}, definitions={}, exports={}, imports={}, globals={}}
 if #source > 200000 then result.limited=true; result.tokens={{text=source,kind='plain',start=1,finish=#source}}
 else
  result.tokens=addon.Query.Editor:Tokenize(source, 50000)
  local items={}
  for _, token in ipairs(result.tokens) do
   if token.closed == false then result.incomplete=true end
   if token.truncated then result.limited=true
   elseif token.kind ~= 'space' and token.kind ~= 'newline' and token.kind ~= 'comment' then items[#items+1]=token end
  end
  local parser=setmetatable({items=items, index=1, steps=0, depth=0, result=result, eof={kind='eof',text='',start=#source+1}}, Parser)
  parser:scope()
  local ok=pcall(parser.chunk, parser, {})
  if not ok then result.limited=true end
 end
 if result.limited or result.incomplete then result.exports={}; result.imports={} end
 if result.globals.requireHelper then
  result.imports={}
  for _, token in ipairs(result.tokens) do token.import=nil end
 end
 if #source > 200000 then return result end
 self.cache[source]=result; self.order[#self.order+1]=source
 self.tokenCount = self.tokenCount + #result.tokens
 self.byteCount = self.byteCount + #source
 while #self.order > 1 and (#self.order > 6 or self.tokenCount > 60000 or self.byteCount > 600000) do
  local oldest=table.remove(self.order,1)
  self.tokenCount=self.tokenCount-#self.cache[oldest].tokens; self.byteCount=self.byteCount-#oldest; self.cache[oldest]=nil
 end
 return result
end
function Analysis:Resolve(source, cursor0)
 local result=self:Get(source)
 if result.limited or result.incomplete then return {} end
 for _, token in ipairs(result.tokens) do
  if identifier(token) and cursor0 >= token.start-1 and cursor0 <= token.finish then
   if token.import then return {{name=token.text, kind='helper', module=token.import.module, member=token.import.member}} end
   if token.definition and token.definition.position0 then return {token.definition} end
   if token.semanticKind == 'globalVariable' or token.semanticKind == 'functionName' then return result.globals[token.text] or {} end
   return {}
  end
 end
 return {}
end
