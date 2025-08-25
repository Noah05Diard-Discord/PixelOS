local req = http.get("https://github.com/Shlomo1412/PixelUI/raw/refs/heads/main/pixelui.lua")
local code = req.readAll()
req.close()
local func,err = load(code,"=pixelui")
if not func then error(err) end
local succ,err = pcall(func)
if not succ then error(err) end
local pixelUI = err
local