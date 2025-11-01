local addonName, addonTable = ...

local WowSimsExport = {}
addonTable.WowSimsExport = WowSimsExport

local LibParse = LibStub and LibStub("LibParse", true)

local EXPORT_VERSION = "v3.1.3"
local UNIT_PLAYER = "player"
local REFORGE_TABLE_BASE = 112

local EQUIPMENT_SLOT_LAYOUT = {
  INVSLOT_HEAD,
  INVSLOT_NECK,
  INVSLOT_SHOULDER,
  INVSLOT_BACK,
  INVSLOT_CHEST,
  INVSLOT_WRIST,
  INVSLOT_HAND,
  INVSLOT_WAIST,
  INVSLOT_LEGS,
  INVSLOT_FEET,
  INVSLOT_FINGER1,
  INVSLOT_FINGER2,
  INVSLOT_TRINKET1,
  INVSLOT_TRINKET2,
  INVSLOT_MAINHAND,
  INVSLOT_OFFHAND,
  INVSLOT_RANGED,
}

local function CreateScanningTooltip()
  if _G.WSEScanningTooltip then
    return _G.WSEScanningTooltip
  end

  local tooltip = CreateFrame("GameTooltip", "WSEScanningTooltip", nil, "GameTooltipTemplate")
  tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
  tooltip:Hide()
  return tooltip
end

local scanningTooltip = CreateScanningTooltip()

local function BuildProfessionLookup()
  local professionSkillLineIDs = {
    Blacksmithing  = 164,
    Leatherworking = 165,
    Alchemy        = 171,
    Herbalism      = 182,
    Mining         = 186,
    Tailoring      = 197,
    Engineering    = 202,
    Enchanting     = 333,
    Skinning       = 393,
    Jewelcrafting  = 755,
    Inscription    = 773,
  }

  local lookup = {}
  for englishName, skillLine in pairs(professionSkillLineIDs) do
    local localizedName = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName(skillLine)
    if localizedName then
      lookup[localizedName] = {
        skillLine = skillLine,
        englishName = englishName,
      }
    end
  end

  return lookup
end

local professionLookup = BuildProfessionLookup()

local function CreateProfessionEntry()
  local professions = {}
  for index = 1, GetNumSkillLines() do
    local name, _, _, skillLevel, _, _, skillLine = GetSkillLineInfo(index)
    local data = professionLookup[name]
    if data then
      table.insert(professions, {
        name = data.englishName,
        level = skillLevel,
      })
    end
  end
  return professions
end

local function CreateGlyphEntry()
  local glyphs = {
    prime = {},
    major = {},
    minor = {},
  }

  if not C_SpecializationInfo or not C_SpecializationInfo.GetActiveSpecGroup then
    return glyphs
  end

  local activeSpecGroup = C_SpecializationInfo.GetActiveSpecGroup(false)
  local unit = UNIT_PLAYER
  local numGlyphSockets = GetNumGlyphSockets()

  for slot = 1, numGlyphSockets do
    local enabled, glyphType, _, glyphID = GetGlyphSocketInfo(slot, activeSpecGroup, false, unit)
    if enabled and glyphType and glyphID then
      local targetTable
      if glyphType == 1 then
        targetTable = glyphs.major
      elseif glyphType == 2 then
        targetTable = glyphs.minor
      else
        targetTable = glyphs.prime
      end
      table.insert(targetTable, { spellID = glyphID })
    end
  end

  glyphs.prime = nil
  return glyphs
end

local function CreateTalentString()
  if not C_SpecializationInfo or not C_SpecializationInfo.GetTalentInfo then
    return ""
  end

  local talents = {}
  local activeSpecGroup = C_SpecializationInfo.GetActiveSpecGroup(false)
  for tier = 1, MAX_NUM_TALENT_TIERS do
    local found = false
    for column = 1, 3 do
      local talentInfo = C_SpecializationInfo.GetTalentInfo({
        isInspect = false,
        target = UNIT_PLAYER,
        groupIndex = activeSpecGroup,
        tier = tier,
        column = column,
      })
      if talentInfo and talentInfo.selected then
        found = true
        talents[#talents + 1] = tostring(column)
        break
      end
    end
    if not found then
      talents[#talents + 1] = "0"
    end
  end
  return table.concat(talents)
end

local function GetSpecSlug()
  if not C_SpecializationInfo or not C_SpecializationInfo.GetSpecialization then
    return ""
  end

  local specIndex = C_SpecializationInfo.GetSpecialization()
  if not specIndex then
    return ""
  end

  local _, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
  if not specName or specName == "" then
    return ""
  end

  specName = specName:lower()
  specName = specName:gsub("%s+", "_")
  return specName
end

local function GetSpecDisplay()
  if not C_SpecializationInfo or not C_SpecializationInfo.GetSpecialization then
    return ""
  end

  local specIndex = C_SpecializationInfo.GetSpecialization()
  if not specIndex then
    return ""
  end

  local specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
  return specName or ""
end

local function NormalizeGemList(gems)
  for index = #gems, 2, -1 do
    if gems[index] and not gems[index - 1] then
      gems[index - 1] = 0
    end
  end

  local cleaned = {}
  for index = 1, #gems do
    local value = gems[index]
    if value ~= nil then
      cleaned[#cleaned + 1] = value
    end
  end

  return cleaned
end

local function ParseItemLink(itemLink)
  if not itemLink then
    return
  end

  local _, itemId, enchantId, gem1, gem2, gem3, gem4, suffixId, uniqueId, linkLevel, reforgeId, _, upgradeId = strsplit(":", itemLink)
  local data = {
    id = tonumber(itemId),
    enchant = tonumber(enchantId),
    gems = NormalizeGemList({ tonumber(gem1), tonumber(gem2), tonumber(gem3), tonumber(gem4) }),
    random_suffix = tonumber(suffixId),
    unique_id = tonumber(uniqueId),
    link_level = tonumber(linkLevel),
    refId = tonumber(reforgeId),
    upgrade = tonumber(upgradeId),
  }
  return data
end

local function GetItemUpgradeLevel(unit, slotId)
  scanningTooltip:ClearLines()
  scanningTooltip:SetInventoryItem(unit, slotId)

  local regions = { scanningTooltip:GetRegions() }
  local pattern = ITEM_UPGRADE_TOOLTIP_FORMAT and ITEM_UPGRADE_TOOLTIP_FORMAT:gsub("%%d", "(%%d)") or nil

  for _, region in ipairs(regions) do
    if region and region:GetObjectType() == "FontString" then
      local text = region:GetText()
      if text and pattern then
        local _, _, currentLevel = text:find(pattern)
        if currentLevel then
          return tonumber(currentLevel)
        end
      end
    end
  end

  return nil
end

local function GetHandTinker(unit)
  scanningTooltip:ClearLines()
  scanningTooltip:SetInventoryItem(unit, INVSLOT_HAND)

  local regions = { scanningTooltip:GetRegions() }
  local onUse = ITEM_SPELL_TRIGGER_ONUSE or "Use:";
  local cdMinutes = ITEM_COOLDOWN_TOTAL_MIN or "min";
  local cdSeconds = ITEM_COOLDOWN_TOTAL_SEC or "sec";

  for _, region in ipairs(regions) do
    if region and region:GetObjectType() == "FontString" then
      local text = region:GetText()
      if text then
        if text:find(onUse .. ".+1.?9.?20.+" .. cdMinutes) then
          return 4898
        end
        if text:find(onUse .. ".+2.?8.?80.+" .. cdMinutes) then
          return 4697
        end
        if text:find(onUse .. ".+42.?0?00.+63.?0?00.+" .. cdSeconds) then
          return 4698
        end
      end
    end
  end

  return nil
end

local function BuildEquipmentSpec(method)
  local equipment = {
    version = EXPORT_VERSION,
    items = {},
  }

  for itemIndex, slotId in ipairs(EQUIPMENT_SLOT_LAYOUT) do
    local itemLink = GetInventoryItemLink(UNIT_PLAYER, slotId)
    if itemLink then
      local parsed = ParseItemLink(itemLink)
      if parsed and parsed.id then
        local itemData = {
          id = parsed.id,
          enchant = parsed.enchant,
        }

        if parsed.gems then
          itemData.gems = parsed.gems
        end

        if parsed.random_suffix and parsed.random_suffix ~= 0 then
          itemData.random_suffix = parsed.random_suffix
        end

        local methodItem = method and method.items and method.items[itemIndex]
        if methodItem then
          if methodItem.reforge and methodItem.reforge > 0 then
            itemData.reforging = REFORGE_TABLE_BASE + methodItem.reforge
          else
            itemData.reforging = nil
          end
        elseif parsed.refId and parsed.refId > 0 then
          itemData.reforging = parsed.refId
        end

        if parsed.upgrade and parsed.upgrade > 0 then
          itemData.upgrade_step = parsed.upgrade
        else
          local upgrade = GetItemUpgradeLevel(UNIT_PLAYER, slotId)
          if upgrade and upgrade > 0 then
            itemData.upgrade_step = upgrade
          end
        end

        if slotId == INVSLOT_HAND then
          local tinker = GetHandTinker(UNIT_PLAYER)
          if tinker and tinker ~= 0 then
            itemData.tinker = tinker
          end
        end

        equipment.items[itemIndex] = itemData
      end
    end
  end

  return equipment
end

local function CreateCharacterSkeleton()
  local name, realm = UnitFullName(UNIT_PLAYER)
  local _, englishClass = UnitClass(UNIT_PLAYER)
  local _, englishRace = UnitRace(UNIT_PLAYER)
  local level = UnitLevel(UNIT_PLAYER)

  local race = englishRace
  if englishRace == "Pandaren" then
    local faction = UnitFactionGroup(UNIT_PLAYER)
    if faction and faction ~= "" then
      race = string.format("%s (%s)", englishRace, faction:sub(1, 1))
    end
  end

  local character = {
    version = EXPORT_VERSION,
    unit = UNIT_PLAYER,
    name = name,
    realm = realm,
    race = race,
    class = englishClass and englishClass:lower() or "",
    level = level,
    talents = CreateTalentString(),
    glyphs = CreateGlyphEntry(),
    professions = CreateProfessionEntry(),
    spec = GetSpecSlug(),
    gear = nil,
  }

  return character
end

local function EnsureLibParse()
  if LibParse then
    return true
  end

  if LibStub then
    LibParse = LibStub("LibParse", true)
  end

  return LibParse ~= nil
end

function WowSimsExport.Generate(method)
  if not EnsureLibParse() then
    return nil, "LibParse not available"
  end

  local character = CreateCharacterSkeleton()
  character.gear = BuildEquipmentSpec(method)

  if not character.spec or character.spec == "" then
    local specName = GetSpecDisplay()
    if specName and specName ~= "" then
      character.spec = specName:lower():gsub("%s+", "_")
    end
  end

  local success, result = pcall(function()
    return LibParse:JSONEncode(character)
  end)

  if success then
    return result
  end

  return nil, result
end

function WowSimsExport.GenerateFromMethod(method)
  return WowSimsExport.Generate(method)
end

