local _, addon = ...
local W, UI, L = addon.Workspace, addon.UI, addon.L
local H = {}
addon.Helpers = H

function H:Options(id)
 W.db.helperModules = W.db.helperModules or {}
 W.db.helperModules[id] = W.db.helperModules[id] or { name = '' }
 return W.db.helperModules[id]
end

function H:Normalize(name)
 if type(name) ~= 'string' then return nil end
 local trimmed = name:match('^%s*(.-)%s*$')
 if #trimmed > 80 or not trimmed:match('^[%a_][%w_.%-]*$') then return nil end
 return trimmed, trimmed:lower()
end

function H:Validate(id, name, enabled)
 local normalized, key = self:Normalize(name)
 if not normalized then return nil, L.helperInvalidName end
 if enabled and not W.db.snippets[id] then return nil, L.saveBeforeAutoRun end
 for other, options in pairs(W.db.helperModules or {}) do
  local _, otherKey = self:Normalize(options.name)
  if other ~= id and options.enabled and otherKey == key then return nil, L.helperDuplicate .. ' ' .. normalized end
 end
 return normalized
end

function H:Set(id, name, enabled)
 local normalized, message = self:Validate(id, name, enabled)
 if not normalized then return false, message end
 local options = self:Options(id)
 options.name, options.enabled = normalized, enabled == true
 return true
end

function H:Resolve(name)
 local _, key = self:Normalize(name)
 if not key then return nil, L.helperInvalidName end
 local found
 for id, options in pairs(W.db.helperModules or {}) do
  local _, otherKey = self:Normalize(options.name)
  if options.enabled and key == otherKey and W.db.snippets[id] then
   if found then return nil, L.helperDuplicate .. ' ' .. name end
   found = { id = id, name = options.name, source = W.db.snippets[id].source, scriptName = W.db.snippets[id].name }
  end
 end
 if not found then return nil, L.helperMissing .. ' ' .. name end
 return found
end

function H:Entries()
 local entries = {}
 for id, options in pairs(W.db.helperModules or {}) do
  if options.enabled and W.db.snippets[id] then
   local module = self:Resolve(options.name)
   if module and module.id == id then entries[#entries + 1] = module end
  end
 end
 table.sort(entries, function(a, b) return a.name:lower() < b.name:lower() end)
 return entries
end

function H:ImportText(name, source, cursor)
 local alias = name:gsub('[^%w_]', '_')
 if not alias:match('^[%a_]') then alias = 'tools_' .. alias end
 local reserved = { ['and']=true, ['break']=true, ['do']=true, ['else']=true, ['elseif']=true, ['end']=true,
  ['false']=true, ['for']=true, ['function']=true, ['if']=true, ['in']=true, ['local']=true, ['nil']=true,
  ['not']=true, ['or']=true, ['repeat']=true, ['return']=true, ['then']=true, ['true']=true, ['until']=true,
  ['while']=true, requireHelper=true }
 local used = {}
 for word in source:gmatch('[%a_][%w_]*') do used[word] = true end
 local base, suffix = alias, 1
 while reserved[alias] or used[alias] do suffix = suffix + 1; alias = base .. suffix end
 local before, after = source:sub(1, cursor), source:sub(cursor + 1)
 return (before ~= '' and before:sub(-1) ~= '\n' and '\n' or '')
  .. 'local ' .. alias .. ' = requireHelper(' .. string.format('%q', name) .. ')'
  .. (after:sub(1, 1) ~= '\n' and '\n' or '')
end

function H:Loader(context)
 local cache, loading, chain, registry = {}, {}, {}, {}
 for id, options in pairs(W.db.helperModules or {}) do
  local _, key = self:Normalize(options.name)
  local saved = W.db.snippets[id]
  if options.enabled and key and saved then
   if registry[key] ~= nil then registry[key] = false
   else registry[key] = { id = id, name = options.name, source = saved.source } end
  end
 end
 local function requireHelper(name)
  local _, key = self:Normalize(name)
  if not key then error(L.helperInvalidName, 0) end
  local module = registry[key]
  if module == false then error(L.helperDuplicate .. ' ' .. name, 0) end
  if not module then error(L.helperMissing .. ' ' .. name, 0) end
  if cache[module.id] then return cache[module.id] end
  if loading[module.id] then error(L.helperCycle .. ' ' .. table.concat(chain, ' -> ') .. ' -> ' .. module.name, 0) end
  local chunk, compileError = _G.loadstring(W:NormalizeSource(module.source), '=LuaWorkbench helper [' .. module.name .. ']')
  if not chunk then error(L.helperLoadError .. ' ' .. module.name .. ': ' .. tostring(compileError), 0) end
  local environment = setmetatable({ addon = addon, editor = addon, requireHelper = requireHelper,
   print = context.print, dump = context.dump, DevTools_Dump = context.DevTools_Dump or function(value, startKey) addon.Query.Console:Dump(value, startKey) end, event = context.event,
  }, { __index = _G })
  _G.setfenv(chunk, environment)
  loading[module.id] = true; chain[#chain + 1] = module.name
  local ok, value = pcall(chunk)
  chain[#chain] = nil; loading[module.id] = nil
  if not ok then error(L.helperLoadError .. ' ' .. module.name .. ': ' .. addon.Query.Console:Format(value), 0) end
  if (_G.issecretvalue and _G.issecretvalue(value)) or type(value) ~= 'table' then error(L.helperMustReturnTable .. ' ' .. module.name, 0) end
  cache[module.id] = value
  return value
 end
 return requireHelper
end

function H:RefreshControlLayout()
 self:UpdateControls()
 W:RefreshTree()
 if addon.Automation.panel and addon.Automation.panel:IsShown() then addon.Automation:UpdateEventRows() end
end

function H:BuildControls(parent)
 self.heading = UI:Text(parent, L.helperModule, 13)
 self.enabled = UI:Check(parent, L.helperEnabled, function(button)
  local options = self:Options(W.current)
  local checked = button:GetChecked() == true
  if not checked then
   options.enabled, self.pendingID = false, nil
   self.name:ClearFocus(); self.error:SetText('')
  else
   local ok, message = self:Set(W.current, self.name:GetText(), true)
   self.pendingID = not ok and W.current or nil
   self.error:SetText(message or '')
   if not ok then self.name:SetFocus() end
  end
  self:RefreshControlLayout()
 end)
 self.nameLabel = UI:Text(parent, L.helperName, 11)
 local box = CreateFrame('EditBox', nil, parent); self.name = box
 box:SetAutoFocus(false); box:SetFontObject(GameFontHighlightSmall); box:SetTextInsets(7, 7, 0, 0); box:SetMaxLetters(80); box:SetHeight(26)
 UI:Background(box, UI.colors.hover); UI:Tooltip(box, L.helperNameHelp)
 box:SetScript('OnEnterPressed', function()
  local desired = self.pendingID == W.current or self:Options(W.current).enabled == true
  local ok, message = self:Set(W.current, box:GetText(), desired)
  self.error:SetText(message or '')
  if ok then
   self.pendingID = nil; box:SetText(self:Options(W.current).name); box:ClearFocus()
  end
  self:RefreshControlLayout()
 end)
 box:SetScript('OnEscapePressed', function()
  self.pendingID = nil; box:ClearFocus(); self.error:SetText(''); self:RefreshControlLayout()
 end)
 self.error = UI:Text(parent, '', 11); self.error:SetTextColor(1, 0.4, 0.4); self.error:SetWordWrap(true)
 self.description = UI:Text(parent, L.helperInlineHelp, 11); self.description:SetWordWrap(true)
 self.example = UI:Text(parent, '', 12); self.example:SetWordWrap(true)
 self.usage = UI:Text(parent, L.helperUsageExample, 11)
 self.consumer = UI:Text(parent, '', 12); self.consumer:SetWordWrap(true)
end

function H:LayoutControls(y)
 local exposed = self.pendingID == W.current or self:Options(W.current).enabled == true
 self.heading:SetPoint('TOPLEFT', 0, -y)
 self.enabled:SetPoint('TOPLEFT', 0, -y - 25); self.enabled:SetPoint('TOPRIGHT', 0, -y - 25)
 self.nameLabel:SetShown(exposed); self.name:SetShown(exposed); self.error:SetShown(exposed)
 if exposed then
  self.nameLabel:SetPoint('TOPLEFT', 0, -y - 56)
  self.name:SetPoint('TOPLEFT', 0, -y - 76); self.name:SetPoint('TOPRIGHT', 0, -y - 76)
  self.error:SetPoint('TOPLEFT', 0, -y - 106); self.error:SetPoint('TOPRIGHT', 0, -y - 106); self.error:SetHeight(38)
 end
 local hasError = exposed and self.error:GetText() ~= ''
 self.error:SetShown(hasError)
 local descriptionY = y + (exposed and (hasError and 146 or 112) or 58)
 self.description:SetPoint('TOPLEFT', 0, -descriptionY); self.description:SetPoint('TOPRIGHT', 0, -descriptionY)
 local bottom = descriptionY + self.description:GetStringHeight() + 14
 self.example:SetShown(exposed); self.usage:SetShown(exposed); self.consumer:SetShown(exposed)
 if exposed then
  local name = self:Options(W.current).name
  if not name or name == '' then name = 'MyHelper' end
  self.example:SetText(addon.Query.Editor:Render('local tools = {}\nfunction tools.GiveInfo(text)\n    print(text)\nend\nreturn tools'))
  self.consumer:SetText(addon.Query.Editor:Render('local tools = requireHelper(' .. string.format('%q', name) .. ')\ntools.GiveInfo("Hello")'))
  for _, block in ipairs({ self.example, self.usage, self.consumer }) do
   block:ClearAllPoints(); block:SetPoint('TOPLEFT', 0, -bottom); block:SetPoint('TOPRIGHT', 0, -bottom); block:SetHeight(0)
   bottom = bottom + block:GetStringHeight() + 14
  end
 end
 return bottom + 6
end

function H:UpdateControls()
 if not self.enabled or not W.current then return end
 local options = self:Options(W.current)
 if self.controlID ~= W.current then
  self.pendingID = nil
  self.name:ClearFocus(); self.error:SetText(''); self.controlID = W.current
 end
 local exposed = options.enabled == true or self.pendingID == W.current
 self.enabled:SetChecked(exposed)
 self.nameLabel:SetShown(exposed); self.name:SetShown(exposed); self.error:SetShown(exposed)
 if not self.name:HasFocus() then self.name:SetText(options.name or '') end
end
