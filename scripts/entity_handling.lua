local EntityHandling = {}
local Logging = require("utility/logging")
local Events = require("utility/events")
local Utils = require("utility/utils")
local Interfaces = require("utility/interfaces")
local Commands = require("utility/commands")
local Colors = require("utility/colors")
local EventScheduler = require("utility/event-scheduler")

local beltDirections = {horizontal = "h", vertical = "v"}
local purgeVersion = 3
local beltMaxLength = 100

EntityHandling.CreateGlobals = function()
    global.entityHandling = global.entityHandling or {}
    global.entityHandling.playersWarned = global.entityHandling or {}
    global.entityHandling.undergroundTiles = global.entityHandling.undergroundTiles or {[1] = {}} -- has a surface first filter layer. id 1 is for nauvis as it doesn't fire a surface created event.
    global.entityHandling.currentUndergroundRouteId = global.entityHandling.currentUndergroundRouteId or 0
    global.entityHandling.undergroundRoutes = global.entityHandling.undergroundRoutes or {} -- array of pairs of underground belts: {entityId, entity, position}
    global.entityHandling.undergroundEntityIdToRouteId = global.entityHandling.undergroundEntityIdToRouteId or {}
    global.entityHandling.mapPurged = global.entityHandling.mapPurged or 0
    global.entityHandling.drawUGTiles = global.entityHandling.drawUGTiles or false
    global.entityHandling.debugRenderIds = global.entityHandling.debugRenderIds or {}
end

EntityHandling.OnLoad = function()
    Events.RegisterEvent(defines.events.on_built_entity, {{filter = "type", type = "underground-belt"}})
    Events.RegisterHandler(defines.events.on_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent)
    Events.RegisterEvent(defines.events.on_robot_built_entity, {{filter = "type", type = "underground-belt"}})
    Events.RegisterHandler(defines.events.on_robot_built_entity, "EntityHandling.OnUndergroundBuiltEvent", EntityHandling.OnUndergroundBuiltEvent)
    Events.RegisterEvent(defines.events.script_raised_built)
    Events.RegisterHandler(defines.events.script_raised_built, "EntityHandling.OnScriptRaisedBuiltEvent", EntityHandling.OnScriptRaisedBuiltEvent)
    Events.RegisterEvent(defines.events.script_raised_revive)
    Events.RegisterHandler(defines.events.script_raised_revive, "EntityHandling.OnScriptRaisedBuiltEvent", EntityHandling.OnScriptRaisedBuiltEvent)
    Events.RegisterEvent(defines.events.on_cancelled_deconstruction)
    Events.RegisterHandler(defines.events.on_cancelled_deconstruction, "EntityHandling.OnScriptRaisedBuiltEvent", EntityHandling.OnScriptRaisedBuiltEvent)

    Events.RegisterEvent(defines.events.on_player_mined_entity, {{filter = "type", type = "underground-belt"}})
    Events.RegisterHandler(defines.events.on_player_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterEvent(defines.events.on_robot_mined_entity, {{filter = "type", type = "underground-belt"}})
    Events.RegisterHandler(defines.events.on_robot_mined_entity, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterEvent(defines.events.on_entity_died, {{filter = "type", type = "underground-belt"}})
    Events.RegisterHandler(defines.events.on_entity_died, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterEvent(defines.events.script_raised_destroy)
    Events.RegisterHandler(defines.events.script_raised_destroy, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)
    Events.RegisterEvent(defines.events.on_marked_for_deconstruction)
    Events.RegisterHandler(defines.events.on_marked_for_deconstruction, "EntityHandling.OnUndergroundRemovedEvent", EntityHandling.OnUndergroundRemovedEvent)

    Events.RegisterEvent(defines.events.on_surface_created)
    Events.RegisterHandler(defines.events.on_surface_created, "EntityHandling.OnSurfaceCreated", EntityHandling.OnSurfaceCreated)
    Commands.Register("belt_braid_sinner_purge_surfaces", {"api-description.belt_braid_sinner_purge_surfaces"}, EntityHandling.PurgeCurrentSurfaces, true)
    Commands.Register("belt_braid_sinner_toggle_debug_render", {"api-description.belt_braid_sinner_toggle_debug_render"}, EntityHandling.ToggleDebugRender, true)
    EventScheduler.RegisterScheduledEventType("EntityHandling.ScheduledOnUndergroundBuiltEvent", EntityHandling.ScheduledOnUndergroundBuiltEvent)
    EventScheduler.RegisterScheduledEventType("EntityHandling.ScheduledCheckForNearbyUnknownConnectedUndergrounds", EntityHandling.ScheduledCheckForNearbyUnknownConnectedUndergrounds)
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
    EntityHandling.CheckAndPurgeCurrentSurfaces()

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

    if (not EntityHandling.HandleNewUndergroundRoute(ugEntity, otherEndEntity)) then
        Interfaces.Call("Sinned.Committed", ugEntity, otherEndEntity, player, robotPlacer)
    end
end

EntityHandling.OnScriptRaisedBuiltEvent = function(event)
    EntityHandling.OnUndergroundBuiltEvent({created_entity = event.entity})
end

EntityHandling.ScheduledOnUndergroundBuiltEvent = function(event)
    local entity = event.data.ugEntity
    if entity ~= nil and entity.valid then
        EntityHandling.OnUndergroundBuiltEvent({created_entity = entity})
    end
end

EntityHandling.OnUndergroundRemovedEvent = function(event)
    local entity = event.entity
    if entity.type ~= "underground-belt" and (entity.type == "ghost" and entity.ghost_type ~= "underground-belt") then
        return
    end
    EntityHandling.CheckAndPurgeCurrentSurfaces()

    local routeId = global.entityHandling.undergroundEntityIdToRouteId[entity.unit_number]
    if routeId == nil then
        return
    end

    local routeDetails = global.entityHandling.undergroundRoutes[routeId]
    local ugEntity1 = routeDetails[1].entity
    local ugEntity2 = routeDetails[2].entity
    EntityHandling.HandleRemovedUndergroundRoute(ugEntity1, ugEntity2)

    local otherEndUg = ugEntity1
    if entity.unit_number == otherEndUg.unit_number then
        otherEndUg = ugEntity2
    end
    if otherEndUg == nil then
        return
    end
    EventScheduler.ScheduleEvent(game.tick + 1, "EntityHandling.ScheduledOnUndergroundBuiltEvent", otherEndUg.unit_number, {ugEntity = otherEndUg})
    EventScheduler.ScheduleEvent(game.tick + 1, "EntityHandling.ScheduledCheckForNearbyUnknownConnectedUndergrounds", otherEndUg.unit_number, {surface = ugEntity1.surface, searchLength = ugEntity1.prototype.max_underground_distance, position1 = ugEntity1.position, position2 = ugEntity2.position, ugName = ugEntity1.name})
end

EntityHandling.HandleNewUndergroundRoute = function(startEntity, endEntity)
    WHEN THIS IS CALLED AFTER AN UPGRADE IT DOESN'T FIND THE NEW UG AT THE SPOTS AS WE DON'T DO A LOOKUP ANY MORE. BUT OLD CODE DIDN'T HANDLE GHOSTS, BUT NEITHER DOES NEW CODE SO MAYBE OLD CODE IS FINE AFTER ALL???
    BREAKS ON CHECKING TILE AS THEN IT DOES A LOOKUP IN INTERNAL GLOBALS BASED ON LOCATION AND FINDS THE OLD ENTITY REFERENCE.

    OLD CODE:
    surface.find_entities_filtered {type = "underground-belt", position = routeDetails[1].position, limit = 1}[1]

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

    --Remove any old routes that we have just changed by placing a single same color underground in the middle of. This isn't a belt braid in itself. Doesn't catch if we use bots to place a pair in between old belt pair at once.
    local oldRouteId = global.entityHandling.undergroundEntityIdToRouteId[startEntity.unit_number] or global.entityHandling.undergroundEntityIdToRouteId[endEntity.unit_number]
    if oldRouteId ~= nil then
        local oldRouteDetails = global.entityHandling.undergroundRoutes[oldRouteId]
        local ugEntity1 = oldRouteDetails[1].entity
        local ugEntity2 = oldRouteDetails[2].entity
        EntityHandling.HandleRemovedUndergroundRoute(ugEntity1, ugEntity2)
    end

    local pos = Utils.DeepCopy(startPos)
    local posString = Logging.PositionToString(pos)
    local tileEmpty = EntityHandling.CheckTileEmpty(surfaceId, posString, direction)
    if (not tileEmpty) then
        return false
    end
    local reachedEndPos, tileDistance = false, 1
    while (not reachedEndPos) and tileDistance < beltMaxLength do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        tileEmpty = EntityHandling.CheckTileEmpty(surfaceId, posString, direction)
        if (not tileEmpty) then
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
        {entityId = startEntity.unit_number, entity = startEntity, position = startEntity.position},
        {entityId = endEntity.unit_number, entity = endEntity, position = endEntity.position}
    }

    pos = Utils.DeepCopy(startPos)
    posString = Logging.PositionToString(pos)
    EntityHandling.MarkTile(surfaceId, posString, direction, routeId)
    reachedEndPos, tileDistance = false, 1
    while (not reachedEndPos) and (tileDistance < beltMaxLength) do
        if direction == beltDirections.vertical then
            pos.y = pos.y + change
        else
            pos.x = pos.x + change
        end
        posString = Logging.PositionToString(pos)
        EntityHandling.MarkTile(surfaceId, posString, direction, routeId)
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
    elseif global.entityHandling.undergroundTiles[surfaceId][tilePosString][direction] == nil then
        return true
    end

    local routeId = global.entityHandling.undergroundTiles[surfaceId][tilePosString][direction]
    local route = global.entityHandling.undergroundRoutes[routeId]
    if route[1].entity.neighbours == nil then
        EntityHandling.HandleRemovedUndergroundRoute(route[1].entity, route[2].entity)
        return true
    else
        return false
    end
end

EntityHandling.MarkTile = function(surfaceId, tilePosString, direction, routeId)
    global.entityHandling.undergroundTiles[surfaceId][tilePosString] = global.entityHandling.undergroundTiles[surfaceId][tilePosString] or {}
    global.entityHandling.undergroundTiles[surfaceId][tilePosString][direction] = routeId
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
    if (startEntity == nil) or (not startEntity.valid) or (endEntity == nil) or (not endEntity.valid) then
        Logging.LogPrint("WARNING - Belt Braid Sinner: underground route contains empty or invalid entites. Purge the map via command to fix and report to mod author.")
        return false
    end
    local startPos, endPos, surfaceId = startEntity.position, endEntity.position, startEntity.surface.index
    local endPosString = Logging.PositionToString(endPos)

    --If theres no logged route using this underground then there is nothing to unmark or remove from globals.
    if global.entityHandling.undergroundEntityIdToRouteId[startEntity.unit_number] == nil then
        return nil
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
    while (not reachedEndPos) and (tileDistance < beltMaxLength) do
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
    return true
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
    local ugEntities = EntityHandling.SearchForNearbyUndergrounds(surface, nil)
    for _, ugEntity in pairs(ugEntities) do
        if ugEntity ~= nil and ugEntity.valid then
            local otherEndEntity = ugEntity.neighbours
            if otherEndEntity ~= nil and global.entityHandling.undergroundEntityIdToRouteId[ugEntity.unit_number] == nil then
                if (not EntityHandling.HandleNewUndergroundRoute(ugEntity, otherEndEntity)) then
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
    if (not global.entityHandling.drawUGTiles) then
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

EntityHandling.SearchForNearbyUndergrounds = function(surface, name, area)
    local ugEntities = surface.find_entities_filtered {type = "underground-belt", name = name, area = area}
    local ugEntitiesGhosts = surface.find_entities_filtered {type = "ghost_entity", ghost_type = "underground-belt", ghost_name = name, area = area}
    return Utils.TableMerge({ugEntities, ugEntitiesGhosts})
end

EntityHandling.ScheduledCheckForNearbyUnknownConnectedUndergrounds = function(event)
    local data = event.data
    EntityHandling.CheckForNearbyUnknownConnectedUndergrounds(data.surface, data.searchLength, data.position1, data.position2, data.ugName)
end

EntityHandling.CheckForNearbyUnknownConnectedUndergrounds = function(surface, searchLength, position1, position2, ugName)
    local area = Utils.CalculateBoundingBoxFrom2Points(position1, position2)
    if area.left_top.x == area.right_bottom.x then
        area.left_top.y = area.left_top.y - searchLength
        area.right_bottom.y = area.right_bottom.y + searchLength
    else
        area.left_top.x = area.left_top.x - searchLength
        area.right_bottom.x = area.right_bottom.x + searchLength
    end
    local ugEntities = EntityHandling.SearchForNearbyUndergrounds(surface, ugName, area)
    for _, ugEntity in pairs(ugEntities) do
        if global.entityHandling.undergroundEntityIdToRouteId[ugEntity.unit_number] == nil then
            local otherEndUgEntity = ugEntity.neighbours
            if otherEndUgEntity ~= nil then
                EntityHandling.HandleNewUndergroundRoute(ugEntity, otherEndUgEntity)
            end
        end
    end
end

return EntityHandling
