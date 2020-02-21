local Sinned = {}
--local Logging = require("utility/logging")
local Interfaces = require("utility/interfaces")

Sinned.OnLoad = function()
    Interfaces.RegisterInterface("Sinned.Committed", Sinned.Committed)
end

Sinned.Committed = function(ugEntity, otherEndEntity, player, robotPlacer)
    game.print("belts clashed - punish them! TODO")
    local surface = ugEntity.surface

    surface.create_entity {name = "belt_braid_sinner-fire", position = ugEntity.position, initial_ground_flame_count = 10}
    surface.create_entity {name = "belt_braid_sinner-fire", position = otherEndEntity.position, initial_ground_flame_count = 10}
    if player ~= nil then
        if player.character ~= nil then
            surface.create_entity {name = "belt_braid_sinner-fire", position = player.character.position, initial_ground_flame_count = 10}
        elseif player.vehicle ~= nil then
            surface.create_entity {name = "belt_braid_sinner-fire", position = player.vehicle.position, initial_ground_flame_count = 10}
        end
    end
    if robotPlacer ~= nil then
        surface.create_entity {name = "belt_braid_sinner-fire", position = robotPlacer.position, initial_ground_flame_count = 10}
    end
end

return Sinned
