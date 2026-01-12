-- musket_module
-- modular musket animation/state handling for bots
local module = {}

local replicatedstorage = game:GetService("ReplicatedStorage")

-- load musket animations from ReplicatedStorage.Asset.Animations.Musket
local anim_folder = replicatedstorage:WaitForChild("Asset")
	:WaitForChild("Animations")
	:WaitForChild("Musket")

print("musket_module: anim folder loaded")

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

-- per-bot musket runtime data (weak keys to avoid leaks)
local musket_data = setmetatable({}, { __mode = "k" })

-- get animator for bot (create if missing)
local function get_animator(bot)
	-- returns animator instance for a bot humanoid
	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

-- stop and cleanup current musket track for bot
function module.stop_all(bot)
	-- stop current musket animation and disconnect its end handler
--	print("musket_module.stop_all called")
	local data = musket_data[bot]
	if not data then return end
	if data.conn then
		pcall(function() data.conn:Disconnect() end)
		data.conn = nil
	end
	if data.track then
		-- stop playing if playing
		if data.track.IsPlaying then
			pcall(function() data.track:Stop() end)
		end
		data.track = nil
	end
end

-- play an animation on the bot and optionally call onend when the track stops
local function play_anim(bot, anim_instance, looped, onend)
	-- internal helper to load/play animation on bot
	local animator = get_animator(bot)
	if not animator then return end

	-- stop previous track
	module.stop_all(bot)

	local track = animator:LoadAnimation(anim_instance)
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = looped == true
	track:Play()

	-- store track and connection so we can stop/cleanup later
	musket_data[bot] = musket_data[bot] or {}
	musket_data[bot].track = track

	if onend then
		local conn
		conn = track.Stopped:Connect(function()
			-- disconnect to avoid duplicate calls
			if conn then
				conn:Disconnect()
			end
			-- clear stored conn reference
			if musket_data[bot] then musket_data[bot].conn = nil end
			-- safe pcall to callback
			pcall(onend)
		end)
		musket_data[bot].conn = conn
	end
end

-- initialize musket attributes for a bot
function module.init(bot)
	-- create musket attributes if missing and mark idle with bullet
	print("musket_module.init called")
	if not bot:GetAttribute("musket_state") then
		bot:SetAttribute("musket_state", "idle")
	end
	if bot:GetAttribute("has_bullet") == nil then
		bot:SetAttribute("has_bullet", true)
	end
	-- ensure no stray tracks
	module.stop_all(bot)
end

-- set musket to idle (looping idle animation)
function module.set_idle(bot)
	-- set bot musket to idle looping animation
--	print("musket_module.set_idle called")
	module.stop_all(bot)
	bot:SetAttribute("musket_state", "idle")
	play_anim(bot, animids.idle, true)
end

-- present command: idle -> makeready -> makereadyidle
function module.present(bot)
	-- transition bot from idle to make-ready sequence
	if bot:GetAttribute("musket_state") ~= "idle" then return end
--	print("musket_module.present called")
	bot:SetAttribute("musket_state", "makeready")
	play_anim(bot, animids.make_ready, false, function()
		bot:SetAttribute("musket_state", "makereadyidle")
		play_anim(bot, animids.make_ready_idle, true)
	end)
end

-- aim command: makereadyidle -> to_aim -> aim_idle
function module.aim(bot)
	-- transition bot from make-ready-idle to aim-idle
	if bot:GetAttribute("musket_state") ~= "makereadyidle" then return end
--	print("musket_module.aim called")
	bot:SetAttribute("musket_state", "toaim")
	play_anim(bot, animids.to_aim, false, function()
		bot:SetAttribute("musket_state", "aimidle")
		play_anim(bot, animids.aim_idle, true)
	end)
end

-- fire command: aimidle -> fire -> reloadidle (consume bullet)
function module.fire(bot)
	-- perform fire sequence if bot has bullet and is aimed
	if bot:GetAttribute("musket_state") ~= "aimidle" then return end
	if bot:GetAttribute("has_bullet") ~= true then return end
--	print("musket_module.fire called")
	bot:SetAttribute("has_bullet", false)
	bot:SetAttribute("musket_state", "fire")
	play_anim(bot, animids.fire, false, function()
		bot:SetAttribute("musket_state", "reloadidle")
		play_anim(bot, animids.reload_idle, true)
	end)
end

-- reload command: reloadidle -> reload -> idle (only if no bullet)
function module.reload(bot)
	-- reload musket only if bot is in reloadidle and has no bullet
	if bot:GetAttribute("musket_state") ~= "reloadidle" then return end
	if bot:GetAttribute("has_bullet") == true then return end
--	print("musket_module.reload called")
	bot:SetAttribute("musket_state", "reloading")
	play_anim(bot, animids.reload, false, function()
		bot:SetAttribute("has_bullet", true)
		module.set_idle(bot)
	end)
end

-- cease command: force to idle but do NOT change bullet state
function module.cease(bot)
	-- force bot into appropriate idle state without changing bullet
--	print("musket_module.cease called")
	module.stop_all(bot)
	if bot:GetAttribute("has_bullet") == true then
		bot:SetAttribute("musket_state", "idle")
		play_anim(bot, animids.idle, true)
	else
		bot:SetAttribute("musket_state", "reloadidle")
		play_anim(bot, animids.reload_idle, true)
	end
end

return module
