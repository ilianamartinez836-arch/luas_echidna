-- Toggle Particulas (r_drawparticles) con la tecla 'K' — Echidna L4D2
local VK_K = 0x4B -- Tecla 'K'
local cv_particles = Cvars.FindVar("r_drawparticles")
local particles_off = false

-- Desbloquear flag FCVAR_CHEAT por si sv_cheats está en 0
if cv_particles then
    pcall(cv_particles.RemoveFlags, cv_particles, 16384)
end

function on_key_down(key)
    if key == VK_K then
        particles_off = not particles_off
        local val = particles_off and 0 or 1

        if cv_particles then
            cv_particles:SetInt(val)
        end
        pcall(EngineClient.ClientCmd, "r_drawparticles " .. val)

        client.print("[Particles] " .. (particles_off and "DESACTIVADAS (0)" or "ACTIVADAS (1)"))
    end
end

client.print("[Particles] Cargado — Presiona 'K' para activar/desactivar.")
