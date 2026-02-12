-- Data model
local damage = require("model.damage")

local init = function()
    -- Ensure data model
    storage = storage or {}
    storage.forces = storage.forces or {}

    damage.init()
end

local load = function()
    commands.add_command("show-dmg", "Mockup to show the damage", function(command)
        local p = game.get_player(command.player_index)
        local map = damage.get(p.force.index, p.surface.index, {{-100, -100}, {100, 100}})

        -- First get the max val
        local max = 0
        for x, col in pairs(map or {}) do
            for y, val in pairs(col or {}) do
                if val > 1 then
                    max = math.max(max, val)
                end
            end
        end

        -- Then draw the heatmap
        for x, col in pairs(map or {}) do
            for y, val in pairs(col or {}) do
                if val > 1 then
                    local prop = {
                        color = {1, 0, 0, (val / max)},
                        filled = true,
                        left_top = {x, y},
                        right_bottom = {x + 1, y + 1},
                        surface = p.surface.index,
                        time_to_live = 10 * 60
                    }
                    rendering.draw_rectangle(prop)
                end
            end
        end
    end)
end

script.on_configuration_changed(function()
    init()
end)

script.on_init(function()
    init()
    load()
end)

script.on_load(function()
    load()
end)

script.on_event({defines.events.on_player_joined_game, defines.events.on_player_created,
                 defines.events.on_player_changed_force}, function(e)
    init()
end)
script.on_event(defines.events.on_tick, function(e)
end)

script.on_event(defines.events.on_entity_damaged, function(e)
    -- Early exit if it's not in our favor, i.e. there is no (valid) entity or we don't have the storage force indexed
    if not e.entity or not storage or not storage.forces[e.entity.force.index] then
        return
    end

    -- Log the damage
    damage.log(e.entity.force.index, game.tick, e.entity.surface.index, math.floor(e.entity.position.x),
        math.floor(e.entity.position.y), e.final_damage_amount)
end)

