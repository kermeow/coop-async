--[[

    async.lua v1

    Over-complicated coroutine wrapper for smlua

    The MIT License (MIT)

    Copyright (c) 2025, kermeet.

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

--]]

---@class AsyncConnection
---@field disconnect fun(self: AsyncConnection): nil Disconnects from the signal.
---@field enable fun(self: AsyncConnection): nil Disables the connection.
---@field disable fun(self: AsyncConnection): nil Enables the connection.

---@class AsyncSignal
---@field fire fun(self: AsyncSignal, ...): nil Fires the signal, triggering all its connections.
---@field connect fun(self: AsyncSignal, fn: function): AsyncConnection Connects to the signal.
---@field once fun(self: AsyncSignal, fn: function): AsyncConnection Connects to the signal for one event.
---@field wait fun(self: AsyncSignal): any Waits for the next event.

local select = select
local error = error
local function assert(v, msg, ...)
    if v then return end
    local args = select('#', ...)
    local message = (args > 0 and string.format(msg, ...)) or msg
    error(message, 2)
end
local co_create, co_resume, co_running, co_yield = coroutine.create, coroutine.resume, coroutine.running,
    coroutine.yield
local tbl_insert, tbl_remove, tbl_unpack = table.insert, table.remove, table.unpack
local tonumber, type = tonumber, type
local function readonly_error()
    error("attempt to update a read-only table", 2)
end

local function assert_yieldable()
    local thread, main = co_running()
    assert(not main, "async: Blocking functions can't be run on the main coroutine.")
    return thread
end

local thread_pool = setmetatable({}, { __mode = "kv" })
local get_thread
do
    local function tuple_call(self, fn, ...)
        fn(...)
        tbl_insert(thread_pool, self)
    end

    local function thread_func()
        local thread = co_running()
        while true do
            tuple_call(thread, co_yield())
        end
    end

    get_thread = function()
        local threads, thread = #thread_pool, nil
        if threads == 0 then
            thread = co_create(thread_func)
            co_resume(thread)
        else
            thread = tbl_remove(thread_pool, threads)
        end
        return thread
    end
end

---Runs the provided function in a coroutine immediately.
---@param fn function | thread
---@vararg any
local function async_spawn(fn, ...)
    local fn_type = type(fn)
    local thread
    if fn_type == "function" then
        thread = get_thread()
        co_resume(thread, fn, ...)
        return
    elseif fn_type == "thread" then
        co_resume(fn, ...)
        return
    end
    assert(false, 'async: Attempt to spawn invalid value (expected "function" or "thread", got "%s")', fn_type)
end

local deferred_calls = {}
---Runs the provided function in a coroutine on the next frame.
---@param fn function | thread
---@vararg any
local function async_defer(fn, ...)
    local fn_type = type(fn)
    local thread
    if fn_type == "function" then
        thread = get_thread()
        tbl_insert(deferred_calls, { thread, fn, ... })
        return
    elseif fn_type == "thread" then
        tbl_insert(deferred_calls, { fn, ... })
        return
    end
    assert(false, 'async: Attempt to defer invalid value (expected "function" or "thread", got "%s")', fn_type)
end

local update_time = clock_elapsed_f64()

local waiting_calls = {}
---Waits `t` seconds.
---Can only be run within coroutines.
---@param t number
local function async_wait(t)
    local thread = assert_yieldable()
    tbl_insert(waiting_calls, { thread, update_time, tonumber(t) })
    return co_yield()
end

do
    local clock_elapsed_f64 = clock_elapsed_f64
    local next = next

    local function run_deferred()
        for i, call in next, deferred_calls do
            co_resume(call[1], tbl_unpack(call, 2))
        end
        deferred_calls = {}
    end

    local function run_timers()
        local i = 0
        while (i < #waiting_calls) do
            i = i + 1

            local call = waiting_calls[i]

            local t_diff = update_time - call[2]
            if t_diff >= call[3] then
                tbl_remove(waiting_calls, i)
                i = i - 1

                co_resume(call[1], t_diff)
            end
        end
    end

    local function update()
        update_time = clock_elapsed_f64()

        run_deferred()
        run_timers()
    end

    hook_event(HOOK_UPDATE, update)
end

local async_signal
do
    local Connection = {}
    local connection_proxy = setmetatable({}, { __mode = "k" })
    local connection_mt = {
        __index = Connection,
        __newindex = readonly_error,
        __metatable = "connection metatable locked"
    }

    function Connection.enable(self)
        local proxy = connection_proxy[self]
        assert(proxy, 'connection: Attempt to enable invalid value (expected "Connection", got "%s")', type(self))
        proxy.enabled = true
    end

    function Connection.disable(self)
        local proxy = connection_proxy[self]
        assert(proxy, 'connection: Attempt to disable invalid value (expected "Connection", got "%s")', type(self))
        proxy.enabled = false
    end

    function Connection.disconnect(self)
        local proxy = connection_proxy[self]
        assert(proxy, 'connection: Attempt to disconnect invalid value (expected "Connection", got "%s")', type(self))
        if not proxy.connected then return end
        proxy.connected = false

        local signal = proxy.signal
        if signal.connectionBack == self then
            signal.connectionBack = proxy.prev
        end
        if signal.connectionFront == self then
            signal.connectionFront = proxy.next
        end

        local next = proxy.next
        if next then
            local next_proxy = connection_proxy[next]
            next_proxy.prev = proxy.prev
        end
        local prev = proxy.prev
        if prev then
            local prev_proxy = connection_proxy[prev]
            prev_proxy.next = proxy.next
        end
    end

    local function connection(signal, fn)
        local self, proxy = {}, {
            connected = true,
            enabled = true,
            signal = signal, -- actually the internal signal table
            fn = fn,
            prev = false,
            next = false
        }
        connection_proxy[self] = proxy
        if not signal.connectionFront then
            signal.connectionFront = self
        end
        if signal.connectionBack then
            connection_proxy[signal.connectionBack].next = self
            proxy.prev = signal.connectionBack
        end
        signal.connectionBack = self
        return setmetatable(self, connection_mt)
    end

    local Signal = {}
    local signal_proxy = setmetatable({}, { __mode = "k" })
    local signal_mt = {
        __index = Signal,
        __newindex = readonly_error,
        __metatable = "signal metatable locked",
    }

    ---@return AsyncConnection
    function Signal.connect(self, fn)
        local proxy = signal_proxy[self]
        assert(proxy, 'signal: Attempt to connect to invalid value (expected "Signal", got "%s")', type(self))
        local fn_type = type(fn)
        assert(fn_type == "function", 'signal: Attempt to connect invalid value (expected "function", got "%s")', fn_type)
        local conn = connection(proxy, fn)
        return conn
    end

    ---@return AsyncConnection
    function Signal.once(self, fn)
        local conn
        conn = self:connect(function(...)
            conn:disconnect()
            fn(...)
        end)
        return conn
    end

    ---@return any
    function Signal.wait(self)
        local thread = assert_yieldable()
        local conn
        conn = self:connect(function(...)
            conn:disconnect()
            co_resume(thread, ...)
        end)
        return co_yield()
    end

    ---@return nil
    function Signal.fire(self, ...)
        local proxy = signal_proxy[self]
        assert(proxy, 'signal: Attempt to fire invalid value (expected "Signal", got "%s")', type(self))
        local item = proxy.connectionFront
        while item do
            local item_proxy = connection_proxy[item]
            if item_proxy.connected and item_proxy.enabled then
                local thread = get_thread()
                co_resume(thread, item_proxy.fn, ...)
            end
            item = item_proxy.next
        end
    end

    signal_mt.__call = Signal.fire

    ---Creates an `AsyncSignal`.
    ---@return AsyncSignal
    async_signal = function()
        local self = {}
        signal_proxy[self] = {
            connectionFront = false,
            connectionBack = false
        }
        return setmetatable(self, signal_mt)
    end
end

---Wraps the provided function in a coroutine.
---Unlike `coroutine.wrap(fn)`, the function returned from `async(fn)` can be reused.
---@param fn function
---@return function
local function async_call(_, fn)
    local fn_type = type(fn)
    assert(fn_type == "function", 'async: Attempt to wrap invalid value (expected "function", got "%s")', fn_type)
    local function resumer(...)
        local thread = get_thread()
        return co_resume(thread, fn, ...)
    end
    return resumer
end

---Can be called as a function to wrap a function in a coroutine.
---@class AsyncLib
local async = {
    spawn = async_spawn,
    defer = async_defer,
    wait = async_wait,
    signal = async_signal
}
local async_mt = {
    __index = async,
    __newindex = readonly_error,
    __call = async_call,
    __metatable = "async metatable locked"
}

return setmetatable({}, async_mt)
