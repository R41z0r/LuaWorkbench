local _, addon = ...
local A = { index = {}, text = {}, revision = 0 }
addon.APIHelp = A
local L = addon.L

function A:Enabled()
 local db = addon.Workspace and addon.Workspace.db
 return db and db.options.apiHelp ~= false
end

function A:Refresh()
 self.source, self.paths = nil, nil
 self.revision = self.revision + 1
 local editor, console = addon.Query.Editor, addon.Query.Console
 editor.colorRevision = (editor.colorRevision or 0) + 1
 if console.input then editor:Paint(console.input) end
 if addon.DebugUI then addon.DebugUI:HideTooltip(nil, 'api-settings') end
end

function A:Load(force)
 if (not force and not self:Enabled()) or self.ready or self.loading then return end
 -- Avoid first-load work during combat. A later editor opening retries failed loads.
 if _G.InCombatLockdown and _G.InCombatLockdown() then self.pending = true; self.pendingForce = force; return end
 self.loading = true
 local docs = _G.APIDocumentation
 if not docs or not docs.functions or #docs.functions == 0 then
  local loader = _G.C_AddOns and _G.C_AddOns.LoadAddOn or _G.LoadAddOn
  if loader then pcall(loader, 'Blizzard_APIDocumentationGenerated') end
  docs = _G.APIDocumentation
 end
 if docs and type(docs.functions) == 'table' and #docs.functions > 0 then
  for _, info in ipairs(docs.functions) do
   local namespace = info.System and info.System.Namespace
   local name = namespace and namespace ~= '' and (namespace .. '.' .. info.Name) or info.Name
   -- Widget methods without a global namespace cannot be resolved from an arbitrary object.
   local value = _G
   for part in name:gmatch('[%w_]+') do
    if type(value) ~= 'table' then value = nil; break end
    value = rawget(value, part)
   end
   if not (_G.issecretvalue and _G.issecretvalue(value)) and type(value) == 'function' then self.index[name] = info end
  end
  self.ready = true
 else
  addon.Query.Console:SetStatus(L.apiUnavailable, true)
 end
 self.loading, self.pending = nil, nil
 self:Refresh()
end

function A:SetEnabled(enabled)
 addon.Workspace.db.options.apiHelp = enabled
 if enabled then self:Load() end
 self:Refresh()
end

-- Resolve documented global names statically. Never execute hovered code.
function A:Paths(source, force)
 if (not force and not self:Enabled()) or not self.ready then return {} end
 if self.source == source and self.paths then return self.paths end
 local analysis = addon.Analysis:Get(source)
 local paths, blocked, chain, root, previous, declaration = {}, {}, nil, nil, nil, nil
 for _, token in ipairs(analysis.tokens) do
  if token.kind ~= 'space' and token.kind ~= 'newline' and token.kind ~= 'comment' then
   if token.kind == 'identifier' or token.kind == 'call' then
    if previous and previous.text == '.' and chain then
     chain = chain .. '.' .. token.text
    elseif previous and (previous.text == '.' or previous.text == ':') then
     chain, root = nil, nil
    else
     root = token
     declaration = previous and previous.text == 'function'
     chain = token.semanticKind == 'globalVariable' and not token.definition and not analysis.globals[token.text] and token.text or nil
    end
    if chain and root and not token.definition then
     local name = chain:gsub('^_G%.', '')
     if self.index[name] and not analysis.globals[name] then
      paths[token.start] = name
      if declaration then blocked[name] = true end
     end
    end
   elseif token.text ~= '.' then
    if token.text == '=' and chain then blocked[chain:gsub('^_G%.', '')] = true end
    chain, root = nil, nil
   end
   previous = token
  end
 end
 for position, name in pairs(paths) do if blocked[name] then paths[position] = nil end end
 self.source, self.paths = source, paths
 return paths
end

function A:AtCursor(source, cursor)
 self:Load(true)
 local paths = self:Paths(source, true)
 for _, token in ipairs(addon.Analysis:Get(source).tokens) do
  if cursor >= token.start - 1 and cursor <= token.finish and paths[token.start] then return paths[token.start] end
 end
end

-- Only static documentation metadata is formatted here, never runtime values.
function A:MetadataValue(value, key)
 if type(value) == 'string' then return value end
 if type(value) == 'boolean' or type(value) == 'number' then return tostring(value) end
 if type(value) ~= 'table' then return '?' end
 local values = {}
 for _, item in ipairs(value) do
  local label
  if key == 'SecretArgumentsAddAspect' or key == 'SecretReturnsForAspect' then
   for name, number in pairs(_G.Enum and _G.Enum.SecretAspect or {}) do
    if type(number) == 'number' and number == item then label = 'Enum.SecretAspect.' .. name; break end
   end
  end
  values[#values + 1] = label or (type(item) ~= 'table' and self:MetadataValue(item, key) or '?')
 end
 return '{ ' .. table.concat(values, ', ') .. ' }'
end

function A:RestrictionKeys(info)
 local keys = {}
 for key, value in pairs(info) do
  if type(key) == 'string' and type(value) ~= 'function' and
   (key:find('Secret', 1, true) or key:find('Restrict', 1, true) or key:find('Secure', 1, true) or key:find('Protected', 1, true)) then
   keys[#keys + 1] = key
  end
 end
 table.sort(keys)
 return keys
end

function A:FullDescription(name, rich)
 if not rich and self.text[name] then return self.text[name] end
 local info = self.index[name]
 if not info then return end
 local function color(text, kind)
  text = text:gsub('|', '||')
  if not rich then return text end
  return '|c' .. (kind == 'heading' and 'ffe6c07b' or addon.Query.Editor:Color(kind)) .. text .. '|r'
 end
 local args = {}
 for _, field in ipairs(info.Arguments or {}) do args[#args + 1] = color(field.Name, 'parameter') .. ((field.Nilable or field.Default ~= nil) and '?' or '') end
 local lines = { color(L.apiFunction, 'heading'), color(name, 'blizzardFunction') .. '(' .. table.concat(args, ', ') .. ')' }
 local function documentation(values)
  for _, detail in ipairs(values or {}) do lines[#lines + 1] = detail:gsub('|', '||') end
 end
 local function fields(title, values, arguments)
  if not values or #values == 0 then return end
  lines[#lines + 1] = ''; lines[#lines + 1] = color(title, 'heading')
  for _, field in ipairs(values) do
   local typeName = field.Type == 'bool' and 'boolean' or field.Type or '?'
   local line = color(field.Name, 'parameter') .. ': ' .. color(typeName, 'blizzardFunction') .. (field.Nilable and (' || ' .. color('nil', 'literal')) or '')
   local notes = {}
   if arguments and (field.Nilable or field.Default ~= nil) then notes[#notes + 1] = L.apiOptional end
   if field.Default ~= nil then
    local value = self:MetadataValue(field.Default)
    if type(field.Default) == 'string' then value = string.format('%q', field.Default) end
    notes[#notes + 1] = L.apiDefault .. ': ' .. color(value, 'literal')
   end
   if #notes > 0 then line = line .. ' (' .. table.concat(notes, ', ') .. ')' end
   lines[#lines + 1] = line
   for _, key in ipairs(self:RestrictionKeys(field)) do
    lines[#lines + 1] = '  ' .. color(key, 'parameter') .. ': ' .. color(self:MetadataValue(field[key], key), 'literal')
   end
   documentation(field.Documentation)
  end
 end
 if info.Documentation and #info.Documentation > 0 then lines[#lines + 1] = ''; documentation(info.Documentation) end
 fields(L.apiArguments, info.Arguments, true); fields(L.apiReturns, info.Returns, false)
 local restrictions = self:RestrictionKeys(info)
 if #restrictions > 0 then
  lines[#lines + 1] = ''; lines[#lines + 1] = color(L.apiRestrictions, 'heading')
  for _, key in ipairs(restrictions) do
   lines[#lines + 1] = color(key, 'parameter') .. ': ' .. color(self:MetadataValue(info[key], key), 'literal')
  end
 end
 local text = table.concat(lines, '\n')
 if not rich then self.text[name] = text end
 return text
end

function A:Description(name)
 local text = self:FullDescription(name)
 if not text then return end
 if #text > 2200 then
  local ending = 2200
  while text:byte(ending + 1) and text:byte(ending + 1) >= 128 and text:byte(ending + 1) < 192 do ending = ending - 1 end
  text = text:sub(1, ending) .. '\n…'
 end
 return text
end

A.events = CreateFrame('Frame')
A.events:RegisterEvent('PLAYER_REGEN_ENABLED')
A.events:SetScript('OnEvent', function()
 if A.pending and addon.Workspace.window and addon.Workspace.window:IsShown() then
  A:Load(A.pendingForce); A.pendingForce = nil
  if addon.KnowledgeBase and addon.KnowledgeBase.panel and addon.KnowledgeBase.panel:IsShown() then addon.KnowledgeBase:Search() end
 end
end)
