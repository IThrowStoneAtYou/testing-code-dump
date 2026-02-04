-- local script
-- client npc renderer + musket system
local replicatedstorage = game:GetService("ReplicatedStorage")
local physicsservice = game:GetService("PhysicsService")

local snapshotEvent = replicatedstorage:WaitForChild("bot_snapshot")
local hitEvent = replicatedstorage:WaitForChild("bot_hit")
local cmdEvent = replicatedstorage:WaitForChild("bot_cmd")
local musketEvent = replicatedstorage:WaitForChild("bot_musket")

local rigTemplate = replicatedstorage:WaitForChild("ranker_rig")

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

local function spawnTracer(bot, hitPosition)
	-- visual only, no damage
	if not bot or not bot.rig then return end

	local musket = bot.rig:FindFirstChild("Musket", true)
	if not musket then return end

	local muzzle = musket:FindFirstChild("Muzzle", true)
	if not muzzle then return end

	local startPos = muzzle.Position
	local endPos = hitPosition

	local dist = (endPos - startPos).Magnitude
	if dist <= 0.01 then return end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(0.12, 0.12, dist)
	part.CFrame = CFrame.new((startPos + endPos) / 2, endPos)
	part.Material = Enum.Material.Neon
	part.Parent = workspace

	game:GetService("Debris"):AddItem(part, 0.1)
end

local function simulateLocalBullet(bot)
	-- client-only bullet simulation and hit detection
	if not bot or not bot.rig then return end

	local musket = bot.rig:FindFirstChild("Musket", true)
	if not musket then return end

	local muzzle = musket:FindFirstChild("Muzzle", true)
	if not muzzle then return end

	local origin = muzzle.Position
	local dir = muzzle.CFrame.LookVector * 300

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {bot.rig}

	local result = workspace:Raycast(origin, dir, params)

	local hitPos = origin + dir
	local hitBotId = nil

	if result then
		hitPos = result.Position

		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model and string.find(model.Name, "bot_") then
			local id = tonumber(string.match(model.Name, "%d+"))
			if id then
				hitBotId = id
			end
		end
	end

	spawnTracer(bot, hitPos)

	if hitBotId then
		hitEvent:FireServer(hitBotId)
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
			musket.has_bullet = false

			-- shoot instantly (no delay)
			simulateLocalBullet(bot)

			playMusket(bot, "Fire", false, function()
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

musketEvent.OnClientEvent:Connect(function(data)
	if not data or type(data.botId) ~= "number" then return end

	local bot = bots[data.botId]
	if not bot then return end

	-- tracer command from server
	if data.cmd == "tracer" then
		spawnTracer(bot, data.hitPosition)
		return
	end

	-- normal animation commands
	if type(data.cmd) == "string" then
		handleMusketCommand(bot, data.cmd)
	end
end)