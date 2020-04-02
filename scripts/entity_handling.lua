local EntityHandling = {}
local Logging = require("utility/logging")
local Events = require("utility/events")
local Utils = require("utility/utils")
local Interfaces = require("utility/interfaces")
local Commands = require("utility/commands")
local Colors = require("utility/colors")

local beltDirections = {horizontal = "h", vertical = "v"}
local purgeVersion = 2
local beltMaxLength = 100

EntityHandling.CreateGlobals = function()
    global.entityHandling = global.entityHandling or {}
    global.entityHandling.playersWarned = global.entityHandling or {}
    global.entityHandling.undergroundTiles = global.entityHandling.undergroundTiles or {[1] = {}} -- has a surface first filter layer. id 1 is for nauvis as it doesn't fire a surface created event.
    global.entityHandling.currentUndergroundRouteId = global.entityHandling.currentUndergroundRouteId or 0
    global.entityHandling.undergroundRoutes = global.entityHandling.undergroundRoutes or {} -- array of pairs of underground belts: {entityId, position}
    global.entityHandling.undergroundEntityIdToRouteId = global.entityHandling.undergroundEntityIdToRouteId or {}
    global.entityHandling.mapPurged = global.entityHandling.mapPurged or 0
    global.entityHandling.drawUGTiles = global.entityHandling.drawUGTiles or false
    global.entityHandling.debugRenderIds = global.entityHandling.debugRenderIds or {}
end

EntityHandling.OnLoad = function()
    Events.RegisterHandler(defines.events.on_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent)
    Events.RegisterHandler(defines.events.on_robot_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent)
    Events.RegisterHandler(defines.events.script_raised_built, "EntityHandling.OnScriptRaisedBuiltEvent", EntityHandling.OnScriptRaisedBuiltEvent)
    Events.RegisterHandler(defines.events.script_raised_revive, "EntityHandling.OnScriptRaisedBuiltEvent", EntityHandling.OnScriptRaisedBuiltEvent)
    Events.RegisterHandler(defines.events.on_player_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterHandler(defines.events.on_robot_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterHandler(defines.events.on_entity_died, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterHandler(defines.events.script_raised_destroy, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterHandler(defines.events.on_surface_created, "EntityHandling.OnSurfaceCreated", EntityHandling.OnSurfaceCreated)
    Commands.Register("belt_braid_sinner_purge_surfaces", {"api-description.belt_braid_sinner_purge_surfaces"}, EntityHandling.PurgeCurrentSurfaces, true)
    Commands.Register("belt_braid_sinner_toggle_debug_render", {"api-description.belt_braid_sinner_toggle_debug_render"}, EntityHandling.ToggleDebugRender, true)
end

EntityHandling.OnSurfaceCreated = function(event)
    local surfaceId = event.surface_index
    global.entityHandling.undergroundTiles[surfaceId] = global.entityHandling.undergroundTiles[surfaceId] or {}
end

EntityHandling.OnUndergroundBuiltEvent = function(event)
    local ugEntity = event.created_entity
    if ugEntity.type ~= "underground-belt" then
        return
    end

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
    if entity.type ~= "underground-belt" then
        return
    end

    EntityHandling.OnUndergroundBuiltEvent({created_entity = entity})
end

EntityHandling.OnUndergroundRemovedEvent = function(event)
    local entity = event.entity
    if entity.type ~= "underground-belt" then
        return
    end

    local routeId = global.entityHandling.undergroundEntityIdToRouteId[entity.unit_number]
    if routeId == nil then
        return
    end

    local surface = entity.surface
    local routeDetails = global.entityHandling.undergroundRoutes[routeId]
    local ugEntity1 = surface.find_entities_filtered {type = "underground-belt", position = routeDetails[1].position, limit = 1}[1]
    local ugEntity2 = surface.find_entities_filtered {type = "underground-belt", position = routeDetails[2].position, limit = 1}[1]
    EntityHandling.HandleRemovedUndergroundRoute(ugEntity1, ugEntity2)
end

EntityHandling.HandleNewUndergroundRoute = function(startEntity, endEntity)
    EntityHandling.CheckAndPurgeCurrentSurfaces()
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
        local ugEntity1 = surface.find_entities_filtered {type = "underground-belt", position = oldRouteDetails[1].position, limit = 1}[1]
        local ugEntity2 = surface.find_entities_filtered {type = "underground-belt", position = oldRouteDetails[2].position, limit = 1}[1]
        EntityHandling.HandleRemovedUndergroundRoute(ugEntity1, ugEntity2)
    end

    local pos = Utils.DeepCopy(startPos)
    local posString = Logging.PositionToString(pos)
    local tileEmpty = EntityHandling.CheckTileEmpty(surfaceId, posString, direction)
    if not tileEmpty then
        return false
    end
    local reachedEndPos, tileDistance = false, 1
    while not reachedEndPos and tileDistance < beltMaxLength do
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
    while not reachedEndPos and tileDistance < beltMaxLength do
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

    EntityHandling.RefreshDebugRender()
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
    EntityHandling.CheckAndPurgeCurrentSurfaces()
    if startEntity == nil or (not startEntity.valid) or endEntity == nil or (not endEntity.valid) then
        return
    end
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
    while not reachedEndPos and tileDistance < beltMaxLength do
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

    EntityHandling.RefreshDebugRender()
end

EntityHandling.CheckAndPurgeCurrentSurfaces = function()
    if global.entityHandling.mapPurged == purgeVersion then
        return
    end
    EntityHandling.PurgeCurrentSurfaces()
end

EntityHandling.PurgeCurrentSurfaces = function()
    global.entityHandling.mapPurged = purgeVersion

    global.entityHandling.undergroundTiles = {[1] = {}}
    global.entityHandling.currentUndergroundRouteId = 0
    global.entityHandling.undergroundRoutes = {}
    global.entityHandling.undergroundEntityIdToRouteId = {}

    for _, surface in pairs(game.surfaces) do
        EntityHandling.PurgeSpecificSurface(surface)
    end

    EntityHandling.RefreshDebugRender()
end

EntityHandling.PurgeSpecificSurface = function(surface)
    local ugEntities = surface.find_entities_filtered {type = "underground-belt"}
    for _, ugEntity in pairs(ugEntities) do
        if ugEntity ~= nil and ugEntity.valid then
            local otherEndEntity = ugEntity.neighbours
            if otherEndEntity ~= nil and global.entityHandling.undergroundEntityIdToRouteId[ugEntity.unit_number] == nil then
                if not EntityHandling.HandleNewUndergroundRoute(ugEntity, otherEndEntity) then
                    Interfaces.Call("Sinned.BurnOldBelt", ugEntity)
                    Interfaces.Call("Sinned.BurnOldBelt", otherEndEntity)
                end
            end
        end
    end
end

EntityHandling.ToggleDebugRender = function()
    if global.entityHandling.drawUGTiles then
        EntityHandling.RemoveDebugRender()
    else
        EntityHandling.AddDebugRender()
    end
end

EntityHandling.RefreshDebugRender = function()
    if not global.entityHandling.drawUGTiles then
        return
    end

    EntityHandling.RemoveDebugRender()
    EntityHandling.AddDebugRender()
end

EntityHandling.AddDebugRender = function()
    global.entityHandling.drawUGTiles = true

    for surfaceId, surfaceUGTiles in pairs(global.entityHandling.undergroundTiles) do
        local surface = game.surfaces[surfaceId]
        for tilePosString, directions in pairs(surfaceUGTiles) do
            local directionString = nil
            if directions[beltDirections.vertical] then
                directionString = "v"
            end
            if directions[beltDirections.horizontal] then
                if directionString ~= nil then
                    directionString = "v-h"
                else
                    directionString = "h"
                end
            end

            local cleansedPosString = string.gsub(tilePosString, "[()]", "")
            local commaIndex = string.find(cleansedPosString, ",")
            local xPos = string.sub(cleansedPosString, 1, commaIndex - 1)
            local yPos = string.sub(cleansedPosString, commaIndex + 2)
            local renderId = rendering.draw_text {text = directionString, surface = surface, target = {x = xPos, y = yPos}, color = Colors.white}
            table.insert(global.entityHandling.debugRenderIds, renderId)
        end
    end
end

EntityHandling.RemoveDebugRender = function()
    global.entityHandling.drawUGTiles = false
    for _, id in pairs(global.entityHandling.debugRenderIds) do
        rendering.destroy(id)
    end
    global.entityHandling.debugRenderIds = {}
end

return EntityHandling
