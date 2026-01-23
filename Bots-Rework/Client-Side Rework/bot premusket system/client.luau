-- local script
-- client npc renderer + musket system
local replicatedstorage = game:GetService("ReplicatedStorage")
local physicsservice = game:GetService("PhysicsService")

local snapshotEvent = replicatedstorage:WaitForChild("bot_snapshot")
local cmdEvent = replicatedstorage:WaitForChild("bot_cmd")
local rigTemplate = replicatedstorage:WaitForChild("npc_rig")

local movementAnimFolder = replicatedstorage:WaitForChild("movement_anim")
local idleAnim = movementAnimFolder:WaitForChild("idle")
local walkAnim = movementAnimFolder:WaitForChild("walk")

local musketAnimFolder = replicatedstorage:WaitForChild("musket_anim")

local bots = {}

-- setup movement animations for humanoid and return table
local function setupMovementAnimations(humanoid)
	local animator = humanoid:WaitForChild("Animator")

	local idleTrack = animator:LoadAnimation(idleAnim)
	idleTrack.Looped = true

	local walkTrack = animator:LoadAnimation(walkAnim)
	walkTrack.Looped = true

	idleTrack:Play()

	return {idle = idleTrack, walk = walkTrack, currentState = "idle"}
end

-- setup musket animations for humanoid; initial state Idle and has_bullet true
local function setupMusketAnimations(humanoid)
	local animator = humanoid:WaitForChild("Animator")
	local anims = {has_bullet = true, current = "Idle"}

	for _, anim in ipairs(musketAnimFolder:GetChildren()) do
		local track = animator:LoadAnimation(anim)
		if string.find(anim.Name, "Idle") then
			track.Looped = true
		end
		anims[anim.Name] = track
	end

	anims.currentTrack = anims["Idle"]
	if anims.currentTrack then
		anims.currentTrack:Play()
	end
	return anims
end

-- create visual bot and attach movement + musket systems
local function createVisualBot(id, position)
	local rig = rigTemplate:Clone()
	rig.Name = "bot_" .. id
	rig.Parent = workspace

	for _, p in ipairs(rig:GetDescendants()) do
		if p:IsA("BasePart") then
			physicsservice:SetPartCollisionGroup(p, "bots")
		end
	end

	rig:PivotTo(CFrame.new(position + Vector3.new(0, 3, 0)))

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		-- ensure humanoid exists before continuing
		rig:Destroy()
		return
	end

	local movement = setupMovementAnimations(humanoid)
	local musket = setupMusketAnimations(humanoid)

	bots[id] = {
		rig = rig,
		humanoid = humanoid,
		movement = movement,
		musket = musket,
		lastTarget = position
	}
end

-- toggle movement animations between idle and walk
local function setMovementAnimation(bot, moving)
	local m = bot.movement
	if moving and m.currentState ~= "walk" then
		m.idle:Stop()
		m.walk:Play()
		m.currentState = "walk"
	elseif not moving and m.currentState ~= "idle" then
		m.walk:Stop()
		m.idle:Play()
		m.currentState = "idle"
	end
end

-- play musket animation safely, call callback once finished
local function playMusket(bot, name, loop, callback)
	local musket = bot.musket
	if not musket then return end

	if musket.currentTrack then
		-- stop previous track
		musket.currentTrack:Stop()
	end

	musket.current = name
	musket.currentTrack = musket[name]
	if musket.currentTrack then
		musket.currentTrack.Looped = loop or false
		musket.currentTrack:Play()

		if callback then
			local conn
			conn = musket.currentTrack.Stopped:Connect(function()
				if conn then conn:Disconnect() end
				callback()
			end)
		end
	end
end

-- handle musket command for a single bot following the finite transitions you specified
local function handleMusketCommand(bot, cmd)
	local musket = bot.musket
	if not musket then return end

	if cmd == "/present" then
		if musket.current == "Idle" then
			playMusket(bot, "MakeReady", false, function()
				playMusket(bot, "MakeReadyIdle", true)
			end)
		end

	elseif cmd == "/aim" then
		if musket.current == "MakeReadyIdle" then
			playMusket(bot, "ToAim", false, function()
				playMusket(bot, "AimIdle", true)
			end)
		end

	elseif cmd == "/fire" then
		if musket.current == "AimIdle" then
			playMusket(bot, "Fire", false, function()
				musket.has_bullet = false
				playMusket(bot, "ReloadIdle", true)
			end)
		end

	elseif cmd == "/reload" then
		if musket.current == "ReloadIdle" then
			playMusket(bot, "Reload", false, function()
				musket.has_bullet = true
				playMusket(bot, "Idle", true)
			end)
		end

	elseif cmd == "/cease" then
		if musket.has_bullet then
			playMusket(bot, "Idle", true)
		else
			playMusket(bot, "ReloadIdle", true)
		end
	end
end

-- apply snapshot updates from server: create/update/destroy visuals and movement
local function applySnapshot(snapshot)
	local seen = {}

	for id, data in pairs(snapshot) do
		seen[id] = true

		local bot = bots[id]

		if not bot then
			if data.position then
				createVisualBot(id, data.position)
				bot = bots[id]
			end
		end

		if bot and bot.humanoid and data.position then
			-- update walk speed and MoveTo target
			bot.humanoid.WalkSpeed = data.speed

			if (bot.lastTarget - data.position).Magnitude > 0.5 then
				bot.humanoid:MoveTo(data.position)
				bot.lastTarget = data.position
			end

			setMovementAnimation(bot, data.moving)
		end
	end

	-- destroy removed bots and stop tracks
	for id, bot in pairs(bots) do
		if not seen[id] then
			local m = bot.movement
			if m and m.idle then m.idle:Stop() end
			if m and m.walk then m.walk:Stop() end

			local musket = bot.musket
			if musket then
				for k, track in pairs(musket) do
					if typeof(track) == "Instance" then
						track:Stop()
					end
				end
			end

			if bot.rig then bot.rig:Destroy() end
			bots[id] = nil
		end
	end
end

-- receive snapshots
snapshotEvent.OnClientEvent:Connect(applySnapshot)

-- receive musket commands from server for specific bot ids
cmdEvent.OnClientEvent:Connect(function(data)
	if not data or type(data.botId) ~= "number" or type(data.cmd) ~= "string" then return end
	local bot = bots[data.botId]
	if bot then
		handleMusketCommand(bot, data.cmd)
	end
end)
