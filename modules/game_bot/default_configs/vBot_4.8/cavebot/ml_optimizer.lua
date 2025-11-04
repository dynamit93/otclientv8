-- Machine-learning driven optimizer for CaveBot waypoints.
-- The optimizer evaluates experience gain over configurable route "rounds"
-- and applies structural mutations (add/remove/move/offset) to the waypoint
-- list. A lightweight hill-climbing strategy is provided by default, while
-- custom models can be registered via CaveBot.MLOptimizer.registerModel.

CaveBot.Extensions.MLOptimizer = CaveBot.Extensions.MLOptimizer or {}
CaveBot.MLOptimizer = CaveBot.MLOptimizer or {}

do
  local Optimizer = CaveBot.MLOptimizer

  local state = {
    initialized = false,
    list = nil,
    profileName = nil,
    lastRoundTime = nil,
    lastRoundExp = nil,
    cycle = { rounds = 0, totalExp = 0, totalTime = 0 },
    history = {},
    historyLimit = 50,
    variantCounter = 0,
    activeVariant = nil,
    bestVariant = nil,
    suppressRouteSnapshot = false,
    pendingPlan = nil,
    model = nil,
    defaultModel = nil,
    isEnabled = false,
    settings = {
      roundsPerCycle = 5,
      maxMutationsPerCycle = 2,
      maxOffset = 3,
      improvementTolerance = 0.03,
    }
  }

  local function getNow()
    if type(now) == "number" then
      return now
    end
    return g_clock.millis()
  end

  local function getPlayer()
    return g_game.getLocalPlayer()
  end

  local function cloneRoute(route)
    local copy = {}
    if not route then
      return copy
    end
    for i, node in ipairs(route) do
      copy[i] = { action = node.action, value = node.value }
    end
    return copy
  end

  local function clampCoord(value)
    if not value then return 0 end
    if value < 0 then
      return 0
    elseif value > 65535 then
      return 65535
    end
    return value
  end

  local function parseWaypoint(value)
    if type(value) ~= "string" then
      return nil
    end
    local numbers = {}
    for number in value:gmatch("(-?%d+)") do
      table.insert(numbers, tonumber(number))
    end
    if #numbers < 3 then
      return nil
    end
    return {
      x = numbers[1],
      y = numbers[2],
      z = numbers[3],
      precision = numbers[4],
    }
  end

  local function formatWaypoint(wp)
    if not wp then return nil end
    local precision = wp.precision
    if precision then
      return string.format("%d,%d,%d,%d", wp.x, wp.y, wp.z, precision)
    end
    return string.format("%d,%d,%d", wp.x, wp.y, wp.z)
  end

  local function countGotos(route)
    local total = 0
    for _, node in ipairs(route) do
      if node.action == "goto" then
        total = total + 1
      end
    end
    return total
  end

  local function resolveGotoOrdinal(route, ordinal)
    if ordinal == nil or ordinal < 1 then
      return nil
    end
    local counter = 0
    for idx, node in ipairs(route) do
      if node.action == "goto" then
        counter = counter + 1
        if counter == ordinal then
          return idx
        end
      end
    end
    return nil
  end

  function Optimizer.exportRoute()
    local list = state.list
    local data = {}
    if not list then
      return data
    end
    for _, child in ipairs(list:getChildren()) do
      table.insert(data, { action = child.action, value = child.value })
    end
    return data
  end

  local function rebuildListFromRoute(route)
    local list = state.list
    if not list then
      return
    end
    list:destroyChildren()
    for _, node in ipairs(route) do
      CaveBot.addAction(node.action, node.value)
    end
    local first = list:getFirstChild()
    if first then
      list:focusChild(first)
    end
  end

  function Optimizer.importRoute(route)
    if not route then return end
    state.suppressRouteSnapshot = true
    rebuildListFromRoute(route)
    CaveBot.save()
    state.suppressRouteSnapshot = false
  end

  local function applyOffset(route, op)
    local ordinal = op.gotoIndex
    if not ordinal then return false end
    local idx = resolveGotoOrdinal(route, ordinal)
    if not idx then return false end
    local node = route[idx]
    if node.action ~= "goto" then return false end
    local wp = parseWaypoint(node.value)
    if not wp then return false end
    local dx = op.dx or 0
    local dy = op.dy or 0
    if dx == 0 and dy == 0 then return false end
    wp.x = clampCoord(wp.x + dx)
    wp.y = clampCoord(wp.y + dy)
    node.value = formatWaypoint(wp)
    return true
  end

  local function applyAdd(route, op)
    local gotoCount = countGotos(route)
    local ordinal = op.afterGotoIndex or gotoCount
    local baseIdx = resolveGotoOrdinal(route, ordinal)
    local basePos = nil
    if baseIdx then
      basePos = parseWaypoint(route[baseIdx].value)
    end
    if not basePos and not op.position then
      return false
    end

    local playerRef = getPlayer()
    local referencePos = basePos or (playerRef and playerRef:getPosition()) or { x = 0, y = 0, z = 0 }
    local newPos = {
      x = referencePos.x or 0,
      y = referencePos.y or 0,
      z = referencePos.z or 0,
      precision = basePos and basePos.precision or (op.position and op.position.precision),
    }

    if op.position then
      if op.position.x then newPos.x = op.position.x end
      if op.position.y then newPos.y = op.position.y end
      if op.position.z then newPos.z = op.position.z end
      if op.position.precision then newPos.precision = op.position.precision end
    else
      local dx = op.dx or 0
      local dy = op.dy or 0
      if dx == 0 and dy == 0 then
        dx = (math.random(0, 1) == 0) and 1 or -1
        dy = (math.random(0, 1) == 0) and 0 or ((math.random(0, 1) == 0) and 1 or -1)
      end
      newPos.x = clampCoord(newPos.x + dx)
      newPos.y = clampCoord(newPos.y + dy)
    end

    local insertIndex = baseIdx and (baseIdx + 1) or (#route + 1)
    table.insert(route, insertIndex, { action = "goto", value = formatWaypoint(newPos) })
    return true
  end

  local function applyRemove(route, op)
    local gotoCount = countGotos(route)
    if gotoCount <= 1 then return false end
    local ordinal = op.gotoIndex
    local idx = resolveGotoOrdinal(route, ordinal)
    if not idx then return false end
    table.remove(route, idx)
    return true
  end

  local function applyMove(route, op)
    local ordinal = op.gotoIndex
    local delta = op.delta
    if not ordinal or not delta or delta == 0 then return false end
    local idx = resolveGotoOrdinal(route, ordinal)
    if not idx then return false end
    local node = table.remove(route, idx)
    local target = idx + delta
    if target < 1 then target = 1 end
    if target > #route + 1 then target = #route + 1 end
    table.insert(route, target, node)
    return true
  end

  local function applyMutationPlan(route, plan)
    if not plan or type(plan.operations) ~= "table" then
      return false
    end
    local applied = 0
    for _, op in ipairs(plan.operations) do
      local success = false
      if op.type == "offset" then
        success = applyOffset(route, op)
      elseif op.type == "add" then
        success = applyAdd(route, op)
      elseif op.type == "remove" then
        success = applyRemove(route, op)
      elseif op.type == "move" then
        success = applyMove(route, op)
      end
      if success then
        applied = applied + 1
      end
    end
    return applied > 0
  end

  local function persistBest()
    storage.mlOptimizer = storage.mlOptimizer or {}
    storage.mlOptimizer.bestRoute = cloneRoute(state.bestVariant and state.bestVariant.route or {})
    storage.mlOptimizer.bestStats = state.bestVariant and state.bestVariant.stats or nil
    storage.mlOptimizer.lastProfile = state.profileName
  end

  local function syncSettingsFromConfig()
    if not CaveBot.Config or not CaveBot.Config.values then
      return
    end
    local values = CaveBot.Config.values
    if values.mlOptimizerRounds then
      local rounds = tonumber(values.mlOptimizerRounds)
      if rounds and rounds >= 1 then
        state.settings.roundsPerCycle = math.max(1, math.floor(rounds))
      end
    end
    state.isEnabled = values.mlOptimizerEnabled == true
  end

  local function resetCycle()
    state.cycle = { rounds = 0, totalExp = 0, totalTime = 0 }
    local playerRef = getPlayer()
    state.lastRoundTime = getNow()
    state.lastRoundExp = playerRef and playerRef:getExperience() or 0
  end

  local function buildMutationContext()
    local bestRoute = state.bestVariant and state.bestVariant.route or Optimizer.exportRoute()
    local route = cloneRoute(bestRoute)
    local gotoOrdinals = {}
    for idx, node in ipairs(route) do
      if node.action == "goto" then
        table.insert(gotoOrdinals, idx)
      end
    end
    local context = {
      route = route,
      history = state.history,
      settings = state.settings,
      bestVariant = state.bestVariant,
      profile = state.profileName,
      random = function()
        return math.random()
      end,
      randomRange = function(a, b)
        return math.random(a, b)
      end
    }
    function context:getWaypointCount()
      return #gotoOrdinals
    end
    function context:getWaypoint(ordinal)
      local idx = gotoOrdinals[ordinal]
      if not idx then return nil end
      return parseWaypoint(route[idx].value), ordinal
    end
    function context:chooseWaypoint()
      if #gotoOrdinals == 0 then return nil end
      local ordinal = math.random(1, #gotoOrdinals)
      return ordinal, parseWaypoint(route[gotoOrdinals[ordinal]].value)
    end
    function context:cloneRoute()
      return cloneRoute(route)
    end
    return context
  end

  local function buildEvaluationContext(stats)
    return {
      stats = stats,
      variant = state.activeVariant,
      bestVariant = state.bestVariant,
      history = state.history,
      settings = state.settings,
      profile = state.profileName,
    }
  end

  local function requestMutationPlan()
    local plan = nil
    local context = buildMutationContext()
    if state.model and state.model.proposeMutation then
      local ok, result = pcall(function()
        return state.model:proposeMutation(context)
      end)
      if ok then
        plan = result
      else
        warn("[CaveBot:ML] Custom model proposeMutation error: " .. result)
      end
    end
    if not plan and state.defaultModel and state.defaultModel.proposeMutation then
      local ok, result = pcall(function()
        return state.defaultModel:proposeMutation(context)
      end)
      if ok then
        plan = result
      else
        warn("[CaveBot:ML] Default model error: " .. result)
      end
    end
    return plan
  end

  local function adoptVariant(route, plan)
    if not route then return false end
    if countGotos(route) == 0 then
      return false
    end
    state.variantCounter = state.variantCounter + 1
    local variantId
    if plan and plan.id then
      variantId = plan.id
    else
      variantId = string.format("variant-%d", state.variantCounter)
    end
    Optimizer.importRoute(route)
    state.activeVariant = {
      id = variantId,
      route = cloneRoute(route),
      plan = plan,
      stats = nil,
    }
    print(string.format("[CaveBot:ML] Testing variant '%s' (%d mutation(s)).", variantId, plan and #plan.operations or 0))
    resetCycle()
    return true
  end

  local function scheduleNextMutation()
    for attempt = 1, 5 do
      local plan = requestMutationPlan()
      if not plan or type(plan) ~= "table" or type(plan.operations) ~= "table" then
        break
      end

      local baseRoute = state.bestVariant and cloneRoute(state.bestVariant.route) or Optimizer.exportRoute()
      if applyMutationPlan(baseRoute, plan) then
        if adoptVariant(baseRoute, plan) then
          return
        end
      end
    end

    if state.bestVariant then
      if not state.activeVariant or state.activeVariant.id ~= state.bestVariant.id then
        Optimizer.importRoute(cloneRoute(state.bestVariant.route))
      end
      state.activeVariant = {
        id = state.bestVariant.id,
        route = cloneRoute(state.bestVariant.route),
        stats = state.bestVariant.stats,
      }
    end
    resetCycle()
    print("[CaveBot:ML] No viable mutation generated; continuing with best route.")
  end

  local function ensureBaseline()
    if not state.bestVariant then
      local route = Optimizer.exportRoute()
      state.bestVariant = {
        id = "baseline",
        route = cloneRoute(route),
        stats = nil,
      }
    end
    if not state.activeVariant then
      state.activeVariant = {
        id = state.bestVariant.id,
        route = cloneRoute(state.bestVariant.route),
        stats = state.bestVariant.stats,
      }
    end
  end

  local function handleCycleCompletion(stats)
    ensureBaseline()
    table.insert(state.history, stats)
    if #state.history > state.historyLimit then
      table.remove(state.history, 1)
    end

    if state.activeVariant then
      state.activeVariant.stats = stats
    end

    local bestStats = state.bestVariant and state.bestVariant.stats
    local bestXpH = bestStats and bestStats.xpPerHour or 0

    local evalContext = buildEvaluationContext(stats)
    if state.model and state.model.onCycleComplete then
      local ok, err = pcall(function()
        state.model:onCycleComplete(evalContext)
      end)
      if not ok then
        warn("[CaveBot:ML] Custom model onCycleComplete error: " .. err)
      end
    end
    if state.defaultModel and state.defaultModel.onCycleComplete then
      local ok, err = pcall(function()
        state.defaultModel:onCycleComplete(evalContext)
      end)
      if not ok then
        warn("[CaveBot:ML] Default model onCycleComplete error: " .. err)
      end
    end

    if not bestStats or bestXpH <= 0 then
      state.bestVariant = {
        id = state.activeVariant.id,
        route = cloneRoute(Optimizer.exportRoute()),
        stats = stats,
      }
      persistBest()
      print(string.format("[CaveBot:ML] Baseline recorded (%.0f xp/h).", stats.xpPerHour or 0))
      scheduleNextMutation()
      return
    end

    if state.activeVariant.id == state.bestVariant.id then
      state.bestVariant.stats = stats
      persistBest()
      scheduleNextMutation()
      return
    end

    local tolerance = state.settings.improvementTolerance or 0.03
    local required = bestXpH * (1 + tolerance)

    if stats.xpPerHour > required then
      state.bestVariant = {
        id = state.activeVariant.id,
        route = cloneRoute(Optimizer.exportRoute()),
        stats = stats,
      }
      persistBest()
      print(string.format("[CaveBot:ML] New best variant '%s' (%.0f xp/h).", state.bestVariant.id, stats.xpPerHour))
      scheduleNextMutation()
      return
    end

    -- revert to previously best route if no improvement
    print(string.format("[CaveBot:ML] Variant '%s' underperformed (%.0f xp/h < %.0f xp/h). Reverting to '%s'.",
      state.activeVariant.id, stats.xpPerHour or 0, bestXpH, state.bestVariant.id))
    Optimizer.importRoute(cloneRoute(state.bestVariant.route))
    state.activeVariant = {
      id = state.bestVariant.id,
      route = cloneRoute(state.bestVariant.route),
      stats = state.bestVariant.stats,
    }
    resetCycle()
    scheduleNextMutation()
  end

  function Optimizer.bootstrap(ctx)
    if ctx and ctx.list then
      state.list = ctx.list
    end
    if state.initialized then
      syncSettingsFromConfig()
      return
    end

    state.initialized = true
    syncSettingsFromConfig()

    storage.mlOptimizer = storage.mlOptimizer or {}
    local saved = storage.mlOptimizer
    if saved.bestRoute then
      state.bestVariant = {
        id = (saved.bestStats and saved.bestStats.variantId) or "baseline",
        route = cloneRoute(saved.bestRoute),
        stats = saved.bestStats,
      }
    end
    state.profileName = CaveBot.getCurrentProfile and CaveBot.getCurrentProfile() or saved.lastProfile

    state.defaultModel = state.defaultModel or {}
    state.defaultModel = setmetatable(state.defaultModel, { __index = {
      onInit = function(self)
        self.id = "default-hillclimb"
      end,
      onCycleComplete = function() end,
        proposeMutation = function(self, context)
          local waypointCount = context:getWaypointCount()
          if waypointCount == 0 then
            return nil
          end
          local maxOps = math.max(1, state.settings.maxMutationsPerCycle or 1)
          local operations = {}

          local function nonZeroOffset(maxOffset)
            maxOffset = math.max(1, maxOffset or 1)
            local value = math.random(-maxOffset, maxOffset)
            if value == 0 then
              value = (math.random(0, 1) == 0) and 1 or -1
            end
            return value
          end

          local function chooseOp(currentCount)
            if currentCount <= 0 then
              return "add"
            end
            if currentCount == 1 then
              return (math.random() < 0.6) and "offset" or "add"
            end
            local r = math.random()
            if r < 0.45 then
              return "offset"
            elseif r < 0.75 then
              return "add"
            elseif r < 0.9 then
              return "move"
            else
              return "remove"
            end
          end

          for _ = 1, maxOps do
            local opType = chooseOp(waypointCount)
            if opType == "offset" and waypointCount > 0 then
              local ordinal = math.random(1, waypointCount)
              table.insert(operations, {
                type = "offset",
                gotoIndex = ordinal,
                dx = nonZeroOffset(state.settings.maxOffset),
                dy = nonZeroOffset(state.settings.maxOffset),
              })
            elseif opType == "add" then
              local ordinal = waypointCount > 0 and math.random(1, waypointCount) or 1
              table.insert(operations, {
                type = "add",
                afterGotoIndex = ordinal,
                dx = nonZeroOffset(state.settings.maxOffset),
                dy = nonZeroOffset(state.settings.maxOffset),
              })
              waypointCount = waypointCount + 1
            elseif opType == "move" and waypointCount > 0 then
              local ordinal = math.random(1, waypointCount)
              local delta = math.random(-2, 2)
              if delta == 0 then delta = (math.random(0, 1) == 0) and -1 or 1 end
              table.insert(operations, {
                type = "move",
                gotoIndex = ordinal,
                delta = delta,
              })
            elseif opType == "remove" and waypointCount > 1 then
              local ordinal = math.random(1, waypointCount)
              table.insert(operations, {
                type = "remove",
                gotoIndex = ordinal,
              })
              waypointCount = math.max(0, waypointCount - 1)
            end
          end

          if #operations == 0 then
            return nil
          end

          return {
            id = string.format("default-%d-%d", getNow(), math.random(1000, 9999)),
            operations = operations,
            metadata = { strategy = "default" }
          }
        end,
    } })

    if state.defaultModel.onInit then
      state.defaultModel:onInit()
    end

    ensureBaseline()
    resetCycle()
    print("[CaveBot:ML] Optimizer bootstrapped.")
  end

  function Optimizer.registerModel(model)
    if model == nil then
      state.model = nil
      return
    end
    if type(model) ~= "table" then
      return warn("[CaveBot:ML] registerModel expects a table")
    end
    state.model = model
    if state.model.onInit then
      local ok, err = pcall(function()
        state.model:onInit(buildMutationContext())
      end)
      if not ok then
        warn("[CaveBot:ML] Custom model onInit error: " .. err)
      end
    end
  end

  function Optimizer.onRoundComplete()
    if not state.initialized or not state.list then
      return
    end
    syncSettingsFromConfig()
    if not state.isEnabled then
      return
    end

    local playerRef = getPlayer()
    if not playerRef then
      return
    end

    if not state.lastRoundTime or not state.lastRoundExp then
      resetCycle()
      return
    end

    local currentExp = playerRef:getExperience()
    local currentTime = getNow()
    local duration = math.max(1, currentTime - state.lastRoundTime)
    local expGain = currentExp - state.lastRoundExp

    state.cycle.rounds = state.cycle.rounds + 1
    state.cycle.totalExp = state.cycle.totalExp + expGain
    state.cycle.totalTime = state.cycle.totalTime + duration

    state.lastRoundTime = currentTime
    state.lastRoundExp = currentExp

    if state.cycle.rounds < (state.settings.roundsPerCycle or 5) then
      return
    end

    local xpPerHour = 0
    if state.cycle.totalTime > 0 then
      xpPerHour = (state.cycle.totalExp * 3600000) / state.cycle.totalTime
    end

    local stats = {
      xpPerHour = xpPerHour,
      xpGained = state.cycle.totalExp,
      rounds = state.cycle.rounds,
      duration = state.cycle.totalTime,
      variantId = state.activeVariant and state.activeVariant.id or "baseline",
      timestamp = currentTime,
    }

    state.cycle = { rounds = 0, totalExp = 0, totalTime = 0 }
    handleCycleCompletion(stats)
  end

  function Optimizer.onRouteSaved()
    if not state.initialized or state.suppressRouteSnapshot then
      return
    end
    local route = Optimizer.exportRoute()
    state.bestVariant = {
      id = "manual-" .. getNow(),
      route = cloneRoute(route),
      stats = nil,
    }
    state.activeVariant = {
      id = state.bestVariant.id,
      route = cloneRoute(route),
      stats = nil,
    }
    state.history = {}
    print("[CaveBot:ML] Route changed manually. Optimizer baseline reset.")
    resetCycle()
    persistBest()
  end

  function Optimizer.onProfileLoaded(name)
    state.profileName = name
    if not state.initialized then
      return
    end
    local route = Optimizer.exportRoute()
    state.bestVariant = {
      id = string.format("%s-baseline", name or "baseline"),
      route = cloneRoute(route),
      stats = nil,
    }
    state.activeVariant = {
      id = state.bestVariant.id,
      route = cloneRoute(route),
      stats = nil,
    }
    state.history = {}
    resetCycle()
    persistBest()
    print(string.format("[CaveBot:ML] Profile '%s' loaded. Baseline ready.", name or "unnamed"))
  end

  CaveBot.Extensions.MLOptimizer.setup = function()
    -- extension hook placeholder (no additional UI yet)
  end

  CaveBot.Extensions.MLOptimizer.onConfigChange = function(configName, enabled, configData)
    -- no per-config data required; rely on CaveBot.Config
  end

  CaveBot.Extensions.MLOptimizer.onSave = function()
    return nil
  end
end
