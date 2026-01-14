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

-- weak....
local musket_data = setmetatable({}, { __mode = "k" })

-- animator getter
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

-- stop all current animations and connections
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

-- play animation helper
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

-- initialize musket attributes
function module.init(bot)
	if bot:GetAttribute("musket_state") == nil then bot:SetAttribute("musket_state","idle") end
	if bot:GetAttribute("has_bullet") == nil then bot:SetAttribute("has_bullet",true) end
	module.stop_all(bot)
end

local bullet_speed = 1950        -- studs per second (musket ~ 800–1000)
local gravity = 196.2           -- roblox gravity
local max_lifetime = 9          -- seconds
local step_rate = 1 / 120       -- simulation step

local function get_muzzle(bot)
--	print("get_muzzle called")

	local Musket = bot:FindFirstChild("Musket")

	local muzzle = Musket:FindFirstChild("Muzzle", true)
	if not muzzle then return end

	if muzzle:IsA("Attachment") then
		return muzzle.WorldPosition, muzzle.WorldCFrame.LookVector
	end

	if muzzle:IsA("BasePart") then
		return muzzle.Position, muzzle.CFrame.LookVector
	end
end

local function play_fire_sound(bot)
	print("play_fire_sound called")

	local origin, _ = get_muzzle(bot)
	if not origin then return end

	local Musket = bot:FindFirstChild("Musket")

	local muzzle = Musket:FindFirstChild("Muzzle", true)
	
	local sounds = sfx:GetChildren()
	if #sounds == 0 then return end

	local sound = sounds[math.random(1,#sounds)]:Clone()
	sound.Parent = muzzle
	sound:Play()

	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function simulate_bullet(bot)
	print("simulate_bullet called")

	local origin, dir = get_muzzle(bot)
	if not origin then return end

	local velocity = dir * bullet_speed
	local position = origin
	local life = 0

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { bot }

	-- tracer
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.Size = Vector3.new(0.15,0.15,0.15)
	tracer.Material = Enum.Material.Neon
	tracer.Parent = workspace
	debris:AddItem(tracer, max_lifetime)

	task.spawn(function()
		while life < max_lifetime do
			local dt = step_rate
			life += dt

			-- gravity drop
			velocity += Vector3.new(0, 0, 0) * dt

			local nextpos = position + velocity * dt

			-- raycast step
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

						if not myteam or not histeam or myteam.Value ~= histeam.Value then
							hum:TakeDamage(1000)
							print("musket hit", model.Name)
						end
					end
				end

				break
			end

			-- move tracer
			tracer.Position = nextpos
			position = nextpos

			task.wait(step_rate)
		end

		tracer:Destroy()
	end)
end

-- set idle animation
function module.set_idle(bot)
	module.stop_all(bot)
	bot:SetAttribute("musket_state","idle")
	play_anim(bot, animids.idle, true)
end

-- present musket
function module.present(bot)
	if bot:GetAttribute("musket_state") ~= "idle" then return end
	bot:SetAttribute("musket_state","makeready")
	play_anim(bot, animids.make_ready,false,function()
		bot:SetAttribute("musket_state","makereadyidle")
		play_anim(bot, animids.make_ready_idle,true)
	end)
end

-- aim musket
function module.aim(bot)
	if bot:GetAttribute("musket_state") ~= "makereadyidle" then return end
	bot:SetAttribute("musket_state","toaim")
	play_anim(bot, animids.to_aim,false,function()
		bot:SetAttribute("musket_state","aimidle")
		play_anim(bot, animids.aim_idle,true)
	end)
end

-- fire musket
function module.fire(bot)
--	print("musket.fire called")

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

-- reload musket
function module.reload(bot)
	if bot:GetAttribute("musket_state") ~= "reloadidle" then return end
	if bot:GetAttribute("has_bullet") == true then return end
	bot:SetAttribute("musket_state","reloading")
	play_anim(bot, animids.reload,false,function()
		bot:SetAttribute("has_bullet",true)
		module.set_idle(bot)
	end)
end

-- cease musket actions
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

return module
