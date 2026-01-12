-- company_controller

local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")
local physics = game:GetService("PhysicsService")
local workspace = workspace

local musket = require(script:WaitForChild("musket_module")) -- ensure these ModuleScripts are sibling children
local formation = require(script:WaitForChild("formation_module"))
local manager = require(script:WaitForChild("company_manager"))

print("company_controller started")

-- formation settings
local spacing = { side = 5.8, front = 6.8, back = 10 }
local formationrate = 0.12
local stoptolerance = 1.5

-- chat command handler
local function onchatted(player, msg)
	-- parse chat commands and run formation/musket logic
	print("company_controller.onchatted called", player.Name, msg)
	local args = string.split(string.lower(msg), " ")
	local companies = manager.get_companies()
	local company = companies[player]

	if args[1] == "/spawn" then
		local n = tonumber(args[2])
		if n then manager.spawn_company(player, n) end
	end

	if args[1] == "/reset" then
		manager.destroy_company(player)
	end

	if args[1] == "/row" and company then
		local n = tonumber(args[2])
		if n then
			company.rows = math.max(1, n)
			manager.rebuiltslots(player)
			print("company_controller: rows set", n)
		end
	end

	if args[1] == "/gaps" and company then
		manager.fillgaps(player)
	end

	if args[1] == "/follow" and company then
		company.follow = true
	end

	if args[1] == "/unfollow" and company then
		company.follow = false
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			company.anchor = player.Character.HumanoidRootPart.CFrame
		end
	end

	-- musket commands (front rank only)
	if company then
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
		elseif args[1] == "/aim" then
			for i = 1, company.maxslots do
				local bot = company.slots[i]
				if bot and bot ~= false and formation.is_front_rank(company, bot) then
					musket.aim(bot)
				end
			end
		elseif args[1] == "/fire" then
			for i = 1, company.maxslots do
				local bot = company.slots[i]
				if bot and bot ~= false and formation.is_front_rank(company, bot) then
					musket.fire(bot)
				end
			end
		elseif args[1] == "/reload" then
			for i = 1, company.maxslots do
				local bot = company.slots[i]
				if bot and bot ~= false and formation.is_front_rank(company, bot) then
					musket.reload(bot)
				end
			end
		elseif args[1] == "/cease" then
			for i = 1, company.maxslots do
				local bot = company.slots[i]
				if bot and bot ~= false and formation.is_front_rank(company, bot) then
					musket.cease(bot)
				end
			end
		end
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

		-- on player death, force unfollow and set anchor
		char:WaitForChild("Humanoid").Died:Connect(function()
			print("company_controller: player died, forcing unfollow", player.Name)
			local companies = manager.get_companies()
			local company = companies[player]
			if company then
				company.follow = false
				if char:FindFirstChild("HumanoidRootPart") then
					company.anchor = char.HumanoidRootPart.CFrame
				end
			end
		end)
	end)
end)

-- formation scheduler
task.spawn(function()
	print("company_controller: formation scheduler started")
	while true do
		local companies = manager.get_companies()
		for player, _ in pairs(companies) do
			local company = companies[player]
			if company then
				local anchor
				if company.follow then
					if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
						anchor = player.Character.HumanoidRootPart.CFrame
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
