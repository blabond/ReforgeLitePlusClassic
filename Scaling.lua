local _, addonTable = ...

local RandPropPoints = addonTable.RandPropPoints
local ItemUpgradeStats = addonTable.ItemUpgradeStats
local ItemStatsRef = addonTable.ItemStatsRef

function addonTable.GetRandPropPoints(iLvl, t)
    return (RandPropPoints[iLvl] and RandPropPoints[iLvl][t] or 0)
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

local function NormalizeUpgradeArgs(arg1, arg2)
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
    if upgradeLevel and upgradeLevel < 0 then
        upgradeLevel = 0
    end
    if ilvlCap and ilvlCap < 0 then
        ilvlCap = 0
    end
    return ilvlCap, upgradeLevel
end

local function ComputeEffectiveItemLevel(link, ilvlCap, upgradeLevel)
    if not link then
        return nil
    end

    local itemId, upgradeId = link:match(ITEM_LINK_UPGRADE_PATTERN)
    itemId = tonumber(itemId)
    upgradeId = tonumber(upgradeId)

    local _, _, _, baseIlvl = C_Item.GetItemInfo(link)
    baseIlvl = baseIlvl or 0
    if baseIlvl == 0 then
        return itemId, 0, 0
    end

    local effectiveIlvl = baseIlvl
    if upgradeLevel and upgradeLevel > 0 then
        effectiveIlvl = effectiveIlvl + upgradeLevel * 4
    elseif baseIlvl >= 458 and upgradeId and ItemUpgrade[upgradeId] then
        effectiveIlvl = effectiveIlvl + ItemUpgrade[upgradeId]
    end

    if ilvlCap and ilvlCap > 0 and ilvlCap < effectiveIlvl then
        effectiveIlvl = ilvlCap
    end

    return itemId, baseIlvl, effectiveIlvl
end

function addonTable.GetItemInfoUp(link, opts)
    local ilvlCap, upgradeLevel
    if type(opts) == "table" then
        ilvlCap = opts.ilvlCap
        upgradeLevel = opts.upgradeLevel
    else
        ilvlCap = opts
    end

    local itemId, _, effectiveIlvl = ComputeEffectiveItemLevel(link, ilvlCap, upgradeLevel)
    return itemId, effectiveIlvl
end

function addonTable.GetItemStatsUp(link, arg1, arg2)
    local ilvlCap, upgradeLevel = NormalizeUpgradeArgs(arg1, arg2)
    local stats = GetItemStats(link)
    if not stats then
        return stats
    end

    local itemId, baseIlvl, effectiveIlvl = ComputeEffectiveItemLevel(link, ilvlCap, upgradeLevel)
    if not itemId or effectiveIlvl == baseIlvl then
        return stats
    end

    local budget, ref
    local itemStats = ItemUpgradeStats[itemId]
    if RandPropPoints[effectiveIlvl] and itemStats then
        budget = RandPropPoints[effectiveIlvl][itemStats[1]]
        ref = ItemStatsRef[itemStats[2] + 1]
    end

    for statIndex, statInfo in ipairs(addonTable.itemStats or {}) do
        local value = stats[statInfo.name]
        if value then
            if budget and ref and ref[statIndex] then
                stats[statInfo.name] = floor(ref[statIndex][1] * budget * 0.0001 - ref[statIndex][2] * 160 + 0.5)
            else
                stats[statInfo.name] = floor(tonumber(value) * math.pow(1.15, (effectiveIlvl - baseIlvl) / 15))
            end
        end
    end

    return stats
end
