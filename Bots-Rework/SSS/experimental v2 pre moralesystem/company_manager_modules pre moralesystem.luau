-- company_manager (modules)
local module = {}

local physics = game:GetService("PhysicsService")
local workspace = workspace
local replicatedstorage = game:GetService("ReplicatedStorage")

local musket = require(script.Parent.musket_module)
local formation = require(script.Parent.formation_module)

local bmusket = replicatedstorage:WaitForChild("Asset"):WaitForChild("bmusket")
local morale_event = replicatedstorage:WaitForChild("morale_event")

-- storage for companies keyed by player
local companies = {}

local max_bots_per_player = 250

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

	debug.profilebegin("get_aim_align")

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
		align.Responsiveness = 20
		align.Enabled = false 
		align.Parent = root
	end

	debug.profileend()

	return align
end

local function update_aim(bot)
	--	print("update_aim") -- debug

	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	-- only aim during aim states
	local state = bot:GetAttribute("musket_state")
	if state ~= "aimidle" and state ~= "toaim" then
		local align = root:FindFirstChild("aim_align")
		if align then
			align.Enabled = false
		end
		return
	end

	-- read target ObjectValue
	local tag = hum:FindFirstChild("target")
	local target = tag and tag.Value
	if not target or not target.Parent then
		local align = root:FindFirstChild("aim_align")
		if align then
			align.Enabled = false
		end
		return
	end

	local thrp = target:FindFirstChild("HumanoidRootPart")
	if not thrp then return end

	-- get or create align
	local align = get_aim_align(bot)
	if not align then return end

	local from = root.Position
	local to = Vector3.new(thrp.Position.X, from.Y, thrp.Position.Z)

	align.CFrame = CFrame.lookAt(from, to)
	align.Enabled = true
end

function module.create_soldier(position, owner)
	-- create bot, set network owner and collision group, prepare attributes and death handler
	debug.profilebegin("create_soldier")

	local bot = bmusket:Clone()
	bot.Parent = workspace
	bot:PivotTo(CFrame.new(position))

	local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
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
	
	-- morale
	bot:SetAttribute("morale", 100)        -- individual morale
	bot:SetAttribute("morale_state", "steady") -- steady | shaken | wavering | broken

	-- set default walk speed
	if humanoid then pcall(function() humanoid.WalkSpeed = 16 end) end

	-- death handling: mark slot empty and cleanup
	humanoid.Died:Connect(function()
		-- death causes morale shock to the rest of the company
		local company = companies[owner]
		if company then
			for _, other in pairs(company.slots) do
				if other and other ~= false then
					local m = other:GetAttribute("morale") or 100
					other:SetAttribute("morale", math.clamp(m - 8, 0, 100))
				end
			end
		end

		musket.stop_all(bot)
		pcall(function() bot:Destroy() end)
	end)

	debug.profileend()

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

function module.get_company_morale(player)
	-- returns average morale of all alive bots
	local company = companies[player]
	if not company then return 0 end

	local total = 0
	local alive = 0

	for _, bot in pairs(company.slots) do
		if bot and bot ~= false then
			local m = bot:GetAttribute("morale") or 0
			total += m
			alive += 1
		end
	end

	if alive == 0 then return 0 end
	return math.floor(total / alive)
end

function module.apply_morale_damage(player, amount)
	-- applies morale loss to every bot in the company
	local company = companies[player]
	if not company then return end

	for _, bot in pairs(company.slots) do
		if bot and bot ~= false then
			local m = bot:GetAttribute("morale") or 100
			m = math.clamp(m - amount, 0, 100)
			bot:SetAttribute("morale", m)
		end
	end
end

morale_event.Event:Connect(function(player, amount)
	-- receives morale damage from musket hits and applies it to the company

	module.apply_morale_damage(player, amount)
end)

function module.get_enemy_centroid(company)
	-- returns the average position of all enemy humanoids

	local sum = Vector3.zero
	local count = 0

	for _, model in ipairs(workspace:GetChildren()) do
		local hum = model:FindFirstChildWhichIsA("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")

		if hum and root and hum.Health > 0 then
			local tag = hum:FindFirstChild("Team")
			if not tag or tag.Value ~= company.team then
				sum += root.Position
				count += 1
			end
		end
	end

	if count == 0 then return nil end
	return sum / count
end

function module.route_bot(bot, enemy_point)
	-- forces a broken bot to run away from the enemy centroid

	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	local dir = (root.Position - enemy_point).Unit
	local target = root.Position + dir * 250 -- run 250 studs away

	hum.WalkSpeed = 30
	hum:MoveTo(target)
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

-- this returns which rank a bot is in (1 = front)
local function get_rank(company, bot)
	-- simple math: slot index -> rank
	for i = 1, company.maxslots do
		if company.slots[i] == bot then
			return math.floor((i - 1) / math.ceil(company.maxslots / company.rows)) + 1
		end
	end
	return nil
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

			-- only front rank may fire
			if not formation.is_front_rank(company, bot) then
				task.wait(0.1)
				continue
			end

			-- random idle spacing
			if state == "idle" or state == "makereadyidle" or state == "aimidle" or state == "reloadidle" then
				local delaytime = math.random(20, 80) / 100
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
	end)

	return thread
end

function module.start_fireatwill(player)
	-- this runs a single fire-at-will scheduler with per-bot random idle delays

	local company = companies[player]
	if not company or company.fireatwill then return end

	company.fireatwill = true

	company._fire_thread = task.spawn(function()
		while company.fireatwill do
			for _, bot in pairs(company.slots) do
				if bot and bot ~= false and formation.is_front_rank(company, bot) then

					local state = bot:GetAttribute("musket_state")

					if state == "idle" then
						-- desync make ready
						task.spawn(function()
							task.wait(math.random(10, 60) / 100)
							if company.fireatwill and bot:GetAttribute("musket_state") == "idle" then
								musket.present(bot)
							end
						end)

					elseif state == "makereadyidle" then
						-- desync aim
						task.spawn(function()
							task.wait(math.random(10, 60) / 100)
							if company.fireatwill and bot:GetAttribute("musket_state") == "makereadyidle" then
								musket.aim(bot)
							end
						end)

					elseif state == "aimidle" and bot:GetAttribute("has_bullet") then
						-- desync fire
						task.spawn(function()
							task.wait(math.random(10, 60) / 100)
							if company.fireatwill and bot:GetAttribute("musket_state") == "aimidle" then
								musket.fire(bot)
							end
						end)

					elseif state == "reloadidle" then
						-- desync reload
						task.spawn(function()
							task.wait(math.random(20, 90) / 100)
							if company.fireatwill and bot:GetAttribute("musket_state") == "reloadidle" then
								musket.reload(bot)
							end
						end)
					end
				end
			end
			task.wait(0.25)
		end
	end)
end

function module.stop_fireatwill(player)
	-- this disables fire-at-will loop

	local company = companies[player]
	if not company then return end

	company.fireatwill = false
	if company._fire_thread then
		task.cancel(company._fire_thread)
		company._fire_thread = nil
	end
end

function module.start_rankbyrank(player)
	-- one time rolling fire: rank 1 fires, rank 2 presents on rank 1 fire, etc

	local company = companies[player]
	if not company then return end

	-- reset all bots
	for _, bot in pairs(company.slots) do
		if bot and bot ~= false then
			musket.init(bot)           -- reset musket attributes
			musket.set_idle(bot)       -- force idle start
		end
	end

	task.wait(0.5)

	for rank = 1, company.rows do

		-- present this rank
		for _, bot in pairs(company.slots) do
			if bot and bot ~= false and get_rank(company, bot) == rank then
				if bot:GetAttribute("musket_state") == "idle" then
					musket.present(bot)   -- start make ready
				end
			end
		end

		-- aim when ready (non blocking)
		for _, bot in pairs(company.slots) do
			if bot and bot ~= false and get_rank(company, bot) == rank then
				task.spawn(function()
					while true do
						if bot:GetAttribute("musket_state") == "makereadyidle" then
							musket.aim(bot) -- go to aim
							break
						end
						task.wait(0.05)
					end
				end)
			end
		end

		-- fire all bots in this rank exactly once
		local remaining = {}

		for _, bot in pairs(company.slots) do
			if bot and bot ~= false and get_rank(company, bot) == rank then
				remaining[bot] = true
			end
		end

		while next(remaining) do
			for bot in pairs(remaining) do
				if bot:GetAttribute("musket_state") == "aimidle"
					and bot:GetAttribute("has_bullet") == true then

					musket.fire(bot)       -- actual fire trigger
					remaining[bot] = nil   -- mark this bot done
				end
			end
			task.wait(0.05)
		end

		-- reload in background (does not block next rank)
		for _, bot in pairs(company.slots) do
			if bot and bot ~= false and get_rank(company, bot) == rank then
				task.spawn(function()
					while true do
						if bot:GetAttribute("musket_state") == "reloadidle" then
							musket.reload(bot) -- reload musket
							break
						end
						task.wait(0.1)
					end
				end)
			end
		end

		task.wait(0.2) -- small spacing before next rank
	end
end

function module.stop_rankbyrank(player)
	-- this stops rank by rank fire

	local company = companies[player]
	if not company then return end

	company.rankbyrank = false
end

-- continuous aim updater
task.spawn(function()
	while true do
		for _, company in pairs(companies) do
			for _, bot in pairs(company.slots) do
				if bot and bot ~= false then
					
					-- aiming
					local state = bot:GetAttribute("musket_state")
					if state == "aimidle" or state == "toaim" then
						update_aim(bot)
					end
					
					-- morale
					local m = bot:GetAttribute("morale") or 100
					local state

					if m > 70 then state = "steady"
					elseif m > 40 then state = "shaken"
					elseif m > 15 then state = "wavering"
					else state = "broken" end

					bot:SetAttribute("morale_state", state)

					if state == "broken" then
						-- broken bots stop obeying and flee
						musket.cease(bot)
						local enemy = module.get_enemy_centroid(company)
						if enemy then
							module.route_bot(bot, enemy)
						end
					end
				end
			end
		end
		task.wait(1)
	end
end)

return module
