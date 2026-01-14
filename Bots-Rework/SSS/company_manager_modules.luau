-- company_manager (modules)
local module = {}

local physics = game:GetService("PhysicsService")
local workspace = workspace
local replicatedstorage = game:GetService("ReplicatedStorage")

local musket = require(script.Parent.musket_module)
local formation = require(script.Parent.formation_module)

local bmusket = replicatedstorage:WaitForChild("Asset"):WaitForChild("bmusket")

-- storage for companies keyed by player
local companies = {}

-- ensure collision groups exist and are configured
pcall(function() physics:CreateCollisionGroup("soldier") end)
pcall(function() physics:CreateCollisionGroup("player") end)
physics:CollisionGroupSetCollidable("soldier", "soldier", false)
physics:CollisionGroupSetCollidable("soldier", "player", false)

-- world folder for companies
local companiesfolder = Instance.new("Folder")
companiesfolder.Name = "companies"
companiesfolder.Parent = workspace
-- print("company_manager: companies folder created")

-- tag bot model with Team and OwnBy under humanoid
function module.tag_bot(bot, player)
	-- attach Team and OwnBy values under bot humanoid for identification
	print("company_manager.tag_bot called")
	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then return end

	local team = humanoid:FindFirstChild("Team")
	if not team then
		team = Instance.new("StringValue")
		team.Name = "Team"
		team.Parent = humanoid
	end

	local owner = humanoid:FindFirstChild("OwnBy")
	if not owner then
		owner = Instance.new("StringValue")
		owner.Name = "OwnBy"
		owner.Parent = humanoid
	end

	team.Value = player.Team and player.Team.Name or "none"
	owner.Value = player.Name
end

-- tag player character humanoid with Team string
function module.tag_player_team(player, character)
	-- create Team string under player's humanoid for later use
	print("company_manager.tag_player_team called")
	local humanoid = character:WaitForChild("Humanoid")
	local tag = humanoid:FindFirstChild("Team")
	if not tag then
		tag = Instance.new("StringValue")
		tag.Name = "Team"
		tag.Parent = humanoid
	end
	tag.Value = player.Team and player.Team.Name or "none"
end

-- create soldier bot with physics and network ownership configured
function module.create_soldier(position, owner)
	-- create bot, set network owner and collision group, prepare attributes and death handler
	print("company_manager.create_soldier called")
	local bot = bmusket:Clone()
	bot.Parent = workspace
	bot:PivotTo(CFrame.new(position))

	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		print("company_manager.create_soldier: invalid bmusket")
		pcall(function() bot:Destroy() end)
		return nil
	end

	for _, p in ipairs(bot:GetDescendants()) do
		if p:IsA("BasePart") then
			-- set server network ownership and soldier collision group
			p:SetNetworkOwner(nil)
			physics:SetPartCollisionGroup(p, "soldier")
		end
	end

	-- set base attributes
	bot:SetAttribute("slot", -1)
	bot:SetAttribute("targetx", 0)
	bot:SetAttribute("targetz", 0)

	-- tagging
	module.tag_bot(bot, owner)

	-- initialize musket attributes and start idle
	musket.init(bot)
	musket.set_idle(bot)

	-- death handling: mark slot empty and cleanup
	humanoid.Died:Connect(function()
		print("company_manager: soldier died")
		local company = companies[owner]
		if company then
			local slot = bot:GetAttribute("slot")
			if slot and slot > 0 then
				company.slots[slot] = false
				company.count = company.count - 1
			end
		end
		musket.stop_all(bot)
		pcall(function() bot:Destroy() end)
	end)

	return bot
end

-- destroy company for player (cleanup)
function module.destroy_company(player)
	-- remove bots and delete the company folder
	print("company_manager.destroy_company called")
	local company = companies[player]
	if not company then return end

	for i = 1, company.maxslots do
		local bot = company.slots[i]
		if bot and bot ~= false then
			musket.stop_all(bot)
			pcall(function() bot:Destroy() end)
		end
	end

	if company.folder then
		pcall(function() company.folder:Destroy() end)
	end

	companies[player] = nil
end

local max_bots_per_player = 165 --fucyou

-- spawn company: creates folder and spawns bots in center-out order
function module.spawn_company(player, count)
	-- create per-player company folder, spawn bots in center-out file order, initialize musket state
	print("company_manager.spawn_company called", player.Name, count)
	if companies[player] then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
	
	count = math.clamp(count or 0, 1, max_bots_per_player)
	
	local companyfolder = Instance.new("Folder")
	companyfolder.Name = player.Name .. "_company"
	companyfolder.Parent = companiesfolder

	local rows = 5 -- default rows; can be changed later via /row
	local company = {
		slots = {},
		rows = rows,
		count = count,
		maxslots = count,
		follow = true,
		anchor = player.Character.HumanoidRootPart.CFrame,
		folder = companyfolder
	}

	-- compute columns and center-out order
	local columns = math.ceil(company.maxslots / company.rows)
	local fileorder = formation.build_file_order(columns)

	-- spawn in row-major using the center-out file order per row
	local spawn_pos = player.Character.HumanoidRootPart.Position
	local index = 1

	for row = 0, company.rows - 1 do
		for _, file in ipairs(fileorder) do
			local slot = row * columns + file
			if slot <= company.maxslots then
				local bot = module.create_soldier(spawn_pos, player)
				if bot then
					bot.Parent = companyfolder
					bot:SetAttribute("slot", slot)
					company.slots[slot] = bot
					-- ensure musket ready
					musket.init(bot)
					musket.set_idle(bot)
				else
					company.slots[slot] = false
				end
				index = index + 1
			end
		end
	end

	companies[player] = company
end

-- expose companies table (read-only style usage)
function module.get_companies()
	return companies
end

-- expose utilities from formation module for convenience
function module.rebuiltslots(player)
	local company = companies[player]
	if not company then return end
	formation.rebuiltslots(company)
end

function module.fillgaps(player)
	local company = companies[player]
	if not company then return end
	formation.fillgaps(company)
end

function module.is_front_rank(player, bot)
	local company = companies[player]
	if not company then return false end
	return formation.is_front_rank(company, bot)
end

-- update formation for a player (anchor supplied)
function module.update_company(player, anchor_cframe, spacing, stoptolerance)
	local company = companies[player]
	if not company then return end
	formation.update_formation(company, anchor_cframe, spacing, stoptolerance)
end

-- return module
return module
