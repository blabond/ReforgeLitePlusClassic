local _, addonTable = ...

local floor = math.floor
local tonumber = tonumber

local RandPropPoints = addonTable.RandPropPoints or {}
local ItemUpgradeStats = addonTable.ItemUpgradeStats or {}
local ItemStatsRef = addonTable.ItemStatsRef or {}

local C_Item = C_Item
local GetBaseItemStats = GetItemStats
local GetItemInfo = GetItemInfo

function addonTable.GetRandPropPoints(iLvl, t)
    return (RandPropPoints[iLvl] and RandPropPoints[iLvl][t] or 0)
end

local function CoerceItemInfo(itemInfoOrLink)
    if type(itemInfoOrLink) == "table" then
        return itemInfoOrLink
    elseif itemInfoOrLink then
        return { link = itemInfoOrLink }
    end
end

local function EnsureItemInfoTable(itemInfoOrLink)
    local itemInfo = CoerceItemInfo(itemInfoOrLink)
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

addonTable.CoerceItemInfo = CoerceItemInfo
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

local function GetItemInfoUp(link, upgrade)
    local id = C_Item.GetItemInfoInstant(link)
    local iLvl = C_Item.GetDetailedItemLevelInfo(id)
    return id, iLvl + (upgrade or 0) * 4, iLvl
end

function addonTable.GetItemStatsUp(link, upgrade)
    local result = GetItemStats(link)
    if result and upgrade and upgrade > 0 then
        local id, iLvl, iLvlBase = GetItemInfoUp(link, upgrade)
        local budget, ref
        if RandPropPoints[iLvl] and ItemUpgradeStats[id] then
            budget = RandPropPoints[iLvl][ItemUpgradeStats[id][1]]
            ref = ItemStatsRef[ItemUpgradeStats[id][2] + 1]
        end
        for sid, sv in ipairs(addonTable.itemStats) do
            if result[sv.name] then
                if budget and ref and ref[sid] then
                    result[sv.name] = floor(ref[sid][1] * budget * 0.0001 - ref[sid][2] * 160 + 0.5)
                else
                    result[sv.name] = floor(tonumber(result[sv.name]) * math.pow(1.15, (iLvl - iLvlBase) / 15))
                end
            end
        end
    end
    return result
end

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

function addonTable.SafeGetItemStats(itemInfoOrLink, overrides, upgradeOverride)
    local handler = addonTable.GetItemStatsUp
    if handler then
        local link = itemInfoOrLink
        local upgrade = upgradeOverride

        if type(itemInfoOrLink) == "table" then
            link = itemInfoOrLink.link

            if upgrade == nil then
                if type(overrides) == "number" then
                    upgrade = overrides
                elseif type(overrides) == "table" then
                    upgrade = overrides.upgradeLevel or overrides[1]
                end
            end

            if upgrade == nil and itemInfoOrLink.upgradeLevel ~= nil then
                upgrade = itemInfoOrLink.upgradeLevel
            end
        else
            if upgrade == nil and type(overrides) == "number" then
                upgrade = overrides
            end
        end

        if type(upgrade) ~= "number" then
            upgrade = tonumber(upgrade)
        end

        if not upgrade then
            upgrade = 0
        end

        if type(link) ~= "string" or link == "" then
            return {}
        end

        local stats = handler(link, upgrade)
        if not stats then
            return {}
        end

        return stats
    end

    local link = itemInfoOrLink
    if type(link) == "table" then
        link = link.link
    end

    if type(link) == "string" then
        return GetBaseItemStats(link)
    end

    return nil
end
