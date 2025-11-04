local context = G.botContext
local Panels = context.Panels

Panels.Waypoints = function(parent)
  local ui = context.setupUI([[
Panel
  id: waypoints
  height: 206
  
  BotLabel
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text: Waypoints
  
  ComboBox
    id: config
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    text-offset: 3 0
    width: 130

  Button
    id: enableButton
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 5
      
  Button
    margin-top: 1
    id: add
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Add
    width: 60
    height: 17

  Button
    id: edit
    anchors.top: prev.top
    anchors.horizontalCenter: parent.horizontalCenter
    text: Edit
    width: 60
    height: 17

  Button
    id: remove
    anchors.top: prev.top
    anchors.right: parent.right
    text: Remove
    width: 60
    height: 17
  
  TextList
    id: list
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    vertical-scrollbar: listScrollbar
    margin-right: 15
    margin-top: 2
    height: 60
    focusable: false
    auto-focus: first
    
  VerticalScrollBar
    id: listScrollbar
    anchors.top: prev.top
    anchors.bottom: prev.bottom
    anchors.right: parent.right
    pixels-scroll: true
    step: 5
    
  Label
    id: pos
    anchors.top: prev.bottom
    anchors.left: parent.left    
    anchors.right: parent.right
    text-align: center
    margin-top: 2
    
  Button
    id: wGoto
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Goto
    width: 61
    margin-top: 1
    height: 17

  Button
    id: wUse
    anchors.top: prev.top
    anchors.left: prev.right
    text: Use
    width: 61
    height: 17

  Button
    id: wUseWith
    anchors.top: prev.top
    anchors.left: prev.right
    text: UseWith
    width: 61
    height: 17

  Button
    id: wWait
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Wait
    width: 61
    margin-top: 1
    height: 17
    
  Button
    id: wSay
    anchors.top: prev.top
    anchors.left: prev.right
    text: Say
    width: 61
    height: 17

  Button
    id: wNpc
    anchors.top: prev.top
    anchors.left: prev.right
    text: Say NPC
    width: 61
    height: 17
    
  Button
    id: wLabel
    anchors.top: prev.bottom
    anchors.left: parent.left
    text: Label
    width: 61
    margin-top: 1
    height: 17
    
  Button
    id: wFollow
    anchors.top: prev.top
    anchors.left: prev.right
    text: Follow
    width: 61
    height: 17

  Button
    id: wFunction
    anchors.top: prev.top
    anchors.left: prev.right
    text: Function
    width: 61
    height: 17
    
  BotSwitch
    id: recording
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    text: Auto Recording
    height: 17

]], parent)

  if type(context.storage.cavebot) ~= "table" then
    context.storage.cavebot = {}
  end
  if type(context.storage.cavebot.configs) ~= "table" then
    context.storage.cavebot.configs = {}  
  end
  
  local getConfigName = function(config)
    local matches = regexMatch(config, [[name:\s*([^\n]*)$]])
    if matches[1] and matches[1][2] then
      return matches[1][2]:trim()
    end
    return nil
  end
  
  local isValidCommand = function(command)
    if command == "goto" then
      return true
    elseif command == "use" then
      return true
    elseif command == "usewith" then
      return true
    elseif command == "wait" then
      return true
    elseif command == "say" then
      return true
    elseif command == "npc" then
      return true
    elseif command == "follow" then
      return true
    elseif command == "label" then
      return true
    elseif command == "gotolabel" then
      return true
    elseif command == "comment" then
      return true
    elseif command == "function" then
      return true
    end
    return false
  end

  local function splitLines(str)
    local lines = {}
    if not str or str == "" then
      return lines
    end
    for line in (str .. "\n"):gmatch("([^\n]*)\n") do
      table.insert(lines, line)
    end
    if #lines > 0 and lines[#lines] == "" then
      table.remove(lines, #lines)
    end
    return lines
  end

  local function splitConfigText(config)
    if not config or config:len() == 0 then
      return "", ""
    end
    local lines = splitLines(config)
    local firstCommandIndex = nil
    for idx, line in ipairs(lines) do
      local colonPos = line:find(":")
      if colonPos then
        local commandName = line:sub(1, colonPos - 1):lower()
        if isValidCommand(commandName) then
          firstCommandIndex = idx
          break
        end
      end
    end
    if not firstCommandIndex then
      return config, ""
    end
    local headerLines = {}
    for i = 1, firstCommandIndex - 1 do
      table.insert(headerLines, lines[i])
    end
    local bodyLines = {}
    for i = firstCommandIndex, #lines do
      table.insert(bodyLines, lines[i])
    end
    return table.concat(headerLines, "\n"), table.concat(bodyLines, "\n")
  end

  local function parseCommandsBody(body)
    local parsed = {}
    if not body or body:len() == 0 then
      return parsed
    end
    local matches = regexMatch(body, [[([^:^\n^\s]+)(:?)([^\n]*)]])
    for i = 1, #matches do
      local command = matches[i][2]
      local hasColon = (matches[i][3] == ":")
      if not hasColon or isValidCommand(command) then
        local text = matches[i][4]
        if hasColon then
          table.insert(parsed, { command = command:lower(), text = text or "" })
        elseif #parsed > 0 then
          parsed[#parsed].text = parsed[#parsed].text .. "\n" .. (matches[i][1] or "")
        end
      end
    end
    return parsed
  end

  local function cloneCommandsList(source)
    local cloned = {}
    for i = 1, #source do
      local entry = source[i]
      cloned[i] = {
        command = entry.command,
        text = entry.text,
      }
    end
    return cloned
  end

  local function resolveCommandText(commandName, value)
    if value == nil then
      return "", nil
    end
    local valueType = type(value)
    if valueType == "string" or valueType == "number" then
      return tostring(value), nil
    end
    if valueType ~= "table" then
      return nil, "unsupported value type"
    end

    commandName = commandName and commandName:lower() or ""
    local function extractPosition(tbl)
      local pos = tbl.position or tbl.pos
      local x = tbl.x or (pos and (pos.x or pos[1])) or tbl[1]
      local y = tbl.y or (pos and (pos.y or pos[2])) or tbl[2]
      local z = tbl.z or (pos and (pos.z or pos[3])) or tbl[3]
      if x and y and z then
        return tonumber(x), tonumber(y), tonumber(z)
      end
    end

    if commandName == "goto" or commandName == "use" then
      local x, y, z = extractPosition(value)
      if not x then
        return nil, "missing position for command " .. commandName
      end
      return string.format("%d,%d,%d", x, y, z), nil
    elseif commandName == "usewith" then
      local itemId = value.itemId or value.item or value.id or value[1]
      if type(itemId) ~= "number" then
        return nil, "missing itemId for usewith command"
      end
      local x, y, z = extractPosition(value)
      if not x then
        return nil, "missing position for usewith command"
      end
      return string.format("%d,%d,%d,%d", itemId, x, y, z), nil
    elseif commandName == "wait" then
      local duration = value.ms or value.milliseconds or value[1]
      if not duration then
        return nil, "missing duration for wait command"
      end
      return tostring(duration), nil
    elseif commandName == "label" or commandName == "gotolabel" or commandName == "follow" or commandName == "say" or commandName == "npc" or commandName == "comment" then
      local text = value.text or value[1]
      if not text then
        return nil, "missing text for " .. commandName .. " command"
      end
      return tostring(text), nil
    elseif commandName == "function" then
      local script = value.script or value[1]
      if not script then
        return nil, "missing script for function command"
      end
      return tostring(script), nil
    end

    return nil, "unsupported payload for command " .. commandName
  end

  local function normalizeCommandEntry(entry)
    if type(entry) == "string" then
      local colonPos = entry:find(":")
      if not colonPos then
        return { command = "comment", text = entry }
      end
      local commandName = entry:sub(1, colonPos - 1):lower()
      local text = entry:sub(colonPos + 1)
      if not isValidCommand(commandName) then
        return nil, "invalid command " .. commandName
      end
      return { command = commandName, text = text }
    elseif type(entry) == "table" then
      local commandName = entry.command or entry[1]
      if type(commandName) ~= "string" then
        return nil, "missing command name"
      end
      commandName = commandName:lower()
      if not isValidCommand(commandName) then
        return nil, "invalid command " .. commandName
      end
      local text = entry.text or entry.value or entry.payload or entry[2]
      local resolvedText, err = resolveCommandText(commandName, text)
      if err then
        return nil, err
      end
      return { command = commandName, text = resolvedText or "" }
    end
    return nil, "unsupported command entry type"
  end

  local function buildBodyFromCommands(commandList)
    local lines = {}
    for _, cmd in ipairs(commandList) do
      local text = cmd.text or ""
      local textLines = splitLines(text)
      if #textLines == 0 then
        table.insert(lines, cmd.command .. ":")
      else
        table.insert(lines, cmd.command .. ":" .. textLines[1])
        for i = 2, #textLines do
          table.insert(lines, textLines[i])
        end
      end
    end
    return table.concat(lines, "\n")
  end

  local function trimTrailingNewline(str)
    if not str or str == "" then
      return ""
    end
    if str:sub(-1) == "\n" then
      return trimTrailingNewline(str:sub(1, -2))
    end
    return str
  end

  local commands = {}
  local lastKnownHeader = ""
  if type(context.cavebot) ~= "table" then
    context.cavebot = {}
  end
  if type(context.storage.cavebot.mlOptimizer) ~= "table" then
    context.storage.cavebot.mlOptimizer = {}
  end
  local mlState = context.storage.cavebot.mlOptimizer
  mlState.history = mlState.history or {}
  mlState.roundsPerUpdate = mlState.roundsPerUpdate or 5
  mlState.enabled = mlState.enabled or false
  mlState.round = mlState.round or 0
  mlState.maxHistory = mlState.maxHistory or 50
  local optimizerOptions = {
    roundsPerUpdate = mlState.roundsPerUpdate,
    maxHistory = mlState.maxHistory or 50,
  }
  local registeredOptimizer = nil
  local optimizerRunning = false
  local roundStartExp = context.player and context.player:getExperience() or 0
  local roundStartTime = context.now

  local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
  end

  local function getActiveConfigText()
    if not context.storage.cavebot.activeConfig then
      return nil
    end
    return context.storage.cavebot.configs[context.storage.cavebot.activeConfig]
  end

  local function updateActiveConfigWithCommands(commandList, scrollDown)
    local activeText = getActiveConfigText()
    if not activeText then
      return false, "no active config"
    end
    local header, _ = splitConfigText(activeText)
    lastKnownHeader = header
    local body = buildBodyFromCommands(commandList)
    local newConfig = ""
    header = trimTrailingNewline(header)
    if header ~= "" then
      if body ~= "" then
        newConfig = header .. "\n" .. body
      else
        newConfig = header
      end
    else
      newConfig = body
    end
    context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = newConfig
    refreshConfig(scrollDown)
    return true
  end

  local function applyOperations(operations, options)
    if type(operations) ~= "table" then
      return false, "operations must be a table"
    end
    local working = cloneCommandsList(commands)

    local function findLabelIndex(label)
      for idx, entry in ipairs(working) do
        if entry.command == "label" and entry.text == label then
          return idx
        end
      end
      return nil
    end

    local function performOperation(op)
      if type(op) ~= "table" then
        return false, "operation must be a table"
      end
      local opType = op.type or op.op or op.action
      if type(opType) ~= "string" then
        return false, "operation missing type"
      end
      opType = opType:lower()

      if opType == "add" or opType == "insert" then
        if not op.command then
          return false, "add operation missing command"
        end
        local commandName = op.command:lower()
        if not isValidCommand(commandName) then
          return false, "invalid command " .. commandName
        end
        local value = op.text or op.value or op.payload or op.data
        local resolvedText, err = resolveCommandText(commandName, value)
        if err then
          return false, err
        end
        local index = op.index or op.position
        if index then
          index = clamp(math.floor(index), 1, #working + 1)
          table.insert(working, index, { command = commandName, text = resolvedText or "" })
        else
          table.insert(working, { command = commandName, text = resolvedText or "" })
        end
        return true
      elseif opType == "remove" or opType == "delete" then
        local index = op.index or op.position or op.at
        if not index and op.label then
          index = findLabelIndex(op.label)
        end
        if not index then
          return false, "remove operation missing index"
        end
        index = math.floor(index)
        if index < 1 or index > #working then
          return false, "remove index out of range"
        end
        table.remove(working, index)
        return true
      elseif opType == "move" or opType == "reorder" then
        local fromIndex = op.from or op.index or op.source
        local toIndex = op.to or op.target or op.position
        if not fromIndex or not toIndex then
          return false, "move operation missing from/to"
        end
        fromIndex = clamp(math.floor(fromIndex), 1, #working)
        toIndex = clamp(math.floor(toIndex), 1, #working)
        if fromIndex == toIndex then
          return true
        end
        local item = table.remove(working, fromIndex)
        table.insert(working, toIndex, item)
        return true
      elseif opType == "update" or opType == "set" then
        local index = op.index or op.position or op.at
        if not index then
          if op.label then
            index = findLabelIndex(op.label)
          end
        end
        if not index then
          return false, "update operation missing index"
        end
        index = clamp(math.floor(index), 1, #working)
        local entry = working[index]
        if op.command then
          local commandName = op.command:lower()
          if not isValidCommand(commandName) then
            return false, "invalid command " .. commandName
          end
          entry.command = commandName
        end
        if op.text ~= nil or op.value ~= nil or op.payload ~= nil or op.data ~= nil then
          local value = op.text or op.value or op.payload or op.data
          local resolvedText, err = resolveCommandText(entry.command, value)
          if err then
            return false, err
          end
          entry.text = resolvedText or ""
        end
        return true
      end
      return false, "unknown operation type " .. opType
    end

    for _, operation in ipairs(operations) do
      local ok, err = performOperation(operation)
      if not ok then
        return false, err
      end
    end

    return updateActiveConfigWithCommands(working, options and options.scrollDown)
  end

  local function setCommandsFromList(commandList, options)
    if type(commandList) ~= "table" then
      return false, "commands must be a table"
    end
    local normalized = {}
    for i = 1, #commandList do
      local cmdEntry, err = normalizeCommandEntry(commandList[i])
      if not cmdEntry then
        return false, err
      end
      table.insert(normalized, cmdEntry)
    end
    return updateActiveConfigWithCommands(normalized, options and options.scrollDown)
  end

  local function replaceActiveConfig(configText, options)
    if not context.storage.cavebot.activeConfig then
      return false, "no active config"
    end
    if type(configText) ~= "string" then
      return false, "configText must be string"
    end
    context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = configText
    refreshConfig(options and options.scrollDown)
    return true
  end

  local function copyHistory(history)
    local cloned = {}
    for i = 1, #history do
      local item = history[i]
      cloned[i] = {
        round = item.round,
        expGain = item.expGain,
        durationMs = item.durationMs,
        expPerHour = item.expPerHour,
        timestamp = item.timestamp,
        commandCount = item.commandCount,
      }
    end
    return cloned
  end

  local function getCurrentExp()
    if context.player and context.player.getExperience then
      return context.player:getExperience()
    end
    return mlState.lastKnownExp or 0
  end

  local function getCurrentLevel()
    if context.player and context.player.getLevel then
      return context.player:getLevel()
    end
    return mlState.lastKnownLevel or 0
  end

  local function computeExpPerHour(expGain, durationMs)
    if not durationMs or durationMs <= 0 then
      return 0
    end
    return (expGain * 3600000) / durationMs
  end

  local function getPlayerExpPerHour()
    if context.player and context.player.expSpeed then
      return math.floor(context.player.expSpeed * 3600)
    end
    return 0
  end

  local function summariseHistory()
    local totalExp = 0
    local totalTime = 0
    for _, entry in ipairs(mlState.history) do
      totalExp = totalExp + (entry.expGain or 0)
      totalTime = totalTime + (entry.durationMs or 0)
    end
    return totalExp, totalTime
  end

  local function runOptimizer(triggerEntry)
    if not registeredOptimizer or optimizerRunning then
      return
    end
    optimizerRunning = true
    local snapshot = {
      round = mlState.round,
      trigger = triggerEntry,
      commands = cloneCommandsList(commands),
      history = copyHistory(mlState.history),
      expPerHour = computeExpPerHour(select(1, summariseHistory()), select(2, summariseHistory())),
      player = {
        level = getCurrentLevel(),
        experience = getCurrentExp(),
        expPerHour = getPlayerExpPerHour(),
        expSpeed = context.player and context.player.expSpeed or nil,
      },
      config = {
        index = context.storage.cavebot.activeConfig,
        name = context.storage.cavebot.activeConfig and getConfigName(context.storage.cavebot.configs[context.storage.cavebot.activeConfig]) or nil,
        roundsPerUpdate = optimizerOptions.roundsPerUpdate,
        commandCount = #commands,
      },
      timestamp = context.now,
      state = mlState.userState,
    }

    local status, result = pcall(registeredOptimizer, snapshot)
    optimizerRunning = false

    if not status then
      context.error("Waypoint optimizer error: " .. tostring(result))
      mlState.enabled = false
      return
    end

    if result == nil then
      return
    end

    local applied = false
    if type(result) == "string" then
      applied = replaceActiveConfig(result)
    elseif type(result) == "table" then
      if result.config then
        applied = replaceActiveConfig(result.config, result.options)
      elseif result.commands then
        applied = setCommandsFromList(result.commands, result.options)
      elseif result.operations then
        local ok, err = applyOperations(result.operations, result.options)
        if not ok and err then
          context.error("Waypoint optimizer operations failed: " .. err)
        end
        applied = ok
      end
      if result.state ~= nil then
        mlState.userState = result.state
      end
      if result.roundsPerUpdate then
        optimizerOptions.roundsPerUpdate = math.max(1, math.floor(result.roundsPerUpdate))
        mlState.roundsPerUpdate = optimizerOptions.roundsPerUpdate
      end
    end

    if applied then
      mlState.lastOptimizerRunRound = mlState.round
      mlState.lastOptimizerRunAt = context.now
      mlState.totalMutations = (mlState.totalMutations or 0) + 1
    end
  end

  local function resetRoundTracking()
    roundStartExp = getCurrentExp()
    roundStartTime = context.now
  end

  local function onRoundComplete()
    local currentExp = getCurrentExp()
    local now = context.now
    local expGain = currentExp - roundStartExp
    local durationMs = now - roundStartTime
    local expPerHour = computeExpPerHour(expGain, durationMs)

    mlState.round = (mlState.round or 0) + 1
    mlState.lastKnownExp = currentExp
    mlState.lastKnownLevel = getCurrentLevel()

    local roundEntry = {
      round = mlState.round,
      expGain = expGain,
      durationMs = durationMs,
      expPerHour = expPerHour,
      timestamp = now,
      commandCount = #commands,
    }
    table.insert(mlState.history, roundEntry)
    local maxHistory = optimizerOptions.maxHistory or 50
    while #mlState.history > maxHistory do
      table.remove(mlState.history, 1)
    end

    resetRoundTracking()

    if mlState.enabled and registeredOptimizer and optimizerOptions.roundsPerUpdate > 0 then
      if (mlState.round % optimizerOptions.roundsPerUpdate) == 0 then
        runOptimizer(roundEntry)
      end
    end
  end

  local waitTo = 0
  local autoRecording = false

  local parseConfig = function(config)
    commands = {}
    lastKnownHeader = ""
    if not config or config:len() == 0 then
      return
    end

    local header, body = splitConfigText(config)
    lastKnownHeader = header or ""
    commands = parseCommandsBody(body)

    for i = 1, #commands do
      commands[i].index = i
      commands[i].text = commands[i].text or ""
      local label = g_ui.createWidget("CaveBotLabel", ui.list)
      if commands[i].command == "comment" then
        label:setText(commands[i].text)
        label:setColor("white")
      else
        label:setText(commands[i].command .. ":" .. commands[i].text)
        if commands[i].command == "goto" then
          label:setColor("green")
        elseif commands[i].command == "label" then
          label:setColor("yellow")
        elseif commands[i].command == "use" or commands[i].command == "usewith" then
          label:setColor("orange")
        elseif commands[i].command == "gotolabel" then
          label:setColor("red")
        end
      end
    end
  end
  
  local ignoreOnOptionChange = true
  local refreshConfig = function(scrollDown)
    ignoreOnOptionChange = true
    if context.storage.cavebot.enabled then
      autoRecording = false
      ui.recording:setOn(false)
      ui.enableButton:setText("On")
      ui.enableButton:setColor('#00AA00FF')
    else
      ui.enableButton:setText("Off")
      ui.enableButton:setColor('#FF0000FF')
      ui.recording:setOn(autoRecording)
    end
        
    ui.config:clear()
    for i, config in ipairs(context.storage.cavebot.configs) do
      local name = getConfigName(config)
      if not name then
        name = "Unnamed config"
      end
      ui.config:addOption(name)
    end
    
    if (not context.storage.cavebot.activeConfig or context.storage.cavebot.activeConfig == 0) and #context.storage.cavebot.configs > 0 then
       context.storage.cavebot.activeConfig = 1
    end
    
      ui.list:destroyChildren()

      if context.storage.cavebot.activeConfig and context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
        if mlState.currentConfigIndex ~= context.storage.cavebot.activeConfig then
          mlState.currentConfigIndex = context.storage.cavebot.activeConfig
          mlState.round = 0
          mlState.history = {}
          mlState.lastKnownExp = nil
          mlState.lastKnownLevel = nil
          resetRoundTracking()
        end
        ui.config:setCurrentIndex(context.storage.cavebot.activeConfig)
        mlState.currentConfigName = getConfigName(context.storage.cavebot.configs[context.storage.cavebot.activeConfig])
        parseConfig(context.storage.cavebot.configs[context.storage.cavebot.activeConfig])
      end
    
    context.saveConfig()
    if scrollDown and ui.list:getLastChild() then
      ui.list:focusChild(ui.list:getLastChild())
    end
    
    waitTo = 0
    ignoreOnOptionChange = false
  end

  
  ui.config.onOptionChange = function(widget)
    if not ignoreOnOptionChange then
      context.storage.cavebot.activeConfig = widget.currentIndex
      refreshConfig()
    end
  end
  ui.enableButton.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    context.storage.cavebot.enabled = not context.storage.cavebot.enabled
    if autoRecording then
      refreshConfig()
    elseif context.storage.cavebot.enabled then
      ui.enableButton:setText("On")
      ui.enableButton:setColor('#00AA00FF')
    else
      ui.enableButton:setText("Off")
      ui.enableButton:setColor('#FF0000FF')
    end
  end
  ui.add.onClick = function()
    modules.client_textedit.multilineEditor("Waypoints editor", "name:Config name\nlabel:start\n", function(newText)
      table.insert(context.storage.cavebot.configs, newText)
      context.storage.cavebot.activeConfig = #context.storage.cavebot.configs
      refreshConfig()
    end)
  end
  ui.edit.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    modules.client_textedit.multilineEditor("Waypoints editor", context.storage.cavebot.configs[context.storage.cavebot.activeConfig], function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = newText
      refreshConfig()
    end)
  end
  ui.remove.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    local questionWindow = nil
    local closeWindow = function()
      questionWindow:destroy()
    end
    local removeConfig = function()
      closeWindow()
      if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
        return
      end
      context.storage.cavebot.enabled = false
      table.remove(context.storage.cavebot.configs, context.storage.cavebot.activeConfig)
      context.storage.cavebot.activeConfig = 0
      refreshConfig()
    end
    questionWindow = context.displayGeneralBox(tr('Remove config'), tr('Do you want to remove current waypoints config?'), {
      { text=tr('Yes'), callback=removeConfig },
      { text=tr('No'), callback=closeWindow },
      anchor=AnchorHorizontalCenter}, removeConfig, closeWindow)
  end
  
  -- waypoint editor
  -- auto recording
  local stepsSincleLastPos = 0
  
  context.onPlayerPositionChange(function(newPos, oldPos)
    ui.pos:setText("Position: " .. newPos.x .. ", " .. newPos.y .. ", " .. newPos.z)
    if not autoRecording then
      return
    end
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    local newText = ""
    if newPos.z ~= oldPos.z then
      newText = "goto:" .. oldPos.x .. "," .. oldPos.y .. "," .. oldPos.z
      newText = newText .. "\ngoto:" .. newPos.x .. "," .. newPos.y .. "," .. newPos.z
      stepsSincleLastPos = 0
    else
      stepsSincleLastPos = stepsSincleLastPos + 1
      if stepsSincleLastPos > 10 then
        newText = "goto:" .. oldPos.x .. "," .. oldPos.y .. "," .. oldPos.z
        stepsSincleLastPos = 0
      end
    end

    if newText:len() > 0 then
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\n" .. newText
      refreshConfig(true)
    end
  end)
  
  context.onUse(function(pos, itemId, stackPos, subType)
    if not autoRecording then
      return
    end
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    if pos.x == 0xFFFF then
      return
    end
    stepsSincleLastPos = 0
    local playerPos = context.player:getPosition()
    newText = "goto:" .. playerPos.x .. "," .. playerPos.y .. "," .. playerPos.z .. "\nuse:" .. pos.x .. "," .. pos.y .. "," .. pos.z
    context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\n" .. newText
    refreshConfig(true)
  end)
  context.onUseWith(function(pos, itemId, target, subType)
    if not autoRecording then
      return
    end
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    if not target:isItem() then
      return
    end
    local targetPos = target:getPosition()
    if targetPos.x == 0xFFFF then
      return
    end
    stepsSincleLastPos = 0
    local playerPos = context.player:getPosition()
    newText = "goto:" .. playerPos.x .. "," .. playerPos.y .. "," .. playerPos.z .. "\nusewith:" .. itemId .. "," .. targetPos.x .. "," .. targetPos.y .. "," .. targetPos.z
    context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\n" .. newText
    refreshConfig(true)
  end)

  -- ui
  local pos = context.player:getPosition()
  ui.pos:setText("Position: " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)

  ui.wGoto.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    local pos = context.player:getPosition()
    modules.client_textedit.singlelineEditor("" .. pos.x .. "," .. pos.y .. "," .. pos.z, function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\ngoto:" .. newText
      refreshConfig(true)
    end)
  end

  ui.wUse.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    local pos = context.player:getPosition()
    modules.client_textedit.singlelineEditor("" .. pos.x .. "," .. pos.y .. "," .. pos.z, function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nuse:" .. newText
      refreshConfig(true)
    end)
  end
  
  ui.wUseWith.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    local pos = context.player:getPosition()
    modules.client_textedit.singlelineEditor("ITEMID," .. pos.x .. "," .. pos.y .. "," .. pos.z, function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nusewith:" .. newText
      refreshConfig(true)
    end)
  end
  
  ui.wWait.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    modules.client_textedit.singlelineEditor("1000", function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nwait:" .. newText
      refreshConfig(true)
    end)
  end

  ui.wSay.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    modules.client_textedit.singlelineEditor("text", function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nsay:" .. newText
      refreshConfig(true)
    end)
  end
  
  ui.wNpc.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    modules.client_textedit.singlelineEditor("text", function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nnpc:" .. newText
      refreshConfig(true)
    end)
  end

  ui.wLabel.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    modules.client_textedit.singlelineEditor("label name", function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nlabel:" .. newText
      refreshConfig(true)
    end)
  end

  ui.wFollow.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    modules.client_textedit.singlelineEditor("creature name", function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nfollow:" .. newText
      refreshConfig(true)
    end)
  end  
  
  ui.wFunction.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    modules.client_textedit.multilineEditor("Add function", "function(waypoints)\n  -- your lua code, function is executed if previous goto was successful or is just after label\n\n  -- must return true to execute next command, otherwise will run in loop till correct return\n  return true\nend", function(newText)
      context.storage.cavebot.configs[context.storage.cavebot.activeConfig] = context.storage.cavebot.configs[context.storage.cavebot.activeConfig] .. "\nfunction:" .. newText
      refreshConfig(true)
    end)
  end
  
  ui.recording.onClick = function()
    if not context.storage.cavebot.activeConfig or not context.storage.cavebot.configs[context.storage.cavebot.activeConfig] then
      return
    end
    autoRecording = not autoRecording
    if autoRecording then
      context.storage.cavebot.enabled = false
      stepsSincleLastPos = 10
    end
    refreshConfig(true)
  end
  
  refreshConfig()

  local usedGotoLabel = false
  local executeNextMacroCall = false
  local commandExecutionNo = 0
  local lastGotoSuccesful = true
  local lastOpenedContainer = 0
  
  local functions = {
    enable = function()
      context.storage.cavebot.enabled = true
      refreshConfig()    
    end,
    disable = function()
      context.storage.cavebot.enabled = false
      refreshConfig()        
    end,
    refresh = function()
      refreshConfig()
    end,
    wait = function(peroid)
      waitTo = context.now + peroid
    end,
    waitTo = function(timepoint)
      waitTo = timepoint
    end,
    gotoLabel = function(name)
      for i=1,ui.list:getChildCount() do
        local command = commands[i]
        if command and command.command == "label" and command.text == name then
          ui.list:focusChild(ui.list:getChildByIndex(i))
          usedGotoLabel = true
          lastGotoSuccesful = true
          return true
        end
      end
      end,
      getCommands = function()
        return cloneCommandsList(commands)
      end,
      setCommands = function(newCommands, options)
        return setCommandsFromList(newCommands, options)
      end,
      setConfig = function(configText, options)
        return replaceActiveConfig(configText, options)
      end,
      applyOperations = function(ops, options)
        return applyOperations(ops, options)
      end,
      getOptimizerState = function()
        return {
          enabled = mlState.enabled and registeredOptimizer ~= nil,
          registered = registeredOptimizer ~= nil,
          roundsPerUpdate = optimizerOptions.roundsPerUpdate,
          round = mlState.round,
          history = copyHistory(mlState.history),
          lastRunRound = mlState.lastOptimizerRunRound,
          lastRunAt = mlState.lastOptimizerRunAt,
          totalMutations = mlState.totalMutations or 0,
          currentConfigIndex = mlState.currentConfigIndex,
          currentConfigName = mlState.currentConfigName,
        }
      end,
      registerOptimizer = function(handler, options)
        if type(handler) ~= "function" then
          return false, "optimizer handler must be a function"
        end
        registeredOptimizer = handler
        mlState.enabled = true
        if type(options) == "table" then
          if options.roundsPerUpdate then
            optimizerOptions.roundsPerUpdate = math.max(1, math.floor(options.roundsPerUpdate))
            mlState.roundsPerUpdate = optimizerOptions.roundsPerUpdate
          end
          if options.maxHistory then
            optimizerOptions.maxHistory = math.max(1, math.floor(options.maxHistory))
            mlState.maxHistory = optimizerOptions.maxHistory
          end
        end
        return true
      end,
      unregisterOptimizer = function()
        registeredOptimizer = nil
        mlState.enabled = false
      end,
      setOptimizerEnabled = function(value)
        mlState.enabled = value and true or false
      end,
      configureOptimizer = function(options)
        if type(options) ~= "table" then
          return false, "options must be a table"
        end
        if options.roundsPerUpdate then
          optimizerOptions.roundsPerUpdate = math.max(1, math.floor(options.roundsPerUpdate))
          mlState.roundsPerUpdate = optimizerOptions.roundsPerUpdate
        end
        if options.maxHistory then
          optimizerOptions.maxHistory = math.max(1, math.floor(options.maxHistory))
          mlState.maxHistory = optimizerOptions.maxHistory
        end
        return true
      end,
      getConfigText = function()
        return getActiveConfigText()
      end,
      isOptimizerRegistered = function()
        return registeredOptimizer ~= nil
      end
  }
  
    context.cavebot.panel = functions
    context.cavebot.getCommands = functions.getCommands
    context.cavebot.setCommands = functions.setCommands
    context.cavebot.applyOperations = functions.applyOperations
    context.cavebot.getConfigText = functions.getConfigText
    context.cavebot.setConfig = functions.setConfig
    context.cavebot.getOptimizerState = functions.getOptimizerState
    context.cavebot.registerOptimizer = functions.registerOptimizer
    context.cavebot.unregisterOptimizer = functions.unregisterOptimizer
    context.cavebot.setOptimizerEnabled = functions.setOptimizerEnabled
    context.cavebot.configureOptimizer = functions.configureOptimizer
    context.cavebot.isOptimizerRegistered = functions.isOptimizerRegistered

    context.cavebot.optimizer = context.cavebot.optimizer or {}
    context.cavebot.optimizer.register = functions.registerOptimizer
    context.cavebot.optimizer.unregister = functions.unregisterOptimizer
    context.cavebot.optimizer.configure = functions.configureOptimizer
    context.cavebot.optimizer.enable = functions.setOptimizerEnabled
    context.cavebot.optimizer.disable = function()
      functions.setOptimizerEnabled(false)
    end
    context.cavebot.optimizer.getState = functions.getOptimizerState

    context.onContainerOpen(function(container)
      if container:getItemsCount() > 0 then
        lastOpenedContainer = context.now + container:getItemsCount() * 100
      end
    end)

  
  context.macro(250, function()
    if not context.storage.cavebot.enabled then
      return
    end

    if modules.game_walking.lastManualWalk + 500 > context.now then
      return
    end
    
    -- wait if walked or opened container recently
    if context.player:isWalking() or lastOpenedContainer + 1000 > context.now then
      executeNextMacroCall = false
      return
    end
    
    -- wait if attacking/following creature
    local attacking = g_game.getAttackingCreature()
    local following = g_game.getFollowingCreature()
    if (attacking and context.getCreatureById(attacking:getId()) and not attacking.ignoreByWaypoints) or (following and context.getCreatureById(following:getId())) then
      executeNextMacroCall = false
      return 
    end
    
    if not executeNextMacroCall then
      executeNextMacroCall = true
      return
    end
    executeNextMacroCall = false
    
    local commandWidget = ui.list:getFocusedChild()
    if not commandWidget then
      if ui.list:getFirstChild() then
        ui.list:focusChild(ui.list:getFirstChild())
      end
      return
    end
    
    local commandIndex = ui.list:getChildIndex(commandWidget)
    local command = commands[commandIndex]
    if not command then
      if ui.list:getFirstChild() then
        ui.list:focusChild(ui.list:getFirstChild())
      end
      return
    end
    
    if commandIndex == 1 then
      lastGotoSuccesful = true
    end
    
    if command.command == "goto" or command.command == "follow" then
      local matches = regexMatch(command.text, [[([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)]])
      if (#matches == 1 and #matches[1] == 4) or command.command == "follow" then
        local position = nil
        if command.command == "follow" then
          local creature = context.getCreatureByName(command.text)
          if creature then
            position = creature:getPosition()
          end
        else
          position = {x=tonumber(matches[1][2]), y=tonumber(matches[1][3]), z=tonumber(matches[1][4])}        
        end
        local distance = 0
        if position then
          distance = context.getDistanceBetween(position, context.player:getPosition())
        end
        if distance > 100 or not position or position.z ~= context.player:getPosition().z then
          lastGotoSuccesful = false
        elseif distance > 0 then
          if not context.findPath(context.player:getPosition(), position, 100, { ignoreNonPathable = true, precision = 1, ignoreCreatures = true }) then
            lastGotoSuccesful = false          
            executeNextMacroCall = true
          else
            commandExecutionNo = commandExecutionNo + 1
            lastGotoSuccesful = false
            if commandExecutionNo <= 3 then -- try max 3 times
              if not context.autoWalk(position, distance * 2, { ignoreNonPathable = false }) then
                if commandExecutionNo > 1 then
                  if context.autoWalk(position, distance * 2, { ignoreNonPathable = true, precision = 1 }) then
                    context.delay(500)
                  end
                end
                return
              end
              return
            elseif commandExecutionNo == 4 then -- try last time, location close to destination
              if context.autoWalk(position, distance * 2, { ignoreNonPathable = true, ignoreLastCreature = true, precision = 2, allowUnseen = true }) then
                context.delay(500)
                return
              end
            elseif distance <= 2 then
              lastGotoSuccesful = true
              executeNextMacroCall = true
            end
          end
        else
          lastGotoSuccesful = true
          executeNextMacroCall = true
        end
      else
        context.error("Waypoints: invalid use of goto function")
      end
    elseif command.command == "use" then
      local matches = regexMatch(command.text, [[([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)]])
      if #matches == 1 and #matches[1] == 4 then
        local position = {x=tonumber(matches[1][2]), y=tonumber(matches[1][3]), z=tonumber(matches[1][4])} 
        if context.player:getPosition().z == position.z then
          local tile = g_map.getTile(position)
          if tile then
            local topThing = tile:getTopUseThing()
            if topThing then
              g_game.use(topThing)
              context.delay(500)
            end
          end
        end
      else
        context.error("Waypoints: invalid use of use function")
      end
    elseif command.command == "usewith" then
      local matches = regexMatch(command.text, [[([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+)]])
      if #matches == 1 and #matches[1] == 5 then
        local itemId = tonumber(matches[1][2])
        local position = {x=tonumber(matches[1][3]), y=tonumber(matches[1][4]), z=tonumber(matches[1][5])}        
        if context.player:getPosition().z == position.z then
          local tile = g_map.getTile(position)
          if tile then
            local topThing = tile:getTopUseThing()
            if topThing then
              context.useWith(itemId, topThing)
              context.delay(500)
            end
          end
        end
      else
        context.error("Waypoints: invalid use of usewith function")
      end
    elseif command.command == "wait" and lastGotoSuccesful then
      if not waitTo or waitTo == 0 then
        waitTo = context.now + tonumber(command.text)
      end
      if context.now < waitTo then
        return
      end
      waitTo = 0
    elseif command.command == "say" and lastGotoSuccesful then
      context.say(command.text)
    elseif command.command == "npc" and lastGotoSuccesful then
      context.sayNpc(command.text)
    elseif command.command == "function" and lastGotoSuccesful then
      usedGotoLabel = false
      local status, result = pcall(function() 
        return assert(load("return " .. command.text, nil, nil, context))()(functions)
      end)
      if not status then
        context.error("Waypoints function execution error:\n" .. result)
        context.delay(2500)
      end
      if not result or usedGotoLabel then
        return
      end
    elseif command.command == "gotolabel" then
      if functions.gotoLabel(command.text) then
        return
      end
    end

      local nextIndex = 1 + commandIndex % #commands    
      local nextChild = ui.list:getChildByIndex(nextIndex)
      if nextChild then
        if nextIndex == 1 then
          onRoundComplete()
        end
        ui.list:focusChild(nextChild)
        commandExecutionNo = 0
      end
  end)
  
  return functions
end

