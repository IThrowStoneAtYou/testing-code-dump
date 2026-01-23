-- company_manager (modules)
local module = {}

local physics = game:GetService("PhysicsService")
local workspace = workspace
local replicatedstorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local musket = require(script.Parent.musket_module)
local formation = require(script.Parent.formation_module)

local bmusket = replicatedstorage:WaitForChild("Asset"):WaitForChild("bmusket")
local morale_event = replicatedstorage:WaitForChild("morale_event") -- BindableEvent used internally

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

-- create a RemoteEvent for client GUI updates (if missing)
local morale_update_event = replicatedstorage:FindFirstChild("company_morale_update")
if not morale_update_event then
	morale_update_event = Instance.new("RemoteEvent")
	morale_update_event.Name = "company_morale_update"
	morale_update_event.Parent = replicatedstorage
end

-- tag bot model with Team and OwnBy under humanoid
function module.tag_bot(bot, player)
	-- simple tags: Team and OwnBy under humanoid
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
	-- store Team value under player's humanoid for later queries
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
	-- ensure a target ObjectValue exists under humanoid
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
	-- create or return AlignOrientation used for aiming
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

	return align
end

local function update_aim(bot)
	-- update AlignOrientation to face the bot's current target (used during aim states)
	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	local state = bot:GetAttribute("musket_state")
	if state ~= "aimidle" and state ~= "toaim" then
		local align = root:FindFirstChild("aim_align")
		if align then align.Enabled = false end
		return
	end

	local tag = hum:FindFirstChild("target")
	local target = tag and tag.Value
	if not target or not target.Parent then
		local align = root:FindFirstChild("aim_align")
		if align then align.Enabled = false end
		return
	end

	local thrp = target:FindFirstChild("HumanoidRootPart")
	if not thrp then return end

	local align = get_aim_align(bot)
	if not align then return end

	local from = root.Position
	local to = Vector3.new(thrp.Position.X, from.Y, thrp.Position.Z)

	align.CFrame = CFrame.lookAt(from, to)
	align.Enabled = true
end

-- central function to change company morale by a flat delta (positive = increase, negative = decrease)
function module.apply_morale_change(player, delta)
	-- applies a direct morale change to all alive bots in player's company
	local company = companies[player]
	if not company then return end

	for _, bot in pairs(company.slots) do
		if bot and bot.Parent and bot ~= false then
			local m = bot:GetAttribute("morale") or 100
			m = math.clamp(m + delta, 0, 100)
			bot:SetAttribute("morale", m)
		end
	end
end

-- legacy wrapper (keeps old name semantics: amount positive => damage)
function module.apply_morale_damage(player, amount)
	-- apply damage as a negative change, preserves compatibility
	if not player then return end
	module.apply_morale_change(player, -math.max(1, math.floor(amount)))
end

-- apply morale delta to all companies' bots within radius of position
function module.apply_morale_delta_to_position(position, radius, delta)
	-- reduces/increases morale for bots whose HumanoidRootPart is within radius of a position
	radius = radius or 30
	for _, comp in pairs(companies) do
		for _, bot in pairs(comp.slots) do
			if bot and bot.Parent and bot ~= false then
				local root = bot:FindFirstChild("HumanoidRootPart")
				if root then
					local d = (root.Position - position).Magnitude
					if d <= radius then
						local m = bot:GetAttribute("morale") or 100
						m = math.clamp(m + delta, 0, 100)
						bot:SetAttribute("morale", m)
					end
				end
			end
		end
	end
end

-- returns average company morale for all companies on a given team
function module.get_average_morale_by_team(team_name)
	local total = 0
	local count = 0
	for _, comp in pairs(companies) do
		if comp.team == team_name then
			for _, bot in pairs(comp.slots) do
				if bot and bot.Parent and bot ~= false then
					local m = bot:GetAttribute("morale") or 0
					total += m
					count += 1
				end
			end
		end
	end
	if count == 0 then return 0 end
	return total / count
end

-- returns which rank a bot is in (1 = front)
local function get_rank(company, bot)
	for i = 1, company.maxslots do
		if company.slots[i] == bot then
			return math.floor((i - 1) / math.ceil(company.maxslots / company.rows)) + 1
		end
	end
	return nil
end

function module.create_soldier(position, owner)
	-- create bot, set network owner and collision group, prepare attributes and death handler
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

	-- morale & timer
	bot:SetAttribute("morale", 100)                    -- individual morale
	bot:SetAttribute("morale_state", "steady")        -- steady | shaken | wavering | broken
	bot:SetAttribute("morale_timer", 0)               -- countdown during which recovery is blocked (seconds)
	bot:SetAttribute("has_routed", false)             -- routing flag



	-- set default walk speed
	if humanoid then pcall(function() humanoid.WalkSpeed = 16 end) end

	-- death handling: mark slot empty and cleanup and contagion to nearby companies
	humanoid.Died:Connect(function()
		local company = companies[owner]
		local pos = root and root.Position or Vector3.new(0,0,0)

		-- local company morale shock (existing behaviour)
		if company then
			for _, other in pairs(company.slots) do
				if other and other ~= false then
					local m = other:GetAttribute("morale") or 100
					other:SetAttribute("morale", math.clamp(m - 8, 0, 100))
					-- set morale timer to prevent instant recovery
					other:SetAttribute("morale_timer", 30)
				end
			end
		end

		-- contagion: nearby friendly companies suffer morale loss when this casualty is close to them
		module.apply_morale_delta_to_position(pos, 40, -6) -- radius 40 studs, -6 morale

		-- trigger existing musket cleanup and destroy this bot
		musket.stop_all(bot)
		pcall(function() bot:Destroy() end)
	end)

	return bot
end

function module.destroy_company(player)
	-- remove bots and delete the company folder
	local company = companies[player]
	if not company then return end

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
	if companies[player] then return end
	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end

	count = math.clamp(count or 0, 1, max_bots_per_player)

	local companyfolder = Instance.new("Folder")
	companyfolder.Name = player.Name .. "_company"
	companyfolder.Parent = companiesfolder

	local rows = 5
	local company = {
		slots = {},
		rows = rows,
		count = count,
		maxslots = count,
		follow = true,
		anchor = player.Character.HumanoidRootPart.CFrame,
		folder = companyfolder,
		fireatwill = false,
		_fire_threads = {},
		anchor_locked = false,
		team = player.Team and player.Team.Name or "none",
	}

	local columns = math.ceil(company.maxslots / company.rows)
	local fileorder = formation.build_file_order(columns)
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
	-- returns average morale of all alive bots in player's company (rounded)
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

-- this returns the average position of all enemy humanoids for tactical routing
function module.get_enemy_centroid(company)
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

function module.route_bot(bot, enemy_point, distance)
	-- route bot away from enemy_point by distance
	local hum = bot:FindFirstChildWhichIsA("Humanoid")
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end

	distance = distance or 250

	local dir = (root.Position - enemy_point).Unit
	local target = root.Position + dir * distance

	hum.WalkSpeed = 30
	hum:MoveTo(target)
end

function module.get_companies()
	-- return companies table for read-only use
	return companies
end

function module.rebuiltslots(player)
	local company = companies[player]
	if not company then return end

	company._form_start = nil
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
	local company = companies[player]
	if not company then return false end
	return formation.is_front_rank(company, bot)
end

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

			if not formation.is_front_rank(company, bot) then
				task.wait(0.1)
				continue
			end

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
	local company = companies[player]
	if not company or company.fireatwill then return end

	company.fireatwill = true

	company._fire_thread = task.spawn(function()
		while company.fireatwill do
			for _, bot in pairs(company.slots) do
				if bot and bot ~= false and formation.is_front_rank(company, bot) then

					local state = bot:GetAttribute("musket_state")

					if state == "idle" then
						task.spawn(function()
							task.wait(math.random(10, 60) / 100)
							if company.fireatwill and bot:GetAttribute("musket_state") == "idle" then
								musket.present(bot)
							end
						end)

					elseif state == "makereadyidle" then
						task.spawn(function()
							task.wait(math.random(10, 60) / 100)
							if company.fireatwill and bot:GetAttribute("musket_state") == "makereadyidle" then
								musket.aim(bot)
							end
						end)

					elseif state == "aimidle" and bot:GetAttribute("has_bullet") then
						task.spawn(function()
							task.wait(math.random(10, 60) / 100)
							if company.fireatwill and bot:GetAttribute("musket_state") == "aimidle" then
								musket.fire(bot)
							end
						end)

					elseif state == "reloadidle" then
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
	local company = companies[player]
	if not company then return end

	company.fireatwill = false
	if company._fire_thread then
		task.cancel(company._fire_thread)
		company._fire_thread = nil
	end
end

function module.start_rankbyrank(player)
	local company = companies[player]
	if not company then return end

	for _, bot in pairs(company.slots) do
		if bot and bot ~= false then
			musket.init(bot)
			musket.set_idle(bot)
		end
	end

	task.wait(0.5)

	for rank = 1, company.rows do
		for _, bot in pairs(company.slots) do
			if bot and bot ~= false and get_rank(company, bot) == rank then
				if bot:GetAttribute("musket_state") == "idle" then
					musket.present(bot)
				end
			end
		end

		for _, bot in pairs(company.slots) do
			if bot and bot ~= false and get_rank(company, bot) == rank then
				task.spawn(function()
					while true do
						if bot:GetAttribute("musket_state") == "makereadyidle" then
							musket.aim(bot)
							break
						end
						task.wait(0.05)
					end
				end)
			end
		end

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

					musket.fire(bot)
					remaining[bot] = nil
				end
			end
			task.wait(0.05)
		end

		for _, bot in pairs(company.slots) do
			if bot and bot ~= false and get_rank(company, bot) == rank then
				task.spawn(function()
					while true do
						if bot:GetAttribute("musket_state") == "reloadidle" then
							musket.reload(bot)
							break
						end
						task.wait(0.1)
					end
				end)
			end
		end

		task.wait(0.2)
	end
end

function module.stop_rankbyrank(player)
	local company = companies[player]
	if not company then return end

	company.rankbyrank = false
end

-- continuous aim, morale timer, recovery, contagion and GUI update loop
task.spawn(function()
	local tick_interval = 0.5 -- main tick interval
	local recovery_rate = 1    -- morale pts per second when recovering (slow)
	local friendly_bonus_rate = 0.5 -- morale pts per second when near friendly company
	local friendly_bonus_radius = 12 -- radius to consider "near friendly company"
	local broken_contagion_radius = 15 -- panic contagion radius
	local near_miss_provoked = {} -- unused here; musket will trigger morale_event directly

	while true do
		for _, company in pairs(companies) do
			for _, bot in pairs(company.slots) do
				if bot and bot.Parent and bot ~= false then
					local hum = bot:FindFirstChildWhichIsA("Humanoid")
					local root = bot:FindFirstChild("HumanoidRootPart")
					if not hum or not root then continue end

					-- update morale state
					local m = bot:GetAttribute("morale") or 100
					local morale_state
					if m > 70 then
						morale_state = "steady"
					elseif m > 40 then
						morale_state = "shaken"
					elseif m > 15 then
						morale_state = "wavering"
					else
						morale_state = "broken"
					end
					bot:SetAttribute("morale_state", morale_state)

					-- if broken and not routed yet, route away once
					local has_routed = bot:GetAttribute("has_routed") or false
					if morale_state == "broken" and not has_routed then
						bot:SetAttribute("has_routed", true)
						musket.cease(bot)

						local enemy = module.get_enemy_centroid(company)
						if enemy then
							module.route_bot(bot, enemy, 125)
						end
					elseif morale_state ~= "broken" then
						bot:SetAttribute("has_routed", false)
					end

					-- aim logic: only aim if bot is not broken
					if morale_state ~= "broken" then
						local state = bot:GetAttribute("musket_state")
						if state == "aimidle" or state == "toaim" then
							update_aim(bot)
						end
					end

					-- morale timer handling: block recovery while timer > 0
					local timer = bot:GetAttribute("morale_timer") or 0
					if timer > 0 then
						timer = math.max(0, timer - tick_interval)
						bot:SetAttribute("morale_timer", timer)
					else
						-- recovery: slowly increase morale when not recently shot/near-missed
						-- also grant a small friendly proximity bonus
						local delta = recovery_rate * tick_interval

						-- friendly proximity bonus: if bot is within friendly_bonus_radius of any allied bot, add small extra
						local near_friendly = false
						for _, other_comp in pairs(companies) do
							if other_comp.team == company.team and other_comp ~= company then
								for _, other_bot in pairs(other_comp.slots) do
									if other_bot and other_bot.Parent and other_bot ~= false then
										local oroot = other_bot:FindFirstChild("HumanoidRootPart")
										if oroot then
											if (oroot.Position - root.Position).Magnitude <= friendly_bonus_radius then
												near_friendly = true
												break
											end
										end
									end
								end
								if near_friendly then break end
							end
						end
						if near_friendly then
							delta = delta + (friendly_bonus_rate * tick_interval)
						end

						-- apply recovery
						local newm = math.clamp((bot:GetAttribute("morale") or 100) + delta, 0, 100)
						bot:SetAttribute("morale", newm)
					end

					-- panic contagion: if broken bots nearby, reduce morale proportionally
					local nearby_total = 0
					local nearby_broken = 0
					for _, other_comp in pairs(companies) do
						for _, other_bot in pairs(other_comp.slots) do
							if other_bot and other_bot.Parent and other_bot ~= false and other_bot ~= bot then
								local oroot = other_bot:FindFirstChild("HumanoidRootPart")
								if oroot then
									local d = (oroot.Position - root.Position).Magnitude
									if d <= broken_contagion_radius then
										nearby_total += 1
										local st = other_bot:GetAttribute("morale_state")
										if st == "broken" then nearby_broken += 1 end
									end
								end
							end
						end
					end
					if nearby_total > 0 and nearby_broken > 0 then
						local contagion = math.floor(2 * (nearby_broken / nearby_total)) -- small immediate penalty
						if contagion > 0 then
							local cur = bot:GetAttribute("morale") or 100
							bot:SetAttribute("morale", math.clamp(cur - contagion, 0, 100))
							-- small cooldown to prevent repeated immediate stacks
							bot:SetAttribute("morale_timer", 2)
						end
					end

				end
			end
		end

		for player, company in pairs(companies) do
			if player and player.Parent and company then
				-- check if player character exists and alive
				local char = player.Character
				local hum = char and char:FindFirstChildWhichIsA("Humanoid")
				if hum and hum.Health > 0 then
					-- compute average morale and distribution
					local avg = 0
					local count = 0
					local counts = { steady = 0, shaken = 0, wavering = 0, broken = 0 }

					for _, bot in pairs(company.slots) do
						if bot and bot.Parent and bot ~= false then
							local m = bot:GetAttribute("morale") or 0
							avg += m
							count += 1
							local st = bot:GetAttribute("morale_state") or "steady"
							counts[st] = counts[st] + 1
						end
					end

					local avg_morale = count == 0 and 0 or math.floor(avg / count)

					-- compute enemy average morale for simple combat advantage metric
					local enemy_avg = 0
					local enemy_count = 0
					for _, comp in pairs(companies) do
						if comp.team ~= company.team then
							for _, bot in pairs(comp.slots) do
								if bot and bot.Parent and bot ~= false then
									enemy_avg += bot:GetAttribute("morale") or 0
									enemy_count += 1
								end
							end
						end
					end
					local enemy_morale = enemy_count == 0 and avg_morale or (enemy_avg / enemy_count)

					-- compute advantage ratio and label
					local ratio = enemy_morale == 0 and 1 or (avg_morale / math.max(1, enemy_morale))
					local advantage = "Even"
					if ratio < 0.7 then
						advantage = "Losing"
					elseif ratio < 0.9 then
						advantage = "Slightly Losing"
					elseif ratio < 1.1 then
						advantage = "Even"
					elseif ratio < 1.3 then
						advantage = "Slightly Winning"
					else
						advantage = "Winning"
					end

					-- fire client event with a compact data table
					local data = {
						avg_morale = avg_morale,
						counts = counts,
						advantage = advantage,
						enemy_morale = math.floor(enemy_morale),
					}
					pcall(function() morale_update_event:FireClient(player, data) end)
				else
					-- player dead or no humanoid: clear GUI
					pcall(function() morale_update_event:FireClient(player, { avg_morale = 0, counts = { steady=0,shaken=0,wavering=0,broken=0 }, advantage = "N/A", enemy_morale = 0 }) end)
				end
			end
		end

		task.wait(tick_interval)
	end
end)

-- handle morale events from other modules (musket will Fire/Bind to this)
morale_event.Event:Connect(function(player, amount)
	-- this event is used by musket_module and other systems to apply morale damage to a specific player's company
	-- amount positive => damage in old convention
	if not player or not companies[player] then return end
	module.apply_morale_damage(player, amount)

	-- set morale_timer for company bots to prevent immediate recovery
	local company = companies[player]
	for _, bot in pairs(company.slots) do
		if bot and bot.Parent and bot ~= false then
			bot:SetAttribute("morale_timer", 30)
		end
	end
end)

return module
