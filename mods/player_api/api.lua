-- Minetest 0.4 mod: player
-- See README.txt for licensing and other information.

player_api = {}

-- Player animation blending
-- Note: This is currently broken due to a bug in Irrlicht, leave at 0
local animation_blend = 0

player_api.registered_models = { }
player_api.registered_skins = { }
-- Local for speed.
local models = player_api.registered_models
local skins = player_api.registered_skins
local registered_skin_modifiers = {}
local registered_on_skin_change = {}

function player_api.register_model(name, def)
	models[name] = def
end

function player_api.register_skin(name, def)
	def.name = name
	skins[name] = def
end

function player_api.register_skin_modifier(modifier_func)
	table.insert(registered_skin_modifiers, modifier_func)
end

function player_api.register_on_skin_change(modifier_func)
	table.insert(registered_on_skin_change, modifier_func)
end

-- Player stats and animations
local player_model = {}
local player_textures = {}
local skin_textures = {}
local player_skin = {}
local player_anim = {}
local player_sneak = {}
player_api.player_attached = {}

function player_api.get_animation(player)
	local name = player:get_player_name()
	return {
		model = player_model[name],
		textures = player_textures[name],
		skin_textures = skin_textures[name],
		animation = player_anim[name],
	}
end

-- Called when a player's appearance needs to be updated
function player_api.set_model(player, model_name)
	local name = player:get_player_name()
	local model = model_name and models[model_name]
	if not model then
		model_name = player_api.default_model
		model = models[model_name]
	end

	player:set_properties({
		mesh = model_name,
		textures = player_textures[name] or model.textures,
		visual = model.visual or "mesh",
		visual_size = model.visual_size or {x = 1, y = 1},
		collisionbox = model.collisionbox or {-0.3, 0.0, -0.3, 0.3, 1.7, 0.3},
		stepheight = model.stepheight or 0.6,
		eye_height = model.eye_height or 1.47,
	})
	player_api.set_animation(player, "stand")
	player_model[name] = model_name
end

-- Apply textures to player model
function player_api.update_textures(player)
	local name = player:get_player_name()
	local model = models[player_model[name]]
	local skin = skins[player_skin[name]]

	local textures
	if skin.textures then
		textures = table.copy(skin.textures)
		skin_textures[name] = skin.textures
	elseif skin.texture then
		textures = { skin.texture }
		skin_textures[name] = { skin.texture }
	else
		textures = table.copy(model.textures)
		skin_textures[name] = model.textures
	end

	for _, modifier_func in ipairs(registered_skin_modifiers) do
		textures = modifier_func(textures, player, player_model[name], player_skin[name]) or textures
	end

	if model.skin_modifier then
		textures = model:skin_modifier(textures, player, player_model[name], player_skin[name]) or textures
	end
--print("set skin textures", dump(textures))
	player_textures[name] = textures
	player:set_properties({textures = textures})
end

-- Called when a player's skin is changed
function player_api.set_skin(player, skin_name, is_default, is_force)
	local name = player:get_player_name()
	local skin = skins[skin_name]
	if not skin then
		skin_name = player_api.default_skin
		skin = skins[skin_name]
		is_default = true
	end
	if player_skin[name] == skin_name and not is_force then
		return
	end

	-- Handle skin model
	player_api.set_model(player, skin.model_name)

	-- Handle skin textures
	player_skin[name] = skin_name
	player_api.update_textures(player)

	if not is_default then
		local meta = player:get_meta()
		meta:set_string("player_api:skin", skin_name)
	end

	for _, modifier_func in ipairs(registered_on_skin_change) do
		modifier_func(player, player_model[name], skin_name)
	end
end

-- Get current assigned or default skin for player
function player_api.get_skin(player)
	local meta = player:get_meta()
	local assigned_skin = meta:get_string("player_api:skin")
	if assigned_skin then
		return assigned_skin, false
	end
	local skinname = "player_"..player:get_player_name():lower()
	if player_api.registered_skins[skinname] then
		return skinname, true
	end
	return player_api.default_skin, true
end

local textures_skin_suffix_blacklist = {
	preview = true,
	back = true
}
player_api.textures_skin_suffix_blacklist = textures_skin_suffix_blacklist

-- Read and analyze data in textures and metadata folder and register them
function player_api.read_textures_and_meta(hook)
	local modpath = minetest.get_modpath(minetest.get_current_modname())
	for _, fn in pairs(minetest.get_dir_list(modpath..'/textures/')) do
		local nameparts = fn:sub(1, -5):split("_")
		local prefix = nameparts[1]
		if ( prefix == 'player' and nameparts[2] or prefix == 'character' ) then
			if not textures_skin_suffix_blacklist[nameparts[#nameparts]] then

				local skin = {texture = fn}
				local skin_id = table.concat(nameparts,'_')

				-- get metadata from file
				local file = io.open(modpath.."/meta/"..skin_id..".txt", "r")
				if file then
					local data = minetest.deserialize("return {" .. file:read('*all') .. "}")
					file:close()
					if data then
						for k, v in pairs(data) do
							skin[k] = v
						end
						if data.name and not data.description then -- name is reserved for registration skin_id
							skin.description = data.name
						end
					end
				end

				-- Check if preview exists
				local file2 = io.open(modpath.."/textures/"..skin_id.."_preview.png", "r")
				if file2 then
					file2:close()
					skin.preview = skin_id.."_preview.png"
				end

				-- Check for private
				if prefix == "player" then
					skin.playername = nameparts[2]
				end

				if not skin.description then
					if nameparts[2] then
						table.remove(nameparts, 1)
					end
					skin.description = table.concat(nameparts,' ')
				end

				-- process hook
				if hook then
					hook(modpath..'/textures/'..fn, skin)
				end
				player_api.register_skin(skin_id, skin)
			end
		end
	end
end

function player_api.set_animation(player, anim_name, speed)
	local name = player:get_player_name()
	if player_anim[name] == anim_name then
		return
	end
	local model = player_model[name] and models[player_model[name]]
	if not (model and model.animations and model.animations[anim_name]) then
		return
	end
	local anim = model.animations[anim_name]
	player_anim[name] = anim_name
	player:set_animation(anim, speed or model.animation_speed, animation_blend)
end

function player_api.init_on_joinplayer(player)
	player_api.player_attached[player:get_player_name()] = false
	player_api.set_skin(player, player_api.get_skin(player), true, true)
	player:set_local_animation(
		{x = 0,   y = 79},
		{x = 168, y = 187},
		{x = 189, y = 198},
		{x = 200, y = 219},
		30
	)
	player:hud_set_hotbar_image("gui_hotbar.png")
	player:hud_set_hotbar_selected_image("gui_hotbar_selected.png")
end

minetest.register_on_joinplayer(function(player)
	-- Wrapped call to be able to redefine the init function
	player_api.init_on_joinplayer(player)
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player_model[name] = nil
	player_anim[name] = nil
	player_textures[name] = nil
	skin_textures[name] = nil
	player_skin[name] = nil
end)

-- Localize for better performance.
local player_set_animation = player_api.set_animation
local player_attached = player_api.player_attached

-- Prevent knockback for attached players
local old_calculate_knockback = minetest.calculate_knockback
function minetest.calculate_knockback(player, ...)
	if player_attached[player:get_player_name()] then
		return 0
	end
	return old_calculate_knockback(player, ...)
end

-- Check each player and apply animations
minetest.register_globalstep(function(dtime)
	for _, player in pairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local model_name = player_model[name]
		local model = model_name and models[model_name]
		if model and not player_attached[name] then
			local controls = player:get_player_control()
			local walking = false
			local animation_speed_mod = model.animation_speed or 30

			-- Determine if the player is walking
			if controls.up or controls.down or controls.left or controls.right then
				walking = true
			end

			-- Determine if the player is sneaking, and reduce animation speed if so
			if controls.sneak then
				animation_speed_mod = animation_speed_mod / 2
			end

			-- Apply animations based on what the player is doing
			if player:get_hp() == 0 then
				player_set_animation(player, "lay")
			elseif walking then
				if player_sneak[name] ~= controls.sneak then
					player_anim[name] = nil
					player_sneak[name] = controls.sneak
				end
				if controls.LMB then
					player_set_animation(player, "walk_mine", animation_speed_mod)
				else
					player_set_animation(player, "walk", animation_speed_mod)
				end
			elseif controls.LMB then
				player_set_animation(player, "mine")
			else
				player_set_animation(player, "stand", animation_speed_mod)
			end
		end
	end
end)
