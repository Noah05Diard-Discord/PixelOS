local req = http.get("https://github.com/Shlomo1412/PixelUI/raw/refs/heads/main/pixelui.lua")
local code = req.readAll()
req.close()
local func,err = load(code,"=pixelui")
if not func then error(err) end
local succ,err = pcall(func)
if not succ then error(err) end
local PixelUI = err

PixelUI.init()

local main = PixelUI.container({
    width = 51,
    height = 19
})

local num = 1

local object = PixelUI.button({
    x = 20,
    y = 15,
    text = "Install",
    onClick = function (self,_,_,btn)
        num = num+1
        self.text = tostring(num)
    end
})

main:addChild(object)

local label = PixelUI.label({
    text = "PixelOS Installer",
    x=15,
    y=2
})

main:addChild(label)

local selection = PixelUI.listView({
    x=13,
    y=4,
    items = {
        "Normal",
        "Organization",
        "Server"
    },
    width = 13,
    height = 3
})

main:addChild(selection)

PixelUI.run()