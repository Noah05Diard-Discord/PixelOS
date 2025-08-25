-- PixelOS Desktop (Minimal Taskbar Version)
-- Features implemented per request:
-- 1. Taskbar only.
-- 2. Start button on left. Left-click -> menu with Restart / Shutdown (each asks for confirmation).
-- 3. Clock on right. Left-click -> menu with toggle "Use IRL Time" (switch between real time and in‑game time).

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
	clockTimer = nil
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
	-- Simple container based menu (auto-added to root by PixelUI.container)
	state.startMenu = PixelUI.container({
		x = 1,
		y = h - 4, -- leave room above taskbar
		width = 14,
		height = 3, -- 2 buttons + background row
		background = colors.black,
		visible = false,
		layout = "absolute"
	})
	-- Restart button
	local restartBtn = PixelUI.button({
		x = 1, y = 1, width = 14, height = 1,
		text = "Restart",
		background = colors.gray, color = colors.white,
		onClick = function()
			showConfirmation("Restart", "Restart PixelOS?", function() PixelOS.restart() end)
		end
	})
	state.startMenu:addChild(restartBtn)
	-- Shutdown button
	local shutdownBtn = PixelUI.button({
		x = 1, y = 2, width = 14, height = 1,
		text = "Shutdown",
		background = colors.gray, color = colors.white,
		onClick = function()
			showConfirmation("Shutdown", "Shutdown PixelOS?", function() PixelOS.shutdown() end)
		end
	})
	state.startMenu:addChild(shutdownBtn)
end

local function buildClockMenu()
	if state.clockMenu then return end
	local w, h = term.getSize()
	state.clockMenu = PixelUI.container({
		x = w - 18,
		y = h - 3,
		width = 18,
		height = 2,
		background = colors.black,
		visible = false,
		layout = "absolute"
	})
	-- Button added in refreshClockMenu
end

local function refreshClockMenu()
	if not state.clockMenu then return end
	-- Remove existing children (simple approach)
	if state.clockMenu.children then
		for i = #state.clockMenu.children, 1, -1 do
			local child = state.clockMenu.children[i]
			state.clockMenu:removeChild(child)
		end
	end
	local label = state.useRealTime and "On" or "Off"
	local toggleBtn = PixelUI.button({
		x = 1, y = 1, width = 18, height = 1,
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
	state.startMenu.visible = not state.startMenu.visible
	if state.startMenu.visible and state.clockMenu then state.clockMenu.visible = false end
end

local function toggleClockMenu()
	if not state.clockMenu then buildClockMenu() end
	local w, h = term.getSize()
	state.clockMenu.x = w - state.clockMenu.width + 1
	state.clockMenu.y = h - 2 -- just above taskbar line
	refreshClockMenu()
	state.clockMenu.visible = not state.clockMenu.visible
	if state.clockMenu.visible and state.startMenu then state.startMenu.visible = false end
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
		text = "Start", background = colors.lightGray, color = colors.black,
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
		if state.startMenu and state.startMenu.visible then
			local m = state.startMenu
			if not (x >= m.x and x < m.x + m.width and y >= m.y and y < m.y + m.height) and
			   not (x >= state.startButton.x and x < state.startButton.x + state.startButton.width and y == state.taskbar.y) then
				m.visible = false
			end
		end
		if state.clockMenu and state.clockMenu.visible then
			local m = state.clockMenu
			if not (x >= m.x and x < m.x + m.width and y >= m.y and y < m.y + m.height) and
			   not (x >= state.clockLabel.x and x < state.clockLabel.x + state.clockLabel.width and y == state.taskbar.y) then
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