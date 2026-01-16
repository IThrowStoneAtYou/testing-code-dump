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

-- get_muzzle: return muzzle world position and look vector
local function get_muzzle(bot)
	local Musket = bot:FindFirstChild("Musket")
	if not Musket then return end
	local muzzle = Musket:FindFirstChild("Muzzle", true)
	if not muzzle then return end
	if muzzle:IsA("Attachment") then
		return muzzle.WorldPosition, muzzle.WorldCFrame.LookVector
	end
	if muzzle:IsA("BasePart") then
		return muzzle.Position, muzzle.CFrame.LookVector
	end
end

-- play_fire_sound: local fire sfx at muzzle
local function play_fire_sound(bot)
--	print("play_fire_sound called")
	local origin, _ = get_muzzle(bot)
	if not origin then return end
	local Musket = bot:FindFirstChild("Musket")
	if not Musket then return end
	local muzzle = Musket:FindFirstChild("Muzzle", true)
	if not muzzle then return end
	local sounds = sfx:GetChildren()
	if #sounds == 0 then return end
	local sound = sounds[math.random(1,#sounds)]:Clone()
	sound.Parent = muzzle
	sound:Play()
	sound.Ended:Connect(function() sound:Destroy() end)
end

local bullet_speed = 1950        -- studs per second (musket ~ 800–1000)
local max_lifetime = 15          -- seconds
local step_rate = 1 / 120       -- simulation step

local function simulate_bullet(bot)
	print("simulate_bullet called")

	local origin, dir = get_muzzle(bot)
	if not origin then return end

	-- apply musket spread
	local spread = math.rad(1.55)
	local yaw = (math.random() - 0.5) * spread
	local pitch = (math.random() - 0.5) * spread
	dir = (CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(pitch, yaw, 0)).LookVector

	local velocity = dir * bullet_speed
	local position = origin
	local life = 0

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }

	-- tracer visual
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.Size = Vector3.new(0.15, 0.15, 0.15)
	tracer.Material = Enum.Material.Neon
	tracer.Parent = workspace
	debris:AddItem(tracer, max_lifetime)

	task.spawn(function()
		while life < max_lifetime do
			local dt = step_rate
			life += dt

			-- apply user-controlled bullet drop
			velocity += Vector3.new(0, -5, 0) * dt

			local nextpos = position + velocity * dt
			local result = workspace:Raycast(position, nextpos - position, params)

			if result then
				local hit = result.Instance
				local model = hit:FindFirstAncestorOfClass("Model")

				if model then
					local hum = model:FindFirstChildWhichIsA("Humanoid")
					if hum then
						local myhum = bot:FindFirstChildWhichIsA("Humanoid")
						local myteam = myhum and myhum:FindFirstChild("Team")
						local histeam = hum:FindFirstChild("Team")

						-- prevent friendly fire
						if not myteam or not histeam or myteam.Value ~= histeam.Value then
							hum:TakeDamage(1000)
							print("musket hit", model.Name)
						end
					end
				end

				break
			end

			tracer.Position = nextpos
			position = nextpos
			task.wait(dt)
		end

		tracer:Destroy()
	end)
end

function module.find_target(bot, range)
	print("find_target called")

	local root = bot:FindFirstChild("HumanoidRootPart")
	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	if not root or not humanoid then return nil end

	local myteam = humanoid:FindFirstChild("Team") and humanoid.Team.Value

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }

	local candidates = {}

	for _, model in ipairs(workspace:GetChildren()) do
		local h = model:FindFirstChildWhichIsA("Humanoid")
		local hrp = model:FindFirstChild("HumanoidRootPart")

		if h and hrp and model ~= bot and h.Health > 0 then
			local tag = h:FindFirstChild("Team")
			if not tag or tag.Value ~= myteam then
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

	if #candidates == 0 then return nil end
	return candidates[ math.random(1, #candidates) ]
end

-- this rotates the bot to face a target
function module.face_target(bot, target)
	print("face_target called")

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
	print("musket.aim called")

	-- this picks a target when aiming
	local target = module.find_target(bot, 500)
	if target then
		module.face_target(bot, target)
	end

	-- only transition from makereadyidle
	if bot:GetAttribute("musket_state") ~= "makereadyidle" then return end

	bot:SetAttribute("musket_state", "toaim")
	play_anim(bot, animids.to_aim, false, function()
		bot:SetAttribute("musket_state", "aimidle")
		play_anim(bot, animids.aim_idle, true)
	end)
end

-- fire: simulate shot and transition to reload idle
function module.fire(bot)
	-- only allowed from aimidle and must have bullet
	if bot:GetAttribute("musket_state") ~= "aimidle" then return end
	if bot:GetAttribute("has_bullet") ~= true then return end

	bot:SetAttribute("has_bullet", false)
	bot:SetAttribute("musket_state", "fire")

	play_fire_sound(bot)
	simulate_bullet(bot)

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
	module.stop_all(bot)
	if bot:GetAttribute("has_bullet") == true then
		bot:SetAttribute("musket_state","idle")
		play_anim(bot, animids.idle,true)
	else
		bot:SetAttribute("musket_state","reloadidle")
		play_anim(bot, animids.reload_idle,true)
	end
end

-- stop_all exposed
module.stop_all = module.stop_all

return module
