if not ForeverAuras.IsLibsOK() then return end
local _, OptionsPrivate = ...
local Theme = OptionsPrivate.Theme
local Tools = {}
OptionsPrivate.EditorTools = Tools

local labels = {
  enUS = {search = "Search", case = "Match case", previous = "Previous match", next = "Next match", empty = "No matches", close = "Close search", theme = "Color theme"},
  deDE = {search = "Suche", case = "Groß-/Kleinschreibung", previous = "Vorheriger Treffer", next = "Nächster Treffer", empty = "Keine Treffer", close = "Suche schließen", theme = "Farbschema"},
  frFR = {search = "Rechercher", case = "Respecter la casse", previous = "Résultat précédent", next = "Résultat suivant", empty = "Aucun résultat", close = "Fermer la recherche", theme = "Couleurs"},
  esES = {search = "Buscar", case = "Distinguir mayúsculas", previous = "Coincidencia anterior", next = "Coincidencia siguiente", empty = "Sin resultados", close = "Cerrar búsqueda", theme = "Tema de color"},
  esMX = {search = "Buscar", case = "Distinguir mayúsculas", previous = "Coincidencia anterior", next = "Coincidencia siguiente", empty = "Sin resultados", close = "Cerrar búsqueda", theme = "Tema de color"},
  itIT = {search = "Cerca", case = "Maiuscole/minuscole", previous = "Risultato precedente", next = "Risultato successivo", empty = "Nessun risultato", close = "Chiudi ricerca", theme = "Tema colori"},
  ptBR = {search = "Buscar", case = "Diferenciar maiúsculas", previous = "Resultado anterior", next = "Próximo resultado", empty = "Sem resultados", close = "Fechar busca", theme = "Tema de cores"},
  ruRU = {search = "Поиск", case = "Учитывать регистр", previous = "Предыдущее совпадение", next = "Следующее совпадение", empty = "Нет совпадений", close = "Закрыть поиск", theme = "Цветовая схема"},
  koKR = {search = "검색", case = "대소문자 구분", previous = "이전 결과", next = "다음 결과", empty = "결과 없음", close = "검색 닫기", theme = "색상 테마"},
  zhCN = {search = "搜索", case = "区分大小写", previous = "上一个匹配", next = "下一个匹配", empty = "无匹配", close = "关闭搜索", theme = "颜色主题"},
  zhTW = {search = "搜尋", case = "區分大小寫", previous = "上一個符合項目", next = "下一個符合項目", empty = "無符合項目", close = "關閉搜尋", theme = "色彩主題"},
}
Tools.labels = labels[GetLocale()] or labels.enUS
Tools.themeOrder = {"Standard", "Obsidian", "Monokai", "Dracula", "Nord", "One Dark", "Gruvbox", "Catppuccin"}
Tools.themes = {
  Standard = {Table = "|c00ff3333", Arithmetic = "|c00ff3333", Relational = "|c00ff3333", Logical = "|c004444ff", Special = "|c00ff3333", Keyword = "|c004444ff", Comment = "|c0000aa00", Number = "|c00ff9900", String = "|c00999999"},
  Obsidian = {Table = "|c00AFC0E5", Arithmetic = "|c00E0E2E4", Relational = "|c00B3B689", Logical = "|c0093C763", Special = "|c00AFC0E5", Keyword = "|c0093C763", Comment = "|c0066747B", Number = "|c00FFCD22", String = "|c00EC7600"},
  Monokai = {Table = "|c00ffffff", Arithmetic = "|c00f92672", Relational = "|c00ff3333", Logical = "|c00f92672", Special = "|c0066d9ef", Keyword = "|c00f92672", Comment = "|c0075715e", Number = "|c00ae81ff", String = "|c00e6db74"},
  Dracula = {Table = "|cfff8f8f2", Arithmetic = "|cffff79c6", Relational = "|cffff79c6", Logical = "|cffff79c6", Special = "|cff8be9fd", Keyword = "|cffff79c6", Comment = "|cff8898cc", Number = "|cffbd93f9", String = "|cfff1fa8c", background = {0.157, 0.165, 0.212, 1}},
  Nord = {Table = "|cffd8dee9", Arithmetic = "|cff81a1c1", Relational = "|cff81a1c1", Logical = "|cff81a1c1", Special = "|cff88c0d0", Keyword = "|cff81a1c1", Comment = "|cff8a9bb5", Number = "|cffb48ead", String = "|cffa3be8c", background = {0.18, 0.204, 0.251, 1}},
  ["One Dark"] = {Table = "|cffabb2bf", Arithmetic = "|cff56b6c2", Relational = "|cff56b6c2", Logical = "|cffc678dd", Special = "|cff61afef", Keyword = "|cffc678dd", Comment = "|cff8992a3", Number = "|cffd19a66", String = "|cff98c379", background = {0.157, 0.173, 0.204, 1}},
  Gruvbox = {Table = "|cffebdbb2", Arithmetic = "|cfffe8019", Relational = "|cfffe8019", Logical = "|cfffb4934", Special = "|cff8ec07c", Keyword = "|cfffb4934", Comment = "|cffa89984", Number = "|cffd3869b", String = "|cffb8bb26", background = {0.157, 0.157, 0.157, 1}, text = {0.922, 0.859, 0.698, 1}},
  Catppuccin = {Table = "|cffcdd6f4", Arithmetic = "|cff89dceb", Relational = "|cff89dceb", Logical = "|cffcba6f7", Special = "|cff89b4fa", Keyword = "|cffcba6f7", Comment = "|cff9399b2", Number = "|cfffab387", String = "|cffa6e3a1", background = {0.118, 0.118, 0.18, 1}, text = {0.804, 0.839, 0.957, 1}},
}

function Tools.ApplyTheme(editor)
  local selected = Tools.themes[ForeverAurasSaved.editor_theme] or Tools.themes.Monokai
  local background = selected.background or {0.065, 0.075, 0.095, 1}
  local text = selected.text or {0.96, 0.97, 0.99, 1}
  editor.frame.faModernBackground = background
  editor.editBox.faModernTextColor = text
  editor.editBox:SetTextColor(unpack(text))
  if Theme.IsModern() then
    Theme.SkinFrame(editor.frame)
  elseif editor.scrollBG.SetBackdropColor then
    editor.scrollBG:SetBackdropColor(unpack(background))
  end
end

function Tools.DecodePositions(raw)
  local text, starts, finishes = {}, {}, {}
  local position, index = 1, 0
  while position <= #raw do
    local marker = raw:sub(position, position + 1)
    if marker == "|c" and raw:sub(position + 2, position + 9):match("^%x%x%x%x%x%x%x%x$") then
      position = position + 10
    elseif marker == "|r" then
      position = position + 2
    else
      index = index + 1
      local escaped = marker == "||"
      text[index] = escaped and "|" or raw:sub(position, position)
      starts[index] = position - 1
      finishes[index] = position + (escaped and 1 or 0)
      position = position + (escaped and 2 or 1)
    end
  end
  return table.concat(text), starts, finishes
end

function Tools.FindMatches(raw, query, matchCase)
  local text, starts, finishes = Tools.DecodePositions(raw)
  local matches = {}
  if not query or query == "" then return matches end
  local haystack = matchCase and text or text:lower()
  local needle = matchCase and query or query:lower()
  local position = 1
  while position <= #haystack do
    local first, last = haystack:find(needle, position, true)
    if not first then break end
    matches[#matches + 1] = {starts[first], finishes[last]}
    position = last + 1
  end
  return matches
end

function Tools.Recolor(editor, originalGetText)
  local box = editor.editBox
  local raw = originalGetText(box) or ""
  local _, _, ends = Tools.DecodePositions(raw)
  local caret, offset = box:GetCursorPosition(), 0
  for index, last in ipairs(ends) do if last <= caret then offset = index else break end end
  local scroll = editor.scrollFrame:GetVerticalScroll()
  box:SetText(box:GetText())
  IndentationLib.colorCodeEditbox(box)
  local _, starts, finishes = Tools.DecodePositions(originalGetText(box) or "")
  box:SetCursorPosition(starts[offset + 1] or finishes[#finishes] or 0)
  editor.scrollFrame:SetVerticalScroll(math.min(scroll, editor.scrollFrame:GetVerticalScrollRange()))
end

function Tools.CreateSearch(group, editor, originalGetText)
  local label = Tools.labels
  local bar = CreateFrame("Frame", nil, editor.frame)
  bar:SetPoint("TOPLEFT", editor.frame, "TOPLEFT", 0, -21)
  bar:SetPoint("TOPRIGHT", editor.frame, "TOPRIGHT", 0, -21)
  bar:SetHeight(28)
  bar:Hide()
  local input = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
  input.faModernInput = true
  input:SetAutoFocus(false)
  input:SetFontObject(ChatFontNormal)
  input:SetHeight(24)
  local title = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  title:SetText(label.search)
  title:SetPoint("LEFT", bar, "LEFT", 2, 0)
  input:SetPoint("LEFT", title, "RIGHT", 12, 0)

  local function Button(text, width)
    local result = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    result:SetText(text)
    result:SetSize(width, 24)
    return result
  end
  local close = Button("x", 24)
  close:SetPoint("RIGHT", bar, "RIGHT")
  local count = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetPoint("RIGHT", close, "LEFT", -6, 0)
  count:SetWidth(96)
  count:SetJustifyH("CENTER")
  local next = Button(">", 28)
  next.faModernArrow = "right"
  next:SetPoint("RIGHT", count, "LEFT", -6, 0)
  local previous = Button("<", 28)
  previous.faModernArrow = "left"
  previous:SetPoint("RIGHT", next, "LEFT", -4, 0)
  local case = Button("Aa", 32)
  case:SetPoint("RIGHT", previous, "LEFT", -4, 0)
  input:SetPoint("RIGHT", case, "LEFT", -8, 0)
  local toggle = CreateFrame("Button", nil, group.frame, "UIPanelButtonTemplate")
  toggle:SetText(label.search)
  toggle:SetSize(100, 20)
  toggle:SetPoint("BOTTOMRIGHT", editor.frame, "TOPRIGHT", -130, -10)
  toggle:SetFrameLevel(group.frame:GetFrameLevel() + 2)
  editor.label:SetPoint("TOPRIGHT", editor.frame, "TOPRIGHT", -240, -4)

  local search = {frame = bar, input = input, matches = {}, index = 0, generation = 0, matchCase = ForeverAurasOptionsSaved.editor_search_match_case == true}
  group.codeSearch = search
  local function UpdateCount()
    if input:GetText() == "" then
      count:SetText("")
    elseif #search.matches == 0 then
      count:SetText(label.empty)
    else
      count:SetText(("%d / %d"):format(search.index, #search.matches))
    end
    previous:SetEnabled(#search.matches > 0)
    next:SetEnabled(#search.matches > 0)
    case:GetFontString().faModernTextColor = search.matchCase and {0.96, 0.77, 0.38, 1} or nil
    if Theme.IsModern() then Theme.SkinFrame(case) end
  end
  local function Rebuild()
    local raw = originalGetText(editor.editBox) or ""
    local query = input:GetText() or ""
    if raw ~= search.raw or query ~= search.query or search.previousCase ~= search.matchCase then
      search.matches = Tools.FindMatches(raw, query, search.matchCase)
      if query ~= search.query or search.previousCase ~= search.matchCase then search.index = 0 end
      search.index = math.min(search.index, #search.matches)
      search.raw, search.query, search.previousCase = raw, query, search.matchCase
    end
    UpdateCount()
  end
  function search:Navigate(direction, focusEditor)
    if IndentationLib.colorCodeEditbox then IndentationLib.colorCodeEditbox(editor.editBox) end
    Rebuild()
    if #self.matches == 0 then return end
    self.index = self.index == 0 and (direction < 0 and #self.matches or 1) or (self.index - 1 + direction) % #self.matches + 1
    local selected = self.matches[self.index]
    local keepFocus = not focusEditor and input:HasFocus()
    if not keepFocus then editor.editBox:SetFocus() end
    editor.editBox:SetCursorPosition(selected[1])
    editor.editBox:HighlightText(selected[1], selected[2])
    local autocomplete = LibStub("LibAPIAutoComplete-1.0", true)
    if autocomplete and autocomplete.scrollBox then autocomplete:Hide() end
    UpdateCount()
  end
  function search:Layout()
    local inset = bar:IsShown() and 32 or 0
    editor.frame.faEditorSearchHeight = inset
    local top = editor.labelHeight == 0 and editor.frame or editor.label
    editor.scrollBar:SetPoint("TOP", top, editor.labelHeight == 0 and "TOP" or "BOTTOM", 0, -(editor.labelHeight == 0 and 23 or 19) - inset)
    if Theme.IsModern() then Theme.SkinFrame(editor.frame); Theme.ApplyFont(bar) end
  end
  function search:Open()
    bar:Show()
    self:Layout()
    input:SetFocus()
    input:HighlightText()
    Rebuild()
  end
  function search:Close()
    self.generation = self.generation + 1
    bar:Hide()
    self:Layout()
    input:ClearFocus()
    editor.editBox:SetFocus()
    editor.editBox:HighlightText(0, 0)
  end
  function search:Reset()
    self.generation = self.generation + 1
    self.matches, self.index, self.raw, self.query = {}, 0, nil, nil
    input:SetText("")
    bar:Hide()
    self:Layout()
  end
  input:SetScript("OnTextChanged", function()
    search.generation = search.generation + 1
    local generation = search.generation
    C_Timer.After(0.15, function()
      if generation ~= search.generation or not bar:IsVisible() then return end
      search.index = 0
      search:Navigate(1, false)
    end)
  end)
  input:SetScript("OnEnterPressed", function() search:Navigate(IsShiftKeyDown() and -1 or 1, false) end)
  input:SetScript("OnEscapePressed", function() search:Close() end)
  toggle:SetScript("OnClick", function() if bar:IsShown() then search:Close() else search:Open() end end)
  previous:SetScript("OnClick", function() search:Navigate(-1, true) end)
  next:SetScript("OnClick", function() search:Navigate(1, true) end)
  close:SetScript("OnClick", function() search:Close() end)
  case:SetScript("OnClick", function()
    search.matchCase = not search.matchCase
    ForeverAurasOptionsSaved.editor_search_match_case = search.matchCase
    search.index, search.previousCase = 0, nil
    search:Navigate(1, false)
  end)
  editor.editBox:HookScript("OnCursorChanged", function(_, _, y, _, cursorHeight)
    if not bar:IsShown() or not input:HasFocus() or not y then return end
    local view = editor.scrollFrame
    local offset = view:GetVerticalScroll()
    local top = math.max(0, -y)
    local bottom = top + (cursorHeight or 0) - view:GetHeight()
    local target = top < offset and top or bottom > offset and bottom or offset
    view:SetVerticalScroll(math.max(0, math.min(view:GetVerticalScrollRange(), target)))
  end)
  editor.editBox:HookScript("OnTextChanged", function()
    if not bar:IsShown() or search.rebuildPending then return end
    search.rebuildPending = true
    C_Timer.After(0, function() search.rebuildPending = false; if bar:IsShown() then Rebuild() end end)
  end)
  local function KeyDown(frame, key)
    if IsControlKeyDown() and key == "F" then
      frame:SetPropagateKeyboardInput(false)
      search:Open()
    elseif key == "F3" then
      frame:SetPropagateKeyboardInput(false)
      if not bar:IsShown() then search:Open() end
      search:Navigate(IsShiftKeyDown() and -1 or 1, frame == editor.editBox)
    end
  end
  editor.editBox:HookScript("OnKeyDown", KeyDown)
  input:SetScript("OnKeyDown", KeyDown)
  for _, control in ipairs({{previous, label.previous .. " (Shift+F3)"}, {next, label.next .. " (F3)"}, {case, label.case}, {close, label.close .. " (Esc)"}}) do
    local button, text = control[1], control[2]
    button:SetScript("OnEnter", function() GameTooltip:SetOwner(button, "ANCHOR_TOP"); GameTooltip:SetText(text); GameTooltip:Show() end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  for _, method in ipairs({"SetLabel", "SetNumLines", "DisableButton"}) do hooksecurefunc(editor, method, function() search:Layout() end) end
  UpdateCount()
  return search
end
