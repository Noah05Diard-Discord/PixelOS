-- PixelOS Crash Screen (Blue Screen of Death)

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
    
    -- Show error details if available
    local currentY = 8
    local lineHeight = 1
    local maxWidth = w - 6 -- Leave some margin
    
    if errorInfo then
        -- Error message (multi-line if needed)
        local errorText = "Error: " .. (errorInfo.message or "Unknown error")
        local errorLines = {}
        
        -- Split long error message into multiple lines
        while #errorText > 0 do
            local line
            if #errorText > maxWidth then
                -- Find a good break point (space) if possible
                local breakPoint = maxWidth
                local lastSpace = string.find(string.reverse(string.sub(errorText, 1, maxWidth)), " ")
                if lastSpace and lastSpace < 20 then -- Don't break too close to the end
                    breakPoint = maxWidth - lastSpace + 1
                end
                line = string.sub(errorText, 1, breakPoint)
                errorText = string.sub(errorText, breakPoint + 1)
            else
                line = errorText
                errorText = ""
            end
            table.insert(errorLines, line)
        end
        
        -- Add error message labels
        for i, line in ipairs(errorLines) do
            local errorLabel = PixelUI.label({
                x = 3, y = currentY,
                width = maxWidth, height = lineHeight,
                text = line,
                color = colors.white,
                background = colors.blue,
                align = "left"
            })
            crashContainer:addChild(errorLabel)
            currentY = currentY + lineHeight
        end
        
        currentY = currentY + 1 -- Add spacing
        
        -- Stop code
        if errorInfo.stopCode then
            local stopCodeLabel = PixelUI.label({
                x = 3, y = currentY,
                width = maxWidth, height = lineHeight,
                text = "Stop code: " .. errorInfo.stopCode,
                color = colors.lightGray,
                background = colors.blue,
                align = "left"
            })
            crashContainer:addChild(stopCodeLabel)
            currentY = currentY + lineHeight + 1
        end
        
        -- Additional details (multi-line if needed)
        if errorInfo.details then
            local detailsText = "Details: " .. tostring(errorInfo.details)
            local detailLines = {}
            
            -- Split long details into multiple lines
            while #detailsText > 0 do
                local line
                if #detailsText > maxWidth then
                    local breakPoint = maxWidth
                    local lastSpace = string.find(string.reverse(string.sub(detailsText, 1, maxWidth)), " ")
                    if lastSpace and lastSpace < 20 then
                        breakPoint = maxWidth - lastSpace + 1
                    end
                    line = string.sub(detailsText, 1, breakPoint)
                    detailsText = string.sub(detailsText, breakPoint + 1)
                else
                    line = detailsText
                    detailsText = ""
                end
                table.insert(detailLines, line)
            end
            
            -- Add detail labels (limit to 5 lines max to save space)
            for i, line in ipairs(detailLines) do
                if i > 5 then break end
                local detailsLabel = PixelUI.label({
                    x = 3, y = currentY,
                    width = maxWidth, height = lineHeight,
                    text = line,
                    color = colors.lightGray,
                    background = colors.blue,
                    align = "left"
                })
                crashContainer:addChild(detailsLabel)
                currentY = currentY + lineHeight
            end
            currentY = currentY + 1
        end
        
        -- Timestamp
        if errorInfo.timestamp then
            local timeLabel = PixelUI.label({
                x = 3, y = currentY,
                width = maxWidth, height = lineHeight,
                text = "Time: " .. errorInfo.timestamp,
                color = colors.lightGray,
                background = colors.blue,
                align = "left"
            })
            crashContainer:addChild(timeLabel)
            currentY = currentY + lineHeight + 2
        end
    end
    
    -- Calculate button position (ensure they're at least 5 lines from bottom)
    local buttonY = math.max(currentY + 2, h - 5)
    
    -- Add instruction label
    local instructionLabel = PixelUI.label({
        x = 3, y = buttonY - 2,
        width = w - 6, height = 1,
        text = "Press any key to restart...",
        color = colors.lightGray,
        background = colors.blue,
        align = "center"
    })
    crashContainer:addChild(instructionLabel)
    
    -- Restart button (kept for mouse users)
    local restartButton = PixelUI.button({
        x = math.floor(w/2) - 6, y = buttonY,
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
    
    -- Render screen and wait for button clicks
    PixelUI.render()
    
    -- Simple event loop for button handling
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()
        PixelUI.handleEvent(event, p1, p2, p3, p4, p5)
        PixelUI.render()
        
        if event == "key" then
            -- Any key press restarts the system
            if PixelOS and PixelOS.restart then
                PixelOS.restart()
            else
                os.reboot()
            end
            break
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
        
        -- Multi-line error display for fallback
        local currentLine = 8
        local maxLineWidth = 40
        
        -- Error message
        local errorText = "Error: " .. errorInfo.message
        while #errorText > 0 do
            local line
            if #errorText > maxLineWidth then
                line = string.sub(errorText, 1, maxLineWidth)
                errorText = string.sub(errorText, maxLineWidth + 1)
            else
                line = errorText
                errorText = ""
            end
            term.setCursorPos(3, currentLine)
            term.write(line)
            currentLine = currentLine + 1
        end
        
        -- Stop code
        if errorInfo.stopCode then
            currentLine = currentLine + 1
            term.setCursorPos(3, currentLine)
            term.write("Stop code: " .. errorInfo.stopCode)
            currentLine = currentLine + 1
        end
        
        -- Details (multi-line with limit)
        if errorInfo.details then
            local detailsText = "Details: " .. tostring(errorInfo.details)
            local lineCount = 0
            while #detailsText > 0 and lineCount < 3 do -- Limit to 3 lines
                local line
                if #detailsText > maxLineWidth then
                    line = string.sub(detailsText, 1, maxLineWidth)
                    detailsText = string.sub(detailsText, maxLineWidth + 1)
                else
                    line = detailsText
                    detailsText = ""
                end
                currentLine = currentLine + 1
                term.setCursorPos(3, currentLine)
                term.write(line)
                lineCount = lineCount + 1
            end
            currentLine = currentLine + 1
        end
        
        -- Instructions
        term.setCursorPos(3, currentLine + 1)
        term.write("Press any key to restart...")
        
        while true do
            local event, key = os.pullEvent("key")
            -- Any key press restarts the system
            os.reboot()
            break
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