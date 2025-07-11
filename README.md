# async.lua

## Installation

The library comes in one file. Find it [here.](/lib/async.lua)

You can install it by copying the file to anywhere in your mod folder.

### sm64coopdx 1.4+

If you're on version 1.4 or above, you need to make sure the file is in a subfolder.

This is due to the `require` function not recognising top-level files.

To use the library, you can prepend the following to any scripts that use it:

```lua
local async = require("async")
```

### sm64coopdx <1.4

If you're on a version below 1.4, there is a line at the very bottom of the script that you need to uncomment.

Since these versions lack a `require` function, the file must be in the top folder of your mod.

After uncommenting the line mentioned previously, you can access the library from anywhere by just `async`.

## Usage

### `async`

`async(fn: function)`

`async` is magic in that it acts as both a table and function.

This will return a coroutine-ified version of whatever function you give it. It is important that you do this for any functions that will use the blocking functionality of the library.

This behaviour is similar to `coroutine.wrap`, however that does not allow you to reuse the function.

For [signals](#asyncsignal), [`async.spawn`](#asyncspawn) and [`async.defer`](#asyncdefer), you do not need to use this.

```lua
hook_event(HOOK_ON_MODS_LOADED, async(function()
    async.wait(5)
    print("Look ma! No errors!")
end))

hook_event(HOOK_ON_MODS_LOADED, function()
    async.wait(5) -- this will throw an error
end)
```

### `async.spawn`

`async.spawn(fn: function, ...: any)`

This will immediately resume a coroutine running the function you give it with the arguments provided.

```lua
async.spawn(function(a, b, c)
    print(a) -- 1
    async.wait(1)
    print(b) -- 2
    async.wait(1)
    print(c) -- 3
end, 1, 2, 3)
```

### `async.defer`

`async.spawn(fn: function, ...: any)`

This behaves the same as [`async.spawn`](#asyncspawn), but will resume the coroutine on the next frame rather than immediately.

See the previous example.

### `async.wait`

`async.wait(t: number)`

This waits for `t` seconds.

Due to the limitations of smlua, the accuracy of this can only be within 1/30th of a second.

Returns the actual time spent waiting.

```lua
hook_event(HOOK_ON_MODS_LOADED, async(function()
    async.wait(30)
    print("Mods loaded 30 seconds ago!")
end))
```

### `async.signal`

`async.signal()`

If you've ever written scripts for Roblox, this will seem familiar.

This is more or less a port of [stravant's GoodSignal](https://github.com/stravant/goodsignal/) with some stylistic changes.

Returns an AsyncSignal.

```lua
local mySignal = async.signal()

async.spawn(function()
    local v = mySignal:wait()
    print(v) -- "Hi!"
    v = mySignal:wait()
    print(v) -- "Hi again!"
end)

local conn = mySignal:connect(function(v)
    print(v) -- "Hi!" then "Hi again!"
end)

mySignal:once(function(v)
    print(v) -- "Hi!"
end)

mySignal:fire("Hi!")
mySignal:fire("Hi again!")

conn:disconnect()
mySignal:fire("Hi again again!") -- never printed
```

For slightly more thorough documentation on signal usage, see the class definitions near the top of `async.lua`.
