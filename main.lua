-- testing

hook_event(HOOK_ON_MODS_LOADED, async(function()
    async.wait(5)
    log_to_console("Mods loaded 5 seconds ago")
end))

-- these should both error
local e
_, e = pcall(async.spawn, "aaa")
log_to_console(tostring(e))
_, e = pcall(async.defer, "aaa")
log_to_console(tostring(e))

local signal = async.signal()

local a = signal:connect(function()
    log_to_console("1")
end)
local b = signal:connect(function()
    log_to_console("2")
end)
local c = signal:connect(function()
    log_to_console("3")
    signal:wait()
    log_to_console("3 again")
end)

signal:fire()

b:disconnect()

signal:fire()

a:disconnect()
c:disconnect()

signal:fire()
