local _, addonTable = ...

local floor, pow = math.floor, math.pow

local RandPropPoints = addonTable.RandPropPoints
local ItemUpgradeStats = addonTable.ItemUpgradeStats
local ItemStatsRef = addonTable.ItemStatsRef

function addonTable.GetRandPropPoints(iLvl, t)
    return (RandPropPoints[iLvl] and RandPropPoints[iLvl][t] or 0)
end

local function ResolveOverrides(itemInfo, overrides, upgradeOverride)
    local ilvlCap, upgradeLevel

    if type(overrides) == "table" then
        ilvlCap = tonumber(overrides.ilvlCap)
        upgradeLevel = tonumber(overrides.upgradeLevel)
    elseif type(overrides) == "number" then
        ilvlCap = overrides
        if type(upgradeOverride) == "number" then
            upgradeLevel = upgradeOverride
        end
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

local function GetBaseItemLevel(itemInfo)
    if itemInfo and itemInfo.itemId then
        local base = C_Item.GetDetailedItemLevelInfo(itemInfo.itemId)
        if base and base > 0 then
            return base
        end
    end
    if itemInfo and itemInfo.link then
        local _, _, _, itemLevel = C_Item.GetItemInfo(itemInfo.link)
        if itemLevel and itemLevel > 0 then
            return itemLevel
        end
    end
    return 0
end

local function EnsureItemInfoTable(itemInfoOrLink)
    if type(itemInfoOrLink) == "table" then
        return itemInfoOrLink
    elseif itemInfoOrLink then
        return { link = itemInfoOrLink }
    end
end

function addonTable.GetItemStatsUp(itemInfoOrLink, overrides, upgradeOverride)
    local itemInfo = EnsureItemInfoTable(itemInfoOrLink)
    if not itemInfo or not itemInfo.link then
        return {}
    end

    local stats = GetItemStats(itemInfo.link)
    if not stats then
        return {}
    end

    local ilvlCap, upgradeLevel = ResolveOverrides(itemInfo, overrides, upgradeOverride)

    local baseIlvl = GetBaseItemLevel(itemInfo)
    local infoUpgradeLevel = tonumber(itemInfo.upgradeLevel) or 0
    local currentIlvl = tonumber(itemInfo.ilvl) or baseIlvl
    if upgradeLevel and currentIlvl > 0 then
        local delta = infoUpgradeLevel - upgradeLevel
        if delta ~= 0 then
            currentIlvl = currentIlvl - (delta * 4)
        end
    end

    if currentIlvl < 0 then
        currentIlvl = 0
    end

    if currentIlvl <= 0 then
        currentIlvl = baseIlvl
    end

    if ilvlCap and ilvlCap > 0 then
        if currentIlvl == 0 or ilvlCap < currentIlvl then
            currentIlvl = ilvlCap
        end
    end

    if baseIlvl == 0 or currentIlvl == 0 or currentIlvl == baseIlvl then
        return stats
    end

    local budget, ref
    local itemId = itemInfo.itemId
    if itemId and RandPropPoints[currentIlvl] and ItemUpgradeStats[itemId] then
        local upgradeData = ItemUpgradeStats[itemId]
        budget = RandPropPoints[currentIlvl][upgradeData[1]]
        ref = ItemStatsRef[upgradeData[2] + 1]
    end

    for statIndex, statInfo in ipairs(addonTable.itemStats or {}) do
        local value = stats[statInfo.name]
        if value then
            if budget and ref and ref[statIndex] then
                stats[statInfo.name] = floor(ref[statIndex][1] * budget * 0.0001 - ref[statIndex][2] * 160 + 0.5)
            else
                stats[statInfo.name] = floor(tonumber(value) * pow(1.15, (currentIlvl - baseIlvl) / 15))
            end
        end
    end

    return stats
end
