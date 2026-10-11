local _, addon = ...
local D, P = {}, {}
addon.DebugCompiler = D
P.__index = P
local binary = { ['or']=1, ['and']=2, ['<']=3, ['>']=3, ['<=']=3, ['>=']=3, ['~=']=3, ['==']=3, ['..']=4, ['+']=5, ['-']=5, ['*']=6, ['/']=6, ['%']=6, ['^']=8 }
local function identifier(token) return token.kind == 'identifier' or token.kind == 'call' end
function P:peek() return self.items[self.index] or self.eof end
function P:take()
 self.steps = self.steps + 1
 if self.steps > 80000 then error('Debugger compiler: source exceeds parser budget', 0) end
 local token = self:peek(); self.index = self.index + 1; self.last = token; return token
end
function P:accept(text) if self:peek().text == text then return self:take() end end
function P:expect(text)
 local token = self:accept(text)
 if not token then error('Debugger compiler: expected ' .. text .. ' at line ' .. self:peek().line, 0) end
 return token
end
function P:name()
 local token = self:take()
 if not identifier(token) then error('Debugger compiler: expected a name at line ' .. token.line, 0) end
 return token.text
end
function P:edit(start, finish, text)
 self.edits[#self.edits + 1] = { start=start, finish=finish, text=text, order=#self.edits + 1 }
 self.generated = self.generated + #text
 if self.generated > 2000000 then error('Debugger compiler: generated code exceeds size budget', 0) end
end
function P:insert(position, text) self:edit(position, position - 1, text) end
function P:scope() self.scopes[#self.scopes + 1] = {} end
function P:leave() self.scopes[#self.scopes] = nil end
function P:declare(name) self.scopes[#self.scopes][name] = true end
function P:bindings()
 local names = {}
 for _, scope in ipairs(self.scopes) do for name in pairs(scope) do names[name] = true end end
 local ordered = {}; for name in pairs(names) do ordered[#ordered + 1] = name end; table.sort(ordered)
 local parts, value = {}, self.helper .. '_value'
 for _, name in ipairs(ordered) do
  parts[#parts + 1] = '[' .. string.format('%q', name) .. ']={get=function() return ' .. name
   .. ' end,set=function(' .. value .. ') ' .. name .. '=' .. value .. ' end}'
 end
 return '{' .. table.concat(parts, ',') .. '}'
end
function P:checkpoint(token)
 self.lines[token.line] = true
 self:insert(token.start, ' ' .. self.helper .. '("step",' .. token.line .. ',' .. self:bindings() .. ',' .. self.frame .. '); ')
end
function P:functionBody(method, line)
 self:expect('('); self:scope()
 if method then self:declare('self') end
 if self:peek().text ~= ')' then
  repeat
   if self:accept('...') then break end
   self:declare(self:name())
  until not self:accept(',')
 end
 local closing = self:expect(')')
 local previous = self.frame
 self.serial = self.serial + 1; self.frame = self.helper .. '_frame' .. self.serial
 self:insert(closing.finish + 1, ' local ' .. self.frame .. '=' .. self.helper .. '("enter",' .. line .. '); ')
 self:chunk({ ['end']=true }, true)
 local ending = self:expect('end')
 self:insert(ending.start, ' ' .. self.helper .. '("leave",' .. self.frame .. '); ')
 self.frame = previous; self:leave()
end
function P:arguments()
 if self:accept('(') then
  if self:peek().text ~= ')' then self:expressions() end
  self:expect(')')
 elseif self:peek().text == '{' or self:peek().kind == 'string' then self:expression(9)
 else error('Debugger compiler: expected call arguments at line ' .. self:peek().line, 0) end
end
function P:expression(minimum)
 self.depth = self.depth + 1
 if self.depth > 70 then error('Debugger compiler: expression nesting limit', 0) end
 local token = self:take()
 local prefix, called = false, false
 if identifier(token) then prefix = true
 elseif token.text == '(' then self:expression(0); self:expect(')'); prefix = true
 elseif token.text == 'function' then self:functionBody(false, token.line)
 elseif token.text == '{' then
  while self:peek().text ~= '}' do
   if self:accept('[') then self:expression(0); self:expect(']'); self:expect('='); self:expression(0)
   elseif identifier(self:peek()) and self.items[self.index + 1] and self.items[self.index + 1].text == '=' then self:take(); self:take(); self:expression(0)
   else self:expression(0) end
   if not self:accept(',') and not self:accept(';') then break end
  end
  self:expect('}')
 elseif token.text == 'not' or token.text == '#' or token.text == '-' then self:expression(7)
 elseif token.kind ~= 'string' and token.kind ~= 'number' and token.kind ~= 'literal' and token.text ~= '...' then
  error('Debugger compiler: unsupported expression at line ' .. token.line, 0)
 end
 while prefix do
  if self:accept('.') then self:name(); called = false
  elseif self:accept('[') then self:expression(0); self:expect(']'); called = false
  elseif self:peek().text == ':' then
   local colon = self:take()
   local method = self:name()
   if method == 'SetScript' or method == 'HookScript' then
    -- A factory captures the receiver and its method before evaluating arguments,
    -- matching Lua's colon-call order without evaluating the receiver twice.
    self:insert(token.start, self.helper .. '("method",')
    self:edit(colon.start, colon.finish, ',')
    self:edit(self.last.start, self.last.finish, string.format('%q', method) .. ')')
   end
   self:arguments(); called = true
  elseif self:peek().text == '(' or self:peek().text == '{' or self:peek().kind == 'string' then self:arguments(); called = true
  else break end
 end
 while true do
  local op = self:peek().text
  local precedence = binary[op]
  if not precedence or precedence <= minimum then break end
  self:take(); self:expression((op == '^' or op == '..') and precedence - 1 or precedence)
 end
 self.depth = self.depth - 1
 return called
end
function P:expressions()
 self:expression(0)
 while self:accept(',') do self:expression(0) end
end
function P:statement()
 local token = self:peek()
 if self:accept(';') then return end
 if token.text ~= 'while' then self:checkpoint(token) end
 if self:accept('local') then
  if self:accept('function') then self:declare(self:name()); self:functionBody(false, token.line)
  else
   local names = { self:name() }
   while self:accept(',') do names[#names + 1] = self:name() end
   if self:accept('=') then self:expressions() end
   for _, name in ipairs(names) do self:declare(name) end
  end
 elseif self:accept('function') then
  self:name(); while self:accept('.') do self:name() end
  local method = self:accept(':'); if method then self:name() end
  self:functionBody(method ~= nil, token.line)
 elseif self:accept('if') then
  self:expression(0); self:expect('then'); self:scope(); self:chunk({ ['elseif']=true, ['else']=true, ['end']=true }); self:leave()
  while self:accept('elseif') do self:expression(0); self:expect('then'); self:scope(); self:chunk({ ['elseif']=true, ['else']=true, ['end']=true }); self:leave() end
  if self:accept('else') then self:scope(); self:chunk({ ['end']=true }); self:leave() end
  self:expect('end')
 elseif self:accept('while') then
  self.lines[token.line] = true
  self:edit(token.start, token.finish, 'while true do ' .. self.helper .. '("step",' .. token.line .. ',' .. self:bindings() .. ',' .. self.frame .. '); if (')
  self:expression(0)
  local opening = self:expect('do')
  self:edit(opening.start, opening.finish, ') then else break end; ')
  self:scope(); self:chunk({ ['end']=true }); self:expect('end'); self:leave()
 elseif self:accept('repeat') then
  self:scope(); self:chunk({ ['until']=true }); self:checkpoint(self:peek()); self:expect('until'); self:expression(0); self:leave()
 elseif self:accept('for') then
  local names = { self:name() }
  if self:accept('=') then self:expression(0); self:expect(','); self:expression(0); if self:accept(',') then self:expression(0) end
  else
   while self:accept(',') do names[#names + 1] = self:name() end
   self:expect('in'); self:expressions()
  end
  local opening = self:expect('do'); self:scope(); for _, name in ipairs(names) do self:declare(name) end
  self:insert(opening.finish + 1, ' ' .. self.helper .. '("step",' .. token.line .. ',' .. self:bindings() .. ',' .. self.frame .. '); ')
  self:chunk({ ['end']=true }); self:expect('end'); self:leave()
 elseif self:accept('do') then self:scope(); self:chunk({ ['end']=true }); self:expect('end'); self:leave()
 elseif self:accept('return') then
  local nextToken = self:peek()
  local empty = nextToken.kind == 'eof' or nextToken.text == ';' or nextToken.text == 'end' or nextToken.text == 'else' or nextToken.text == 'elseif' or nextToken.text == 'until'
  if not empty then self:expressions() end
  self:edit(token.start, token.finish, 'do return ' .. self.helper .. '("return",' .. self.frame .. (empty and '' or ','))
  self:insert(self.last.finish + 1, ') end')
 elseif self:accept('break') then self:edit(token.start, token.finish, 'do break end'); return
 else
  local called = self:expression(9)
  if self:accept(',') then repeat self:expression(9) until not self:accept(','); self:expect('='); self:expressions()
  elseif self:accept('=') then self:expressions()
  elseif not called then error('Debugger compiler: unsupported statement at line ' .. token.line, 0) end
 end
end
function P:chunk(stops, nonempty)
 self.blockDepth = self.blockDepth + 1
 if self.blockDepth > 60 then error('Debugger compiler: block nesting limit', 0) end
 if nonempty and stops[self:peek().text] then self:checkpoint(self:peek()) end
 while self:peek().kind ~= 'eof' and not stops[self:peek().text] do self:statement() end
 self.blockDepth = self.blockDepth - 1
end

function D:Compile(source)
 if type(source) ~= 'string' or #source > 150000 then return nil, 'Debugger compiler: source size limit' end
 local original, failure = _G.loadstring(source, '=LuaWorkbench source')
 if not original then return nil, failure end
 local tokens = addon.Query.Editor:Tokenize(source, 30000)
 local items, line = {}, 1
 for _, token in ipairs(tokens) do
  if token.truncated then return nil, 'Debugger compiler: token budget' end
  token.line = line
  local _, count = token.text:gsub('\n', ''); line = line + count
  if token.kind ~= 'space' and token.kind ~= 'newline' and token.kind ~= 'comment' then items[#items + 1] = token end
 end
 local serial, helper = 1, '__LuaWorkbenchDebug1'
 while source:find(helper, 1, true) do serial = serial + 1; helper = '__LuaWorkbenchDebug' .. serial end
 local parser = setmetatable({ items=items, index=1, steps=0, depth=0, blockDepth=0, scopes={}, edits={}, generated=0,
  eof={kind='eof',text='',start=#source+1,finish=#source,line=line}, helper=helper, serial=0, frame=helper .. '_frame0', lines={} }, P)
 local ok, problem = pcall(function()
  parser:scope()
  parser:insert(1, 'local ' .. parser.frame .. '=' .. helper .. '("enter",1); ')
  parser:chunk({})
  if parser:peek().kind ~= 'eof' then error('Debugger compiler: incomplete parse', 0) end
  parser:insert(#source + 1, '\n' .. helper .. '("leave",' .. parser.frame .. ');')
 end)
 if not ok then return nil, problem end
 table.sort(parser.edits, function(a,b) return a.start == b.start and a.order < b.order or a.start < b.start end)
 local parts, position = {}, 1
 for _, edit in ipairs(parser.edits) do
  if edit.start < position then return nil, 'Debugger compiler: overlapping edits' end
  parts[#parts + 1] = source:sub(position, edit.start - 1); parts[#parts + 1] = edit.text
  position = math.max(edit.finish + 1, edit.start)
 end
 parts[#parts + 1] = source:sub(position)
 local instrumented = table.concat(parts)
 local compiled, compilerError = _G.loadstring(instrumented, '=LuaWorkbench debugger')
 if not compiled then return nil, compilerError end
 local lineMap = {}; for index = 1, line do lineMap[index] = index end; lineMap[line + 1] = line
 return instrumented, { helperName=helper, lines=parser.lines, lineMap=lineMap, tailCallsPreserved=false }
end
