-- Fake Duck / Crouch Desync (Heaven Port 1:1) — Echidna (L4D2)
local ENABLED = true

local function LK8_W()
    local O9_C = 0
    
    return function(cmd, local_player)
        if not ENABLED then 
            O9_C = 0
            return 
        end

        local IN_DUCK = 4

        O9_C = O9_C + 1

        if O9_C <= 7 then
            cmd:add_button(IN_DUCK)
            pcall(client.set_send_packet, false)
            
        elseif O9_C <= 14 then
            cmd:remove_button(IN_DUCK)
            pcall(client.set_send_packet, false)
            
        else
            pcall(client.set_send_packet, true)
            O9_C = 0
        end
    end
end

local T9_X = LK8_W()

function on_create_move_prediction(cmd, local_player)
    if not cmd or not local_player or not local_player:is_alive() then
        return
    end

    T9_X(cmd, local_player)
end
