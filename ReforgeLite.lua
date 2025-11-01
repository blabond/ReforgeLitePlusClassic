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

if not addonTable.L then
  local translations = {}
  local lower = string.lower
  addonTable.L = setmetatable(translations, {
    __index = function(self, key)
      if type(key) == "string" then
        local lowerKey = lower(key)
        if lowerKey ~= key then
          local lowerValue = rawget(self, lowerKey)
          if lowerValue ~= nil then
            rawset(self, key, lowerValue)
            return lowerValue
          end
        end
      end

      rawset(self, key, key or "")
      return self[key]
    end,
    __newindex = function(self, key, value)
      rawset(self, key, value)
      if type(key) == "string" then
        local lowerKey = lower(key)
        if lowerKey ~= key then
          rawset(self, lowerKey, value)
        end
      end
    end,
  })
end

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

addonTable.printLog = {}
local gprint = print
local function print(...)
    local message = strjoin(" ", date("[%X]:"), tostringall(...))
    tinsert(addonTable.printLog, message)
    gprint("|cff33ff99"..addonName.."|r:", ...)
end
addonTable.print = print

local CopyTableShallow = addonTable.CopyTableShallow

local GetBaseItemStats = GetItemStats

do

  local floor = math.floor
  local tonumber = tonumber

  local RandPropPoints = addonTable.RandPropPoints or {}
  local ItemUpgradeStats = addonTable.ItemUpgradeStats or {}
  local ItemStatsRef = addonTable.ItemStatsRef or {}

  local C_Item = C_Item
  local GetItemInfo = GetItemInfo

  function addonTable.GetRandPropPoints(iLvl, t)
      return (RandPropPoints[iLvl] and RandPropPoints[iLvl][t] or 0)
  end

  local function EnsureItemInfoTable(itemInfoOrLink)
      local itemInfo
      if type(itemInfoOrLink) == "table" then
          itemInfo = itemInfoOrLink
      elseif itemInfoOrLink then
          itemInfo = { link = itemInfoOrLink }
      end
      if not itemInfo then
          return
      end

      if itemInfo.link and not itemInfo.itemId and C_Item and C_Item.GetItemInfoInstant then
          local itemId = C_Item.GetItemInfoInstant(itemInfo.link)
          if itemId then
              itemInfo.itemId = itemInfo.itemId or itemId
          end
      end

      return itemInfo
  end

  local ITEM_LINK_UPGRADE_PATTERN = "item:(%d+):%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:%d+:%d+:(%d+)"

  local ItemUpgrade = {
      [1]   =  8, -- 1/1
      [373] =  4, -- 1/2
      [374] =  8, -- 2/2
      [375] =  4, -- 1/3
      [376] =  4, -- 2/3
      [377] =  4, -- 3/3
      [378] =  7, -- 1/1
      [379] =  4, -- 1/2
      [380] =  4, -- 2/2
      [445] =  0, -- 0/2
      [446] =  4, -- 1/2
      [447] =  8, -- 2/2
      [451] =  0, -- 0/1
      [452] =  8, -- 1/1
      [453] =  0, -- 0/2
      [454] =  4, -- 1/2
      [455] =  8, -- 2/2
      [456] =  0, -- 0/1
      [457] =  8, -- 1/1
      [458] =  0, -- 0/4
      [459] =  4, -- 1/4
      [460] =  8, -- 2/4
      [461] = 12, -- 3/4
      [462] = 16, -- 4/4
      [465] =  0, -- 0/2
      [466] =  4, -- 1/2
      [467] =  8, -- 2/2
      [468] =  0, -- 0/4
      [469] =  4, -- 1/4
      [470] =  8, -- 2/4
      [471] = 12, -- 3/4
      [472] = 16, -- 4/4
  }

  local function GetLinkUpgradeData(link)
      if type(link) ~= "string" then
          return
      end

      local itemId, upgradeId = link:match(ITEM_LINK_UPGRADE_PATTERN)
      if not itemId then
          return
      end

      itemId = tonumber(itemId)
      upgradeId = tonumber(upgradeId)

      local upgradeDelta = upgradeId and ItemUpgrade[upgradeId]

      return itemId, upgradeId, upgradeDelta
  end

  local function NormalizeOverrides(itemInfo, arg1, arg2)
      local ilvlCap, upgradeLevel

      if type(arg1) == "table" then
          ilvlCap = tonumber(arg1.ilvlCap)
          upgradeLevel = tonumber(arg1.upgradeLevel or arg1[1])
      elseif type(arg1) == "number" then
          if type(arg2) == "number" then
              ilvlCap = arg1
              upgradeLevel = arg2
          else
              upgradeLevel = arg1
          end
      end

      if upgradeLevel == nil and type(arg2) == "number" then
          upgradeLevel = arg2
      end

      if itemInfo then
          if ilvlCap == nil then
              ilvlCap = tonumber(itemInfo.ilvlCap)
          end
          if upgradeLevel == nil then
              upgradeLevel = tonumber(itemInfo.upgradeLevel)
          end
      end

      if upgradeLevel and upgradeLevel < 0 then
          upgradeLevel = 0
      end
      if ilvlCap and ilvlCap < 0 then
          ilvlCap = 0
      end

      return ilvlCap, upgradeLevel
  end

  addonTable.EnsureItemInfoTable = EnsureItemInfoTable
  addonTable.NormalizeOverrides = NormalizeOverrides
  addonTable.GetLinkUpgradeData = GetLinkUpgradeData
  _G.EnsureItemInfoTable = EnsureItemInfoTable
  _G.NormalizeOverrides = NormalizeOverrides

  local function SafeGetDetailedItemLevelInfo(...)
      if not (C_Item and C_Item.GetDetailedItemLevelInfo) then
          return
      end

      local numericArgs, otherArgs = {}, {}
      local argCount = select("#", ...)
      for index = 1, argCount do
          local arg = select(index, ...)
          if arg ~= nil then
              if type(arg) == "number" then
                  numericArgs[#numericArgs + 1] = arg
              else
                  otherArgs[#otherArgs + 1] = arg
              end
          end
      end

      local function Evaluate(handle)
          local ok, effective, preview, base = pcall(C_Item.GetDetailedItemLevelInfo, handle)
          if ok then
              local best = base or preview or effective
              if (best and best > 0) or (effective and effective > 0) then
                  best = best or effective
                  return {
                      best = best,
                      effective = effective,
                      preview = preview,
                      base = base,
                  }
              end
          end
      end

      local fallback

      local function Consider(handle)
          local result = Evaluate(handle)
          if not result then
              return
          end

          if result.base and result.base > 0 then
              return result
          end

          if not fallback then
              fallback = result
          end
      end

      for index = 1, #numericArgs do
          local candidate = Consider(numericArgs[index])
          if candidate then
              return candidate.best, candidate.effective, candidate.preview, candidate.base
          end
      end

      for index = 1, #otherArgs do
          local candidate = Consider(otherArgs[index])
          if candidate then
              return candidate.best, candidate.effective, candidate.preview, candidate.base
          end
      end

      if fallback then
          return fallback.best, fallback.effective, fallback.preview, fallback.base
      end
  end

  addonTable.SafeGetDetailedItemLevelInfo = SafeGetDetailedItemLevelInfo

  local function FetchBaseItemLevel(itemLocation, itemLink, itemId)
      local best, effective, _, base = SafeGetDetailedItemLevelInfo(itemId, itemLocation, itemLink)
      if base and base > 0 then
          return base
      end

      if itemLink then
          local _, _, upgradeDelta = GetLinkUpgradeData(itemLink)
          if upgradeDelta and upgradeDelta > 0 then
              local sourceLevel = effective or best
              if sourceLevel and sourceLevel > 0 then
                  local derived = sourceLevel - upgradeDelta
                  if derived > 0 then
                      return derived
                  end
              end
          end
      end

      return best or effective
  end

  local function ResolveBaseItemLevel(itemInfo)
      if not itemInfo then
          return 0
      end

      local baseIlvl = tonumber(itemInfo.baseIlvl) or tonumber(itemInfo.ilvlBase)
      if baseIlvl and baseIlvl > 0 then
          return floor(baseIlvl + 0.5)
      end

      local itemId = itemInfo.itemId
      if not itemId and itemInfo.link and C_Item and C_Item.GetItemInfoInstant then
          itemId = C_Item.GetItemInfoInstant(itemInfo.link)
      end

      local baseFromAPI = FetchBaseItemLevel(itemInfo.itemLocation, itemInfo.link, itemId)
      local current = tonumber(itemInfo.ilvl)
      local upgrade = tonumber(itemInfo.upgradeLevel)
      if upgrade and upgrade < 0 then
          upgrade = 0
      end

      local candidate = baseFromAPI
      if current and current > 0 and upgrade and upgrade > 0 then
          local derived = current - upgrade * 4
          if derived > 0 then
              if not candidate or candidate <= 0 or derived < candidate then
                  candidate = derived
              end
          end
      end

      if candidate and candidate > 0 then
          return floor(candidate + 0.5)
      end

      if itemInfo.link then
          local _, _, _, infoLevel = GetItemInfo(itemInfo.link)
          if infoLevel and infoLevel > 0 then
              return floor(infoLevel + 0.5)
          end
      end

      return 0
  end

  addonTable.ResolveBaseItemLevel = ResolveBaseItemLevel

  local function DetermineUpgradeLevel(currentIlvl, baseIlvl, overrideUpgrade, storedUpgrade)
      if overrideUpgrade ~= nil then
          local coerced = tonumber(overrideUpgrade) or 0
          if coerced < 0 then
              coerced = 0
          end
          return floor(coerced + 0.5), true
      end

      if storedUpgrade ~= nil then
          local coerced = tonumber(storedUpgrade) or 0
          if coerced < 0 then
              coerced = 0
          end
          return floor(coerced + 0.5), false
      end

      if currentIlvl and baseIlvl and currentIlvl > baseIlvl then
          local diff = currentIlvl - baseIlvl
          if diff > 0.01 then
              return floor(diff / 4 + 0.5), false
          end
      end

      return 0, false
  end

  local function ComputeEffectiveItemLevel(itemInfo, ilvlCap, overrideUpgradeLevel, skipAutomaticUpgrade)
      if not itemInfo or not itemInfo.link then
          return nil, 0, 0
      end

      local linkItemId, _, linkUpgradeDelta = GetLinkUpgradeData(itemInfo.link)
      local itemId = tonumber(itemInfo.itemId) or linkItemId
      local upgradeDelta = linkUpgradeDelta

      local baseIlvl = tonumber(itemInfo.baseIlvl) or tonumber(itemInfo.ilvlBase) or 0
      local currentIlvl = tonumber(itemInfo.ilvl)

      local bestFromAPI, effectiveFromAPI, _, rawBase = SafeGetDetailedItemLevelInfo(itemId, itemInfo.itemLocation, itemInfo.link)

      if (not currentIlvl or currentIlvl <= 0) then
          if effectiveFromAPI and effectiveFromAPI > 0 then
              currentIlvl = effectiveFromAPI
          elseif bestFromAPI and bestFromAPI > 0 then
              currentIlvl = bestFromAPI
          end
      end

      if baseIlvl == 0 then
          if rawBase and rawBase > 0 then
              baseIlvl = rawBase
          elseif bestFromAPI and bestFromAPI > 0 then
              baseIlvl = bestFromAPI
          end
      end

      if upgradeDelta and upgradeDelta > 0 and currentIlvl and currentIlvl > 0 then
          local candidate = currentIlvl - upgradeDelta
          if candidate > 0 then
              if baseIlvl == 0 or baseIlvl >= currentIlvl or (currentIlvl - baseIlvl) < upgradeDelta - 0.25 then
                  baseIlvl = candidate
              end
          end
      end

      if baseIlvl == 0 and itemInfo.link and C_Item and C_Item.GetItemInfo then
          local _, _, _, infoLevel = C_Item.GetItemInfo(itemInfo.link)
          baseIlvl = infoLevel or 0
      end

      if baseIlvl == 0 and itemInfo.link then
          local _, _, _, infoLevel = GetItemInfo(itemInfo.link)
          if infoLevel and infoLevel > 0 then
              baseIlvl = infoLevel
          end
      end

      if baseIlvl == 0 and currentIlvl then
          if overrideUpgradeLevel and overrideUpgradeLevel > 0 then
              baseIlvl = currentIlvl - overrideUpgradeLevel * 4
          elseif itemInfo.upgradeLevel and tonumber(itemInfo.upgradeLevel) and tonumber(itemInfo.upgradeLevel) > 0 then
              baseIlvl = currentIlvl - tonumber(itemInfo.upgradeLevel) * 4
          elseif upgradeDelta and upgradeDelta > 0 then
              baseIlvl = currentIlvl - upgradeDelta
          else
              baseIlvl = currentIlvl
          end
      end

      if currentIlvl and currentIlvl > 0 and baseIlvl > currentIlvl then
          baseIlvl = currentIlvl
      end

      if baseIlvl and baseIlvl > 0 then
          baseIlvl = floor(baseIlvl + 0.5)
      else
          baseIlvl = 0
      end

      local effectiveIlvl = baseIlvl

      if overrideUpgradeLevel and overrideUpgradeLevel > 0 then
          effectiveIlvl = baseIlvl + overrideUpgradeLevel * 4
      elseif not skipAutomaticUpgrade then
          local storedUpgrade = tonumber(itemInfo.upgradeLevel)
          if storedUpgrade and storedUpgrade > 0 then
              effectiveIlvl = baseIlvl + storedUpgrade * 4
          elseif baseIlvl >= 458 and upgradeDelta and upgradeDelta > 0 then
              effectiveIlvl = baseIlvl + upgradeDelta
          elseif currentIlvl and currentIlvl > effectiveIlvl then
              effectiveIlvl = currentIlvl
          end
      elseif currentIlvl and currentIlvl > effectiveIlvl then
          effectiveIlvl = currentIlvl
      end

      if ilvlCap and ilvlCap > 0 and effectiveIlvl > ilvlCap then
          effectiveIlvl = ilvlCap
      end

      if effectiveIlvl and effectiveIlvl > 0 then
          effectiveIlvl = floor(effectiveIlvl + 0.5)
      else
          effectiveIlvl = 0
      end

      return itemId or tonumber(itemInfo.itemId) or 0, baseIlvl, effectiveIlvl
  end

  function addonTable.GetItemBaseAndUpgrade(itemInfoOrLink, overrides, upgradeOverride)
      local itemInfo = EnsureItemInfoTable(itemInfoOrLink)
      if not itemInfo or not itemInfo.link then
          return 0, 0, 0, 0
      end

      local ilvlCap, overrideUpgradeLevel = NormalizeOverrides(itemInfo, overrides, upgradeOverride)

      local itemId, baseIlvl, effectiveIlvl = ComputeEffectiveItemLevel(itemInfo, ilvlCap, overrideUpgradeLevel)
      if not itemId and itemInfo.link and C_Item and C_Item.GetItemInfoInstant then
          itemId = C_Item.GetItemInfoInstant(itemInfo.link)
      end

      local currentIlvl = tonumber(itemInfo.ilvl)
      if currentIlvl and currentIlvl > 0 then
          currentIlvl = floor(currentIlvl + 0.5)
      else
          currentIlvl = nil
      end

      if baseIlvl and baseIlvl > 0 then
          baseIlvl = floor(baseIlvl + 0.5)
      else
          baseIlvl = ResolveBaseItemLevel(itemInfo)
      end

      if baseIlvl <= 0 and currentIlvl then
          baseIlvl = currentIlvl
      end

      local upgradeLevel, appliedOverride = DetermineUpgradeLevel(currentIlvl, baseIlvl, overrideUpgradeLevel, itemInfo.upgradeLevel)

      if upgradeLevel and upgradeLevel > 0 then
          effectiveIlvl = baseIlvl + upgradeLevel * 4
      end

      if (not effectiveIlvl or effectiveIlvl <= 0) and currentIlvl then
          effectiveIlvl = currentIlvl
      end

      if ilvlCap and ilvlCap > 0 and effectiveIlvl and effectiveIlvl > ilvlCap then
          effectiveIlvl = ilvlCap
          if baseIlvl > 0 then
              upgradeLevel = floor(((effectiveIlvl - baseIlvl) / 4) + 0.5)
              if upgradeLevel < 0 then
                  upgradeLevel = 0
              end
          end
      end

      if currentIlvl and baseIlvl > 0 and not appliedOverride then
          local diff = currentIlvl - baseIlvl
          if diff > (upgradeLevel or 0) * 4 + 0.01 then
              upgradeLevel = floor(diff / 4 + 0.5)
              effectiveIlvl = baseIlvl + upgradeLevel * 4
          end
      end

      if baseIlvl and baseIlvl > 0 then
          baseIlvl = floor(baseIlvl + 0.5)
      else
          baseIlvl = 0
      end

      upgradeLevel = floor((tonumber(upgradeLevel) or 0) + 0.5)
      if upgradeLevel < 0 then
          upgradeLevel = 0
      end

      if not effectiveIlvl or effectiveIlvl <= 0 then
          effectiveIlvl = baseIlvl + upgradeLevel * 4
      end

      if currentIlvl and currentIlvl > 0 and currentIlvl > effectiveIlvl then
          effectiveIlvl = currentIlvl
      end

      if effectiveIlvl < baseIlvl then
          effectiveIlvl = baseIlvl
      end

      itemInfo.baseIlvl = baseIlvl
      itemInfo.upgradeLevel = upgradeLevel
      itemInfo.effectiveIlvl = effectiveIlvl
      if effectiveIlvl and effectiveIlvl > 0 then
          itemInfo.ilvl = effectiveIlvl
      end
      if itemId and itemId ~= 0 then
          itemInfo.itemId = itemId
      elseif itemInfo.link and C_Item and C_Item.GetItemInfoInstant then
          local resolvedId = C_Item.GetItemInfoInstant(itemInfo.link)
          if resolvedId then
              itemId = resolvedId
              itemInfo.itemId = resolvedId
          end
      end

      return baseIlvl, upgradeLevel, effectiveIlvl, itemId or 0
  end

  _G.GetItemBaseAndUpgrade = addonTable.GetItemBaseAndUpgrade

  local function ComputeEffectiveItemLevelPublic(itemInfo, ilvlCap, overrideUpgradeLevel, skipAutomaticUpgrade)
      local itemId, baseIlvl, effectiveIlvl = ComputeEffectiveItemLevel(itemInfo, ilvlCap, overrideUpgradeLevel, skipAutomaticUpgrade)
      if skipAutomaticUpgrade and overrideUpgradeLevel == nil then
          effectiveIlvl = baseIlvl
      elseif overrideUpgradeLevel ~= nil and baseIlvl and baseIlvl > 0 then
          effectiveIlvl = baseIlvl + (overrideUpgradeLevel or 0) * 4
      end
      return itemId, baseIlvl, effectiveIlvl
  end

  addonTable.ComputeEffectiveItemLevel = ComputeEffectiveItemLevelPublic
  _G.ComputeEffectiveItemLevel = ComputeEffectiveItemLevelPublic

  function addonTable.GetCappedUpgradeLevel(baseIlvl, upgradeLevel, ilvlCap)
      upgradeLevel = tonumber(upgradeLevel) or 0
      if upgradeLevel < 0 then
          upgradeLevel = 0
      end

      baseIlvl = tonumber(baseIlvl) or 0
      if baseIlvl <= 0 then
          return upgradeLevel
      end

      ilvlCap = tonumber(ilvlCap)
      if not ilvlCap or ilvlCap <= 0 then
          return upgradeLevel
      end

      local maxUpgrade = floor((ilvlCap - baseIlvl) / 4)
      if maxUpgrade < 0 then
          maxUpgrade = 0
      end

      if upgradeLevel > maxUpgrade then
          upgradeLevel = maxUpgrade
      end

      return upgradeLevel
  end
end

local DeepCopy = addonTable.DeepCopy
local GetItemStats
local SafeGetDetailedItemLevelInfo = addonTable.SafeGetDetailedItemLevelInfo
local GetLinkUpgradeData = addonTable.GetLinkUpgradeData

if type(ReforgePlusLiteClassicDB) ~= "table" and type(ReforgeLiteLiteDB) == "table" then
  ReforgePlusLiteClassicDB = ReforgeLiteLiteDB
end
ReforgeLiteLiteDB = nil

local ITEM_SIZE = 24

local NUM_CAPS = 3
local EXACT_CAP_LIMIT = 2
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
local METHOD_ACTION_BUTTON_HEIGHT = 22
local METHOD_ALTERNATIVE_BUTTON_SPACING = 6
local METHOD_ALTERNATIVE_BUTTON_MIN_WIDTH = 72
local METHOD_ALTERNATIVE_COLUMN_SPACING = 8

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
    wowSimsPopupLocation = false,
    openOnReforge = true,
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

GUI.CreateStaticPopup("REFORGE_LITE_SAVE_PRESET", L["Enter the preset name"], function(popup)
  local text = popup:GetEditBox():GetText()
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
end, { hasEditBox = true, editBoxWidth = 240, dialogWidthPadding = 30 })

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

local hitStatWeightLabel
local hitResultLabel
local dodgeStatLabel
local masteryStatLabel

local function RefreshItemStatLabels()
  hitStatWeightLabel = addonTable.WEIGHT_HIT_LABEL or HIT
  hitResultLabel = addonTable.RESULT_HIT_LABEL or hitStatWeightLabel
  dodgeStatLabel = addonTable.STAT_DODGE_LABEL or STAT_DODGE
  masteryStatLabel = addonTable.STAT_MASTERY_LABEL or STAT_MASTERY

  local itemStats = ReforgeLite.itemStats
  if type(itemStats) == "table" then
    for _, stat in ipairs(itemStats) do
      if stat and stat.name == "ITEM_MOD_DODGE_RATING" then
        stat.tip = dodgeStatLabel
      elseif stat and stat.name == "ITEM_MOD_HIT_RATING" then
        stat.tip = hitStatWeightLabel
        stat.long = hitStatWeightLabel
        stat.resultLabel = hitResultLabel
      elseif stat and stat.name == "ITEM_MOD_MASTERY_RATING_SHORT" then
        stat.tip = masteryStatLabel
      end
    end
  end

  local statHeaders = ReforgeLite.statHeaders
  if type(statHeaders) == "table" then
    for index, header in ipairs(statHeaders) do
      local stat = itemStats and itemStats[index]
      if header and stat and header.SetText then
        header:SetText(stat.tip or "")
      end
    end
  end
end

RefreshItemStatLabels()

local function Stat(options)
  local function EscapePattern(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
  end
  local stat = {
    statId = options.statId,
    name = options.name,
    tip = options.tip,
    long = options.long,
    resultLabel = options.resultLabel,
    tooltipConstant = options.tooltipConstant,
    tooltipPrefix = options.tooltipPrefix,
    tooltipSuffix = options.tooltipSuffix,
    customTooltipPatterns = options.tooltipPatterns,
    getter = options.getter or function ()
      local rating = GetCombatRating(options.ratingId)
      if StatAdditives[options.ratingId] then
        rating = StatAdditives[options.ratingId](rating)
      end
      return rating
    end,
    mgetter = options.mgetter or function (method, orig)
      return (orig and method.orig_stats and method.orig_stats[options.statId]) or method.stats[options.statId]
    end,
  }

  function stat:getTooltipPatterns()
    if self.customTooltipPatterns then
      return self.customTooltipPatterns
    end

    local tooltipText = _G[self.tooltipConstant or self.name]
    if type(tooltipText) ~= "string" or tooltipText == "" then
      return nil
    end

    if self.generatedTooltipText ~= tooltipText then
      local escapedText = EscapePattern(tooltipText)
      local prefix = self.tooltipPrefix or "%+"
      local suffix = self.tooltipSuffix or "%+"

      self.generatedTooltipPatterns = {
        "^" .. prefix .. "([%d%.,%s]+)%s*" .. escapedText,
        "^" .. escapedText .. "%s*" .. suffix .. "([%d%.,%s]+)"
      }
      self.generatedTooltipText = tooltipText
    end

    return self.generatedTooltipPatterns
  end

  return stat
end

local ITEM_STATS = {
    Stat {
      statId = statIds.SPIRIT,
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
      end,
    },
    Stat {
      statId = statIds.DODGE,
      name = "ITEM_MOD_DODGE_RATING",
      tooltipConstant = "ITEM_MOD_DODGE_RATING_SHORT",
      tip = dodgeStatLabel,
      long = STAT_DODGE,
      ratingId = CR_DODGE,
    },
    Stat {
      statId = statIds.PARRY,
      name = "ITEM_MOD_PARRY_RATING",
      tooltipConstant = "ITEM_MOD_PARRY_RATING_SHORT",
      tip = STAT_PARRY,
      long = STAT_PARRY,
      ratingId = CR_PARRY,
    },
    Stat {
      statId = statIds.HIT,
      name = "ITEM_MOD_HIT_RATING",
      tooltipConstant = "ITEM_MOD_HIT_RATING_SHORT",
      tip = hitStatWeightLabel,
      long = ITEM_MOD_HIT_RATING_SHORT,
      resultLabel = hitResultLabel,
      getter = function()
        local hit = GetCombatRating(CR_HIT)
        if (ReforgeLite.conversion[statIds.EXP] or {})[statIds.HIT] then
          hit = hit + (GetCombatRating(CR_EXPERTISE) * ReforgeLite.conversion[statIds.EXP][statIds.HIT])
        end
        return hit
      end,
      mgetter = function (method, orig)
        return (orig and method.orig_stats and method.orig_stats[statIds.HIT]) or method.stats[statIds.HIT]
      end,
    },
    Stat {
      statId = statIds.CRIT,
      name = "ITEM_MOD_CRIT_RATING",
      tooltipConstant = "ITEM_MOD_CRIT_RATING_SHORT",
      tip = CRIT_ABBR,
      long = CRIT_ABBR,
      ratingId = CR_CRIT,
    },
    Stat {
      statId = statIds.HASTE,
      name = "ITEM_MOD_HASTE_RATING",
      tooltipConstant = "ITEM_MOD_HASTE_RATING_SHORT",
      tip = STAT_HASTE,
      long = STAT_HASTE,
      ratingId = CR_HASTE,
    },
    Stat {
      statId = statIds.EXP,
      name = "ITEM_MOD_EXPERTISE_RATING",
      tooltipConstant = "ITEM_MOD_EXPERTISE_RATING_SHORT",
      tip = EXPERTISE_ABBR,
      long = STAT_EXPERTISE,
      ratingId = CR_EXPERTISE,
    },
    Stat {
      statId = statIds.MASTERY,
      name = "ITEM_MOD_MASTERY_RATING_SHORT",
      tip = masteryStatLabel,
      long = STAT_MASTERY,
      ratingId = CR_MASTERY,
    },
}

local ITEM_STAT_COUNT = #ITEM_STATS
addonTable.itemStats = ITEM_STATS
addonTable.itemStatCount = ITEM_STAT_COUNT
ReforgeLite.itemStats = ITEM_STATS

RefreshItemStatLabels()

local REFORGE_TABLE_BASE = 112

local reforgeTable = {}
for srcIdx in ipairs(ITEM_STATS) do
  for dstIdx in ipairs(ITEM_STATS) do
    if srcIdx ~= dstIdx then
      tinsert(reforgeTable, {srcIdx, dstIdx})
    end
  end
end

ReforgeLite.reforgeTable = reforgeTable

local scanTooltip = CreateFrame("GameTooltip", "ReforgeLiteScanTooltip", nil, "GameTooltipTemplate")
local tooltipStatsCache = {}

local function SetTooltipFromItemInfo(itemInfo)
  scanTooltip:ClearLines()
  scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  if itemInfo.slotId then
    local success = scanTooltip:SetInventoryItem("player", itemInfo.slotId)
    if success then
      return true
    end
  end
  scanTooltip:SetHyperlink(itemInfo.link)
  return true
end

function addonTable.GetItemStatsFromTooltip(itemInfo)
  if type(itemInfo) ~= "table" or type(itemInfo.link) ~= "string" or itemInfo.link == "" then
    return {}
  end

  if itemInfo.ilvl and itemInfo.originalIlvl and itemInfo.ilvl == itemInfo.originalIlvl then
    return CopyTableShallow(GetBaseItemStats(itemInfo.link) or {})
  end

  local itemId = itemInfo.itemId
  local itemLevel = itemInfo.ilvl
  if itemId and itemLevel then
    local cachedByLevel = tooltipStatsCache[itemId]
    if cachedByLevel and cachedByLevel[itemLevel] then
      return CopyTableShallow(cachedByLevel[itemLevel])
    end
  end

  SetTooltipFromItemInfo(itemInfo)

  local stats = {}
  local itemStats = addonTable.itemStats or {}
  local foundStats = 0
  local maxStats = 2
  local srcName, destName

  local function CleanTooltipLine(text)
    if type(text) ~= "string" then
      return ""
    end

    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("%b()", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
  end

  local reforgeIndex = itemInfo.reforge
  if type(reforgeIndex) == "number" and reforgeIndex >= 1 then
    local reforgeEntry = reforgeTable[reforgeIndex]
    if reforgeEntry then
      local srcIndex, dstIndex = unpack(reforgeEntry)
      srcName = itemStats[srcIndex] and itemStats[srcIndex].name or nil
      destName = itemStats[dstIndex] and itemStats[dstIndex].name or nil
      if srcName and destName then
        maxStats = 3
      end
    end
  end

  for _, region in ipairs({scanTooltip:GetRegions()}) do
    if foundStats >= maxStats then
      break
    end
    if region.GetText then
      local text = CleanTooltipLine(region:GetText())
      if text ~= "" then
        for _, statInfo in ipairs(itemStats) do
          if not stats[statInfo.name] and statInfo.getTooltipPatterns then
            local tooltipPatterns = statInfo:getTooltipPatterns()
            if tooltipPatterns then
              local value
              for _, pattern in ipairs(tooltipPatterns) do
                value = text:match(pattern)
                if value then
                  break
                end
              end
              if value then
                local numericValue = tonumber((value:gsub("[^%d%-]", "")))
                if numericValue then
                  foundStats = foundStats + 1
                  stats[statInfo.name] = numericValue
                end
                break
              end
            end
          end
        end
      end
    end
  end

  scanTooltip:Hide()

  if srcName and destName and stats[srcName] and stats[destName] then
    stats[srcName] = stats[srcName] + stats[destName]
    stats[destName] = nil
  end

  if not next(stats) then
    return CopyTableShallow(GetBaseItemStats(itemInfo.link) or {})
  end

  if itemId and itemLevel then
    tooltipStatsCache[itemId] = tooltipStatsCache[itemId] or {}
    tooltipStatsCache[itemId][itemLevel] = CopyTableShallow(stats)
  end

  return CopyTableShallow(stats)
end

GetItemStats = addonTable.GetItemStatsFromTooltip

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

  c.Refresh = function(category)
    if category.expanded then
      for _, frame in pairs(category.frames) do
        if not frame.chidden then
          frame:Show()
        end
      end
      for _, anchor in pairs(category.anchors) do
        anchor.frame:SetPoint(anchor.point, anchor.rel, anchor.relPoint, anchor.x, anchor.y)
      end
    else
      for _, frame in pairs(category.frames) do
        frame:Hide()
      end
      for k, v in pairs (category.anchors) do
        v.frame:SetPoint (v.point, category.button, v.relPoint, v.x, v.y)
      end
    end

    category.button:UpdateTexture()
  end

  c.Toggle = function (category)
    category.expanded = not category.expanded
    self.pdb.categoryStates[name] = category.expanded
    category:Refresh()
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

local plusSign = (_G and _G.PLUS_SIGN) or "+"
local minusSign = (_G and _G.MINUS_SIGN) or "-"

local function FormatNumber(num)
  if type(num) ~= "number" then
    return tostring(num or "")
  end

  if num == 0 then
    return FormatLargeNumber(0)
  end

  local prefix = num > 0 and plusSign or minusSign
  local magnitude = abs(num)
  local rounded = floor(magnitude + 0.5)
  if abs(magnitude - rounded) < 0.01 then
    magnitude = rounded
    return prefix .. FormatLargeNumber(magnitude)
  end

  local decimalFormatted = string.format("%.2f", magnitude)
  local integerPart, fractionalPart = decimalFormatted:match("^(%d+)%.(%d+)$")
  if integerPart and fractionalPart then
    local formattedInteger = FormatLargeNumber(tonumber(integerPart))
    return string.format("%s%s.%s", prefix, formattedInteger, fractionalPart)
  end

  return prefix .. decimalFormatted
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
  text:SetText(FormatNumber(value - cur))
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

local function EnsureTableAutoWidthRespectsMinimums(table)
  if not table or type(table.AutoSizeColumns) ~= "function" or table._hasMinWidthHook then
    return
  end

  table._hasMinWidthHook = true

  local originalAutoSizeColumns = table.AutoSizeColumns
  table.AutoSizeColumns = function(tbl, columnIndex)
    originalAutoSizeColumns(tbl, columnIndex)

    local function enforceMinimum(colIndex)
      if not colIndex then
        return false
      end

      local desired = nil
      if tbl.minColumnWidth and tbl.minColumnWidth[colIndex] then
        desired = tbl.minColumnWidth[colIndex]
      end
      if not desired and tbl.defaultColumnWidth and tbl.defaultColumnWidth[colIndex] then
        desired = tbl.defaultColumnWidth[colIndex]
      end
      if not desired then
        return false
      end

      local current = tbl.colWidth and tbl.colWidth[colIndex]
      if current == "AUTO" or (type(current) == "number" and current < desired) then
        tbl.colWidth[colIndex] = desired
        return true
      end

      return false
    end

    local adjusted = false
    if columnIndex then
      adjusted = enforceMinimum(columnIndex) or adjusted
    else
      if tbl.autoWidthColumns then
        for colIndex, enabled in pairs(tbl.autoWidthColumns) do
          if enabled then
            adjusted = enforceMinimum(colIndex) or adjusted
          end
        end
      end
      if tbl.minColumnWidth then
        for colIndex in pairs(tbl.minColumnWidth) do
          adjusted = enforceMinimum(colIndex) or adjusted
        end
      end
    end

    if adjusted then
      tbl:OnUpdateFix()
    end
  end
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
  self.itemTable.defaultColumnWidth = self.itemTable.defaultColumnWidth or {}
  self.itemTable.minColumnWidth = self.itemTable.minColumnWidth or {}
  for index = 1, #self.itemStats do
    local defaultWidth = 45
    self.itemTable:SetColumnWidth(index, defaultWidth)
    self.itemTable.defaultColumnWidth[index] = defaultWidth
    local previousMin = self.itemTable.minColumnWidth[index] or 0
    if previousMin < defaultWidth then
      self.itemTable.minColumnWidth[index] = defaultWidth
    end
    autoColumns[#autoColumns + 1] = index
  end
  EnsureTableAutoWidthRespectsMinimums(self.itemTable)
  if #autoColumns > 0 then
    self.itemTable:EnableColumnAutoWidth(unpack(autoColumns))
  end

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

  local masteryColumnIndex = statIds.MASTERY
  local masteryHeader = self.statHeaders[masteryColumnIndex]
  if masteryHeader then
    local minWidth = math.ceil((masteryHeader:GetStringWidth() or 0) + 12)
    if minWidth > 0 then
      local previousMin = self.itemTable.minColumnWidth[masteryColumnIndex] or 0
      if minWidth > previousMin then
        self.itemTable.minColumnWidth[masteryColumnIndex] = minWidth
      end
      self.itemTable:AutoSizeColumns(masteryColumnIndex)
    end
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
  self.itemTable:SetCellText (#self.itemSlots + 1, 0, "", "CENTER", {1, 0.8, 0})
  for i, v in ipairs (self.itemStats) do
    self.itemTable:SetCellText (#self.itemSlots + 1, i, FormatLargeNumber(0), nil, {1, 0.8, 0})
    self.statTotals[i] = self.itemTable.cells[#self.itemSlots + 1][i]
  end

  self.statColumnShown = {}
  self.statColumnShownInitialized = false
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

function ReforgeLite:GetExactCapSelectionCount(excludeCapIndex, excludePointIndex)
  local count = 0
  for capIndex = 1, NUM_CAPS do
    local cap = self.pdb.caps and self.pdb.caps[capIndex]
    if cap and cap.points then
      for pointIndex, point in ipairs(cap.points) do
        if point.method == addonTable.StatCapMethods.Exactly then
          if not (capIndex == excludeCapIndex and pointIndex == excludePointIndex) then
            count = count + 1
          end
        end
      end
    end
  end
  return count
end

function ReforgeLite:CanUseExactCapMethod(capIndex, pointIndex)
  local cap = self.pdb.caps and self.pdb.caps[capIndex]
  local point = cap and cap.points and cap.points[pointIndex]
  if point and point.method == addonTable.StatCapMethods.Exactly then
    return true
  end
  return self:GetExactCapSelectionCount(capIndex, pointIndex) < EXACT_CAP_LIMIT
end

function ReforgeLite:GetCapMethodCounts(capIndex, excludePointIndex)
  local counts = {
    [addonTable.StatCapMethods.AtLeast] = 0,
    [addonTable.StatCapMethods.AtMost] = 0,
    [addonTable.StatCapMethods.Exactly] = 0,
  }

  local cap = self.pdb.caps and self.pdb.caps[capIndex]
  if not cap or not cap.points then
    return counts
  end

  for index, point in ipairs(cap.points) do
    if not excludePointIndex or index ~= excludePointIndex then
      if counts[point.method] ~= nil then
        counts[point.method] = counts[point.method] + 1
      end
    end
  end

  return counts
end

function ReforgeLite:CanAddCapPoint(capIndex)
  local cap = self.pdb.caps and self.pdb.caps[capIndex]
  if not cap or cap.stat == 0 then
    return false
  end

  cap.points = cap.points or {}
  local numPoints = #cap.points
  if numPoints == 0 then
    return true
  end

  if numPoints >= 2 then
    return false
  end

  for _, point in ipairs(cap.points) do
    if point.method == addonTable.StatCapMethods.Exactly then
      return false
    end
  end

  return true
end

function ReforgeLite:ShouldDisableCapMethodOption(capIndex, pointIndex, method, currentMethod)
  if method == addonTable.StatCapMethods.Exactly then
    return not self:CanUseExactCapMethod(capIndex, pointIndex)
  end

  local cap = self.pdb.caps and self.pdb.caps[capIndex]
  if not cap or not cap.points then
    return false
  end

  if currentMethod == nil and pointIndex and cap.points[pointIndex] then
    currentMethod = cap.points[pointIndex].method
  end

  local occurrences = 0
  for index, point in ipairs(cap.points) do
    if point.method == method then
      occurrences = occurrences + 1
      if pointIndex and cap.points[pointIndex] and index ~= pointIndex then
        return true
      end
    end
  end

  if (not pointIndex or not cap.points[pointIndex]) and currentMethod ~= method and occurrences > 0 then
    return true
  end

  return false
end

function ReforgeLite:UpdateCapAddButtonState(capIndex)
  if not self.statCaps or not self.statCaps[capIndex] then
    return
  end

  local addButton = self.statCaps[capIndex].add
  if not addButton then
    return
  end

  local cap = self.pdb.caps and self.pdb.caps[capIndex]
  if not cap or cap.stat == 0 then
    addButton:Disable()
    return
  end

  if self:CanAddCapPoint(capIndex) then
    addButton:Enable()
  else
    addButton:Disable()
  end
end

function ReforgeLite:NormalizeExactCapSelections()
  local exactCount = 0
  for capIndex = 1, NUM_CAPS do
    local cap = self.pdb.caps and self.pdb.caps[capIndex]
    if cap and cap.points then
      for _, point in ipairs(cap.points) do
        if point.method == addonTable.StatCapMethods.Exactly then
          exactCount = exactCount + 1
          if exactCount > EXACT_CAP_LIMIT then
            point.method = addonTable.StatCapMethods.AtLeast
          end
        end
      end
    end
  end
end

function ReforgeLite:AddCapPoint (i, loading)
  if not loading and not self:CanAddCapPoint(i) then
    return
  end

  self.pdb.caps[i] = self.pdb.caps[i] or CreateDefaultCap()
  self.pdb.caps[i].points = self.pdb.caps[i].points or {}
  local base = self:GetCapBaseRow(i)
  local row = (loading or #self.pdb.caps[i].points + 1) + base
  local point = (loading or #self.pdb.caps[i].points + 1)
  self.statCaps:AddRow (row)

  local capPoints = self.pdb.caps[i].points
  local capPointRef = loading and capPoints[loading] or nil

  if not loading then
    local methodCounts = self:GetCapMethodCounts(i)
    local newMethod = addonTable.StatCapMethods.AtLeast
    if methodCounts[addonTable.StatCapMethods.AtLeast] > 0 and methodCounts[addonTable.StatCapMethods.AtMost] == 0 then
      newMethod = addonTable.StatCapMethods.AtMost
    elseif methodCounts[addonTable.StatCapMethods.AtMost] > 0 and methodCounts[addonTable.StatCapMethods.AtLeast] == 0 then
      newMethod = addonTable.StatCapMethods.AtLeast
    elseif methodCounts[addonTable.StatCapMethods.Exactly] > 0 then
      newMethod = addonTable.StatCapMethods.Exactly
    end

    tinsert (capPoints, 1, {value = 0, method = newMethod, after = 0, preset = 1})
    capPointRef = capPoints[1]
  end

  capPointRef = capPointRef or capPoints[point]

  local function ResolvePointIndex(widget)
    local points = capPoints
    if not points or #points == 0 then
      return 1
    end

    if widget then
      local ref = widget.capPointRef
      if ref then
        for idx, entry in ipairs(points) do
          if entry == ref then
            widget.pointIndex = idx
            return idx
          end
        end
      end

      local widgetIndex = widget.pointIndex
      if widgetIndex and points[widgetIndex] then
        return widgetIndex
      end
    end

    if capPointRef then
      for idx, entry in ipairs(points) do
        if entry == capPointRef then
          return idx
        end
      end
    end

    local fallback = point or 1
    if fallback < 1 then
      fallback = 1
    elseif fallback > #points then
      fallback = #points
    end
    return fallback
  end

  local rem
  rem = GUI:CreateImageButton (self.statCaps, 20, 20, "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent",
    "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent", nil, nil, function ()
    local targetIndex = ResolvePointIndex(rem)
    self:RemoveCapPoint (i, targetIndex)
    self.statCaps:ToggleStatDropdownToCorrectState()
  end)
  rem.capPointRef = capPointRef
  rem.pointIndex = ResolvePointIndex(rem)

  local methodList = {
    {value = addonTable.StatCapMethods.AtLeast, name = L["At least"]},
    {value = addonTable.StatCapMethods.AtMost, name = L["At most"]},
    {value = addonTable.StatCapMethods.Exactly, name = L["Exactly"]}
  }
  local method
  method = GUI:CreateDropdown(self.statCaps, methodList, {
    default = (capPointRef and capPointRef.method) or addonTable.StatCapMethods.AtLeast,
    setter = function(dropdown, val)
      local methodDropdown = dropdown or method
      local targetIndex = ResolvePointIndex(methodDropdown)
      if capPoints[targetIndex] then
        capPoints[targetIndex].method = val
      end
      if methodDropdown then
        methodDropdown.value = val
      end
      self:UpdateCapAddButtonState(i)
    end,
    width = 95,
    menuItemDisabled = function(methodValue, dropdown)
      local methodDropdown = dropdown or method
      if not methodDropdown then
        return false
      end
      local targetIndex = ResolvePointIndex(methodDropdown)
      return self:ShouldDisableCapMethodOption(i, targetIndex, methodValue, methodDropdown.value)
    end,
  })
  method.capPointRef = capPointRef
  method.pointIndex = ResolvePointIndex(method)

  local preset
  preset = GUI:CreateDropdown (self.statCaps, self.capPresets, {
    default = (capPointRef and capPointRef.preset) or 1,
    width = 60,
    setter = function (_,val)
      local targetIndex = ResolvePointIndex(preset)
      if capPoints[targetIndex] then
        capPoints[targetIndex].preset = val
        self:UpdateCapPreset (i, targetIndex)
        self:ReorderCapPoint (i, targetIndex)
        self:RefreshMethodStats ()
      end
    end,
    menuItemHidden = function(info)
      return info.category and info.category ~= self.statCaps[i].stat.selectedValue
    end
  })
  preset.capPointRef = capPointRef
  preset.pointIndex = ResolvePointIndex(preset)

  local value
  value = GUI:CreateEditBox (self.statCaps, 40, 30, (capPointRef and capPointRef.value) or 0, function (val)
    local targetIndex = ResolvePointIndex(value)
    if capPoints[targetIndex] then
      capPoints[targetIndex].value = val
      self:ReorderCapPoint (i, targetIndex)
      self:RefreshMethodStats ()
    end
  end)
  value.capPointRef = capPointRef
  value.pointIndex = ResolvePointIndex(value)

  local after
  after = GUI:CreateEditBox (self.statCaps, 40, 30, (capPointRef and capPointRef.after) or 0, function (val)
    local targetIndex = ResolvePointIndex(after)
    if capPoints[targetIndex] then
      capPoints[targetIndex].after = val
      self:RefreshMethodStats ()
    end
  end)
  after.capPointRef = capPointRef
  after.pointIndex = ResolvePointIndex(after)

  GUI:SetTooltip (rem, L["Remove cap"])
  GUI:SetTooltip (value, function()
    local cap = self.pdb.caps[i]
    if cap.stat == statIds.SPIRIT then return end
    local targetIndex = ResolvePointIndex(value)
    local pointValue = (cap.points[targetIndex].value or 0)
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
  self:UpdateCapAddButtonState(i)
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
  self:UpdateCapAddButtonState(i)
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
    local row = base + point
    local cells = self.statCaps.cells[row]
    if cells then
      local capPoint = self.pdb.caps[i].points[point]
      if cells[0] then
        cells[0].pointIndex = point
        cells[0].capPointRef = capPoint
      end
      if cells[1] then
        cells[1].pointIndex = point
        cells[1].capPointRef = capPoint
        cells[1]:SetValue (capPoint.method)
      end
      if cells[2] then
        cells[2].pointIndex = point
        cells[2].capPointRef = capPoint
        cells[2]:SetValue (capPoint.preset)
      end
      if cells[3] then
        cells[3].pointIndex = point
        cells[3].capPointRef = capPoint
      end
      if cells[4] then
        cells[4].pointIndex = point
        cells[4].capPointRef = capPoint
        cells[4]:SetText (capPoint.after)
      end
    end
    self:UpdateCapPreset (i, point)
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
      self:UpdateCapAddButtonState(i)
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

  self.statWeights:SetColumnWidth (2, 61)
  self.statWeights:SetColumnWidth (4, 61)
  self.statWeights:EnableColumnAutoWidth(1, 3)

  self.statCaps:Show2 ()
  self:SetAnchor (self.computeButton, "TOPLEFT", self.statCaps, "BOTTOMLEFT", 0, -10)

  self:UpdateContentSize ()
end

function ReforgeLite:CreateOptionList ()
  self.statWeightsCategory = self:CreateCategory (L["Stat Weights"])
  self:SetAnchor (self.statWeightsCategory, "TOPLEFT", self.content, "TOPLEFT", 2, -2)

  self.statWeightsHelpButton = GUI:CreateHelpButton(self.content, L["|cffffffffPresets:|r Load pre-configured stat weights and caps for your spec. Click to select from class-specific presets, custom saved presets, or Pawn imports.\n\n|cffffffffImport:|r Use stat weights from WoWSims, Pawn, or QuestionablyEpic. WoWSims and QE can also import pre-calculated reforge plans.\n\n|cffffffffTarget Level:|r Select your raid difficulty to calculate stat caps at the appropriate level (PvP, Heroic Dungeon, or Raid).\n\n|cffffffffBuffs:|r Enable raid buffs you'll have active (Spell Haste, Melee Haste, Mastery) to account for their stat bonuses in cap calculations.\n\n|cffffffffStat Weights:|r Assign relative values to each stat. Higher weights mean the optimizer will prioritize that stat more when reforging. For example, if Hit has weight 60 and Crit has weight 20, the optimizer values Hit three times more than Crit.\n\n|cffffffffStat Caps:|r Set minimum or maximum values for specific stats. Use presets (Hit Cap, Expertise Cap, Haste Breakpoints) or enter custom values. The optimizer will respect these caps when calculating the optimal reforge plan."], {scale = 0.5})
  self.statWeightsHelpButton:SetPoint("LEFT", self.statWeightsCategory.name, "RIGHT", 4, 0)

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
  self.statWeights:SetColumnWidth (2, 61)
  self.statWeights:SetColumnWidth (4, 61)
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
        GUI:SetDropdownEnabled(dropdown, self.pdb.caps[i - 1] and self.pdb.caps[i - 1].stat ~= 0)
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

        self.pdb.caps[i].stat = val

        if val == 0 then
          while #self.pdb.caps[i].points > 0 do
            self:RemoveCapPoint (i, 1)
          end
        elseif previous == 0 then
          self:AddCapPoint(i)
        end

        if val == 0 then
          self:CollapseStatCaps()
        end

        self.statCaps:ToggleStatDropdownToCorrectState()
        self:UpdateCapAddButtonState(i)
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
      if self:CanAddCapPoint(i) then
        self:AddCapPoint (i)
      end
      self:UpdateCapAddButtonState(i)
    end)
    GUI:SetTooltip (self.statCaps[i].add, L["Add cap"])

    self.statCaps:SetCell (i, 0, self.statCaps[i].stat, "LEFT")
    self.statCaps:SetCell (i, 2, self.statCaps[i].add, "LEFT")
    self:UpdateCapAddButtonState(i)
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
  self:SetAnchor (self.settingsCategory, "TOPLEFT", self.computeButton, "BOTTOMLEFT", 0, -10, { ignoreCollapseOffset = true })
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

  self.settings:SetCell (getOrderId('settings', self.settings), 0, GUI:CreateCheckButton (self.settings, L["Show import button"],
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
  return FormatNumber(delta)
end

function ReforgeLite:GetMethodAlternativeLabel(index)
  if index == 1 then
    return L["Best Result"]
  end
  local altLabel = L["Alt %d"] or L["Alternative %d"]
  return string.format(altLabel, index - 1)
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
    self:RefreshWowSimsPopup()
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
    self:RefreshWowSimsPopup()
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
  self:RefreshWowSimsPopup()
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
  for index, stat in ipairs(self.itemStats) do
    if self:ShouldDisplayStat(index) then
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
      local altIndex = index - 2
      if altIndex >= 0 and altIndex < 4 then
        local column = altIndex % 2
        local row = floor(altIndex / 2)
        if column == 0 then
          if row == 0 then
            button:SetPoint("TOPLEFT", self.methodAlternativeButtons[1], "BOTTOMLEFT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
          else
            button:SetPoint("TOPLEFT", self.methodAlternativeButtons[index - 2], "BOTTOMLEFT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
          end
        else
          if row == 0 then
            button:SetPoint("TOPRIGHT", self.methodAlternativeButtons[1], "BOTTOMRIGHT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
          else
            button:SetPoint("TOPRIGHT", self.methodAlternativeButtons[index - 2], "BOTTOMRIGHT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
          end
        end
        button:SetWidth(self.methodAlternativeButtonWidth or METHOD_ALTERNATIVE_BUTTON_MIN_WIDTH)
      else
        button:SetPoint("TOPLEFT", self.methodAlternativeButtons[index - 1], "BOTTOMLEFT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
        button:SetPoint("TOPRIGHT", self.methodAlternativeButtons[index - 1], "BOTTOMRIGHT", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
      end
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
    button.label:SetPoint("TOP", 0, -2)
    button.label:SetPoint("BOTTOM", 0, 2)
    button.label:SetJustifyH("CENTER")
    button.label:SetJustifyV("MIDDLE")
    button.label:SetWordWrap(false)

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
    if self.methodWowSimsButton then
      self.methodWowSimsButton:Hide()
    end
    return
  end

  local methods = self.methodAlternatives or {}
  local selected = self:GetSelectedMethodAlternative()
  local visible = 0
  local lastRowAnchor

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
        if index == 1 then
          lastRowAnchor = button
        else
          local altIndex = index - 2
          if altIndex < 0 then
            lastRowAnchor = button
          elseif (altIndex % 2) == 0 then
            lastRowAnchor = button
          end
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
  if self.methodWowSimsButton then
    if visible > 0 and lastRowAnchor then
      self.methodWowSimsButton:Show()
      self.methodWowSimsButton:ClearAllPoints()
      self.methodWowSimsButton:SetPoint("TOP", lastRowAnchor, "BOTTOM", 0, -METHOD_ALTERNATIVE_BUTTON_SPACING)
      self.methodWowSimsButton:SetPoint("LEFT", self.methodAlternativesContainer, "LEFT", 0, 0)
      self.methodWowSimsButton:SetPoint("RIGHT", self.methodAlternativesContainer, "RIGHT", 0, 0)
    else
      self.methodWowSimsButton:Hide()
    end
  end

  self:RefreshWowSimsPopup()
end

local function PrintWowSimsMessage(message)
  if DEFAULT_CHAT_FRAME and message then
    DEFAULT_CHAT_FRAME:AddMessage(("[%s] %s"):format(addonName, message))
  end
end

local function GetExportMethod(self)
  if self.methodAlternativesHidden then
    return self.pdb and self.pdb.method
  end

  local alternatives = self.methodAlternatives
  if alternatives and #alternatives > 0 then
    local index = self:GetSelectedMethodAlternative()
    local method = alternatives[index]
    if method and not method.isPlaceholder then
      return method
    end
  end

  return self.pdb and self.pdb.method
end

local WOW_SIMS_POPUP_TITLE = "WoW Sims Export"

local function GetWowSimsSuffix(self)
  if self.methodAlternativesHidden then
    local method = self.pdb and self.pdb.method
    if method and method.items then
      return "(Best)"
    end
    return nil
  end

  local selected = self:GetSelectedMethodAlternative()
  if not selected then
    return nil
  end

  if selected <= 1 then
    return "(Best)"
  end

  return string.format("(ALT %d)", selected - 1)
end

function ReforgeLite:SetWowSimsPopupTitleSuffix(suffix)
  local popup = self.wowSimsPopup
  if not popup or not popup.title then
    return
  end

  if suffix and suffix ~= "" then
    popup.title:SetText(('%s - Code: %s'):format(WOW_SIMS_POPUP_TITLE, suffix))
  else
    popup.title:SetText(WOW_SIMS_POPUP_TITLE)
  end
end

function ReforgeLite:EnsureWowSimsPopup()
  if self.wowSimsPopup then
    return self.wowSimsPopup
  end

  local frame = CreateFrame("Frame", addonName .. "WowSimsPopup", UIParent, "BackdropTemplate")
  frame:SetSize(500, 320)
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)

  frame.backdropInfo = self.backdropInfo
  frame:ApplyBackdrop()
  frame:SetBackdropColor(self:GetBackdropColor())
  frame:SetBackdropBorderColor(self:GetBackdropBorderColor())

  frame.titlebar = frame:CreateTexture(nil, "BACKGROUND")
  frame.titlebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
  frame.titlebar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -3, -3)
  frame.titlebar:SetHeight(20)

  if self.SetFrameActive then
    frame.SetFrameActive = self.SetFrameActive
    frame:SetFrameActive(true)
  end

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetTextColor(1, 1, 1)
  frame.title:SetText(WOW_SIMS_POPUP_TITLE)
  frame.title:SetPoint("TOPLEFT", 12, frame.title:GetHeight() - frame.titlebar:GetHeight())

  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
  frame.close:SetPoint("TOPRIGHT")
  frame.close:SetSize(28, 28)
  frame.close:SetScript("OnClick", function(btn)
    btn:GetParent():Hide()
  end)

  frame:SetScript("OnMouseDown", function(window, button)
    self:SetNewTopWindow(window)
    if button == "LeftButton" then
      window:StartMoving()
      window.moving = true
    end
  end)
  frame:SetScript("OnMouseUp", function(window)
    if window.moving then
      window:StopMovingOrSizing()
      window.moving = nil
      if self.db then
        self.db.wowSimsPopupLocation = SafePack(window:GetPoint())
      end
    end
  end)
  frame:SetScript("OnShow", function(window)
    self:SetNewTopWindow(window)
  end)
  frame:SetScript("OnHide", function(window)
    window.moving = nil
    if window.SetFrameActive then
      window:SetFrameActive(false)
    end
    if self:IsShown() then
      self:SetNewTopWindow(self)
    end
  end)

  frame:ClearAllPoints()
  if self.db and self.db.wowSimsPopupLocation then
    frame:SetPoint(SafeUnpack(self.db.wowSimsPopupLocation))
  else
    frame:SetPoint("CENTER", self, "CENTER")
  end

  tinsert(UISpecialFrames, frame:GetName())
  tinsert(RFL_FRAMES, frame)

  local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -12)
  scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 12)

  local editBox = CreateFrame("EditBox", nil, scrollFrame)
  editBox:SetMultiLine(true)
  editBox:SetMaxLetters(0)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal or GameFontHighlight)
  editBox:SetWidth(450)
  editBox:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
    frame:Hide()
  end)

  scrollFrame:SetScrollChild(editBox)
  scrollFrame:SetScript("OnSizeChanged", function(_, width)
    editBox:SetWidth(width)
  end)

  frame.scrollFrame = scrollFrame
  frame.editBox = editBox

  frame:Hide()

  self.wowSimsPopup = frame
  return frame
end

function ReforgeLite:DisplayWowSimsExport(text, suffix, shouldHighlight)
  local popup = self:EnsureWowSimsPopup()
  local editBox = popup.editBox
  local hadFocus = editBox:HasFocus()

  editBox:SetText(text or "")

  if shouldHighlight then
    editBox:HighlightText()
    editBox:SetFocus()
  elseif hadFocus then
    editBox:SetFocus()
  else
    editBox:HighlightText(0, 0)
    editBox:ClearFocus()
  end

  self:SetWowSimsPopupTitleSuffix(suffix)
  popup:Show()
end

function ReforgeLite:GenerateWowSimsExportText()
  local exporter = addonTable.WowSimsExport
  if not exporter or type(exporter.Generate) ~= "function" then
    return nil, "WowSims export not available."
  end

  local method = GetExportMethod(self)
  if not method or not method.items then
    return nil, "No reforge method available."
  end

  local result, err = exporter.Generate(method)
  if not result then
    return nil, ("WowSims export failed: %s"):format(tostring(err or "unknown error"))
  end

  return result
end

function ReforgeLite:RefreshWowSimsPopup()
  local popup = self.wowSimsPopup
  if not popup or not popup:IsShown() then
    return
  end

  local result = self:GenerateWowSimsExportText()
  if not result then
    popup:Hide()
    return
  end

  self:DisplayWowSimsExport(result, GetWowSimsSuffix(self), popup.editBox:HasFocus())
end

function ReforgeLite:ShowWowSimsExportPopup()
  local result, err = self:GenerateWowSimsExportText()
  if not result then
    if err then
      PrintWowSimsMessage(err)
    end
    return
  end

  self:DisplayWowSimsExport(result, GetWowSimsSuffix(self), true)
end

function ReforgeLite:UpdateMethodCategory()
  if self.methodCategory == nil then
    self.methodCategory = self:CreateCategory (L["Result"])
    self:SetAnchor (self.methodCategory, "TOPLEFT", self.computeButton, "BOTTOMLEFT", 0, -10)

    self.methodHelpButton = GUI:CreateHelpButton(self.content, L["The Result table shows the stat changes from the optimized reforge.\n\nThe left column shows your total stats after reforging.\n\nThe right column shows how much each stat changed:\n- Green: Stat increased and improved your weighted score\n- Red: Stat decreased and lowered your weighted score\n- Grey: No meaningful change (either unchanged, or changed but weighted score stayed the same)\n\nClick 'Show' to see a detailed breakdown of which items to reforge.\n\nClick 'Reset' to clear the current reforge plan."], {scale = 0.5})
    self.methodHelpButton:SetPoint("LEFT", self.methodCategory.name, "RIGHT", 4, 0)

    self.methodStats = GUI:CreateTable (#self.itemStats - 1, 2, ITEM_SIZE, 60, {0.5, 0.5, 0.5, 1})
    self.methodCategory:AddFrame (self.methodStats)
    self:SetAnchor (self.methodStats, "TOPLEFT", self.methodCategory, "BOTTOMLEFT", 0, -5)
    self.methodStats:SetRowHeight (ITEM_SIZE + 2)
    self.methodStats.defaultRowHeight = ITEM_SIZE + 2

    local labelMeasure = self.methodStats:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    labelMeasure:Hide()
    local maxLabelWidth = 0

    for i, v in ipairs (self.itemStats) do
      local label = v.resultLabel or v.tip
      self.methodStats:SetCellText (i - 1, 0, label, "LEFT")

      self.methodStats[i] = {}

      self.methodStats[i].value = self.methodStats:CreateFontString (nil, "OVERLAY", "GameFontNormalSmall")
      self.methodStats:SetCell (i - 1, 1, self.methodStats[i].value)
      self.methodStats[i].value:SetTextColor (1, 1, 1)
      self.methodStats[i].value:SetText (FormatLargeNumber(0))

      self.methodStats[i].delta = self.methodStats:CreateFontString (nil, "OVERLAY", "GameFontNormalSmall")
      self.methodStats:SetCell (i - 1, 2, self.methodStats[i].delta)
      self.methodStats[i].delta:SetTextColor (0.7, 0.7, 0.7)
      self.methodStats[i].delta:SetText (FormatNumber(0))

      labelMeasure:SetText(label or "")
      local labelWidth = labelMeasure:GetStringWidth() or 0
      if labelWidth > maxLabelWidth then
        maxLabelWidth = labelWidth
      end
    end

    labelMeasure:SetText("")
    labelMeasure:Hide()

    local labelColumnPadding = 16
    local labelColumnWidth = math.ceil(maxLabelWidth) + labelColumnPadding
    local paddingReduction = 6
    local minimumPadding = 8
    local reducedWidth = labelColumnWidth - paddingReduction
    local minimumWidth = math.ceil(maxLabelWidth) + minimumPadding
    labelColumnWidth = max(minimumWidth, reducedWidth)
    local valueColumnWidth = 72
    self.methodStats:SetColumnWidth(0, labelColumnWidth)
    self.methodStats:SetColumnWidth(1, valueColumnWidth)
    self.methodStats:SetColumnWidth(2, valueColumnWidth)

    local expertiseLabelCell = self.methodStats.cells and self.methodStats.cells[statIds.EXP - 1] and self.methodStats.cells[statIds.EXP - 1][0]
    self.expertiseToHitHelpButton = GUI:CreateHelpButton(self.methodStats, L["Your Expertise rating is being converted to spell hit.\n\nIn Mists of Pandaria, casters benefit from Expertise due to it automatically converting to Hit at a 1:1 ratio.\n\nThe Hit value shown above includes this converted Expertise rating.\n\nNote: The character sheet is bugged and doesn't show Expertise converted to spell hit, but the conversion works correctly in combat."], { scale = 0.45 })
    if expertiseLabelCell then
      self.expertiseToHitHelpButton:SetPoint("LEFT", expertiseLabelCell, "RIGHT", -8, 0)
    else
      self.expertiseToHitHelpButton:SetPoint("LEFT", self.methodStats, "RIGHT", 0, 0)
    end
    self.expertiseToHitHelpButton:Hide()

    self.methodStats.visibleRows = {}

    self.methodAlternativesContainer = CreateFrame("Frame", nil, self.content)
    self.methodCategory:AddFrame(self.methodAlternativesContainer)
    self:SetAnchor (self.methodAlternativesContainer, "TOPLEFT", self.methodStats, "TOPRIGHT", 10, 0)
    self.methodAlternativesContainer:SetPoint("BOTTOMLEFT", self.methodStats, "BOTTOMRIGHT", 10, 0)

    local alternativeLabelMeasure = self.methodAlternativesContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    alternativeLabelMeasure:Hide()

    local maxButtons = addonTable.MAX_METHOD_ALTERNATIVES or 5
    local bestLabelWidth = 0
    local altLabelWidth = 0
    for index = 1, maxButtons do
      alternativeLabelMeasure:SetText(self:GetMethodAlternativeLabel(index))
      local width = alternativeLabelMeasure:GetStringWidth() or 0
      if index == 1 then
        bestLabelWidth = width
      else
        if width > altLabelWidth then
          altLabelWidth = width
        end
      end
    end

    alternativeLabelMeasure:SetText("")
    alternativeLabelMeasure:Hide()

    local baseAltWidth = math.ceil(altLabelWidth) + 16
    if baseAltWidth < METHOD_ALTERNATIVE_BUTTON_MIN_WIDTH then
      baseAltWidth = METHOD_ALTERNATIVE_BUTTON_MIN_WIDTH
    end

    local bestWidth = math.ceil(bestLabelWidth) + 16
    local containerWidth = math.max(bestWidth, (baseAltWidth * 2) + METHOD_ALTERNATIVE_COLUMN_SPACING)
    local finalAltWidth = math.max(baseAltWidth, floor((containerWidth - METHOD_ALTERNATIVE_COLUMN_SPACING) / 2))

    self.methodAlternativeButtonWidth = finalAltWidth
    self.methodAlternativesContainer:SetWidth(containerWidth)
    self.methodAlternativesContainer:Hide()

    self.methodAlternativeButtons = {}
    self:EnsureMethodAlternativeButtons(addonTable.MAX_METHOD_ALTERNATIVES)

    self.methodWowSimsButton = GUI:CreatePanelButton(self.content, "WowSims", function()
      self:ShowWowSimsExportPopup()
    end)
    self.methodWowSimsButton:SetHeight(METHOD_ACTION_BUTTON_HEIGHT)
    self.methodWowSimsButton:SetPoint("TOPLEFT", self.methodAlternativesContainer, "BOTTOMLEFT", 0, 0)
    self.methodWowSimsButton:SetPoint("TOPRIGHT", self.methodAlternativesContainer, "BOTTOMRIGHT", 0, 0)
    self.methodWowSimsButton:Hide()
    self.methodCategory:AddFrame(self.methodWowSimsButton)

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
    if self.settingsCategory.Refresh then
      self.settingsCategory:Refresh()
    end
  end

  if self.pdb.method and (not self.methodAlternatives or #self.methodAlternatives == 0) then
    self:SetMethodAlternatives({self.pdb.method}, self.selectedMethodAlternative or 1)
  end

  self:UpdateMethodAlternativeButtons()

  self:RefreshMethodStats()

  self:RefreshMethodWindow()
  self:UpdateContentSize ()
end

function ReforgeLite:ShouldGroupExpertiseWithHit()
  if not self.conversionInitialized then
    if type(self.GetConversion) ~= "function" then
      return false
    end
    self:GetConversion()
  end

  if not self.conversion then
    return false
  end

  local expertiseConversion = (self.conversion[statIds.EXP] or {})[statIds.HIT]
  if not expertiseConversion or expertiseConversion == 0 then
    return false
  end

  if not C_SpecializationInfo or not C_SpecializationInfo.GetSpecialization then
    return false
  end

  local specIndex = C_SpecializationInfo.GetSpecialization()
  if not specIndex then
    return false
  end

  local role = select(6, C_SpecializationInfo.GetSpecializationInfo(specIndex))
  return role == "DAMAGER"
end

function ReforgeLite:RefreshMethodStats()
  self:UpdateMethodStatVisibility()

  local method = self.pdb.method
  if method then
    self:UpdateMethodStats (method)
  end

  local methodStats = self.methodStats
  if methodStats then
    local showHelp = self.db.showHelp ~= false
    local weights = self.pdb.weights or {}
    local spiritWeight = weights[statIds.SPIRIT] or 0
    local spiritConversion = (self.conversion[statIds.SPIRIT] or {})[statIds.HIT]
    local expertiseConversion = (self.conversion[statIds.EXP] or {})[statIds.HIT]
    local groupExpertiseWithHit = self:ShouldGroupExpertiseWithHit()
    local showExpertiseHelp = false

    for index, stat in ipairs (self.itemStats) do
      local row = index - 1
      local baseVisible = methodStats.visibleRows and methodStats.visibleRows[row]
      if baseVisible == nil then
        baseVisible = true
      end

      local statRow = methodStats[index]
      local methodValue = 0
      if method and stat.mgetter then
        methodValue = stat.mgetter (method)
        local formattedValue
        if stat.percent then
          formattedValue = string.format("%s%%", FormatMethodStatValue(methodValue))
        else
          formattedValue = FormatMethodStatValue(methodValue)
        end
        if statRow and statRow.value then
          statRow.value:SetText(formattedValue)
        elseif methodStats then
          methodStats:SetCellText(row, 1, formattedValue)
        end
        local override
        local compareValue = stat.mgetter (method, true)
        local currentValue = stat.getter and stat.getter () or 0
        if self:GetStatScore (index, compareValue) == self:GetStatScore (index, currentValue) then
          override = 0
        end
        if statRow and statRow.delta then
          SetTextDelta (statRow.delta, compareValue, currentValue, override)
        end
      end

      if index == statIds.EXP and expertiseConversion and methodValue > 0 then
        showExpertiseHelp = true
      end

      local shouldShow = baseVisible
      if index == statIds.SPIRIT then
        local hasSpiritStat = methodValue > 0
        shouldShow = shouldShow and (spiritWeight > 0 or spiritConversion or hasSpiritStat)
      elseif index == statIds.EXP and groupExpertiseWithHit then
        local hasExpertiseStat = expertiseConversion and methodValue > 0
        if statRow and statRow.value then
          if hasExpertiseStat then
            statRow.value:SetText("")
          end
        end
        shouldShow = shouldShow and hasExpertiseStat
      end

      methodStats:SetRowExpanded(row, shouldShow)
    end

    if self.expertiseToHitHelpButton then
      local helpVisible = showHelp and showExpertiseHelp
      self.expertiseToHitHelpButton:SetShown(helpVisible)
      self.expertiseToHitHelpButton:SetEnabled(showExpertiseHelp)
    end
  end

  self:UpdateMethodChecks()
end

function ReforgeLite:UpdateContentSize (skipDeferred)
  if not self.content then
    return
  end

  local newHeight
  local contentTop = self.content and self.content:GetTop()

  local lowestBottom
  if self.content then
    local children = { self.content:GetChildren() }
    for index = 1, #children do
      local child = children[index]
      if child and child:IsShown() then
        local childBottom = child:GetBottom()
        if childBottom and (not lowestBottom or childBottom < lowestBottom) then
          lowestBottom = childBottom
        end
      end
    end
  end

  if contentTop and lowestBottom then
    newHeight = contentTop - lowestBottom
  end

  if (not newHeight or newHeight <= 0) and self.lastElement and contentTop then
    local contentBottom = self.lastElement:GetBottom()
    if contentBottom then
      newHeight = contentTop - contentBottom
    end
  end

  if not newHeight or newHeight <= 0 then
    newHeight = -self:GetFrameY (self.lastElement)
  end

  if newHeight <= 0 then
    newHeight = 1
  end

  self.content:SetHeight (newHeight)
  RunNextFrame(function() self:FixScroll() end)

  if not skipDeferred and not self.pendingContentSizeUpdate then
    -- Tables within the scroll content adjust their heights on the next frame
    -- via OnUpdateFix callbacks. Queue another measurement after those layouts
    -- finish so hidden rows from collapsed categories don't leave blank space.
    self.pendingContentSizeUpdate = true
    RunNextFrame(function()
      self.pendingContentSizeUpdate = nil
      if self.content then
        self:UpdateContentSize(true)
      end
    end)
  end
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
  if not item
    or item:IsItemEmpty()
    or not item:HasItemLocation()
    or item:GetItemQuality() < Enum.ItemQuality.Rare
    or item:GetCurrentItemLevel() < 458 then
    return 0
  end

  local itemId = item:GetItemID()
  if not itemId or not SafeGetDetailedItemLevelInfo then
    return 0
  end

  local baseFromAPI, _, _, rawBase = SafeGetDetailedItemLevelInfo(itemId, item:GetItemLocation(), item:GetItemLink())
  local originalIlvl = rawBase or baseFromAPI
  if not originalIlvl or originalIlvl <= 0 then
    return 0
  end

  local currentIlvl = item:GetCurrentItemLevel() or 0
  local upgrade = (currentIlvl - originalIlvl) / 4
  if upgrade < 0 then
    upgrade = 0
  end
  return floor(upgrade + 0.5)
end

local function CopyItemInfoFields(target, source)
  wipe(target)
  if not source then
    return
  end

  for key, value in pairs(source) do
    target[key] = value
  end
end

local function DeriveItemUpgradeData(item)
  if not item or item:IsItemEmpty() then
    return 0, nil
  end

  local rareQuality = Enum and Enum.ItemQuality and Enum.ItemQuality.Rare or LE_ITEM_QUALITY_RARE or 3

  if not item:HasItemLocation()
    or item:GetItemQuality() < rareQuality then
    return 0, nil
  end

  local link = item:GetItemLink()
  if not link then
    return 0, nil
  end

  local _, _, linkUpgradeDelta = GetLinkUpgradeData(link)

  local baseIlvl

  if SafeGetDetailedItemLevelInfo then
    local best, effective, _, rawBase = SafeGetDetailedItemLevelInfo(item:GetItemID(), item:GetItemLocation(), link)
    baseIlvl = rawBase or best

    if (not baseIlvl or baseIlvl <= 0) and effective and effective > 0 then
      baseIlvl = effective
    end

    if linkUpgradeDelta and linkUpgradeDelta > 0 then
      local current = effective or (best and best > 0 and best) or item:GetCurrentItemLevel()
      if current and current > 0 then
        local candidate = current - linkUpgradeDelta
        if candidate > 0 then
          if not baseIlvl or baseIlvl <= 0 or baseIlvl >= current or (current - baseIlvl) < linkUpgradeDelta - 0.25 then
            baseIlvl = candidate
          end
        end
      end
    end
  end

  if (not baseIlvl or baseIlvl <= 0) then
    local _, _, _, infoLevel = GetItemInfo(link)
    if infoLevel and infoLevel > 0 then
      baseIlvl = infoLevel
    end
  end

  local currentIlvl = item:GetCurrentItemLevel() or 0
  if currentIlvl <= 0 and SafeGetDetailedItemLevelInfo then
    local best, effective = SafeGetDetailedItemLevelInfo(item:GetItemID(), item:GetItemLocation(), link)
    currentIlvl = (effective and effective > 0 and effective) or (best and best > 0 and best) or 0
  end
  if not currentIlvl or currentIlvl <= 0 then
    if baseIlvl and baseIlvl > 0 then
      return 0, baseIlvl
    end
    return 0, nil
  end

  if currentIlvl < 458 then
    if baseIlvl and baseIlvl > 0 then
      return 0, baseIlvl
    end
    return 0, nil
  end

  if (not baseIlvl or baseIlvl <= 0) and linkUpgradeDelta and linkUpgradeDelta > 0 then
    baseIlvl = currentIlvl - linkUpgradeDelta
  end

  if not baseIlvl or baseIlvl <= 0 then
    return 0, nil
  end

  local upgradeLevel = (currentIlvl - baseIlvl) / 4
  if upgradeLevel < 0 then
    upgradeLevel = 0
  end

  return floor(upgradeLevel + 0.5), baseIlvl
end

local function CollectItemInfoWithUpgrade(item, slotId)
  if not item or item:IsItemEmpty() then
    return
  end

  local link = item:GetItemLink()
  if not link then
    return
  end

  local apiBaseIlvl, apiCurrentIlvl
  if C_Item and C_Item.GetDetailedItemLevelInfo then
    local itemId = item:GetItemID()
    if itemId then
      apiBaseIlvl, apiCurrentIlvl = C_Item.GetDetailedItemLevelInfo(itemId)
    end
  end

  local derivedUpgrade, derivedOriginalIlvl = DeriveItemUpgradeData(item)

  local originalIlvl = apiBaseIlvl
  if not originalIlvl or originalIlvl <= 0 then
    originalIlvl = derivedOriginalIlvl
  end

  local currentIlvl = apiCurrentIlvl
  if not currentIlvl or currentIlvl <= 0 then
    currentIlvl = item:GetCurrentItemLevel()
  end

  local computedUpgrade
  if currentIlvl and currentIlvl > 0 and originalIlvl and originalIlvl > 0 then
    computedUpgrade = floor(((currentIlvl - originalIlvl) / 4) + 0.5)
    if computedUpgrade < 0 then
      computedUpgrade = 0
    end
  end

  local itemInfo = {
    link = link,
    itemId = item:GetItemID(),
    itemGUID = item:GetItemGUID(),
    ilvl = currentIlvl,
    slotId = slotId,
  }

  if item:HasItemLocation() then
    itemInfo.itemLocation = item:GetItemLocation()
  end

  if originalIlvl and originalIlvl > 0 then
    local roundedBase = floor(originalIlvl + 0.5)
    itemInfo.baseIlvl = roundedBase
    itemInfo.ilvlBase = roundedBase
    itemInfo.originalIlvl = roundedBase
  end
  if computedUpgrade and computedUpgrade > 0 then
    itemInfo.upgradeLevel = computedUpgrade
  elseif derivedUpgrade and derivedUpgrade > 0 then
    itemInfo.upgradeLevel = derivedUpgrade
  end

  local baseIlvl, upgradeLevel, effectiveIlvl = addonTable.GetItemBaseAndUpgrade(itemInfo)

  if (not baseIlvl or baseIlvl <= 0) and originalIlvl and originalIlvl > 0 then
    baseIlvl = floor(originalIlvl + 0.5)
  end

  if (not baseIlvl or baseIlvl <= 0) and itemInfo.ilvl then
    baseIlvl = itemInfo.ilvl
  end

  if (not effectiveIlvl or effectiveIlvl <= 0) and baseIlvl then
    effectiveIlvl = baseIlvl + (upgradeLevel or 0) * 4
  end

  upgradeLevel = upgradeLevel or 0
  baseIlvl = baseIlvl or 0
  effectiveIlvl = effectiveIlvl or baseIlvl

  itemInfo.baseIlvl = baseIlvl
  itemInfo.upgradeLevel = upgradeLevel
  itemInfo.effectiveIlvl = effectiveIlvl
  itemInfo.ilvl = effectiveIlvl
  if not itemInfo.originalIlvl then
    itemInfo.originalIlvl = baseIlvl
  end

  return itemInfo, baseIlvl, upgradeLevel
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
    if not item:IsItemEmpty() then
      local itemInfo, baseIlvl, upgradeLevel = CollectItemInfoWithUpgrade(item, v.slotId)
      if itemInfo then
        CopyItemInfoFields(info, itemInfo)
        info.reforge = GetReforgeID(v.slotId)

        v.item = info.link
        v.itemId = info.itemId
        v.ilvl = info.ilvl
        v.itemGUID = info.itemGUID
        v.baseIlvl = baseIlvl
        v.upgradeLevel = upgradeLevel
        v.reforge = info.reforge

        v.texture:SetTexture(item:GetItemIcon())
        local qualityColor = item:GetItemQualityColor()
        v.qualityColor = qualityColor
        v.quality:SetVertexColor(qualityColor.r, qualityColor.g, qualityColor.b)

        local statsSource = GetItemStats(info)
        statsOrig = CopyTableShallow(statsSource)
        stats = CopyTableShallow(statsSource)
        if info.reforge then
          local srcIndex, dstIndex = unpack(reforgeTable[info.reforge])
          reforgeSrc = self.itemStats[srcIndex].name
          reforgeDst = self.itemStats[dstIndex].name
          local amount = floor ((stats[reforgeSrc] or 0) * addonTable.REFORGE_COEFF)
          stats[reforgeSrc] = (stats[reforgeSrc] or 0) - amount
          stats[reforgeDst] = (stats[reforgeDst] or 0) + amount
        end
      else
        CopyItemInfoFields(info)
        info.reforge = nil
        v.item = nil
        v.itemId = nil
        v.ilvl = nil
        v.itemGUID = nil
        v.baseIlvl = nil
        v.upgradeLevel = nil
        v.reforge = nil
        v.texture:SetTexture(item:GetItemIcon())
        local qualityColor = item:GetItemQualityColor()
        v.qualityColor = qualityColor
        if qualityColor then
          v.quality:SetVertexColor(qualityColor.r, qualityColor.g, qualityColor.b)
        else
          v.quality:SetVertexColor(1, 1, 1)
        end
        stats = {}
        statsOrig = {}
      end
    else
      CopyItemInfoFields(info)
      v.item = nil
      v.itemId = nil
      v.ilvl = nil
      v.reforge = nil
      v.itemGUID = nil
      v.qualityColor = nil
      v.upgradeLevel = nil
      v.baseIlvl = nil
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
        statFont:SetText (FormatLargeNumber(currentValue))
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

  self.statColumnShown = self.statColumnShown or {}
  for i, v in ipairs (self.itemStats) do
    local hasData = columnHasData[i]
    local showColumn = hasData or not hasAnyData
    self.statColumnShown[i] = showColumn

    if self.statTotals[i] then
      local totalValue = v.getter and v.getter() or 0
      if totalValue and totalValue ~= 0 then
        self.statTotals[i]:SetText(FormatLargeNumber(totalValue))
      else
        self.statTotals[i]:SetText(FormatLargeNumber(0))
      end
    end

    if showColumn then
      if not (self.itemTable and self.itemTable.ExpandColumn) then
        error("Item table missing ExpandColumn implementation")
      end
      self.itemTable:ExpandColumn(i)
      if self.itemTable.AutoSizeColumns then
        self.itemTable:AutoSizeColumns(i)
      end
      if self.statHeaders and self.statHeaders[i] then
        self.statHeaders[i]:Show()
        if self.statHeaders[i].SetAlpha then
          self.statHeaders[i]:SetAlpha(1)
        end
      end
      if self.statTotals[i] then
        self.statTotals[i]:Show()
        if self.statTotals[i].SetAlpha then
          self.statTotals[i]:SetAlpha(1)
        end
      end
    else
      if not (self.itemTable and self.itemTable.CollapseColumn) then
        error("Item table missing CollapseColumn implementation")
      end
      self.itemTable:CollapseColumn(i)
      if self.statHeaders and self.statHeaders[i] then
        if self.statHeaders[i].Hide then
          self.statHeaders[i]:Hide()
        else
          self.statHeaders[i]:SetAlpha(0)
        end
      end
      if self.statTotals[i] then
        if self.statTotals[i].Hide then
          self.statTotals[i]:Hide()
        else
          self.statTotals[i]:SetAlpha(0)
        end
      end
    end
  end

  self.statColumnShownInitialized = true

  self:UpdateMethodStatVisibility()

  local _, minHeight, maxWidth, maxHeight = self:GetResizeBounds()
  local methodStatsWidth = self.methodStats and self.methodStats:GetWidth() or 0
  if not methodStatsWidth or methodStatsWidth <= 0 then
    methodStatsWidth = 280
  end
  local alternativesWidth = 0
  if self.methodAlternativesContainer and self.methodAlternativesContainer:GetWidth() then
    alternativesWidth = self.methodAlternativesContainer:GetWidth()
  end
  if alternativesWidth < 0 then
    alternativesWidth = 0
  end
  local methodSpacing = (alternativesWidth > 0) and 10 or 0
  local methodPanelWidth = methodStatsWidth + methodSpacing + alternativesWidth
  if methodPanelWidth <= 0 then
    methodPanelWidth = 400
  end
  local minWidth = self.itemTable:GetWidth() + 10 + methodPanelWidth + 22
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

function ReforgeLite:DoesMethodUseStat(statIndex)
  local method = self.pdb and self.pdb.method
  if not method or not method.items then
    return false
  end

  for _, slotInfo in ipairs(method.items) do
    if slotInfo and slotInfo.reforge and (slotInfo.src == statIndex or slotInfo.dst == statIndex) then
      return true
    end
  end

  return false
end

function ReforgeLite:ShouldDisplayStat(statIndex)
  if not statIndex or statIndex <= 0 then
    return false
  end

  if not self.statColumnShownInitialized then
    return true
  end

  if self.statColumnShown and self.statColumnShown[statIndex] then
    return true
  end

  return self:DoesMethodUseStat(statIndex)
end

function ReforgeLite:UpdateMethodStatVisibility()
  if not self.methodStats then
    return
  end

  self.methodStats.visibleRows = self.methodStats.visibleRows or {}

  for index = 1, #self.itemStats do
    local shouldShow = self:ShouldDisplayStat(index)
    local row = index - 1
    local changed = self.methodStats.visibleRows[row] ~= shouldShow
    self.methodStats.visibleRows[row] = shouldShow
    self.methodStats:SetRowExpanded(row, shouldShow)

    if changed then
      local labelCell = self.methodStats.cells and self.methodStats.cells[row] and self.methodStats.cells[row][0]
      if labelCell then
        labelCell:SetShown(shouldShow)
      end

      local statRow = self.methodStats[index]
      if statRow then
        if statRow.value then
          statRow.value:SetShown(shouldShow)
        end
        if statRow.delta then
          statRow.delta:SetShown(shouldShow)
        end
      end
    end
  end
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

function ReforgeLite:RegisterQueueUpdateEvents()
  for event, unitID in pairs(queueUpdateEvents) do
    if not self:IsEventRegistered(event) then
      if unitID == true then
        self:RegisterEvent(event)
      else
        self:RegisterUnitEvent(event, unitID)
      end
    end
  end
end

function ReforgeLite:UnregisterQueueUpdateEvents()
  for event in pairs(queueUpdateEvents) do
    if self:IsEventRegistered(event) then
      self:UnregisterEvent(event)
    end
  end
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
    frame:SetText(L["Reforge Result Title"])
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
      local itemInfo = CollectItemInfoWithUpgrade(item, v.slotId)
      CopyItemInfoFields(v.itemInfo, itemInfo)
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
            local itemInfo = CollectItemInfoWithUpgrade(item, slotData.slotId)
            CopyItemInfoFields(windowItem.itemInfo, itemInfo)
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
          local reforgeItemInfo = slotInfo.itemInfo or self.itemData[slotId].itemInfo
          local stats = {}
          if reforgeItemInfo and reforgeItemInfo.link then
            stats = GetItemStats(reforgeItemInfo) or {}
          end
          for _, reforgeInfo in ipairs(reforgeTable) do
            local srcIndex, dstIndex = unpack(reforgeInfo)
            if (stats[self.itemStats[srcIndex].name] or 0) ~= 0 and (stats[self.itemStats[dstIndex].name] or 0) == 0 then
              id = id + 1
            end
            if srcIndex == self.pdb.method.items[slotId].src and dstIndex == self.pdb.method.items[slotId].dst then
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
  if not currentSpec then
    currentSpec = curr
  end
  if currentSpec ~= curr then
    currentSpec = curr
    self:SwapSpecProfiles()
  end
end

function ReforgeLite:PLAYER_SPECIALIZATION_CHANGED()
  self:GetConversion()
  self:UpdatePlayerSpecInfo()
end

function ReforgeLite:PLAYER_ENTERING_WORLD()
  self:GetConversion()
  if not currentSpec then
    currentSpec = C_SpecializationInfo.GetActiveSpecGroup()
  end
end

local ILVL_DISPLAY_FORMAT = "iLvl: %d"

function ReforgeLite:PLAYER_AVG_ITEM_LEVEL_UPDATE()
  self.itemLevel:SetFormattedText(ILVL_DISPLAY_FORMAT, select(2, GetAverageItemLevel()))
end

function ReforgeLite:ADDON_LOADED (addon)
  if addon ~= addonName then return end
  self:Hide()
  self:UpgradeDB()

  RefreshItemStatLabels()

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
