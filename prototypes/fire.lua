local Utils = require("utility/utils")

local fireFlame = data.raw["fire"]["fire-flame"]
local fireFlameOnTree = data.raw["fire"]["fire-flame-on-tree"]
local fireEntity = Utils.DeepCopy(fireFlame)
fireEntity.name = "belt_braid_sinner-fire"
fireEntity.initial_lifetime = 300
fireEntity.spread_delay = 120
fireEntity.spread_delay_deviation = 2
fireEntity.smoke_source_pictures = fireFlameOnTree.smoke_source_pictures
fireEntity.smoke = fireFlameOnTree.smoke
fireEntity.smoke[1].name = "belt_braid_sinner-fire_smoke"
fireEntity.smoke[1].frequency = fireEntity.smoke[1].frequency / 2
fireEntity.smoke_fade_in_duration = fireFlameOnTree.smoke_fade_in_duration
fireEntity.smoke_fade_out_duration = fireFlameOnTree.smoke_fade_out_duration
fireEntity.tree_dying_factor = fireFlameOnTree.tree_dying_factor
fireEntity.damage_per_tick = {amount = 2, type = "fire"}
fireEntity.maximum_damage_multiplier = 0
data:extend({fireEntity})

local fireSmoke = Utils.DeepCopy(data.raw["trivial-smoke"]["fire-smoke-without-glow"])
fireSmoke.name = "belt_braid_sinner-fire_smoke"
fireSmoke.show_when_smoke_off = true
data:extend({fireSmoke})
