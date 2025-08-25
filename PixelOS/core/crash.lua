-- PixelOS Crash Screen (Blue Screen of Death)
-- A Windows-style crash screen for PixelOS

local PixelOS = _G.PixelOS or dofile("PixelOS/core/libraries/PixelOS.lua")
local PixelUI = _G.PixelUI or dofile("PixelOS/core/libraries/pixelui.lua")

local CrashScreen = {}

local function showCrashScreen(errorInfo)
    -- Initialize PixelUI if not already done
    if not PixelUI then
        error("PixelUI not available for crash screen")
    end
    PixelUI.init()
    
    local w, h = term.getSize()
    
    -- Create blue background container
    local crashContainer = PixelUI.container({
        x = 1, y = 1,
        width = w, height = h,
        background = colors.blue,
        visible = true
    })
    
    -- Sad face emoticon
    local sadFace = PixelUI.label({
        x = 3, y = 3,
        width = 4, height = 3,
        text = ":(",
        color = colors.white,
        background = colors.blue,
        align = "left"
    })
    crashContainer:addChild(sadFace)
    
    -- Main crash message
    local crashMessage = PixelUI.label({
        x = 3, y = 6,
        width = w - 4, height = 1,
        text = "Your PC ran into a problem and need to restart",
        color = colors.white,
        background = colors.blue,
        align = "left"
    })
    crashContainer:addChild(crashMessage)
    
    -- Restart button
    local restartButton = PixelUI.button({
        x = math.floor(w/2) - 12, y = h - 5,
        width = 12, height = 3,
        text = "Restart",
        background = colors.blue,
        color = colors.white,
        clickEffect = true,
        border = true,
        onClick = function()
            if PixelOS and PixelOS.restart then
                PixelOS.restart()
            else
                os.reboot()
            end
        end
    })
    crashContainer:addChild(restartButton)
    
    -- Exit PixelOS button
    local exitButton = PixelUI.button({
        x = math.floor(w/2) + 2, y = h - 5,
        width = 14, height = 3,
        text = "Exit PixelOS",
        border = true,
        background = colors.blue,
        clickEffect = true,
        color = colors.white,
        onClick = function()
            if PixelOS and PixelOS.shutdown then
                PixelOS.shutdown()
            else
                os.shutdown()
            end
        end
    })
    crashContainer:addChild(exitButton)
    
    -- Render screen and wait for button clicks
    PixelUI.render()
    
    -- Simple event loop for button handling
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        PixelUI.handleEvent(event, p1, p2, p3, p4, p5)
        PixelUI.render()
        
        if event == "key" then
            -- Allow ESC (key code 28) to exit
            if p1 == 28 then
                break
            end
        end
    end
end

-- Main crash function - can be called from anywhere
function CrashScreen.show(errorMessage, stopCode, additionalDetails)
    local errorInfo = {
        message = errorMessage or "An unexpected error occurred",
        stopCode = stopCode or "PIXEL_OS_EXCEPTION",
        details = additionalDetails,
        timestamp = os.date and os.date("%Y-%m-%d %H:%M:%S") or "Unknown time"
    }
    
    -- Log the crash if logging is available
    if PixelOS and PixelOS.log then
        PixelOS.log.error("CRASH: " .. errorInfo.message)
        PixelOS.log.error("Stop Code: " .. errorInfo.stopCode)
        if errorInfo.details then
            PixelOS.log.error("Details: " .. tostring(errorInfo.details))
        end
    end
    
    -- Show the crash screen
    local success, err = pcall(showCrashScreen, errorInfo)
    if not success then
        -- Fallback to simple text crash screen if PixelUI fails
        term.setBackgroundColor(colors.blue)
        term.clear()
        term.setTextColor(colors.white)
        term.setCursorPos(3, 3)
        term.write(":(")
        term.setCursorPos(3, 6)
        term.write("Your PC ran into a problem and need to restart")
        term.setCursorPos(3, 8)
        term.write("Error: " .. errorInfo.message)
        term.setCursorPos(3, 11)
        term.write("Press R to restart or Q to quit...")
        
        while true do
            local event, key = os.pullEvent("key")
            if key == 19 then -- R key
                os.reboot()
            elseif key == 16 then -- Q key
                os.shutdown()
            end
        end
    end
end

-- Function to be called when an unhandled error occurs
function CrashScreen.handleError(error, traceback)
    local stopCodes = {
        "KERNEL_DATA_INPAGE_ERROR",
        "SYSTEM_THREAD_EXCEPTION_NOT_HANDLED", 
        "MEMORY_MANAGEMENT",
        "IRQL_NOT_LESS_OR_EQUAL",
        "SYSTEM_SERVICE_EXCEPTION",
        "PIXEL_OS_EXCEPTION",
        "CRITICAL_PROCESS_DIED"
    }
    
    local randomStopCode = stopCodes[math.random(1, #stopCodes)]
    CrashScreen.show(tostring(error), randomStopCode, traceback)
end

-- Test function for demonstration
function CrashScreen.test()
    CrashScreen.show(
        "This is a test crash",
        "TEST_EXCEPTION", 
        "PixelOS/core/crash.lua:test_function"
    )
end

return CrashScreen