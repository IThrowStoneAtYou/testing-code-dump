local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

local SOLDIER_MODEL = ServerStorage:WaitForChild("Soldier")

-- formation tuning
local SPACING_X = 4
local SPACING_Z = 5

local POSITION_EPSILON = 0.5
local ROTATION_EPSILON = 0.02

local FOLLOW_UPDATE_RATE = 0.1 -- seconds (updates/sec)
local followAccumulator = 0

local MAX_UNITS = 100

local function setupCollisionGroups()
	local success, err

	success, err = pcall(function()
		PhysicsService:CreateCollisionGroup("Soldiers")
	end)

	success, err = pcall(function()
		PhysicsService:CreateCollisionGroup("Players")
	end)

	-- Soldiers do NOT collide with Soldiers
	PhysicsService:CollisionGroupSetCollidable("Soldiers", "Soldiers", false)

	-- Soldiers do NOT collide with Players
	PhysicsService:CollisionGroupSetCollidable("Soldiers", "Players", false)
end

setupCollisionGroups()


-- data
local PlayerData = {}

local function getData(player)
	if not PlayerData[player] then
		PlayerData[player] = {
			units = {},
			following = false,
			ranks = 1,
			lastPos = nil,
			lastLook = nil,
			spawned = false
		}
	end
	return PlayerData[player]
end


-- SPAWN
local function spawnUnits(player, amount)
	local data = getData(player)
	if data.spawned then return end

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
		unit:SetAttribute("MoveVersion", 0)
		table.insert(data.units, unit)
	end
	
	data.spawned = true
end

local function resetUnits(player)
	local data = getData(player)

	for _, unit in ipairs(data.units) do
		if unit and unit.Parent then
			unit:Destroy()
		end
	end

	data.units = {}
	data.following = false
	data.ranks = 1
	data.lastPos = nil
	data.lastLook = nil
	data.spawned = false
end

local function moveUnit(unit, targetPos)
	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	local root = unit.PrimaryPart
	if not humanoid or not root then return end

	local dist = (root.Position - targetPos).Magnitude
	if dist < 0.75 then return end

	-- increment version
	local version = (unit:GetAttribute("MoveVersion") or 0) + 1
	unit:SetAttribute("MoveVersion", version)

	-- speed up stragglers
	humanoid.WalkSpeed = dist > 20 and 20 or 18
	humanoid:MoveTo(targetPos)

	task.spawn(function()
		local reached = humanoid.MoveToFinished:Wait()

		-- ignore stale commands
		if unit:GetAttribute("MoveVersion") ~= version then
			return
		end

		if not reached then
			humanoid:MoveTo(targetPos)
		end
	end)
end

-- FORMATION CALC 
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
		
		local hrp = unit.PrimaryPart
		if hrp and (hrp.Position - targetPos).Magnitude > 0.75 then
			moveUnit(unit, targetPos)
		end
	end
end

local function setCharacterCollision(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			PhysicsService:SetPartCollisionGroup(part, "Players")
		end
	end
end

-- HEARTBEAT FOLLOW UPDATE
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

		if not data.lastLook or (look - data.lastLook).Magnitude > ROTATION_EPSILON then
			moved = true
		end

		if moved then
			data.lastPos = pos
			data.lastLook = look
			applyLineFormation(player)
		end
	end
end)

-- CHAT COMMANDS
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		setCharacterCollision(character)
	end)
	
	player.Chatted:Connect(function(msg)
		if msg:sub(1,1) ~= "/" then return end

		local args = string.split(msg, " ")
		local cmd = args[1]:lower()

		if cmd == "/spawn" then
			local count = tonumber(args[2])
			if count and count > 0 and count <= MAX_UNITS then
				spawnUnits(player, count)
			end

		elseif cmd == "/line" then
			local ranks = tonumber(args[2])
			if ranks and ranks >= 1 then
				local data = getData(player)
				
				data.ranks = math.floor(ranks)
				data.lastPos = nil
				data.lastLook = nil
				
				applyLineFormation(player)
			end

		elseif cmd == "/follow" then
			local data = getData(player)
			data.following = true
			data.lastPos = nil
			data.lastLook = nil

		elseif cmd == "/halt" then
			--	setFollow(player, false) -- it fucking broke-
			local data = getData(player)
			data.following = false
		
		elseif cmd == "/reset" then
			resetUnits(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerData[player] = nil
end)
