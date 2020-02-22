local EntityHandling = {}
local Logging = require("utility/logging")
local Events = require("utility/events")
local Utils = require("utility/utils")
local Interfaces = require("utility/interfaces")

local beltDirections = {horizontal = "h", vertical = "v"}

EntityHandling.CreateGlobals = function()
    global.entityHandling = global.entityHandling or {}
    global.entityHandling.playersWarned = global.entityHandling or {}
    global.entityHandling.undergroundTiles = global.entityHandling.undergroundTiles or {[1] = {}} -- has a surface first filter layer. id 1 is for nauvis as it doesn't fire a surface created event.
    global.entityHandling.currentUndergroundRouteId = global.entityHandling.currentUndergroundRouteId or 0
    global.entityHandling.undergroundRoutes = global.entityHandling.undergroundRoutes or {} -- array of pairs of underground belts: {entityId, position}
    global.entityHandling.undergroundEntityIdToRouteId = global.entityHandling.undergroundEntityIdToRouteId or {}
end

EntityHandling.OnLoad = function()
    Events.RegisterHandler(defines.events.on_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.on_robot_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.script_raised_built, "EntityHandling.OnScriptRaisedBuiltEvent", EntityHandling.OnScriptRaisedBuiltEvent)
    Events.RegisterHandler(defines.events.on_player_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.on_robot_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.on_entity_died, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent, "typeUndergroundBelt")
    Events.RegisterHandler(defines.events.script_raised_destroy, "EntityHandling.OnScriptRaisedDestroyedEvent", EntityHandling.OnScriptRaisedDestroyedEvent)
    Events.RegisterHandler(defines.events.on_surface_created, "EntityHandling.OnSurfaceCreated", EntityHandling.OnSurfaceCreated)
end

EntityHandling.OnSurfaceCreated = function(event)
    local surfaceId = event.surface_index
    global.entityHandling.undergroundTiles[surfaceId] = global.entityHandling.undergroundTiles[surfaceId] or {}
end

EntityHandling.OnUndergroundBuiltEvent = function(event)
    local ugEntity = event.created_entity
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
        Interfaces.Call("Sinned.Committed", ugEntity, otherEndEntity, player, robotPlacer)
    end
end

EntityHandling.OnScriptRaisedBuiltEvent = function(event)
    local entity = event.entity
    if entity.type == "underground-belt" then
        EntityHandling.OnUndergroundBuiltEvent({created_entity = entity})
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

EntityHandling.OnScriptRaisedDestroyedEvent = function(event)
    local entity = event.entity
    if entity.type == "underground-belt" then
        EntityHandling.OnUndergroundRemovedEvent({entity = entity})
    end
end

EntityHandling.HandleNewUndergroundRoute = function(startEntity, endEntity)
    local startPos, endPos, surface = startEntity.position, endEntity.position, startEntity.surface
    local endPosString, surfaceId = Logging.PositionToString(endPos), surface.index

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

    --Remove any old routes that we have just changed by placing a same color underground in the middle of. This isn't a belt braid in itself.
    local oldRouteId = global.entityHandling.undergroundEntityIdToRouteId[startEntity.unit_number] or global.entityHandling.undergroundEntityIdToRouteId[endEntity.unit_number]
    if oldRouteId ~= nil then
        local oldRouteDetails = global.entityHandling.undergroundRoutes[oldRouteId]
        local ugEntity1 = surface.find_entities_filtered {type = "underground-belt", position = oldRouteDetails[1].position}[1]
        local ugEntity2 = surface.find_entities_filtered {type = "underground-belt", position = oldRouteDetails[2].position}[1]
        EntityHandling.HandleRemovedUndergroundRoute(ugEntity1, ugEntity2)
    end

    local pos = Utils.DeepCopy(startPos)
    local posString = Logging.PositionToString(pos)
    local tileEmpty = EntityHandling.CheckTileEmpty(surfaceId, posString, direction)
    if not tileEmpty then
        return false
    end
    local reachedEndPos, tileDistance = false, 1
    while not reachedEndPos and tileDistance < 100 do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        tileEmpty = EntityHandling.CheckTileEmpty(surfaceId, posString, direction)
        if not tileEmpty then
            return false
        end
        if posString == endPosString then
            reachedEndPos = true
        end
        tileDistance = tileDistance + 1
    end

    global.entityHandling.currentUndergroundRouteId = global.entityHandling.currentUndergroundRouteId + 1
    local routeId = global.entityHandling.currentUndergroundRouteId
    global.entityHandling.undergroundEntityIdToRouteId[startEntity.unit_number] = routeId
    global.entityHandling.undergroundEntityIdToRouteId[endEntity.unit_number] = routeId
    global.entityHandling.undergroundRoutes[routeId] = {
        {entityId = startEntity.unit_number, position = startEntity.position},
        {entityId = endEntity.unit_number, position = endEntity.position}
    }

    pos = Utils.DeepCopy(startPos)
    posString = Logging.PositionToString(pos)
    EntityHandling.MarkTile(surfaceId, posString, direction)
    reachedEndPos, tileDistance = false, 1
    while not reachedEndPos and tileDistance < 100 do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        EntityHandling.MarkTile(surfaceId, posString, direction)
        if posString == endPosString then
            reachedEndPos = true
        end
        tileDistance = tileDistance + 1
    end

    return true
end

EntityHandling.CheckTileEmpty = function(surfaceId, tilePosString, direction)
    if global.entityHandling.undergroundTiles[surfaceId][tilePosString] == nil then
        return true
    end
    if global.entityHandling.undergroundTiles[surfaceId][tilePosString][direction] == nil then
        return true
    else
        return false
    end
end

EntityHandling.MarkTile = function(surfaceId, tilePosString, direction)
    global.entityHandling.undergroundTiles[surfaceId][tilePosString] = global.entityHandling.undergroundTiles[surfaceId][tilePosString] or {}
    global.entityHandling.undergroundTiles[surfaceId][tilePosString][direction] = true
end

EntityHandling.UnMarkTile = function(surfaceId, tilePosString, direction)
    if global.entityHandling.undergroundTiles[surfaceId][tilePosString] == nil then
        return
    end
    global.entityHandling.undergroundTiles[surfaceId][tilePosString][direction] = nil
    if Utils.GetTableNonNilLength(global.entityHandling.undergroundTiles[surfaceId][tilePosString]) == 0 then
        global.entityHandling.undergroundTiles[surfaceId][tilePosString] = nil
    end
end

EntityHandling.HandleRemovedUndergroundRoute = function(startEntity, endEntity)
    local startPos, endPos, surfaceId = startEntity.position, endEntity.position, startEntity.surface.index
    local endPosString = Logging.PositionToString(endPos)

    --If theres no logged route using this underground then there is nothing to unmark or remove from globals.
    if global.entityHandling.undergroundEntityIdToRouteId[startEntity.unit_number] == nil then
        return
    end

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

    local routeId = global.entityHandling.undergroundEntityIdToRouteId[startEntity.unit_number]
    global.entityHandling.undergroundRoutes[routeId] = nil
    global.entityHandling.undergroundEntityIdToRouteId[startEntity.unit_number] = nil
    global.entityHandling.undergroundEntityIdToRouteId[endEntity.unit_number] = nil

    local pos = Utils.DeepCopy(startPos)
    local posString = Logging.PositionToString(pos)
    EntityHandling.UnMarkTile(surfaceId, posString, direction)
    local reachedEndPos, tileDistance = false, 1
    while not reachedEndPos and tileDistance < 100 do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        EntityHandling.UnMarkTile(surfaceId, posString, direction)
        if posString == endPosString then
            reachedEndPos = true
        end
        tileDistance = tileDistance + 1
    end
end

return EntityHandling
