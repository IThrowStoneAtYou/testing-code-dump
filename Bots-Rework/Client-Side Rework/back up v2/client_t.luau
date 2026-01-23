-- local script
-- client npc renderer
local replicatedstorage = game:GetService("ReplicatedStorage")
local physicsservice = game:GetService("PhysicsService")

local snapshotEvent = replicatedstorage:WaitForChild("bot_snapshot")
local rigTemplate = replicatedstorage:WaitForChild("npc_rig")

local animFolder = replicatedstorage:WaitForChild("movement_anim")
local idleAnim = animFolder:WaitForChild("idle")
local walkAnim = animFolder:WaitForChild("walk")

local bots = {}


-- loads both animations once and stores tracks
local function setupAnimations(humanoid)
	local animator = humanoid:WaitForChild("Animator")

	local idleTrack = animator:LoadAnimation(idleAnim)
	idleTrack.Looped = true

	local walkTrack = animator:LoadAnimation(walkAnim)
	walkTrack.Looped = true

	idleTrack:Play()

	return idleTrack, walkTrack
end


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

	local idleTrack, walkTrack = setupAnimations(humanoid)

	bots[id] = {
		rig = rig,
		humanoid = humanoid,
		idle = idleTrack,
		walk = walkTrack,
		currentState = "idle",
		lastTarget = position
	}
end

-- switches animation safely
local function setAnimation(bot, moving)
	-- toggles between idle and walk
	if moving and bot.currentState ~= "walk" then
		bot.idle:Stop()
		bot.walk:Play()
		bot.currentState = "walk"

	elseif not moving and bot.currentState ~= "idle" then
		bot.walk:Stop()
		bot.idle:Play()
		bot.currentState = "idle"
	end
end


local function applySnapshot(snapshot)
	local seen = {}

	for id, data in pairs(snapshot) do
		seen[id] = true

		local bot = bots[id]

		if not bot then
			createVisualBot(id, data.position)
			bot = bots[id]
		end

		if bot and bot.humanoid and data.position then
			bot.humanoid.WalkSpeed = data.speed

			-- only MoveTo if target meaningfully changed (prevents MoveTo flood)
			if (bot.lastTarget - data.position).Magnitude > 0.5 then
				bot.humanoid:MoveTo(data.position)
				bot.lastTarget = data.position
			end

			setAnimation(bot, data.moving)
		end
	end

	-- destroy removed bots and stop tracks first
	for id, bot in pairs(bots) do
		if not seen[id] then
			if bot.idle then bot.idle:Stop() end
			if bot.walk then bot.walk:Stop() end
			if bot.rig then bot.rig:Destroy() end
			bots[id] = nil
		end
	end
end

snapshotEvent.OnClientEvent:Connect(applySnapshot)

-- end of local script