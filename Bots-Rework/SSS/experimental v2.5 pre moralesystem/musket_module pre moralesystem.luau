-- musket_module (modules)
local module = {}

local runservice = game:GetService("RunService")
local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")
local workspace = workspace
local debris = game:GetService("Debris")

-- load musket animations from ReplicatedStorage.Asset.Animations.Musket
local anim_folder = replicatedstorage:WaitForChild("Asset")
	:WaitForChild("Animations")
	:WaitForChild("Musket")

local sfx = replicatedstorage:WaitForChild("Asset")
	:WaitForChild("SFX")
	:WaitForChild("musket")
	:WaitForChild("fire")

local animids = {
	idle = anim_folder:WaitForChild("Idle"),
	make_ready = anim_folder:WaitForChild("MakeReady"),
	make_ready_idle = anim_folder:WaitForChild("MakeReadyIdle"),
	to_aim = anim_folder:WaitForChild("ToAim"),
	aim_idle = anim_folder:WaitForChild("AimIdle"),
	fire = anim_folder:WaitForChild("Fire"),
	reload = anim_folder:WaitForChild("Reload"),
	reload_idle = anim_folder:WaitForChild("ReloadIdle"),
}

-- weak table to store per-bot runtime data (tracks, conns)
local musket_data = setmetatable({}, { __mode = "k" })

-- get_animator: return animator for bot humanoid, create if missing
local function get_animator(bot)
	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	return animator
end

-- stop_all: stop any playing animation and disconnect trackers for the bot
function module.stop_all(bot)
	local data = musket_data[bot]
	if not data then return end
	if data.conn then
		pcall(function() data.conn:Disconnect() end)
		data.conn = nil
	end
	if data.track then
		if data.track.IsPlaying then pcall(function() data.track:Stop() end) end
		data.track = nil
	end
end

-- play_anim: helper to play an animation and register onend callback
local function play_anim(bot, anim, looped, onend)
	local animator = get_animator(bot)
	if not animator then return end
	module.stop_all(bot)

	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = looped == true
	track:Play()

	musket_data[bot] = musket_data[bot] or {}
	musket_data[bot].track = track

	if onend then
		local conn
		conn = track.Stopped:Connect(function()
			if conn then conn:Disconnect() end
			if musket_data[bot] then musket_data[bot].conn = nil end
			pcall(onend)
		end)
		musket_data[bot].conn = conn
	end
end

-- init: initialize musket attributes for the bot
function module.init(bot)
	if bot:GetAttribute("musket_state") == nil then bot:SetAttribute("musket_state","idle") end
	if bot:GetAttribute("has_bullet") == nil then bot:SetAttribute("has_bullet",true) end
	module.stop_all(bot)
end

local function play_fire_sound(bot)

	local musket = bot:FindFirstChild("Musket")
	if not musket then return end

	local muzzle = musket:FindFirstChild("Muzzle", true)
	if not muzzle then return end

	local sounds = sfx:GetChildren()
	if #sounds == 0 then return end

	local sound = sounds[math.random(1, #sounds)]:Clone()
	sound.Parent = muzzle
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

-- this caches all humanoid models by team for fast targeting
local team_cache = {}  -- [teamName] = { model1, model2, ... }

-- this rebuilds the cache (cheap, called rarely)
function module.rebuild_team_cache()
	-- this clears and rebuilds the humanoid team cache
	team_cache = {}

	for _, model in ipairs(workspace:GetChildren()) do
		local hum = model:FindFirstChildWhichIsA("Humanoid")
		if hum then
			local team = hum:FindFirstChild("Team")
			local t = team and team.Value or "none"

			team_cache[t] = team_cache[t] or {}
			table.insert(team_cache[t], model)

			-- this removes dead humanoids lazily
			hum.Died:Connect(function()
				local list = team_cache[t]
				if not list then return end
				for i = #list, 1, -1 do
					if list[i] == model then
						table.remove(list, i)
						break
					end
				end
			end)
		end
	end
end

local bullet_speed = 1950        -- studs per second (musket ~ 800–1000)
local max_lifetime = 10          -- seconds
local step_rate = 1 / 60       -- simulation step

local function get_predicted_direction(bot, target, origin)

	local thrp = target:FindFirstChild("HumanoidRootPart")
	if not thrp then return nil end

	local rel = thrp.Position - origin
	local dist = rel.Magnitude
	if dist <= 0 then return rel.Unit end

	-- simple linear lead (no gravity compensation by design)
	local time = dist / bullet_speed
	local predicted_pos = thrp.Position + thrp.AssemblyLinearVelocity * time

	return (predicted_pos - origin).Unit
end

local tracer_event = replicatedstorage:WaitForChild("bullet_tracer")

local function simulate_bullet(bot)

	local musket = bot:FindFirstChild("Musket")
	if not musket then return end

	local muzzle = musket:FindFirstChild("Muzzle", true)
	if not muzzle then return end

	local origin = muzzle:IsA("Attachment") and muzzle.WorldPosition or muzzle.Position

	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	local myteam = hum and hum:FindFirstChild("Team") and hum.Team.Value

	local dir

	-- use predicted target if exists
	if hum then
		local tag = hum:FindFirstChild("target")
		local target = tag and tag.Value
		if target and target.Parent then
			local predicted = get_predicted_direction(bot, target, origin)
			if predicted then dir = predicted end
		end
	end

	-- fallback direction
	if not dir then
		dir = muzzle:IsA("Attachment") and muzzle.WorldCFrame.LookVector or muzzle.CFrame.LookVector
	end

	-- single spread number (degrees)
	local spread = math.rad(1.5) -- this controls accuracy (lower = more accurate, higher = more random)

	local yaw = (math.random() - 0.5) * spread
	local pitch = (math.random() - 0.5) * spread
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(pitch, yaw, 0)).LookVector

	local velocity = dir * bullet_speed
	local position = origin
	local life = 0

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }

	-- send tracer with same physics
	tracer_event:FireAllClients("start", origin, velocity)

	task.spawn(function()
		while life < max_lifetime do
			local dt = step_rate
			life += dt

			-- gravity
			velocity += Vector3.new(0, -10, 0) * dt

			local nextpos = position + velocity * dt
			local result = workspace:Raycast(position, nextpos - position, params)

			if result then
				local model = result.Instance:FindFirstAncestorOfClass("Model")
				local hum2 = model and model:FindFirstChildWhichIsA("Humanoid")

				if hum2 then
					local histeam = hum2:FindFirstChild("Team") and hum2.Team.Value

					-- ignore friendly hits and keep flying
					if histeam == myteam then
						params.FilterDescendantsInstances[#params.FilterDescendantsInstances + 1] = model
					else
						-- enemy hit
						hum2:TakeDamage(1000)
						tracer_event:FireAllClients("hit", position)
						
						-- morale shock to target company
						local owner = players:GetPlayerFromCharacter(model)
						if owner then
							replicatedstorage:WaitForChild("morale_event"):Fire(owner, 4)
						end
						break
					end
				else
					-- world hit
					tracer_event:FireAllClients("hit", position)
					break
				end
			end

			position = nextpos
			task.wait(dt)
		end
	end)
end

function module.find_target(bot, range)
	-- this finds a random visible enemy using the team cache (fast)

	local root = bot:FindFirstChild("HumanoidRootPart")
	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	if not root or not humanoid then return nil end

	local myteam = humanoid:FindFirstChild("Team") and humanoid.Team.Value

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }

	local candidates = {}

	for team, list in pairs(team_cache) do
		if team ~= myteam then
			for i = #list, 1, -1 do
				local model = list[i]
				if not model or not model.Parent then
					table.remove(list, i)
				else
					local h = model:FindFirstChildWhichIsA("Humanoid")
					local hrp = model:FindFirstChild("HumanoidRootPart")
					if h and hrp and h.Health > 0 then
						local dir = hrp.Position - root.Position
						local dist = dir.Magnitude
						if dist <= range then
							local hit = workspace:Raycast(root.Position, dir, params)
							if hit and hit.Instance:IsDescendantOf(model) then
								table.insert(candidates, model)
							end
						end
					end
				end
			end
		end
	end

	if #candidates == 0 then return nil end
	return candidates[math.random(1, #candidates)]
end


-- this rotates the bot to face a target
function module.face_target(bot, target)
	--	print("face_target called")

	local root = bot:FindFirstChild("HumanoidRootPart")
	local thrp = target and target:FindFirstChild("HumanoidRootPart")
	if not root or not thrp then return end

	local pos = root.Position
	local look = Vector3.new(thrp.Position.X, pos.Y, thrp.Position.Z)

	root.CFrame = CFrame.new(pos, look)
end

-- set_idle: set idle animation and state
function module.set_idle(bot)
	module.stop_all(bot)
	bot:SetAttribute("musket_state","idle")
	play_anim(bot, animids.idle, true)
end

-- present: play make ready -> idle
function module.present(bot)
	-- only transition from idle
	if bot:GetAttribute("musket_state") ~= "idle" then return end
	bot:SetAttribute("musket_state","makeready")
	play_anim(bot, animids.make_ready,false,function()
		bot:SetAttribute("musket_state","makereadyidle")
		play_anim(bot, animids.make_ready_idle,true)
	end)
end

-- aim: play to_aim -> aim idle
function module.aim(bot)
	--	print("musket.aim")

	if bot:GetAttribute("musket_state") ~= "makereadyidle" then return end

	local target = module.find_target(bot, 500)
	if target then
		local hum = bot:FindFirstChildWhichIsA("Humanoid")
		if hum then
			local tag = hum:FindFirstChild("target")
			if not tag then
				tag = Instance.new("ObjectValue")
				tag.Name = "target"
				tag.Parent = hum
			end
			tag.Value = target -- ObjectValue prevents name collision
		end
	end

	bot:SetAttribute("musket_state", "toaim")
	play_anim(bot, animids.to_aim, false, function()
		bot:SetAttribute("musket_state", "aimidle")
		play_anim(bot, animids.aim_idle, true)
	end)
end


-- fire: simulate shot and transition to reload idle
function module.fire(bot)
	--	print("musket.fire")

	if bot:GetAttribute("musket_state") ~= "aimidle" then return end
	if bot:GetAttribute("has_bullet") ~= true then return end

	bot:SetAttribute("has_bullet", false)
	bot:SetAttribute("musket_state", "fire")

	play_fire_sound(bot)
	simulate_bullet(bot)

	-- clear target safely
	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	if hum then
		local tag = hum:FindFirstChild("target")
		if tag then
			tag.Value = nil
		end
	end

	-- disable aiming immediately
	local root = bot:FindFirstChild("HumanoidRootPart")
	local align = root:FindFirstChild("aim_align")
	if align then
		align.Enabled = false
	end

	play_anim(bot, animids.fire, false, function()
		bot:SetAttribute("musket_state", "reloadidle")
		play_anim(bot, animids.reload_idle, true)
	end)
end


-- reload: play reload then set has_bullet true and idle
function module.reload(bot)
	-- only allowed from reloadidle and when actually out of bullet
	if bot:GetAttribute("musket_state") ~= "reloadidle" then return end
	if bot:GetAttribute("has_bullet") == true then return end
	bot:SetAttribute("musket_state","reloading")
	play_anim(bot, animids.reload,false,function()
		bot:SetAttribute("has_bullet",true)
		module.set_idle(bot)
	end)
end

-- cease: stop actions and set appropriate idle state depending on has_bullet
function module.cease(bot)
	print("musket.cease")

	module.stop_all(bot)

	-- disable aim hard-stop
	local root = bot:FindFirstChild("HumanoidRootPart")
	if root then
		local align = root:FindFirstChild("aim_align")
		if align then
			align.Enabled = false
		end
	end

	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	if hum then
		local tag = hum:FindFirstChild("target")
		if tag then
			tag.Value = nil
		end
	end

	if bot:GetAttribute("has_bullet") == true then
		bot:SetAttribute("musket_state", "idle")
		play_anim(bot, animids.idle, true)
	else
		bot:SetAttribute("musket_state", "reloadidle")
		play_anim(bot, animids.reload_idle, true)
	end
end


-- stop_all exposed
module.stop_all = module.stop_all

return module
