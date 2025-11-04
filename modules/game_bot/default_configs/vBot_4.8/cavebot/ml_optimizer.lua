CaveBot.Extensions.MLOptimizer = {}
local MLOptimizer = CaveBot.Extensions.MLOptimizer

local defaults = {
  enabled = false,
  endpoint = "",
  authToken = "",
  interval = 5,
  maxChanges = 3,
  allowAdd = true,
  allowUpdate = true,
  allowRemove = false,
  allowMove = true
}

local ui = {}
local state = {
  pending = false,
  roundAccumulator = 0,
  lastAppliedChanges = nil,
  lastRequestAt = 0,
  lastResponseAt = 0,
  lastRequestId = 0,
  lastSnapshot = nil
}

local silentUiUpdate = false

local function cloneDefaults()
  local copy = {}
  for key, value in pairs(defaults) do
    copy[key] = value
  end
  return copy
end

local function ensureStorage()
  storage.mlOptimizer = storage.mlOptimizer or {}
  local store = storage.mlOptimizer
  if type(store.sessionId) ~= "string" or store.sessionId:len() == 0 then
    store.sessionId = string.format("ml-%d-%05d", os.time(), math.random(0, 99999))
  end
  store.history = store.history or {}
  return store
end

local function trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return value:match("^%s*(.-)%s*$")
end

local function sanitizeBoolean(value, fallback)
  if type(value) == "boolean" then
    return value
  end
  if value == "true" or value == "1" or value == 1 then
    return true
  end
  if value == "false" or value == "0" or value == 0 then
    return false
  end
  return fallback
end

local function sanitizeNumber(value, fallback, minimum, maximum)
  local numberValue = tonumber(value)
  if not numberValue then
    return fallback
  end
  numberValue = math.floor(numberValue)
  if minimum and numberValue < minimum then
    numberValue = minimum
  end
  if maximum and numberValue > maximum then
    numberValue = maximum
  end
  return numberValue
end

local function updateConfig(key, value, skipSave)
  if MLOptimizer.config[key] == value then
    return
  end
  MLOptimizer.config[key] = value
  if not skipSave and CaveBot.save then
    schedule(0, function()
      CaveBot.save()
    end)
  end
end

local function refreshUI()
  if not next(ui) then
    return
  end

  silentUiUpdate = true

  if ui.enableSwitch then
    ui.enableSwitch:setOn(MLOptimizer.config.enabled)
  end

  if ui.endpointInput then
    ui.endpointInput:setText(MLOptimizer.config.endpoint or "")
  end

  if ui.authInput then
    ui.authInput:setText(MLOptimizer.config.authToken or "")
  end

  if ui.intervalInput then
    ui.intervalInput:setText(tostring(MLOptimizer.config.interval or defaults.interval))
  end

  if ui.maxChangesInput then
    ui.maxChangesInput:setText(tostring(MLOptimizer.config.maxChanges or defaults.maxChanges))
  end

  if ui.allowAddSwitch then
    ui.allowAddSwitch:setOn(MLOptimizer.config.allowAdd)
  end

  if ui.allowUpdateSwitch then
    ui.allowUpdateSwitch:setOn(MLOptimizer.config.allowUpdate)
  end

  if ui.allowRemoveSwitch then
    ui.allowRemoveSwitch:setOn(MLOptimizer.config.allowRemove)
  end

  if ui.allowMoveSwitch then
    ui.allowMoveSwitch:setOn(MLOptimizer.config.allowMove)
  end

  silentUiUpdate = false
end

local function gatherWaypoints()
  local list = CaveBot.actionList
  if not list then
    return {}
  end

  local children = list:getChildren()
  if not children or #children == 0 then
    return {}
  end

  local result = {}
  for index, child in ipairs(children) do
    table.insert(result, {
      index = index,
      action = child.action,
      value = child.value,
      text = child:getText()
    })
  end
  return result
end

local function getFocusedIndex(list)
  if not list then
    return nil
  end
  local focused = list:getFocusedChild()
  if not focused then
    return nil
  end
  return list:getChildIndex(focused)
end

local function getPlayerInfo()
  local playerInfo = {}
  if g_game.getLocalPlayer then
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
      playerInfo.name = localPlayer:getName()
      if localPlayer.getLevel then
        playerInfo.level = localPlayer:getLevel()
      end
      if localPlayer.getVocation then
        playerInfo.vocation = localPlayer:getVocation()
      end
      local position = localPlayer:getPosition()
      if position then
        playerInfo.position = { x = position.x, y = position.y, z = position.z }
      end
    end
  end
  playerInfo.clientVersion = g_game.getClientVersion and g_game.getClientVersion() or nil
  playerInfo.platform = g_platform and g_platform.getOs and g_platform.getOs() or nil
  return playerInfo
end

local function serializeValue(value)
  if type(value) == "string" then
    return value
  end
  if type(value) == "table" then
    if value.x and value.y and value.z then
      return string.format("%d,%d,%d", value.x, value.y, value.z)
    end
    if #value > 0 then
      return table.concat(value, ",")
    end
    local status, encoded = pcall(json.encode, value)
    if status then
      return encoded
    end
  end
  if value == nil then
    return ""
  end
  return tostring(value)
end

local function normalizeIndex(value, list, allowAppend)
  if not list then
    return nil
  end
  local idx = tonumber(value)
  if not idx then
    return nil
  end
  idx = math.floor(idx)
  if idx < 1 then
    idx = 1
  end
  local count = list:getChildCount()
  local upperBound = allowAppend and (count + 1) or count
  if idx > upperBound then
    idx = upperBound
  end
  return idx
end

local function ensureAction(action)
  if type(action) ~= "string" then
    return nil
  end
  action = action:lower()
  if not CaveBot.Actions[action] then
    return nil
  end
  return action
end

local function handleChange(change, list)
  if type(change) ~= "table" then
    return false
  end

  local changeType = trim(change.type or change.op or change.actionType or change.kind)
  if changeType == "" then
    return false
  end
  changeType = changeType:lower()

  if changeType == "update" or changeType == "edit" or changeType == "replace" then
    if not MLOptimizer.config.allowUpdate then
      return false
    end
    local index = normalizeIndex(change.index or change.at, list, false)
    if not index then
      return false
    end
    local widget = list:getChildByIndex(index)
    if not widget then
      return false
    end
    local action = ensureAction(change.action or widget.action)
    if not action then
      warn("[CaveBot][ML] Ignored update with invalid action: " .. tostring(change.action))
      return false
    end
    local value = serializeValue(change.value or change.data or widget.value)
    CaveBot.editAction(widget, action, value)
    return true
  elseif changeType == "add" or changeType == "insert" then
    if not MLOptimizer.config.allowAdd then
      return false
    end
    local action = ensureAction(change.action)
    if not action then
      warn("[CaveBot][ML] Ignored insert with invalid action: " .. tostring(change.action))
      return false
    end
    local value = serializeValue(change.value or change.data or "")
    local widget = CaveBot.addAction(action, value)
    if not widget then
      return false
    end
    local index = normalizeIndex(change.index or change.position or (list:getChildCount()), list, true)
    if index then
      list:moveChildToIndex(widget, index)
    end
    return true
  elseif changeType == "remove" or changeType == "delete" then
    if not MLOptimizer.config.allowRemove then
      return false
    end
    local index = normalizeIndex(change.index or change.position, list, false)
    if not index then
      return false
    end
    local widget = list:getChildByIndex(index)
    if not widget then
      return false
    end
    widget:destroy()
    return true
  elseif changeType == "move" or changeType == "reorder" then
    if not MLOptimizer.config.allowMove then
      return false
    end
    local fromIndex = normalizeIndex(change.from or change.index, list, false)
    if not fromIndex then
      return false
    end
    local delta = tonumber(change.delta)
    local toIndexValue = change.to or change.position
    if not toIndexValue and delta then
      toIndexValue = fromIndex + delta
    end
    local toIndex = normalizeIndex(toIndexValue, list, false)
    if not toIndex or not list:getChildByIndex(fromIndex) then
      return false
    end
    local widget = list:getChildByIndex(fromIndex)
    list:moveChildToIndex(widget, toIndex)
    return true
  end

  return false
end

local function applyChanges(response)
  if type(response) ~= "table" then
    return
  end

  local list = CaveBot.actionList
  if not list then
    warn("[CaveBot][ML] Unable to apply ML changes: action list is unavailable.")
    return
  end

  if type(response.config) == "table" then
    if response.config.interval then
      updateConfig("interval", sanitizeNumber(response.config.interval, MLOptimizer.config.interval, 1), true)
    end
    if response.config.maxChanges then
      updateConfig("maxChanges", sanitizeNumber(response.config.maxChanges, MLOptimizer.config.maxChanges, 1, 20), true)
    end
  end

  local changes = response.changes or response.actions
  if type(changes) ~= "table" then
    if response.message then
      print("[CaveBot][ML] " .. tostring(response.message))
    end
    return
  end

  local applied = 0
  local focusIndex = getFocusedIndex(list)
  local maxChanges = sanitizeNumber(MLOptimizer.config.maxChanges, defaults.maxChanges, 1, 20)
  local appliedChanges = {}

  for _, change in ipairs(changes) do
    if applied >= maxChanges then
      break
    end
    local ok, result = pcall(handleChange, change, list)
    if ok and result then
      applied = applied + 1
      table.insert(appliedChanges, change)
    elseif not ok then
      warn("[CaveBot][ML] Failed to apply change: " .. tostring(result))
    end
  end

  if applied > 0 then
    if focusIndex then
      local childCount = list:getChildCount()
      if childCount > 0 then
        list:focusChild(list:getChildByIndex(math.min(focusIndex, childCount)))
      end
    end
    CaveBot.resetWalking()
    CaveBot.save()
    state.lastAppliedChanges = appliedChanges
    local store = ensureStorage()
    table.insert(store.history, {
      timestamp = os.time(),
      applied = applied,
      requestId = state.lastRequestId,
      metadata = response.metadata
    })
    print(string.format("[CaveBot][ML] Applied %d change(s) via ML optimizer.", applied))
  elseif response.message then
    print("[CaveBot][ML] " .. tostring(response.message))
  end
end

local function runLocalOptimizer(snapshot)
  if type(MLOptimizer.onOptimize) ~= "function" then
    return
  end
  local status, result = pcall(MLOptimizer.onOptimize, snapshot)
  if not status then
    warn("[CaveBot][ML] Local optimizer error: " .. tostring(result))
    return
  end
  if result then
    applyChanges(result)
  end
end

local function requestOptimization(roundNumber, snapshot)
  local endpoint = trim(MLOptimizer.config.endpoint)
  if endpoint == "" then
    return
  end

  local list = CaveBot.actionList
  if not list then
    return
  end

  local store = ensureStorage()
  state.pending = true
  state.lastRequestAt = now
  state.lastRequestId = state.lastRequestId + 1

  local payload = {
    request_id = state.lastRequestId,
    session_id = store.sessionId,
    timestamp = os.time(),
    player = getPlayerInfo(),
    round = {
      number = roundNumber,
      duration_ms = snapshot and snapshot.lastRoundDuration or nil,
      exp_gain = snapshot and snapshot.lastRoundExpGain or nil,
      exp_per_hour = snapshot and snapshot.expPerHour or nil,
      total_exp_gain = snapshot and snapshot.expGain or nil,
      rounds_completed = snapshot and snapshot.rounds or nil,
      runtime_ms = snapshot and snapshot.startTick and snapshot.timestamp and math.max(0, snapshot.timestamp - snapshot.startTick) or nil
    },
    cavebot = {
      profile = snapshot and snapshot.profile or (CaveBot.getCurrentProfile and CaveBot.getCurrentProfile()) or nil,
      waypoint_focus = getFocusedIndex(list),
      waypoint_count = list:getChildCount(),
      allow = {
        add = MLOptimizer.config.allowAdd,
        update = MLOptimizer.config.allowUpdate,
        remove = MLOptimizer.config.allowRemove,
        move = MLOptimizer.config.allowMove
      },
      max_changes = MLOptimizer.config.maxChanges,
      interval = MLOptimizer.config.interval
    },
    runtime = snapshot,
    waypoints = gatherWaypoints(),
    last_changes = state.lastAppliedChanges,
    auth_token = trim(MLOptimizer.config.authToken or "")
  }

  local playerPos = pos and pos()
  if playerPos then
    payload.environment = {
      position = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
    }
  end

  local postCallback = function(response, err)
    state.pending = false
    state.lastResponseAt = now
    if err then
      warn("[CaveBot][ML] Optimizer request failed: " .. tostring(err))
      return
    end
    applyChanges(response)
  end

  local ok, message = pcall(HTTP.postJSON, endpoint, payload, postCallback)
  if not ok then
    state.pending = false
    warn("[CaveBot][ML] Unable to send optimizer request: " .. tostring(message))
  else
    state.roundAccumulator = 0
  end
end

MLOptimizer.setup = function()
  ensureStorage()
  MLOptimizer.config = cloneDefaults()
  state.roundAccumulator = 0

  setDefaultTab("Cave")
  UI.Separator()
  ui.title = UI.Label("ML Waypoint Optimizer")
  UI.Separator()

  ui.enableSwitch = addSwitch("ml_optimizer_enable", "Enable ML optimizer", function(widget)
    if silentUiUpdate then return end
    widget:setOn(not widget:isOn())
    updateConfig("enabled", widget:isOn())
  end)
  ui.enableSwitch:setOn(MLOptimizer.config.enabled)

  UI.Label("Endpoint URL")
  ui.endpointInput = UI.TextEdit(MLOptimizer.config.endpoint or "", function(widget, text)
    if silentUiUpdate then return end
    updateConfig("endpoint", trim(text))
  end)

  UI.Label("Auth token (optional)")
  ui.authInput = UI.TextEdit(MLOptimizer.config.authToken or "", function(widget, text)
    if silentUiUpdate then return end
    updateConfig("authToken", trim(text))
  end)

  UI.Label("Optimize every X rounds")
  ui.intervalInput = UI.TextEdit(tostring(MLOptimizer.config.interval or defaults.interval), function(widget, text)
    if silentUiUpdate then return end
    local value = sanitizeNumber(text, MLOptimizer.config.interval, 1, 50)
    updateConfig("interval", value)
    local previous = silentUiUpdate
    silentUiUpdate = true
    widget:setText(tostring(value))
    silentUiUpdate = previous
  end)

  UI.Label("Max changes per optimization")
  ui.maxChangesInput = UI.TextEdit(tostring(MLOptimizer.config.maxChanges or defaults.maxChanges), function(widget, text)
    if silentUiUpdate then return end
    local value = sanitizeNumber(text, MLOptimizer.config.maxChanges, 1, 20)
    updateConfig("maxChanges", value)
    local previous = silentUiUpdate
    silentUiUpdate = true
    widget:setText(tostring(value))
    silentUiUpdate = previous
  end)

  UI.Label("Allowed operations")
  ui.allowAddSwitch = addSwitch("ml_optimizer_allow_add", "Allow add", function(widget)
    if silentUiUpdate then return end
    widget:setOn(not widget:isOn())
    updateConfig("allowAdd", widget:isOn())
  end)
  ui.allowAddSwitch:setOn(MLOptimizer.config.allowAdd)

  ui.allowUpdateSwitch = addSwitch("ml_optimizer_allow_update", "Allow update", function(widget)
    if silentUiUpdate then return end
    widget:setOn(not widget:isOn())
    updateConfig("allowUpdate", widget:isOn())
  end)
  ui.allowUpdateSwitch:setOn(MLOptimizer.config.allowUpdate)

  ui.allowRemoveSwitch = addSwitch("ml_optimizer_allow_remove", "Allow remove", function(widget)
    if silentUiUpdate then return end
    widget:setOn(not widget:isOn())
    updateConfig("allowRemove", widget:isOn())
  end)
  ui.allowRemoveSwitch:setOn(MLOptimizer.config.allowRemove)

  ui.allowMoveSwitch = addSwitch("ml_optimizer_allow_move", "Allow move", function(widget)
    if silentUiUpdate then return end
    widget:setOn(not widget:isOn())
    updateConfig("allowMove", widget:isOn())
  end)
  ui.allowMoveSwitch:setOn(MLOptimizer.config.allowMove)

  UI.Separator()
  UI.Label("Configure an HTTP endpoint that returns waypoint changes.")
end

MLOptimizer.onConfigChange = function(configName, isEnabled, configData)
  local newConfig = cloneDefaults()
  if type(configData) == "table" then
    for key, value in pairs(configData) do
      if newConfig[key] ~= nil then
        if type(newConfig[key]) == "boolean" then
          newConfig[key] = sanitizeBoolean(value, newConfig[key])
        elseif type(newConfig[key]) == "number" then
          if key == "interval" then
            newConfig[key] = sanitizeNumber(value, newConfig[key], 1, 50)
          elseif key == "maxChanges" then
            newConfig[key] = sanitizeNumber(value, newConfig[key], 1, 20)
          else
            newConfig[key] = sanitizeNumber(value, newConfig[key])
          end
        else
          newConfig[key] = value
        end
      end
    end
  end

  MLOptimizer.config = newConfig
  state.roundAccumulator = 0
  refreshUI()
end

MLOptimizer.onSave = function()
  return MLOptimizer.config
end

MLOptimizer.onRoundComplete = function(roundNumber, roundDuration, snapshot)
  state.lastSnapshot = snapshot
  state.roundAccumulator = (state.roundAccumulator or 0) + 1

  if not MLOptimizer.config.enabled then
    return
  end

  local list = CaveBot.actionList
  if not list or list:getChildCount() == 0 then
    return
  end

  if state.pending then
    return
  end

  local interval = sanitizeNumber(MLOptimizer.config.interval, defaults.interval, 1, 50)
  if interval <= 0 then
    interval = 1
  end

  if state.roundAccumulator % interval ~= 0 then
    return
  end

  local endpoint = trim(MLOptimizer.config.endpoint)
  if endpoint == "" then
    runLocalOptimizer(snapshot)
    state.roundAccumulator = 0
    return
  end

  requestOptimization(roundNumber, snapshot)
end
