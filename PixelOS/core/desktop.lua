-- PixelOS Desktop (Minimal Taskbar Version)

local PixelOS = dofile("PixelOS/core/libraries/PixelOS.lua")
local PixelUI = dofile("PixelOS/core/libraries/pixelui.lua")

local Desktop = {}

local state = {
	taskbar = nil,
	startButton = nil,
	clockLabel = nil,
	startMenu = nil,
	clockMenu = nil,
	useRealTime = PixelOS.config.get("desktop.useRealTimeClock", true),
	clockTimer = nil,
	clockMenuOpen = false,
	startMenuOpen = false
}

-- In‑game clock (os.time returns fractional hours 0..24)
local function getInGameClock()
	local t = os.time()
	local hour = math.floor(t)
	local minute = math.floor((t - hour) * 60)
	return string.format("%02d:%02d", hour, minute)
end

local function updateClock()
	if not state.clockLabel then return end
	if state.useRealTime then
		state.clockLabel.text = os.date("%H:%M")
	else
		state.clockLabel.text = getInGameClock()
	end
end

local function showConfirmation(title, message, onYes)
	if PixelUI.msgBox then
		local box = PixelUI.msgBox({
			title = title,
			message = message,
			buttons = {"Yes", "No"},
            border = true,
			onButton = function(_, index, text)
				if text == "Yes" then onYes() end
			end
		})
		box.visible = true
	else
		-- Fallback: immediate action (no dialog widget available)
		onYes()
	end
end

local function buildStartMenu()
	if state.startMenu then return end
	local w, h = term.getSize()
	-- Create a nice container with proper styling
	state.startMenu = PixelUI.container({
		x = 2,
        border = true,
        borderColor = colors.blue,
		y = h - 6, -- leave more room above taskbar
		width = 16,
		height = 5, -- room for title + 2 buttons + padding
		background = colors.lightGray,
		visible = false,
		layout = "absolute"
	})
	
	-- Menu title/header
	local titleLabel = PixelUI.label({
		x = 1, y = 1, width = 16, height = 1,
		text = "  Start Menu  ",
		background = colors.blue, color = colors.white,
		align = "center"
	})
	state.startMenu:addChild(titleLabel)
	
	-- Restart button
	local restartBtn = PixelUI.button({
		x = 2, y = 3, width = 12, height = 1,
		text = "Restart",
		background = colors.gray, color = colors.white,
		onClick = function()
			state.startMenuOpen = false
			state.startMenu.visible = false
			showConfirmation("Restart", "Restart PixelOS?", function() PixelOS.restart() end)
		end
	})
	state.startMenu:addChild(restartBtn)
	
	-- Shutdown button
	local shutdownBtn = PixelUI.button({
		x = 2, y = 4, width = 12, height = 1,
		text = "Shutdown",
		background = colors.gray, color = colors.white,
		onClick = function()
			state.startMenuOpen = false
			state.startMenu.visible = false
			showConfirmation("Shutdown", "Shutdown PixelOS?", function() PixelOS.shutdown() end)
		end
	})
	state.startMenu:addChild(shutdownBtn)
end

local function buildClockMenu()
	if state.clockMenu then return end
	local w, h = term.getSize()
	state.clockMenu = PixelUI.container({
		x = w - 22,
		y = h - 5,
        border = true,
		width = 22,
		height = 4, -- room for title + toggle button + padding
		background = colors.lightGray,
		visible = false,
		layout = "absolute"
	})
	
	-- Menu title/header
	local titleLabel = PixelUI.label({
		x = 1, y = 1, width = 22, height = 1,
		text = "   Clock Settings   ",
		background = colors.blue, color = colors.white,
		align = "center"
	})
	state.clockMenu:addChild(titleLabel)
	
	-- Button will be added in refreshClockMenu
end

local function refreshClockMenu()
	if not state.clockMenu then return end
	if state.clockMenu.children and #state.clockMenu.children > 1 then
		for i = #state.clockMenu.children, 2, -1 do
			local child = state.clockMenu.children[i]
			state.clockMenu:removeChild(child)
		end
	end
	local label = state.useRealTime and "On" or "Off"
	local toggleBtn = PixelUI.button({
		x = 2, y = 3, width = 18, height = 1,
		text = "Use IRL Time: " .. label,
		background = colors.gray, color = colors.white,
		onClick = function()
			state.useRealTime = not state.useRealTime
			PixelOS.config.set("desktop.useRealTimeClock", state.useRealTime)
			refreshClockMenu()
			updateClock()
		end
	})
	state.clockMenu:addChild(toggleBtn)
end

local function toggleStartMenu()
	if not state.startMenu then buildStartMenu() end
	state.startMenuOpen = not state.startMenuOpen
	state.startMenu.visible = state.startMenuOpen
	if state.startMenuOpen and state.clockMenuOpen then
		state.clockMenuOpen = false
		state.clockMenu.visible = false
	end
end

local function toggleClockMenu()
	if not state.clockMenu then buildClockMenu() end
	
	-- Only reposition and refresh when opening the menu
	if not state.clockMenuOpen then
		local w, h = term.getSize()
		-- Position the menu properly on the right side
		state.clockMenu.x = w - state.clockMenu.width + 1
		state.clockMenu.y = h - state.clockMenu.height
		refreshClockMenu()
	end
	
	state.clockMenuOpen = not state.clockMenuOpen
	state.clockMenu.visible = state.clockMenuOpen
	if state.clockMenuOpen and state.startMenuOpen then
		state.startMenuOpen = false
		state.startMenu.visible = false
	end
end

local function initTaskbar()
	PixelOS.ui.init() -- ensure UI root
	local w, h = term.getSize()
	state.taskbar = PixelUI.container({
		x = 1, y = h, width = w, height = 1,
		background = colors.gray,
		layout = "absolute"
	})
	state.startButton = PixelUI.button({
		x = 1, y = 1, width = 6, height = 1,
		text = "Start", background = colors.lightGray, color = colors.black, clickEffect = true,
		onClick = toggleStartMenu
	})
	state.taskbar:addChild(state.startButton)
	state.clockLabel = PixelUI.label({
		x = w - 7, y = 1, width = 7, height = 1,
		text = "--:--", background = colors.gray, color = colors.white,
		align = "center",
		onClick = toggleClockMenu
	})
	state.taskbar:addChild(state.clockLabel)
	buildStartMenu()
	buildClockMenu()
	updateClock()
end

local function scheduleClock()
	-- Use a simple timer that repeats every second
	state.clockTimer = os.startTimer(1)
end

local function handleTimer(id)
	if id == state.clockTimer then
		updateClock()
		scheduleClock() -- restart the timer
	end
end

local function registerEvents()
	-- Close menus when clicking outside them
	PixelOS.event.on("mouse_click", function(_, x, y)
		-- Ensure menus exist before hit-testing
		if not state.startMenu then buildStartMenu() end
		if not state.clockMenu then buildClockMenu() end
		if state.startMenuOpen then
			local m = state.startMenu
			if not (x >= m.x and x < m.x + m.width and y >= m.y and y < m.y + m.height) and
			   not (x >= state.startButton.x and x < state.startButton.x + state.startButton.width and y == state.taskbar.y) then
				state.startMenuOpen = false
				m.visible = false
			end
		end
		if state.clockMenuOpen then
			local m = state.clockMenu
			if not (x >= m.x and x < m.x + m.width and y >= m.y and y < m.y + m.height) and
			   not (x >= state.clockLabel.x and x < state.clockLabel.x + state.clockLabel.width and y == state.taskbar.y) then
				state.clockMenuOpen = false
				m.visible = false
			end
		end
	end)
	PixelOS.event.on("timer", handleTimer)
end

function Desktop.run()
	PixelOS.log.info("Starting minimal PixelOS desktop")
	initTaskbar()
	registerEvents()
	scheduleClock()
	-- Force an immediate initial render so the user doesn't see a blank screen
	if PixelUI and PixelUI.render then PixelUI.render() end
	
	-- Use PixelUI's event loop instead of PixelOS.event.loop()
	-- This ensures proper rendering and event handling
	if PixelUI and PixelUI.run then
		PixelUI.run({
			onEvent = function(event, p1, p2, p3, p4, p5)
				-- Handle system events
				if event == "terminate" then
					PixelOS.shutdown()
				end
				-- Emit to PixelOS event handlers
				PixelOS.event.emit(event, p1, p2, p3, p4, p5)
			end,
			onKey = function(key)
				-- Handle key events if needed - just return true to continue
				return true -- continue running
			end
		})
	else
		-- Fallback to PixelOS event loop
		PixelOS.event.loop()
	end
end

return Desktop