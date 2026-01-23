-- server script
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
physicsservice:CollisionGroupSetCollidable("bots", "bots", false)
physicsservice:CollisionGroupSetCollidable("bots", "players", false)

-- character collision helper
local function setCharacterGroupDeep(char, group)
	for _, obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BasePart") then
			physicsservice:SetPartCollisionGroup(obj, group)
		end
	end

	char.DescendantAdded:Connect(function(obj)
		if obj:IsA("BasePart") then
			if obj:IsA("BasePart") then
				physicsservice:SetPartCollisionGroup(obj, group)
			end
		end
	end)
end

-- create bot
local function createBot(owner, position, rank)
	local bot = {
		id = nextId,
		owner = owner,
		position = position,
		target = position,
		speed = MOVE_SPEED,
		moving = false,
		rank = rank or 1,
		alive = true
	}
	bots[nextId] = bot
	nextId += 1
	return bot
end

-- build offsets evenly across rows, center-first
local function buildOffsets(count, rows)
	rows = math.max(1, rows)
	local offsets = {}

	local basePerRow = math.floor(count / rows)
	local extra = count % rows
	local index = 1

	local function centeredOrder(n)
		local t = {0}
		for i = 1, n do
			table.insert(t, i)
			table.insert(t, -i)
		end
		return t
	end

	for r = 0, rows - 1 do
		local thisRowCount = basePerRow
		if r < extra then
			thisRowCount += 1
		end

		local order = centeredOrder(thisRowCount - 1)

		for _, c in ipairs(order) do
			if index > count then break end
			offsets[index] = {
				pos = Vector3.new(c * SPACING_X, 0, r * SPACING_Z),
				rank = r + 1
			}
			index += 1
		end
	end

	return offsets
end

-- get or create company
local function getCompany(player)
	if companies[player] then return companies[player] end
	companies[player] = {player = player, rows = 2, botList = {}}
	return companies[player]
end

-- update formation + assign ranks
local function updateFormation(company)
	local char = company.player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local count = #company.botList
	if count == 0 then return end

	local rows = company.rows
	local perRow = math.floor(count / rows)
	local extra = count % rows

	local index = 1
	local base = root.CFrame

	for r = 0, rows - 1 do
		local thisRowCount = perRow
		if r < extra then
			thisRowCount += 1
		end

		-- get bots for this row
		for i = 0, thisRowCount - 1 do
			local bot = company.botList[index]
			if not bot then break end

			-- centered spread
			local c = 0
			if i > 0 then
				if i % 2 == 1 then
					c = math.ceil(i/2)
				else
					c = -math.ceil(i/2)
				end
			end

			bot.target = (base * CFrame.new(c * SPACING_X, 0, r * SPACING_Z)).Position
			bot.rank = r + 1

			index += 1
		end
	end
end

-- move bot
local function updateBot(bot, dt)
	local delta = bot.target - bot.position
	local dist = delta.Magnitude

	if dist > 0.05 then
		-- speed boost if far
		local speed = bot.speed
		if dist > 20 then           -- tweak this threshold
			speed = bot.speed * 2    -- double speed when far
		elseif dist > 10 then
			speed = bot.speed * 1.5  -- 1.5x speed at mid-distance
		end

		local step = speed * dt
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

-- bot death
local function killBot(bot)
	if not bot or not bot.alive then return end
	bot.alive = false
	bots[bot.id] = nil

	local company = companies[bot.owner]
	if not company then return end

	for i, b in ipairs(company.botList) do
		if b == bot then
			table.remove(company.botList, i)
			break
		end
	end
end

-- snapshot
local function buildSnapshot()
	local snapshot = {}
	for id, bot in pairs(bots) do
		local boost = 1
		local dist = (bot.target - bot.position).Magnitude
		if dist > 20 then
			boost = 2
		elseif dist > 10 then
			boost = 1.5
		end

		snapshot[id] = {
			id = id,
			position = bot.position,
			speed = bot.speed * boost, -- send boosted speed
			moving = bot.moving,
			rank = bot.rank
		}
	end
	return snapshot
end


-- reset company
local function resetCompany(player)
	local company = companies[player]
	if not company then return end
	for _, bot in ipairs(company.botList) do
		bots[bot.id] = nil
	end
	companies[player] = nil
	nextId = 1
end

-- spawn bots
local function spawnBots(player, amount)
	resetCompany(player)
	amount = math.clamp(tonumber(amount) or 0, 1, 300)

	local char = player.Character or player.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart")

	local company = getCompany(player)

	for i = 1, amount do
		local bot = createBot(player, root.Position, 1)
		table.insert(company.botList, bot)
	end
end

-- set rows
local function setRows(player, rows)
	rows = math.clamp(tonumber(rows) or 1, 1, 30)
	local company = getCompany(player)
	company.rows = rows
end

-- handle command
local function handleCommand(player, message)
	if type(message) ~= "string" then return end
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

-- player events
players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		setCharacterGroupDeep(char, "players")
	end)
	player.Chatted:Connect(function(message)
		handleCommand(player, message)
	end)
end)

cmdEvent.OnServerEvent:Connect(handleCommand)

-- heartbeat
runservice.Heartbeat:Connect(function(dt)
	for _, company in pairs(companies) do
		updateFormation(company)
		for _, bot in ipairs(company.botList) do
			updateBot(bot, dt)
		end
	end
end)

-- snapshot loop
task.spawn(function()
	while true do
		task.wait(0.25)
		snapshotEvent:FireAllClients(buildSnapshot())
	end
end)

-- end of server script