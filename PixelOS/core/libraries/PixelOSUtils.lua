local lib = {}

function lib.rf(f)
    if fs.exists(f) then
        return fs.open(f,"r").readAll()
    else
        error(f.." not found on HDD.")
    end
end

function lib.wf(f,d)
    local h = fs.open(f,"w")
    h.write(d)
    h.close()
end

function lib.clear(x,y,c)
    x = x or 1
    y = y or 1
    c = c or colors.black
    term.setBackgroundColor(c)
    term.clear()
    term.setCursorPos(x,y)
end

return lib