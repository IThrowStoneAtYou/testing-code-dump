
local players = game:GetService("Players")
local runservice = game:GetService("RunService")
local replicatedstorage = game:GetService("ReplicatedStorage")

local bmusket = replicatedstorage:WaitForChild("Asset"):WaitForChild("bmusket")

-- collision setup

-- this function registers and configures all collision groups
local function setupcollisiongroups()
	print("setupcollisiongroups called")

	local physics = game:GetService("PhysicsService")

	-- soldier group
	if not physics:IsCollisionGroupRegistered("soldier") then
		physics:RegisterCollisionGroup("soldier")
		print("registered collision group soldier")
	end

	-- player group
	if not physics:IsCollisionGroupRegistered("player") then
		physics:RegisterCollisionGroup("player")
		print("registered collision group player")
	end

	-- soldier vs soldier off
	physics:CollisionGroupSetCollidable("soldier", "soldier", false)
	print("disabled soldier vs soldier collision")

	-- soldier vs player off
	physics:CollisionGroupSetCollidable("soldier", "player", false)
	print("disabled soldier vs player collision")
end

setupcollisiongroups()
print("collision groups initialized")

-- this function assigns all parts of a model into a collision group
local function setmodelcollision(model, groupname)
	print("setmodelcollision called for", model.Name, "group", groupname)

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.CollisionGroup = groupname
		end
	end
end

-- world folders

local companiesfolder = Instance.new("Folder")
companiesfolder.Name = "companies"
companiesfolder.Parent = workspace

-- formation settings

local spacing = {side = 6, front = 7, back = 10}
local formationrate = 0.12
local stoptolerance = 1.5

-- data

local companies = {}

-- utility

local function countslots(slots)
	local n = 0
	for _, _ in pairs(slots) do n += 1 end
	return n
end

-- create soldier

local function createsoldier(position, owner)
	print("creating soldier for", owner.Name)

	local bot = bmusket:Clone()
	bot.Parent = companiesfolder
	bot:PivotTo(CFrame.new(position))

	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")

	if not humanoid or not root then
		print("invalid bmusket model")
		bot:Destroy()
		return nil
	end

	setmodelcollision(bot, "soldier")
	print("soldier collision applied")

	bot:SetAttribute("slot", -1)
	bot:SetAttribute("targetx", 0)
	bot:SetAttribute("targetz", 0)

	humanoid.Died:Connect(function()
		print("soldier died for", owner.Name)

		local company = companies[owner]
		if company then
			local slot = bot:GetAttribute("slot")
			if slot and slot > 0 then
				company.slots[slot] = false
				company.count -= 1
			end
		end

		bot:Destroy()
	end)

	return bot
end

-- destroy company

local function destroycompany(player)
	if not companies[player] then return end
	print("destroying company for", player.Name)

	for _, bot in pairs(companies[player].slots) do
		if bot then bot:Destroy() end
	end

	companies[player] = nil
end

-- gap filling using nearest rear soldier

local function fillgaps(company)
	print("executing real napoleonic gap repair")

	local slots = company.slots
	local rows = company.rows
	local columns = company.width

	-- flatten grid into row arrays
	local grid = {}

	for r = 1, rows do
		grid[r] = {}
		for c = 1, columns do
			local s = (r - 1) * columns + c
			grid[r][c] = slots[s]
		end
	end

	-- front rank never moves
	for r = 2, rows do
		for c = 1, columns do
			if grid[1][c] == false and grid[r][c] and grid[r][c] ~= false then
				print("pulling soldier up from row", r, "col", c)
				grid[1][c] = grid[r][c]
				grid[r][c] = false
				grid[1][c]:SetAttribute("slot", c)
			end
		end
	end

	-- now every rank closes sideways
	for r = 1, rows do
		local write = 1
		for read = 1, columns do
			if grid[r][read] and grid[r][read] ~= false then
				if read ~= write then
					print("sliding rank", r, "from", read, "to", write)
					grid[r][write] = grid[r][read]
					grid[r][read] = false
					grid[r][write]:SetAttribute("slot", (r - 1) * columns + write)
				end
				write += 1
			end
		end
	end

	-- rebuild slots
	for r = 1, rows do
		for c = 1, columns do
			local s = (r - 1) * columns + c
			slots[s] = grid[r][c]
		end
	end
end

-- formation update

local function updateformation(player)
	local company = companies[player]
	if not company then return end

	local anchor
	if company.follow then
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
		anchor = player.Character.HumanoidRootPart.CFrame
	else
		anchor = company.anchor
	end

	local columns = company.width

	for slot, bot in pairs(company.slots) do
		if bot and bot ~= false then
			local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
			local root = bot:FindFirstChild("HumanoidRootPart")
			if humanoid and root then
				local cf = anchor * CFrame.new(
					((slot - 1) % columns - (columns - 1) / 2) * spacing.side,
					0,
					math.floor((slot - 1) / columns) * spacing.front + spacing.back
				)

				local target = cf.Position
				if (root.Position - target).Magnitude > stoptolerance then
					if bot:GetAttribute("targetx") ~= target.X or bot:GetAttribute("targetz") ~= target.Z then
						bot:SetAttribute("targetx", target.X)
						bot:SetAttribute("targetz", target.Z)
						humanoid:MoveTo(target)
					end
				else
					humanoid:Move(Vector3.zero)
				end
			end
		end
	end
end

-- spawn company

local function spawncompany(player, count)
	if companies[player] then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end

	print("spawning", count, "soldiers for", player.Name)

	local company = {
		slots = {},
		rows = 1,
		count = count,
		width = count, -- locked front rank width
		follow = true,
		anchor = player.Character.HumanoidRootPart.CFrame
	}


	for i = 1, count do
		local bot = createsoldier(player.Character.HumanoidRootPart.Position, player)
		if bot then
			bot:SetAttribute("slot", i)
			company.slots[i] = bot
		end
	end

	companies[player] = company
end

-- commands

local function onchatted(player, msg)
	local args = string.split(string.lower(msg), " ")
	local company = companies[player]

	if args[1] == "/spawn" then
		local n = tonumber(args[2])
		if n then spawncompany(player, n) end
	end

	if args[1] == "/reset" then
		destroycompany(player)
	end

	if args[1] == "/row" and company then
		local n = tonumber(args[2])
		if n then
			n = math.max(1, n)
			n = math.min(n, company.count)

			print("rebuilding slots for new row count")

			-- extract soldiers in visual order
			local ordered = {}
			for i = 1, company.width * company.rows do
				local bot = company.slots[i]
				if bot and bot ~= false then
					table.insert(ordered, bot)
				end
			end

			company.rows = n
			company.width = math.ceil(#ordered / n)

			-- clear slots
			company.slots = {}

			-- reassign in row-major order
			for i, bot in ipairs(ordered) do
				company.slots[i] = bot
				bot:SetAttribute("slot", i)
			end

			print("rows now", company.rows, "width now", company.width)
		end
	end

	if args[1] == "/gaps" and company then
		fillgaps(company)
	end

	if args[1] == "/follow" and company then
		print("company following officer")
		company.follow = true
	end

	if args[1] == "/unfollow" and company then
		print("company anchored")
		company.follow = false
		company.anchor = player.Character.HumanoidRootPart.CFrame
	end
end

-- player handling

players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		onchatted(player, msg)
	end)

	player.CharacterAdded:Connect(function(char)
		for _, p in ipairs(char:GetDescendants()) do
			setmodelcollision(char, "player")
			print("player collision applied")
		end

		char.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") then
				obj.CollisionGroup = "player"
			end
		end)

		char:WaitForChild("Humanoid").Died:Connect(function()
			destroycompany(player)
		end)
	end)
end)

-- formation loop

local acc = 0
runservice.Heartbeat:Connect(function(dt)
	acc += dt
	if acc >= formationrate then
		acc = 0
		for player, _ in pairs(companies) do
			updateformation(player)
		end
	end
end)
