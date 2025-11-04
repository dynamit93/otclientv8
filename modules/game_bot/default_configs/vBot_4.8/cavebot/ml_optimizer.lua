CaveBot.Extensions.MLWaypointOptimizer = {}
local Optimizer = CaveBot.Extensions.MLWaypointOptimizer

local STORAGE_KEY = "mlWaypointOptimizer"
local DEFAULTS = {
  enabled = true,
  evaluationRounds = 5,
  explorationRate = 0.25,
  improvementThreshold = 0.02,
  minGotoWaypoints = 3,
  maxOffset = 2,
  saveOnChange = true,
  log = true
}

local MUTATION_TYPES = {"add", "move", "remove"}

local persistent = storage[STORAGE_KEY] or {}
storage[STORAGE_KEY] = persistent
local settings = persistent

local state = {
  planStartExp = nil,
  planStartTime = nil,
  roundsSinceEvaluation = 0,
  baselinePlan = nil,
  baselineMetric = nil,
  testingPlan = nil,
  stats = {},
  pendingBaselineRestore = nil,
  history = {}
}

local function ensureDefaults()
  for key, value in pairs(DEFAULTS) do
    if settings[key] == nil then
      settings[key] = value
    end
  end
end

local function normalizeSettings()
  settings.evaluationRounds = math.max(1, math.floor(tonumber(settings.evaluationRounds) or DEFAULTS.evaluationRounds))
  settings.explorationRate = math.max(0, math.min(1, tonumber(settings.explorationRate) or DEFAULTS.explorationRate))
  settings.improvementThreshold = tonumber(settings.improvementThreshold) or DEFAULTS.improvementThreshold
  settings.minGotoWaypoints = math.max(1, math.floor(tonumber(settings.minGotoWaypoints) or DEFAULTS.minGotoWaypoints))
  settings.maxOffset = math.max(1, math.floor(tonumber(settings.maxOffset) or DEFAULTS.maxOffset))
  settings.saveOnChange = settings.saveOnChange ~= false
  settings.log = settings.log ~= false
  settings.enabled = settings.enabled ~= false
end

local function ensureStats()
  state.stats = state.stats or {}
  for _, kind in ipairs(MUTATION_TYPES) do
    if not state.stats[kind] then
      state.stats[kind] = {attempts = 0, successes = 0, totalDelta = 0}
    end
  end
end

local function trim(str)
  return str:gsub("^%s+", ""):gsub("%s+$", "")
end

local function round(num)
  if num >= 0 then
    return math.floor(num + 0.5)
  end
  return math.ceil(num - 0.5)
end

local function logMessage(text)
  if settings.log then
    print(string.format("[ML Optimizer] %s", text))
  end
end

local function clonePlan(sequence)
  local clone = {}
  if type(sequence) ~= "table" then
    return clone
  end
  for index, entry in ipairs(sequence) do
    clone[index] = {action = entry.action, value = entry.value}
  end
  return clone
end

local function sequenceContainsValue(sequence, actionName, actionValue)
  if type(sequence) ~= "table" then
    return false
  end
  for _, entry in ipairs(sequence) do
    if entry.action == actionName and entry.value == actionValue then
      return true
    end
  end
  return false
end

local function getGotoIndices(sequence)
  local indices = {}
  if type(sequence) ~= "table" then
    return indices
  end
  for index, entry in ipairs(sequence) do
    if entry.action == "goto" then
      table.insert(indices, index)
    end
  end
  return indices
end

local function parseGoto(value)
  if type(value) ~= "string" then
    return nil
  end
  local parts = value:split(",")
  if #parts < 3 then
    return nil
  end
  local x = tonumber(trim(parts[1]))
  local y = tonumber(trim(parts[2]))
  local z = tonumber(trim(parts[3]))
  if not x or not y or not z then
    return nil
  end
  return {x = x, y = y, z = z}
end

local function formatGoto(position)
  if not position then
    return nil
  end
  local x = position.x or position[1]
  local y = position.y or position[2]
  local z = position.z or position[3]
  if not x or not y or not z then
    return nil
  end
  return string.format("%d,%d,%d", round(x), round(y), round(z))
end

local function normalizePosition(raw)
  if not raw then
    return nil
  end
  if type(raw) == "table" then
    if raw.x and raw.y and raw.z then
      return {x = raw.x, y = raw.y, z = raw.z}
    elseif raw[1] and raw[2] and raw[3] then
      return {x = raw[1], y = raw[2], z = raw[3]}
    end
  elseif type(raw) == "userdata" then
    if raw.x and raw.y and raw.z then
      return {x = raw.x, y = raw.y, z = raw.z}
    end
  end
  return nil
end

local function computeXpPerHour(expGain, elapsedMs)
  if elapsedMs <= 0 then
    return 0
  end
  return (expGain * 3600000) / elapsedMs
end

local function recordMutationResult(kind, success, relative)
  ensureStats()
  local stat = state.stats[kind]
  if not stat then
    return
  end
  stat.attempts = stat.attempts + 1
  if success then
    stat.successes = (stat.successes or 0) + 1
  end
  stat.totalDelta = stat.totalDelta + (relative or 0)
end

local function chooseMutationType()
  ensureStats()
  if math.random() < settings.explorationRate then
    return MUTATION_TYPES[math.random(#MUTATION_TYPES)]
  end

  local bestKind
  local bestScore
  for _, kind in ipairs(MUTATION_TYPES) do
    local stat = state.stats[kind]
    local score = 0
    if stat and stat.attempts > 0 then
      score = stat.totalDelta / stat.attempts
    end
    if not bestScore or score > bestScore then
      bestScore = score
      bestKind = kind
    end
  end

  return bestKind or MUTATION_TYPES[math.random(#MUTATION_TYPES)]
end

local function mutateAdd(sequence)
  local gotoIndices = getGotoIndices(sequence)
  if #gotoIndices == 0 then
    return nil
  end

  local mutated = clonePlan(sequence)
  local anchorIndex = gotoIndices[math.random(#gotoIndices)]
  local anchorPos = parseGoto(mutated[anchorIndex].value)
  if not anchorPos then
    return nil
  end

  local offsetRange = math.max(1, settings.maxOffset or 2)
  local attempts = 0

  while attempts < 6 do
    attempts = attempts + 1
    local candidate = nil

    if math.random() < 0.35 then
      local currentPos = normalizePosition(pos and pos())
      if currentPos and currentPos.z == anchorPos.z then
        candidate = currentPos
      end
    end

    if not candidate then
      local dx = math.random(-offsetRange, offsetRange)
      local dy = math.random(-offsetRange, offsetRange)
      if dx == 0 and dy == 0 then
        dx = (math.random(0, 1) == 0 and -offsetRange or offsetRange)
      end
      candidate = {
        x = anchorPos.x + dx,
        y = anchorPos.y + dy,
        z = anchorPos.z
      }
    end

    local value = formatGoto(candidate)
    if value and not sequenceContainsValue(mutated, "goto", value) then
      table.insert(mutated, anchorIndex + 1, {action = "goto", value = value})
      return mutated, {type = "add", index = anchorIndex + 1, value = value}
    end
  end

  return nil
end

local function mutateMove(sequence)
  local gotoIndices = getGotoIndices(sequence)
  if #gotoIndices == 0 then
    return nil
  end

  local mutated = clonePlan(sequence)
  local index = gotoIndices[math.random(#gotoIndices)]
  local base = parseGoto(mutated[index].value)
  if not base then
    return nil
  end

  local offsetRange = math.max(1, settings.maxOffset or 2)
  local attempts = 0

  while attempts < 6 do
    attempts = attempts + 1
    local dx = math.random(-offsetRange, offsetRange)
    local dy = math.random(-offsetRange, offsetRange)
    if dx == 0 and dy == 0 then
      dx = (math.random(0, 1) == 0 and -offsetRange or offsetRange)
    end
    local candidate = {
      x = base.x + dx,
      y = base.y + dy,
      z = base.z
    }
    local value = formatGoto(candidate)
    if value and not sequenceContainsValue(mutated, "goto", value) then
      mutated[index].value = value
      return mutated, {type = "move", index = index, value = value}
    end
  end

  return nil
end

local function mutateRemove(sequence)
  local gotoIndices = getGotoIndices(sequence)
  if #gotoIndices <= settings.minGotoWaypoints then
    return nil
  end

  local mutated = clonePlan(sequence)
  local index = gotoIndices[math.random(#gotoIndices)]
  table.remove(mutated, index)
  return mutated, {type = "remove", index = index}
end

local function applyMutation(kind, sequence)
  if kind == "add" then
    return mutateAdd(sequence)
  elseif kind == "move" then
    return mutateMove(sequence)
  elseif kind == "remove" then
    return mutateRemove(sequence)
  end
end

local function plansAreEqual(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  if #a ~= #b then
    return false
  end
  for index = 1, #a do
    local first = a[index]
    local second = b[index]
    if first.action ~= second.action or first.value ~= second.value then
      return false
    end
  end
  return true
end

local function proposePlan()
  if not CaveBot.getActionSequence then
    return nil
  end

  local current = CaveBot.getActionSequence()
  if not current or #current == 0 then
    return nil
  end

  local gotoIndices = getGotoIndices(current)
  if #gotoIndices == 0 then
    return nil
  end

  local mutationType = chooseMutationType()
  local mutated, metadata = applyMutation(mutationType, current)

  if not mutated then
    local fallback = {"move", "add", "remove"}
    for _, alternative in ipairs(fallback) do
      if alternative ~= mutationType then
        mutated, metadata = applyMutation(alternative, current)
        if mutated then
          mutationType = alternative
          break
        end
      end
    end
  end

  if not mutated or plansAreEqual(current, mutated) then
    return nil
  end

  metadata = metadata or {}
  metadata.type = metadata.type or mutationType
  return {actions = mutated, mutation = metadata}
end

local function applySequence(sequence)
  if type(sequence) ~= "table" then
    return
  end

  local snapshot = clonePlan(sequence)

  local function execute()
    if not CaveBot.replaceActionSequence then
      schedule(50, execute)
      return
    end

    CaveBot.replaceActionSequence(snapshot, {save = settings.saveOnChange})
    state.planStartExp = exp()
    state.planStartTime = now
    state.roundsSinceEvaluation = 0
  end

  schedule(30, execute)
end

Optimizer.setup = function()
  ensureDefaults()
  normalizeSettings()
  ensureStats()

  state.planStartExp = exp()
  state.planStartTime = now
  state.roundsSinceEvaluation = 0
  state.baselinePlan = nil
  state.baselineMetric = nil
  state.testingPlan = nil
  state.pendingBaselineRestore = nil

  logMessage(string.format(
    "initialized (enabled: %s, eval rounds: %d, exploration: %.2f)",
    tostring(settings.enabled),
    settings.evaluationRounds,
    settings.explorationRate
  ))
end

Optimizer.onConfigChange = function(configName, isEnabled, configData)
  configData = configData or {}

  for key, defaultValue in pairs(DEFAULTS) do
    if configData[key] ~= nil then
      settings[key] = configData[key]
    elseif settings[key] == nil then
      settings[key] = defaultValue
    end
  end

  normalizeSettings()
  ensureStats()

  local previousBaseline = state.baselinePlan and clonePlan(state.baselinePlan) or nil
  state.baselinePlan = nil
  state.baselineMetric = nil
  state.testingPlan = nil
  state.pendingBaselineRestore = nil
  state.roundsSinceEvaluation = 0
  state.planStartExp = exp()
  state.planStartTime = now

  if not settings.enabled then
    if previousBaseline and #previousBaseline > 0 then
      state.pendingBaselineRestore = previousBaseline
    end
    logMessage(string.format("disabled for profile '%s'", configName or ""))
    return
  end

  logMessage(string.format("enabled for profile '%s'", configName or ""))
end

Optimizer.onSave = function()
  return {
    enabled = settings.enabled,
    evaluationRounds = settings.evaluationRounds,
    explorationRate = settings.explorationRate,
    improvementThreshold = settings.improvementThreshold,
    minGotoWaypoints = settings.minGotoWaypoints,
    maxOffset = settings.maxOffset,
    saveOnChange = settings.saveOnChange,
    log = settings.log
  }
end

Optimizer.onRoundComplete = function(roundIndex, roundDuration)
  if not settings.enabled then
    return
  end

  if CaveBot.isOn and not CaveBot.isOn() then
    return
  end

  if not CaveBot.actionList or CaveBot.actionList:getChildCount() == 0 then
    return
  end

  if not CaveBot.getActionSequence then
    return
  end

  if state.pendingBaselineRestore then
    applySequence(state.pendingBaselineRestore)
    state.pendingBaselineRestore = nil
    return
  end

  state.roundsSinceEvaluation = (state.roundsSinceEvaluation or 0) + 1
  if state.roundsSinceEvaluation < settings.evaluationRounds then
    return
  end

  state.roundsSinceEvaluation = 0

  local currentExp = exp()
  local startExp = state.planStartExp or currentExp
  local startTime = state.planStartTime or now
  local elapsed = math.max(1, now - startTime)
  local expGain = currentExp - startExp
  local xpPerHour = computeXpPerHour(expGain, elapsed)

  state.planStartExp = currentExp
  state.planStartTime = now

  table.insert(state.history, 1, {round = roundIndex, xp = xpPerHour, testing = state.testingPlan and state.testingPlan.mutation.type or "baseline"})
  if #state.history > 20 then
    table.remove(state.history)
  end

  if not state.baselineMetric then
    state.baselineMetric = xpPerHour
    state.baselinePlan = clonePlan(CaveBot.getActionSequence() or {})
    logMessage(string.format("baseline captured: %.2f exp/h", xpPerHour))
    return
  end

  if state.testingPlan then
    local baseline = state.baselineMetric
    local improvement = xpPerHour - baseline
    local relative = 0
    if baseline ~= 0 then
      relative = improvement / baseline
    elseif xpPerHour > 0 then
      relative = 1
    end

    local mutationType = state.testingPlan.mutation.type or "unknown"

    if relative >= settings.improvementThreshold then
      logMessage(string.format(
        "accepted %s mutation: %.2f exp/h (%.2f%%)",
        mutationType,
        xpPerHour,
        relative * 100
      ))
      recordMutationResult(mutationType, true, relative)
      state.baselineMetric = xpPerHour
      state.baselinePlan = clonePlan(CaveBot.getActionSequence() or {})
    else
      logMessage(string.format(
        "reverted %s mutation: %.2f exp/h (%.2f%%)",
        mutationType,
        xpPerHour,
        relative * 100
      ))
      recordMutationResult(mutationType, false, relative)
      if state.baselinePlan then
        state.pendingBaselineRestore = clonePlan(state.baselinePlan)
      end
    end

    state.testingPlan = nil
    return
  end

  local candidate = proposePlan()
  if candidate then
    state.testingPlan = {
      mutation = candidate.mutation,
      actions = clonePlan(candidate.actions)
    }
    logMessage(string.format("testing %s mutation (round %d)", candidate.mutation.type, roundIndex))
    applySequence(candidate.actions)
  end
end
