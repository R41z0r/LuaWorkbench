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
  self:Catalog(docs)
  self.ready = true
 else
  addon.Query.Console:SetStatus(L.apiUnavailable, true)
 end
 self.loading, self.pending = nil, nil
 self:Refresh()
end

-- Keep documentation separate from globals eligible for editor highlighting.
function A:Catalog(docs)
 self.catalog, self.aliases, self.byInfo = {}, {}, {}
 local function alias(key, name)
  if not key or key == '' then return end
  if self.aliases[key] == nil then self.aliases[key] = name
  elseif self.aliases[key] ~= name then self.aliases[key] = false end
 end
 local function add(info, kind, name)
  if self.byInfo[info] then return end
  if self.catalog[name] then name = (info.System and info.System.Name or kind) .. '.' .. name end
  self.catalog[name] = { info = info, kind = kind, name = name }
  self.byInfo[info] = name
  alias(name, name); alias(info.Name, name)
  return name
 end
 for _, info in ipairs(docs.systems or {}) do
  local name = add(info, 'apiSystems', info.Namespace or info.Name)
  if info.Type == 'ScriptObject' then alias(info.Name:gsub('API$', ''), name) end
 end
 for _, info in ipairs(docs.tables or {}) do
  local enum = info.Type == 'Enumeration'
  add(info, enum and 'apiEnums' or (info.Type == 'Structure' and 'apiStructures' or (info.Type == 'CallbackType' and 'apiCallbacks' or (info.Type == 'Constants' and 'apiConstants' or 'apiOther'))), enum and ('Enum.' .. info.Name) or info.Name)
 end
 for _, info in ipairs(docs.functions or {}) do
  local system = info.System
  local namespace = system and system.Namespace
  local object = system and system.Type ~= 'System' and system.Type ~= nil
  local name = namespace and namespace ~= '' and (namespace .. '.' .. info.Name)
   or object and (system.Name:gsub('API$', '') .. ':' .. info.Name) or info.Name
  add(info, 'apiFunctions', name)
 end
 for _, info in ipairs(docs.events or {}) do add(info, 'apiEvents', info.LiteralName or info.Name) end
 for _, info in ipairs(docs.callbacks or {}) do add(info, 'apiCallbacks', info.Name) end
 self.text = {}
end

function A:Reference(name, context)
 if self.catalog and self.catalog[name] then return name end
 local match = self.aliases and self.aliases[name]
 if match then return match end
 -- Resolve duplicate type names within their documented system only.
 local owner = context and (context.System or context)
 if owner then
  for _, info in ipairs(owner.Tables or {}) do
   if info.Name == name then return self.byInfo[info] end
  end
 end
end

function A:Link(name, label)
 return '|Hlwapi:' .. name .. '|h' .. label .. '|h'
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

function A:FullDescription(name, rich, links)
 if not rich and self.text[name] then return self.text[name] end
 local entry = self.catalog and self.catalog[name]
 local info = entry and entry.info or self.index[name]
 if not info then return end
 local function color(text, kind)
  text = text:gsub('|', '||')
  if not rich then return text end
  return '|c' .. (kind == 'heading' and 'ffe6c07b' or addon.Query.Editor:Color(kind)) .. text .. '|r'
 end
 local function reference(label, target)
  local text = color(label, 'blizzardFunction')
  local destination = target or self:Reference(label, info)
  return rich and links and destination and self:Link(destination, text) or text
 end
 local args = {}
 for _, field in ipairs(info.Arguments or {}) do args[#args + 1] = color(field.Name, 'parameter') .. ((field.Nilable or field.Default ~= nil) and '?' or '') end
 local callable = not entry or entry.kind == 'apiFunctions' or entry.kind == 'apiCallbacks'
 local lines = { color(entry and entry.kind == 'apiCallbacks' and L.apiCallbacks or (callable and L.apiFunction or L[entry.kind]), 'heading'), color(name, 'blizzardFunction') .. (callable and ('(' .. table.concat(args, ', ') .. ')') or '') }
 if info.System and self.byInfo and self.byInfo[info.System] then
  lines[#lines + 1] = reference(info.System.Namespace or info.System.Name, self.byInfo[info.System])
 end
 local function documentation(values)
  for _, detail in ipairs(values or {}) do lines[#lines + 1] = detail:gsub('|', '||') end
 end
 local function fields(title, values, arguments)
  if not values or #values == 0 then return end
  lines[#lines + 1] = ''; lines[#lines + 1] = color(title, 'heading')
  for _, field in ipairs(values) do
   local typeName = field.Type == 'bool' and 'boolean' or field.Type or '?'
   local line = color(field.Name, 'parameter') .. ': ' .. reference(typeName) .. (field.InnerType and ('<' .. reference(field.InnerType) .. '>') or '') .. (field.Nilable and (' || ' .. color('nil', 'literal')) or '')
   if field.EnumValue ~= nil then line = line .. ' = ' .. color(tostring(field.EnumValue), 'number') end
   if field.Value ~= nil then line = line .. ' = ' .. color(self:MetadataValue(field.Value), 'literal') end
   if field.Mixin then line = line .. ' (' .. reference(field.Mixin) .. ')' end
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
 fields(L.apiFields, info.Fields, false); fields(L.apiPayload, info.Payload, false)
 for _, group in ipairs({ {'Functions', 'apiFunctions'}, {'Tables', 'apiTypes'}, {'Events', 'apiEvents'}, {'Callbacks', 'apiCallbacks'} }) do
  if info[group[1]] and #info[group[1]] > 0 then
   lines[#lines + 1] = ''; lines[#lines + 1] = color(L[group[2]], 'heading')
   for _, child in ipairs(info[group[1]]) do
    local target = self.byInfo and self.byInfo[child]
    lines[#lines + 1] = reference(child.LiteralName or child.Name, target)
   end
  end
 end
 -- Preserve additional static metadata without traversing mixin methods or parent cycles.
 local metadata = {}
 local excluded = {Name=true,Type=true,Namespace=true,LiteralName=true,loweredName=true,loweredNamespaceName=true}
 for key, value in pairs(info) do
  if not excluded[key] and (type(value) == 'string' or type(value) == 'number' or type(value) == 'boolean')
   and not (key:find('Secret') or key:find('Restrict') or key:find('Secure') or key:find('Protected')) then metadata[#metadata + 1] = key end
 end
 table.sort(metadata)
 for _, key in ipairs(metadata) do lines[#lines + 1] = color(key, 'parameter') .. ': ' .. color(self:MetadataValue(info[key], key), 'literal') end
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

-- Search only needs static words, not a fully formatted article for every entry.
-- Do not traverse documentation parent links or injected mixin methods.
function A:SearchText(name)
 local entry = self.catalog and self.catalog[name]
 local info = entry and entry.info or self.index[name]
 if not info then return '' end
 local words = { name, entry and L[entry.kind] or L.apiFunction }
 local function collect(value)
  if value.Name then words[#words + 1] = value.Name .. ':' end
  if value.Type then words[#words + 1] = value.Type == 'bool' and 'boolean' or value.Type end
  for _, line in ipairs(value.Documentation or {}) do words[#words + 1] = line end
  for key, item in pairs(value) do
   if key ~= 'Name' and key ~= 'Type' and key ~= 'Nilable' and key ~= 'loweredName' and key ~= 'loweredNamespaceName'
    and (type(item) == 'string' or type(item) == 'number' or type(item) == 'boolean') then
    words[#words + 1] = key .. ': ' .. tostring(item)
   elseif type(item) == 'table' and (key:find('Secret') or key:find('Restrict')) then
    words[#words + 1] = key .. ': ' .. self:MetadataValue(item, key)
   end
  end
  if value.Nilable then words[#words + 1] = 'nil' end
  if value.Default ~= nil then words[#words + 1] = L.apiDefault end
 end
 collect(info)
 if info.System then words[#words + 1] = info.System.Namespace or info.System.Name or '' end
 for _, group in ipairs({ {'Arguments', L.apiArguments}, {'Returns', L.apiReturns}, {'Fields', L.apiFields}, {'Payload', L.apiPayload} }) do
  local fields = info[group[1]]
  if fields and #fields > 0 then
   words[#words + 1] = group[2]
   for _, field in ipairs(fields) do
    collect(field)
    if group[1] == 'Arguments' and (field.Nilable or field.Default ~= nil) then words[#words + 1] = L.apiOptional end
   end
  end
 end
 for _, group in ipairs({ 'Functions', 'Tables', 'Events', 'Callbacks' }) do
  for _, child in ipairs(info[group] or {}) do words[#words + 1] = child.LiteralName or child.Name end
 end
 return table.concat(words, ' '):lower()
end

function A:Preview(name)
 local text = self:FullDescription(name, true)
 if not text then return end
 local lines = {}
 for line in (text .. '\n'):gmatch('(.-)\n') do
  if #lines == 18 then lines[#lines + 1] = '…'; break end
  lines[#lines + 1] = line
 end
 return table.concat(lines, '\n')
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
