local _, addon = ...
local W, UI, L, Console = addon.Workspace, addon.UI, addon.L, addon.Query.Console
local N = { history = {} }
addon.Navigation = N

function N:CanBack() return #self.history > 0 end

function N:Remember()
 self.history[#self.history + 1] = { id = W.current, cursor = Console.input.editBox:GetCursorPosition(), scroll = Console.input.scrollFrame:GetVerticalScroll() }
 if #self.history > 40 then table.remove(self.history, 1) end
end

function N:ScrollTo(input, offset)
 local scroll = input.scrollFrame
 scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(), offset)))
end

function N:Position(input, position, focus)
 if focus ~= false then input:SetFocus() end
 input:SetCursorPosition(position); input:HighlightText(position, position)
 if input == Console.input then
  Console:UpdateLineNumbers()
  local line = Console:GetLinePosition(Console.source, position)
  local state = input.queryLineNumbers
  local entry = state and state.positions and state.positions[line]
  if entry then self:ScrollTo(input, entry.offset - 40) end
 else
  local size = select(2, input.editBox:GetFont()) or 14
  local _, line = input:GetText():sub(1, position):gsub('\n', '')
  self:ScrollTo(input, line * (size + input.editBox:GetSpacing()) - 40)
 end
end

function N:Back()
 local target = table.remove(self.history)
 if not target then return end
 if self.snapshot then self.snapshot:Hide() end
 if not W.db.drafts[target.id] and not W.db.snippets[target.id] then Console:SetStatus(L.navigationMissingScript, true); return end
 W:Select(target.id)
 self:Position(Console.input, math.min(target.cursor, #Console.source))
 self:ScrollTo(Console.input, target.scroll)
end

function N:SavedSnapshot(module, definition)
 W:HidePanels(self.snapshot)
 if not self.snapshot then
  local panel = CreateFrame('Frame', 'LuaWorkbenchSavedHelper', W.window); self.snapshot = panel
  panel:SetSize(math.max(320, W.window:GetWidth() - 40), math.max(300, W.window:GetHeight() - 70)); panel:SetPoint('CENTER')
  panel:SetFrameLevel(W.window:GetFrameLevel() + 55); panel:EnableMouse(true)
  UI:MovablePanel(panel, 'savedHelper'); panel:RestorePanelPosition()
 UI:Background(panel, { 0.09, 0.11, 0.15, 1 }); UI:Border(panel, { 0.28, 0.34, 0.43, 1 })
  self.snapshotTitle = UI:Text(panel, '', 13); self.snapshotTitle:SetPoint('TOPLEFT', 14, -12); self.snapshotTitle:SetPoint('RIGHT', -42, 0)
  local close = UI:Button(panel, 'close', _G.CLOSE, function() self:Back() end); close:SetPoint('TOPRIGHT', -4, -4)
  local hint = UI:Text(panel, L.navigationSavedHelp, 11); hint:SetPoint('TOPLEFT', 14, -40); hint:SetPoint('TOPRIGHT', -14, -40); hint:SetWordWrap(true)
  self.snapshotInput = UI:Editor(panel, L.savedCodeOnly, true)
  self.snapshotInput.frame:SetPoint('TOPLEFT', 8, -90); self.snapshotInput.frame:SetPoint('BOTTOMRIGHT', -8, 8)
  self.snapshotInput.editBox:HookScript('OnKeyDown', function(_, key)
   if self:IsBackKey(key) then self:Back() end
  end)
  self.snapshotInput.editBox:SetScript('OnEscapePressed', function() self:Back() end)
  panel:SetScript('OnHide', function() self.snapshotInput:ClearFocus() end)
  _G.UISpecialFrames[#_G.UISpecialFrames + 1] = 'LuaWorkbenchSavedHelper'
 end
 self.snapshotTitle:SetText((module.name .. ' — ' .. L.navigationSavedVersion):gsub('|', '||'))
 self.snapshotInput:SetText(W:NormalizeSource(module.source))
 self.snapshot:Show(); self:Position(self.snapshotInput, definition.position0)
 Console:SetStatus(L.navigationSavedHelp)
end

function N:Jump(candidate)
 if candidate.module then
  local module, message = addon.Helpers:Resolve(candidate.module)
  if not module then Console:SetStatus(message, true); return end
  local result = addon.Analysis:Get(W:NormalizeSource(module.source))
  local definition = result.exports[candidate.member]
  if not definition or definition.ambiguous then Console:SetStatus(L.navigationNotFound, true); return end
  self:Remember()
  local draft = W.db.drafts[module.id]
  if draft and W:NormalizeSource(draft.source) ~= W:NormalizeSource(module.source) then
   self:SavedSnapshot(module, definition)
  else
   W:Select(module.id); self:Position(Console.input, definition.position0)
  end
 else
  if not candidate.position0 then Console:SetStatus(L.navigationNotFound, true); return end
  self:Remember(); self:Position(Console.input, candidate.position0)
 end
end

function N:Go(target)
 if not Console.input then return end
 local source, cursor = Console.source, Console.input.editBox:GetCursorPosition()
 if target then
  if target.scriptId ~= W.current or target.source ~= source then Console:SetStatus(L.textSnippetTargetChanged, true); return end
  cursor = target.cursor
 end
 local candidates = addon.Analysis:Resolve(source, cursor)
 if #candidates == 0 then
  local apiName = addon.APIHelp and addon.APIHelp:AtCursor(source, cursor)
  if apiName then addon.KnowledgeBase:Show(apiName); Console:SetStatus(nil); return end
  Console:SetStatus(L.navigationNotFound, true); return
 end
 if #candidates == 1 then self:Jump(candidates[1]); return end
 local entries = {}
 for _, candidate in ipairs(candidates) do
  local selected = candidate
  local line = candidate.position0 and Console:GetLinePosition(source, candidate.position0) or 0
  entries[#entries + 1] = { text = (candidate.name or '') .. ' · ' .. string.format(L.navigationLine, line), action = function() self:Jump(selected) end }
 end
 W:OpenMenu(Console.input.frame, entries)
end

function N:IsBackKey(key)
 return key == 'F12' and IsShiftKeyDown() and not IsControlKeyDown()
  and not (_G.IsAltKeyDown and IsAltKeyDown()) and not (_G.IsMetaKeyDown and _G.IsMetaKeyDown())
end

function N:Shortcut(key)
 if not W.window or not W.window:IsShown() or not Console.input or not Console.input.editBox:HasFocus() then return false end
 if key == 'F12' and not IsControlKeyDown() and not IsShiftKeyDown() and not (_G.IsAltKeyDown and IsAltKeyDown()) and not (_G.IsMetaKeyDown and _G.IsMetaKeyDown()) then
  if not self.held then self.held = key; self:Go() end
  return true
 elseif self:IsBackKey(key) then
  if not self.held then self.held = key; self:Back() end
  return true
 end
 return false
end
