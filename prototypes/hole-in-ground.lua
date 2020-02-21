local Constants = require("constants")
local Colors = require("utility/colors")
local Utils = require("utility/utils")

local explosionOffGrid = Utils.DeepCopy(data.raw["explosion"]["explosion"])
table.insert(explosionOffGrid.flags, "placeable-off-grid")
explosionOffGrid.name = "belt_braid_sinner-explosion"
explosionOffGrid.animations[1] = explosionOffGrid.animations[2] --remove the smaller graphic in our case
explosionOffGrid.animations[2] = nil

data:extend(
    {
        explosionOffGrid,
        {
            type = "corpse",
            name = "belt_braid_sinner-hole_in_ground",
            flags = {"placeable-off-grid", "not-selectable-in-game"},
            ground_patch = {
                filename = Constants.AssetModName .. "/graphics/entity/hole_in_ground.png",
                width = 332,
                height = 240,
                scale = 0.25,
                shift = {0.1, 0}
            },
            time_before_shading_off = 3 * 60,
            time_before_removed = 9 * 60
        },
        {
            type = "trivial-smoke",
            name = "belt_braid_sinner-hole_in_ground_burst",
            flags = {"not-on-map"},
            animation = {
                filename = "__base__/graphics/entity/smoke-fast/smoke-fast.png",
                priority = "high",
                width = 50,
                height = 50,
                frame_count = 16,
                animation_speed = 0.25,
                scale = 1
            },
            render_layer = "building-smoke",
            affected_by_wind = false,
            movement_slow_down_factor = 0.96,
            duration = 64,
            fade_away_duration = 20,
            show_when_smoke_off = true,
            color = Colors.burlywood
        },
        {
            type = "trivial-smoke",
            name = "belt_braid_sinner-hole_in_ground_linger",
            flags = {"not-on-map"},
            animation = {
                width = 152,
                height = 120,
                line_length = 5,
                frame_count = 60,
                animation_speed = 0.25,
                filename = "__base__/graphics/entity/smoke/smoke.png"
            },
            affected_by_wind = false,
            movement_slow_down_factor = 0,
            duration = 600,
            cyclic = true,
            fade_away_duration = 60,
            show_when_smoke_off = true,
            color = Colors.burlywood
        }
    }
)
