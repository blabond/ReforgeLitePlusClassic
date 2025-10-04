-- The Dragonflight+ client removed GetLootMethod in favor of C_PartyInfo. Some
-- classic-era addons (including Shadowed Unit Frames) still expect the legacy
-- helper to exist, so provide a thin shim that emulates the historic return
-- values when the game client no longer offers the function.
if type(GetLootMethod) ~= "function" and C_PartyInfo and C_PartyInfo.GetLootMethod then
  local lootMethodEnumToString
  if Enum and Enum.LootMethod then
    lootMethodEnumToString = {}
    local enum = Enum.LootMethod
    local function assign(enumKey, legacyValue)
      if enum[enumKey] then
        lootMethodEnumToString[enum[enumKey]] = legacyValue
      end
    end

    assign("FreeForAll", "freeforall")
    assign("RoundRobin", "roundrobin")
    assign("Master", "master")
    assign("GroupLoot", "group")
    assign("Group", "group")
    assign("NeedBeforeGreed", "needbeforegreed")
    assign("Personal", "personalloot")
    assign("PersonalLoot", "personalloot")

    for key, value in pairs(enum) do
      if type(value) == "number" and lootMethodEnumToString[value] == nil and type(key) == "string" then
        local normalized = key:gsub("(%u)", " %1"):lower():gsub("[%s_]+", "")
        lootMethodEnumToString[value] = normalized
      end
    end
  end

  local function NormalizeLootMethod(method)
    if type(method) == "string" then
      return method:lower()
    end
    if lootMethodEnumToString and lootMethodEnumToString[method] then
      return lootMethodEnumToString[method]
    end
    return method
  end

  local function NormalizeLootMasterUnit(unit)
    if unit == nil then
      return nil, nil
    end

    if unit == "player" then
      return 0, nil
    end

    local partyIndex = unit:match("^party(%d+)$")
    if partyIndex then
      return tonumber(partyIndex), nil
    end

    local raidIndex = unit:match("^raid(%d+)$")
    if raidIndex then
      return nil, tonumber(raidIndex)
    end

    return nil, nil
  end

  function GetLootMethod()
    local lootMethod = C_PartyInfo.GetLootMethod()
    if lootMethod == nil then
      return nil
    end

    local masterUnit
    if C_PartyInfo.GetLootMasterUnit then
      masterUnit = C_PartyInfo.GetLootMasterUnit()
    end

    local partyIndex, raidIndex = NormalizeLootMasterUnit(masterUnit)
    return NormalizeLootMethod(lootMethod), partyIndex, raidIndex
  end
end

local addonName, addonTable = ...
local addonTitle = C_AddOns.GetAddOnMetadata(addonName, "title")

local ReforgeLite = CreateFrame("Frame", addonName, UIParent, "BackdropTemplate")
addonTable.ReforgeLite = ReforgeLite
ReforgeLite.computeInProgress = false
ReforgeLite.methodAlternatives = nil
ReforgeLite.allMethodAlternatives = nil
ReforgeLite.selectedMethodAlternative = nil

local L = addonTable.L
local GUI = addonTable.GUI
addonTable.MAX_LOOPS = 200000
local MIN_LOOPS = 10000
addonTable.MAX_METHOD_ALTERNATIVES = 5
addonTable.CORE_SPEED_PRESET_MULTIPLIERS = {
  extra_fast = 0.45,
  fast = 0.65,
  normal = 1,
}
addonTable.CORE_SPEED_PRESET = addonTable.CORE_SPEED_PRESET or "fast"

local DeepCopy = addonTable.DeepCopy
local GetItemStats = addonTable.GetItemStatsUp

addonTable.printLog = {}
local gprint = print
local function print(...)
    local message = strjoin(" ", date("[%X]:"), tostringall(...))
    tinsert(addonTable.printLog, message)
    gprint("|cff33ff99"..addonName.."|r:", ...)
end
addonTable.print = print

if type(ReforgePlusLiteClassicDB) ~= "table" and type(ReforgeLiteLiteDB) == "table" then
  ReforgePlusLiteClassicDB = ReforgeLiteLiteDB
end
ReforgeLiteLiteDB = nil

local ITEM_SIZE = 24

local NUM_CAPS = 3
addonTable.NUM_CAPS = NUM_CAPS

local ITEM_SLOTS = {
  "HEADSLOT",
  "NECKSLOT",
  "SHOULDERSLOT",
  "BACKSLOT",
  "CHESTSLOT",
  "WRISTSLOT",
  "HANDSSLOT",
  "WAISTSLOT",
  "LEGSSLOT",
  "FEETSLOT",
  "FINGER0SLOT",
  "FINGER1SLOT",
  "TRINKET0SLOT",
  "TRINKET1SLOT",
  "MAINHANDSLOT",
  "SECONDARYHANDSLOT",
}
local ITEM_SLOT_COUNT = #ITEM_SLOTS

local abs = math.abs
local floor = math.floor
local max = math.max

local METHOD_ALTERNATIVE_BUTTON_HEIGHT = 32
local METHOD_ALTERNATIVE_BUTTON_SPACING = 6

local function CreateDefaultCap()
  return {
    stat = 0,
    points = {
      {
        method = 1,
        value = 0,
        after = 0,
        preset = 1
      }
    }
  }
end

local function CreateDefaultCaps()
  local caps = {}
  for i = 1, NUM_CAPS do
    caps[i] = CreateDefaultCap()
  end
  return caps
end

function ReforgeLite:SetCoreSpeedPreset(preset)
  if addonTable.CORE_SPEED_PRESET_MULTIPLIERS[preset] == nil then
    preset = "fast"
  end
  if self.db then
    self.db.coreSpeedPreset = preset
  end
  addonTable.CORE_SPEED_PRESET = preset
end

local DefaultDB = {
  global = {
    windowLocation = false,
    methodWindowLocation = false,
    openOnReforge = true,
    updateTooltip = false,
    speed = addonTable.MAX_LOOPS * 0.8,
    coreSpeedPreset = "fast",
    activeWindowTitle = {0.6, 0, 0},
    inactiveWindowTitle = {0.5, 0.5, 0.5},
    specProfiles = false,
    importButton = true,
    showHelp = true,
  },
  char = {
    windowWidth = 720,
    windowHeight = 564,
    targetLevel = 3,
    ilvlCap = 0,
    meleeHaste = true,
    spellHaste = true,
    mastery = false,
    weights = {0, 0, 0, 0, 0, 0, 0, 0},
    caps = CreateDefaultCaps(),
    methodOrigin = addonName,
    itemsLocked = {},
    categoryStates = { [SETTINGS] = false },
  },
  class = {
    customPresets = {}
  },
}

local RFL_FRAMES = { ReforgeLite }
function RFL_FRAMES:CloseAll()
  for _, frame in ipairs(self) do
    frame:Hide()
  end
end

local function ReforgeFrameIsVisible()
  return ReforgingFrame and ReforgingFrame:IsShown()
end

addonTable.localeClass, addonTable.playerClass, addonTable.playerClassID = UnitClass("player")
addonTable.playerRace = select(2, UnitRace("player"))

ReforgeLite.itemSlots = ITEM_SLOTS
local PLAYER_ITEM_DATA = setmetatable({}, {
  __index = function(t, k)
    if type(k) == "number" and k >= INVSLOT_FIRST_EQUIPPED and k <= INVSLOT_LAST_EQUIPPED then
      rawset(t, k, Item:CreateFromEquipmentSlot(k))
      return t[k]
    elseif tContains(ITEM_SLOTS, k) then
      local slotId = GetInventorySlotInfo(k)
      rawset(t, k, t[slotId])
      return t[slotId]
    end
  end
})
addonTable.playerData = PLAYER_ITEM_DATA

local UNFORGE_INDEX = -1
addonTable.StatCapMethods = EnumUtil.MakeEnum("AtLeast", "AtMost", "NewValue", "Exactly")

function ReforgeLite:UpgradeDB()
  local db = ReforgePlusLiteClassicDB
  if not db then return end
  if db.classProfiles then
    db.class = DeepCopy(db.classProfiles)
    db.classProfiles = nil
  end
  if db.profiles then
    db.char = DeepCopy(db.profiles)
    db.profiles = nil
  end
  if not db.global then
    db.global = {}
    for k, v in pairs(db) do
      local default = DefaultDB.global[k]
      if default ~= nil then
        if default ~= v then
          db.global[k] = DeepCopy(v)
        end
        db[k] = nil
      end
    end
  end

  if db.global then
    local width, height = db.global.windowWidth, db.global.windowHeight
    if width or height then
      db.char = db.char or {}
      for _, profile in pairs(db.char) do
        if type(profile) == "table" then
          if width and profile.windowWidth == nil then
            profile.windowWidth = width
          end
          if height and profile.windowHeight == nil then
            profile.windowHeight = height
          end
        end
      end
      db.global.windowWidth = nil
      db.global.windowHeight = nil
    end
  end

end

-----------------------------------------------------------------

GUI.CreateStaticPopup("REFORGE_LITE_SAVE_PRESET", L["Enter the preset name"], function(text)
  ReforgeLite.cdb.customPresets[text] = {
    caps = DeepCopy(ReforgeLite.pdb.caps),
    weights = DeepCopy(ReforgeLite.pdb.weights)
  }
  ReforgeLite:InitCustomPresets()
  if ReforgeLite.RefreshPresetMenu then
    ReforgeLite:RefreshPresetMenu()
  elseif ReforgeLite.presetMenuGenerator and ReforgeLite.presetsButton then
    ReforgeLite.presetsButton:SetupMenu(ReforgeLite.presetMenuGenerator)
  end
end)

local ignoredSlots = { [INVSLOT_TABARD] = true, [INVSLOT_BODY] = true }

local statIds = EnumUtil.MakeEnum("SPIRIT", "DODGE", "PARRY", "HIT", "CRIT", "HASTE", "EXP", "MASTERY", "SPELLHIT")
addonTable.statIds = statIds
ReforgeLite.STATS = statIds

local FIRE_SPIRIT = 4
local function GetFireSpirit()
  local s2h = (ReforgeLite.conversion[statIds.SPIRIT] or {})[statIds.HIT]
  if s2h and C_UnitAuras.GetPlayerAuraBySpellID(7353) then
    return floor(FIRE_SPIRIT * s2h)
  end
  return 0
end

local CR_HIT, CR_CRIT, CR_HASTE = CR_HIT_SPELL, CR_CRIT_SPELL, CR_HASTE_SPELL
if addonTable.playerClass == "HUNTER" then
  CR_HIT, CR_CRIT, CR_HASTE = CR_HIT_RANGED, CR_CRIT_RANGED, CR_HASTE_RANGED
end

local StatAdditives = {
  [CR_HIT] = function(rating)
    return rating - GetFireSpirit()
  end,
  [CR_MASTERY] = function(rating)
    if ReforgeLite.pdb.mastery and not ReforgeLite:PlayerHasMasteryBuff() then
      rating = rating + (addonTable.MASTERY_BY_LEVEL[UnitLevel("player")] or 0)
    end
    return rating
  end,
}

local function RatingStat (i, name_, tip_, long_, id_)
  return {
    name = name_,
    tip = tip_,
    long = long_,
    getter = function ()
      local rating = GetCombatRating(id_)
      if StatAdditives[id_] then
        rating = StatAdditives[id_](rating)
      end
      return rating
    end,
    mgetter = function (method, orig)
      return (orig and method.orig_stats and method.orig_stats[i]) or method.stats[i]
    end
  }
end

ReforgeLite.itemStats = {
    {
      name = "ITEM_MOD_SPIRIT_SHORT",
      tip = SPELL_STAT5_NAME,
      long = ITEM_MOD_SPIRIT_SHORT,
      getter = function ()
        local _, spirit = UnitStat("player", LE_UNIT_STAT_SPIRIT)
        if GetFireSpirit() ~= 0 then
          spirit = spirit - FIRE_SPIRIT
        end
        return spirit
      end,
      mgetter = function (method, orig)
        return (orig and method.orig_stats and method.orig_stats[statIds.SPIRIT]) or method.stats[statIds.SPIRIT]
      end
    },
    RatingStat (statIds.DODGE,   "ITEM_MOD_DODGE_RATING",         STAT_DODGE,     STAT_DODGE,           CR_DODGE),
    RatingStat (statIds.PARRY,   "ITEM_MOD_PARRY_RATING",         STAT_PARRY,     STAT_PARRY,           CR_PARRY),
    --RatingStat (statIds.HIT,     "ITEM_MOD_HIT_RATING",           HIT,            HIT,                  CR_HIT),
    {
      name = "ITEM_MOD_HIT_RATING",
      tip = HIT,
      long = HIT,
      getter = function()
        local hit = GetCombatRating(CR_HIT)
        if (ReforgeLite.conversion[statIds.EXP] or {})[statIds.HIT] then
          hit = hit + (GetCombatRating(CR_EXPERTISE) * ReforgeLite.conversion[statIds.EXP][statIds.HIT])
        end
        return hit
      end,
      mgetter = function (method, orig)
        return (orig and method.orig_stats and method.orig_stats[statIds.HIT]) or method.stats[statIds.HIT]
      end
    },
    RatingStat (statIds.CRIT,    "ITEM_MOD_CRIT_RATING",          CRIT_ABBR,      CRIT_ABBR,            CR_CRIT),
    RatingStat (statIds.HASTE,   "ITEM_MOD_HASTE_RATING",         STAT_HASTE,     STAT_HASTE,           CR_HASTE),
    RatingStat (statIds.EXP,     "ITEM_MOD_EXPERTISE_RATING",     EXPERTISE_ABBR, STAT_EXPERTISE,       CR_EXPERTISE),
    RatingStat (statIds.MASTERY, "ITEM_MOD_MASTERY_RATING_SHORT", STAT_MASTERY,   STAT_MASTERY,         CR_MASTERY),
}

local REFORGE_TABLE_BASE = 112
local reforgeTable = {
  {statIds.SPIRIT, statIds.DODGE}, {statIds.SPIRIT, statIds.PARRY}, {statIds.SPIRIT, statIds.HIT}, {statIds.SPIRIT, statIds.CRIT}, {statIds.SPIRIT, statIds.HASTE}, {statIds.SPIRIT, statIds.EXP}, {statIds.SPIRIT, statIds.MASTERY},
  {statIds.DODGE, statIds.SPIRIT}, {statIds.DODGE, statIds.PARRY}, {statIds.DODGE, statIds.HIT}, {statIds.DODGE, statIds.CRIT}, {statIds.DODGE, statIds.HASTE}, {statIds.DODGE, statIds.EXP}, {statIds.DODGE, statIds.MASTERY},
  {statIds.PARRY, statIds.SPIRIT}, {statIds.PARRY, statIds.DODGE}, {statIds.PARRY, statIds.HIT}, {statIds.PARRY, statIds.CRIT}, {statIds.PARRY, statIds.HASTE}, {statIds.PARRY, statIds.EXP}, {statIds.PARRY, statIds.MASTERY},
  {statIds.HIT, statIds.SPIRIT}, {statIds.HIT, statIds.DODGE}, {statIds.HIT, statIds.PARRY}, {statIds.HIT, statIds.CRIT}, {statIds.HIT, statIds.HASTE}, {statIds.HIT, statIds.EXP}, {statIds.HIT, statIds.MASTERY},
  {statIds.CRIT, statIds.SPIRIT}, {statIds.CRIT, statIds.DODGE}, {statIds.CRIT, statIds.PARRY}, {statIds.CRIT, statIds.HIT}, {statIds.CRIT, statIds.HASTE}, {statIds.CRIT, statIds.EXP}, {statIds.CRIT, statIds.MASTERY},
  {statIds.HASTE, statIds.SPIRIT}, {statIds.HASTE, statIds.DODGE}, {statIds.HASTE, statIds.PARRY}, {statIds.HASTE, statIds.HIT}, {statIds.HASTE, statIds.CRIT}, {statIds.HASTE, statIds.EXP}, {statIds.HASTE, statIds.MASTERY},
  {statIds.EXP, statIds.SPIRIT}, {statIds.EXP, statIds.DODGE}, {statIds.EXP, statIds.PARRY}, {statIds.EXP, statIds.HIT}, {statIds.EXP, statIds.CRIT}, {statIds.EXP, statIds.HASTE}, {statIds.EXP, statIds.MASTERY},
  {statIds.MASTERY, statIds.SPIRIT}, {statIds.MASTERY, statIds.DODGE}, {statIds.MASTERY, statIds.PARRY}, {statIds.MASTERY, statIds.HIT}, {statIds.MASTERY, statIds.CRIT}, {statIds.MASTERY, statIds.HASTE}, {statIds.MASTERY, statIds.EXP},
}
ReforgeLite.reforgeTable = reforgeTable

addonTable.REFORGE_COEFF = 0.4

function ReforgeLite:UpdateWindowSize ()
  if not self.pdb then
    return
  end
  self.pdb.windowWidth = self:GetWidth ()
  self.pdb.windowHeight = self:GetHeight ()
end

function ReforgeLite:GetCapScore (cap, value)
  local score = 0
  for i = #cap.points, 1, -1 do
    if value > cap.points[i].value then
      score = score + cap.points[i].after * (value - cap.points[i].value)
      value = cap.points[i].value
    end
  end
  score = score + self.pdb.weights[cap.stat] * value
  return score
end

function ReforgeLite:GetStatScore (stat, value)
  for i = 1, NUM_CAPS do
    local cap = self.pdb.caps[i]
    if cap and stat == cap.stat then
      return self:GetCapScore (cap, value)
    end
  end
  return self.pdb.weights[stat] * value
end

addonTable.WoWSimsOriginTag = "WoWSims"

local function IsItemSwapped(slot, wowsims)
  local SWAPPABLE_SLOTS = {
    [INVSLOT_FINGER1] = INVSLOT_FINGER2,
    [INVSLOT_FINGER2] = INVSLOT_FINGER1,
    [INVSLOT_TRINKET1] = INVSLOT_TRINKET2,
    [INVSLOT_TRINKET2] = INVSLOT_TRINKET1,
  }
  local slotName = ReforgeLite.itemSlots[slot]
  if not slotName then return end
  local oppositeSlotId = SWAPPABLE_SLOTS[GetInventorySlotInfo(slotName)]
  if not oppositeSlotId then return end
  local slotItemId = (wowsims.player.equipment.items[slot] or {}).id or 0
  local oppositeSlotItemId = (wowsims.player.equipment.items[oppositeSlotId] or {}).id or 0
  if C_Item.IsEquippedItem(slotItemId) and C_Item.IsEquippedItem(oppositeSlotItemId) then
    return oppositeSlotId
  end
end

function ReforgeLite:ValidateWoWSimsString(importStr)
  local success, wowsims = pcall(function () return C_EncodingUtil.DeserializeJSON(importStr) end)
  if not success or type(wowsims) ~= "table" then return false, wowsims end
  if not (wowsims.player or {}).equipment then
    return false, L['This import is missing player equipment data! Please make sure "Gear" is selected when exporting from WoWSims.']
  end
  local newItems = DeepCopy((self.pdb.method or self:InitializeMethod()).items)
  for slot, item in ipairs(newItems) do
    local simItemInfo = wowsims.player.equipment.items[slot] or {}
    local equippedItemInfo = self.itemData[slot]
    if simItemInfo.id ~= equippedItemInfo.itemId then
      local swappedSlotId = IsItemSwapped(slot, wowsims)
      if swappedSlotId then
        simItemInfo = wowsims.player.equipment.items[swappedSlotId] or {}
      else
        return false, { itemId = simItemInfo.id, slot = slot }
      end
    end
    if simItemInfo.reforging then
      item.src, item.dst = unpack(self.reforgeTable[simItemInfo.reforging - REFORGE_TABLE_BASE])
    else
      item.src, item.dst = nil, nil
    end
  end
  return true, newItems
end

function ReforgeLite:ApplyWoWSimsImport(newItems, attachToReforge)
  if not self.pdb.method then
    self.pdb.method = { items = {} }
  end
  self.pdb.method.items = newItems
  self.pdb.methodOrigin = addonTable.WoWSimsOriginTag
  self:FinalizeReforge({ method = self.pdb.method })
  self:SetMethodAlternatives({ self.pdb.method }, 1)
  self:UpdateMethodCategory()
  self:ShowMethodWindow(attachToReforge)
end

--[===[@debug@
function ReforgeLite:ParsePresetString(presetStr)
  local success, preset = pcall(function () return C_EncodingUtil.DeserializeJSON(presetStr) end)
  if success and type(preset.caps) == "table" then
    DevTools_Dump(preset)
  end
end
--@end-debug@]===]

function ReforgeLite:ValidatePawnString(importStr)
  local pos, _, version, name, values = strfind (importStr, "^%s*%(%s*Pawn%s*:%s*v(%d+)%s*:%s*\"([^\"]+)\"%s*:%s*(.+)%s*%)%s*$")
  version = tonumber (version)
  if version and version > 1 then return false end
  if not (pos and version and name and values) or name == "" or values == "" then
    return false
  end
  return true, values
end

function ReforgeLite:ParsePawnString(values)
  local raw = {}
  local average = 0
  local total = 0
  gsub (values .. ",", "[^,]*,", function (pair)
    local pos, _, stat, value = strfind (pair, "^%s*([%a%d]+)%s*=%s*(%-?[%d%.]+)%s*,$")
    value = tonumber (value)
    if pos and stat and stat ~= "" and value then
      raw[stat] = value
      average = average + value
      total = total + 1
    end
  end)
  local factor = 1
  if average / total < 10 then
    factor = 100
  end
  for k, v in pairs (raw) do
    raw[k] = Round(v * factor)
  end

  self:SetStatWeights ({
    raw["Spirit"] or 0,
    raw["DodgeRating"] or 0,
    raw["ParryRating"] or 0,
    raw["HitRating"] or 0,
    raw["CritRating"] or 0,
    raw["HasteRating"] or 0,
    raw["ExpertiseRating"] or 0,
    raw["MasteryRating"] or 0
  })
end

local orderIds = {}
local function getOrderId(section, grid)
  orderIds[section] = (orderIds[section] or 0) + 1
  if grid then
    while grid.rows < orderIds[section] do
      grid:AddRow()
    end
    if not grid.cells[orderIds[section]] then
      grid.cells[orderIds[section]] = {}
    end
  end
  return orderIds[section]
end

------------------------------------------------------------------------

function ReforgeLite:CreateCategory (name)
  local c = CreateFrame ("Frame", nil, self.content)
  c:ClearAllPoints ()
  c:SetSize(16,16)
  c.expanded = self.pdb.categoryStates[name] ~= false
  c.name = c:CreateFontString (nil, "OVERLAY", "GameFontNormal")
  c.catname = c.name
  c.name:SetPoint ("TOPLEFT", c, "TOPLEFT", 18, -1)
  c.name:SetTextColor (1, 1, 1)
  c.name:SetText (name)

  c.button = CreateFrame ("Button", nil, c)
  c.button:ClearAllPoints ()
  c.button:SetSize (14,14)
  c.button:SetPoint ("TOPLEFT")
  c.button:SetHighlightTexture ("Interface\\Buttons\\UI-PlusButton-Hilight")
  c.button.UpdateTexture = function (self)
    if self:GetParent ().expanded then
      self:SetNormalTexture ("Interface\\Buttons\\UI-MinusButton-Up")
      self:SetPushedTexture ("Interface\\Buttons\\UI-MinusButton-Down")
    else
      self:SetNormalTexture ("Interface\\Buttons\\UI-PlusButton-Up")
      self:SetPushedTexture ("Interface\\Buttons\\UI-PlusButton-Down")
    end
  end
  c.button:UpdateTexture ()
  c.button:SetScript ("OnClick", function (btn) btn:GetParent():Toggle() end)
  c.button.anchor = {point = "TOPLEFT", rel = c, relPoint = "TOPLEFT", x = 0, y = 0}

  c.frames = {}
  c.anchors = {}
  c.AddFrame = function (cat, frame)
    tinsert (cat.frames, frame)
    frame.Show2 = function (f)
      if f.category.expanded then
        f:Show ()
      end
      f.chidden = nil
    end
    frame.Hide2 = function (f)
      f:Hide ()
      f.chidden = true
    end
    frame.category = cat
    if not cat.expanded then
      frame:Hide()
    end
  end

  c.Toggle = function (category)
    category.expanded = not category.expanded
    self.pdb.categoryStates[name] = category.expanded
    if c.expanded then
      for k, v in pairs (category.frames) do
        if not v.chidden then
          v:Show ()
        end
      end
      for k, v in pairs (category.anchors) do
        v.frame:SetPoint (v.point, v.rel, v.relPoint, v.x, v.y)
      end
    else
      for k, v in pairs (category.frames) do
        v:Hide ()
      end
      for k, v in pairs (category.anchors) do
        v.frame:SetPoint (v.point, category.button, v.relPoint, v.x, v.y)
      end
    end
    category.button:UpdateTexture ()
    self:UpdateContentSize ()
  end

  return c
end

function ReforgeLite:SetAnchor (frame_, point_, rel_, relPoint_, offsX, offsY)
  if rel_ and rel_.catname and rel_.button then
    rel_ = rel_.button
  end
  if rel_.category then
    tinsert (rel_.category.anchors, {frame = frame_, point = point_, rel = rel_, relPoint = relPoint_, x = offsX, y = offsY})
    if rel_.category.expanded then
      frame_:SetPoint (point_, rel_, relPoint_, offsX, offsY)
    else
      frame_:SetPoint (point_, rel_.category.button, relPoint_, offsX, offsY)
    end
  else
    frame_:SetPoint (point_, rel_, relPoint_, offsX, offsY)
  end
  frame_.anchor = {point = point_, rel = rel_, relPoint = relPoint_, x = offsX, y = offsY}
end
function ReforgeLite:GetFrameY (frame)
  local cur = frame
  local offs = 0
  while cur and cur ~= self.content do
    if cur.anchor == nil then
      return offs
    end
    if cur.anchor.point:find ("BOTTOM") then
      offs = offs + cur:GetHeight ()
    end
    local rel = cur.anchor.rel
    if rel.category and not rel.category.expanded then
      rel = rel.category.button
    end
    if cur.anchor.relPoint:find ("BOTTOM") then
      offs = offs - rel:GetHeight ()
    end
    offs = offs + cur.anchor.y
    cur = rel
  end
  return offs
end

local function SetTextDelta (text, value, cur, override)
  override = override or (value - cur)
  if override == 0 then
    text:SetTextColor (0.7, 0.7, 0.7)
  elseif override > 0 then
    text:SetTextColor (0.6, 1, 0.6)
  else
    text:SetTextColor (1, 0.4, 0.4)
  end
  text:SetFormattedText(value - cur >= 0 and "+%s" or "%s", value - cur)
end

------------------------------------------------------------------------

function ReforgeLite:SetScroll (value)
  local viewheight = self.scrollFrame:GetHeight ()
  local height = self.content:GetHeight ()
  local offset

  if viewheight > height then
    offset = 0
  else
    offset = floor ((height - viewheight) / 1000 * value)
  end
  self.content:ClearAllPoints ()
  self.content:SetPoint ("TOPLEFT", 0, offset)
  self.content:SetPoint ("TOPRIGHT", 0, offset)
  self.scrollOffset = offset
  self.scrollValue = value
end

function ReforgeLite:FixScroll ()
  local offset = self.scrollOffset
  local viewheight = self.scrollFrame:GetHeight ()
  local height = self.content:GetHeight ()
  if height < viewheight + 2 then
    if self.scrollBarShown then
      self.scrollBarShown = false
      self.scrollBar:Hide ()
      self.scrollBar:SetValue (0)
    end
  else
    if not self.scrollBarShown then
      self.scrollBarShown = true
      self.scrollBar:Show ()
    end
    local value = (offset / (height - viewheight) * 1000)
    if value > 1000 then value = 1000 end
    self.scrollBar:SetValue (value)
    self:SetScroll (value)
    if value < 1000 then
      self.content:ClearAllPoints ()
      self.content:SetPoint ("TOPLEFT", 0, offset)
      self.content:SetPoint ("TOPRIGHT", 0, offset)
    end
  end
end

function ReforgeLite:SetNewTopWindow(newTopWindow)
  if not RFL_FRAMES[2] then return end
  newTopWindow = newTopWindow or self
  for _, frame in ipairs(RFL_FRAMES) do
    if frame == newTopWindow then
      frame:Raise()
      frame:SetFrameActive(true)
    else
      frame:Lower()
      frame:SetFrameActive(false)
    end
  end
end

function ReforgeLite:CreateFrame()
  self:InitPresets()
  self:SetFrameStrata ("DIALOG")
  self:SetToplevel(true)
  self:ClearAllPoints ()
  local windowWidth = (self.pdb and self.pdb.windowWidth) or (self.db and self.db.windowWidth) or DefaultDB.char.windowWidth
  local windowHeight = (self.pdb and self.pdb.windowHeight) or (self.db and self.db.windowHeight) or DefaultDB.char.windowHeight
  if self.pdb then
    self.pdb.windowWidth = windowWidth
    self.pdb.windowHeight = windowHeight
  end
  self:SetSize(windowWidth, windowHeight)
  self:SetResizeBounds(680, 500, 1000, 800)
  if self.db.windowLocation then
    self:SetPoint (SafeUnpack(self.db.windowLocation))
  else
    self:SetPoint ("CENTER")
  end
  self.backdropInfo = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 3, right = 3, top = 22, bottom = 3 }
  }
  self:ApplyBackdrop()
  self:SetBackdropBorderColor (0.1,0.1,0.1)
  self:SetBackdropColor (0.1, 0.1, 0.1)

  self.titlebar = self:CreateTexture(nil,"BACKGROUND")
  self.titlebar:SetPoint("TOPLEFT", 3, -3)
  self.titlebar:SetPoint("TOPRIGHT", -3, 3)
  self.titlebar:SetHeight(20)
  self.SetFrameActive = function(frame, active)
    if active then
      frame.titlebar:SetColorTexture(unpack (self.db.activeWindowTitle))
    else
      frame.titlebar:SetColorTexture(unpack (self.db.inactiveWindowTitle))
    end
  end
  self:SetFrameActive(true)

  self:EnableMouse (true)
  self:SetMovable (true)
  self:SetResizable (true)
  self:SetScript ("OnMouseDown", function (self, arg)
    self:SetNewTopWindow()
    if arg == "LeftButton" then
      self:StartMoving ()
      self.moving = true
    end
  end)
  self:SetScript ("OnMouseUp", function (self)
    if self.moving then
      self:StopMovingOrSizing ()
      self.moving = false
      self.db.windowLocation = SafePack(self:GetPoint())
    end
  end)
  tinsert(UISpecialFrames, self:GetName()) -- allow closing with escape

  self.titleIcon = CreateFrame("Frame", nil, self)
  self.titleIcon:SetSize(16, 16)
  self.titleIcon:SetPoint ("TOPLEFT", 12, floor(self.titleIcon:GetHeight())-floor(self.titlebar:GetHeight()))

  self.titleIcon.texture = self.titleIcon:CreateTexture("ARTWORK")
  self.titleIcon.texture:SetAllPoints(self.titleIcon)
  self.titleIcon.texture:SetTexture([[Interface\Reforging\Reforge-Portrait]])


  self.title = self:CreateFontString (nil, "OVERLAY", "GameFontNormal")
  self.title:SetText (addonTitle)
  self.title:SetTextColor (1, 1, 1)
  self.title:SetPoint ("BOTTOMLEFT", self.titleIcon, "BOTTOMRIGHT", 2, 1)

  self.close = CreateFrame ("Button", nil, self, "UIPanelCloseButtonNoScripts")
  self.close:SetSize(28, 28)
  self.close:SetPoint("TOPRIGHT")
  self.close:SetScript("OnClick", function(btn) btn:GetParent():Hide() end)

  local function GripOnMouseDown(btn, arg)
    if arg == "LeftButton" then
      local anchorPoint = btn:GetPoint()
      btn:GetParent():StartSizing(anchorPoint)
      btn:GetParent().sizing = true
    end
  end

  local function GripOnMouseUp(btn, arg)
    if btn:GetParent().sizing then
      btn:GetParent():StopMovingOrSizing ()
      btn:GetParent().sizing = false
      btn:GetParent():UpdateWindowSize ()
    end
  end

  self.leftGrip = CreateFrame ("Button", nil, self, "PanelResizeButtonTemplate")
  self.leftGrip:SetSize(16, 16)
  self.leftGrip:SetRotationDegrees(-90)
  self.leftGrip:SetPoint("BOTTOMLEFT")
  self.leftGrip:SetScript("OnMouseDown", GripOnMouseDown)
  self.leftGrip:SetScript("OnMouseUp", GripOnMouseUp)

  self.rightGrip = CreateFrame ("Button", nil, self, "PanelResizeButtonTemplate")
  self.rightGrip:SetSize(16, 16)
  self.rightGrip:SetPoint("BOTTOMRIGHT")
  self.rightGrip:SetScript("OnMouseDown", GripOnMouseDown)
  self.rightGrip:SetScript("OnMouseUp", GripOnMouseUp)

  self:CreateItemTable ()

  self.scrollValue = 0
  self.scrollOffset = 0
  self.scrollBarShown = false

  self.scrollFrame = CreateFrame ("ScrollFrame", nil, self)
  self.scrollFrame:ClearAllPoints ()
  self.scrollFrame:SetPoint ("LEFT", self.itemTable, "RIGHT", 10, 0)
  self.scrollFrame:SetPoint ("TOP", 0, -28)
  self.scrollFrame:SetPoint ("BOTTOMRIGHT", -22, 15)
  self.scrollFrame:EnableMouseWheel (true)
  self.scrollFrame:SetScript ("OnMouseWheel", function (frame, value)
    if self.scrollBarShown then
      local diff = self.content:GetHeight() - frame:GetHeight ()
      local delta = (value > 0 and -1 or 1)
      self.scrollBar:SetValue (min (max (self.scrollValue + delta * (1000 / (diff / 45)), 0), 1000))
    end

  end)
  self.scrollFrame:SetScript ("OnSizeChanged", function (frame)
    RunNextFrame(function() self:FixScroll() end)
  end)

  self.scrollBar = CreateFrame ("Slider", "ReforgeLiteScrollBar", self.scrollFrame, "UIPanelScrollBarTemplate")
  self.scrollBar:SetPoint ("TOPLEFT", self.scrollFrame, "TOPRIGHT", 0, -14)
  self.scrollBar:SetPoint ("BOTTOMLEFT", self.scrollFrame, "BOTTOMRIGHT", 4, 16)
  self.scrollBar:SetMinMaxValues (0, 1000)
  self.scrollBar:SetValueStep (1)
  self.scrollBar:SetValue (0)
  self.scrollBar:SetWidth (16)
  self.scrollBar:SetScript ("OnValueChanged", function (bar, value)
    self:SetScroll (value)
  end)
  self.scrollBar:Hide ()

  self.scrollBg = self.scrollBar:CreateTexture (nil, "BACKGROUND")
  self.scrollBg:SetAllPoints (self.scrollBar)
  self.scrollBg:SetColorTexture (0, 0, 0, 0.4)

  self.content = CreateFrame ("Frame", nil, self.scrollFrame)
  self.scrollFrame:SetScrollChild (self.content)
  self.content:ClearAllPoints ()
  self.content:SetPoint ("TOPLEFT")
  self.content:SetPoint ("TOPRIGHT")
  self.content:SetHeight (1000)

  GUI.defaultParent = self.content

  self:CreateOptionList ()

  RunNextFrame(function() self:FixScroll() end)
  GUI:SetHelpButtonsShown(self.db.showHelp ~= false)
end

function ReforgeLite:CreateItemTable ()
  self.playerSpecTexture = self:CreateTexture (nil, "ARTWORK")
  self.playerSpecTexture:SetPoint ("TOPLEFT", 10, -28)
  self.playerSpecTexture:SetSize(18, 18)
  self.playerSpecTexture:SetTexCoord(0.0825, 0.0825, 0.0825, 0.9175, 0.9175, 0.0825, 0.9175, 0.9175)

  self.playerTalents = {}
  for tier = 1, MAX_NUM_TALENT_TIERS do
    self.playerTalents[tier] = self:CreateTexture(nil, "ARTWORK")
    self.playerTalents[tier]:SetPoint("TOPLEFT", self.playerTalents[tier-1] or self.playerSpecTexture, "TOPRIGHT", 4, 0)
    self.playerTalents[tier]:SetSize(18, 18)
    self.playerTalents[tier]:SetTexCoord(0.0825, 0.0825, 0.0825, 0.9175, 0.9175, 0.0825, 0.9175, 0.9175)
    self.playerTalents[tier]:SetScript("OnLeave", GameTooltip_Hide)
  end

  self:UpdatePlayerSpecInfo()

  self.itemTable = GUI:CreateTable (#self.itemSlots + 1, #self.itemStats, ITEM_SIZE, ITEM_SIZE + 4, {0.5, 0.5, 0.5, 1}, self)
  self.itemTable:SetPoint ("TOPLEFT", self.playerSpecTexture, "BOTTOMLEFT", 0, -6)
  self.itemTable:SetPoint ("BOTTOM", 0, 10)
  self.itemTable:SetWidth (400)
  local autoColumns = {}
  for index = 1, #self.itemStats do
    autoColumns[index] = index
  end
  self.itemTable:EnableColumnAutoWidth(unpack(autoColumns))

  self.itemLevel = self:CreateFontString (nil, "OVERLAY", "GameFontNormal")
  ReforgeLite.itemLevel:SetPoint ("BOTTOMRIGHT", ReforgeLite.itemTable, "TOPRIGHT", 0, 8)
  self.itemLevel:SetTextColor (1, 1, 0.8)
  self:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
  self:PLAYER_AVG_ITEM_LEVEL_UPDATE()

  self.itemLockHelpButton = GUI:CreateHelpButton(self, L["The Item Table shows your currently equipped gear and their stats.\n\nEach row represents one equipped item. Only stats present on your gear are shown as columns.\n\nAfter computing, items being reforged show:\n• Red numbers: Stat being reduced\n• Green numbers: Stat being added\n\nClick an item icon to lock/unlock it. Locked items (shown with a lock icon) are ignored during optimization."], { scale = 0.5 })

  self.itemTable:SetCell(0, 0, self.itemLockHelpButton, "TOPLEFT", -5, 10)

  self.statHeaders = {}
  for i, v in ipairs (self.itemStats) do
    self.itemTable:SetCellText (0, i, v.tip, nil, {1, 0.8, 0})
    self.statHeaders[i] = self.itemTable.cells[0][i]
  end
  self.itemData = {}
  for i, v in ipairs (self.itemSlots) do
    self.itemData[i] = CreateFrame ("Frame", nil, self.itemTable)
    self.itemData[i].slot = v
    self.itemData[i]:ClearAllPoints ()
    self.itemData[i]:SetSize(ITEM_SIZE, ITEM_SIZE)
    self.itemTable:SetCell (i, 0, self.itemData[i])
    self.itemData[i]:EnableMouse (true)
    self.itemData[i]:SetScript ("OnEnter", function (frame)
      GameTooltip:SetOwner (frame, "ANCHOR_LEFT")
      if frame.item then
        GameTooltip:SetInventoryItem("player", frame.slotId)
      else
        GameTooltip:SetText(_G[strupper(frame.slot)])
      end
      GameTooltip:Show ()
    end)
    self.itemData[i]:SetScript ("OnLeave", GameTooltip_Hide)
    self.itemData[i]:SetScript ("OnMouseDown", function (frame)
      local itemGUID = frame.itemInfo and frame.itemInfo.itemGUID
      if not itemGUID then return end
      self.pdb.itemsLocked[itemGUID] = not self.pdb.itemsLocked[itemGUID] and 1 or nil
      if self.pdb.itemsLocked[itemGUID] then
        frame.locked:Show ()
      else
        frame.locked:Hide ()
      end
    end)
    self.itemData[i].slotId, self.itemData[i].slotTexture = GetInventorySlotInfo (v)
    self.itemData[i].texture = self.itemData[i]:CreateTexture (nil, "ARTWORK")
    self.itemData[i].texture:SetAllPoints (self.itemData[i])
    self.itemData[i].texture:SetTexture (self.itemData[i].slotTexture)
    self.itemData[i].texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    self.itemData[i].locked = self.itemData[i]:CreateTexture (nil, "OVERLAY")
    self.itemData[i].locked:SetAllPoints (self.itemData[i])
    self.itemData[i].locked:SetTexture ("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent")
    self.itemData[i].quality = self.itemData[i]:CreateTexture (nil, "OVERLAY")
    self.itemData[i].quality:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    self.itemData[i].quality:SetBlendMode("ADD")
    self.itemData[i].quality:SetAlpha(0.75)
    self.itemData[i].quality:SetSize(44,44)
    self.itemData[i].quality:SetPoint ("CENTER", self.itemData[i])
    self.itemData[i].itemInfo = {}

    self.itemData[i].stats = {}
    for j, s in ipairs (self.itemStats) do
      local fontColors = {
        grey = {0.8, 0.8, 0.8},
        red = {1, 0.4, 0.4},
        green = {0.6, 1, 0.6},
        white = {1, 1, 1},
      }
      self.itemTable:SetCellText (i, j, "-", nil, fontColors.grey)
      self.itemData[i].stats[j] = self.itemTable.cells[i][j]
      self.itemData[i].stats[j].fontColors = fontColors
    end
  end
  self.statTotals = {}
  self.itemTable:SetCellText (#self.itemSlots + 1, 0, L["Sum"], "CENTER", {1, 0.8, 0})
  for i, v in ipairs (self.itemStats) do
    self.itemTable:SetCellText (#self.itemSlots + 1, i, "0", nil, {1, 0.8, 0})
    self.statTotals[i] = self.itemTable.cells[#self.itemSlots + 1][i]
  end
end

function ReforgeLite:GetCapBaseRow(index)
  local base = 1
  for i = 1, index - 1 do
    if self.pdb.caps[i] then
      base = base + #self.pdb.caps[i].points + 1
    end
  end
  return base
end

function ReforgeLite:HasExactCapSelection(excludeCapIndex, excludePointIndex)
  for capIndex = 1, NUM_CAPS do
    local cap = self.pdb.caps and self.pdb.caps[capIndex]
    if cap and cap.points then
      for pointIndex, point in ipairs(cap.points) do
        if point.method == addonTable.StatCapMethods.Exactly then
          if not (capIndex == excludeCapIndex and pointIndex == excludePointIndex) then
            return true
          end
        end
      end
    end
  end
  return false
end

function ReforgeLite:CanUseExactCapMethod(capIndex, pointIndex)
  local cap = self.pdb.caps and self.pdb.caps[capIndex]
  local point = cap and cap.points and cap.points[pointIndex]
  if not point then
    return false
  end
  if point.method == addonTable.StatCapMethods.Exactly then
    return true
  end
  return not self:HasExactCapSelection(capIndex, pointIndex)
end

function ReforgeLite:NormalizeExactCapSelections()
  local exactFound = false
  for capIndex = 1, NUM_CAPS do
    local cap = self.pdb.caps and self.pdb.caps[capIndex]
    if cap and cap.points then
      for _, point in ipairs(cap.points) do
        if point.method == addonTable.StatCapMethods.Exactly then
          if exactFound then
            point.method = addonTable.StatCapMethods.AtLeast
          else
            exactFound = true
          end
        end
      end
    end
  end
end

function ReforgeLite:AddCapPoint (i, loading)
  self.pdb.caps[i] = self.pdb.caps[i] or CreateDefaultCap()
  self.pdb.caps[i].points = self.pdb.caps[i].points or {}
  local base = self:GetCapBaseRow(i)
  local row = (loading or #self.pdb.caps[i].points + 1) + base
  local point = (loading or #self.pdb.caps[i].points + 1)
  self.statCaps:AddRow (row)

  if not loading then
    tinsert (self.pdb.caps[i].points, 1, {value = 0, method = 1, after = 0, preset = 1})
  end

  local rem = GUI:CreateImageButton (self.statCaps, 20, 20, "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent",
    "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent", nil, nil, function ()
    self:RemoveCapPoint (i, point)
    self.statCaps:ToggleStatDropdownToCorrectState()
  end)
  local methodList = {
    {value = addonTable.StatCapMethods.AtLeast, name = L["At least"]},
    {value = addonTable.StatCapMethods.AtMost, name = L["At most"]},
    {value = addonTable.StatCapMethods.Exactly, name = L["Exactly"]}
  }
  local method = GUI:CreateDropdown(self.statCaps, methodList, {
    default = 1,
    setter = function(_, val)
      self.pdb.caps[i].points[point].method = val
    end,
    width = 95,
    menuItemHidden = function(info)
      if info.value ~= addonTable.StatCapMethods.Exactly then
        return false
      end
      return not self:CanUseExactCapMethod(i, point)
    end,
  })
  local preset = GUI:CreateDropdown (self.statCaps, self.capPresets, {
    default = 1,
    width = 60,
    setter = function (_,val)
      self.pdb.caps[i].points[point].preset = val
      self:UpdateCapPreset (i, point)
      self:ReorderCapPoint (i, point)
      self:RefreshMethodStats ()
    end,
    menuItemHidden = function(info)
      return info.category and info.category ~= self.statCaps[i].stat.selectedValue
    end
  })
  local value = GUI:CreateEditBox (self.statCaps, 40, 30, 0, function (val)
    self.pdb.caps[i].points[point].value = val
    self:ReorderCapPoint (i, point)
    self:RefreshMethodStats ()
  end)
  local after = GUI:CreateEditBox (self.statCaps, 40, 30, 0, function (val)
    self.pdb.caps[i].points[point].after = val
    self:RefreshMethodStats ()
  end)

  GUI:SetTooltip (rem, L["Remove cap"])
  GUI:SetTooltip (value, function()
    local cap = self.pdb.caps[i]
    if cap.stat == statIds.SPIRIT then return end
    local pointValue = (cap.points[point].value or 0)
    local rating = pointValue / self:RatingPerPoint(cap.stat)
    if cap.stat == statIds.HIT then
      local meleeHitBonus = self:GetMeleeHitBonus()
      rating = RoundToSignificantDigits(rating, 1)
      if meleeHitBonus > 0 then
        rating = ("%.2f%% + %s%% = %.2f"):format(rating, meleeHitBonus, rating + meleeHitBonus)
      else
        rating = ("%.2f"):format(rating)
      end
      local spellHitRating = RoundToSignificantDigits(pointValue / self:RatingPerPoint(statIds.SPELLHIT), 1)
      local spellHitBonus = self:GetSpellHitBonus()
      if spellHitBonus > 0 then
        spellHitRating = ("%.2f%% + %s%% = %.2f"):format(spellHitRating,spellHitBonus,spellHitRating+spellHitBonus)
      else
        spellHitRating = ("%.2f"):format(spellHitRating)
      end
      rating = ("%s: %s%%\n%s: %s%%"):format(MELEE, rating, STAT_CATEGORY_SPELL, spellHitRating)
    elseif cap.stat == statIds.EXP then
      rating = RoundToSignificantDigits(rating, 1)
      local expBonus = self:GetExpertiseBonus()
      if expBonus > 0 then
        rating = ("%.2f%% + %s%% = %.2f%%"):format(rating, expBonus, rating + expBonus)
      else
        rating = ("%.2f%%"):format(rating)
      end
    elseif cap.stat == statIds.HASTE then
      local meleeHaste, rangedHaste, spellHaste = self:CalcHasteWithBonuses(rating)
      rating = ("%s: %.2f\n%s: %.2f\n%s: %.2f"):format(MELEE, meleeHaste, RANGED, rangedHaste, STAT_CATEGORY_SPELL, spellHaste)
    else
      rating = ("%.2f"):format(rating)
    end
    return ("%s\n%s"):format(L["Cap value"], rating)
  end)
  GUI:SetTooltip (after, L["Weight after cap"])

  self.statCaps:SetCell (row, 0, rem, "LEFT")
  self.statCaps:SetCell (row, 1, method, "LEFT")
  self.statCaps:SetCell (row, 2, preset, "LEFT", 5, 0)
  self.statCaps:SetCell (row, 3, value)
  self.statCaps:SetCell (row, 4, after)

  if not loading then
    self:UpdateCapPoints (i)
    self:UpdateContentSize ()
  end
  self.statCaps[i].add:Enable()
  self.statCaps:OnUpdateFix()
end
function ReforgeLite:RemoveCapPoint (i, point, loading)
  if not (self.pdb.caps[i] and self.pdb.caps[i].points) then
    return
  end
  local points = self.pdb.caps[i].points
  local numPoints = #points
  if numPoints == 0 then
    return
  end
  local base = self:GetCapBaseRow(i)
  local row = base + numPoints
  tremove (points, point)
  self.statCaps:DeleteRow (row)
  if not loading then
    self:UpdateCapPoints (i)
    self:UpdateContentSize ()
  end
  if #points == 0 then
    self.pdb.caps[i].stat = 0
    self.statCaps[i].add:Disable()
    self.statCaps[i].stat:SetValue(0)
  end
  if self.statCaps and self.statCaps.ToggleStatDropdownToCorrectState then
    self.statCaps:ToggleStatDropdownToCorrectState()
  end
end
function ReforgeLite:ReorderCapPoint (i, point)
  local newpos = point
  while newpos > 1 and self.pdb.caps[i].points[newpos - 1].value > self.pdb.caps[i].points[point].value do
    newpos = newpos - 1
  end
  while newpos < #self.pdb.caps[i].points and self.pdb.caps[i].points[newpos + 1].value < self.pdb.caps[i].points[point].value do
    newpos = newpos + 1
  end
  if newpos ~= point then
    local tmp = self.pdb.caps[i].points[point]
    tremove (self.pdb.caps[i].points, point)
    tinsert (self.pdb.caps[i].points, newpos, tmp)
    self:UpdateCapPoints (i)
  end
end
function ReforgeLite:UpdateCapPreset (i, point)
  local preset = self.pdb.caps[i].points[point].preset
  local row = point + self:GetCapBaseRow(i)
  if self.capPresets[preset] == nil then
    preset = 1
  end
  if self.capPresets[preset].getter then
    self.statCaps.cells[row][3]:SetTextColor (0.5, 0.5, 0.5)
    self.statCaps.cells[row][3]:SetMouseClickEnabled (false)
    self.statCaps.cells[row][3]:ClearFocus ()
    self.pdb.caps[i].points[point].value = max(0, floor(self.capPresets[preset].getter()))
  else
    self.statCaps.cells[row][3]:SetTextColor (1, 1, 1)
    self.statCaps.cells[row][3]:SetMouseClickEnabled (true)
  end
  self.statCaps.cells[row][3]:SetText(self.pdb.caps[i].points[point].value)
end
function ReforgeLite:UpdateCapPoints (i)
  local base = self:GetCapBaseRow(i)
  for point = 1, #self.pdb.caps[i].points do
    self.statCaps.cells[base + point][1]:SetValue (self.pdb.caps[i].points[point].method)
    self.statCaps.cells[base + point][2]:SetValue (self.pdb.caps[i].points[point].preset)
    self:UpdateCapPreset (i, point)
    self.statCaps.cells[base + point][4]:SetText (self.pdb.caps[i].points[point].after)
  end
end
function ReforgeLite:CollapseStatCaps()
  local caps = DeepCopy(self.pdb.caps)
  table.sort(caps, function(a,b)
    local aIsNone = a.stat == 0 and 1 or 0
    local bIsNone = b.stat == 0 and 1 or 0
    return aIsNone < bIsNone
  end)
  self:SetStatWeights(nil, caps)
end
function ReforgeLite:SetStatWeights (weights, caps)
  if weights then
    self.pdb.weights = DeepCopy (weights)
    for i = 1, #self.itemStats do
      if self.statWeights.inputs[i] then
        self.statWeights.inputs[i]:SetText (self.pdb.weights[i])
      end
    end
  end
  if caps then
    for i = 1, NUM_CAPS do
      local count = 0
      if caps[i] then
        count = #caps[i].points
      end
      self.pdb.caps[i] = self.pdb.caps[i] or CreateDefaultCap()
      self.pdb.caps[i].stat = caps[i] and caps[i].stat or 0
      if self.statCaps[i] and self.statCaps[i].stat then
        self.statCaps[i].stat:SetValue (self.pdb.caps[i].stat)
      end
      while #self.pdb.caps[i].points < count do
        self:AddCapPoint (i)
      end
      while #self.pdb.caps[i].points > count do
        self:RemoveCapPoint (i, 1)
      end
      if caps[i] then
        self.pdb.caps[i] = DeepCopy (caps[i])
        for p = 1, #self.pdb.caps[i].points do
          local point = self.pdb.caps[i].points[p]
          if point.method == addonTable.StatCapMethods.NewValue then
            point.method = addonTable.StatCapMethods.AtLeast
          end
          point.method = point.method or addonTable.StatCapMethods.AtLeast
          point.after = point.after or 0
          point.value = point.value or 0
          point.preset = point.preset or 1
        end
      else
        self.pdb.caps[i].stat = 0
        self.pdb.caps[i].points = {}
      end
    end
    self:NormalizeExactCapSelections()
    for i = 1, NUM_CAPS do
      self:UpdateCapPoints (i)
    end
    self.statCaps:ToggleStatDropdownToCorrectState()
    self.statCaps.onUpdate ()
    self:UpdateContentSize ()
    RunNextFrame(function() self:CapUpdater() end)
  end
  self:RefreshMethodStats ()
end
function ReforgeLite:CapUpdater ()
  for i = 1, NUM_CAPS do
    if not self.pdb.caps[i] then
      self.pdb.caps[i] = CreateDefaultCap()
    end
    if self.statCaps[i] and self.statCaps[i].stat then
      self.statCaps[i].stat:SetValue (self.pdb.caps[i].stat or 0)
    end
    self:UpdateCapPoints (i)
  end
end
function ReforgeLite:CustomPresetsExist()
  return next(ReforgeLite.cdb.customPresets) ~= nil
end
function ReforgeLite:UpdateStatWeightList ()
  local stats = self.itemStats
  local rows = 0
  for i, v in pairs (stats) do
    rows = rows + 1
  end
  local extraRows = 0
  self.statWeights:ClearCells ()
  self.statWeights.inputs = {}
  rows = ceil (rows / 2) + extraRows
  while self.statWeights.rows > rows do
    self.statWeights:DeleteRow (1)
  end
  if self.statWeights.rows < rows then
    self.statWeights:AddRow (1, rows - self.statWeights.rows)
  end
  local pos = 0
  for i, v in pairs (stats) do
    pos = pos + 1
    local col = floor ((pos - 1) / (self.statWeights.rows - extraRows))
    local row = pos - col * (self.statWeights.rows - extraRows) + extraRows
    col = 1 + 2 * col

    local labelColor = addonTable.FONTS and addonTable.FONTS.darkyellow
    self.statWeights:SetCellText (row, col, v.long, "LEFT", labelColor)
    self.statWeights.inputs[i] = GUI:CreateEditBox (self.statWeights, 50, ITEM_SIZE, self.pdb.weights[i], function (val)
      self.pdb.weights[i] = val
      self:RefreshMethodStats ()
    end, {
      OnTabPressed = function(frame)
        if self.statWeights.inputs[i+1] then
          self.statWeights.inputs[i+1]:SetFocus()
        else
          frame:ClearFocus()
        end
      end,
    })
    self.statWeights:SetCell (row, col + 1, self.statWeights.inputs[i])
  end

  self.statWeights:SetColumnWidth (2, 50)
  self.statWeights:SetColumnWidth (4, 50)
  self.statWeights:EnableColumnAutoWidth(1, 3)

  self.statCaps:Show2 ()
  self:SetAnchor (self.computeButton, "TOPLEFT", self.statCaps, "BOTTOMLEFT", 0, -10)

  self:UpdateContentSize ()
end

function ReforgeLite:CreateOptionList ()
  self.statWeightsCategory = self:CreateCategory (L["Stat Weights"])
  self:SetAnchor (self.statWeightsCategory, "TOPLEFT", self.content, "TOPLEFT", 2, -2)

  self.presetsButton = GUI:CreateFilterDropdown(self.content, L["Presets"], {resizeToTextPadding = 35})
  self.statWeightsCategory:AddFrame(self.presetsButton)
  self:SetAnchor(self.presetsButton, "TOPLEFT", self.statWeightsCategory, "BOTTOMLEFT", 0, -5)
  if self.presetMenuGenerator then
    self.presetsButton:SetupMenu(self.presetMenuGenerator)
  end

  self.pawnButton = GUI:CreatePanelButton (self.content, L["Import WoWSims/Pawn/QE"], function(btn) self:ImportData() end)
  self.statWeightsCategory:AddFrame (self.pawnButton)
  self:SetAnchor (self.pawnButton, "LEFT", self.presetsButton, "RIGHT", 8, 0)

  local levelList = function()
    return {
        {value=0,name=("%s (+%d)"):format(PVP, 0)},
        {value=1,name=("%d (+%d)"):format(UnitLevel('player') + 1, 1)},
        {value=2,name=("%s (+%d)"):format(LFG_TYPE_HEROIC_DUNGEON, 2)},
        {value=3,name=("%s %s (+%d)"):format(CreateSimpleTextureMarkup([[Interface\TargetingFrame\UI-TargetingFrame-Skull]], 16, 16), LFG_TYPE_RAID, 3)},
    }
  end

  self.targetLevel = GUI:CreateDropdown(self.content, levelList, {
    default =  self.pdb.targetLevel,
    setter = function(_,val) self.pdb.targetLevel = val; self:UpdateItems() end,
    width = 150,
  })
  self.statWeightsCategory:AddFrame(self.targetLevel)
  self.targetLevel.text = self.targetLevel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  self.targetLevel.text:SetText(STAT_TARGET_LEVEL)
  self:SetAnchor(self.targetLevel.text, "TOPLEFT", self.presetsButton, "BOTTOMLEFT", 0, -12)
  self.targetLevel:SetPoint("LEFT", self.targetLevel.text, "RIGHT", 5, 0)

  self.buffsContextMenu = GUI:CreateFilterDropdown(self.content, L["Buffs"], {resizeToTextPadding = 25})
  self.statWeightsCategory:AddFrame(self.buffsContextMenu)
  self:SetAnchor(self.buffsContextMenu, "LEFT", self.targetLevel, "RIGHT", 10, 0)

  local buffsContextValues = {
    spellHaste = { text = addonTable.CreateIconMarkup(136092) .. L["Spell Haste"], selected = self.PlayerHasSpellHasteBuff },
    meleeHaste = { text = addonTable.CreateIconMarkup(133076) .. L["Melee Haste"], selected = self.PlayerHasMeleeHasteBuff },
    mastery = { text = addonTable.CreateIconMarkup(136046) .. STAT_MASTERY, selected = self.PlayerHasMasteryBuff },
  }

  self.buffsContextMenu:SetupMenu(function(dropdown, rootDescription)
    local function IsSelected(value)
        return self.pdb[value] or buffsContextValues[value].selected(self)
    end
    local function SetSelected(value)
        self.pdb[value] = not self.pdb[value]
        self:QueueUpdate()
    end
    for key, box in pairs(buffsContextValues) do
        local checkbox = rootDescription:CreateCheckbox(box.text, IsSelected, SetSelected, key)
        checkbox.IsEnabled = function(chkbox) return not buffsContextValues[chkbox.data].selected(self) end
    end
  end)

  self.statWeights = GUI:CreateTable (ceil (#self.itemStats / 2), 4)
  self:SetAnchor (self.statWeights, "TOPLEFT", self.targetLevel.text, "BOTTOMLEFT", 0, -8)
  self.statWeightsCategory:AddFrame (self.statWeights)
  self.statWeights:SetRowHeight (ITEM_SIZE + 2)
  self.statWeights:SetColumnWidth (2, 50)
  self.statWeights:SetColumnWidth (4, 50)
  self.statWeights:EnableColumnAutoWidth(1, 3)

  self.statCaps = GUI:CreateTable (NUM_CAPS, 4, nil, ITEM_SIZE + 2)
  self.statWeightsCategory:AddFrame (self.statCaps)
  self:SetAnchor (self.statCaps, "TOPLEFT", self.statWeights, "BOTTOMLEFT", 0, -10)
  self.statCaps:SetPoint ("RIGHT", -5, 0)
  self.statCaps:SetRowHeight (ITEM_SIZE + 2)
  self.statCaps:SetColumnWidth (1, 100)
  self.statCaps:SetColumnWidth (3, 50)
  self.statCaps:SetColumnWidth (4, 50)

  local statList = {{value = 0, name = NONE}}
  for i, v in ipairs (self.itemStats) do
    tinsert (statList, {value = i, name = v.long})
  end

  self.statCaps.ToggleStatDropdownToCorrectState = function(caps)
    for i = 2, NUM_CAPS do
      local dropdown = caps[i] and caps[i].stat
      if dropdown then
        dropdown:SetEnabled(self.pdb.caps[i - 1] and self.pdb.caps[i - 1].stat ~= 0)
      end
    end
  end

  for i = 1, NUM_CAPS do
    self.pdb.caps[i] = self.pdb.caps[i] or CreateDefaultCap()
    self.statCaps[i] = {}
    self.statCaps[i].stat = GUI:CreateDropdown (self.statCaps, statList, {
      default = self.pdb.caps[i].stat,
      setter = function (dropdown, val, oldVal)
        local previous = oldVal
        if previous == nil then
          previous = dropdown.value
        end

        if val == 0 then
          while #self.pdb.caps[i].points > 0 do
            self:RemoveCapPoint (i, 1)
          end
        elseif previous == 0 then
          self:AddCapPoint(i)
        end

        self.pdb.caps[i].stat = val
        if val == 0 then
          self:CollapseStatCaps()
        end

        self.statCaps:ToggleStatDropdownToCorrectState()
      end,
      width = 125,
      menuItemDisabled = function(val)
        if val <= 0 then
          return false
        end
        for j = 1, NUM_CAPS do
          if j ~= i and self.statCaps[j] and self.statCaps[j].stat.value == val then
            return true
          end
        end
        return false
      end
    })

    self.statCaps[i].add = GUI:CreateImageButton (self.statCaps, 20, 20, "Interface\\Buttons\\UI-PlusButton-Up",
      "Interface\\Buttons\\UI-PlusButton-Down", "Interface\\Buttons\\UI-PlusButton-Hilight", "Interface\\Buttons\\UI-PlusButton-Disabled", function()
      self:AddCapPoint (i)
    end)
    GUI:SetTooltip (self.statCaps[i].add, L["Add cap"])

    self.statCaps:SetCell (i, 0, self.statCaps[i].stat, "LEFT")
    self.statCaps:SetCell (i, 2, self.statCaps[i].add, "LEFT")
  end

  for i = 1, NUM_CAPS do
    for point in ipairs(self.pdb.caps[i].points) do
      self:AddCapPoint (i, point)
    end
    self:UpdateCapPoints (i)
    if self.pdb.caps[i].stat == 0 then
      self:RemoveCapPoint(i)
    end
  end

  self.statCaps:ToggleStatDropdownToCorrectState()

  self.statCaps.onUpdate = function ()
    local row = 1
    for i = 1, NUM_CAPS do
      row = row + 1
      for point = 1, #self.pdb.caps[i].points do
        local cell = self.statCaps.cells[row] and self.statCaps.cells[row][2]
        if cell and cell.values then
          cell:SetWidth(self.statCaps:GetColumnWidth (2) - 20)
        end
        row = row + 1
      end
    end
  end

  self.statCaps.saveOnUpdate = self.statCaps.onUpdate
  self.statCaps.onUpdate ()
  RunNextFrame(function() self:CapUpdater() end)

  self.computeButton = GUI:CreatePanelButton (self.content, L["Compute"], function() self:StartCompute() end)
  self.computeButton:SetScript ("PreClick", function (btn)
    GUI:Lock()
    GUI:ClearFocus()
    btn:RenderText(IN_PROGRESS)
  end)

  self:UpdateStatWeightList ()

  self.quality = CreateFrame ("Slider", nil, self.content, "UISliderTemplateWithLabels")
  self:SetAnchor (self.quality, "LEFT", self.computeButton, "RIGHT", 10, 0)
  self.quality:SetSize(150, 15)
  self.quality:SetMinMaxValues (MIN_LOOPS, addonTable.MAX_LOOPS)
  self.quality:SetValueStep ((addonTable.MAX_LOOPS - MIN_LOOPS) / 20)
  self.quality:SetObeyStepOnDrag(true)
  self.quality:SetValue (self.db.speed)
  self.quality:EnableMouseWheel (false)
  self.quality:SetScript ("OnValueChanged", function (slider)
    self.db.speed = slider:GetValue ()
  end)

  self.quality.Text:SetText (SPEED)
  self.quality.Low:SetText (SLOW)
  self.quality.High:SetText (FAST)

  self.quality.helpButton = GUI:CreateHelpButton(self.quality, L["Slide to the left if the calculation slows your game too much."], { scale = 0.45 })
  self.quality.helpButton:SetPoint("BOTTOMLEFT",self.quality.Text, "BOTTOMRIGHT",0,-20)

  self.settingsCategory = self:CreateCategory (SETTINGS)
  self:SetAnchor (self.settingsCategory, "TOPLEFT", self.computeButton, "BOTTOMLEFT", 0, -10)
  self.settings = GUI:CreateTable (7, 1, nil, 200)
  self.settingsCategory:AddFrame (self.settings)
  self:SetAnchor (self.settings, "TOPLEFT", self.settingsCategory, "BOTTOMLEFT", 0, -5)
  self.settings:SetPoint ("RIGHT", self.content, -10, 0)
  self.settings:SetRowHeight (ITEM_SIZE + 2)

  self:FillSettings()

  self.lastElement = CreateFrame ("Frame", nil, self.content)
  self.lastElement:ClearAllPoints ()
  self.lastElement:SetSize(0, 0)
  self:SetAnchor (self.lastElement, "TOPLEFT", self.settings, "BOTTOMLEFT", 0, -10)
  self:UpdateContentSize ()

  if self.pdb.method then
    ReforgeLite:UpdateMethodCategory ()
  end
end
function ReforgeLite:GetActiveWindow()
  if not RFL_FRAMES[2] and self:IsShown() then
    return self
  end
  local topWindow
  for _, frame in ipairs(RFL_FRAMES) do
    if frame:IsShown() and (not topWindow or frame:GetRaisedFrameLevel() > topWindow:GetRaisedFrameLevel()) then
      topWindow = frame
    end
  end
  return topWindow
end

function ReforgeLite:GetInactiveWindows()
  if not RFL_FRAMES[2] then
    return {}
  end
  local activeWindow = self:GetActiveWindow()
  local bottomWindows = {}
  for _, frame in ipairs(RFL_FRAMES) do
    if frame:IsShown() and frame ~= activeWindow and frame:GetRaisedFrameLevel() < activeWindow:GetRaisedFrameLevel() then
      tinsert(bottomWindows, frame)
    end
  end
  return bottomWindows
end

local function GetColorRGB(color, fallbackR, fallbackG, fallbackB)
  if color then
    if color.GetRGB then
      return color:GetRGB()
    elseif color.r then
      return color.r, color.g, color.b
    end
  end
  return fallbackR, fallbackG, fallbackB
end

function ReforgeLite:UpdateSpeedPresetRadiosEnabled()
  local radioFrame = self.settings and self.settings.speedPresetRadioFrame
  if not radioFrame or not radioFrame.radios then
    return
  end

  local enabled = not self.computeInProgress
  local defaultR, defaultG, defaultB = GetColorRGB(NORMAL_FONT_COLOR, 1, 1, 1)
  local disabledR, disabledG, disabledB = GetColorRGB(GRAY_FONT_COLOR, 0.5, 0.5, 0.5)

  for _, radio in ipairs(radioFrame.radios) do
    if enabled then
      radio:Enable()
      if radio.Text then
        local original = radio.Text.originalColor
        if original then
          radio.Text:SetTextColor(original[1], original[2], original[3])
        else
          radio.Text:SetTextColor(defaultR, defaultG, defaultB)
        end
      end
    else
      radio:Disable()
      if radio.Text then
        radio.Text:SetTextColor(disabledR, disabledG, disabledB)
      end
    end
  end
end

function ReforgeLite:FillSettings()
  self.settings:ClearCells()
  orderIds['settings'] = 0

  local speedLabelRow = getOrderId('settings', self.settings)
  local speedOptions = {
    { value = "extra_fast", name = L["Extra Fast"] },
    { value = "fast", name = L["Fast"] },
    { value = "normal", name = L["Normal"] },
  }

  self.settings:SetCellText(speedLabelRow, 0, L["Speed/Accuracy"] .. ":", "LEFT", nil, "GameFontNormal")

  local speedRadioRow = getOrderId('settings', self.settings)
  local selectedPreset = self.db.coreSpeedPreset or "fast"
  local selectedPresetValid = false
  for _, option in ipairs(speedOptions) do
    if option.value == selectedPreset then
      selectedPresetValid = true
      break
    end
  end
  if not selectedPresetValid then
    selectedPreset = "fast"
    self:SetCoreSpeedPreset(selectedPreset)
  end
  local radioFrame = self.settings.speedPresetRadioFrame

  local radioSpacing = 4
  local radioTopPadding = 4
  local radioBottomPadding = 12
  if not radioFrame then
    radioFrame = CreateFrame("Frame", nil, self.settings)
    radioFrame.radios = {}
    self.settings.speedPresetRadioFrame = radioFrame
  else
    radioFrame:SetParent(self.settings)
    radioFrame:Show()
  end
  radioFrame:SetWidth(260)

  local function UpdateRadioSelection(value)
    for _, button in ipairs(radioFrame.radios) do
      button:SetChecked(button.value == value)
    end
  end
  self.settings.speedPresetDropdown = nil

  local previous
  local owner = self
  for index, option in ipairs(speedOptions) do
    local radio = radioFrame.radios[index]
    if not radio then
      radio = CreateFrame("CheckButton", nil, radioFrame, "UIRadioButtonTemplate")
      radioFrame.radios[index] = radio
    end

    if not radio.Text then
      local label = radio:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      radio.Text = label
      label:SetPoint("LEFT", radio, "RIGHT", 2, 0)
    else
      radio.Text:ClearAllPoints()
      radio.Text:SetPoint("LEFT", radio, "RIGHT", 2, 0)
    end

    radio:ClearAllPoints()
    if previous then
      radio:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -radioSpacing)
    else
      radio:SetPoint("TOPLEFT", radioFrame, "TOPLEFT", 0, -radioTopPadding)
    end

    radio.value = option.value
    radio.Text:SetText(option.name)
    if radio.Text and not radio.Text.originalColor then
      local r, g, b = radio.Text:GetTextColor()
      radio.Text.originalColor = {r, g, b}
    end

    radio:SetScript("OnClick", function(button)
      if not button:GetChecked() then
        button:SetChecked(true)
        return
      end
      owner:SetCoreSpeedPreset(button.value)
      UpdateRadioSelection(button.value)
    end)

    radio:Show()
    previous = radio
  end

  for index = #radioFrame.radios, #speedOptions + 1, -1 do
    local extra = radioFrame.radios[index]
    if extra then
      extra:Hide()
    end
    radioFrame.radios[index] = nil
  end

  local totalHeight = 0
  if #speedOptions > 0 then
    local radioHeight = radioFrame.radios[1] and radioFrame.radios[1]:GetHeight() or 24
    totalHeight = radioTopPadding + (#speedOptions * radioHeight) + ((#speedOptions - 1) * radioSpacing) + radioBottomPadding
  else
    totalHeight = radioTopPadding + radioBottomPadding + (ITEM_SIZE + 2)
  end

  radioFrame:SetHeight(totalHeight)
  if self.settings and self.settings.SetRowHeight then
    local desiredHeight = max(totalHeight, ITEM_SIZE + 2)
    self.settings:SetRowHeight(speedRadioRow, desiredHeight)
  end

  UpdateRadioSelection(selectedPreset)
  self:UpdateSpeedPresetRadiosEnabled()
  self.settings:SetCell(speedRadioRow, 0, radioFrame, "TOPLEFT")

  self.settings:SetCell (getOrderId('settings', self.settings), 0, GUI:CreateCheckButton (self.settings, L["Open window when reforging"],
    self.db.openOnReforge, function (val) self.db.openOnReforge = val end), "LEFT")

  self.settings:SetCell (getOrderId('settings', self.settings), 0, GUI:CreateCheckButton (self.settings, L["Summarize reforged stats"],
    self.db.updateTooltip,
    function (val)
      self.db.updateTooltip = val
      if val then
        self:HookTooltipScripts()
      end
    end),
    "LEFT")

  self.settings:SetCell (getOrderId('settings', self.settings), 0, GUI:CreateCheckButton (self.settings, L["Enable spec profiles"],
    self.db.specProfiles, function (val)
      self.db.specProfiles = val
      if val then
        self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
      else
        self.pdb.prevSpecSettings = nil
        self:UnregisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
      end
    end),
    "LEFT")

  self.settings:SetCell (getOrderId('settings', self.settings), 0, GUI:CreateCheckButton (self.settings, L["Show import button on Reforging window"],
    self.db.importButton, function (val)
      self.db.importButton = val
      if val then
        self:CreateImportButton()
      elseif self.importButton then
        self.importButton:Hide()
      end
    end),
    "LEFT")

  self.settings:SetCell (getOrderId('settings', self.settings), 0, GUI:CreateCheckButton (self.settings, L["Show help buttons"],
    self.db.showHelp ~= false, function (val)
      self.db.showHelp = not not val
      GUI:SetHelpButtonsShown(val)
    end),
    "LEFT")

  local activeWindowTitleOrderId = getOrderId('settings', self.settings)
  self.settings:SetCellText (activeWindowTitleOrderId, 0, L["Active window color"], "LEFT", nil, "GameFontNormal")
  self.settings:SetCell (activeWindowTitleOrderId, 1, GUI:CreateColorPicker (self.settings, 20, 20, self.db.activeWindowTitle, function ()
    local activeWindow = self:GetActiveWindow()
    if activeWindow then
      activeWindow:SetFrameActive(true)
    end
  end), "LEFT")

  local inactiveWindowTitleOrderId = getOrderId('settings', self.settings)
  self.settings:SetCellText (inactiveWindowTitleOrderId, 0, L["Inactive window color"], "LEFT", nil, "GameFontNormal")
  self.settings:SetCell (inactiveWindowTitleOrderId, 1, GUI:CreateColorPicker (self.settings, 20, 20, self.db.inactiveWindowTitle, function ()
    for _, frame in ipairs(self:GetInactiveWindows()) do
      frame:SetFrameActive(false)
    end
  end), "LEFT")

  while self.settings.rows > orderIds['settings'] do
    self.settings:DeleteRow(self.settings.rows)
  end

end

function ReforgeLite:CreateImportButton()
  if not self.db.importButton then return end
  if self.importButton then
    self.importButton:Show()
  else
    self.importButton = CreateFrame("Button", nil, ReforgingFrame.TitleContainer, "UIPanelButtonTemplate")
    self.importButton:SetPoint("TOPRIGHT")
    self.importButton:SetText(L["Import"])
    self.importButton.fitTextWidthPadding = 20
    self.importButton:FitToText()
    self.importButton:SetScript("OnClick", function(btn) self:ImportData(btn) end)
  end
end

local function FormatMethodStatValue(value)
  if type(value) ~= "number" then
    return tostring(value or "")
  end
  local rounded = floor(value + 0.5)
  if abs(value - rounded) < 0.01 then
    return FormatLargeNumber(rounded)
  end
  return string.format("%.2f", value)
end

local function FormatMethodDelta(value, base)
  local delta = value - base
  if abs(delta) < 0.01 then
    delta = 0
  end
  if delta >= 0 then
    return string.format("+%s", FormatMethodStatValue(delta))
  end
  return string.format("-%s", FormatMethodStatValue(-delta))
end

function ReforgeLite:GetMethodAlternativeLabel(index)
  if index == 1 then
    return L["Best Result"]
  end
  return string.format(L["Alternative %d"], index - 1)
end

function ReforgeLite:SetMethodAlternatives(methods, selectedIndex)

  self.allMethodAlternatives = methods or {}

  local maxDisplay = addonTable.MAX_METHOD_ALTERNATIVES or #self.allMethodAlternatives
  local display = {}
  for index = 1, math.min(#self.allMethodAlternatives, maxDisplay) do
    display[index] = self.allMethodAlternatives[index]
  end

  self.methodAlternatives = display
  local count = #self.methodAlternatives
  if count == 0 then
    self.methodAlternativesHidden = true
    self.selectedMethodAlternative = nil
    self.pdb.method = nil
    if self.methodAlternativeButtons then
      self:UpdateMethodAlternativeButtons()
    end
    return
  end

  local firstSelectable
  for index, method in ipairs(self.methodAlternatives) do
    if method and not method.isPlaceholder then
      firstSelectable = firstSelectable or index
    end
  end

  if not firstSelectable then
    self.methodAlternativesHidden = true
    self.selectedMethodAlternative = nil
    self.pdb.method = self.methodAlternatives[1] or nil
    if self.methodAlternativeButtons then
      self:UpdateMethodAlternativeButtons()
    end
    return
  end

  local selection = selectedIndex or self.selectedMethodAlternative or firstSelectable
  if selection < 1 or selection > count or (self.methodAlternatives[selection] and self.methodAlternatives[selection].isPlaceholder) then
    selection = firstSelectable
  end

  self.methodAlternativesHidden = false
  self.selectedMethodAlternative = selection
  self.pdb.method = self.methodAlternatives[self.selectedMethodAlternative]

  if self.methodAlternativeButtons then
    self:UpdateMethodAlternativeButtons()
  end
end

function ReforgeLite:GetSelectedMethodAlternative()
  if self.methodAlternativesHidden then
    return nil
  end
  return self.selectedMethodAlternative or 1
end

function ReforgeLite:SelectMethodAlternative(index)
  if self.methodAlternativesHidden then
    return
  end
  if not self.methodAlternatives or not self.methodAlternatives[index] then
    return
  end
  if self.selectedMethodAlternative == index then
    return
  end

  self.selectedMethodAlternative = index
  self.pdb.method = self.methodAlternatives[index]
  GUI:ClearFocus()
  self:RefreshMethodStats()
  self:RefreshMethodWindow()
  self:UpdateMethodChecks()
  self:UpdateMethodAlternativeButtons()
end

function ReforgeLite:ShowMethodAlternativeTooltip(button)
  if not button or not button.altIndex then
    return
  end
  local method = self.methodAlternatives and self.methodAlternatives[button.altIndex]
  if not method then
    return
  end

  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:SetText(self:GetMethodAlternativeLabel(button.altIndex))

  GameTooltip:AddLine(" ")
  for _, stat in ipairs(self.itemStats) do
    local value = stat.mgetter(method)
    local current = stat.getter()
    local delta = value - current
    local r, g, b = 0.9, 0.9, 0.9
    if delta > 0.01 then
      r, g, b = 0.6, 1, 0.6
    elseif delta < -0.01 then
      r, g, b = 1, 0.4, 0.4
    end
    GameTooltip:AddDoubleLine(stat.tip, string.format("%s (%s)", FormatMethodStatValue(value), FormatMethodDelta(value, current)), 1, 1, 1, r, g, b)
  end

  if method.satisfied then
    local missing = {}
    for capIndex, satisfied in ipairs(method.satisfied) do
      if satisfied == false then
        local cap = self.pdb.caps and self.pdb.caps[capIndex]
        local statId = cap and cap.stat
        if statId and statId > 0 and self.itemStats[statId] then
          missing[#missing + 1] = self.itemStats[statId].tip
        end
      end
    end
    if #missing > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format("%s: %s", L["Caps not met"], table.concat(missing, ", ")), 1, 0.4, 0.4)
    end
  end

  GameTooltip:Show()
end

function ReforgeLite:EnsureMethodAlternativeButtons(count)
  if not self.methodAlternativesContainer then
    return
  end

  self.methodAlternativeButtons = self.methodAlternativeButtons or {}

  for index = #self.methodAlternativeButtons + 1, count do
    local button = CreateFrame("Button", nil, self.methodAlternativesContainer, "BackdropTemplate")
    button:SetHeight(METHOD_ALTERNATIVE_BUTTON_HEIGHT)
    if index == 1 then
      button:SetPoint("TOPLEFT")
      button:SetPoint("TOPRIGHT")
    else
      button:SetPoint("TOPLEFT", self.methodAlternativeButtons[index - 1], "BOTTOMLEFT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
      button:SetPoint("TOPRIGHT", self.methodAlternativeButtons[index - 1], "BOTTOMRIGHT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
    end

    button.bg = button:CreateTexture(nil, "BACKGROUND")
    button.bg:SetAllPoints()
    button.bg:SetColorTexture(0.08, 0.08, 0.08, 0.7)

    button.selected = button:CreateTexture(nil, "BORDER")
    button.selected:SetAllPoints()
    button.selected:SetColorTexture(0.8, 0.6, 0, 0.25)
    button.selected:Hide()

    button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
    button.highlight:SetAllPoints()
    button.highlight:SetColorTexture(1, 1, 1, 0.08)

    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", -8, 0)
    button.label:SetJustifyH("LEFT")

    button:SetScript("OnEnter", function(btn) self:ShowMethodAlternativeTooltip(btn) end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:SetScript("OnClick", function(btn) self:SelectMethodAlternative(btn.altIndex) end)

    self.methodAlternativeButtons[index] = button
  end
end

function ReforgeLite:UpdateMethodAlternativeButtons()
  if not self.methodAlternativeButtons then
    return
  end

  if self.methodAlternativesHidden then
    for _, button in ipairs(self.methodAlternativeButtons) do
      button:Hide()
      button.selected:Hide()
    end
    if self.methodAlternativesContainer then
      self.methodAlternativesContainer:Hide()
    end
    return
  end

  local methods = self.methodAlternatives or {}
  local selected = self:GetSelectedMethodAlternative()
  local visible = 0

  local maxButtons = addonTable.MAX_METHOD_ALTERNATIVES or #self.methodAlternativeButtons

  self:EnsureMethodAlternativeButtons(maxButtons)

  for index, button in ipairs(self.methodAlternativeButtons) do
    if index > maxButtons then
      button:Hide()
      button.altIndex = nil
      button.selected:Hide()
    else
      local method = methods[index]
      if method and method.isPlaceholder then
        method = nil
      end
      button.altIndex = index
      if method then
        visible = visible + 1
        button:Show()
        button.label:SetText(self:GetMethodAlternativeLabel(index))
        if index == selected then
          button.selected:Show()
        else
          button.selected:Hide()
        end
      else
        button:Hide()
        button.selected:Hide()
      end
    end
  end

  if self.methodAlternativesContainer then
    if visible > 0 then
      self.methodAlternativesContainer:Show()
    else
      self.methodAlternativesContainer:Hide()
    end
  end
end

function ReforgeLite:UpdateMethodCategory()
  if self.methodCategory == nil then
    self.methodCategory = self:CreateCategory (L["Result"])
    self:SetAnchor (self.methodCategory, "TOPLEFT", self.computeButton, "BOTTOMLEFT", 0, -10)

    self.methodStats = GUI:CreateTable (#self.itemStats - 1, 2, ITEM_SIZE, 60, {0.5, 0.5, 0.5, 1})
    self.methodCategory:AddFrame (self.methodStats)
    self:SetAnchor (self.methodStats, "TOPLEFT", self.methodCategory, "BOTTOMLEFT", 0, -5)
    self.methodStats:SetRowHeight (ITEM_SIZE + 2)
    self.methodStats:SetColumnWidth (60)

    for i, v in ipairs (self.itemStats) do
      self.methodStats:SetCellText (i - 1, 0, v.tip, "LEFT")

      self.methodStats[i] = {}

      self.methodStats[i].value = self.methodStats:CreateFontString (nil, "OVERLAY", "GameFontNormalSmall")
      self.methodStats:SetCell (i - 1, 1, self.methodStats[i].value)
      self.methodStats[i].value:SetTextColor (1, 1, 1)
      self.methodStats[i].value:SetText ("0")

      self.methodStats[i].delta = self.methodStats:CreateFontString (nil, "OVERLAY", "GameFontNormalSmall")
      self.methodStats:SetCell (i - 1, 2, self.methodStats[i].delta)
      self.methodStats[i].delta:SetTextColor (0.7, 0.7, 0.7)
      self.methodStats[i].delta:SetText ("+0")
    end

    self.methodAlternativesContainer = CreateFrame("Frame", nil, self.content)
    self.methodCategory:AddFrame(self.methodAlternativesContainer)
    self:SetAnchor (self.methodAlternativesContainer, "TOPLEFT", self.methodStats, "TOPRIGHT", 10, 0)
    self.methodAlternativesContainer:SetPoint("BOTTOMLEFT", self.methodStats, "BOTTOMRIGHT", 10, 0)
    self.methodAlternativesContainer:SetWidth(120)
    self.methodAlternativesContainer:Hide()

    self.methodAlternativeButtons = {}
    self:EnsureMethodAlternativeButtons(addonTable.MAX_METHOD_ALTERNATIVES)

    self.methodReforge = GUI:CreatePanelButton (self.content, REFORGE, function(btn)
      if not self.methodWindow then
        self:CreateMethodWindow()
      end
      self:DoReforge()
    end)
    self.methodReforge:SetSize(114, 22)
    self.methodReforge:SetMotionScriptsWhileDisabled(true)
    GUI:SetTooltip(self.methodReforge, function()
      if not ReforgeFrameIsVisible() then
        return L["Reforging window must be open"]
      end
    end)
    self.methodCategory:AddFrame (self.methodReforge)
    self:SetAnchor (self.methodReforge, "TOPLEFT", self.methodStats, "BOTTOMLEFT", 0, -5)

    self.methodCost = CreateFrame("Frame", nil, self.content, "SmallMoneyFrameTemplate")
    MoneyFrame_SetType(self.methodCost, "REFORGE")
    self.methodCost:Hide()
    self.methodCategory:AddFrame(self.methodCost)
    self:SetAnchor(self.methodCost, "TOPLEFT", self.methodReforge, "TOPRIGHT", 5, 0)

    self.methodShow = GUI:CreatePanelButton (self.content, SHOW, function(btn) self:ShowMethodWindow() end)
    self.methodShow:SetSize(85, 22)
    self.methodCategory:AddFrame (self.methodShow)
    self:SetAnchor (self.methodShow, "TOPLEFT", self.methodReforge, "BOTTOMLEFT", 0, -5)

    self.methodReset = GUI:CreatePanelButton (self.content, RESET, function(btn) self:ResetMethod() end)
    self.methodReset:SetSize(114, 22)
    self.methodCategory:AddFrame (self.methodReset)

    self:SetAnchor (self.methodReset, "TOPLEFT", self.methodShow, "TOPRIGHT", 5, 0)
    self:SetAnchor (self.settingsCategory, "TOPLEFT", self.methodShow, "BOTTOMLEFT", 0, -10)
  end

  if self.pdb.method and (not self.methodAlternatives or #self.methodAlternatives == 0) then
    self:SetMethodAlternatives({self.pdb.method}, self.selectedMethodAlternative or 1)
  end

  self:UpdateMethodAlternativeButtons()

  self:RefreshMethodStats()

  self:RefreshMethodWindow()
  self:UpdateContentSize ()
end
function ReforgeLite:RefreshMethodStats()
  if self.pdb.method then
    self:UpdateMethodStats (self.pdb.method)
  end
  if self.pdb.method then
    if self.methodStats then
      for i, v in ipairs (self.itemStats) do
        local mvalue = v.mgetter (self.pdb.method)
        if v.percent then
          self.methodStats[i].value:SetFormattedText("%.2f%%", mvalue)
        else
          self.methodStats[i].value:SetText (mvalue)
        end
        local override
        mvalue = v.mgetter (self.pdb.method, true)
        local value = v.getter ()
        if self:GetStatScore (i, mvalue) == self:GetStatScore (i, value) then
          override = 0
        end
        SetTextDelta (self.methodStats[i].delta, mvalue, value, override)
      end
    end
  end
  self:UpdateMethodChecks()
end

function ReforgeLite:UpdateContentSize ()
  self.content:SetHeight (-self:GetFrameY (self.lastElement))
  RunNextFrame(function() self:FixScroll() end)
end

function ReforgeLite:GetReforgeTableIndex(src, dst)
  for k,v in ipairs(reforgeTable) do
    if v[1] == src and v[2] == dst then
      return k
    end
  end
  return UNFORGE_INDEX
end

local reforgeIdStringCache = setmetatable({}, {
  __index = function(self, key)
    local _, itemOptions = GetItemInfoFromHyperlink(key)
    if not itemOptions then return false end
    local reforgeId = select(10, LinkUtil.SplitLinkOptions(itemOptions))
    reforgeId = tonumber(reforgeId)
    if not reforgeId then
      reforgeId = UNFORGE_INDEX
    else
      reforgeId = reforgeId - REFORGE_TABLE_BASE
    end
    rawset(self, key, reforgeId)
    return reforgeId
  end
})

local function GetReforgeIDFromString(item)
  local id = reforgeIdStringCache[item]
  if id and id ~= UNFORGE_INDEX then
    return id
  end
end

local function GetReforgeID(slotId)
  if ignoredSlots[slotId] then return end
  local item = PLAYER_ITEM_DATA[slotId]
  if item and not item:IsItemEmpty() then
    local link = item:GetItemLink()
    if link then
      return GetReforgeIDFromString(link)
    end
  end
end

local function GetItemUpgradeLevel(item)
  if item:IsItemEmpty()
  or not item:HasItemLocation()
  or item:GetItemQuality() < Enum.ItemQuality.Rare
  or item:GetCurrentItemLevel() < 458 then
    return 0
  end

  local baseIlvl = C_Item.GetDetailedItemLevelInfo(item:GetItemID())
  if not baseIlvl then
    return 0
  end

  return (item:GetCurrentItemLevel() - baseIlvl) / 4
end

function ReforgeLite:UpdateItems()
  if not self.itemData or not self.pdb then
    return
  end
  self.pdb.itemsLocked = self.pdb.itemsLocked or {}
  local columnHasData = {}
  for _, v in ipairs (self.itemData) do
    local item = PLAYER_ITEM_DATA[v.slotId]
    local stats = {}
    local statsOrig = {}
    local reforgeSrc, reforgeDst
    v.itemInfo = v.itemInfo or {}
    local info = v.itemInfo
    wipe(info)
    if not item:IsItemEmpty() then
      info.link = item:GetItemLink()
      info.itemId = item:GetItemID()
      info.ilvl = item:GetCurrentItemLevel()
      info.itemGUID = item:GetItemGUID()
      info.upgradeLevel = GetItemUpgradeLevel(item)
      info.reforge = GetReforgeID(v.slotId)

      v.item = info.link
      v.itemId = info.itemId
      v.ilvl = info.ilvl
      v.itemGUID = info.itemGUID
      v.upgradeLevel = info.upgradeLevel
      v.reforge = info.reforge

      v.texture:SetTexture(item:GetItemIcon())
      local qualityColor = item:GetItemQualityColor()
      v.qualityColor = qualityColor
      v.quality:SetVertexColor(qualityColor.r, qualityColor.g, qualityColor.b)

      stats = GetItemStats(info, { ilvlCap = self.pdb.ilvlCap }) or {}
      statsOrig = GetItemStats(info) or {}
      if info.reforge then
        local srcId, dstId = unpack(reforgeTable[info.reforge])
        reforgeSrc, reforgeDst = self.itemStats[srcId].name, self.itemStats[dstId].name
        local amount = floor ((stats[reforgeSrc] or 0) * addonTable.REFORGE_COEFF)
        stats[reforgeSrc] = (stats[reforgeSrc] or 0) - amount
        stats[reforgeDst] = (stats[reforgeDst] or 0) + amount
      end
    else
      v.item = nil
      v.itemId = nil
      v.ilvl = nil
      v.reforge = nil
      v.itemGUID = nil
      v.qualityColor = nil
      v.upgradeLevel = nil
      v.texture:SetTexture (v.slotTexture)
      v.quality:SetVertexColor(1,1,1)
      stats = {}
      statsOrig = {}
    end

    v.quality:SetShown(not item:IsItemEmpty())

    local itemGUID = info.itemGUID
    v.locked:SetShown(itemGUID and self.pdb.itemsLocked[itemGUID])

    for j, s in ipairs (self.itemStats) do
      local statFont = v.stats[j]
      local fontColors = statFont.fontColors
      local currentValue = stats[s.name]
      local origValue = statsOrig[s.name]

      if (origValue and origValue ~= 0) or (currentValue and currentValue ~= 0) then
        columnHasData[j] = true
      end

      if currentValue and currentValue ~= 0 then
        statFont:SetText (currentValue)
        if s.name == reforgeSrc then
          statFont:SetTextColor (unpack(fontColors.red))
        elseif s.name == reforgeDst then
          statFont:SetTextColor (unpack(fontColors.green))
        else
          statFont:SetTextColor (unpack(fontColors.white))
        end
      else
        statFont:SetText ("-")
        statFont:SetTextColor (unpack(fontColors.grey))
      end
    end
  end

  local hasAnyData = false
  for _, hasData in pairs(columnHasData) do
    if hasData then
      hasAnyData = true
      break
    end
  end

  for i, v in ipairs (self.itemStats) do
    local hasData = columnHasData[i]
    if hasData or not hasAnyData then
      self.itemTable:SetColumnWidth(i, 55)
      if self.statHeaders and self.statHeaders[i] then
        self.statHeaders[i]:Show()
      end
      if self.statTotals[i] then
        self.statTotals[i]:Show()
      end
    else
      self.itemTable:SetColumnWidth(i, 0)
      if self.statHeaders and self.statHeaders[i] then
        self.statHeaders[i]:Hide()
      end
      if self.statTotals[i] then
        self.statTotals[i]:Hide()
      end
    end
    if self.statTotals[i] then
      self.statTotals[i]:SetText(v.getter())
    end
  end

  local _, minHeight, maxWidth, maxHeight = self:GetResizeBounds()
  local minWidth = self.itemTable:GetWidth() + 10 + 400 + 22
  self:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
  if self:GetWidth() < minWidth then
    self:SetWidth(minWidth)
  end

  for capIndex, cap in ipairs(self.pdb.caps) do
    for pointIndex, point in ipairs(cap.points) do
      local oldValue = point.value
      self:UpdateCapPreset (capIndex, pointIndex)
      if oldValue ~= point.value then
        self:ReorderCapPoint (capIndex, pointIndex)
      end
    end
  end
  self:RefreshMethodStats()
end

function ReforgeLite:UpdatePlayerSpecInfo()
  if not self.playerSpecTexture then return end
  local _, specName, _, icon = C_SpecializationInfo.GetSpecializationInfo(C_SpecializationInfo.GetSpecialization())
  if specName == "" then
    specName, icon = NONE, 132222
  end
  self.playerSpecTexture:SetTexture(icon)
  local activeSpecGroup = C_SpecializationInfo.GetActiveSpecGroup()
  for tier = 1, MAX_NUM_TALENT_TIERS do
    self.playerTalents[tier]:Show()
    local tierAvailable, selectedTalentColumn = GetTalentTierInfo(tier, activeSpecGroup, false, "player")
    if tierAvailable then
      if selectedTalentColumn > 0 then
        local talentInfo = C_SpecializationInfo.GetTalentInfo({
          tier = tier,
          column = selectedTalentColumn,
          groupIndex = activeSpecGroup,
          target = 'player'
        })
        self.playerTalents[tier]:SetTexture(talentInfo.icon)
        self.playerTalents[tier]:SetScript("OnEnter", function(f)
          GameTooltip:SetOwner(f, "ANCHOR_LEFT")
          GameTooltip:SetTalent(talentInfo.talentID, false, false, activeSpecGroup)
          GameTooltip:Show()
        end)
      else
        self.playerTalents[tier]:SetTexture(132222)
        self.playerTalents[tier]:SetScript("OnEnter", nil)
      end
    else
      self.playerTalents[tier]:Hide()
    end
  end
end

local queueUpdateEvents = {
  COMBAT_RATING_UPDATE = true,
  MASTERY_UPDATE = true,
  PLAYER_EQUIPMENT_CHANGED = true,
  FORGE_MASTER_ITEM_CHANGED = true,
  UNIT_AURA = "player",
  UNIT_SPELL_HASTE = "player",
}

local queueEventsRegistered = false
function ReforgeLite:RegisterQueueUpdateEvents()
  if queueEventsRegistered then return end
  for event, unitID in pairs(queueUpdateEvents) do
    if unitID == true then
      self:RegisterEvent(event)
    else
      self:RegisterUnitEvent(event, unitID)
    end
  end
  queueEventsRegistered = true
end

function ReforgeLite:UnregisterQueueUpdateEvents()
  if not queueEventsRegistered then return end
  for event in pairs(queueUpdateEvents) do
    self:UnregisterEvent(event)
  end
  queueEventsRegistered = false
end

function ReforgeLite:QueueUpdate()
  local time = GetTime()
  if self.lastRan == time then return end
  self.lastRan = time
  RunNextFrame(function()
    self:UpdateItems()
    self:RefreshMethodWindow()
  end)
end

--------------------------------------------------------------------------

function ReforgeLite:CreateMethodWindow()
  self.methodWindow = CreateFrame ("Frame", "ReforgeLiteMethodWindow", UIParent, "BackdropTemplate")
  self.methodWindow:Hide()
  self.methodWindow:SetFrameStrata ("DIALOG")
  self.methodWindow:SetToplevel(true)
  self.methodWindow:ClearAllPoints ()
  self.methodWindow:SetSize(250, 480)
  if self.db.methodWindowLocation then
    self.methodWindow:SetPoint (SafeUnpack(self.db.methodWindowLocation))
  else
    self.methodWindow:SetPoint ("CENTER", self, "CENTER")
  end
  self.methodWindow.backdropInfo = self.backdropInfo
  self.methodWindow:ApplyBackdrop()

  self.methodWindow.titlebar = self.methodWindow:CreateTexture(nil,"BACKGROUND")
  self.methodWindow.titlebar:SetPoint("TOPLEFT",self.methodWindow,"TOPLEFT",3,-3)
  self.methodWindow.titlebar:SetPoint("TOPRIGHT",self.methodWindow,"TOPRIGHT",-3,-3)
  self.methodWindow.titlebar:SetHeight(20)
  self.methodWindow.SetFrameActive = self.SetFrameActive
  self.methodWindow:SetFrameActive(true)

  self.methodWindow:SetBackdropColor (self:GetBackdropColor())
  self.methodWindow:SetBackdropBorderColor (self:GetBackdropBorderColor())

  self.methodWindow:EnableMouse (true)
  self.methodWindow:SetMovable (true)
  self.methodWindow:SetScript ("OnMouseDown", function (window, arg)
    self:SetNewTopWindow(window)
    if arg == "LeftButton" then
      window:StartMoving ()
      window.moving = true
    end
  end)
  self.methodWindow:SetScript ("OnMouseUp", function (window)
    if window.moving then
      window:StopMovingOrSizing ()
      window.moving = false
      self.db.methodWindowLocation = SafePack(window:GetPoint())
    end
  end)
  tinsert(UISpecialFrames, self.methodWindow:GetName()) -- allow closing with escape
  tinsert(RFL_FRAMES, self.methodWindow)

  self.methodWindow.title = self.methodWindow:CreateFontString (nil, "OVERLAY", "GameFontNormal")
  self.methodWindow.title:SetTextColor (1, 1, 1)
  self.methodWindow.title.RefreshText = function(frame)
    frame:SetFormattedText(L["Apply %s Output"], self.pdb.methodOrigin)
  end
  self.methodWindow.title:RefreshText()
  self.methodWindow.title:SetPoint ("TOPLEFT", 12, self.methodWindow.title:GetHeight()-self.methodWindow.titlebar:GetHeight())

  self.methodWindow.close = CreateFrame ("Button", nil, self.methodWindow, "UIPanelCloseButtonNoScripts")
  self.methodWindow.close:SetPoint ("TOPRIGHT")
  self.methodWindow.close:SetSize(28, 28)
  self.methodWindow.close:SetScript ("OnClick", function (btn)
    btn:GetParent():Hide()
  end)
  self.methodWindow:SetScript ("OnShow", function (frame)
    self:SetNewTopWindow(frame)
    self:RefreshMethodWindow()
    self:RegisterQueueUpdateEvents()
  end)
  self.methodWindow:SetScript ("OnHide", function ()
    if self:IsShown() then
      self:SetNewTopWindow(self)
    else
      self:UnregisterQueueUpdateEvents()
    end
  end)

  self.methodWindow.itemTable = GUI:CreateTable (ITEM_SLOT_COUNT + 1, 3, 0, 0, nil, self.methodWindow)
  self.methodWindow.itemTable:SetPoint ("TOPLEFT", self.methodWindow.title, "BOTTOMLEFT", 0, -12)
  self.methodWindow.itemTable:SetRowHeight (26)
  self.methodWindow.itemTable:SetColumnWidth (1, ITEM_SIZE)
  self.methodWindow.itemTable:SetColumnWidth (2, ITEM_SIZE + 2)
  self.methodWindow.itemTable:SetColumnWidth (3, 274 - ITEM_SIZE * 2)

  self.methodOverride = {}
  for i = 1, ITEM_SLOT_COUNT do
    self.methodOverride[i] = 0
  end

  self.methodWindow.items = {}
  for i, v in ipairs (self.itemSlots) do
    self.methodWindow.items[i] = CreateFrame ("Frame", nil, self.methodWindow.itemTable)
    self.methodWindow.items[i].slot = v
    self.methodWindow.items[i]:ClearAllPoints ()
    self.methodWindow.items[i]:SetSize(ITEM_SIZE, ITEM_SIZE)
    self.methodWindow.itemTable:SetCell (i, 2, self.methodWindow.items[i])
    self.methodWindow.items[i]:EnableMouse (true)
    self.methodWindow.items[i]:RegisterForDrag("LeftButton")
    self.methodWindow.items[i]:SetScript ("OnEnter", function (itemSlot)
      GameTooltip:SetOwner(itemSlot, "ANCHOR_LEFT")
      if itemSlot.item then
        GameTooltip:SetInventoryItem("player", itemSlot.slotId)
      else
        GameTooltip:SetText(_G[itemSlot.slot:upper()])
      end
      GameTooltip:Show()
    end)
    self.methodWindow.items[i]:SetScript ("OnLeave", GameTooltip_Hide)
    self.methodWindow.items[i]:SetScript ("OnDragStart", function (itemSlot)
      if itemSlot.item and ReforgeFrameIsVisible() then
        PickupInventoryItem(itemSlot.slotId)
      end
    end)
    self.methodWindow.items[i].slotId, self.methodWindow.items[i].slotTexture = GetInventorySlotInfo(v)
    self.methodWindow.items[i].texture = self.methodWindow.items[i]:CreateTexture (nil, "OVERLAY")
    self.methodWindow.items[i].texture:SetAllPoints (self.methodWindow.items[i])
    self.methodWindow.items[i].texture:SetTexture (self.methodWindow.items[i].slotTexture)

    self.methodWindow.items[i].quality = self.methodWindow.items[i]:CreateTexture(nil, "OVERLAY")
    self.methodWindow.items[i].quality:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    self.methodWindow.items[i].quality:SetBlendMode("ADD")
    self.methodWindow.items[i].quality:SetAlpha(0.75)
    self.methodWindow.items[i].quality:SetSize(44,44)
    self.methodWindow.items[i].quality:SetPoint("CENTER", self.methodWindow.items[i])

    self.methodWindow.items[i].reforge = self.methodWindow.itemTable:CreateFontString (nil, "OVERLAY", "GameFontNormal")
    self.methodWindow.itemTable:SetCell (i, 3, self.methodWindow.items[i].reforge, "LEFT")
    self.methodWindow.items[i].reforge:SetTextColor (1, 1, 1)
    self.methodWindow.items[i].reforge:SetText ("")

    self.methodWindow.items[i].check = GUI:CreateCheckButton (self.methodWindow.itemTable, "", false,
      function (val) self.methodOverride[i] = (val and 1 or -1) self:UpdateMethodChecks () end, true)
    self.methodWindow.itemTable:SetCell (i, 1, self.methodWindow.items[i].check)
  end
  self.methodWindow.reforge = GUI:CreatePanelButton (self.methodWindow, REFORGE, function(btn) self:DoReforge() end)
  self.methodWindow.reforge:SetSize(114, 22)
  self.methodWindow.reforge:SetPoint ("BOTTOMLEFT", 12, 12)
  self.methodWindow.reforge:SetMotionScriptsWhileDisabled(true)
  GUI:SetTooltip (self.methodWindow.reforge, function()
    if not ReforgeFrameIsVisible() then
      return L["Reforging window must be open"]
    end
  end)

  self.methodWindow.cost = CreateFrame ("Frame", "ReforgeLiteReforgeCost", self.methodWindow, "SmallMoneyFrameTemplate")
  MoneyFrame_SetType (self.methodWindow.cost, "REFORGE")
  self.methodWindow.cost:SetPoint ("LEFT", self.methodWindow.reforge, "RIGHT", 5, 0)

  self.methodWindow.AttachToReforgingFrame = function(frame)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", ReforgingFrame, "RIGHT")
  end

  self:RefreshMethodWindow()
end

function ReforgeLite:RefreshMethodWindow()
  if not self.methodWindow then
    return
  end
  self.methodWindow.title:RefreshText()
  for i = 1, ITEM_SLOT_COUNT do
    self.methodOverride[i] = 0
  end

  for i, v in ipairs (self.methodWindow.items) do
    local item = PLAYER_ITEM_DATA[v.slotId]
    if not item:IsItemEmpty() then
      v.itemInfo = v.itemInfo or {}
      wipe(v.itemInfo)
      v.itemInfo.link = item:GetItemLink()
      v.itemInfo.itemId = item:GetItemID()
      v.itemInfo.ilvl = item:GetCurrentItemLevel()
      v.itemInfo.itemGUID = item:GetItemGUID()
      v.itemInfo.upgradeLevel = GetItemUpgradeLevel(item)
      v.itemInfo.reforge = GetReforgeID(v.slotId)

      v.item = v.itemInfo.link
      v.texture:SetTexture(item:GetItemIcon())
      v.qualityColor = item:GetItemQualityColor()
      v.quality:SetVertexColor(v.qualityColor.r, v.qualityColor.g, v.qualityColor.b)
      v.quality:Show()
    else
      v.itemInfo = nil
      v.item = nil
      v.texture:SetTexture (v.slotTexture)
      v.qualityColor = nil
      v.quality:SetVertexColor(1,1,1)
      v.quality:Hide()
    end
    local slotInfo = self.pdb.method.items[i]
    if slotInfo.reforge then
      v.reforge:SetFormattedText("%d %s > %s", slotInfo.amount, self.itemStats[slotInfo.src].long, self.itemStats[slotInfo.dst].long)
      v.reforge:SetTextColor (1, 1, 1)
    else
      v.reforge:SetText (L["No reforge"])
      v.reforge:SetTextColor (0.7, 0.7, 0.7)
    end
  end
  self.methodWindow.title:RefreshText()
  self:UpdateMethodChecks ()
end

function ReforgeLite:ShowMethodWindow(attachToReforge)
  if not self.methodWindow then
    self:CreateMethodWindow()
  end

  GUI:ClearFocus()
  if self.methodWindow:IsShown() then
    self:SetNewTopWindow(self.methodWindow)
  else
    self.methodWindow:Show()
  end
  if attachToReforge and self.methodWindow.AttachToReforgingFrame then
    self.methodWindow:AttachToReforgingFrame()
  end
end

local function IsReforgeMatching (slotId, reforge, override)
  return override == 1 or reforge == GetReforgeID(slotId)
end

function ReforgeLite:UpdateMethodChecks ()
  local method = self.pdb and self.pdb.method
  local cost = 0
  local anyDiffer = false

  if method and self.itemData then
    local overrides = self.methodOverride
    for index, slotData in ipairs(self.itemData) do
      local methodItem = method.items and method.items[index]
      if methodItem then
        local override = overrides and overrides[index] or 0
        local item = PLAYER_ITEM_DATA[slotData.slotId]
        local isMatching = item:IsItemEmpty() or IsReforgeMatching(slotData.slotId, methodItem.reforge, override)
        if self.methodWindow and self.methodWindow.items and self.methodWindow.items[index] then
          local windowItem = self.methodWindow.items[index]
          if not item:IsItemEmpty() then
            windowItem.itemInfo = windowItem.itemInfo or {}
            wipe(windowItem.itemInfo)
            windowItem.itemInfo.link = item:GetItemLink()
            windowItem.itemInfo.itemId = item:GetItemID()
            windowItem.itemInfo.ilvl = item:GetCurrentItemLevel()
            windowItem.itemInfo.itemGUID = item:GetItemGUID()
            windowItem.itemInfo.upgradeLevel = GetItemUpgradeLevel(item)
            windowItem.itemInfo.reforge = GetReforgeID(slotData.slotId)
            windowItem.item = windowItem.itemInfo.link
          else
            windowItem.itemInfo = nil
            windowItem.item = nil
          end
          windowItem.texture:SetTexture(item:GetItemIcon() or windowItem.slotTexture)
          windowItem.check:SetChecked(isMatching)
        end
        if not isMatching then
          anyDiffer = true
          if methodItem.reforge then
            local itemLink = item:GetItemLink()
            local itemCost = itemLink and select(11, C_Item.GetItemInfo(itemLink)) or 0
            cost = cost + (itemCost > 0 and itemCost or 100000)
          end
        end
      end
    end
  end

  local enoughMoney = anyDiffer and GetMoney() >= cost
  local canReforge = anyDiffer and ReforgeFrameIsVisible() and enoughMoney
  local reforgeInProgress = reforgeCo ~= nil
  local canClick = (canReforge or reforgeInProgress) and not self.computeInProgress

  if self.methodWindow then
    if self.methodWindow.cost then
      self.methodWindow.cost:SetShown(anyDiffer)
      SetMoneyFrameColorByFrame(self.methodWindow.cost, enoughMoney and "white" or "red")
      MoneyFrame_Update (self.methodWindow.cost, cost)
    end
    if self.methodWindow.reforge then
      self.methodWindow.reforge:SetEnabled(canClick)
    end
  end
  if self.methodCost then
    self.methodCost:SetShown(anyDiffer)
    SetMoneyFrameColorByFrame(self.methodCost, enoughMoney and "white" or "red")
    MoneyFrame_Update(self.methodCost, cost)
  end
  if self.methodReforge then
    self.methodReforge:SetEnabled(canClick)
  end
end

function ReforgeLite:SwapSpecProfiles()
  if not self.db.specProfiles then return end

  local currentSettings = {
    caps = DeepCopy(self.pdb.caps),
    weights = DeepCopy(self.pdb.weights),
  }

  if self.pdb.prevSpecSettings then
    if self.initialized then
      self:SetStatWeights(self.pdb.prevSpecSettings.weights, self.pdb.prevSpecSettings.caps or {})
    else
      self.pdb.weights = DeepCopy(self.pdb.prevSpecSettings.weights)
      self.pdb.caps = DeepCopy(self.pdb.prevSpecSettings.caps)
    end
  end

  self.pdb.prevSpecSettings = currentSettings
end

--------------------------------------------------------------------------

local function ClearReforgeWindow()
  ClearCursor()
  C_Reforge.SetReforgeFromCursorItem ()
  ClearCursor()
end

local reforgeCo

function ReforgeLite:DoReforge()
  if self.pdb.method and self.methodWindow and ReforgeFrameIsVisible() then
    if reforgeCo then
      self:StopReforging()
    else
      ClearReforgeWindow()
      self.methodWindow.reforge:SetText (CANCEL)
      if self.methodReforge then
        self.methodReforge:SetText(CANCEL)
      end
      reforgeCo = coroutine.create( function() self:DoReforgeUpdate() end )
      coroutine.resume(reforgeCo)
    end
  end
end

function ReforgeLite:StopReforging()
  if reforgeCo then
    reforgeCo = nil
    ClearReforgeWindow()
    collectgarbage()
  end
  if self.methodWindow then
    self.methodWindow.reforge:SetText(REFORGE)
  end
  if self.methodReforge then
    self.methodReforge:SetText(REFORGE)
  end
  self:UpdateMethodChecks()
end

function ReforgeLite:ContinueReforge()
  if not reforgeCo then
    return
  end

  if not (self.pdb.method and self.methodWindow and ReforgeFrameIsVisible()) then
    self:StopReforging()
    return
  end

  coroutine.resume(reforgeCo)
end

function ReforgeLite:DoReforgeUpdate()
  if self.methodWindow then
    for slotId, slotInfo in ipairs(self.methodWindow.items) do
      local newReforge = self.pdb.method.items[slotId].reforge
      if slotInfo.item and not IsReforgeMatching(slotInfo.slotId, newReforge, self.methodOverride[slotId]) then
        PickupInventoryItem(slotInfo.slotId)
        C_Reforge.SetReforgeFromCursorItem()
        if newReforge then
          local id = UNFORGE_INDEX
          local stats = GetItemStats(slotInfo.itemInfo or self.itemData[slotId].itemInfo, { ilvlCap = self.pdb.ilvlCap })
          for s, reforgeInfo in ipairs(reforgeTable) do
            local srcstat, dststat = unpack(reforgeInfo)
            if (stats[self.itemStats[srcstat].name] or 0) ~= 0 and (stats[self.itemStats[dststat].name] or 0) == 0 then
              id = id + 1
            end
            if srcstat == self.pdb.method.items[slotId].src and dststat == self.pdb.method.items[slotId].dst then
              C_Reforge.ReforgeItem (id)
              coroutine.yield()
            end
          end
        elseif GetReforgeID(slotInfo.slotId) then
          C_Reforge.ReforgeItem (UNFORGE_INDEX)
          coroutine.yield()
        end
      end
    end
  end
  self:StopReforging()
end

--------------------------------------------------------------------------

local function HandleTooltipUpdate(tip)
  if not ReforgeLite.db.updateTooltip then return end
  local _, item = tip:GetItem()
  if not item then return end
  local reforgeId = GetReforgeIDFromString(item)
  if not reforgeId then return end
  for _, region in pairs({tip:GetRegions()}) do
    if region:GetObjectType() == "FontString" and region:GetText() == REFORGED then
      local srcId, destId = unpack(reforgeTable[reforgeId])
      region:SetFormattedText("%s (%s > %s)", REFORGED, ReforgeLite.itemStats[srcId].long, ReforgeLite.itemStats[destId].long)
      return
    end
  end
end

function ReforgeLite:HookTooltipScripts()
  if self.tooltipsHooked then return end
  local tooltips = {
    "GameTooltip",
    "ShoppingTooltip1",
    "ShoppingTooltip2",
    "ItemRefTooltip",
    "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2",
  }
  for _, tooltipName in ipairs(tooltips) do
    local tooltip = _G[tooltipName]
    if tooltip then
      tooltip:HookScript("OnTooltipSetItem", HandleTooltipUpdate)
    end
  end
  self.tooltipsHooked = true
end

--------------------------------------------------------------------------

function ReforgeLite:OnEvent(event, ...)
  if self[event] then
    self[event](self, ...)
  end
  if queueUpdateEvents[event] then
    self:QueueUpdate()
  end
end

function ReforgeLite:Initialize()
  if not self.initialized then
    self:CreateFrame()
    self.initialized = true
  end
end

function ReforgeLite:OnShow()
  self:Initialize()
  self:SetNewTopWindow()
  self:UpdateItems()
  self:RegisterQueueUpdateEvents()
end

function ReforgeLite:OnHide()
  if self.methodWindow and self.methodWindow:IsShown() then
    self:SetNewTopWindow(self.methodWindow)
    self.methodWindow:SetFrameActive(true)
  else
    self:UnregisterQueueUpdateEvents()
  end
end

function ReforgeLite:OnCommand (cmd)
  if InCombatLockdown() then print(ERROR_CAPS, ERR_AFFECTING_COMBAT) return end
  self:Show ()
end

function ReforgeLite:FORGE_MASTER_ITEM_CHANGED()
  self:ContinueReforge()
end

function ReforgeLite:FORGE_MASTER_OPENED()
  if self.db.openOnReforge and not self:IsShown() and (not self.methodWindow or not self.methodWindow:IsShown()) then
    self.autoOpened = true
    self:Show()
  end
  if self.methodWindow then
    self:RefreshMethodWindow()
  end
  self:CreateImportButton()
  self:StopReforging()
end

function ReforgeLite:FORGE_MASTER_CLOSED()
  if self.autoOpened then
    RFL_FRAMES:CloseAll()
    self.autoOpened = nil
  end
  self:StopReforging()
end

function ReforgeLite:PLAYER_REGEN_DISABLED()
  RFL_FRAMES:CloseAll()
end

local currentSpec -- hack because this event likes to fire twice
function ReforgeLite:ACTIVE_TALENT_GROUP_CHANGED(curr)
  if currentSpec ~= curr then
    currentSpec = curr
    self:SwapSpecProfiles()
  end
end

function ReforgeLite:PLAYER_SPECIALIZATION_CHANGED(unitId)
  if unitId == 'player' then
    self:GetConversion()
    self:UpdatePlayerSpecInfo()
  end
end

function ReforgeLite:PLAYER_ENTERING_WORLD()
  self:GetConversion()
end

function ReforgeLite:PLAYER_AVG_ITEM_LEVEL_UPDATE()
  self.itemLevel:SetFormattedText(CHARACTER_LINK_ITEM_LEVEL_TOOLTIP, select(2,GetAverageItemLevel()))
end

function ReforgeLite:ADDON_LOADED (addon)
  if addon ~= addonName then return end
  self:Hide()
  self:UpgradeDB()

  local db = LibStub("AceDB-3.0"):New(addonName.."DB", DefaultDB)

  self.db = db.global
  self.pdb = db.char
  self.cdb = db.class

  if self.db then
    self.db.methodAlternativeCount = nil
  end

  self:SetCoreSpeedPreset(self.db and self.db.coreSpeedPreset)

  while #self.pdb.caps > #DefaultDB.char.caps do
    tremove(self.pdb.caps)
  end
  while #self.pdb.caps < NUM_CAPS do
    tinsert(self.pdb.caps, CreateDefaultCap())
  end
  for i = 1, #self.pdb.caps do
    self.pdb.caps[i].points = self.pdb.caps[i].points or {}
  end

  self.conversion = setmetatable({}, {
    __index = function(t, k)
      local value = {}
      rawset(t, k, value)
      return value
    end,
  })

  if self.db.updateTooltip then
    self:HookTooltipScripts()
  end
  self:RegisterEvent("FORGE_MASTER_OPENED")
  self:RegisterEvent("FORGE_MASTER_CLOSED")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
  if self.db.specProfiles then
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  end
  self:UnregisterEvent("ADDON_LOADED")

  self:SetScript("OnShow", self.OnShow)
  self:SetScript("OnHide", self.OnHide)

  for k, v in ipairs({ addonName, "reforge", REFORGE:lower(), "rfl" }) do
    _G["SLASH_"..addonName:upper()..k] = "/" .. v
  end
  SlashCmdList[addonName:upper()] = function(...) self:OnCommand(...) end
end

ReforgeLite:SetScript ("OnEvent", ReforgeLite.OnEvent)
ReforgeLite:RegisterEvent ("ADDON_LOADED")
