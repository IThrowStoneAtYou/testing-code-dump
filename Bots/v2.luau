local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local SOLDIER_MODEL = ServerStorage:WaitForChild("Soldier")

-- formation tuning
local SPACING_X = 4
local SPACING_Z = 5

local POSITION_EPSILON = 0.5
local ANGLE_EPSILON = math.rad(2)

local FOLLOW_UPDATE_RATE = 0.1
local followAccumulator = 0

local MAX_UNITS = 100

-- COLLISION GROUPS
local function setupCollisionGroups()
	pcall(function()
		PhysicsService:CreateCollisionGroup("Soldiers")
	end)

	pcall(function()
		PhysicsService:CreateCollisionGroup("Players")
	end)

	PhysicsService:CollisionGroupSetCollidable("Soldiers", "Soldiers", false)
	PhysicsService:CollisionGroupSetCollidable("Soldiers", "Players", false)
end

setupCollisionGroups()

-- DATA
local PlayerData = {}

local function getData(player)
	if not PlayerData[player] then
		PlayerData[player] = {
			units = {},
			following = false,
			ranks = 1,
			lastPos = nil,
			lastLook = nil,
		}
	end
	return PlayerData[player]
end

-- CLEANUP
local function clearUnits(data)
	for _, unit in ipairs(data.units) do
		if unit and unit.Parent then
			unit:Destroy()
		end
	end
	data.units = {}
end

-- SPAWN
local function spawnUnits(player, amount)
	local data = getData(player)

	clearUnits(data)

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end
	local root = char.HumanoidRootPart

	for i = 1, amount do
		local unit = SOLDIER_MODEL:Clone()
		unit.Parent = workspace
		unit:PivotTo(root.CFrame * CFrame.new(0, 0, -10))

		for _, part in ipairs(unit:GetDescendants()) do
			if part:IsA("BasePart") then
				PhysicsService:SetPartCollisionGroup(part, "Soldiers")
			end
		end

		unit.PrimaryPart:SetNetworkOwner(nil)
		unit:SetAttribute("LastTarget", nil)

		table.insert(data.units, unit)
	end
end

-- MOVE (THREADS)
local function moveUnit(unit, targetPos)
	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	local root = unit.PrimaryPart
	if not humanoid or not root then return end

	local lastTarget = unit:GetAttribute("LastTarget")
	if lastTarget then
		if (lastTarget - targetPos).Magnitude < 0.25 then
			return
		end
	end

	unit:SetAttribute("LastTarget", targetPos)

	local dist = (root.Position - targetPos).Magnitude
	if dist < 0.75 then return end

	humanoid.WalkSpeed = dist > 20 and 20 or 18
	humanoid:MoveTo(targetPos)
end

-- FORMATION
local function applyLineFormation(player)
	local data = getData(player)
	local units = data.units
	if #units == 0 then return end

	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return end

	local root = char.HumanoidRootPart
	local origin = root.Position - root.CFrame.LookVector * 10
	local right = root.CFrame.RightVector
	local forward = root.CFrame.LookVector

	local ranks = math.max(1, data.ranks)
	local unitsPerRank = math.ceil(#units / ranks)

	for index, unit in ipairs(units) do
		local rank = math.floor((index - 1) / unitsPerRank)
		local file = (index - 1) % unitsPerRank

		local xOffset = (file - (unitsPerRank - 1) / 2) * SPACING_X
		local zOffset = rank * SPACING_Z

		local targetPos =
			origin
			+ right * xOffset
		- forward * zOffset

		moveUnit(unit, targetPos)
	end
end

-- CHARACTER COLLISION
local function onCharacterAdded(player, character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			PhysicsService:SetPartCollisionGroup(part, "Players")
		end
	end

	-- FORCE HALT ON RESPAWN
	local data = getData(player)
	data.following = false
	data.lastPos = nil
	data.lastLook = nil
end

-- HEARTBEAT FOLLOW
RunService.Heartbeat:Connect(function(dt)
	followAccumulator += dt
	if followAccumulator < FOLLOW_UPDATE_RATE then return end
	followAccumulator = 0

	for player, data in pairs(PlayerData) do
		if not data.following then continue end

		local char = player.Character
		if not char or not char:FindFirstChild("HumanoidRootPart") then continue end

		local root = char.HumanoidRootPart
		local pos = root.Position
		local look = root.CFrame.LookVector

		local moved = false

		if not data.lastPos or (pos - data.lastPos).Magnitude > POSITION_EPSILON then
			moved = true
		end

		if data.lastLook then
			local angle = math.acos(math.clamp(data.lastLook:Dot(look), -1, 1))
			if angle > ANGLE_EPSILON then
				moved = true
			end
		else
			moved = true
		end

		if moved then
			data.lastPos = pos
			data.lastLook = look
			applyLineFormation(player)
		end
	end
end)

-- COMMANDS
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)

	player.Chatted:Connect(function(msg)
		if msg:sub(1,1) ~= "/" then return end

		local args = string.split(msg, " ")
		local cmd = args[1]:lower()
		local data = getData(player)

		if cmd == "/spawn" then
			local count = tonumber(args[2])
			if count and count > 0 and count <= MAX_UNITS then
				spawnUnits(player, count)
			end

		elseif cmd == "/line" then
			local ranks = tonumber(args[2])
			if ranks and ranks >= 1 then
				data.ranks = math.floor(ranks)
				data.lastPos = nil
				data.lastLook = nil
				applyLineFormation(player)
			end

		elseif cmd == "/follow" then
			data.following = true
			data.lastPos = nil
			data.lastLook = nil

		elseif cmd == "/halt" then
			data.following = false

		elseif cmd == "/reset" then
			clearUnits(data)
			data.following = false
			data.lastPos = nil
			data.lastLook = nil
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	local data = PlayerData[player]
	if data then
		clearUnits(data)
	end
	PlayerData[player] = nil
end)
