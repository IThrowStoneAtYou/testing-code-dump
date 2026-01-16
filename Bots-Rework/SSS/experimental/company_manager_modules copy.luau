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

local max_bots_per_player = 185

-- ensure collision groups exist and are configured
pcall(function() physics:CreateCollisionGroup("soldier") end)
pcall(function() physics:CreateCollisionGroup("player") end)
physics:CollisionGroupSetCollidable("soldier", "soldier", false)
physics:CollisionGroupSetCollidable("soldier", "player", false)

-- world folder for companies
local companiesfolder = Instance.new("Folder")
companiesfolder.Name = "companies"
companiesfolder.Parent = workspace

-- tag bot model with Team and OwnBy under humanoid
function module.tag_bot(bot, player)
	-- attach Team and OwnBy values under bot humanoid for identification

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

function module.tag_player_team(player, character)
	-- create Team string under player's humanoid for later use

	local humanoid = character:WaitForChild("Humanoid")
	local tag = humanoid:FindFirstChild("Team")
	if not tag then
		tag = Instance.new("StringValue")
		tag.Name = "Team"
		tag.Parent = humanoid
	end
	tag.Value = player.Team and player.Team.Name or "none"
end

local function ensure_target_value(bot)

	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	if not hum then return nil end

	local tag = hum:FindFirstChild("target")
	if not tag then
		tag = Instance.new("ObjectValue")
		tag.Name = "target"
		tag.Value = nil
		tag.Parent = hum
	end

	return tag
end

local function get_aim_align(bot)
--	print("get_aim_align called")

	local root = bot:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local att = root:FindFirstChild("aim_attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "aim_attachment"
		att.Parent = root
	end

	local align = root:FindFirstChild("aim_align")
	if not align then
		align = Instance.new("AlignOrientation")
		align.Name = "aim_align"
		align.Attachment0 = att
		align.Mode = Enum.OrientationAlignmentMode.OneAttachment
		align.RigidityEnabled = false
		align.MaxTorque = math.huge
		align.Responsiveness = 17
		align.Parent = root
	end

	return align
end


function module.create_soldier(position, owner)
	-- create bot, set network owner and collision group, prepare attributes and death handler
--	print("company_manager.create_soldier called")
	local bot = bmusket:Clone()
	bot.Parent = workspace
	bot:PivotTo(CFrame.new(position))

	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
	--	print("company_manager.create_soldier: invalid bmusket")
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

	-- set default walk speed
	if humanoid then pcall(function() humanoid.WalkSpeed = 16 end) end

	-- death handling: mark slot empty and cleanup
	humanoid.Died:Connect(function()
	--	print("company_manager: soldier died")
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


function module.destroy_company(player)
	-- remove bots and delete the company folder

	local company = companies[player]
	if not company then return end

	-- ensure fire-at-will stopped
	module.stop_fireatwill(player)

	for i = 1, company.maxslots do
		local bot = company.slots[i]
		if bot and bot ~= false then
			musket.stop_all(bot)
			pcall(function() bot:Destroy() end)
		end
	end

	if company.folder then pcall(function() company.folder:Destroy() end) end

	companies[player] = nil
end

function module.spawn_company(player, count)
	-- create per-player company folder, spawn bots in center-out file order, initialize musket state
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
		folder = companyfolder,
		fireatwill = false, -- controls /fire2
		_fire_threads = {}, -- [bot] = thread
		anchor_locked = false,

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

-- continuously aim bot at its stored target
local function update_aim(bot)
--	print("update_aim called")

	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	local tag = hum:FindFirstChild("target")
	local target = tag and tag.Value
	if not target or not target.Parent then return end

	local thrp = target:FindFirstChild("HumanoidRootPart")
	if not thrp then return end

	local align = get_aim_align(bot)
	if not align then return end

	local from = root.Position
	local to = Vector3.new(thrp.Position.X, from.Y, thrp.Position.Z)

	align.CFrame = CFrame.lookAt(from, to)
end

-- expose companies table (read-only usage)
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

function module.face_company(player)
	
	local company = companies[player]
	if not company then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end

	local look = player.Character.HumanoidRootPart.CFrame.LookVector

	for _, bot in pairs(company.slots) do
		if bot and bot ~= false then
			local root = bot:FindFirstChild("HumanoidRootPart")
			if root then
				local pos = root.Position
				root.CFrame = CFrame.new(pos, pos + look)
			end
		end
	end
end

function module.is_front_rank(player, bot)
	-- wrapper kept for API parity (not used widely)
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

function module.can_bot_fire(company, bot)
	if not company or not bot then return false end
	return formation.is_front_rank(company, bot)
end

local function start_bot_fire_loop(company, bot)

	local thread = task.spawn(function()
		while company.fireatwill do
			if not bot or not bot.Parent then break end

			if bot:GetAttribute("musket_state") == nil or bot:GetAttribute("has_bullet") == nil then
				musket.init(bot)
				musket.set_idle(bot)
			end

			local state = bot:GetAttribute("musket_state")
			local has_bullet = bot:GetAttribute("has_bullet")

			-- only front rank may fire, gaps can promote bots
			if not formation.is_front_rank(company, bot) then
				task.wait(0.1)
				continue
			end

			-- random idle spacing
			if state == "idle" or state == "makereadyidle" or state == "aimidle" or state == "reloadidle" then
				local delaytime = math.random(20, 80) / 100
			--	print("fire2 idle delay", delaytime)
				local t = 0
				while t < delaytime and company.fireatwill do
					task.wait(0.05)
					t += 0.05
				end
			end

			if not company.fireatwill then break end

			if state == "idle" then
				musket.present(bot)

			elseif state == "makereadyidle" then
				musket.aim(bot)

			elseif state == "aimidle" and has_bullet == true then
				musket.fire(bot)

			elseif state == "reloadidle" and has_bullet == false then
				musket.reload(bot)

			else
				task.wait(0.05)
			end

			task.wait(0.02)
		end

	--	print("fire2 loop ended")
	end)

	return thread
end

function module.start_fireatwill(player)
	
	local company = companies[player]
	if not company then return end
	if company.fireatwill then return end

	company.fireatwill = true
	company._fire_threads = {}

	for i = 1, company.maxslots do
		local bot = company.slots[i]
		if bot and bot ~= false then
			if bot:GetAttribute("musket_state") == nil or bot:GetAttribute("has_bullet") == nil then
				musket.init(bot)
				musket.set_idle(bot)
			end

			company._fire_threads[bot] = start_bot_fire_loop(company, bot)
			task.wait(0.01)
		end
	end
end

function module.stop_fireatwill(player)

	local company = companies[player]
	if not company then return end

	company.fireatwill = false
	company._fire_threads = {}
end

-- continuously update aiming for all bots with targets
task.spawn(function()
	-- keeps bots smoothly facing their targets
	while true do
		for _, company in pairs(companies) do
			for _, bot in pairs(company.slots) do
				if bot and bot ~= false then
					update_aim(bot)
				end
			end
		end
		task.wait(0.05)
	end
end)


return module
