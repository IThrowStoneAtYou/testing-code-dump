-- ModuleScript: bot_controller
-- Returns create(bot_model, settings) -> controller
-- Lightweight controller for NPC bots: movement via NoobPath, shooting via FastCast.
-- top-level overview of what this module does

local module = {}

-- services
local replicatedstorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")
local runservice = game:GetService("RunService")
local collectionservice = game:GetService("CollectionService")
local debris = game:GetService("Debris")
local players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local BOT_GROUP = "Bots"

-- modules 
local fastcast = require(replicatedstorage.Modules:WaitForChild("FastCastRedux"))
local noobpath = require(replicatedstorage.Modules:WaitForChild("NoobPath"))
local noobpath_factory = require(replicatedstorage.Modules:WaitForChild("noobpath_factory"))
local movementAnim = require(replicatedstorage.Modules:WaitForChild("movementAnim"))

local tracer_event = replicatedstorage.Remotes.Replication:WaitForChild("BotsBulletFx")

-- shared asset references
local tracer_template = replicatedstorage:WaitForChild("FX"):WaitForChild("Tracer")
local tracer_container = workspace:WaitForChild("Tracers")
local fx_folder = replicatedstorage:WaitForChild("FX"):WaitForChild("Impact")
local fx_sound_root = replicatedstorage:WaitForChild("FX"):WaitForChild("ImpactSound")
local bot_stuff_root = replicatedstorage:WaitForChild("FX"):WaitForChild("Bot_stuff")

-- registry for controllers so global events can refresh filters
local controllers = {}

-- schedule update of bullet filters for all controllers (deferred, safe)
local function schedule_update_all_filters()
	task.defer(function()
		for _, ctrl in ipairs(controllers) do
			if ctrl and ctrl.update_bullet_filter then
				pcall(function() ctrl:update_bullet_filter() end)
			end
		end
	end)
end

-- refresh filters when players spawn/leave so teams are excluded from bullets
players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		schedule_update_all_filters()
	end)
end)

players.PlayerRemoving:Connect(function()
	schedule_update_all_filters()
end)

local _next_cast_id = 0
local function generate_cast_id()
	_next_cast_id += 1
	return _next_cast_id
end

-- create a controller for a bot model (requires settings table)
function module.create(bot_model, settings)
	assert(bot_model and bot_model:IsA("Model"), "bot_controller.create: bot_model must be a Model")
	assert(type(settings) == "table", "bot_controller.create: settings table required")

	-- if a controller already exists for this bot, return it to avoid double-creation
	for _, existing in ipairs(controllers) do
		if existing and existing.bot == bot_model then
			-- return existing controller instead of creating a duplicate
			return existing
		end
	end

	local self = {}
	self.bot = bot_model
	self.settings = settings
	self.alive = true
	self.active_casts = {} -- stores {id = cast_id, cast = active_cast}
	self.heartbeat_conn = nil
	self.path = nil
	self.target_char = nil
	self.path_mode = "aggressive"
	self.last_path_update_time = 0
	self.last_goal = nil
	self.current_ammo = self.settings.mag_size or 0
	self.reloading = false
	self.last_fire_time = 0
	self._cosmetics = {} -- map active_cast -> cosmetic object (if any)

	-- required bot parts
	local humanoid = self.bot:WaitForChild("Humanoid")
	local humanoid_root = self.bot:WaitForChild("HumanoidRootPart")
	local handle = self.bot:WaitForChild("Handle")
	local firing_point = handle:WaitForChild("FiringPoint")

	-- assign team attribute automatically if provided in settings
	if self.settings.team then
		humanoid:SetAttribute("Team", self.settings.team)
	end

	-- animator + animation track helper
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function create_anim_track(animator_obj, anim_id)
		-- create and return an AnimationTrack for given animation id
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(anim_id)
		return animator_obj:LoadAnimation(anim)
	end

	local idle_anim_track = create_anim_track(animator, self.settings.idle_animation or 0)
	local fire_anim_track = create_anim_track(animator, self.settings.fire_animation or 0)
	local reload_anim_track = create_anim_track(animator, self.settings.reload_animation or 0)
	pcall(function() idle_anim_track:Play() end)

	local anim_controller = movementAnim.create({
		humanoid = humanoid,
		idle_anim_id = 180435571,
		walk_anim_id = 180426354
	})

	anim_controller:start()
	self._anim_controller = anim_controller

	-- create collision group if missing (keep bots not colliding with themselves)
	pcall(function()
		local found = false
		for _, g in ipairs(PhysicsService:GetCollisionGroups()) do
			if g.name == BOT_GROUP or g.Name == BOT_GROUP then
				found = true
				break
			end
		end
		if not found then
			PhysicsService:CreateCollisionGroup(BOT_GROUP)
			PhysicsService:CollisionGroupSetCollidable(BOT_GROUP, BOT_GROUP, false)
		end
	end)

	-- assign collision group and ensure parts are unanchored (do not call SetNetworkOwner to avoid engine warnings)
	for _, part in ipairs(self.bot:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function()
				PhysicsService:SetPartCollisionGroup(part, BOT_GROUP)
			end)
			-- un-anchor to allow physics; avoid touching network ownership API
			pcall(function() part.Anchored = false end)
		end
	end

	-- fastcast setup (per controller) and cosmetic tracer behavior
	local caster = fastcast.new()
	caster.VisualizeCasts = true
	caster.SimulateBeforePhysics = false
	caster.WorldRoot = workspace

	local behavior = fastcast.newBehavior()
	behavior.MaxDistance = self.settings.max_distance or 4000
	behavior.CosmeticBulletTemplate = nil
	behavior.CosmeticBulletContainer = nil
	behavior.AutoIgnoreContainer = true

	self._caster = caster
	self._behavior = behavior

	-- when humanoid dies, stop controller and clear state (does not remove model itself)
	humanoid.Died:Connect(function()
		if not self.alive then return end

		self.alive = false
		self.reloading = false

		-- stop heartbeat
		if self.heartbeat_conn then
			self.heartbeat_conn:Disconnect()
			self.heartbeat_conn = nil
		end

		-- stop pathing
		if self.path then
			self.path:Stop()
			self.path = nil
		end

		-- stop anim
		if anim_controller then
			anim_controller:stop()
		end

		-- terminate active casts cleanly
		for i = #self.active_casts, 1, -1 do
			local entry = self.active_casts[i]
			if entry and entry.cast and entry.cast.Terminate then
				pcall(function() entry.cast:Terminate() end)
			end
			self.active_casts[i] = nil
		end

		-- destroy any cosmetics left
		for cast_key, cos in pairs(self._cosmetics) do
			pcall(function()
				if cos and cos.Parent then
					cos:Destroy()
				end
			end)
			self._cosmetics[cast_key] = nil
		end
	end)

	-- team helpers use humanoid attribute "Team"
	local function get_team_from_model(model)
		if not model then return nil end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum then return nil end
		return hum:GetAttribute("Team")
	end

	local function is_same_team(char_a, char_b)
		if not char_a or not char_b then return false end
		local team_a = get_team_from_model(char_a)
		local team_b = get_team_from_model(char_b)
		if not team_a or not team_b then return false end
		return team_a == team_b
	end

	-- collect instances to ignore in raycasts (teammates, self, tracer container)
	local function build_team_ignore_list()
		local ignore = { self.bot, tracer_container }
		local my_team = get_team_from_model(self.bot)
		if not my_team then return ignore end

		-- ignore friendly players
		for _, plr in ipairs(players:GetPlayers()) do
			local char = plr.Character
			if char and get_team_from_model(char) == my_team then
				table.insert(ignore, char)
			end
		end

		-- ignore friendly bots in workspace.bots
		local bot_folder = workspace:FindFirstChild("bots")
		if bot_folder then
			for _, bot_model in ipairs(bot_folder:GetChildren()) do
				if bot_model ~= self.bot and get_team_from_model(bot_model) == my_team then
					table.insert(ignore, bot_model)
				end
			end
		end

		return ignore
	end

	-- expose bullet filter update (makes FastCast ignore teammates)
	function self:update_bullet_filter()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		params.FilterDescendantsInstances = build_team_ignore_list()
		-- attach to behavior safely
		self._behavior.RaycastParams = params 
	end

	-- initialize bullet filter safely
	local success, err = pcall(function()
		self:update_bullet_filter()
	end)

	if not success then
		warn("Failed to update bullet filter:", err)
	end

	-- utility to find humanoid from any instance (returns humanoid or nil)
	local function get_humanoid_from_instance(inst)
		if not inst then return nil end
		local parent = inst.Parent
		if parent then
			local hum = parent:FindFirstChildOfClass("Humanoid")
			if hum then return hum end
		end
		local ancestor_model = inst:FindFirstAncestorOfClass("Model")
		if ancestor_model then
			return ancestor_model:FindFirstChildOfClass("Humanoid")
		end
		return nil
	end

	-- clone folder contents into a parent
	local function clone_folder_contents(source_folder, target_parent)
		for _, child in ipairs(source_folder:GetChildren()) do
			child:Clone().Parent = target_parent
		end
	end

	-- pick a random subfolder variant and clone its contents - used for outfit/accessory variant application
	local function random_subfolder_clone(category_name, bot_model)
		local category_folder = bot_stuff_root:FindFirstChild(category_name)
		if not category_folder then
			return
		end

		local variant_name = settings[category_name]
		if not variant_name then
			return
		end

		local variant_folder = category_folder:FindFirstChild(variant_name)
		if not variant_folder then
			return
		end

		local subfolders = {}
		for _, child in ipairs(variant_folder:GetChildren()) do
			if child:IsA("Folder") then
				table.insert(subfolders, child)
			end
		end

		if #subfolders == 0 then
			return
		end

		local chosen = subfolders[math.random(1, #subfolders)]
		clone_folder_contents(chosen, bot_model)
	end

	random_subfolder_clone("Outfit", bot_model)
	random_subfolder_clone("Accessory", bot_model)

	-- compute a spread direction biased by accuracy (returns unit vector)
	local function random_spread_direction(direction)
		local spread_deg = self.settings.bullet_spread or 2
		local spread_rad = math.rad(spread_deg)

		local accuracy = math.clamp(self.settings.accuracy or 0.8, 0, 1)

		local up = Vector3.new(0,1,0)
		if math.abs(direction:Dot(up)) > 0.999 then
			up = Vector3.new(1,0,0)
		end

		local right = direction:Cross(up).Unit
		local forward = right:Cross(direction).Unit

		local u = math.random()
		local v = math.random()

		local theta = math.acos(1 - u * (1 - math.cos(spread_rad)) * (1 - accuracy))
		local phi = 2 * math.pi * v

		local x = math.sin(theta) * math.cos(phi)
		local y = math.sin(theta) * math.sin(phi)
		local z = math.cos(theta)

		local world_vec = (right * x) + (forward * y) + (direction * z)
		return world_vec.Unit
	end

	-- reload sequence (blocks firing), plays animation and sound
	local function do_reload()
		if self.reloading then return end
		self.reloading = true
		pcall(function() reload_anim_track:Play() end)

		local reload_sound = Instance.new("Sound", handle)
		reload_sound.SoundId = "rbxassetid://" .. tostring(self.settings.reload_sound_id or 0)
		reload_sound.Volume = self.settings.reload_sound_volume or 0.2

		reload_sound.RollOffMode = Enum.RollOffMode.Linear
		reload_sound.RollOffMinDistance = 5
		reload_sound.RollOffMaxDistance = 50

		reload_sound:Play()
		debris:AddItem(reload_sound, 5)

		task.spawn(function()
			task.wait(self.settings.reload_speed or 1)
			self.current_ammo = self.settings.mag_size or 0
			self.reloading = false
		end)
	end

	-- play a 3D impact sound at the world position
	local function play_impact_sound(position, impact_type)
		local folder = fx_sound_root:FindFirstChild(impact_type) or fx_sound_root:FindFirstChild("Hit")
		if not folder then return end

		local sounds = {}
		for _, s in ipairs(folder:GetChildren()) do
			if s:IsA("Sound") then
				table.insert(sounds, s)
			end
		end
		if #sounds == 0 then return end

		local chosen = sounds[math.random(1, #sounds)]:Clone()

		local attach = Instance.new("Attachment")
		attach.Parent = workspace.Terrain
		attach.WorldPosition = position

		chosen.Parent = attach
		chosen.RollOffMode = Enum.RollOffMode.Linear
		chosen.RollOffMinDistance = 8
		chosen.RollOffMaxDistance = 250
		chosen:Play()

		debris:AddItem(attach, chosen.TimeLength > 0 and chosen.TimeLength or 4)
	end

	-- spawn impact particles (emit then cleanup)
	local function spawn_impact_fx(hit_part, hit_position, hit_normal)
		if not hit_part then return end

		local hum = get_humanoid_from_instance(hit_part)
		if hum and is_same_team(self.bot, hum.Parent) then
			return -- skip FX for friendly bots
		end

		local impact_type = "Hit"
		if hit_part.Parent and hit_part.Parent:FindFirstChild("Humanoid") then
			impact_type = "Hit"
		elseif collectionservice:HasTag(hit_part, "DeflectionSurface") or
			(hit_part.Parent and collectionservice:HasTag(hit_part.Parent, "DeflectionSurface")) then
			impact_type = "Metal"
		else
			local material_map = {
				[Enum.Material.Wood] = "Wood",
				[Enum.Material.Grass] = "Ground",
				[Enum.Material.Ground] = "Ground",
				[Enum.Material.Sand] = "Sand",
				[Enum.Material.Concrete] = "Stone",
				[Enum.Material.Brick] = "Stone",
				[Enum.Material.Glass] = "Glass",
			}
			impact_type = material_map[hit_part.Material] or "Ground"
		end

		local material_folder = fx_folder:FindFirstChild(impact_type)
		if not material_folder then
			play_impact_sound(hit_position, impact_type)
			return
		end

		local attachment = Instance.new("Attachment")
		attachment.Parent = workspace.Terrain
		attachment.WorldCFrame = CFrame.lookAt(hit_position, hit_position + hit_normal)

		local function burst_emit(emitter_template)
			local emitter = emitter_template:Clone()
			emitter.Parent = attachment
			emitter.Enabled = true

			local count = emitter_template:GetAttribute("EmitCount") or 10
			emitter:Emit(count)
			emitter.Enabled = false
		end

		local part_templates = {}
		for _, v in ipairs(material_folder:GetChildren()) do
			if v:IsA("Part") then table.insert(part_templates, v) end
		end

		if #part_templates > 0 then
			local chosen = part_templates[math.random(1, #part_templates)]
			for _, child in ipairs(chosen:GetChildren()) do
				if child:IsA("ParticleEmitter") then burst_emit(child) end
			end
		else
			for _, desc in ipairs(material_folder:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then burst_emit(desc) end
			end
		end

		debris:AddItem(attachment, 5)
		play_impact_sound(hit_position, impact_type)
	end

	-- FastCast RayHit: apply damage (only to enemies), spawn impact FX
	caster.RayHit:Connect(function(active_cast, raycast_result)
		if not raycast_result then return end

		local inst = raycast_result.Instance
		local hum = get_humanoid_from_instance(inst)

		if hum then
			local hit_char = hum.Parent
			if not is_same_team(self.bot, hit_char) then
				pcall(function()
					hum:TakeDamage(self.settings.damage or 1)
				end)
			end
		end

		spawn_impact_fx(inst, raycast_result.Position, raycast_result.Normal)
	end)

	-- handle pierce event (no-op placeholder)
	caster.RayPierced:Connect(function()
		-- intentionally left blank
	end)

	-- update tracer cosmetic as length changes (record cosmetic for cleanup)
	caster.LengthChanged:Connect(function(active_cast, last_point, ray_dir, displacement, segment_velocity, cosmetic)
		-- record cosmetic if provided (sometimes created later and surfaced here)
		if active_cast and cosmetic then
			self._cosmetics[active_cast] = cosmetic
		end

		if cosmetic and cosmetic.Parent then
			pcall(function()
				local pos = last_point + (ray_dir * displacement)
				-- anchor & orient cosmetic safely
				pcall(function()
					cosmetic.Anchored = true
					cosmetic.CFrame = CFrame.new(pos, pos + ray_dir)
				end)
			end)
		end
	end)

	-- cleanup when cast terminates: remove active cast, notify clients, and destroy cosmetic
	caster.CastTerminating:Connect(function(active_cast)
		-- remove from active_casts array and notify clients
		for i = #self.active_casts, 1, -1 do
			local entry = self.active_casts[i]
			if entry and entry.cast == active_cast then
				-- notify clients to stop tracer using cast ID
				tracer_event:FireAllClients("stop", entry.id)
				table.remove(self.active_casts, i)
				break
			end
		end

		-- attempt to find and destroy any cosmetic object associated with the active_cast
		local function destroy_if_valid(obj)
			if not obj then return end
			if obj.Parent == nil then return end
			pcall(function() obj:Destroy() end)
		end

		local cosmetic = nil
		if active_cast then
			cosmetic = self._cosmetics[active_cast]
		end

		-- fallback attempts to locate cosmetic on active_cast structure
		if not cosmetic and active_cast then
			local ok, rayinfo = pcall(function() return active_cast.CastRayInfo end)
			if ok and rayinfo and rayinfo.CosmeticBulletObject then
				cosmetic = rayinfo.CosmeticBulletObject
			end
		end

		if not cosmetic and active_cast and active_cast.CosmeticBulletObject then
			cosmetic = active_cast.CosmeticBulletObject
		end

		if not cosmetic and active_cast and active_cast._CosmeticBulletObject then
			cosmetic = active_cast._CosmeticBulletObject
		end

		destroy_if_valid(cosmetic)

		-- clear map entry if present
		if active_cast then
			self._cosmetics[active_cast] = nil
		end

		-- in some edge cases behavior may also store a top-level CosmeticBulletObject on active_cast; attempt again defensively
		if active_cast and active_cast._CosmeticBulletObject then
			destroy_if_valid(active_cast._CosmeticBulletObject)
		end
	end)

	-- LOS raycast params for is_visible checks (excludes self and tracers)
	local los_params = RaycastParams.new()
	los_params.FilterType = Enum.RaycastFilterType.Exclude
	los_params.IgnoreWater = true
	los_params.FilterDescendantsInstances = build_team_ignore_list()

	-- check if any sample point on target is visible from origin
	local function is_visible(target_char, origin)
		if not target_char or not origin then return false end

		-- rebuild params every call so filter stays current
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		params.FilterDescendantsInstances = build_team_ignore_list()

		local points = {}

		local head = target_char:FindFirstChild("Head")
		local hrp = target_char:FindFirstChild("HumanoidRootPart")

		if head then table.insert(points, head.Position) end
		if hrp then table.insert(points, hrp.Position) end
		if #points == 0 then return false end

		local check_origins = { origin, humanoid_root.Position }

		for _, check_origin in ipairs(check_origins) do
			for _, pt in ipairs(points) do
				local dir = pt - check_origin
				if dir.Magnitude == 0 then continue end

				local result = workspace:Raycast(check_origin, dir, params)

				if not result or result.Instance:IsDescendantOf(target_char) then
					return true
				end
			end
		end

		return false
	end

	-- fire at the target respecting ammo, firerate, LOS and spawn tracers
	local function fire_at_target(target_char)
		if not self.alive then return end
		if self.reloading then return end
		if (self.current_ammo or 0) <= 0 then
			do_reload()
			return
		end

		local now = os.clock()
		local fire_interval = 60 / (self.settings.firerate or 600)
		if now - self.last_fire_time < fire_interval then return end
		self.last_fire_time = now

		local target_hrp = target_char and target_char:FindFirstChild("HumanoidRootPart")
		if not target_hrp then return end

		local origin = firing_point and firing_point.WorldPosition or humanoid_root.Position
		local look_dir = (target_hrp.Position - humanoid_root.Position)
		if look_dir.Magnitude > 0 then
			origin = origin + look_dir.Unit * 0.5
		end

		if not is_visible(target_char, origin) then return end

		local dir = (target_hrp.Position - origin)
		if dir.Magnitude == 0 then return end
		local dir_unit = dir.Unit

		-- play firing animation and sound
		pcall(function() fire_anim_track:Play() end)

		local fire_sound = Instance.new("Sound", handle)
		fire_sound.SoundId = "rbxassetid://" .. tostring(self.settings.fire_sound_id or 0)
		fire_sound.Volume = self.settings.fire_sound_volume or 0.4
		fire_sound.RollOffMode = Enum.RollOffMode.Linear
		fire_sound.RollOffMinDistance = 5
		fire_sound.RollOffMaxDistance = 300
		fire_sound:Play()
		debris:AddItem(fire_sound, 5)

		local speed = self.settings.projectile_speed or 3000

		-- fire pellets and wire up tracer ids & record active casts
		for i = 1, (self.settings.pellets or 1) do
			local shot_dir = random_spread_direction(dir_unit)

			local ok, active_cast = pcall(function()
				return caster:Fire(origin, shot_dir, speed, self._behavior)
			end)

			if ok and active_cast then
				local cast_id = generate_cast_id()
				table.insert(self.active_casts, {id = cast_id, cast = active_cast})

				-- notify clients to spawn tracer (use cast ID, not object)
				tracer_event:FireAllClients("start", cast_id, origin, shot_dir, speed)
			end
		end

		-- decrement ammo once per trigger event (pellets are part of one shot)
		self.current_ammo = (self.current_ammo or 0) - 1
		if self.current_ammo <= 0 then
			do_reload()
		end
	end

	-- create noobpath instance with safe callbacks (wrap humanoid MoveTo/Jump)
	local function create_noobpath()
		local agent_params = self.settings.noobpath_agent or {}
		-- pass humanoid so factory can safely use MoveTo/Jump checks; provide stop callback to clear last_goal
		local ok, np = pcall(function()
			return noobpath_factory.create(self.bot, humanoid, agent_params, self.settings.noobpath_speed, function()
				-- keep controller state in sync when np traps/errors
				self.last_goal = nil
			end)
		end)

		if ok and np then
			return np
		end

		return nil
	end

	-- compute destination vector for current path mode (aggressive vs tactical)
	local function compute_destination_for_target(mode, hrp)
		if not hrp then return humanoid_root.Position end
		if mode == "aggressive" then
			return hrp.Position
		else
			local dir_vec = (humanoid_root.Position - hrp.Position)
			if dir_vec.Magnitude == 0 then dir_vec = Vector3.new(0, 0, -1) end
			local dest = hrp.Position + dir_vec.Unit * (self.settings.desired_distance or 12)
			return dest
		end
	end

	-- choose path mode by LOS (tactical if visible, aggressive otherwise)
	local function decide_path_mode(target_char)
		if not target_char then
			return "aggressive"
		end

		local now = os.clock()

		self._mode_timer = self._mode_timer or 0
		self._last_mode_check = self._last_mode_check or 0

		-- only allow mode change every 0.5s
		if now - self._last_mode_check < 0.5 then
			return self.path_mode
		end

		self._last_mode_check = now

		local origin = firing_point and firing_point.WorldPosition or humanoid_root.Position

		if is_visible(target_char, origin) then
			return "tactical"
		end

		return "aggressive"
	end

	-- ensure path is created and update proactively when needed (throttled)
	local function ensure_path_to_destination(destination)
		if not destination then return end

		local now = os.clock()

		if not self.path then
			self.path = create_noobpath()
			if not self.path then return end
		end

		local recalc_dist = self.settings.goal_recalc_distance or 8 -- larger threshold
		local cooldown = self.settings.path_update_cooldown or 0.8  -- slower replans

		local need_update = false

		-- first run
		if not self.last_goal then
			need_update = true
		else
			local diff = (self.last_goal - destination).Magnitude
			if diff >= recalc_dist then
				need_update = true
			end
		end

		-- throttle replans
		if now - self.last_path_update_time < cooldown then
			return
		end

		-- ONLY replan when path is idle or goal changed significantly
		if need_update and (self.path.Idle or not self.path.Running) then
			self.last_goal = destination
			self.last_path_update_time = now
			self.path:Run(destination)
		end
	end

	-- update path logic per heartbeat (handles tactical retreat, clipping to max_path_distance)
	local function update_path_to_target()
		if not self.alive then return end
		if not self.target_char then
			if self.path then pcall(function() self.path:Stop() end) self.path = nil end
			self.last_goal = nil
			return
		end
		local hrp = self.target_char:FindFirstChild("HumanoidRootPart")
		local hum = self.target_char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then
			if self.path then
				pcall(function() self.path:Stop() end)
				self.path = nil
			end

			self.last_goal = nil
			return
		end

		local new_mode = decide_path_mode(self.target_char)
		if new_mode ~= self.path_mode then
			self.path_mode = new_mode
			self.last_goal = nil
		end

		local destination = compute_destination_for_target(self.path_mode, hrp)
		if self.path_mode == "tactical" then
			local dist = (hrp.Position - humanoid_root.Position).Magnitude
			if dist <= (self.settings.retreat_threshold or 10) then
				local away = (humanoid_root.Position - hrp.Position)
				if away.Magnitude == 0 then away = Vector3.new(0, 0, -1) end
				destination = humanoid_root.Position + away.Unit * (self.settings.desired_distance or 12)
			end
		end

		local to_target = (destination - humanoid_root.Position).Magnitude
		if to_target > (self.settings.max_path_distance or 1500) then
			destination = humanoid_root.Position + (destination - humanoid_root.Position).Unit * (self.settings.max_path_distance or 1500)
		end

		ensure_path_to_destination(destination)
	end

	-- pick closest enemy within engagement range for targeting (players + bots)
	local function get_closest_player_within_range()
		local closest_char = nil
		local closest_dist = math.huge

		local my_team = get_team_from_model(self.bot)
		local max_range = self.settings.engagement_range or 225

		-- check one character model safely
		local function try_candidate(char)
			if not char or char == self.bot then return end

			local hum = char:FindFirstChildOfClass("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hum or not hrp then return end
			if hum.Health <= 0 then return end

			local team = hum:GetAttribute("Team")
			if team and my_team and team == my_team then
				return
			end

			local d = (hrp.Position - humanoid_root.Position).Magnitude
			if d < closest_dist and d <= max_range then
				closest_dist = d
				closest_char = char
			end
		end

		-- scan real players
		for _, plr in ipairs(players:GetPlayers()) do
			try_candidate(plr.Character)
		end

		-- scan bot folder only (no workspace-wide scan)
		local bot_folder = workspace:FindFirstChild("bots")
		if bot_folder then
			for _, bot_model in ipairs(bot_folder:GetChildren()) do
				try_candidate(bot_model)
			end
		end

		return closest_char
	end

	-- update arms and head to look at target (R6 only)
	local function update_bot_arms_and_head(bot_model, humanoid, target_char, delta)
		if not humanoid or not humanoid.Parent then return end
		if humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end

		local hrp = bot_model:FindFirstChild("HumanoidRootPart")
		local torso = bot_model:FindFirstChild("Torso")
		local head = bot_model:FindFirstChild("Head")
		local neck = torso and torso:FindFirstChild("Neck")
		local rs = torso and torso:FindFirstChild("Right Shoulder")
		local ls = torso and torso:FindFirstChild("Left Shoulder")
		if not hrp or not torso or not head or not neck or not rs or not ls then return end

		-- cache default C0s
		if not bot_model:FindFirstChild("_neckC0") then
			local n = Instance.new("CFrameValue")
			n.Name = "_neckC0"
			n.Value = neck.C0
			n.Parent = bot_model
		end
		if not bot_model:FindFirstChild("_rsC0") then
			local r = Instance.new("CFrameValue")
			r.Name = "_rsC0"
			r.Value = rs.C0
			r.Parent = bot_model
		end
		if not bot_model:FindFirstChild("_lsC0") then
			local l = Instance.new("CFrameValue")
			l.Name = "_lsC0"
			l.Value = ls.C0
			l.Parent = bot_model
		end

		local neck_org = bot_model._neckC0.Value
		local rs_org = bot_model._rsC0.Value
		local ls_org = bot_model._lsC0.Value

		local updatespeed = 0.5
		local headhor = 0.8
		local headvert = 0.8

		if target_char and is_visible(target_char, humanoid_root.Position) and not is_same_team(self.bot, target_char) then
			local target_hrp = target_char:FindFirstChild("HumanoidRootPart") or target_char:FindFirstChild("Head")
			if target_hrp then
				local headpos = head.Position
				local torso_look = torso.CFrame.LookVector
				local aimpos = target_hrp.Position
				local vec = aimpos - headpos
				local dist = vec.Magnitude
				if dist > 0 then
					local pitch = -(math.asin(vec.Y / dist) * headvert)
					local yaw = -(vec.Unit:Cross(torso_look)).Y * headhor
					local target_neck = neck_org * CFrame.Angles(pitch, 0, yaw)
					neck.C0 = neck.C0:Lerp(target_neck, updatespeed)

					local x = math.asin(vec.Unit.Y)
					local _, ry, rz = rs.C0:ToEulerAnglesXYZ()
					local _, ly, lz = ls.C0:ToEulerAnglesXYZ()
					rs.C0 = rs.C0:Lerp(CFrame.new(rs.C0.Position) * CFrame.Angles(x, ry, rz), updatespeed)
					ls.C0 = ls.C0:Lerp(CFrame.new(ls.C0.Position) * CFrame.Angles(x, ly, lz), updatespeed)
				end
			end
		else
			-- reset to default C0s
			neck.C0 = neck.C0:Lerp(neck_org, updatespeed)
			rs.C0 = rs.C0:Lerp(rs_org, updatespeed)
			ls.C0 = ls.C0:Lerp(ls_org, updatespeed)
		end
	end

	-- heartbeat step picks target, updates path, fires
	local function heartbeat_step()
		if not self.alive then
			return
		end

		self.target_char = get_closest_player_within_range()

		update_path_to_target()

		local align = humanoid_root:FindFirstChildOfClass("AlignOrientation")
		if align then
			if self.target_char and is_visible(self.target_char, humanoid_root.Position) then
				humanoid.AutoRotate = false
				align.Enabled = true

				local target_hrp = self.target_char:FindFirstChild("HumanoidRootPart")
				if target_hrp then
					local look_vector = (target_hrp.Position - humanoid_root.Position).Unit
					local target_cframe = CFrame.lookAt(humanoid_root.Position, humanoid_root.Position + look_vector)
					align.CFrame = target_cframe
				end
			else
				humanoid.AutoRotate = true
				align.Enabled = false
			end
		end

		update_bot_arms_and_head(self.bot, humanoid, self.target_char, 0)

		if self.target_char then
			fire_at_target(self.target_char)
		end
	end

	-- start controller (connect heartbeat)
	function self:start()
		if self.heartbeat_conn then return end
		self.heartbeat_conn = runservice.Heartbeat:Connect(function()
			heartbeat_step()
		end)
	end

	-- stop controller (disconnect heartbeat, stop path, terminate casts)
	function self:stop()
		if self.heartbeat_conn then
			self.heartbeat_conn:Disconnect()
			self.heartbeat_conn = nil
		end

		if self.path then
			pcall(function()
				self.path:Stop()
			end)
		end

		self.last_goal = nil

		-- terminate all active fastcast bullets (handle stored entry shape)
		for i = #self.active_casts, 1, -1 do
			local entry = self.active_casts[i]
			if entry then
				-- entry expected to be {id = cast_id, cast = active_cast}
				if entry.cast and entry.cast.Terminate then
					pcall(function() entry.cast:Terminate() end)
				end
				-- notify clients to stop tracer if id exists
				if entry.id then
					pcall(function() tracer_event:FireAllClients("stop", entry.id) end)
				end
			end
			self.active_casts[i] = nil
		end

		-- stop movement animation controller
		if self._anim_controller then
			self._anim_controller:stop()
			self._anim_controller = nil
		end

		-- clear cosmetics
		for cast_key, cos in pairs(self._cosmetics) do
			pcall(function()
				if cos and cos.Parent then cos:Destroy() end
			end)
			self._cosmetics[cast_key] = nil
		end

		self.alive = false
		self.reloading = false
	end

	-- destroy controller fully and remove from registry
	function self:destroy()
		self:stop()
		for i, v in ipairs(controllers) do
			if v == self then table.remove(controllers, i) break end
		end
	end

	-- add controller to global registry and return it
	table.insert(controllers, self)
	return self
end

return module
-- end of bot_controller
