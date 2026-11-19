local IN_ATTACK = 1
function on_create_move(cmd, local_player)
    if not local_player then return end
    if cmd:has_button(IN_ATTACK) then
        if (cmd:get_command_number() % 2 == 0) then
            cmd:remove_button(IN_ATTACK)
        end
    end
end
