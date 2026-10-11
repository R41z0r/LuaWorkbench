local _, addon = ...
local Search = {}
addon.Search = Search

-- Plain-text matching: code punctuation is never interpreted as a pattern.
function Search:Matches(source, query, matchCase, wholeWord)
 source = source:gsub('\r\n', '\n'):gsub('\r', '\n')
 local matches = {}
 if query == '' then return matches end
 local text, needle = source, query
 if not matchCase then text, needle = text:lower(), needle:lower() end
 local offset = 1
 while offset <= #text do
  local first, last = text:find(needle, offset, true)
  if not first then break end
  local before, after = source:sub(first - 1, first - 1), source:sub(last + 1, last + 1)
  if not wholeWord or (not before:match('[%w_]') and not after:match('[%w_]')) then
   matches[#matches + 1] = { first = first, last = last }
  end
  offset = last + 1
 end
 return matches
end

function Search:SnippetRows(db, query)
 local rows, seen = {}, {}
 for _, collection in ipairs({ db.drafts, db.snippets }) do
  for id, snippet in pairs(collection) do
   if not seen[id] then
    seen[id] = true
    local matches = self:Matches(snippet.source, query, false, false)
    local named = query == '' or snippet.name:lower():find(query:lower(), 1, true)
    if named or #matches > 0 then
     rows[#rows + 1] = { id = id, name = snippet.name, matches = matches }
    end
   end
  end
 end
 table.sort(rows, function(a, b)
  if a.name == b.name then return tonumber(a.id) < tonumber(b.id) end
  return a.name:lower() < b.name:lower() or (a.name:lower() == b.name:lower() and a.id < b.id)
 end)
 return rows
end
