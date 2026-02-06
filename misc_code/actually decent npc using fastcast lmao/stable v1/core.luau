-- server-side bot gun script (stable fixed i think)
local replicatedstorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")
local runservice = game:GetService("RunService")

local fastcast = require(replicatedstorage.Modules:WaitForChild("FastCastRedux"))

-- general settings for tracers, projectile, magazine, and bot behavior
local tracer_template = replicatedstorage:WaitForChild("FX"):WaitForChild("Tracer")
local tracer_container = workspace:WaitForChild("Tracers")

local projectile_speed = 3000
local max_distance = 4000

local mag_size = 35
local firerate = 605 -- RPM
local pellets = 1
local bullet_spread = 0.3 -- degrees
local reload_speed = 3.33
local damage = 3.3

local engagement_range = 225

-- bot references and firing point
local bot = script.Parent
local humanoid_root = bot:WaitForChild("HumanoidRootPart")
local handle = bot:WaitForChild("Handle")
local firing_point = handle:WaitForChild("FiringPoint")

local humanoid = bot:WaitForChild("Humanoid") -- cached humanoid for death handling
local active_casts = {}                          -- track active casts so we can terminate them on death
local heartbeat_conn = nil                       -- keep reference to heartbeat connection for disconnect
local alive = true                               -- flag indicating bot is alive and allowed to fire

-- fastcast / behavior setup
local caster = fastcast.new()
caster.VisualizeCasts = false
caster.SimulateBeforePhysics = false
caster.WorldRoot = workspace

local behavior = fastcast.newBehavior()
behavior.MaxDistance = max_distance
behavior.CosmeticBulletTemplate = tracer_template
behavior.CosmeticBulletContainer = tracer_container
behavior.AutoIgnoreContainer = true

-- state for ammo, reload and firing timing
local current_ammo = mag_size
local reloading = false
local last_fire_time = 0
local fire_interval = 60 / firerate -- seconds per shot

-- helper to find humanoid from a raycast hit instance
local function get_humanoid_from_instance(inst)
	-- try direct parent first, then search ancestors
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

-- compute a random direction within a cone defined by bullet_spread degrees
local function random_spread_direction(direction)
	-- produce a small random perturbation using spherical coordinates
	local spread_rad = math.rad(bullet_spread)
	-- sample random unit vector within cone around 'direction'
	-- create orthonormal basis
	local up = Vector3.new(0, 1, 0)
	if math.abs(direction:Dot(up)) > 0.999 then
		up = Vector3.new(1, 0, 0)
	end
	local right = direction:Cross(up).Unit
	local forward = right:Cross(direction).Unit
	-- pick random angle within cone
	local u = math.random()
	local v = math.random()
	local theta = math.acos(1 - u * (1 - math.cos(spread_rad))) -- correct distribution
	local phi = 2 * math.pi * v
	local x = math.sin(theta) * math.cos(phi)
	local y = math.sin(theta) * math.sin(phi)
	local z = math.cos(theta)
	-- transform local cone vector to world
	local world_vec = (right * x) + (forward * y) + (direction * z)
	return world_vec.Unit
end

-- perform reload (blocks firing while reloading)
local function do_reload()
	if reloading then return end
	reloading = true
	task.spawn(function()
		task.wait(reload_speed)
		current_ammo = mag_size
		reloading = false
	end)
end

-- caster-level ray hit handler applies damage and destroys tracer
caster.RayHit:Connect(function(active_cast, raycast_result, segment_velocity, cosmetic)
	-- apply damage to humanoids
	local inst = raycast_result and raycast_result.Instance
	local hum = get_humanoid_from_instance(inst)
	if hum then
		-- apply damage on server
		pcall(function()
			hum:TakeDamage(damage)
		end)
	end
	-- remove cosmetic tracer when hit
	if cosmetic and cosmetic.Parent then
		pcall(function() cosmetic:Destroy() end)
	end
end)

-- caster-level ray pierced handler (optional: apply partial effects, keep tracer)
caster.RayPierced:Connect(function(active_cast, raycast_result, segment_velocity, cosmetic)
	-- do nothing by default; you can apply smaller damage or effects here
	-- keep tracer alive; it will be removed on hit or termination
end)

-- caster-level length changed updates tracer position for smooth visuals
caster.LengthChanged:Connect(function(active_cast, last_point, ray_dir, displacement, segment_velocity, cosmetic)
	if cosmetic and cosmetic.Parent then
		pcall(function()
			cosmetic.Anchored = true
			cosmetic.CFrame = CFrame.new(last_point + (ray_dir * displacement), last_point + (ray_dir * displacement) + ray_dir)
		end)
	end
end)


-- cast terminating cleanup (safety)
caster.CastTerminating:Connect(function(active_cast)
	-- remove active_cast from active_casts table when it terminates
	for i = #active_casts, 1, -1 do
		if active_casts[i] == active_cast then
			table.remove(active_casts, i)
			break
		end
	end

	-- existing cosmetic cleanup (keeps original behavior)
	local rayinfo = active_cast and active_cast.CastRayInfo
	if not rayinfo then return end
	local cosmetic = rayinfo.CosmeticBulletObject
	if not cosmetic then return end
	pcall(function()
		if cosmetic:IsA("Model") then
			cosmetic:Destroy()
		elseif cosmetic:IsA("BasePart") then
			cosmetic:Destroy()
		else
			if cosmetic.Parent then cosmetic:Destroy() end
		end
	end)
end)

local function stop_all_bot_activity()
	if not alive then return end
	alive = false

	-- stop reloads
	reloading = false

	-- disconnect heartbeat safely
	if heartbeat_conn then
		pcall(function() heartbeat_conn:Disconnect() end)
		heartbeat_conn = nil
	end

	-- terminate every active cast (FastCast ActiveCast:Terminate)
	for i = #active_casts, 1, -1 do
		local ac = active_casts[i]
		pcall(function()
			if ac and ac.Terminate then
				ac:Terminate()
			end
		end)
		active_casts[i] = nil
	end
end

-- fire a single shot at the target character (checks ammo, rate, reload)
local function fire_at_target(target_char)
	if not alive then return end
	if reloading then return end
	if current_ammo <= 0 then
		do_reload()
		return
	end

	local now = os.clock()
	if now - last_fire_time < fire_interval then return end
	last_fire_time = now

	local target_hrp = target_char and target_char:FindFirstChild("HumanoidRootPart")
	if not target_hrp then return end

	local origin = firing_point.WorldPosition -- Attachment world-space
	if not origin then return end

	local dir = (target_hrp.Position - origin)
	if dir.Magnitude == 0 then return end
	local dir_unit = dir.Unit

	for i = 1, pellets do
		local shot_dir = random_spread_direction(dir_unit)
		-- store active cast for termination on death
		local ok, active = pcall(function()
			return caster:Fire(origin, shot_dir, projectile_speed, behavior)
		end)
		if ok and active then
			table.insert(active_casts, active)
		end
	end

	current_ammo = current_ammo - 1
	if current_ammo <= 0 then
		do_reload()
	end
end

humanoid.Died:Connect(function()
	stop_all_bot_activity()
end)

-- main AI loop finds closest player in range and fires
runservice.Heartbeat:Connect(function()
	local closest_char = nil
	local closest_dist = math.huge

	for _, player in pairs(game.Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 then
			local d = (hrp.Position - humanoid_root.Position).Magnitude
			if d < closest_dist and d <= engagement_range then
				closest_dist = d
				closest_char = char
			end
		end
	end

	if closest_char then
		fire_at_target(closest_char)
	end
end)
