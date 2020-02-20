local EntityHandling = {}
local Logging = require("utility/logging")
local Events = require("utility/events")
local Utils = require("utility/utils")

local beltDirections = {horizontal = "h", vertical = "v"}

EntityHandling.CreateGlobals = function()
    global.entityHandling = global.entityHandling or {}
    global.entityHandling.playersWarned = global.entityHandling or {}
    global.entityHandling.undergroundTiles = global.entityHandling.undergroundTiles or {}
end

EntityHandling.OnLoad = function()
    Events.RegisterHandler(defines.events.on_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.on_robot_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.script_raised_built, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent)
    Events.RegisterHandler(defines.events.on_player_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.on_robot_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.on_entity_died, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.script_raised_destroy, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterHandler(defines.events.on_player_rotated_entity, "EntityHandling.OnUndergroundChangedEvent", EntityHandling.OnUndergroundChangedEvent)
end

EntityHandling.OnUndergroundBuiltEvent = function(event)
    EntityHandling.CreateGlobals() --TODO: just to make test save work
    local ugEntity = event.created_entity or event.entity
    local otherEndEntity = ugEntity.neighbours
    if otherEndEntity == nil then
        return
    end

    local playerId, player = event.player_index
    local robotPlacer = event.robot
    if playerId ~= nil then
        player = game.get_player(playerId)
    else
        player = ugEntity.last_user
    end

    if not EntityHandling.HandleNewUndergroundRoute(ugEntity, otherEndEntity) then
        game.print("belts clashed - punish them! TODO")
    end
end

EntityHandling.OnUndergroundChangedEvent = function(event)
    --[[
        entity :: LuaEntity: The rotated entity.
        previous_direction :: defines.direction: The previous direction
        player_index :: uint
    ]]
    game.print("entity rotation TODO")
end

EntityHandling.HandleNewUndergroundRoute = function(startEntity, endEntity)
    local debug = false
    local startPos, endPos = startEntity.position, endEntity.position
    local direction, change
    if startPos.x < endPos.x then
        direction = beltDirections.horizontal
        change = 1
    elseif startPos.x > endPos.x then
        direction = beltDirections.horizontal
        change = -1
    elseif startPos.y < endPos.y then
        direction = beltDirections.vertical
        change = 1
    elseif startPos.y > endPos.y then
        direction = beltDirections.vertical
        change = -1
    else
        Logging.LogPrint("Error: no belt direction between start and end")
        return nil
    end

    local endPosString = Logging.PositionToString(endPos)

    local pos = Utils.DeepCopy(startPos)
    local posString = Logging.PositionToString(pos)
    local tileEmpty = EntityHandling.CheckTileEmpty(posString, direction)
    if not tileEmpty then
        return false
    end
    local reachedEndPos, tileDistance = false, 1
    Logging.LogPrint("check - start: " .. posString, debug)
    while not reachedEndPos and tileDistance < 100 do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        Logging.LogPrint("check: " .. posString, debug)
        tileEmpty = EntityHandling.CheckTileEmpty(posString, direction)
        if not tileEmpty then
            return false
        end
        if posString == endPosString then
            reachedEndPos = true
        end
        tileDistance = tileDistance + 1
    end

    pos = Utils.DeepCopy(startPos)
    posString = Logging.PositionToString(pos)
    EntityHandling.MarkTile(posString, direction)
    reachedEndPos, tileDistance = false, 1
    Logging.LogPrint("mark - start: " .. posString, debug)
    while not reachedEndPos and tileDistance < 100 do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        Logging.LogPrint("mark: " .. posString, debug)
        EntityHandling.MarkTile(posString, direction)
        if posString == endPosString then
            reachedEndPos = true
        end
        tileDistance = tileDistance + 1
    end

    return true
end

EntityHandling.CheckTileEmpty = function(tilePosString, direction)
    if global.entityHandling.undergroundTiles[tilePosString] == nil then
        return true
    end
    if global.entityHandling.undergroundTiles[tilePosString][direction] == nil then
        return true
    else
        return false
    end
end

EntityHandling.MarkTile = function(tilePosString, direction)
    global.entityHandling.undergroundTiles[tilePosString] = global.entityHandling.undergroundTiles[tilePosString] or {}
    global.entityHandling.undergroundTiles[tilePosString][direction] = true
end

EntityHandling.UnMarkTile = function(tilePosString, direction)
    if global.entityHandling.undergroundTiles[tilePosString] == nil then
        return
    end
    global.entityHandling.undergroundTiles[tilePosString][direction] = nil
    if Utils.GetTableNonNilLength(global.entityHandling.undergroundTiles[tilePosString]) == 0 then
        global.entityHandling.undergroundTiles[tilePosString] = nil
    end
end

EntityHandling.OnUndergroundRemovedEvent = function(event)
    local ugEntity = event.entity
    local otherEndEntity = ugEntity.neighbours
    if otherEndEntity == nil then
        return
    end
    EntityHandling.HandleRemovedUndergroundRoute(ugEntity, otherEndEntity)
end

EntityHandling.HandleRemovedUndergroundRoute = function(startEntity, endEntity)
    local debug = false
    local startPos, endPos = startEntity.position, endEntity.position
    local direction, change
    if startPos.x < endPos.x then
        direction = beltDirections.horizontal
        change = 1
    elseif startPos.x > endPos.x then
        direction = beltDirections.horizontal
        change = -1
    elseif startPos.y < endPos.y then
        direction = beltDirections.vertical
        change = 1
    elseif startPos.y > endPos.y then
        direction = beltDirections.vertical
        change = -1
    else
        Logging.LogPrint("Error: no belt direction between start and end")
        return nil
    end

    local endPosString = Logging.PositionToString(endPos)

    local pos = Utils.DeepCopy(startPos)
    local posString = Logging.PositionToString(pos)
    EntityHandling.UnMarkTile(posString, direction)
    local reachedEndPos, tileDistance = false, 1
    Logging.LogPrint("remove - start: " .. posString, debug)
    while not reachedEndPos and tileDistance < 100 do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        Logging.LogPrint("remove: " .. posString, debug)
        EntityHandling.UnMarkTile(posString, direction)
        if posString == endPosString then
            reachedEndPos = true
        end
        tileDistance = tileDistance + 1
    end
end

return EntityHandling
