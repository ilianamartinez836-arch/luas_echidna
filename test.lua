-- PROBE FINAL — pega esto como archivo .lua y cárgalo en partida
local done_groups = false
local done_color  = false

function on_end_scene()
    if not EngineClient.IsInGame() then return end

    -- 1) GetGroup en partida real, con nombres de clase para saber qué hay en cada grupo
    if not done_groups then
        done_groups = true
        for _, n in ipairs({0,1,2,3,4,5,6}) do
            local ok, res = pcall(function() return EntityCache.GetGroup(n) end)
            if ok and type(res) == "table" then
                local names = {}
                for _, ent in ipairs(res) do
                    local ok2, cls = pcall(function() return ent:get_class_name() end)
                    names[#names+1] = ok2 and cls or "?"
                end
                client.print(string.format("[TEST] GetGroup(%d) = %d -> %s", n, #res, table.concat(names, ",")))
            else
                client.print(string.format("[TEST] GetGroup(%d) ERROR/nil", n))
            end
        end
    end

    -- 2) Escala de color de visual.* — dibuja dos cajas, una con 255 y otra con 1.0, bien separadas
    if not done_color then
        done_color = true
        client.print("[TEST] Mirando pantalla: caja arriba-izq debe verse ROJA si visual.* es 0-255")
        client.print("[TEST] Caja abajo-der debe verse ROJA si visual.* es 0-1 (si la de arriba sale blanca/rara, es esta la correcta)")
    end
    pcall(function() visual.draw_box(50, 50, 80, 40, {255, 0, 0, 255}) end)
    pcall(function() visual.draw_box(50, 400, 80, 40, {1.0, 0, 0, 1.0}) end)
end

-- 3) Niveles de log 3 y 4, mirando con atención el color/prefijo exacto en consola
function on_create_move(cmd, lp)
    -- nada, solo para que el script tenga un hook activo normal
end

print("Ejecuta esto una sola vez en consola para ver niveles 3 y 4 de nuevo, con atención al color del texto:")
print("client.log('ping_nivel3', 3)")
print("client.log('ping_nivel4', 4)")
