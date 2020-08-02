----------------------------------------------------------------------
-- Gundu
--a small fish
--[[
filter feeds in sunlit waters
]]
---------------------------------------------------------------------

local random = math.random


--energy
local energy_max = 8000--secs it can survive without food
local energy_egg = energy_max/4 --energy that goes to egg
local egg_timer  = 60*25
local young_per_egg = 8		--will get this/energy_egg starting energy

local lifespan = energy_max * 6



-----------------------------------
local function brain(self)

	--die from damage
	if not animals.core_hp_water(self) then
		return
	end

	if mobkit.timer(self,1) then

		local pos = mobkit.get_stand_pos(self)

		local age, energy = animals.core_life(self, lifespan, pos)
		--die from exhaustion or age
		if not age then
			return
		end


		local prty = mobkit.get_queue_priority(self)
		-------------------
		--High priority actions
		local pred

		if prty < 50 then

			--Threats
			local plyr = mobkit.get_nearby_player(self)
			if plyr then
				animals.fight_or_flight_plyr_water(self, plyr, 55, 0.01)
			end

			pred = animals.predator_avoid_water(self, 55, 0.01)

		end


		----------------------
		--Low priority actions
		if prty < 20 then


			--social behaviour
			local rival
			if random() <0.75 then
				animals.flock(self, 25, 1.5, self.max_speed/4)
			elseif random() <0.05 then
				rival = animals.territorial_water(self, energy, false)
			end


			--feeding
			local light = minetest.get_node_light(pos, 0.5)
			if light >= 7 then
				if energy < energy_max then
					energy = energy + 2.1
				end
				mobkit.hq_aqua_roam(self,10, random(0.5, self.max_speed/2))
			elseif random() < 0.2 then
				--rise
				local vel = self.object:get_velocity()
				vel.y = vel.y+0.1
				self.object:set_velocity(vel)
				mobkit.hq_aqua_roam(self,10, random(1, self.max_speed))
			end


			--hide during the darkest part of night
			if random() < 0.01 then
				local tod = minetest.get_timeofday()
				if tod <0.1 or tod >0.9 then
					--sink
					local vel = self.object:get_velocity()
					vel.y = vel.y-0.2
					self.object:set_velocity(vel)
					mobkit.hq_aqua_roam(self,15,0.1)
				end
			end

			--reproduction
			--asexual parthogenesis, eggs
			if random() < 0.01
			and not rival
			and not pred
			and self.hp >= self.max_hp
			and energy >= energy_egg *2 then
				energy = animals.place_egg(pos, "animals:gundu_eggs", energy, energy_egg, 'nodes_nature:salt_water_source')
			end

		end

		-------------------
		--generic behaviour
		if mobkit.is_queue_empty_high(self) then
			mobkit.animate(self,'def')
			mobkit.hq_aqua_roam(self,10,1)
		end


		-----------------
		--housekeeping
		--save energy, age
		mobkit.remember(self,'energy',energy)
		mobkit.remember(self,'age',age)

	end
end






---------------
-- the CREATURE
---------------

--eggs
minetest.register_node("animals:gundu_eggs", {
	description = 'Gundu Eggs',
	tiles = {"animals_gundu_eggs.png"},
	stack_max = minimal.stack_max_bulky,
	groups = {snappy = 3},
	sounds = nodes_nature.node_sound_defaults(),
	on_use = function(itemstack, user, pointed_thing)
		--hp_change, thirst_change, hunger_change, energy_change, temp_change, replace_with_item
		return HEALTH.use_item(itemstack, user, 0, 12, 120, -60, 0)
	end,
	on_construct = function(pos)
		minetest.get_node_timer(pos):start(math.random(egg_timer,egg_timer*2))
	end,
	on_timer =function(pos, elapsed)
		return animals.hatch_egg(pos, 'nodes_nature:salt_water_source', 'nodes_nature:salt_water_flowing', "animals:gundu", energy_egg, young_per_egg)
	end,
})




----------------------------------------------

--The Animal
minetest.register_entity("animals:gundu",{
	--core
	physical = true,
	collide_with_objects = true,
	collisionbox = {-0.15, -0.15, -0.15, 0.15, 0.15, 0.15},
	visual = "mesh",
	mesh = "animals_gundu.b3d",
	textures = {"animals_gundu.png"},
	visual_size = {x = 9, y = 9},
	makes_footstep_sound = false,
	timeout = 0,

	--damage
	max_hp = 100,
	lung_capacity = 20,
	min_temp = 1,
	max_temp = 35,

	--interaction
	predators = {"animals:sarkamos"},
	rivals = {"animals:gundu"},
	friends = {"animals:gundu"},
	--prey = {"animals:impethu"},

	on_step = mobkit.stepfunc,
	on_activate = mobkit.actfunc,
	get_staticdata = mobkit.statfunc,
	logic = brain,
	-- optional mobkit props
	-- or used by built in behaviors
	--physics = [function user defined] 		-- optional, overrides built in physics
	animation = {
		def={range={x=1,y=35},speed=30,loop=true},
		fast={range={x=1,y=35},speed=60,loop=true},
		stand={range={x=36,y=75},speed=20,loop=true},
	},
	sounds = {
		flee = {
			name = "animals_water_swish",
			gain={0.5, 1.5},
			fade={0.5, 1.5},
			pitch={0.5, 1.5},
		},
		call = {
			name = "animals_gundu_call",
			gain={0.01, 0.1},
			fade={0.5, 1.5},
			pitch={0.6, 1.2},
		},
		punch = {
			name = "animals_punch",
			gain={0.5, 1},
			fade={0.5, 1.5},
			pitch={0.5, 1.5},
		},
	},

	--movement
	springiness=0.5,
	buoyancy = 1,
	max_speed = 5,					-- m/s
	jump_height = 1.5,				-- nodes/meters
	view_range = 5,					-- nodes/meters

	--attack
	attack={range=0.3, damage_groups={fleshy=1}},
	armor_groups = {fleshy=100},

	--on actions
	drops = {
		{name = "animals:carcass_fish_small", chance = 1, min = 1, max = 1,},
	},
	on_punch=function(self, puncher, time_from_last_punch, tool_capabilities, dir)
		animals.on_punch_water(self, tool_capabilities, puncher, 55, 0.01)
	end,
	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then
			return
		end
		animals.stun_catch_mob(self, clicker, 0.1)
	end,
})


--spawn egg (i.e. live animal in inventory)
animals.register_egg("animals:gundu", "Live Gundu", "animals_gundu_item.png", minimal.stack_max_medium/2, energy_egg)
