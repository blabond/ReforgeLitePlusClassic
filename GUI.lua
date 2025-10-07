local addonName, addonTable = ...
local GUI = {}

addonTable.FONTS = addonTable.FONTS or {
  grey = INACTIVE_COLOR,
  lightgrey = TUTORIAL_FONT_COLOR,
  white = WHITE_FONT_COLOR,
  green = CreateColor(0.6, 1, 0.6),
  red = CreateColor(1, 0.4, 0.4),
  panel = PANEL_BACKGROUND_COLOR,
  gold = GOLD_FONT_COLOR,
  darkyellow = DARKYELLOW_FONT_COLOR,
  disabled = DISABLED_FONT_COLOR,
}

GUI.widgetCount = 0
function GUI:GenerateWidgetName ()
  self.widgetCount = self.widgetCount + 1
  return addonName .. "Widget" .. self.widgetCount
end
GUI.defaultParent = nil
GUI.helpButtons = {}
GUI.helpButtonsShown = true

function GUI:CreateHelpButton(parent, tooltip, opts)
  opts = opts or {}
  local btn = CreateFrame("Button", nil, parent, "MainHelpPlateButton")
  btn:SetFrameLevel(btn:GetParent():GetFrameLevel() + 1)
  btn:SetScale(opts.scale or 0.6)
  self:SetTooltip(btn, tooltip)
  tinsert(self.helpButtons, btn)
  if not self.helpButtonsShown then
    btn:Hide()
  end
  return btn
end

function GUI:SetHelpButtonsShown(shown)
  self.helpButtonsShown = shown and true or false
  for _, btn in ipairs(self.helpButtons) do
    btn:SetShown(shown)
  end
end

function GUI:ClearEditFocus()
  if MenuUtil and MenuUtil.CloseMenu then
    MenuUtil.CloseMenu()
  end
  for _,v in ipairs(self.editBoxes) do
    v:ClearFocus()
  end
end

function GUI:ClearFocus()
  self:ClearEditFocus()
end

local function DropdownIsEnabled(dropdown)
  if not dropdown then
    return false
  end

  if dropdown.IsEnabled then
    local ok, enabled = pcall(dropdown.IsEnabled, dropdown)
    if ok then
      return enabled and true or false
    end
  end

  return dropdown.isDisabled == nil or dropdown.isDisabled == false
end

function GUI:SetDropdownEnabled(dropdown, enabled)
  if not dropdown then
    return
  end

  if dropdown.SetEnabled then
    dropdown:SetEnabled(enabled)
  end

  if enabled then
    if dropdown.EnableDropdown then
      dropdown:EnableDropdown()
    end
    if dropdown.Enable then
      dropdown:Enable()
    end
  else
    if dropdown.DisableDropdown then
      dropdown:DisableDropdown()
    end
    if dropdown.Disable then
      dropdown:Disable()
    end
  end

  local button = dropdown.Button
  if button then
    if enabled then
      if button.Enable then
        button:Enable()
      elseif button.SetEnabled then
        button:SetEnabled(true)
      end
    else
      if button.Disable then
        button:Disable()
      elseif button.SetEnabled then
        button:SetEnabled(false)
      end
    end
  end

  dropdown.isDisabled = not enabled
end

function GUI:Lock()
  for _, frames in ipairs({self.panelButtons, self.imgButtons, self.editBoxes, self.checkButtons}) do
    for _, frame in pairs(frames) do
      if frame:IsEnabled() then
        frame.locked = true
        frame:Disable()
        if frame:IsMouseEnabled() then
          frame:EnableMouse(false)
          frame.mouseDisabled = true
        elseif frame:IsMouseMotionEnabled() then
          frame:SetMouseMotionEnabled(false)
          frame.mouseMotionDisabled = true
        end
        if frame.SetTextColor then
          frame.prevColor = {frame:GetTextColor()}
          frame:SetTextColor (0.5, 0.5, 0.5)
        end
      end
    end
  end
  for _, dropdown in pairs(self.dropdowns) do
    if DropdownIsEnabled(dropdown) then
      self:SetDropdownEnabled(dropdown, false)
      dropdown.locked = true
    end
  end
  for _, dropdown in pairs(self.filterDropdowns or {}) do
    if DropdownIsEnabled(dropdown) and not dropdown.preventLock then
      self:SetDropdownEnabled(dropdown, false)
      dropdown.locked = true
    end
  end
end

function GUI:Unlock()
  for _, frames in ipairs({self.panelButtons, self.imgButtons, self.editBoxes, self.checkButtons}) do
    for _, frame in pairs(frames) do
      if frame.locked then
        frame:Enable()
        frame.locked = nil
        if frame.mouseDisabled then
          frame:EnableMouse(true)
          frame.mouseDisabled = nil
        elseif frame.mouseMotionDisabled then
          frame:SetMouseMotionEnabled(true)
          frame.mouseMotionDisabled = nil
        end
        if frame.prevColor then
          frame:SetTextColor (unpack(frame.prevColor))
          frame.prevColor = nil
        end
      end
    end
  end
  for _, dropdown in pairs(self.dropdowns) do
    if dropdown.locked then
      self:SetDropdownEnabled(dropdown, true)
      dropdown.locked = nil
    end
  end
  for _, dropdown in pairs(self.filterDropdowns or {}) do
    if dropdown.locked then
      self:SetDropdownEnabled(dropdown, true)
      dropdown.locked = nil
    end
  end
end

function GUI:SetTooltip (widget, tip)
  if tip then
    widget:SetScript ("OnEnter", function (tipFrame)
      local tooltipFunc = "AddLine"
      local tipText
      if type(tip) == "function" then
        tipText = tip()
      else
        tipText = tip
      end
      if type(tipText) == "table" then
        if tipText.spellID ~= nil then
          tooltipFunc = "SetSpellByID"
          tipText = tipText.spellID
        end
      end
      if tipText then
        GameTooltip:SetOwner(tipFrame, "ANCHOR_LEFT")
        GameTooltip[tooltipFunc](GameTooltip, tipText, nil, nil, nil, true)
        GameTooltip:Show()
      end
    end)
    widget:SetScript ("OnLeave", GameTooltip_Hide)
  else
    widget:SetScript ("OnEnter", nil)
    widget:SetScript ("OnLeave", nil)
  end
end

GUI.editBoxes = {}
GUI.unusedEditBoxes = {}
function GUI:CreateEditBox (parent, width, height, default, setter, opts)
  opts = opts or {}
  local box
  if #self.unusedEditBoxes > 0 then
    box = tremove (self.unusedEditBoxes)
    box:SetParent (parent)
    box:Show ()
    if addonTable.FONTS and addonTable.FONTS.white then
      box:SetTextColor(addonTable.FONTS.white:GetRGB())
    else
      box:SetTextColor (1, 1, 1)
    end
    box:EnableMouse (true)
    self.editBoxes[box:GetName()] = box
  else
    box = CreateFrame ("EditBox", self:GenerateWidgetName (), parent, "InputBoxTemplate")
    self.editBoxes[box:GetName()] = box
    box:SetAutoFocus (false)
    box:SetFontObject (ChatFontNormal)
    if addonTable.FONTS and addonTable.FONTS.white then
      box:SetTextColor(addonTable.FONTS.white:GetRGB())
    else
      box:SetTextColor (1, 1, 1)
    end
    box:SetNumeric ()
    box:SetTextInsets (0, 0, 3, 3)
    box:SetMaxLetters (8)
    box.Recycle = function (box)
      box:Hide ()
      box:SetScript ("OnEditFocusLost", nil)
      box:SetScript ("OnEditFocusGained", nil)
      box:SetScript ("OnEnterPressed", nil)
      box:SetScript ("OnEnter", nil)
      box:SetScript ("OnLeave", nil)
      box:SetScript ("OnTabPressed", nil)
      self.editBoxes[box:GetName()] = nil
      tinsert (self.unusedEditBoxes, box)
    end
  end
  if width then
    box:SetWidth (width)
  end
  if height then
    box:SetHeight (height)
  end
  box:SetText (default)
  box:SetScript ("OnEnterPressed", box.ClearFocus)
  box:SetScript ("OnEditFocusGained", function(frame)
    frame.prevValue = tonumber(frame:GetText())
    frame:HighlightText()
  end)
  box:SetScript ("OnEditFocusLost", function (frame)
    local value = tonumber(frame:GetText())
    if not value then
      value = frame.prevValue or 0
    end
    frame:SetText (value)
    if setter then
      setter (value)
    end
    frame.prevValue = nil
  end)
  box:SetScript ("OnTabPressed", opts.OnTabPressed)
  return box
end


GUI.dropdowns = {}
GUI.unusedDropdowns = {}
GUI.filterDropdowns = {}
GUI.unusedFilterDropdowns = {}

function GUI:CreateFilterDropdown (parent, text, options)
  options = options or {}
  local dropdown
  if #self.unusedFilterDropdowns > 0 then
    dropdown = tremove(self.unusedFilterDropdowns)
    dropdown:SetParent(parent)
    dropdown:Show()
    dropdown:SetEnabled(true)
    if dropdown.originalResizeToTextPadding then
      dropdown.resizeToTextPadding = dropdown.originalResizeToTextPadding
      dropdown.originalResizeToTextPadding = nil
    end
    self.filterDropdowns[dropdown:GetName()] = dropdown
  else
    local name = self:GenerateWidgetName()
    dropdown = CreateFrame("DropdownButton", name, parent, "WowStyle1FilterDropdownTemplate")
    self.filterDropdowns[name] = dropdown
    dropdown.originalResizeToTextPadding = dropdown.resizeToTextPadding

    dropdown.Recycle = function(frame)
      frame:Hide()
      frame.originalResizeToTextPadding = frame.resizeToTextPadding
      frame.resizeToTextPadding = nil
      self.filterDropdowns[frame:GetName()] = nil
      tinsert(self.unusedFilterDropdowns, frame)
    end
  end

  if options.resizeToTextPadding then
    dropdown.resizeToTextPadding = options.resizeToTextPadding
  end
  dropdown:SetText(text)
  self:SetTooltip(dropdown, options.tooltip)
  return dropdown
end

function GUI:CreateDropdown (parent, values, options)
  options = options or {}
  local sel
  if #self.unusedDropdowns > 0 then
    sel = tremove(self.unusedDropdowns)
    sel:SetParent(parent)
    sel:Show()
    self:SetDropdownEnabled(sel, true)
    self.dropdowns[sel:GetName()] = sel
  else
    sel = CreateFrame("DropdownButton", self:GenerateWidgetName(), parent, "WowStyle1DropdownTemplate")
    self.dropdowns[sel:GetName()] = sel

    if sel.Text then
      sel.Text:ClearAllPoints()
      sel.Text:SetPoint("RIGHT", sel.Arrow, "LEFT")
      sel.Text:SetPoint("LEFT", sel, "LEFT", 9, 0)
      if addonTable.FONTS and addonTable.FONTS.white then
        sel.Text:SetTextColor(addonTable.FONTS.white:GetRGB())
      else
        sel.Text:SetTextColor(1, 1, 1)
      end
    end

    sel.GetValues = function(frame)
      return GetValueOrCallFunction(frame, 'values')
    end

    sel.SetValue = function(dropdown, value)
      dropdown.value = value
      dropdown.selectedValue = value
      local list = dropdown:GetValues()
      if not list then
        if dropdown.Text then
          dropdown.Text:SetText("")
        end
        return
      end
      for _, v in ipairs(list) do
        if v.value == value then
          if dropdown.Text then
            dropdown.Text:SetText(v.name)
          end
          return
        end
      end
      if dropdown.Text then
        dropdown.Text:SetText("")
      end
    end

    sel.Recycle = function(frame)
      frame:Hide()
      frame.setter = nil
      frame.value = nil
      frame.selectedName = nil
      frame.selectedID = nil
      frame.selectedValue = nil
      frame.menuItemDisabled = nil
      frame.menuItemHidden = nil
      frame.values = nil
      if frame.Text then
        frame.Text:SetText("")
      end
      self.dropdowns[frame:GetName()] = nil
      tinsert(self.unusedDropdowns, frame)
    end
  end

  sel.values = values
  sel.setter = options.setter
  sel.menuItemDisabled = options.menuItemDisabled
  sel.menuItemHidden = options.menuItemHidden

  sel:SetupMenu(function(dropdown, rootDescription)
    GUI:ClearEditFocus()
    local list = dropdown:GetValues()
    if not list then
      return
    end
    for _, item in ipairs(list) do
      if not (dropdown.menuItemHidden and dropdown.menuItemHidden(item)) then
        local button = rootDescription:CreateRadio(item.name, function()
          return dropdown.value == item.value
        end, function()
          local oldValue = dropdown.value
          dropdown.value = item.value
          dropdown.selectedValue = item.value
          if dropdown.Text then
            dropdown.Text:SetText(item.name)
          end
          if dropdown.setter then
            dropdown.setter(dropdown, item.value, oldValue)
          end
        end, item.value)

        if dropdown.menuItemDisabled and dropdown.menuItemDisabled(item.value) then
          button:SetEnabled(false)
        end
      end
    end
  end)

  if not sel.EnableDropdown then
    sel.EnableDropdown = function(dropdown)
      dropdown:SetEnabled(true)
      dropdown.isDisabled = false
    end
  end
  if not sel.DisableDropdown then
    sel.DisableDropdown = function(dropdown)
      dropdown:SetEnabled(false)
      dropdown.isDisabled = true
    end
  end

  sel:SetHeight(options.height or 20)
  self:SetDropdownEnabled(sel, true)
  sel:SetValue(options.default)
  if options.width then
    sel:SetWidth(options.width)
  end
  return sel
end

GUI.checkButtons = {}
GUI.unusedCheckButtons = {}
function GUI:CreateCheckButton (parent, text, default, setter, forceNew)
  local btn
  if #self.unusedCheckButtons > 0 and not forceNew then
    btn = tremove (self.unusedCheckButtons)
    btn:SetParent (parent)
    btn:Show ()
    self.checkButtons[btn:GetName()] = btn
  else
    local name = self:GenerateWidgetName ()
    btn = CreateFrame ("CheckButton", name, parent, "UICheckButtonTemplate")
    self.checkButtons[btn:GetName()] = btn
    btn.Recycle = function (btn)
      btn:Hide ()
      btn:SetScript ("OnEnter", nil)
      btn:SetScript ("OnLeave", nil)
      btn:SetScript ("OnClick", nil)
      self.checkButtons[btn:GetName()] = nil
      tinsert (self.unusedCheckButtons, btn)
    end
  end
  btn.Text:SetText(text)
  btn:SetChecked (default)
  if setter then
    btn:SetScript ("OnClick", function (self)
      setter (self:GetChecked ())
    end)
  end
  return btn
end

GUI.imgButtons = {}
GUI.unusedImgButtons = {}
function GUI:CreateImageButton (parent, width, height, img, pus, hlt, disabledTexture, handler)
  local btn
  if #self.unusedImgButtons > 0 then
    btn = tremove (self.unusedImgButtons)
    btn:SetParent (parent)
    btn:Show ()
  else
    local name = self:GenerateWidgetName ()
    btn = CreateFrame ("Button", name, parent)
    self.imgButtons[btn:GetName()] = btn
    btn.Recycle = function (f)
      f:Hide ()
      f:SetScript ("OnEnter", nil)
      f:SetScript ("OnLeave", nil)
      f:SetScript ("OnClick", nil)
      self.imgButtons[f:GetName()] = nil
      tinsert (self.unusedImgButtons, f)
    end
  end
  btn:SetNormalTexture (img)
  btn:SetPushedTexture (pus)
  btn:SetHighlightTexture (hlt or img)
  btn:SetDisabledTexture(disabledTexture or img)
  btn:SetSize(width, height)
  if handler then
    btn:SetScript ("OnClick", handler)
  end
  return btn
end

GUI.panelButtons = {}
GUI.unusedPanelButtons = {}
function GUI:CreatePanelButton(parent, text, handler)
  local btn
  if #self.unusedPanelButtons > 0 then
    btn = tremove(self.unusedPanelButtons)
    btn:SetParent(parent)
    btn:Show()
    self.panelButtons[btn:GetName()] = btn
  else
    local name = self:GenerateWidgetName ()
    btn = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    self.panelButtons[btn:GetName()] = btn
    btn.Recycle = function (f)
      f:SetText("")
      f:Hide ()
      f:SetScript ("OnEnter", nil)
      f:SetScript ("OnLeave", nil)
      f:SetScript ("OnPreClick", nil)
      f:SetScript ("OnClick", nil)
      self.panelButtons[btn:GetName()] = nil
      tinsert (self.unusedPanelButtons, f)
    end
    btn.RenderText = function(f, ...)
      f:SetText(...)
      f:FitToText()
    end
  end
  btn:RenderText(text)
  btn:SetScript("OnClick", handler)
  return btn
end

function GUI:CreateColorPicker (parent, width, height, color, handler)
  local box = CreateFrame ("Frame", nil, parent)
  box:SetSize(width, height)
  box:EnableMouse (true)
  box.texture = box:CreateTexture (nil, "OVERLAY")
  box.texture:SetAllPoints ()
  box.texture:SetColorTexture (unpack (color))
  box.glow = box:CreateTexture (nil, "BACKGROUND")
  box.glow:SetPoint ("TOPLEFT", -2, 2)
  box.glow:SetPoint ("BOTTOMRIGHT", 2, -2)
  box.glow:SetColorTexture (1, 1, 1, 0.3)
  box.glow:Hide ()

  box:SetScript ("OnEnter", function (b) b.glow:Show() end)
  box:SetScript ("OnLeave", function (b) b.glow:Hide() end)
  box:SetScript ("OnMouseDown", function (b)
    local function applyColor(func)
      return function()
        local prevR, prevG, prevB = func(ColorPickerFrame)
        color[1], color[2], color[3] = prevR, prevG, prevB
        b.texture:SetColorTexture(prevR, prevG, prevB)
        if handler then
          handler()
        end
      end
    end
    ColorPickerFrame:SetupColorPickerAndShow({
      r = color[1], g = color[2], b = color[3],
      swatchFunc = applyColor(ColorPickerFrame.GetColorRGB),
      cancelFunc = applyColor(ColorPickerFrame.GetPreviousValues),
    })
  end)

  return box
end

-------------------------------------------------------------------------------

function GUI:CreateHLine (x1, x2, y, w, color, parent)
  parent = parent or self.defaultParent
  local line = parent:CreateTexture (nil, "ARTWORK")
  line:SetDrawLayer ("ARTWORK")
  line:SetColorTexture (unpack(color))
  if x1 > x2 then
    x1, x2 = x2, x1
  end
  line:ClearAllPoints ()
  line:SetTexCoord (0, 0, 0, 1, 1, 0, 1, 1)
  line.width = w
  line:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x1, y - w / 2)
  line:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x2, y + w / 2)
  line:Show ()
  line.SetPos = function (self, x1, x2, y)
    if x1 > x2 then
      x1, x2 = x2, x1
    end
    self:ClearAllPoints ()
    self:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x1, y - self.width / 2)
    self:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x2, y + self.width / 2)
  end
  return line
end

function GUI:CreateVLine (x, y1, y2, w, color, parent)
  parent = parent or self.defaultParent
  local line = parent:CreateTexture (nil, "ARTWORK")
  line:SetDrawLayer ("ARTWORK")
  line:SetColorTexture (unpack(color))
  if y1 > y2 then
    y1, y2 = y2, y1
  end
  line:ClearAllPoints ()
  line:SetTexCoord (1, 0, 0, 0, 1, 1, 0, 1)
  line.width = w
  line:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x - w / 2, y1)
  line:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x + w / 2, y2)
  line:Show ()
  line.SetPos = function (self, x, y1, y2)
    if y1 > y2 then
      y1, y2 = y2, y1
    end
    self:ClearAllPoints ()
    self:SetPoint ("BOTTOMLEFT", parent, "TOPLEFT", x - self.width / 2, y1)
    self:SetPoint ("TOPRIGHT", parent, "TOPLEFT", x + self.width / 2, y2)
  end
  return line
end

--------------------------------------------------------------------------------

function GUI:CreateTable (rows, cols, firstRow, firstColumn, gridColor, parent)
  parent = parent or self.defaultParent
  firstRow = firstRow or 0
  firstColumn = firstColumn or 0

  local t = CreateFrame ("Frame", nil, parent)
  t:ClearAllPoints ()
  t:SetSize(400, 400)
  t:SetPoint ("TOPLEFT")

  t.rows = rows
  t.cols = cols
  t.gridColor = gridColor
  t.autoWidthColumns = {}
  t.rowPos = {}
  t.colPos = {}
  t.rowHeight = {}
  t.colWidth = {}
  t.rowPos[-1] = 0
  t.rowPos[0] = firstRow
  t.colPos[-1] = 0
  t.colPos[0] = firstColumn
  t.rowHeight[0] = firstRow
  t.colWidth[0] = firstColumn

  t.SetRowHeight = function (self, n, h)
    if h then
      if n < 0 or n > self.rows then
        return
      end
      self.rowHeight[n] = h
      if n == 0 and self.hlines then
        self.hlines[-1]:SetShown(h ~= 0)
      end
    else
      for i = 1, self.rows do
        self.rowHeight[i] = n
      end
    end
    self:OnUpdateFix ()
  end
  t.SetColumnWidth = function (self, n, w)
    if w then
      if n < 0 or n > self.cols then
        return
      end
      self.colWidth[n] = w
      if n == 0 and self.vlines then
        self.vlines[-1]:SetShown(w ~= 0)
      end
    else
      for i = 1, self.cols do
        self.colWidth[i] = n
      end
    end
    self:OnUpdateFix ()
  end
  t.SetColumnAutoWidth = function (self, n, enabled)
    if n < 0 or n > self.cols then
      return
    end
    self.autoWidthColumns[n] = enabled
  end
  t.EnableColumnAutoWidth = function (self, ...)
    for _, v in ipairs({...}) do
      self:SetColumnAutoWidth(v, true)
    end
  end
  t.AddRow = function (self, i, n)
    i = i or (self.rows + 1)
    n = n or 1
    local height = ((i == self.rows + 1) and self.rowHeight[i - 1] or self.rowHeight[i])
    for r = self.rows, i, -1 do
      self.cells[r + n] = self.cells[r]
      self.rowHeight[r + n] = self.rowHeight[r]
    end
    for r = i, i + n - 1 do
      self.cells[r] = {}
      self.rowHeight[r] = height
      self.rows = self.rows + 1
      if self.gridColor then
        if self.hlines[self.rows] then
          self.hlines[self.rows]:Show ()
        else
          self.hlines[self.rows] = GUI:CreateHLine (0, 0, 0, 1.5, self.gridColor, self)
        end
      end
    end
    self:OnUpdateFix ()
  end
  t.MoveRow = function (self, i, to)
    local height = self.row[i] - self.rowPos[i - 1]
    local cells = self.cells[i]
    if to > i then
      for r = i + 1, to do
        self.cells[r - 1] = self.cells[r]
        self.rowHeight[r - 1] = self.rowHeight[r]
      end
    elseif to < i then
      for r = i - 1, to, -1 do
        self.cells[r + 1] = self.cells[r]
        self.rowHeight[r + 1] = self.rowHeight[r]
      end
    end
    self.cells[to] = cells
    self.rowHeight[to] = height
    self:OnUpdateFix ()
  end
  t.DeleteRow = function (self, i)
    for j = 0, self.cols do
      if self.cells[i][j] then
        if type (self.cells[i][j].Recycle) == "function" then
          self.cells[i][j]:Recycle ()
        else
          self.cells[i][j]:Hide ()
        end
      end
    end
    for r = i + 1, self.rows do
      self.cells[r - 1] = self.cells[r]
      self.rowHeight[r - 1] = self.rowHeight[r]
    end
    if self.hlines and self.hlines[self.rows] then
      self.hlines[self.rows]:Hide ()
    end
    self.rows = self.rows - 1
    self:OnUpdateFix ()
  end
  t.ClearCells = function (self)
    for i = 0, self.rows do
      for j = 0, self.cols do
        if self.cells[i][j] then
          if type (self.cells[i][j].Recycle) == "function" then
            self.cells[i][j]:Recycle ()
          else
            self.cells[i][j]:Hide ()
          end
        end
      end
      self.cells[i] = {}
    end
  end

  t.GetCellY = function (self, i)
    local n = ceil (i)
    if n < 0 then n = 0 end
    if n > self.rows then n = self.rows end
    return - (self.rowPos[n] + (self.rowPos[n - 1] - self.rowPos[n]) * (n - i))
  end
  t.GetCellX = function (self, j)
    local n = ceil (j)
    if n < 0 then n = 0 end
    if n > self.cols then n = self.cols end
    return self.colPos[n] + (self.colPos[n - 1] - self.colPos[n]) * (n - j)
  end
  t.GetRowHeight = function (self, i)
    return self.rowPos[i] - self.rowPos[i - 1]
  end
  t.GetColumnWidth = function (self, j)
    return self.colPos[j] - self.colPos[j - 1]
  end
  t.AlignCell = function (self, i, j)
    local cell = self.cells[i][j]
    local x = cell.offsX or 0
    local y = cell.offsY or 0
    if cell.align == "FILL" then
      cell:SetPoint ("TOPLEFT", self, "TOPLEFT", self:GetCellX (j - 1) + x, self:GetCellY (i - 1) + y)
      cell:SetPoint ("BOTTOMRIGHT", self, "BOTTOMRIGHT", self:GetCellX (j) + x, self:GetCellY (i) + y)

    elseif cell.align == "TOPLEFT" then
      cell:SetPoint ("TOPLEFT", self, "TOPLEFT", self:GetCellX (j - 1) + 2 + x, self:GetCellY (i - 1) - 2 + y)
    elseif cell.align == "LEFT" then
      cell:SetPoint ("LEFT", self, "TOPLEFT", self:GetCellX (j - 1) + 2 + x, self:GetCellY (i - 0.5) + y)
    elseif cell.align == "BOTTOMLEFT" then
      cell:SetPoint ("BOTTOMLEFT", self, "TOPLEFT", self:GetCellX (j - 1) + 2 + x, self:GetCellY (i) + 2 + y)

    elseif cell.align == "TOP" then
      cell:SetPoint ("TOP", self, "TOPLEFT", self:GetCellX (j - 0.5) + x, self:GetCellY (j - 1) - 2 + y)
    elseif cell.align == "CENTER" then
      cell:SetPoint ("CENTER", self, "TOPLEFT", self:GetCellX (j - 0.5) + x, self:GetCellY (i - 0.5) + y)
    elseif cell.align == "BOTTOM" then
      cell:SetPoint ("BOTTOM", self, "TOPLEFT", self:GetCellX (j - 0.5) + x, self:GetCellY (j) + 2 + y)

    elseif cell.align == "TOPRIGHT" then
      cell:SetPoint ("TOPRIGHT", self, "TOPLEFT", self:GetCellX (j) - 2 + x, self:GetCellY (i - 1) - 2 + y)
    elseif cell.align == "RIGHT" then
      cell:SetPoint ("RIGHT", self, "TOPLEFT", self:GetCellX (j) - 2 + x, self:GetCellY (i - 0.5) + y)
    elseif cell.align == "BOTTOMRIGHT" then
      cell:SetPoint ("BOTTOMRIGHT", self, "TOPLEFT", self:GetCellX (j) - 2 + x, self:GetCellY (i) + 2 + y)
    end
  end
  t.OnUpdateFix = function (self)
    self:SetScript ("OnSizeChanged", nil)

    local numAutoRows = 0
    local totalHeight = 0
    for i = 0, self.rows do
      if self.rowHeight[i] == "AUTO" then
        numAutoRows = numAutoRows + 1
      else
        totalHeight = totalHeight + self.rowHeight[i]
      end
    end
    if numAutoRows == 0 then
      self:SetHeight (totalHeight)
    end
    local remHeight = self:GetHeight () - totalHeight
    for i = 0, self.rows do
      if self.rowHeight[i] == "AUTO" then
        self.rowPos[i] = self.rowPos[i - 1] + remHeight / numAutoRows
      else
        self.rowPos[i] = self.rowPos[i - 1] + self.rowHeight[i]
      end
    end
    local numAutoCols = 0
    local totalWidth = 0
    for i = 0, self.cols do
      if self.colWidth[i] == "AUTO" then
        numAutoCols = numAutoCols + 1
      else
        totalWidth = totalWidth + self.colWidth[i]
      end
    end
    if numAutoCols == 0 then
      self:SetWidth (totalWidth)
    end
    local remWidth = self:GetWidth () - totalWidth
    for i = 0, self.cols do
      if self.colWidth[i] == "AUTO" then
        self.colPos[i] = self.colPos[i - 1] + remWidth / numAutoCols
      else
        self.colPos[i] = self.colPos[i - 1] + self.colWidth[i]
      end
    end

    if self.gridColor then
      for i = -1, self.rows do
        self.hlines[i]:SetPos (0, self.colPos[self.cols], -self.rowPos[i])
      end
      for i = -1, self.cols do
        self.vlines[i]:SetPos (self.colPos[i], 0, -self.rowPos[self.rows])
      end
    end
    for i = -1, self.rows do
      for j = -1, self.cols do
        if self.cells[i][j] then
          self:AlignCell (i, j)
        end
      end
    end

    self:SetScript ("OnSizeChanged", function (self)
      RunNextFrame(function() self:OnUpdateFix() end)
    end)

    if self.onUpdate then
      self.onUpdate ()
    end
  end

  if gridColor then
    t.hlines = {}
    t.vlines = {}
    for i = -1, rows do
      t.hlines[i] = self:CreateHLine (0, 0, 0, 1.5, gridColor, t)
    end
    for i = -1, cols do
      t.vlines[i] = self:CreateVLine (0, 0, 0, 1.5, gridColor, t)
    end
    if firstRow == 0 then
      t.hlines[-1]:Hide ()
    end
    if firstColumn == 0 then
      t.vlines[-1]:Hide ()
    end
  end
  t.cells = {}
  for i = -1, rows do
    t.cells[i] = {}
  end

  for i = 1, t.rows do
    t.rowHeight[i] = "AUTO"
  end
  for j = 1, t.cols do
    t.colWidth[j] = "AUTO"
  end
  t:OnUpdateFix ()

  t:SetScript ("OnSizeChanged", function (self)
    RunNextFrame(function() self:OnUpdateFix() end)
  end)

  t.AutoSizeColumns = function(self, columnIndex)
    local columnsToProcess = {}
    if columnIndex then
      if self.autoWidthColumns[columnIndex] then
        columnsToProcess[columnIndex] = true
      end
    else
      for index, enabled in pairs(self.autoWidthColumns) do
        if enabled then
          columnsToProcess[index] = true
        end
      end
    end

    if not next(columnsToProcess) then
      return
    end

    local maxWidths = {}
    for _, row in pairs(self.cells) do
      for colIndex in pairs(columnsToProcess) do
        local cell = row[colIndex]
        if cell then
          local foundWidth = 0
          if cell.GetStringWidth then
            foundWidth = cell:GetStringWidth()
          elseif cell.GetWidth then
            foundWidth = cell:GetWidth()
          end
          local currentMax = maxWidths[colIndex] or 0
          if foundWidth > currentMax then
            maxWidths[colIndex] = ceil(foundWidth) + 10
          end
        end
      end
    end

    for colIndex, width in pairs(maxWidths) do
      self.colWidth[colIndex] = width
    end
    self:OnUpdateFix()
  end

  t.SetCell = function (self, i, j, value, align, offsX, offsY)
    align = align or "CENTER"
    self.cells[i][j] = value
    self.cells[i][j].align = align
    self.cells[i][j].offsX = offsX
    self.cells[i][j].offsY = offsY
    self:AlignCell (i, j)
    self:AutoSizeColumns(j)
  end
  t.textTagPool = {}
  t.SetCellText = function (self, i, j, text, align, color, font)
    align = align or "CENTER"
    color = color or (addonTable.FONTS and addonTable.FONTS.white) or {1, 1, 1}
    font = font or "GameFontNormalSmall"

    if self.cells[i][j] and not self.cells[i][j].istag then
      if type (self.cells[i][j].Recycle) == "function" then
        self.cells[i][j]:Recycle ()
      else
        self.cells[i][j]:Hide ()
      end
      self.cells[i][j] = nil
    end

    if self.cells[i][j] then
      self.cells[i][j]:SetFontObject (font)
      self.cells[i][j]:Show ()
    elseif #self.textTagPool > 0 then
      self.cells[i][j] = tremove (self.textTagPool)
      self.cells[i][j]:SetFontObject (font)
      self.cells[i][j]:Show ()
    else
      self.cells[i][j] = self:CreateFontString (nil, "OVERLAY", font)
      self.cells[i][j].Recycle = function (tag)
        tag:Hide ()
        tinsert (self.textTagPool, tag)
      end
    end
    self.cells[i][j].istag = true
    local r, g, b
    if type(color) == "table" then
      if type(color.GetRGB) == "function" then
        r, g, b = color:GetRGB()
      elseif color.r and color.g and color.b then
        r, g, b = color.r, color.g, color.b
      else
        r, g, b = unpack(color)
      end
    elseif type(color) == "userdata" and type(color.GetRGB) == "function" then
      r, g, b = color:GetRGB()
    end
    if not r then
      r, g, b = 1, 1, 1
    end
    self.cells[i][j]:SetTextColor (r, g, b)
    self.cells[i][j]:SetText (text)
    self.cells[i][j].align = align
    self:AlignCell (i, j)
    self:AutoSizeColumns(j)
  end

  return t
end

function GUI.CreateStaticPopup(name, text, options, legacyOpts)
  local onAccept
  local opts
  if type(options) == "function" then
    onAccept = options
    opts = legacyOpts or {}
  else
    opts = options or {}
    onAccept = opts.func or opts.OnAccept
  end

  if type(onAccept) ~= "function" then
    error("GUI.CreateStaticPopup requires an onAccept function")
  end

  local hasEditBox = opts.hasEditBox
  if hasEditBox == nil then
    hasEditBox = true
  end

  StaticPopupDialogs[name] = {
    text = text,
    button1 = opts.button1 or ACCEPT,
    button2 = opts.button2 or CANCEL,
    hasEditBox = hasEditBox,
    editBoxWidth = opts.editBoxWidth or 350,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(self)
      if hasEditBox then
        onAccept(self:GetEditBox():GetText(), self)
      else
        onAccept(self)
      end
    end,
    OnShow = function(self)
      local editBox = self:GetEditBox()
      if editBox and hasEditBox then
        editBox:SetText("")
        editBox:SetFocus()
        self:GetButton1():Disable()
      else
        self:GetButton1():Enable()
      end
      self:GetButton2():Enable()
    end,
    OnHide = function(self)
      ChatEdit_FocusActiveWindow()
      local editBox = self:GetEditBox()
      if editBox then
        editBox:SetText("")
      end
    end,
    EditBoxOnEnterPressed = function(editBox)
      local parent = editBox:GetParent()
      if parent:GetButton1():IsEnabled() then
        onAccept(editBox:GetText(), parent)
        parent:Hide()
      end
    end,
    EditBoxOnTextChanged = function(editBox)
      local parent = editBox:GetParent()
      parent:GetButton1():SetEnabled(editBox:GetText() ~= "")
    end,
    EditBoxOnEscapePressed = function(editBox)
      editBox:GetParent():Hide()
    end,
  }
end

addonTable.GUI = GUI
