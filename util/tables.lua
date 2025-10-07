local _, addonTable = ...

local function MergeTables(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return dst
    end

    for k, v in pairs(src) do
        if type(v) ~= "table" then
            if dst[k] == nil then
                dst[k] = v
            end
        else
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            MergeTables(dst[k], v)
        end
    end

    return dst
end
addonTable.MergeTables = MergeTables

local function DeepCopy(value, cache)
    if type(value) ~= "table" then
        return value
    end

    cache = cache or {}
    if cache[value] then
        return cache[value]
    end

    local copy = {}
    cache[value] = copy

    for key, innerValue in pairs(value) do
        copy[key] = DeepCopy(innerValue, cache)
    end

    return copy
end
addonTable.DeepCopy = DeepCopy
