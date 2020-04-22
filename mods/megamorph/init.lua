-- Megamorph init.lua



megamorph = {}
local mod = megamorph
--local mod_name = 'megamorph'

minetest.set_mapgen_setting('mg_flags', "nodungeons", true)

mod.path = minetest.get_modpath(minetest.get_current_modname())
mod.world = minetest.get_worldpath()
mod.max_height = 31000
mod.morph_depth = -1
mod.registered_loot = {}

mod.time_overhead = 0
minetest.register_on_shutdown(function()
  print('Megamorph time overhead: '..mod.time_overhead)
end)



-- This table looks up nodes that aren't already stored.
mod.node = setmetatable({}, {
	__index = function(t, k)
		if not (t and k and type(t) == 'table') then
			return
		end

		t[k] = minetest.get_content_id(k)
		return t[k]
	end
})
local node = mod.node


----------------------------------------
--Realms
----------------------------------------

mod.registered_realms = {
  {name = 'geomoria', realm_minp = {x = -31000, y = -1000, z = -31000}, realm_maxp = {x = 31000, y = -120, z = 31000}},

}

---------------------------------------
--functions
---------------------------------------

----
function math.xor(a, b)
	local r = 0
	for i = 0, 31 do
		local x = a / 2 + b / 2
		if x ~= math.floor(x) then
			r = r + 2^i
		end
		a = math.floor(a / 2)
		b = math.floor(b / 2)
	end
	return r
end

-----
local fnv_offset = 2166136261
local fnv_prime = 16777619
function math.fnv1a(data)
	local hash = fnv_offset
	for _, b in pairs(data) do
		hash = math.xor(hash, b)
		hash = hash * fnv_prime
	end
	return hash
end

----
function mod.generate_map_seed()
	-- I use the fixed_map_seed by preference, since minetest 5.0.1
	--  gives the wrong seed to lua when a text map seed is used.
	-- By wrong, I mean that it doesn't match the seed used in the
	--  C code (the one displayed when you hit F5).

	local map_seed = minetest.get_mapgen_setting('fixed_map_seed')
	if map_seed == '' then
		return minetest.get_mapgen_setting('seed')
	else
		-- Just convert each letter into a byte of data.
		local bytes = {map_seed:byte(1, math.min(8, map_seed:len()))}
		local seed = 0
		local i = 1
		for _, v in pairs(bytes) do
			seed = seed + v * i
			i = i * 256
		end
		return seed
	end
end

-----
function mod.generate_block_seed(minp, map_seed)
	local seed = tonumber(map_seed or mod.map_seed)
	local data = {}

	while seed > 0 do
		table.insert(data, seed % 256)
		seed = math.floor(seed / 256)
	end

	for _, axis in pairs({'x', 'y', 'z'}) do
		table.insert(data, math.floor(minp[axis] + mod.max_height) % 256)
		table.insert(data, math.floor((minp[axis] + mod.max_height) / 256))
	end

	return math.fnv1a(data)
end


--for realms
function mod.cube_intersect(r1, r2)
  local axes = { 'x', 'y', 'z' }
	local minp, maxp = {}, {}
	for _, axis in pairs(axes) do
		minp[axis] = math.max(r1.minp[axis], r2.minp[axis])
		maxp[axis] = math.min(r1.maxp[axis], r2.maxp[axis])

		if minp[axis] > maxp[axis] then
			return
		end
	end
	return minp, maxp
end


--
function vector.contains(minp, maxp, x, y, z)
	-- Don't create a vector here. It would be slower.
	if y and z then
		if minp.x > x or maxp.x < x
		or minp.y > y or maxp.y < y
		or minp.z > z or maxp.z < z then
			return
		end
	else
		for _, a in pairs(axes) do
			if minp[a] > x[a] or maxp[a] < x[a] then
				return
			end
		end
	end

	return true
end



-- These nodes will have their on_construct method called
--  when placed by the mapgen (to start timers).
mod.construct_nodes = {}
function mod.add_construct(node_name)
	mod.construct_nodes[node[node_name]] = true
end

----
function mod.do_on_constructs(params)
	-- Call on_construct methods for nodes that request it.
	-- This is mainly useful for starting timers.
	local data, area = params.data, params.area
	for i, n in ipairs(data) do
		if mod.construct_nodes[n] then
			local pos = area:position(i)
			local node_name = minetest.get_name_from_content_id(n)
			if minetest.registered_nodes[node_name] and minetest.registered_nodes[node_name].on_construct then
				minetest.registered_nodes[node_name].on_construct(pos)
			else
				local timer = minetest.get_node_timer(pos)
				if timer then
					timer:start(math.random(100))
				end
			end
		end
	end
end



--Loot

function mod.fill_chest(pos)
	local value = math.random(20)
	if pos.y < -100 then
		local depth = math.log(pos.y / -100)
		depth = depth * depth * depth * 10
		value = value + math.floor(depth)
	end
	local loot = mod.get_loot(value)

	local inv = minetest.get_inventory({ type = 'node', pos = pos })
	if inv then
		for _, it in pairs(loot) do
			if inv:room_for_item('main', it) then
				inv:add_item('main', it)
			end
		end
	end
end


function mod.get_loot(avg_value)
	local value = avg_value or 10
	local loot = {}
	local jump = 3

	if avg_value > 100 then
		jump = 4
	end

	while value > 0 do
		local r = 1
		local its = {}

		for i = 1, 12 do
			if math.random(5) < jump then
				r = r + 1
			else
				break
			end
		end

		while #its < 1 do
			for _, tr in pairs(mod.registered_loot) do
				if tr.rarity == r then
					table.insert(its, tr)
				end
			end
			r = r - 1
		end

		if #its > 0 then
			local it = its[math.random(#its)]
			local it_str = it.name
			local num = it.number.min
			local tool = minetest.registered_tools[it.name] ~= nil
			if tool or it.number.max > num then
				num = math.random(num, it.number.max)
				it_str = it_str .. ' ' .. num
				if tool then
					it_str = it_str .. ' ' .. math.floor(65000 * (math.random(10) + 5) / 20)
				end
			end
			table.insert(loot, it_str)
			value = value - 3 ^ r
		end
	end

	return loot
end



function mod.register_loot(def, force)
	if not def.name or not def.rarity
	or not minetest.registered_items[def.name]
	or (not force and mod.registered_loot[def.name]) then
		print(mod_name .. ': not (re)registering ' .. (def.name or 'nil'))
		--print(dump(def))
		return
	end

	if not def.level then
		def.level = 1
	end

	if not def.number then
		def.number = {}
	end
	if not def.number.min then
		def.number.min = 1
	end
	if not def.number.max then
		def.number.max = def.number.min
	end

	mod.registered_loot[def.name] = def
end



minetest.after(0, function()
	local options = {}
  --level, rarity, max stack (nil for unstackables)
  --not sure what, if anything, level does (original seems to have all at 1)
  --Examples from original:
	-- 1 wood / stone
	-- 2 coal
	-- 3 iron
	-- 4 gold
	-- 5 diamond
	-- 6 mese
  --[[
  options['default:desert_cobble']      =  {  1,  1,   20     }
  options['default:coal_lump']         =  {  1,  2,    10    }
  options['map:mapping_kit']            =  { 1, 4, nil }
  options['default:pick_diamond']      =  {  1,  6,   nil   }
  ]]

  --Only those items whch could survive centuries.
  --e.g. no food, wood/fabric etc rare

  --raw materials (rarity 1)
  options['nodes_nature:granite_boulder'] =  { 1, 1, 2 }
  options['nodes_nature:basalt_boulder'] =  { 1, 1, 2 }
  options['nodes_nature:limestone_boulder'] =  { 1, 1, 2 }
  options['nodes_nature:ironstone_boulder'] =  { 1, 1, 2 }
  options['nodes_nature:gravel'] =  { 1, 1, 2 }
  options['nodes_nature:sand'] =  { 1, 1, 2 }
  options['nodes_nature:silt'] =  { 1, 1, 2 }
  options['nodes_nature:clay'] =  { 1, 1, 2 }
  options['nodes_nature:loam'] =  { 1, 1, 2 }


  --cheap processed materials (rarity 2)
  options['nodes_nature:granite_brick'] =  { 1, 2, 4 }
  options['nodes_nature:basalt_brick'] =  { 1, 2, 4 }
  options['nodes_nature:limestone_brick'] =  { 1, 1, 4 }
  options['nodes_nature:granite_block'] =  { 1, 2, 4 }
  options['nodes_nature:basalt_block'] =  { 1, 2, 4 }
  options['nodes_nature:limestone_block'] =  { 1, 2, 4 }


  --medium processed materials, cheap tools (rarity 3)
  options['tech:mortar_pestle_basalt'] =  { 1, 3, nil }
  options['tech:mortar_pestle_granite'] =  { 1, 3, nil }
  options['tech:iron_ingot'] =  { 1, 3, 4 }
  options['tech:clay_water_pot'] =  { 1, 3, nil }
  options['tech:clay_storage_pot'] =  { 1, 3, nil }
  options['tech:clay_oil_lamp_empty'] =  { 1, 3, nil }

  --costly processed materials, expensive tools, (rarity 4)
  options['tech:anvil'] =  { 1, 4, nil }
  options['tech:mace_iron'] =  { 1, 4, nil }


  --low level artifacts (rarity 5), non-durables
  options['artifacts:light_meter'] =  { 1, 5, nil }
  options['artifacts:thermometer'] =  { 1, 5, nil }
  options['artifacts:temp_probe'] =  { 1, 5, nil }
  options['artifacts:mapping_kit'] =  { 1, 5, nil }
  options['tech:stick'] =  { 1, 5, 1 }
  options['tech:fine_fabric'] =  { 1, 5, nil }
  options['tech:paint_lime_white'] =  { 1, 5, nil }
  options['tech:paint_glow_paint'] =  { 1, 5, nil }
  --options['tech:carpentry_bench'] =  { 1, 5, nil }
  --options['tech:masonry_bench'] =  { 1, 5, nil }
  --options['tech:spinning_wheel'] =  { 1, 5, nil }
  --options['tech:loom'] =  { 1, 5, nil }

  --high level artifacts (rarity 6)
  --options['artifacts:?'] =  { 1, 6, nil }


	for name, d in pairs(options) do
		if minetest.registered_items[name] then
			local def = {
				level = d[1],
				rarity = d[2],
				name = name,
				number = {
					min = 1,
					max = d[3] or 1,
				},
			}
			mod.register_loot(def, true)
		end
	end

	for name, desc in pairs(minetest.registered_items) do
		if name:find('^wool:') then
			local def = {
				level = 1,
				rarity = 100,
				name = name,
				number = {
					min = 1,
					max = 10,
				},
			}
		end
	end
end)

--[[

do
	local orig_loot_reg = dungeon_loot.register
	dungeon_loot.register = function(def)
		if not def or def.chance <= 0 then
			return
		end

		mod.register_loot({
			name = def.name,
			rarity = math.ceil(1 / 2 / def.chance),
			level = def.level or 1,
			number = {
				min = def.count[1] or 1,
				max = def.count[2] or 1,
			},
		})

		orig_loot_reg(def)
	end
end
]]


--------------------------------------
dofile(mod.path .. '/geomorph.lua')
dofile(mod.path .. '/plans.lua')
dofile(mod.path .. '/mapgen.lua')
