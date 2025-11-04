-- CaveBot ML Optimizer extension

CaveBot.Extensions = CaveBot.Extensions or {}
CaveBot.Extensions.MLOptimizer = CaveBot.Extensions.MLOptimizer or {}

local optimizer = CaveBot.Extensions.MLOptimizer

local defaultState = {
  arms = {
    move = { reward = 0, tries = 0 },
    insert = { reward = 0, tries = 0 },
    remove = { reward = 0, tries = 0 }
  },
  initialWaypointCount = nil
}

local function cloneDefaultState()
  return table.recursivecopy(defaultState)
end

optimizer.state = optimizer.state or cloneDefaultState()
optimizer.roundHistory = optimizer.roundHistory or {}
optimizer.waypointMetrics = optimizer.waypointMetrics or {}
optimizer.roundCounter = optimizer.roundCounter or 0
optimizer.pendingExperiment = nil
optimizer.roundStartTime = nil
optimizer.roundStartExp = nil
optimizer.lastWaypointTime = nil
optimizer.lastWaypointExp = nil
optimizer.statusLabel = nil
optimizer.lastStatusMessage = nil

local function safeCall(fn, ...)
  if not fn then
    return nil
  end
  local status, result = pcall(fn, ...)
  if not status then
    return nil
  end
  return result
end

local function getBooleanConfig(id, defaultValue)
  local getter = CaveBot.Config and CaveBot.Config.get
  local value = safeCall(getter, id)
  if type(value) ~= "boolean" then
    return defaultValue
  end
  return value
end

local function getNumberConfig(id, defaultValue)
  local getter = CaveBot.Config and CaveBot.Config.get
  local value = safeCall(getter, id)
  if type(value) ~= "number" then
    return defaultValue
  end
  return value
end

local function parseGotoValue(text)
  if type(text) ~= "string" then
    return nil
  end
  local match = regexMatch(text, "\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)")
  if not match[1] then
    return nil
  end
  return {
    x = tonumber(match[1][2]),
    y = tonumber(match[1][3]),
    z = tonumber(match[1][4])
  }
end

local function waypointKey(value)
  if type(value) ~= "string" then
    return nil
  end
  return value:match("%d+,%d+,%d+") or value
end

local function updateStatus(message, color)
  if optimizer.lastStatusMessage == message then
    return
  end
  optimizer.lastStatusMessage = message
  if optimizer.statusLabel then
    optimizer.statusLabel:setText("ML Optimizer: " .. message)
    if color then
      optimizer.statusLabel:setColor(color)
    end
  end
end

local function snapshotActions()
  local snapshot = {}
  if not CaveBot.actionList then
    return snapshot
  end
  for _, child in ipairs(CaveBot.actionList:getChildren()) do
    table.insert(snapshot, { child.action, child.value })
  end
  return snapshot
end

local function restoreActions(snapshot)
  if not CaveBot.actionList then
    return
  end
  CaveBot.actionList:destroyChildren()
  for _, entry in ipairs(snapshot) do
    CaveBot.addAction(entry[1], entry[2])
  end
  CaveBot.resetWalking()
  CaveBot.save()
end

local function collectWaypoints()
  local waypoints = {}
  if not CaveBot.actionList then
    return waypoints
  end
  for index, child in ipairs(CaveBot.actionList:getChildren()) do
    if child.action == "goto" then
      local pos = parseGotoValue(child.value)
      if pos then
        table.insert(waypoints, {
          widget = child,
          index = index,
          position = pos,
          value = child.value,
          key = waypointKey(child.value)
        })
      end
    end
  end
  return waypoints
end

local function selectWaypoint(waypoints)
  if #waypoints == 0 then
    return nil
  end
  local selected
  local bestScore = -math.huge
  for _, wp in ipairs(waypoints) do
    local metrics = wp.key and optimizer.waypointMetrics[wp.key] or nil
    local score
    if metrics and metrics.count > 0 then
      local avgDuration = metrics.totalDuration / metrics.count
      local avgExp = metrics.totalExp / metrics.count
      score = avgDuration - (avgExp / math.max(1, metrics.count)) * 0.001
    else
      score = 0
    end
    if not selected or score > bestScore then
      selected = wp
      bestScore = score
    end
  end
  return selected or waypoints[math.random(#waypoints)]
end

local function averageExpPerHour(lastRounds)
  if type(lastRounds) ~= "number" or lastRounds < 1 then
    return nil
  end
  local total = 0
  local count = 0
  for i = #optimizer.roundHistory, 1, -1 do
    local round = optimizer.roundHistory[i]
    if round and round.expPerHour then
      total = total + round.expPerHour
      count = count + 1
      if count >= lastRounds then
        break
      end
    end
  end
  if count < lastRounds or count == 0 then
    return nil
  end
  return total / count
end

local function chooseArm()
  local arms = optimizer.state.arms
  local explorationPercent = getNumberConfig("mlOptimizerExploration", 25)
  local exploration = math.max(0, math.min(100, explorationPercent)) / 100
  if math.random() < exploration then
    local keys = {}
    for name, _ in pairs(arms) do
      table.insert(keys, name)
    end
    return keys[math.random(#keys)]
  end
  local bestName
  local bestScore = -math.huge
  for name, stats in pairs(arms) do
    local tries = stats.tries or 0
    local score
    if tries == 0 then
      score = 0
    else
      score = (stats.reward or 0) / tries
    end
    if not bestName or score > bestScore then
      bestName = name
      bestScore = score
    end
  end
  return bestName or "move"
end

local function applyMove(waypoints, config)
  local candidate = selectWaypoint(waypoints)
  if not candidate then
    return nil
  end
  local jitter = math.max(1, math.floor(getNumberConfig("mlOptimizerJitter", config.jitter)))
  local newPos = {
    x = math.max(0, candidate.position.x + math.random(-jitter, jitter)),
    y = math.max(0, candidate.position.y + math.random(-jitter, jitter)),
    z = candidate.position.z
  }
  local value = string.format("%d,%d,%d", newPos.x, newPos.y, newPos.z)
  CaveBot.editAction(candidate.widget, "goto", value)
  return {
    type = "move",
    target = candidate.index,
    from = candidate.value,
    to = value
  }
end

local function applyRemove(waypoints)
  if #waypoints <= 2 then
    return nil
  end
  local candidate = selectWaypoint(waypoints)
  if not candidate then
    return nil
  end
  candidate.widget:destroy()
  return {
    type = "remove",
    target = candidate.index,
    value = candidate.value
  }
end

local function midpoint(a, b)
  return {
    x = math.floor((a.x + b.x) / 2),
    y = math.floor((a.y + b.y) / 2),
    z = a.z
  }
end

local function applyInsert(waypoints, config)
  local baseCount = optimizer.state.initialWaypointCount or #waypoints
  local extraAllowed = getNumberConfig("mlOptimizerMaxExtraWaypoints", config.maxExtra)
  if (#waypoints - baseCount) >= extraAllowed then
    return nil
  end
  if #waypoints < 1 then
    return nil
  end
  local candidate = selectWaypoint(waypoints)
  if not candidate then
    return nil
  end
  local targetIndex
  local neighbourPos
  for i, wp in ipairs(waypoints) do
    if wp.index == candidate.index then
      targetIndex = wp.index + 1
      local nextWaypoint = waypoints[i + 1]
      if nextWaypoint and nextWaypoint.position.z == candidate.position.z then
        neighbourPos = nextWaypoint.position
      elseif waypoints[i - 1] and waypoints[i - 1].position.z == candidate.position.z then
        neighbourPos = waypoints[i - 1].position
      end
      break
    end
  end
  neighbourPos = neighbourPos or candidate.position
  local pos = midpoint(candidate.position, neighbourPos)
  local jitter = math.max(0, math.floor(getNumberConfig("mlOptimizerJitter", config.jitter) / 2))
  if jitter > 0 then
    pos.x = math.max(0, pos.x + math.random(-jitter, jitter))
    pos.y = math.max(0, pos.y + math.random(-jitter, jitter))
  end
  local value = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
  local widget = CaveBot.addAction("goto", value)
  if targetIndex then
    CaveBot.actionList:moveChildToIndex(widget, targetIndex)
  end
  return {
    type = "insert",
    target = targetIndex,
    value = value
  }
end

local function applyModification(arm, waypoints, config)
  if arm == "move" then
    return applyMove(waypoints, config)
  elseif arm == "remove" then
    return applyRemove(waypoints)
  elseif arm == "insert" then
    return applyInsert(waypoints, config)
  end
  return nil
end

local function updateArmStats(arm, reward)
  local stats = optimizer.state.arms[arm]
  if not stats then
    return
  end
  stats.reward = (stats.reward or 0) + reward
  stats.tries = (stats.tries or 0) + 1
end

local function evaluatePendingExperiment()
  local experiment = optimizer.pendingExperiment
  if not experiment then
    return
  end
  local enabled = getBooleanConfig("mlOptimizerEnabled", false)
  if not enabled then
    restoreActions(experiment.snapshot)
    optimizer.pendingExperiment = nil
    updateStatus("disabled", "#888888")
    return
  end
  local evalRounds = math.max(1, getNumberConfig("mlOptimizerEvaluationWindow", 5))
  local elapsed = optimizer.roundCounter - experiment.appliedRound
  if elapsed < evalRounds then
    local remaining = math.max(0, evalRounds - elapsed)
    updateStatus(string.format("evaluating %s (rounds left: %d)", experiment.modification.type, remaining), "#d4af37")
    return
  end
  local currentAverage = averageExpPerHour(evalRounds)
  if not currentAverage then
    updateStatus("waiting for data", "#888888")
    return
  end
  local baseline = experiment.baseline or 1
  local improvement = (currentAverage - baseline) / math.max(1, baseline)
  updateArmStats(experiment.arm, improvement)
  local minGainPercent = getNumberConfig("mlOptimizerMinGain", 3)
  local minGain = math.max(-100, minGainPercent) / 100
  if improvement >= minGain then
    optimizer.pendingExperiment = nil
    updateStatus(string.format("accepted %s (%.2f%%)", experiment.modification.type, improvement * 100), "#5fd35f")
    CaveBot.save()
    return
  end
  restoreActions(experiment.snapshot)
  optimizer.pendingExperiment = nil
  updateStatus(string.format("reverted %s (%.2f%%)", experiment.modification.type, improvement * 100), "#f06262")
end

local function maybeStartExperiment()
  if optimizer.pendingExperiment then
    return
  end
  local enabled = getBooleanConfig("mlOptimizerEnabled", false)
  if not enabled then
    updateStatus("disabled", "#888888")
    return
  end
  local evalRounds = math.max(1, getNumberConfig("mlOptimizerEvaluationWindow", 5))
  if #optimizer.roundHistory < evalRounds then
    updateStatus("collecting baseline", "#888888")
    return
  end
  local roundInterval = math.max(1, getNumberConfig("mlOptimizerRoundInterval", 5))
  if optimizer.roundCounter % roundInterval ~= 0 then
    return
  end
  local baseline = averageExpPerHour(evalRounds)
  if not baseline or baseline <= 0 then
    updateStatus("insufficient data", "#888888")
    return
  end
  local waypoints = collectWaypoints()
  if #waypoints == 0 then
    updateStatus("no waypoints to optimize", "#f06262")
    return
  end
  if not optimizer.state.initialWaypointCount then
    optimizer.state.initialWaypointCount = #waypoints
  end
  local arm = chooseArm()
  local snapshot = snapshotActions()
  local modification = applyModification(arm, waypoints, {
    jitter = getNumberConfig("mlOptimizerJitter", 2),
    maxExtra = getNumberConfig("mlOptimizerMaxExtraWaypoints", 3)
  })
  if not modification then
    updateStatus("unable to modify waypoints", "#f06262")
    return
  end
  optimizer.pendingExperiment = {
    arm = arm,
    appliedRound = optimizer.roundCounter,
    baseline = baseline,
    snapshot = snapshot,
    modification = modification
  }
  CaveBot.resetWalking()
  CaveBot.save()
  updateStatus(string.format("testing %s", modification.type), "#4fc3f7")
end

optimizer.setup = function()
  optimizer.roundHistory = {}
  optimizer.waypointMetrics = {}
  optimizer.roundCounter = 0
  optimizer.pendingExperiment = nil
  optimizer.roundStartTime = nil
  optimizer.roundStartExp = nil
  optimizer.lastWaypointTime = nil
  optimizer.lastWaypointExp = nil

  setDefaultTab("Cave")
  UI.Separator()
  local title = UI.Label("ML Optimizer")
  title:setColor("#6ae3c4")
  local status = UI.Label("ML Optimizer: waiting for data")
  status:setColor("#888888")
  status:setTooltip("Configure the optimizer from the CaveBot config panel. Every few rounds the optimizer will try a waypoint mutation and keep it if experience per hour improves.")
  optimizer.statusLabel = status
  optimizer.lastStatusMessage = nil
  updateStatus("waiting for data", "#888888")
end

optimizer.onConfigChange = function(_, _, data)
  optimizer.state = cloneDefaultState()
  if type(data) ~= "table" then
    return
  end
  local arms = data.arms
  if type(arms) == "table" then
    for name, stats in pairs(arms) do
      if optimizer.state.arms[name] then
        optimizer.state.arms[name].reward = tonumber(stats.reward) or 0
        optimizer.state.arms[name].tries = tonumber(stats.tries) or 0
      end
    end
  end
  if data.initialWaypointCount then
    optimizer.state.initialWaypointCount = tonumber(data.initialWaypointCount)
  end
end

optimizer.onSave = function()
  return {
    arms = optimizer.state.arms,
    initialWaypointCount = optimizer.state.initialWaypointCount
  }
end

optimizer.onActionEvaluated = function(widget, success)
  if not success or not widget or widget.action ~= "goto" then
    return
  end
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end
  local now = g_clock.seconds()
  local exp = player:getExperience()
  if optimizer.lastWaypointTime then
    local duration = math.max(0, now - optimizer.lastWaypointTime)
    local gain = exp - (optimizer.lastWaypointExp or exp)
    local key = waypointKey(widget.value)
    if key then
      local metrics = optimizer.waypointMetrics[key] or {
        count = 0,
        totalDuration = 0,
        totalExp = 0
      }
      metrics.count = metrics.count + 1
      metrics.totalDuration = metrics.totalDuration + duration
      metrics.totalExp = metrics.totalExp + gain
      optimizer.waypointMetrics[key] = metrics
    end
  end
  optimizer.lastWaypointTime = now
  optimizer.lastWaypointExp = exp
end

optimizer.onRoundComplete = function()
  local player = g_game.getLocalPlayer()
  if not player then
    optimizer.roundStartTime = nil
    optimizer.roundStartExp = nil
    return
  end
  local now = g_clock.seconds()
  local exp = player:getExperience()
  if not optimizer.roundStartTime or not optimizer.roundStartExp then
    optimizer.roundStartTime = now
    optimizer.roundStartExp = exp
    return
  end
  local duration = math.max(0.1, now - optimizer.roundStartTime)
  local gained = exp - optimizer.roundStartExp
  local expPerHour = (gained * 3600) / duration

  optimizer.roundCounter = optimizer.roundCounter + 1
  table.insert(optimizer.roundHistory, {
    round = optimizer.roundCounter,
    duration = duration,
    expGain = gained,
    expPerHour = expPerHour
  })
  if #optimizer.roundHistory > 150 then
    table.remove(optimizer.roundHistory, 1)
  end

  optimizer.roundStartTime = now
  optimizer.roundStartExp = exp

  evaluatePendingExperiment()
  maybeStartExperiment()
end

