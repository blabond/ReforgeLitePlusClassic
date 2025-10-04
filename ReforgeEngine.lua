local addonName, addonTable = ...
local REFORGE_COEFF = addonTable.REFORGE_COEFF

local abs = math.abs
local max = math.max

local EXACT_UNDER_TOLERANCE = 3
local EXACT_OVER_TOLERANCE = 35
local ReforgeLite = addonTable.ReforgeLite
local L = addonTable.L
local DeepCopy = addonTable.DeepCopy
local Print = addonTable.print
local playerClass, playerRace = addonTable.playerClass, addonTable.playerRace
local statIds = addonTable.statIds
local NUM_CAPS = addonTable.NUM_CAPS or 2

local function GetMaxMethodAlternatives()
  return addonTable.MAX_METHOD_ALTERNATIVES or 5
end

local GetItemStats = addonTable.GetItemStatsUp
local TABLE_SIZE = 50000
local MAX_CORE_STATES = addonTable.MAX_CORE_STATES or 4000
local CORE_SPEED_PRESET_MULTIPLIERS = addonTable.CORE_SPEED_PRESET_MULTIPLIERS or {
  normal = 1,
  fast = 0.25,
  extra_fast = 0.045,
}

local function CountConfiguredCaps(caps)
  local count = 0
  if not caps then
    return count
  end
  for i = 1, NUM_CAPS do
    local cap = caps[i]
    if cap and cap.stat and cap.stat > 0 then
      local points = cap.points
      if points and #points > 0 then
        count = count + 1
      end
    end
  end
  return count
end

local function CreateZeroedArray()
  local arr = {}
  for i = 1, NUM_CAPS do
    arr[i] = 0
  end
  return arr
end

local function EncodeState(values)
  local key = 0
  local multiplier = 1
  for i = 1, NUM_CAPS do
    key = key + (values[i] or 0) * multiplier
    multiplier = multiplier * TABLE_SIZE
  end
  return key
end

local function CopyArray(values)
  local copy = {}
  for i = 1, NUM_CAPS do
    copy[i] = values[i] or 0
  end
  return copy
end

local function GetCapIndex(caps, stat)
  if not stat or stat == 0 then
    return nil
  end
  for i = 1, NUM_CAPS do
    if caps[i] and caps[i].stat == stat then
      return i
    end
  end
end

local function GetCapMismatchPenalty(cap, value, weights)
  if not cap or not cap.stat or cap.stat == 0 then
    return 0
  end

  local penalty = 0
  local baseWeight = max(abs(weights[cap.stat] or 0), 1)
  for _, point in ipairs(cap.points or {}) do
    local targetValue = point.value or 0
    if point.method == addonTable.StatCapMethods.Exactly then
      if cap.forceExactAsAtLeast then
        local deficit = targetValue - value
        if deficit > 0 then
          penalty = penalty + deficit * baseWeight * 5
        end
      else
        local diff = value - targetValue
        if diff > 0 then
          if diff > EXACT_OVER_TOLERANCE then
            penalty = penalty + (diff - EXACT_OVER_TOLERANCE) * baseWeight * 50
          end
          penalty = penalty + diff * baseWeight * 50
        else
          local deficit = -diff
          if deficit > EXACT_UNDER_TOLERANCE then
            penalty = penalty + (deficit - EXACT_UNDER_TOLERANCE) * baseWeight * 50
          end
          penalty = penalty + deficit * baseWeight * 10
        end
      end
    elseif point.method == addonTable.StatCapMethods.AtLeast then
      local deficit = targetValue - value
      if deficit > 0 then
        penalty = penalty + deficit * baseWeight * 5
      end
    elseif point.method == addonTable.StatCapMethods.AtMost then
      local excess = value - targetValue
      if excess > 0 then
        penalty = penalty + excess * baseWeight * 5
      end
    end
  end

  return penalty
end

local function EvaluateStateHeuristic(self, data, capValues, baseScore)
  local heuristic = baseScore
  for capIndex = 1, NUM_CAPS do
    local cap = data.caps[capIndex]
    local stat = cap and cap.stat
    if stat and stat > 0 then
      local value = capValues[capIndex] or 0
      heuristic = heuristic + self:GetCapScore(cap, value)
      heuristic = heuristic - GetCapMismatchPenalty(cap, value, data.weights)
    end
  end
  return heuristic
end

---------------------------------------------------------------------------------------

function ReforgeLite:GetStatMultipliers()
  local result = {}
  for _, v in ipairs(self.itemData) do
    local info = v.itemInfo
    if info and info.itemId and addonTable.AmplificationItems[info.itemId] then
      local factor = 1 + 0.01 * Round(addonTable.GetRandPropPoints(info.ilvl, 2) / 420)
      result[statIds.HASTE] = (result[statIds.HASTE] or 1) * factor
      result[statIds.MASTERY] = (result[statIds.MASTERY] or 1) * factor
      result[statIds.SPIRIT] = (result[statIds.SPIRIT] or 1) * factor
    end
  end
  return result
end

local CASTER_SPEC_noSpiritHit = {}
local CASTER_SPEC = {[statIds.EXP] = {[statIds.HIT] = 1}}
local HYBRID_SPEC = {[statIds.SPIRIT] = {[statIds.HIT] = 1}, [statIds.EXP] = {[statIds.HIT] = 1}}
local STAT_CONVERSIONS = {
  DRUID = {
    specs = {
      [SPEC_DRUID_BALANCE] = HYBRID_SPEC,
      [4] = CASTER_SPEC -- Resto
    }
  },
  MAGE = { base = CASTER_SPEC_noSpiritHit },
  MONK = {
    specs = {
      [SPEC_MONK_MISTWEAVER] = {
        [statIds.SPIRIT] = {[statIds.HIT] = 0.5, [statIds.EXP] = 0.5},
        [statIds.HASTE] = {[statIds.HASTE] = 0.5},
      }
    }
  },
  PALADIN = {
    specs = {
      [1] = CASTER_SPEC -- Holy
    }
  },
  PRIEST = {
    base = CASTER_SPEC,
    specs = {
      [SPEC_PRIEST_SHADOW] = HYBRID_SPEC -- Shadow
    }
  },
  SHAMAN = {
    specs = {
      [1] = HYBRID_SPEC, -- Ele
      [SPEC_SHAMAN_RESTORATION] = CASTER_SPEC -- Resto
    }
  },
  WARLOCK = { base = CASTER_SPEC_noSpiritHit },
}

function ReforgeLite:GetConversion()
  self.conversion = wipe(self.conversion or {})

  local classConversionInfo = STAT_CONVERSIONS[playerClass]
  if classConversionInfo then
    if classConversionInfo.base then
      addonTable.MergeTables(self.conversion, classConversionInfo.base)
    end

    local spec = C_SpecializationInfo.GetSpecialization()
    if spec and classConversionInfo.specs and classConversionInfo.specs[spec] then
      addonTable.MergeTables(self.conversion, classConversionInfo.specs[spec])
    end
  end

  local raceToken = playerRace
  if raceToken and raceToken:upper() == "HUMAN" then
    self.conversion[statIds.SPIRIT] = self.conversion[statIds.SPIRIT] or {}
    self.conversion[statIds.SPIRIT][statIds.SPIRIT] = (self.conversion[statIds.SPIRIT][statIds.SPIRIT] or 1) * 0.03
  end
end


function ReforgeLite:UpdateMethodStats (method)
  local mult = self:GetStatMultipliers()
  local oldstats = {}
  method.stats = {}
  for i = 1, #self.itemStats do
    oldstats[i] = self.itemStats[i].getter ()
    method.stats[i] = oldstats[i] / (mult[i] or 1)
  end
  method.items = method.items or {}
  for i = 1, #self.itemData do
    local slotData = self.itemData[i]
    local info = slotData.itemInfo
    local orgstats = info and GetItemStats(info) or {}
    local stats = info and GetItemStats(info, { ilvlCap = self.pdb.ilvlCap }) or {}
    local reforge = info and info.reforge

    method.items[i] = method.items[i] or {}

    method.items[i].stats = nil
    method.items[i].amount = nil

    for s, v in ipairs(self.itemStats) do
      method.stats[s] = method.stats[s] - (orgstats[v.name] or 0) + (stats[v.name] or 0)
    end
    if reforge then
      local src, dst = unpack(self.reforgeTable[reforge])
      local amount = floor ((orgstats[self.itemStats[src].name] or 0) * REFORGE_COEFF)
      method.stats[src] = method.stats[src] + amount
      method.stats[dst] = method.stats[dst] - amount
    end
    if method.items[i].src and method.items[i].dst then
      method.items[i].amount = floor ((stats[self.itemStats[method.items[i].src].name] or 0) * REFORGE_COEFF)
      method.stats[method.items[i].src] = method.stats[method.items[i].src] - method.items[i].amount
      method.stats[method.items[i].dst] = method.stats[method.items[i].dst] + method.items[i].amount
    end
  end

  for s, f in pairs(mult) do
    method.stats[s] = Round(method.stats[s] * f)
  end

  for src, c in pairs(self.conversion) do
    for dst, f in pairs(c) do
      method.stats[dst] = method.stats[dst] + Round((method.stats[src] - oldstats[src]) * f)
    end
  end
end

function ReforgeLite:FinalizeReforge (data)
  for _,item in ipairs(data.method.items) do
    item.reforge = nil
    if item.src and item.dst then
      item.reforge = self:GetReforgeTableIndex(item.src, item.dst)
    end
    item.stats = nil
  end
  self:UpdateMethodStats (data.method)
end

function ReforgeLite:ResetMethod ()
  local method = { items = {} }
  for i = 1, #self.itemData do
    method.items[i] = {}
    local info = self.itemData[i].itemInfo
    if info and info.reforge then
      method.items[i].reforge = info.reforge
      method.items[i].src, method.items[i].dst = unpack(self.reforgeTable[info.reforge])
    end
  end
  method.isPlaceholder = true
  self:UpdateMethodStats (method)
  self.pdb.methodOrigin = addonName
  self:SetMethodAlternatives({method}, 1)
  self:UpdateMethodCategory()
end

function ReforgeLite:CapAllows (cap, value)
  for _,v in ipairs(cap.points) do
    if v.method == addonTable.StatCapMethods.AtLeast and value < v.value then
      return false
    elseif v.method == addonTable.StatCapMethods.AtMost and value > v.value then
      return false
    elseif v.method == addonTable.StatCapMethods.Exactly then
      if cap.forceExactAsAtLeast then
        if value < v.value then
          return false
        end
      else
        if value > (v.value + EXACT_OVER_TOLERANCE) + 0.5 then
          return false
        end
        if value < (v.value - EXACT_UNDER_TOLERANCE) - 0.5 then
          return false
        end
      end
    end
  end
  return true
end

function ReforgeLite:IsItemLocked (slot)
  local slotData = self.itemData[slot]
  local info = slotData and slotData.itemInfo
  if not info or not info.link then
    return true
  end
  return (info.ilvl or 0) < 200
  or self.pdb.itemsLocked[info.itemGUID]
end

------------------------------------- CLASSIC REFORGE ------------------------------

function ReforgeLite:MakeReforgeOption(item, data, src, dst)
  local deltas = CreateZeroedArray()
  local dscore = 0
  if src and dst then
    local amountRaw = floor(item.stats[src] * REFORGE_COEFF)
    local amount = Round(amountRaw * (data.mult[src] or 1))
    local capIndex = GetCapIndex(data.caps, src)
    if capIndex then
      deltas[capIndex] = deltas[capIndex] - amount
    else
      dscore = dscore - data.weights[src] * amount
    end
    if data.conv[src] then
      for to, factor in pairs(data.conv[src]) do
        local conv = Round(amount * factor)
        capIndex = GetCapIndex(data.caps, to)
        if capIndex then
          deltas[capIndex] = deltas[capIndex] - conv
        else
          dscore = dscore - data.weights[to] * conv
        end
      end
    end
    amount = Round(amountRaw * (data.mult[dst] or 1))
    capIndex = GetCapIndex(data.caps, dst)
    if capIndex then
      deltas[capIndex] = deltas[capIndex] + amount
    else
      dscore = dscore + data.weights[dst] * amount
    end
    if data.conv[dst] then
      for to, factor in pairs(data.conv[dst]) do
        local conv = Round(amount * factor)
        capIndex = GetCapIndex(data.caps, to)
        if capIndex then
          deltas[capIndex] = deltas[capIndex] + conv
        else
          dscore = dscore + data.weights[to] * conv
        end
      end
    end
  end
  return {deltas = deltas, src = src, dst = dst, score = dscore}
end

function ReforgeLite:GetItemReforgeOptions (item, data, slot)
  if self:IsItemLocked (slot) then
    local src, dst = nil, nil
    local info = self.itemData[slot].itemInfo
    if info and info.reforge then
      src, dst = unpack(self.reforgeTable[info.reforge])
    end
    return { self:MakeReforgeOption (item, data, src, dst) }
  end
  local aopt = {}
  local baseOption = self:MakeReforgeOption (item, data)
  aopt[EncodeState(baseOption.deltas)] = baseOption
  for src = 1, #self.itemStats do
    if item.stats[src] > 0 then
      for dst = 1, #self.itemStats do
        if item.stats[dst] == 0 then
          local o = self:MakeReforgeOption (item, data, src, dst)
          local pos = EncodeState(o.deltas)
          if not aopt[pos] or aopt[pos].score < o.score then
            aopt[pos] = o
          end
        end
      end
    end
  end
  local opt = {}
  for _, v in pairs (aopt) do
    tinsert (opt, v)
  end
  return opt
end

function ReforgeLite:InitializeMethod()
  local method = { items = {} }
  local orgitems = {}
  local statsSum = 0
  for i = 1, #self.itemData do
    method.items[i] = {}
    method.items[i].stats = {}
    orgitems[i] = {}
    local info = self.itemData[i].itemInfo
    local stats = info and GetItemStats(info, { ilvlCap = self.pdb.ilvlCap }) or {}
    local orgstats = info and GetItemStats(info) or {}
    for j, v in ipairs(self.itemStats) do
      method.items[i].stats[j] = (stats[v.name] or 0)
      orgitems[i][j] = (orgstats[v.name] or 0)
      statsSum = statsSum + method.items[i].stats[j]
    end
  end
  return method, orgitems, statsSum
end

function ReforgeLite:InitReforgeClassic()
  local method, orgitems, statsSum = self:InitializeMethod()
  local data = {}
  data.method = method
  data.weights = DeepCopy (self.pdb.weights)
  data.caps = DeepCopy (self.pdb.caps)
  while #data.caps > NUM_CAPS do
    table.remove(data.caps)
  end
  for i = 1, NUM_CAPS do
    data.caps[i] = data.caps[i] or { stat = 0, points = {} }
    data.caps[i].points = data.caps[i].points or {}
    data.caps[i].init = 0
  end
  data.initial = {}

  data.mult = self:GetStatMultipliers()
  data.conv = DeepCopy(self.conversion)

  for i = 1, NUM_CAPS do
    for point = 1, #data.caps[i].points do
      local preset = data.caps[i].points[point].preset
      if self.capPresets[preset] == nil then
        preset = 1
      end
      if self.capPresets[preset].getter then
        data.caps[i].points[point].value = floor(self.capPresets[preset].getter())
      end
    end
  end

  local cheat = math.ceil(statsSum / 1000)
  if cheat < 1 then
    cheat = 1
  end
  if NUM_CAPS > 2 then
    cheat = cheat * (NUM_CAPS - 1)
  end
  data.cheat = cheat

  for i = 1, #self.itemStats do
    data.initial[i] = self.itemStats[i].getter() / (data.mult[i] or 1)
    for j = 1, #orgitems do
      data.initial[i] = data.initial[i] - orgitems[j][i]
    end
  end
  local reforged = {}
  for i = 1, #self.itemStats do
    reforged[i] = 0
  end
  for i = 1, #data.method.items do
    local info = self.itemData[i].itemInfo
    local reforge = info and info.reforge
    if reforge then
      local src, dst = unpack(self.reforgeTable[reforge])
      local amount = floor (method.items[i].stats[src] * REFORGE_COEFF)
      data.initial[src] = data.initial[src] + amount
      data.initial[dst] = data.initial[dst] - amount
      reforged[src] = reforged[src] - amount
      reforged[dst] = reforged[dst] + amount
    end
  end
  for src, c in pairs(data.conv) do
    for dst, f in pairs(c) do
      data.initial[dst] = data.initial[dst] - Round(reforged[src] * (data.mult[src] or 1) * f)
    end
  end
  for i = 1, NUM_CAPS do
    local stat = data.caps[i].stat
    if stat and stat > 0 then
      local init = data.initial[stat]
      for j = 1, #data.method.items do
        init = init + data.method.items[j].stats[stat]
      end
      data.caps[i].init = init
    else
      data.caps[i].init = 0
    end
  end

  table.sort(data.caps, function(a, b)
    local aZero = (a.stat or 0) == 0 and 1 or 0
    local bZero = (b.stat or 0) == 0 and 1 or 0
    if aZero ~= bZero then
      return aZero < bZero
    end
    return false
  end)

  local seen = {}
  for i = 1, NUM_CAPS do
    local stat = data.caps[i].stat
    if stat and stat > 0 then
      if seen[stat] then
        data.caps[i].stat = 0
        data.caps[i].init = 0
      else
        seen[stat] = true
      end
    else
      data.caps[i].stat = 0
      data.caps[i].init = 0
    end
  end

  for src, conv in pairs(data.conv) do
    if data.weights[src] == 0 then
      local relevant = false
      for i = 1, NUM_CAPS do
        local capStat = data.caps[i] and data.caps[i].stat
        if capStat and conv[capStat] then
          relevant = true
          break
        end
      end
      if relevant then
        if src == addonTable.statIds.EXP then
          data.weights[src] = -1
        else
          data.weights[src] = 1
        end
      end
    end
  end

  local configuredCaps = CountConfiguredCaps(data.caps)
  local overrideStates = addonTable.MAX_CORE_STATES
  if overrideStates ~= nil then
    MAX_CORE_STATES = overrideStates
  else
    local baseStates
    if configuredCaps >= 3 then
      baseStates = 90000
    else
      baseStates = 125000
    end
    local preset = addonTable.CORE_SPEED_PRESET or "normal"
    local multiplier = CORE_SPEED_PRESET_MULTIPLIERS[preset] or 1
    MAX_CORE_STATES = math.floor(baseStates * multiplier + 0.5)
  end

  return data
end

function ReforgeLite:ComputeReforgeCore (data, reforgeOptions)
  local scores, codes = {}, {}
  local schar = string.char
  local stateCache = {}
  local initialState = CreateZeroedArray()
  for i = 1, NUM_CAPS do
    initialState[i] = Round(data.caps[i] and data.caps[i].init or 0)
  end
  local initialKey = EncodeState(initialState)
  scores[initialKey] = 0
  codes[initialKey] = ""
  stateCache[initialKey] = initialState
  local runYieldCheck = self.RunYieldCheck
  for i = 1, #self.itemData do
    local newscores, newcodes = {}, {}
    local newStateCache = {}
    local newHeuristic = {}
    local opt = reforgeOptions[i]
    local optionCount = 0
    if opt then
      optionCount = #opt
    else
      opt = {}
    end
    if optionCount == 0 then
      optionCount = 1
    end
    for k, score in pairs(scores) do
      local code = codes[k]
      local baseState = stateCache[k] or CreateZeroedArray()
      for j = 1, #opt do
        local o = opt[j]
        local nscore = score + o.score
        local newState = CopyArray(baseState)
        local optionDeltas = o.deltas or {}
        for capIndex = 1, NUM_CAPS do
          local delta = optionDeltas[capIndex]
          if delta and delta ~= 0 then
            newState[capIndex] = Round((newState[capIndex] or 0) + delta)
          end
        end
        local nk = EncodeState(newState)
        local heuristicScore = EvaluateStateHeuristic(self, data, newState, nscore)
        local existingHeuristic = newHeuristic[nk]
        if existingHeuristic == nil or heuristicScore > existingHeuristic or (heuristicScore == existingHeuristic and nscore > (newscores[nk] or -math.huge)) then
          newscores[nk] = nscore
          newcodes[nk] = code .. schar(j)
          newStateCache[nk] = newState
          newHeuristic[nk] = heuristicScore
        end
      end
      runYieldCheck(self, optionCount)
    end

    if MAX_CORE_STATES and MAX_CORE_STATES > 0 then
      local count = 0
      for _ in pairs(newscores) do
        count = count + 1
      end
      if count > MAX_CORE_STATES then
        local ordered = {}
        for key, heuristicScore in pairs(newHeuristic) do
          ordered[#ordered + 1] = { key = key, heuristic = heuristicScore, score = newscores[key] or -math.huge }
        end
        table.sort(ordered, function(a, b)
          if a.heuristic ~= b.heuristic then
            return a.heuristic > b.heuristic
          end
          return a.score > b.score
        end)
        for index = MAX_CORE_STATES + 1, #ordered do
          local key = ordered[index].key
          newscores[key] = nil
          newcodes[key] = nil
          newStateCache[key] = nil
          newHeuristic[key] = nil
        end
      end
    end

    scores, codes = newscores, newcodes
    stateCache = newStateCache
  end
  return scores, codes
end

function ReforgeLite:GetCapTarget(cap)
  local target
  for _, p in ipairs(cap.points or {}) do
    if p.method == addonTable.StatCapMethods.Exactly then
      return p.value
    elseif p.method == addonTable.StatCapMethods.AtLeast then
      target = math.max(target or p.value, p.value)
    elseif p.method == addonTable.StatCapMethods.AtMost then
      target = math.min(target or p.value, p.value)
    end
  end
  return target or 0
end

local function CollectExactCapIndices(caps)
  local indices = {}
  for capIndex = 1, NUM_CAPS do
    local cap = caps[capIndex]
    if cap and cap.points then
      for _, point in ipairs(cap.points) do
        if point.method == addonTable.StatCapMethods.Exactly then
          table.insert(indices, capIndex)
          break
        end
      end
    end
  end
  return indices
end

function ReforgeLite:ChooseReforgeClassic (data, reforgeOptions, scores, codes, exactFallbackApplied)
  local maxPriority = 2 ^ NUM_CAPS
  local bestPerPriority = {}
  local maxAlternatives = GetMaxMethodAlternatives()
  local exactCapIndices = CollectExactCapIndices(data.caps)
  local anyExactSatisfied = (#exactCapIndices == 0)
  for k, baseScore in pairs(scores) do
    self:RunYieldCheck()
    local code = codes[k]
    local capValues = CreateZeroedArray()
    for capIndex = 1, NUM_CAPS do
      capValues[capIndex] = data.caps[capIndex] and data.caps[capIndex].init or 0
    end
    for i = 1, #code do
      local option = reforgeOptions[i][code:byte(i)]
      local optionDeltas = option.deltas or {}
      for capIndex = 1, NUM_CAPS do
        capValues[capIndex] = capValues[capIndex] + (optionDeltas[capIndex] or 0)
      end
    end
    local satisfied = {}
    local score = baseScore
    for capIndex = 1, NUM_CAPS do
      local cap = data.caps[capIndex]
      local stat = cap and cap.stat
      if stat and stat > 0 then
        local value = capValues[capIndex]
        local allows = self:CapAllows(cap, value)
        satisfied[capIndex] = allows
        score = score + self:GetCapScore(cap, value)
        score = score - GetCapMismatchPenalty(cap, value, data.weights)
      else
        satisfied[capIndex] = true
      end
    end
    if #exactCapIndices > 0 and not anyExactSatisfied then
      local entryExactSatisfied = true
      for _, exactIndex in ipairs(exactCapIndices) do
        if not satisfied[exactIndex] then
          entryExactSatisfied = false
          break
        end
      end
      if entryExactSatisfied then
        anyExactSatisfied = true
      end
    end
    do
      local hitIndex = GetCapIndex(data.caps, statIds.HIT)
      if hitIndex then
        local hitCap = data.caps[hitIndex]
        local target = self:GetCapTarget(hitCap)
        if target and target > 0 then
          local diff = (capValues[hitIndex] or 0) - target
          local over  = (diff > 0) and diff or 0
          local under = (diff < 0) and -diff or 0
          local w = (data.weights[statIds.HIT] ~= 0) and 0.05 or 0.02
          score = score - under * w - over * (w * 2)
        end
      end
    end

    local priority = 0
    for capIndex = 1, NUM_CAPS do
      priority = priority * 2 + (satisfied[capIndex] and 1 or 0)
    end
    bestPerPriority[priority] = bestPerPriority[priority] or {}
    local bucket = bestPerPriority[priority]
    local entry = { code = code, score = score, satisfied = CopyArray(satisfied), priority = priority }
    local inserted = false
    for index, existing in ipairs(bucket) do
      if score > existing.score then
        table.insert(bucket, index, entry)
        inserted = true
        break
      end
    end
    if not inserted then
      table.insert(bucket, entry)
    end

    if #bucket > maxAlternatives then
      table.remove(bucket)
    end
  end
  if not exactFallbackApplied and #exactCapIndices > 0 and not anyExactSatisfied then
    local fallbackCaps = {}
    for _, capIndex in ipairs(exactCapIndices) do
      local cap = data.caps[capIndex]
      if cap then
        cap.forceExactAsAtLeast = true
        table.insert(fallbackCaps, cap)
      end
    end
    local results = self:ChooseReforgeClassic(data, reforgeOptions, scores, codes, true)
    for _, cap in ipairs(fallbackCaps) do
      cap.forceExactAsAtLeast = nil
    end
    return results
  end
  local results = {}
  for priority = maxPriority - 1, 0, -1 do
    local bucket = bestPerPriority[priority]
    if bucket then
      for _, entry in ipairs(bucket) do
        table.insert(results, entry)

        if #results >= maxAlternatives then
          return results
        end
      end
    end
  end
  return results
end

function ReforgeLite:ComputeReforge()
  local data = self:InitReforgeClassic()
  local reforgeOptions = {}
  for i = 1, #self.itemData do
    reforgeOptions[i] = self:GetItemReforgeOptions(data.method.items[i], data, i)
  end

  self.__chooseLoops = nil

  local scores, codes = self:ComputeReforgeCore(data, reforgeOptions)

  self.__chooseLoops = nil

  local alternatives = self:ChooseReforgeClassic(data, reforgeOptions, scores, codes)
  if not alternatives or #alternatives == 0 then
    scores, codes = nil, nil
    collectgarbage("collect")
    if Print and L then
      Print(L["No reforge"])
    end
    return
  end
  scores, codes = nil, nil
  collectgarbage ("collect")

  local methods = {}
  for index, entry in ipairs(alternatives) do
    local methodCopy = DeepCopy(data.method)
    local code = entry.code
    for i = 1, #methodCopy.items do
      local opt = reforgeOptions[i][code:byte(i)]
      if data.conv[addonTable.statIds.SPIRIT] and data.conv[addonTable.statIds.SPIRIT][addonTable.statIds.HIT] == 1 then
        if opt.dst == addonTable.statIds.HIT and methodCopy.items[i].stats[addonTable.statIds.SPIRIT] == 0 then
          opt.dst = addonTable.statIds.SPIRIT
        end
      end
      methodCopy.items[i].src = opt.src
      methodCopy.items[i].dst = opt.dst
    end

    self:FinalizeReforge ({ method = methodCopy })

    methodCopy.isPlaceholder = nil
    methodCopy.score = entry.score
    methodCopy.priority = entry.priority
    methodCopy.satisfied = CopyArray(entry.satisfied)
    methodCopy.code = entry.code
    methods[index] = methodCopy
  end

  if #methods > 0 then
    self.pdb.methodOrigin = addonName
    self:SetMethodAlternatives(methods, 1)
    self:UpdateMethodCategory ()
  end
end

function ReforgeLite:Compute()
  self:ComputeReforge()
  self:EndCompute()
end

local NORMAL_STATUS_CODES = { suspended = true, running = true }
local routine

function ReforgeLite:ResumeCompute()
  coroutine.resume(routine)
  if not NORMAL_STATUS_CODES[coroutine.status(routine)] then
    self:EndCompute()
  end
end

function ReforgeLite:ResumeComputeNextFrame()
  RunNextFrame(function() self:ResumeCompute() end)
end

function ReforgeLite:RunYieldCheck(step)
  local loops = (self.__chooseLoops or 0) + (step or 1)
  if loops >= self.db.speed then
    self.__chooseLoops = nil
    self:ResumeComputeNextFrame()
    coroutine.yield()
  else
    self.__chooseLoops = loops
  end
end

function ReforgeLite:StartCompute()
  self.computeInProgress = true
  if self.UpdateSpeedPresetRadiosEnabled then
    self:UpdateSpeedPresetRadiosEnabled()
  end
  if self.UpdateMethodChecks then
    self:UpdateMethodChecks()
  end
  routine = coroutine.create(function() self:Compute() end)
  self:ResumeComputeNextFrame()
end

function ReforgeLite:EndCompute()
  self.computeInProgress = false
  self.computeButton:RenderText(L["Compute"])
  addonTable.GUI:Unlock()
  if self.UpdateSpeedPresetRadiosEnabled then
    self:UpdateSpeedPresetRadiosEnabled()
  end
  if self.UpdateMethodChecks then
    self:UpdateMethodChecks()
  end
end
