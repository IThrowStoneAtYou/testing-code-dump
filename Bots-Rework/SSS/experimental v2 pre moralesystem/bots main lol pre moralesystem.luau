-- company_controller (server script)
local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")
local physics = game:GetService("PhysicsService")
local workspace = workspace

local musket = require(script:WaitForChild("musket_module"))
local formation = require(script:WaitForChild("formation_module"))
local manager = require(script:WaitForChild("company_manager"))

local botcmd = replicatedstorage:WaitForChild("botcmd"):WaitForChild("send")

local chantfolder = replicatedstorage:WaitForChild("Asset")
	:WaitForChild("SFX")
	:WaitForChild("chant")
	:WaitForChild("rus")

local Cmdr = require(replicatedstorage.Cmdr)

Cmdr:RegisterDefaultCommands()
Cmdr:RegisterHooksIn(replicatedstorage.Cmdr.Hooks)

--print("game started")

-- formation settings
local spacing = {
	side = 5.8,
	front = 6,
	back = 10
}

local anchor_offsets = {}  -- offset for anchor
local anchor_mode = {}   -- "back", "left", "right"


local formationrate = 0.12
local stoptolerance = 1

musket.rebuild_team_cache()

-- play_chant: play chant sfx on each bot head
local function play_chant(company)
	local sounds = chantfolder:GetChildren()
	if #sounds == 0 then return end

	for i = 1, company.maxslots do
		local bot = company.slots[i]
		if bot and bot ~= false then
			local head = bot:FindFirstChild("Head")
			if head then
				local sound = sounds[math.random(1,#sounds)]:Clone()
				sound.Parent = head
				sound:Play()
				sound.Ended:Connect(function() sound:Destroy() end)
			end
		end
	end
end

-- this calculates how wide the company currently is
local function get_company_half_width(company, spacing)
	if not company then 
		return 0 
	end

	local columns = math.ceil(company.maxslots / company.rows)
	local width = columns * spacing.side
	return width * 0.5
end

-- this computes formation extents in studs
local function get_company_extents(company, spacing)
	local columns = math.ceil(company.maxslots / company.rows)
	local width = columns * spacing.side
	local depth = company.rows * spacing.front

	return width * 0.5, depth
end

-- this recalculates flank offsets when rows or slot counts change
local function update_anchor_offset(player, company)
	local mode = anchor_mode[player]
	if not mode or not company then return end

	local columns = math.ceil(company.maxslots / company.rows)
	local width = columns * spacing.side
	local depth = company.rows * spacing.front

	if mode == "right" then
		-- player stands at front-left of company
		anchor_offsets[player] = CFrame.new(
			width * 0.5 + 6,
			0,
			depth * 0.5 + 6
		)
	elseif mode == "left" then
		-- player stands at front-right of company
		anchor_offsets[player] = CFrame.new(
			- width * 0.5 - 6,
			0,
			depth * 0.5 + 6
		)
	elseif mode == "back" then
		-- player stands in front of first rank
		anchor_offsets[player] = CFrame.new(
			0,
			0,
			depth * 0.5 + -13
		)
	end
end

-- onchatted: parse chat commands and control manager/formation/musket
local function onchatted(player, msg)
	local args = string.split(string.lower(msg), " ")
	local companies = manager.get_companies()
	local company = companies[player]

	if args[1] == "/spawn" then
		local n = tonumber(args[2])
		if n then
			manager.spawn_company(player, n)
			musket.rebuild_team_cache() -- rebuild cache after new bots spawn
			
			anchor_mode[player] = "left"
			
			local companies = manager.get_companies()
			local company = companies[player]
			if company then
				update_anchor_offset(player, company) 
			end
		end
		return
	end

	if args[1] == "/reset" then
		manager.destroy_company(player)
		return
	end

	if args[1] == "/face" then
		manager.face_company(player)
		return
	end

	if args[1] == "/row" and company then
		local n = tonumber(args[2])
		if n then
			company.rows = math.max(1, n)
			manager.rebuiltslots(player)
			update_anchor_offset(player, company)
			print("company_controller: rows set", n)
		end
		return
	end

	if args[1] == "/gaps" and company then
		manager.fillgaps(player)
		update_anchor_offset(player, company)
		return
	end

	if args[1] == "/follow" and company then
		company.follow = true
		company.anchor_locked = false
		return
	end

	if args[1] == "/unfollow" and company then
		local offset = anchor_offsets[player] or CFrame.new()
		company.follow = false
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			company.anchor = player.Character.HumanoidRootPart.CFrame * offset
		end

		return
	end

	if args[1] == "/left" and company then
		anchor_mode[player] = "left"
		update_anchor_offset(player, company)
		return
	end

	if args[1] == "/right" and company then
		anchor_mode[player] = "right"
		update_anchor_offset(player, company)
		return
	end

	if args[1] == "/back" and company then
		anchor_mode[player] = "back"
		update_anchor_offset(player, company)
		return
	end

	if args[1] == "/chant" and company then
		play_chant(company)
		return
	end

	-- musket commands (front rank only)
	if not company then return end
	
	-- block orders if company is broken
	local morale = manager.get_company_morale(player)
	if morale < 20 then return end

	if args[1] == "/present" then
		for i = 1, company.maxslots do
			local bot = company.slots[i]
			if bot and bot ~= false and formation.is_front_rank(company, bot) then
				if bot:GetAttribute("musket_state") == nil or bot:GetAttribute("has_bullet") == nil then
					musket.init(bot); musket.set_idle(bot)
				end

				musket.present(bot)
			end
		end
		return
	end

	if args[1] == "/aim" then
		for i = 1, company.maxslots do
			local bot = company.slots[i]
			if bot and bot ~= false and formation.is_front_rank(company, bot) then
				musket.aim(bot)
			end
		end
		return
	end

	if args[1] == "/fire" then
		-- this fires the front rank with small random delays so it is not perfectly synced

		for i = 1, company.maxslots do
			local bot = company.slots[i]
			if bot and bot ~= false and formation.is_front_rank(company, bot) then
				task.spawn(function()
					-- random delay to desync manual firing
					task.wait(math.random(0, 40) / 100)

					if bot:GetAttribute("musket_state") == "aimidle" then
						musket.fire(bot)
					end
				end)
			end
		end
		return
	end
	
	if args[1] == "/fire3" then
		-- this enables rank by rank rolling fire

		if company then
			manager.start_rankbyrank(player)
		end
		return
	end

	if args[1] == "/reload" then
		for i = 1, company.maxslots do
			local bot = company.slots[i]
			if bot and bot ~= false and formation.is_front_rank(company, bot) then
				musket.reload(bot)
			end
		end
		return
	end

	if args[1] == "/cease" then
		-- stop fire-at-will and cease animations on front rank
		if company then
			manager.stop_fireatwill(player)
		end
		for i = 1, company.maxslots do
			local bot = company.slots[i]
			if bot and bot ~= false and formation.is_front_rank(company, bot) then
				musket.cease(bot)
				manager.stop_rankbyrank(player)
			end
		end
		return
	end

	if args[1] == "/fire2" then
		-- enable continuous fire-at-will for front rank
		if company then
			manager.start_fireatwill(player)
		end
		return
	end
end

-- player events wiring
players.PlayerAdded:Connect(function(player)
	print("company_controller: player added", player.Name)
	player.Chatted:Connect(function(msg) onchatted(player, msg) end)

	player.CharacterAdded:Connect(function(char)
		print("company_controller: character added", player.Name)
		-- tag player team on spawn
		manager.tag_player_team(player, char)

		-- set player parts to player collision group
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then
				physics:SetPartCollisionGroup(p, "player")
			end
		end

		char.DescendantAdded:Connect(function(obj)
			if obj:IsA("BasePart") then
				physics:SetPartCollisionGroup(obj, "player")
			end
		end)

		-- delete company if player left the game.
		players.PlayerRemoving:Connect(function(player)
			print("company_controller: player removing", player.Name)

			-- destroy company if it exists
			manager.destroy_company(player)

			-- cleanup anchor data
			anchor_offsets[player] = nil
			anchor_mode[player] = nil
		end)

		-- on player death, force unfollow and set anchor
		char:WaitForChild("Humanoid").Died:Connect(function()
			print("company_controller: player died", player.Name)

			local companies = manager.get_companies()
			local company = companies[player]
			if not company then return end

			-- if already unfollowed, do nothing (anchor is already fixed)
			if company.follow == false then
				return
			end

			-- otherwise force unfollow and lock anchor at death position
			company.follow = false

			if char:FindFirstChild("HumanoidRootPart") then
				local offset = anchor_offsets[player] or CFrame.new()
				company.anchor = char.HumanoidRootPart.CFrame * offset
			end
		end)
	end)
end)

-- formation scheduler (ticks every formationrate seconds)
task.spawn(function()
	while true do
		local companies = manager.get_companies()
		for player, _ in pairs(companies) do
			local company = companies[player]
			if company then
				local anchor

				local offset = anchor_offsets[player] or CFrame.new()

				if company.follow and not company.anchor_locked then
					if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
						anchor = player.Character.HumanoidRootPart.CFrame * offset
					else
						anchor = company.anchor
					end
				else
					anchor = company.anchor
				end

				manager.update_company(player, anchor, spacing, stoptolerance)
			end
		end
		task.wait(formationrate)
	end
end)


botcmd.OnServerEvent:Connect(function(player, text)
	print("gui command", player.Name, text)
	onchatted(player, text)
end)