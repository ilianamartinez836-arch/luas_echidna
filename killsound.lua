local ffi = require("ffi")
pcall(ffi.cdef, [[ bool PlaySoundA(const char* s, void* h, uint32_t f); ]])
local winmm = ffi.load("winmm")

local SOUND_PATH = [[C:\Users\ACER\Downloads\neverlose.wav]]

local id = events.add_listener("player_death", function()
    winmm.PlaySoundA(SOUND_PATH, nil, 0x20003)
end)

function on_unload()
    if id then events.remove_listener("player_death", id) end
end
