local function apply()
    if not EngineClient.IsInGame() then return end
    EngineClient.ClientCmd_Unrestricted("fog_override 1; fog_start 0; fog_end 2500; fog_maxdensity 0.85; fog_blend 1; fog_color 189 126 239; fog_color2 189 126 239")
end

function on_create_move(cmd, lp)
    apply()
end

function on_unload()
    EngineClient.ClientCmd_Unrestricted("fog_override 0; fog_maxdensity 1; fog_color -1 -1 -1; fog_color2 -1 -1 -1")
end

apply()
