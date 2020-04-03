local EntityHandling = require("scripts/entity_handling")
local Sinned = require("scripts/sinned")
local EventScheduler = require("utility/event-scheduler")

local function CreateGlobals()
    EntityHandling.CreateGlobals()
    Sinned.CreateGlobals()
end

local function OnLoad()
    --Any Remote Interface registration calls can go in here or in root of control.lua
    EntityHandling.OnLoad()
    Sinned.OnLoad()
end

local function OnSettingChanged(event)
    Sinned.OnSettingChanged(event)
end

local function OnStartup()
    CreateGlobals()
    OnLoad()
    OnSettingChanged(nil)

    EntityHandling.OnStartup()
end

script.on_init(OnStartup)
script.on_configuration_changed(OnStartup)
script.on_event(defines.events.on_runtime_mod_setting_changed, OnSettingChanged)
script.on_load(OnLoad)
EventScheduler.RegisterScheduler()
