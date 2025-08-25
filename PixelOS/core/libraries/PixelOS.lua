-- PixelOS API

local PixelOS = {}

-- Import PixelUI if available
local PixelUI = nil
if fs.exists("PixelOS/core/libraries/pixelui.lua") then
    PixelUI = dofile("PixelOS/core/libraries/pixelui.lua")
elseif fs.exists("pixelui.lua") then
    PixelUI = dofile("pixelui.lua")
end

-- Core OS state
local osState = {
    version = "1.0.0",
    booted = false,
    currentUser = "user",
    processes = {},
    services = {},
    nextPID = 1,
    eventQueue = {},
    running = true,
    desktop = nil,
    taskbar = nil,
    windows = {},
    notifications = {},
    themes = {},
    currentTheme = "default"
}

-- =============================================================================
-- SYSTEM MANAGEMENT
-- =============================================================================

--- Initialize the PixelOS system
function PixelOS.init()
    if osState.booted then
        return false, "PixelOS already initialized"
    end
    
    -- Set up default directories
    PixelOS.fs.ensureDir("/PixelOS/apps")
    PixelOS.fs.ensureDir("/PixelOS/config")
    PixelOS.fs.ensureDir("/PixelOS/logs")
    PixelOS.fs.ensureDir("/PixelOS/temp")
    PixelOS.fs.ensureDir("/PixelOS/user")
    
    -- Load configuration
    PixelOS.config.load()
    
    -- Initialize UI if available
    if PixelUI then
        PixelUI.init()
        PixelOS.ui.init()
    end
    
    osState.booted = true
    PixelOS.log.info("PixelOS initialized successfully")
    return true
end

--- Get system information
function PixelOS.getSystemInfo()
    return {
        version = osState.version,
        computerID = os.getComputerID(),
        computerLabel = os.getComputerLabel() or "Unknown",
        uptime = os.clock(),
        totalMemory = math.huge, -- CC doesn't have memory limits
        processes = #osState.processes,
        ccVersion = _HOST or "Unknown"
    }
end

--- Shutdown the system
function PixelOS.shutdown()
    PixelOS.log.info("Shutting down PixelOS...")
    
    -- Stop all processes
    for _, process in pairs(osState.processes) do
        PixelOS.process.kill(process.pid)
    end
    
    -- Stop all services
    for name, _ in pairs(osState.services) do
        PixelOS.service.stop(name)
    end
    
    -- Save configuration
    PixelOS.config.save()
    
    osState.running = false
    os.shutdown()
end

--- Restart the system
function PixelOS.restart()
    PixelOS.log.info("Restarting PixelOS...")
    PixelOS.config.save()
    osState.running = false
    os.reboot()
end

--- Trigger a crash screen for testing
function PixelOS.crash(message, stopCode, details)
    local crashScreen = dofile("PixelOS/core/crash.lua")
    if crashScreen then
        crashScreen.show(message, stopCode, details)
    else
        error(message or "Manual crash triggered")
    end
end

-- =============================================================================
-- PROCESS MANAGEMENT
-- =============================================================================

PixelOS.process = {}

--- Start a new process
function PixelOS.process.start(path, args, options)
    args = args or {}
    options = options or {}
    
    if not fs.exists(path) then
        return nil, "File not found: " .. path
    end
    
    local pid = osState.nextPID
    osState.nextPID = osState.nextPID + 1
    
    local process = {
        pid = pid,
        path = path,
        args = args,
        environment = options.environment or {},
        workingDirectory = options.workingDirectory or fs.getDir(path),
        status = "running",
        startTime = os.clock(),
        parent = options.parent or 0,
        coroutine = nil,
        window = options.window
    }
    
    -- Create process environment
    local env = setmetatable({}, { __index = _G })
    for k, v in pairs(process.environment) do
        env[k] = v
    end
    
    -- Add PixelOS API to environment
    env.pixelos = PixelOS
    env.process = {
        pid = pid,
        args = args,
        exit = function(code) PixelOS.process.kill(pid, code) end
    }
    
    -- Load and create coroutine
    local func, err = loadfile(path, nil, env)
    if not func then
        return nil, "Failed to load: " .. err
    end
    
    process.coroutine = coroutine.create(function()
        return func(table.unpack(args))
    end)
    
    osState.processes[pid] = process
    PixelOS.log.info("Started process " .. pid .. ": " .. path)
    
    return pid
end

--- Kill a process
function PixelOS.process.kill(pid, exitCode)
    local process = osState.processes[pid]
    if not process then
        return false, "Process not found"
    end
    
    process.status = "terminated"
    process.exitCode = exitCode or 0
    process.endTime = os.clock()
    
    -- Clean up
    osState.processes[pid] = nil
    
    PixelOS.log.info("Terminated process " .. pid .. " with exit code " .. (exitCode or 0))
    return true
end

--- Get process information
function PixelOS.process.getInfo(pid)
    if pid then
        return osState.processes[pid]
    else
        return osState.processes
    end
end

--- Resume a process with an event
function PixelOS.process.resume(pid, event, ...)
    local process = osState.processes[pid]
    if not process or not process.coroutine then
        return false
    end
    
    if coroutine.status(process.coroutine) == "dead" then
        PixelOS.process.kill(pid)
        return false
    end
    
    local ok, result = coroutine.resume(process.coroutine, event, ...)
    if not ok then
        PixelOS.log.error("Process " .. pid .. " crashed: " .. result)
        PixelOS.process.kill(pid, -1)
        return false
    end
    
    if coroutine.status(process.coroutine) == "dead" then
        PixelOS.process.kill(pid, result)
    end
    
    return true
end

-- =============================================================================
-- SERVICE MANAGEMENT
-- =============================================================================

PixelOS.service = {}

--- Register a service
function PixelOS.service.register(name, serviceFunc, autoStart)
    if osState.services[name] then
        return false, "Service already exists"
    end
    
    osState.services[name] = {
        name = name,
        func = serviceFunc,
        running = false,
        pid = nil,
        autoStart = autoStart or false
    }
    
    if autoStart then
        return PixelOS.service.start(name)
    end
    
    return true
end

--- Start a service
function PixelOS.service.start(name)
    local service = osState.services[name]
    if not service then
        return false, "Service not found"
    end
    
    if service.running then
        return false, "Service already running"
    end
    
    local pid = PixelOS.process.start("", {}, {
        environment = { service = service }
    })
    
    if pid then
        service.pid = pid
        service.running = true
        osState.processes[pid].coroutine = coroutine.create(service.func)
        PixelOS.log.info("Started service: " .. name)
        return true
    end
    
    return false, "Failed to start service"
end

--- Stop a service
function PixelOS.service.stop(name)
    local service = osState.services[name]
    if not service then
        return false, "Service not found"
    end
    
    if service.pid then
        PixelOS.process.kill(service.pid)
    end
    
    service.running = false
    service.pid = nil
    PixelOS.log.info("Stopped service: " .. name)
    return true
end

--- Get service status
function PixelOS.service.status(name)
    if name then
        return osState.services[name]
    else
        return osState.services
    end
end

-- =============================================================================
-- FILE SYSTEM UTILITIES
-- =============================================================================

PixelOS.fs = {}

--- Ensure directory exists
function PixelOS.fs.ensureDir(path)
    if not fs.exists(path) then
        fs.makeDir(path)
        return true
    elseif not fs.isDir(path) then
        return false, "Path exists but is not a directory"
    end
    return true
end

--- Copy files with progress callback
function PixelOS.fs.copy(source, destination, progressCallback)
    if not fs.exists(source) then
        return false, "Source file not found"
    end
    
    if fs.isDir(source) then
        -- Copy directory recursively
        PixelOS.fs.ensureDir(destination)
        local files = fs.list(source)
        
        for i, file in ipairs(files) do
            local srcPath = fs.combine(source, file)
            local destPath = fs.combine(destination, file)
            
            if progressCallback then
                progressCallback(i, #files, file)
            end
            
            local success, err = PixelOS.fs.copy(srcPath, destPath, progressCallback)
            if not success then
                return false, err
            end
        end
        
        return true
    else
        -- Copy single file
        fs.copy(source, destination)
        return true
    end
end

--- Get file/directory size
function PixelOS.fs.getSize(path)
    if not fs.exists(path) then
        return 0
    end
    
    if fs.isDir(path) then
        local totalSize = 0
        local files = fs.list(path)
        
        for _, file in ipairs(files) do
            totalSize = totalSize + PixelOS.fs.getSize(fs.combine(path, file))
        end
        
        return totalSize
    else
        return fs.getSize(path)
    end
end

--- Get file type by extension
function PixelOS.fs.getFileType(path)
    local extension = path:match("%.([^%.]+)$")
    if not extension then
        return "unknown"
    end
    
    extension = extension:lower()
    
    local types = {
        lua = "script",
        txt = "text",
        nfp = "image",
        json = "data",
        conf = "config",
        log = "log",
        md = "markdown"
    }
    
    return types[extension] or "unknown"
end

-- =============================================================================
-- CONFIGURATION MANAGEMENT
-- =============================================================================

PixelOS.config = {}
local configData = {}

--- Load configuration from file
function PixelOS.config.load()
    local configPath = "/PixelOS/config/system.json"
    if fs.exists(configPath) then
        local file = fs.open(configPath, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            local success, data = pcall(textutils.unserializeJSON, content)
            if success then
                configData = data
            else
                PixelOS.log.warn("Failed to parse config file, using defaults")
            end
        end
    end
    
    -- Set defaults
    if not configData.theme then configData.theme = "default" end
    if not configData.autostart then configData.autostart = {} end
    if not configData.desktop then configData.desktop = {} end
end

--- Save configuration to file
function PixelOS.config.save()
    local configPath = "/PixelOS/config/system.json"
    PixelOS.fs.ensureDir("/PixelOS/config")
    
    local file = fs.open(configPath, "w")
    if file then
        file.write(textutils.serializeJSON(configData))
        file.close()
        return true
    end
    
    return false, "Failed to save configuration"
end

--- Get configuration value
function PixelOS.config.get(key, default)
    local value = configData
    for part in key:gmatch("[^%.]+") do
        value = value[part]
        if value == nil then
            return default
        end
    end
    return value
end

--- Set configuration value
function PixelOS.config.set(key, value)
    local parts = {}
    for part in key:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    
    local current = configData
    for i = 1, #parts - 1 do
        if not current[parts[i]] then
            current[parts[i]] = {}
        end
        current = current[parts[i]]
    end
    
    current[parts[#parts]] = value
end

-- =============================================================================
-- LOGGING SYSTEM
-- =============================================================================

PixelOS.log = {}

local logLevels = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

local currentLogLevel = logLevels.INFO

--- Set log level
function PixelOS.log.setLevel(level)
    if type(level) == "string" then
        currentLogLevel = logLevels[level:upper()] or logLevels.INFO
    else
        currentLogLevel = level
    end
end

--- Write log message
local function writeLog(level, message)
    if logLevels[level] < currentLogLevel then
        return
    end
    
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local logEntry = string.format("[%s] [%s] %s", timestamp, level, message)
    
    -- Write to console
    if term.isColor() then
        local colors = {
            DEBUG = colors.lightGray,
            INFO = colors.white,
            WARN = colors.yellow,
            ERROR = colors.red
        }
        term.setTextColor(colors[level] or colors.white)
    end
    print(logEntry)
    if term.isColor() then
        term.setTextColor(colors.white)
    end
    
    -- Write to log file
    local logPath = "/PixelOS/logs/system.log"
    PixelOS.fs.ensureDir("/PixelOS/logs")
    
    local file = fs.open(logPath, "a")
    if file then
        file.writeLine(logEntry)
        file.close()
    end
end

function PixelOS.log.debug(message) writeLog("DEBUG", message) end
function PixelOS.log.info(message) writeLog("INFO", message) end
function PixelOS.log.warn(message) writeLog("WARN", message) end
function PixelOS.log.error(message) writeLog("ERROR", message) end

-- =============================================================================
-- USER INTERFACE (when PixelUI is available)
-- =============================================================================

PixelOS.ui = {}

--- Initialize UI system
function PixelOS.ui.init()
    if not PixelUI then
        return false, "PixelUI not available"
    end    
    return true
end

--- Show notification
function PixelOS.ui.notify(title, message, type, duration)
    if not PixelUI then
        PixelOS.log.info("NOTIFICATION: " .. title .. " - " .. message)
        return
    end
    
    local notification = PixelUI.notificationToast({
        title = title,
        message = message,
        type = type or "info",
        duration = duration or 3000,
        closeable = true
    })
    
    notification:show()
    table.insert(osState.notifications, notification)
    
    return notification
end

-- =============================================================================
-- EVENT SYSTEM
-- =============================================================================

PixelOS.event = {}

local eventHandlers = {}

--- Register event handler
function PixelOS.event.on(eventName, handler)
    if not eventHandlers[eventName] then
        eventHandlers[eventName] = {}
    end
    table.insert(eventHandlers[eventName], handler)
    return #eventHandlers[eventName]
end

--- Unregister event handler
function PixelOS.event.off(eventName, handlerId)
    if eventHandlers[eventName] and eventHandlers[eventName][handlerId] then
        eventHandlers[eventName][handlerId] = nil
        return true
    end
    return false
end

--- Emit event
function PixelOS.event.emit(eventName, ...)
    if eventHandlers[eventName] then
        for _, handler in pairs(eventHandlers[eventName]) do
            if handler then
                local success, err = pcall(handler, ...)
                if not success then
                    PixelOS.log.error("Event handler error: " .. err)
                end
            end
        end
    end
end

--- Main event loop
function PixelOS.event.loop()
    while osState.running do
        local event = { os.pullEvent() }
        local eventName = event[1]
        
        -- Handle UI events if PixelUI is available
        if PixelUI then
            PixelUI.handleEvent(table.unpack(event))
        end
        
        -- Handle system events
        if eventName == "terminate" then
            PixelOS.shutdown()
            break
        end
        
        -- Resume all processes with this event
        for pid, _ in pairs(osState.processes) do
            PixelOS.process.resume(pid, table.unpack(event))
        end
        
        -- Emit to custom event handlers
        PixelOS.event.emit(eventName, table.unpack(event, 2))
        
        -- Render UI if available
        if PixelUI then
            PixelUI.render()
        end
    end
end

-- =============================================================================
-- APPLICATION MANAGEMENT
-- =============================================================================

PixelOS.app = {}

--- Launch an application
function PixelOS.app.launch(appPath, args, options)
    -- To be implemented
end

--- Install an application
function PixelOS.app.install(sourcePath, appName)
    if not appName then
        appName = fs.getName(sourcePath)
    end
    
    local appDir = "/PixelOS/apps/" .. appName
    local success, err = PixelOS.fs.copy(sourcePath, appDir)
    
    if success then
        PixelOS.log.info("Installed application: " .. appName)
        PixelOS.ui.notify("App Installed", appName .. " installed successfully", "success")
        return true
    else
        PixelOS.log.error("Failed to install " .. appName .. ": " .. err)
        PixelOS.ui.notify("Install Failed", "Failed to install " .. appName, "error")
        return false, err
    end
end

--- List installed applications
function PixelOS.app.list()
    local apps = {}
    local appsDir = "/PixelOS/apps"
    
    if fs.exists(appsDir) then
        for _, item in ipairs(fs.list(appsDir)) do
            local appPath = fs.combine(appsDir, item)
            if fs.isDir(appPath) then
                table.insert(apps, {
                    name = item,
                    path = appPath,
                    executable = fs.combine(appPath, "main.lua")
                })
            end
        end
    end
    
    return apps
end

-- =============================================================================
-- THEME SYSTEM
-- =============================================================================

PixelOS.theme = {}

--- Register a theme
function PixelOS.theme.register(name, themeData)
    osState.themes[name] = themeData
    PixelOS.log.info("Registered theme: " .. name)
end

--- Apply a theme
function PixelOS.theme.apply(name)
    local theme = osState.themes[name]
    if not theme then
        return false, "Theme not found"
    end
    
    osState.currentTheme = name
    PixelOS.config.set("theme", name)
    
    if PixelUI and theme.pixelui then
        PixelUI.setTheme(theme.pixelui)
    end
    
    PixelOS.log.info("Applied theme: " .. name)
    PixelOS.event.emit("themeChanged", name, theme)
    return true
end

--- Get current theme
function PixelOS.theme.getCurrent()
    return osState.currentTheme, osState.themes[osState.currentTheme]
end

-- Register default theme
PixelOS.theme.register("default", {
    name = "Default",
    colors = {
        primary = colors.blue,
        secondary = colors.lightBlue,
        success = colors.green,
        warning = colors.yellow,
        error = colors.red,
        background = colors.black,
        surface = colors.gray,
        text = colors.white
    },
    pixelui = {
        primary = colors.blue,
        secondary = colors.lightBlue,
        background = colors.black,
        surface = colors.gray,
        text = colors.white,
        border = colors.lightGray
    }
})

-- =============================================================================
-- UTILITY FUNCTIONS
-- =============================================================================

PixelOS.utils = {}

--- Format bytes to human readable string
function PixelOS.utils.formatBytes(bytes)
    local units = {"B", "KB", "MB", "GB"}
    local index = 1
    local size = bytes
    
    while size >= 1024 and index < #units do
        size = size / 1024
        index = index + 1
    end
    
    return string.format("%.1f %s", size, units[index])
end

--- Format time duration
function PixelOS.utils.formatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    
    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    else
        return string.format("%02d:%02d", minutes, secs)
    end
end

--- Generate UUID
function PixelOS.utils.uuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

--- Deep copy table
function PixelOS.utils.deepCopy(original)
    local copy = {}
    for key, value in pairs(original) do
        if type(value) == "table" then
            copy[key] = PixelOS.utils.deepCopy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

-- =============================================================================
-- INITIALIZATION
-- =============================================================================

-- Auto-initialize if not already done
if not osState.booted then
    local success, err = pcall(PixelOS.init)
    if not success then
        -- Load crash screen and show error
        local crashScreen = dofile("PixelOS/core/crash.lua")
        if crashScreen then
            crashScreen.handleError("Failed to initialize PixelOS: " .. tostring(err))
        else
            error("Failed to initialize PixelOS: " .. err)
        end
    end
end

-- Set up global error handler
local originalError = error
function error(message, level)
    local crashScreen = dofile("PixelOS/core/crash.lua")
    if crashScreen then
        crashScreen.handleError(message, debug.traceback())
    else
        originalError(message, level)
    end
end

return PixelOS
