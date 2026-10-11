local _, addon = ...
local W, UI, L = addon.Workspace, addon.UI, addon.L

function W:NormalizeSource(source) return (source:gsub('\r\n', '\n'):gsub('\r', '\n')) end
function W:StoreSource(source)
 source = self:NormalizeSource(source)
 return self.db.options.crlf and source:gsub('\n', '\r\n') or source
end

function W:Fonts()
 local fonts = {}
 local seen = {}
 for _, item in ipairs({ { ChatFontNormal, L.fontChat }, { GameFontHighlightSmall, L.fontUI }, { _G.NumberFontNormal or GameFontHighlightSmall, L.fontNumbers } }) do
  local path = item[1]:GetFont()
  fonts[#fonts + 1] = { path = path, name = item[2] }
  seen[path] = true
 end
 local media = _G.LibStub and LibStub('LibSharedMedia-3.0', true)
 if media then
  for _, name in ipairs(media:List('font')) do
   local path = media:Fetch('font', name)
   if not seen[path] then fonts[#fonts + 1] = { path = path, name = name }; seen[path] = true end
  end
 end
 return fonts
end

function W:ApplyOptions()
 local options = self.db.options
 local default = ChatFontNormal:GetFont()
 for _, item in ipairs({ { addon.Query.Console.input, 'code' }, { addon.Query.Console.output, 'output' }, { addon.Snippets.panel and addon.Snippets.panel.code, 'code' } }) do
  local input, key = item[1], item[2]
  if input then
   local ok = input.editBox:SetFont(options[key .. 'Font'] or default, options[key .. 'Size'] or 14, options[key .. 'Style'] or '')
   if ok == false then input.editBox:SetFont(default, options[key .. 'Size'] or 14, options[key .. 'Style'] or '') end
   if key == 'code' and input.queryLineNumbers then
    local width = math.max(36, math.ceil((options.codeSize or 14) * 3))
    input.queryLineNumbers.gutter:SetWidth(width)
    input.scrollFrame:SetPoint('TOPLEFT', input.scrollBG, 'TOPLEFT', width + 7, -6)
   end
   input.scrollFrame:UpdateScrollChildRect()
   if input.queryEditor then addon.Query.Editor:Paint(input) end
  end
 end
 if addon.Query.Console.input then
  addon.Query.Editor:Paint(addon.Query.Console.input)
  addon.Query.Console:UpdateLineNumbers()
 end
 self:UpdateStatus()
 self:RefreshTree()
end

function W:ShowOptions()
 self:HidePanels(self.optionsFrame)
 if self.syntaxFrame then self.syntaxFrame:Hide() end
 if addon.Diagnostics.panel then addon.Diagnostics.panel:Hide() end
 if addon.Automation.panel then addon.Automation.panel:Hide() end
 if self.helpFrame then self.helpFrame:Hide() end
 if self.optionsFrame then self.optionsFrame:SetShown(not self.optionsFrame:IsShown()); return end
 local panel = CreateFrame('Frame', nil, self.window)
 self.optionsFrame = panel
 panel:SetSize(math.min(520, self.window:GetWidth() - 24), math.min(570, self.window:GetHeight() - 30)); panel:SetPoint('CENTER'); panel:SetFrameLevel(self.window:GetFrameLevel() + 30); panel:EnableMouse(true)
 UI:MovablePanel(panel, 'options'); panel:RestorePanelPosition()
 UI:Background(panel, { 0.09, 0.11, 0.15, 1 })
 local title = UI:Text(panel, L.options, 15); title:SetPoint('TOPLEFT', 16, -15)
 local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide() end); close:SetPoint('TOPRIGHT', -6, -7)
 local scroll = UI:Scroll(panel); scroll:SetPoint('TOPLEFT', 12, -48); scroll:SetPoint('BOTTOMRIGHT', -24, 58)
 local content = CreateFrame('Frame', nil, scroll); content:SetSize(472, 490); scroll:SetScrollChild(content)
 local options, section = self.db.options, 1
 local rows, tabs = {}, {}
 panel.optionRows, panel.optionTabs, panel.optionTab = rows, tabs, 1
 local function setting(label, value, action, enabled)
  local y = 0
  local text = UI:Text(content, label, 11); text:SetPoint('TOPLEFT', 3, y - 8); text:SetWidth(237)
  local button = CreateFrame('Button', nil, content); button:SetSize(220, 29); button:SetPoint('TOPRIGHT', -2, y)
  UI:Background(button, { 0.16, 0.19, 0.24, 1 })
  button.text = UI:Text(button, '', 11); button.text:SetPoint('LEFT', 8, 0); button.text:SetWidth(174); button.text:SetWordWrap(false)
  local track, knob
  if enabled then
   track = button:CreateTexture(nil, 'ARTWORK'); track:SetSize(26, 12); track:SetPoint('RIGHT', -10, 0)
   knob = UI:Dot(button, 8)
  else
   for step = 1, 4 do
    local arrow = button:CreateTexture(nil, 'ARTWORK')
    arrow:SetColorTexture(0.8, 0.85, 0.94, 1); arrow:SetSize(9 - step * 2, 1)
    arrow:SetPoint('RIGHT', button, 'RIGHT', -14 - step, 3 - step)
   end
  end
  local hover = button:CreateTexture(nil, 'HIGHLIGHT'); hover:SetAllPoints(); hover:SetColorTexture(1, 1, 1, 0.06)
  local function refresh()
   button.text:SetText(value())
   if enabled then
    local on = enabled()
    track:SetColorTexture(on and 0.17 or 0.3, on and 0.5 or 0.32, on and 0.34 or 0.37, 1)
    knob:ClearAllPoints(); knob:SetPoint('RIGHT', button, 'RIGHT', on and -12 or -24, 0)
   end
  end
  button:SetScript('OnShow', refresh)
  button:SetScript('OnClick', function() action(button, refresh); refresh() end)
  refresh()
  rows[#rows + 1] = { label = text, button = button, section = section, refresh = refresh }
 end
 for _, item in ipairs({ { 'code', L.optionsTabEditor }, { 'output', L.optionsTabOutput } }) do
  local key = item[1]
  section = key == 'code' and 1 or 2
  setting(item[2] .. ': ' .. L.font, function() return options[key .. 'FontName'] or L.fontChat end, function(button, refresh)
   local entries = {}
   for _, font in ipairs(self:Fonts()) do
    local selected = font
    entries[#entries + 1] = { text = font.name, selected = font.name == (options[key .. 'FontName'] or L.fontChat), action = function()
     options[key .. 'Font'], options[key .. 'FontName'] = selected.path, selected.name
     self:ApplyOptions(); refresh()
    end }
   end
   self:OpenMenu(button, entries)
  end)
  setting(item[2] .. ': ' .. L.fontSize, function() return tostring(options[key .. 'Size'] or 14) end, function(button, refresh)
   local entries = {}
   for size = 10, 28 do
    local selected = size
    entries[#entries + 1] = { text = tostring(size), selected = size == (options[key .. 'Size'] or 14), action = function() options[key .. 'Size'] = selected; self:ApplyOptions(); refresh() end }
   end
   self:OpenMenu(button, entries)
  end)
  local styles = { { '', L.normal }, { 'OUTLINE', L.outline }, { 'THICKOUTLINE', L.thickOutline }, { 'MONOCHROME,OUTLINE', L.monochrome } }
  setting(item[2] .. ': ' .. L.fontStyle, function()
   for _, style in ipairs(styles) do if style[1] == (options[key .. 'Style'] or '') then return style[2] end end
  end, function(button, refresh)
   local entries = {}
   for _, style in ipairs(styles) do
    local selected = style
    entries[#entries + 1] = { text = style[2], selected = style[1] == (options[key .. 'Style'] or ''), action = function() options[key .. 'Style'] = selected[1]; self:ApplyOptions(); refresh() end }
   end
   self:OpenMenu(button, entries)
  end)
 end
 local function toggle(label, key, default)
  local function enabled() local state = options[key]; if state == nil then state = default end; return state end
  setting(label, function() return enabled() and _G.ENABLE or _G.DISABLE end,
   function() options[key] = not enabled(); self:UpdateStatus(); self:RefreshTree() end, enabled)
 end
 section = 2
 local outputModes = { { 'embedded', L.outputEmbedded }, { 'floating', L.outputFloating }, { 'left', L.outputLeft }, { 'right', L.outputRight }, { 'top', L.outputTop }, { 'bottom', L.outputBottom } }
 setting(L.outputWindow, function()
  for _, mode in ipairs(outputModes) do if mode[1] == addon.OutputWindow:Mode() then return mode[2] end end
 end, function(button, refresh)
  local entries = {}
  for _, mode in ipairs(outputModes) do
   local selected = mode[1]
   entries[#entries + 1] = { text = mode[2], selected = mode[1] == addon.OutputWindow:Mode(), action = function() addon.OutputWindow:SetMode(selected); refresh() end }
  end
  self:OpenMenu(button, entries)
 end)
 setting(L.outputLimit, function() return tostring(addon.Query.Console:OutputLimit()) end, function(button, refresh)
  local entries = {}
  for _, limit in ipairs({ 50, 100, 250, 500, 1000, 2000, 5000 }) do
   local selected = limit
   entries[#entries + 1] = { text = tostring(limit), selected = limit == addon.Query.Console:OutputLimit(), action = function()
    options.outputLimit = selected; addon.Query.Console:Refresh(); refresh()
   end }
  end
  self:OpenMenu(button, entries)
 end)
 toggle(L.secretDumpChat, 'secretDumpChat', false)
 section = 1
 setting(L.apiHelp, function() return options.apiHelp ~= false and _G.ENABLE or _G.DISABLE end, function(_, refresh)
  addon.APIHelp:SetEnabled(options.apiHelp == false); refresh()
 end, function() return options.apiHelp ~= false end)
 setting(L.syntaxColors, function() return L.customize end, function() self:ShowSyntaxColors() end)
 toggle(L.runWithF5, 'runWithF5', true)
 toggle(L.autoPairs, 'autoPairs', true)
 toggle(L.autoIndent, 'autoIndent', true)
 toggle(L.debugReadOnly, 'debugReadOnly', true)
 setting(L.indentWidth, function() return tostring(options.indentWidth or 4) end, function(button, refresh)
  local entries = {}
  for _, width in ipairs({ 2, 4, 8 }) do
   local selected = width
   entries[#entries + 1] = { text = tostring(width), selected = width == (options.indentWidth or 4), action = function() options.indentWidth = selected; refresh() end }
  end
  self:OpenMenu(button, entries)
 end)
 setting(L.lineEnding, function() return options.crlf and 'CRLF' or 'LF' end, function(button, refresh)
  self:OpenMenu(button, {
   { text = 'LF', selected = not options.crlf, action = function() options.crlf = false; self:Capture(); refresh() end },
   { text = 'CRLF', selected = options.crlf == true, action = function() options.crlf = true; self:Capture(); refresh() end },
  })
 end)
 section = 3
 setting(L.windowClamp, function() return options.windowClamp ~= false and _G.ENABLE or _G.DISABLE end,
  function() options.windowClamp = options.windowClamp == false; self:ApplyWindowClamp() end,
  function() return options.windowClamp ~= false end)
 toggle(L.minimizedOutput, 'minimizedOutput', false)
 setting(L.minimizedOutputLines, function() return tostring(addon.Diagnostics:PreviewLineLimit()) end, function(button, refresh)
  local entries = {}
  for _, count in ipairs({ 1, 2, 3, 5, 10, 20 }) do
   local selected = count
   entries[#entries + 1] = { text = tostring(count), selected = count == addon.Diagnostics:PreviewLineLimit(), action = function()
    options.minimizedOutputLines = selected; addon.Diagnostics:RefreshPreview(); refresh()
   end }
  end
  self:OpenMenu(button, entries)
 end)
 toggle(L.dirtyText, 'dirtyText', false)
 toggle(L.restoreDrafts, 'restoreDrafts', true)
 setting(L.minimapToggle, function() return self.db.minimap.hide and _G.DISABLE or _G.ENABLE end, function() self:ToggleMinimap() end, function() return not self.db.minimap.hide end)
 local function layout()
  local width, y = math.max(240, scroll:GetWidth()), 0
  content:SetWidth(width)
  for _, item in ipairs(rows) do
   local shown = item.section == panel.optionTab
   item.label:SetShown(shown); item.button:SetShown(shown)
   if shown then
    local buttonWidth = math.min(220, width * 0.47)
    item.label:ClearAllPoints(); item.label:SetPoint('TOPLEFT', 3, -y - 8)
    item.label:SetWidth(width - buttonWidth - 16); item.label:SetHeight(0)
    item.label:SetWordWrap(true); item.label:SetNonSpaceWrap(true)
    item.button:ClearAllPoints(); item.button:SetPoint('TOPRIGHT', -2, -y)
    item.button:SetWidth(buttonWidth); item.button.text:SetWidth(math.max(20, buttonWidth - 46))
    item.refresh()
    y = y + math.max(37, item.label:GetStringHeight() + 18)
   end
  end
  content:SetHeight(y)
  scroll:UpdateScrollChildRect()
  local tabWidth = (panel:GetWidth() - 32) / 3
  for index, tab in ipairs(tabs) do
   tab:ClearAllPoints(); tab:SetPoint('BOTTOMLEFT', 16 + (index - 1) * tabWidth, 12)
   tab:SetSize(tabWidth - 4, 32); tab.active:SetShown(index == panel.optionTab)
   tab.label:SetTextColor(index == panel.optionTab and 0.4 or 0.8, index == panel.optionTab and 0.86 or 0.84, 1)
  end
 end
 function panel:SelectOptionsTab(index)
  if W.contextMenu then W.contextMenu:Hide() end
  self.optionTab = index
  scroll:SetVerticalScroll(0)
  layout()
 end
 for index, name in ipairs({ L.optionsTabEditor, L.optionsTabOutput, L.optionsTabGeneral }) do
  local tab = UI:Button(panel, '', name, function() panel:SelectOptionsTab(index) end, nil, true)
  tab.label = UI:Text(tab, name, 11)
  tab.label:SetPoint('LEFT', 5, 0); tab.label:SetPoint('RIGHT', -5, 0)
  tab.label:SetJustifyH('CENTER'); tab.label:SetWordWrap(true)
  tab.active = tab:CreateTexture(nil, 'OVERLAY'); tab.active:SetColorTexture(0.4, 0.86, 1, 1)
  tab.active:SetPoint('BOTTOMLEFT'); tab.active:SetPoint('BOTTOMRIGHT'); tab.active:SetHeight(2)
  tabs[#tabs + 1] = tab
 end
 scroll:SetScript('OnSizeChanged', layout)
 panel:HookScript('OnShow', layout)
 panel:HookScript('OnHide', function() if W.contextMenu then W.contextMenu:Hide() end end)
 layout()
end

function W:ShowSyntaxColors()
 self.optionsFrame:Hide()
 if self.syntaxFrame then self.syntaxFrame:Show(); self:RefreshSyntaxColors(); return end
 local panel = CreateFrame('Frame', 'LuaWorkbenchSyntaxColors', self.window)
 self.syntaxFrame = panel
 panel:SetSize(490, math.min(620, self.window:GetHeight() - 30)); panel:SetPoint('CENTER')
 panel:SetFrameLevel(self.window:GetFrameLevel() + 40); panel:EnableMouse(true)
 UI:MovablePanel(panel, 'syntaxColors'); panel:RestorePanelPosition()
 UI:Background(panel, { 0.09, 0.11, 0.15, 1 }); UI:Border(panel, { 0.28, 0.34, 0.43, 1 })
 _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchSyntaxColors'
 local title = UI:Text(panel, L.syntaxColors, 15); title:SetPoint('TOPLEFT', 16, -15)
 local close = UI:Button(panel, 'close', _G.CLOSE, function() panel:Hide(); self.optionsFrame:Show() end); close:SetPoint('TOPRIGHT', -6, -7)
 local preview = CreateFrame('Frame', nil, panel)
 preview:SetPoint('BOTTOMLEFT', 16, 16); preview:SetPoint('BOTTOMRIGHT', -16, 16); preview:SetHeight(120)
 UI:Background(preview, { 0.045, 0.055, 0.075, 1 })
 local scroll = UI:Scroll(panel); scroll:SetPoint('TOPLEFT', 16, -48); scroll:SetPoint('BOTTOMRIGHT', preview, 'TOPRIGHT', -12, 12)
 local content = CreateFrame('Frame', nil, scroll); content:SetSize(442, 630); scroll:SetScrollChild(content)
 local description = UI:Text(content, L.syntaxHelp, 11); description:SetPoint('TOPLEFT'); description:SetWidth(438); description:SetWordWrap(true)
 local y = description:GetStringHeight() + 18
 self.syntaxRows = {}
 local editor = addon.Query.Editor
 for _, item in ipairs({
  { 'blizzardFunction', L.apiFunction }, { 'keyword', L.colorKeyword }, { 'call', L.colorCall }, { 'identifier', L.colorIdentifier },
  { 'string', L.colorString }, { 'number', L.colorNumber }, { 'literal', L.colorLiteral },
  { 'comment', L.colorComment }, { 'operator', L.colorOperator }, { 'punctuation', L.colorPunctuation },
  { 'localVariable', L.colorLocalVariable }, { 'globalVariable', L.colorGlobalVariable },
  { 'parameter', L.colorParameter }, { 'functionName', L.colorFunctionName },
 }) do
  local kind = item[1]
  local label = UI:Text(content, item[2], 11); label:SetPoint('TOPLEFT', 0, -y - 7); label:SetWidth(220)
  local swatch = CreateFrame('Button', nil, content); swatch:SetPoint('TOPLEFT', 228, -y); swatch:SetSize(30, 27)
  swatch.color = UI:Background(swatch); UI:Border(swatch, { 0.7, 0.75, 0.82, 1 })
  local hex = CreateFrame('EditBox', nil, content); hex:SetAutoFocus(false); hex:SetFontObject(GameFontHighlightSmall)
  hex:SetTextInsets(7, 7, 0, 0); hex:SetMaxLetters(7); hex:SetSize(95, 27); hex:SetPoint('LEFT', swatch, 'RIGHT', 8, 0)
  UI:Background(hex, UI.colors.hover); UI:Tooltip(hex, L.hexColor)
  hex:SetScript('OnEnterPressed', function()
   if editor:SetColor(kind, hex:GetText():gsub('^#', '')) then self:RefreshSyntaxColors(); hex:ClearFocus()
   else hex:SetTextColor(1, 0.35, 0.38) end
  end)
  hex:SetScript('OnEscapePressed', function() self:RefreshSyntaxColors(); hex:ClearFocus() end)
  hex:SetScript('OnEditFocusLost', function() self:RefreshSyntaxColors() end)
  local reset = UI:Button(content, 'previous', L.resetColor, function() editor:SetColor(kind, nil); self:RefreshSyntaxColors() end)
  reset:SetPoint('LEFT', hex, 'RIGHT', 8, 0)
  swatch:SetScript('OnClick', function()
   local picker = _G.ColorPickerFrame
   if not picker or not picker.SetupColorPickerAndShow then hex:SetFocus(); hex:HighlightText(); return end
   picker:Hide()
   local value = editor:Color(kind):sub(3)
   local previous = self.db.options.syntaxColors and self.db.options.syntaxColors[kind]
   self.ownedColorPicker = true
   picker:SetupColorPickerAndShow({
    r = tonumber(value:sub(1, 2), 16) / 255, g = tonumber(value:sub(3, 4), 16) / 255, b = tonumber(value:sub(5, 6), 16) / 255,
    hasOpacity = false,
    swatchFunc = function()
     local r, g, b = picker:GetColorRGB()
     editor:SetColor(kind, string.format('%02x%02x%02x', math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
     self:RefreshSyntaxColors()
    end,
    cancelFunc = function() editor:SetColor(kind, previous); self:RefreshSyntaxColors() end,
   })
  end)
  self.syntaxRows[kind] = { hex = hex, swatch = swatch.color }
  y = y + 35
 end
 local reset = UI:Action(content, 'previous', L.resetColors, L.resetColors, function() editor:ResetColors(); self:RefreshSyntaxColors() end)
 reset:SetPoint('TOPLEFT', 0, -y - 6)
 self.syntaxPreview = UI:Text(preview, '', 13)
 self.syntaxPreview:SetPoint('TOPLEFT', 12, -12); self.syntaxPreview:SetPoint('TOPRIGHT', -12, -12)
 self.syntaxPreview:SetWordWrap(true)
 content:SetHeight(y + 42)
 panel:HookScript('OnHide', function()
  if self.ownedColorPicker and _G.ColorPickerFrame then _G.ColorPickerFrame:Hide(); self.ownedColorPicker = nil end
 end)
 self:RefreshSyntaxColors()
end

function W:RefreshSyntaxColors()
 if not self.syntaxRows then return end
 local editor = addon.Query.Editor
 for kind, row in pairs(self.syntaxRows) do
  local value = editor:Color(kind):sub(3)
  row.hex:SetText('#' .. value:upper()); row.hex:SetTextColor(0.8, 0.85, 0.94)
  row.swatch:SetColorTexture(tonumber(value:sub(1, 2), 16) / 255, tonumber(value:sub(3, 4), 16) / 255, tonumber(value:sub(5, 6), 16) / 255, 1)
 end
 self.syntaxPreview:SetText(editor:Render('-- Lua\nlocal count = 3\nlocal function greet(name)\n    print("Hello", name, count + 1, true)\nend'))
end
