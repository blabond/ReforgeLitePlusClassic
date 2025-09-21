local addonName, addonTable = ...
local REFORGE_COEFF = addonTable.REFORGE_COEFF

local ReforgeLite = addonTable.ReforgeLite
local L = addonTable.L
local DeepCopy = addonTable.DeepCopy
local Print = addonTable.print
local playerClass, playerRace = addonTable.playerClass, addonTable.playerRace
local statIds = addonTable.statIds
local NUM_CAPS = addonTable.NUM_CAPS or 2

local GetItemStats = addonTable.GetItemStatsUp
local TABLE_SIZE = 20000

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

---------------------------------------------------------------------------------------

function ReforgeLite:GetStatMultipliers()
  local result = {}
  if playerRace == "HUMAN" then
    result[addonTable.statIds.SPIRIT] = (result[addonTable.statIds.SPIRIT] or 1) * 1.03
  end
  for _, v in ipairs (self.itemData) do
    if v.item then
      local id, iLvl = addonTable.GetItemInfoUp(v.item)
      if id and addonTable.AmplificationItems[id] then
        local factor = 1 + 0.01 * Round(addonTable.GetRandPropPoints(iLvl, 2) / 420)
        result[addonTable.statIds.HASTE] = (result[addonTable.statIds.HASTE] or 1) * factor
        result[addonTable.statIds.MASTERY] = (result[addonTable.statIds.MASTERY] or 1) * factor
        result[addonTable.statIds.SPIRIT] = (result[addonTable.statIds.SPIRIT] or 1) * factor
      end
    end
  end
  return result
end

local CASTER_SPEC_WL = {}
local CASTER_SPEC = {[statIds.EXP] = {[statIds.HIT] = 1}}
local HYBRID_SPEC = {[statIds.SPIRIT] = {[statIds.HIT] = 1}, [statIds.EXP] = {[statIds.HIT] = 1}}
local STAT_CONVERSIONS = {
  DRUID = {
    specs = {
      [SPEC_DRUID_BALANCE] = HYBRID_SPEC,
      [4] = CASTER_SPEC -- Resto
    }
  },
  MAGE = { base = CASTER_SPEC },
  MONK = {
    specs = {
      [SPEC_MONK_MISTWEAVER] = {[statIds.SPIRIT] = {[statIds.HIT] = 0.5, [statIds.EXP] = 0.5}}
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
  WARLOCK = { base = CASTER_SPEC_WL },
}

function ReforgeLite:GetConversion()
  local classConversionInfo = STAT_CONVERSIONS[playerClass]
  if not classConversionInfo then return end

  local result = {}

  if classConversionInfo.base then
    addonTable.MergeTables(result, classConversionInfo.base)
  end

  local spec = C_SpecializationInfo.GetSpecialization()
  if spec and classConversionInfo.specs and classConversionInfo.specs[spec] then
    addonTable.MergeTables(result, classConversionInfo.specs[spec])
  end

  self.conversion = result
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
    local item = self.itemData[i].item
    local upgradeLevel = self.itemData[i].upgradeLevel or 0
    local orgstats = (item and GetItemStats(item, { upgradeLevel = upgradeLevel }) or {})
    local stats = (item and GetItemStats(item, { ilvlCap = self.pdb.ilvlCap, upgradeLevel = upgradeLevel }) or {})
    local reforge = self.itemData[i].reforge

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
    if self.itemData[i].reforge then
      method.items[i].reforge = self.itemData[i].reforge
      method.items[i].src, method.items[i].dst = unpack(self.reforgeTable[self.itemData[i].reforge])
    end
  end
  self:UpdateMethodStats (method)
  self.pdb.method = method
  self.pdb.methodOrigin = addonName
  self:UpdateMethodCategory()
end

function ReforgeLite:CapAllows (cap, value)
  for _,v in ipairs(cap.points) do
    if v.method == addonTable.StatCapMethods.AtLeast and value < v.value then
      return false
    elseif v.method == addonTable.StatCapMethods.AtMost and value > v.value then
      return false
    elseif v.method == addonTable.StatCapMethods.Exactly and value ~= v.value then
      return false
    end
  end
  return true
end

function ReforgeLite:IsItemLocked (slot)
  local slotData = self.itemData[slot]
  return not slotData.item
  or slotData.ilvl < 200
  or self.pdb.itemsLocked[slotData.itemGUID]
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
    if self.itemData[slot].reforge then
      src, dst = unpack(self.reforgeTable[self.itemData[slot].reforge])
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
    local item = self.itemData[i].item
    local upgradeLevel = self.itemData[i].upgradeLevel or 0
    local stats = (item and GetItemStats(item, { ilvlCap = self.pdb.ilvlCap, upgradeLevel = upgradeLevel }) or {})
    local orgstats = (item and GetItemStats(item, { upgradeLevel = upgradeLevel }) or {})
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
    local reforge = self.itemData[i].reforge
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

  return data
end

function ReforgeLite:ComputeReforgeCore (data, reforgeOptions)
  local scores, codes = {}, {}
  local mfloor = math.floor
  local mrandom = math.random
  local schar = string.char
  local stateCache = {}
  local initialState = CreateZeroedArray()
  for i = 1, NUM_CAPS do
    initialState[i] = mfloor((data.caps[i] and data.caps[i].init or 0) / data.cheat + mrandom())
  end
  local initialKey = EncodeState(initialState)
  scores[initialKey] = 0
  codes[initialKey] = ""
  stateCache[initialKey] = initialState
  local runYieldCheck = self.RunYieldCheck
  for i = 1, #self.itemData do
    local newscores, newcodes = {}, {}
    local newStateCache = {}
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
            newState[capIndex] = newState[capIndex] + mfloor(delta / data.cheat + mrandom())
          end
        end
        local nk = EncodeState(newState)
        if newscores[nk] == nil or nscore > newscores[nk] then
          newscores[nk] = nscore
          newcodes[nk] = code .. schar(j)
          newStateCache[nk] = newState
        end
      end
      runYieldCheck(self, optionCount)
    end
    scores, codes = newscores, newcodes
    stateCache = newStateCache
  end
  return scores, codes
end

function ReforgeLite:ChooseReforgeClassic (data, reforgeOptions, scores, codes)
  local maxPriority = 2 ^ NUM_CAPS
  local bestCode = {}
  local bestScore = {}
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
      else
        satisfied[capIndex] = true
      end
    end
    local priority = 0
    for capIndex = 1, NUM_CAPS do
      priority = priority * 2 + (satisfied[capIndex] and 1 or 0)
    end
    if not bestCode[priority] or score > bestScore[priority] then
      bestCode[priority] = code
      bestScore[priority] = score
    end
  end
  for priority = maxPriority - 1, 0, -1 do
    if bestCode[priority] then
      return bestCode[priority]
    end
  end
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

  local code = self:ChooseReforgeClassic(data, reforgeOptions, scores, codes)
  if not code then
    scores, codes = nil, nil
    collectgarbage("collect")
    if Print and L then
      Print(L["No reforge"])
    end
    return
  end
  scores, codes = nil, nil
  collectgarbage ("collect")
  for i = 1, #data.method.items do
    local opt = reforgeOptions[i][code:byte(i)]
    if data.conv[addonTable.statIds.SPIRIT] and data.conv[addonTable.statIds.SPIRIT][addonTable.statIds.HIT] == 1 then
      if opt.dst == addonTable.statIds.HIT and data.method.items[i].stats[addonTable.statIds.SPIRIT] == 0 then
        opt.dst = addonTable.statIds.SPIRIT
      end
    end
    data.method.items[i].src = opt.src
    data.method.items[i].dst = opt.dst
  end
  self.methodDebug = { data = DeepCopy(data) }
  self:FinalizeReforge (data)
  self.methodDebug.method = DeepCopy(data.method)
  if data.method then
    self.pdb.method = data.method
    self.pdb.methodOrigin = addonName
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
  routine = coroutine.create(function() self:Compute() end)
  self:ResumeComputeNextFrame()
end

function ReforgeLite:EndCompute()
  self.computeButton:RenderText(L["Compute"])
  addonTable.GUI:Unlock()
end
