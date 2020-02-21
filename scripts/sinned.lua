local Sinned = {}
--local Logging = require("utility/logging")
local Interfaces = require("utility/interfaces")
local Utils = require("utility/utils")
local Colors = require("utility/colors")

Sinned.CreateGlobals = function()
    global.sinned = global.sinned or {}
    global.sinned.playerWarningsMax = global.sinned.playerWarningsMax or 0
    global.sinned.playersWarned = global.sinned.playersWarned or {}
end

Sinned.OnLoad = function()
    Interfaces.RegisterInterface("Sinned.Committed", Sinned.Committed)
end

Sinned.OnSettingChanged = function(event)
    local settingName
    if event ~= nil then
        settingName = event.setting
    end
    if event == nil or settingName == "belt_braid_sinner-player_warnings" then
        global.sinned.playerWarningsMax = tonumber(settings.global["belt_braid_sinner-player_warnings"].value)
    end
end

Sinned.Committed = function(ugEntity, otherEndEntity, player, robotPlacer)
    local surface = ugEntity.surface

    Sinned.SwallowEntityInHole(ugEntity)
    Sinned.SwallowEntityInHole(otherEndEntity)
    if player ~= nil then
        local playerToBePunished = true
        if global.sinned.playerWarningsMax > 0 then
            global.sinned.playersWarned[player.index] = global.sinned.playersWarned[player.index] or 0
            global.sinned.playersWarned[player.index] = global.sinned.playersWarned[player.index] + 1
            if global.sinned.playersWarned[player.index] <= global.sinned.playerWarningsMax then
                playerToBePunished = false
            end
        end
        if playerToBePunished then
            game.print({"message.belt_braid_sinner-player_punished", player.name}, Colors.red)
            if player.character ~= nil then
                surface.create_entity {name = "belt_braid_sinner-fire", position = player.character.position, initial_ground_flame_count = 10}
                surface.create_entity {name = "fire-sticker", position = player.character.position, target = player.character}
            elseif player.vehicle ~= nil then
                surface.create_entity {name = "belt_braid_sinner-fire", position = player.vehicle.position, initial_ground_flame_count = 10}
                surface.create_entity {name = "fire-sticker", position = player.vehicle.position, target = player.vehicle}
            end
        else
            game.print({"message.belt_braid_sinner-player_warning", player.name}, Colors.red)
        end
    end
    if robotPlacer ~= nil then
        robotPlacer.die()
    end
end

Sinned.SwallowEntityInHole = function(targetEntity)
    local surface, position = targetEntity.surface, targetEntity.position
    surface.create_entity {name = "belt_braid_sinner-hole_in_ground", position = position}

    surface.create_trivial_smoke {name = "belt_braid_sinner-hole_in_ground_burst", position = position}
    surface.create_trivial_smoke {name = "belt_braid_sinner-hole_in_ground_burst", position = position}
    surface.create_trivial_smoke {name = "belt_braid_sinner-hole_in_ground_linger", position = position}

    surface.create_entity {name = "flying-robot-damaged-explosion", position = position}
    surface.create_entity {name = "flying-robot-damaged-explosion", position = position}
    surface.create_entity {name = "flying-robot-damaged-explosion", position = position}
    surface.create_entity {name = "rock-damaged-explosion", position = position}
    surface.create_entity {name = "rock-damaged-explosion", position = position}
    surface.create_entity {name = "rock-damaged-explosion", position = position}

    targetEntity.destroy()
    surface.create_entity {name = "belt_braid_sinner-explosion", position = Utils.ApplyOffsetToPosition(position, {x = 0, y = 0.5})}
end

return Sinned
