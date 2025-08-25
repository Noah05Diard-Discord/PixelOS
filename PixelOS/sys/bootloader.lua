-- PixelOS Bootloader

local function centerWrite(y, text, txtColor, bgColor)
	local w, _ = term.getSize()
	if bgColor then term.setBackgroundColor(bgColor) end
	if txtColor then term.setTextColor(txtColor) end
	local x = math.floor((w - #text) / 2) + 1
	term.setCursorPos(x, y)
	term.write(text)
end

local function drawLogo()
	local path = "PixelOS/logo.nfp"
	local w, h = term.getSize()
	local logoHeight = 8
	if fs.exists(path) then
		local ok, img = pcall(paintutils.loadImage, path)
		if ok and img then
			-- Determine image dimensions
			local ih = #img
			local iw = 0
			for _, row in ipairs(img) do iw = math.max(iw, #row) end
			local startX = math.max(1, math.floor((w - iw) / 2) + 1)
			local startY = math.max(1, math.floor((h - ih) / 2) - 3)
			paintutils.drawImage(img, startX, startY)
			logoHeight = ih
			return startY + logoHeight
		end
	end
	-- Fallback ASCII logo
	local ascii = {
		" ____  _          _   ____  _____ ",
		"|  _ \\(_)        | | / __ \\|  __ \\",
		"| |_) |_ __  __ _| | | |  | | |  | |",
		"|  __/| |\\ \\/ /\\ \\/ | |  | | |  | |",
		"| |   | | >  <  >  <\\ \\__| | |_| |",
		"|_|   |_|/_/\\_\\/_/\\_\\\\____/|_____/,",
		"           Powered by PixelUI"
	}
	local startY = math.floor((h - #ascii) / 2) - 2
	for i, line in ipairs(ascii) do centerWrite(startY + i - 1, line, colors.cyan, colors.black) end
	return startY + #ascii
end

local function drawBar(progress, total, y, label)
	local w = select(1, term.getSize())
	local barW = math.max(10, w - 10)
	local filled = math.floor((progress / total) * barW)
	term.setCursorPos(math.floor((w - barW) / 2) + 1, y)
	term.setBackgroundColor(colors.gray)
	term.write(string.rep(" ", barW))
	term.setCursorPos(math.floor((w - barW) / 2) + 1, y)
	term.setBackgroundColor(colors.green)
	term.write(string.rep(" ", filled))
	term.setBackgroundColor(colors.black)
	if label then centerWrite(y + 1, label, colors.lightGray, colors.black) end
end

local function errorScreen(stage, err)
	-- Try to load and show the crash screen first
	local success, crashScreen = pcall(dofile, "PixelOS/core/crash.lua")
	if success and crashScreen then
		crashScreen.show(
			"Boot failure in stage: " .. (stage or "unknown"),
			"BOOT_FAILURE",
			tostring(err)
		)
		return
	end
	
	-- Fallback to simple error screen
	term.setBackgroundColor(colors.black)
	term.clear()
	centerWrite(3, "PixelOS Boot Error", colors.red)
	centerWrite(5, "Stage: " .. (stage or "unknown"), colors.red)
	local w, h = term.getSize()
	term.setTextColor(colors.white)
	local wrap = {}
	local msg = tostring(err)
	while #msg > w - 4 do
		table.insert(wrap, msg:sub(1, w - 4))
		msg = msg:sub(w - 3)
	end
	table.insert(wrap, msg)
	for i, line in ipairs(wrap) do
		term.setCursorPos(3, 7 + i)
		term.write(line)
	end
	centerWrite(h - 2, "Press any key to reboot", colors.yellow)
	os.pullEvent("key")
	os.reboot()
end

local stages = {
	{ name = "Load PixelUI", fn = function(ctx)
			ctx.PixelUI = dofile("PixelOS/core/libraries/pixelui.lua")
			_G.PixelUI = ctx.PixelUI -- expose globally to prevent duplicate loads
		end },
	{ name = "Load PixelOS API", fn = function(ctx)
			ctx.PixelOS = dofile("PixelOS/core/libraries/PixelOS.lua")
			_G.PixelOS = ctx.PixelOS
		end },
	{ name = "Init UI", fn = function(ctx)
			if ctx.PixelOS and ctx.PixelOS.ui and ctx.PixelOS.ui.init then ctx.PixelOS.ui.init() end
		end },
	{ name = "Load Desktop", fn = function(ctx)
			ctx.Desktop = dofile("PixelOS/core/desktop.lua")
		end },
	{ name = "Finalize", fn = function() end }
}

local function run()
	term.setBackgroundColor(colors.black)
	term.clear()
	term.setCursorPos(1,1)
	local barBaseY = drawLogo() + 2
	local ctx = {}
	for i, stage in ipairs(stages) do
		local ok, err = pcall(stage.fn, ctx)
		if not ok then
			return errorScreen(stage.name, err)
		end
		drawBar(i, #stages, barBaseY, stage.name)
		os.sleep(0.05) -- brief visual delay
	end
	-- Transition to desktop
	term.setBackgroundColor(colors.black)
	term.clear()
	if ctx.Desktop and ctx.Desktop.run then
		ctx.Desktop.run()
	else
		errorScreen("Desktop", "Desktop module missing run()")
	end
end

-- Execute bootloader
local ok, err = pcall(run)
if not ok then
	errorScreen("Bootloader", err)
end