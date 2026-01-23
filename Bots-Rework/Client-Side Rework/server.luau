-- server formation bot controller

local players = game:GetService("Players")
local runservice = game:GetService("RunService")
local replicatedstorage = game:GetService("ReplicatedStorage")
local physicsservice = game:GetService("PhysicsService")

local snapshotEvent = replicatedstorage:WaitForChild("bot_snapshot")
local cmdEvent = replicatedstorage:WaitForChild("bot_cmd")

local bots = {}          -- [id] = bot
local companies = {}     -- [player] = company
local nextId = 1

local SPACING_X = 5
local SPACING_Z = 4
local MOVE_SPEED = 16


-- collision setup
pcall(function()
	physicsservice:CreateCollisionGroup("bots")
	physicsservice:CreateCollisionGroup("players")
end)

-- bots collide with nothing
physicsservice:CollisionGroupSetCollidable("bots", "bots", false)
physicsservice:CollisionGroupSetCollidable("bots", "players", false)


-- puts entire character into a collision group
local function setCharacterGroup(char, group)
	-- sets collision group for all parts
	for _, obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BasePart") then
			physicsservice:SetPartCollisionGroup(obj, group)
		end
	end
end


local function setCharacterGroupDeep(char, group)
	-- ensures every part always stays in the correct group
	for _, obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BasePart") then
			physicsservice:SetPartCollisionGroup(obj, group)
		end
	end

	char.DescendantAdded:Connect(function(obj)
		if obj:IsA("BasePart") then
			physicsservice:SetPartCollisionGroup(obj, group)
		end
	end)
end


-- creates one logical bot
local function createBot(owner, position)
	-- creates server-only logical soldier
	local bot = {
		id = nextId,
		owner = owner,
		position = position,
		target = position,
		speed = MOVE_SPEED,
		moving = false
	}

	bots[nextId] = bot
	nextId += 1

	return bot
end


-- builds formation offsets (depth = rows)
local function buildOffsets(count, rows)
	-- rows = number of ranks (depth)
	rows = math.max(1, rows)

	local offsets = {}

	-- width per rank
	local perRank = math.ceil(count / rows)

	local halfW = (perRank - 1) * 0.5

	local index = 1

	-- fill LEFT/RIGHT first, then go BACK each rank
	for r = 0, rows - 1 do
		for c = 0, perRank - 1 do
			if index > count then break end

			offsets[index] = Vector3.new(
				(c - halfW) * SPACING_X, -- spread width
				0,
				r * SPACING_Z -- each rank goes behind player
			)

			index += 1
		end
	end

	return offsets
end


-- returns or creates company for player
local function getCompany(player)
	-- stores formation state
	if companies[player] then
		return companies[player]
	end

	companies[player] = {
		player = player,
		rows = 2,
		botList = {}
	}

	return companies[player]
end


-- assigns formation targets and rotates with player
local function updateFormation(company)
	-- positions bots trailing the player
	local char = company.player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local count = #company.botList
	if count == 0 then return end

	local offsets = buildOffsets(count, company.rows)

	-- base starts directly behind player
	local base = root.CFrame

	for i, bot in ipairs(company.botList) do
		bot.target = (base * CFrame.new(offsets[i])).Position
	end
end


-- moves bot toward assigned slot
local function updateBot(bot, dt)
	local delta = bot.target - bot.position
	local dist = delta.Magnitude

	if dist > 0.05 then
		local step = bot.speed * dt

		if step >= dist then
			bot.position = bot.target
		else
			bot.position += delta.Unit * step
		end

		bot.moving = true
	else
		bot.position = bot.target
		bot.moving = false
	end
end

--[[
local function updateBot(bot, dt)
	-- simple linear movement
	local delta = bot.target - bot.position
	local dist = delta.Magnitude

	if dist > 0.1 then
		bot.position += delta.Unit * bot.speed * dt
		bot.moving = true
	else
		bot.moving = false
	end
end
--[[]]

--------------------------------------------------------------------
-- builds snapshot for client renderer
--------------------------------------------------------------------
local function buildSnapshot()
	-- packs minimal replication data
	local snapshot = {}

	for id, bot in pairs(bots) do
		snapshot[id] = {
			id = id,
			position = bot.position,
			speed = bot.speed,
			moving = bot.moving
		}
	end

	return snapshot
end

local function resetCompany(player)
	local company = companies[player]
	if not company then return end

	for _, bot in ipairs(company.botList) do
		bots[bot.id] = nil
	end

	companies[player] = nil

	-- reuse ids to prevent infinite growth / client churn
	nextId = 1
end

--[[
local function resetCompany(player)
	-- deletes bots and removes company entry
	local company = companies[player]
	if not company then return end

	for _, bot in ipairs(company.botList) do
		bots[bot.id] = nil
	end

	companies[player] = nil -- remove table completely
end
--[[]]

-- spawns bots for player

local function spawnBots(player, amount)
	-- always clear old company first (prevents lock state)
	resetCompany(player)

	amount = math.clamp(tonumber(amount) or 0, 1, 300)

	local char = player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local company = getCompany(player)

	for i = 1, amount do
		local bot = createBot(player, root.Position)
		table.insert(company.botList, bot)
	end
end

-- changes row depth
local function setRows(player, rows)
	-- sets exact number of ranks
	rows = math.clamp(tonumber(rows) or 1, 1, 30)

	local company = getCompany(player)
	company.rows = rows
end


-- command handler (shared by chat + gui)
local function handleCommand(player, message)
	-- parses "/spawn 50", "/row 3", "/reset"
	if type(message) ~= "string" then
		return
	end

	local args = string.split(message, " ")
	local cmd = string.lower(args[1] or "")

	if cmd == "/spawn" then
		spawnBots(player, args[2])

	elseif cmd == "/row" then
		setRows(player, args[2])

	elseif cmd == "/reset" then
		resetCompany(player)
	end
end


-- chat + gui input wiring
players.PlayerAdded:Connect(function(player)

	player.CharacterAdded:Connect(function(char)
		-- players use non-colliding group permanently
		setCharacterGroupDeep(char, "players")
	end)

	-- normal roblox chat support
	player.Chatted:Connect(function(message)
		handleCommand(player, message)
	end)
end)


-- gui fallback support
cmdEvent.OnServerEvent:Connect(function(player, message)
	handleCommand(player, message)
end)


-- main simulation loop
runservice.Heartbeat:Connect(function(dt)
	for _, company in pairs(companies) do
		updateFormation(company)

		for _, bot in ipairs(company.botList) do
			updateBot(bot, dt)
		end
	end
end)


-- network snapshot loop
task.spawn(function()
	while true do
		task.wait(0.25)
		snapshotEvent:FireAllClients(buildSnapshot())
	end
end)