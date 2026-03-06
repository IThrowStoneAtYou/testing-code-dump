-- CentreInvServer

-- Modules
local Data_Player = require(game.ServerScriptService.GuiScript.Data_Player)
local Backpack_Manager = require(game.ServerScriptService.GuiScript.BackpackManager)

-- ReplicatedStorage references (use WaitForChild to avoid race)
local Replicated = game:GetService("ReplicatedStorage"):WaitForChild("Gui_Inventory_Manager")
local RemoteFolder = Replicated:WaitForChild("Remote")
local GuiManager = Replicated:WaitForChild("Gui_Manager")

local EquipRemote = RemoteFolder:WaitForChild("Equip")
local Update_Player_Remote = RemoteFolder:WaitForChild("Update_Player")
local HotbarsRemote = RemoteFolder:WaitForChild("Hotbars")
local UpdateCharacterBindable = RemoteFolder:WaitForChild("UpdateCharacter") -- treated like a BindableEvent
local SelectRemote = RemoteFolder:WaitForChild("Select")

local Update_Backpack_Remote = GuiManager:WaitForChild("Update_Backpack")

-- Other references
local Item_Folder = Replicated:WaitForChild("Item")
local Item_Setting = Replicated:WaitForChild("Item_Setting")
local Drop_Folder = workspace:FindFirstChild("Drop")

-- Local state
local hotbarMap = {} -- maps player.UserId -> last-used hotbar name

-- Simple helper: safe wait for character
local function getCharacter(player)
	-- returns the character, waiting if necessary
	return player.Character or player.CharacterAdded:Wait()
end

-- Update player's character/inventory/armor folders and ensure structure exists
-- This function creates player's Inventory and Armor folder structure and updates them.
local function Update(player)
	-- ensure character reference
	local Char = getCharacter(player)
	-- ensure Inventory folder and hotbar slots
	local Inventory_Folder = player:FindFirstChild("Inventory")
	if not Inventory_Folder then
		Inventory_Folder = Instance.new("Folder")
		Inventory_Folder.Name = "Inventory"
		Inventory_Folder.Parent = player
		for i = 1, 4 do
			local Hotbars = Instance.new("Folder")
			Hotbars.Name = "Hotbar"..i
			Hotbars.Parent = Inventory_Folder
		end
	end
	-- populate Inventory from Data_Player
	if Inventory_Folder then
		Update_Folder(player)
	end

	-- ensure Armor_Folder under character
	local Armor_Folder = Char:FindFirstChild("Armor_Folder")
	if not Armor_Folder then
		Armor_Folder = Instance.new("Folder")
		Armor_Folder.Name = "Armor_Folder"
		Armor_Folder.Parent = Char

		local slots = {"Head","Body","Arm","Pants","Mask","Backpack"}
		for _, sname in ipairs(slots) do
			local slot = Instance.new("Folder")
			slot.Name = sname
			slot.Parent = Armor_Folder
		end
	end

	-- apply armor visuals/stats
	Equip_Armor(player)
end

-- Update GUI Inventory folder items to match Data_Player Hotbars
-- Replaces tools inside player's Inventory hotbar slots and notifies client.
function Update_Folder(player)
	-- populate player's inventory hotbar slots from stored Data_Player
	local Inventory_Folder = player:FindFirstChild("Inventory")
	if not Inventory_Folder then return end

	local Hotbars = Data_Player[player.UserId] and Data_Player[player.UserId].Hotbars
	if not Hotbars then return end

	local Char = getCharacter(player)
	for key, data in pairs(Hotbars) do
		local Hotbar_Slot = Inventory_Folder:FindFirstChild(key)
		if not Hotbar_Slot then continue end

		-- remove existing Tool in slot
		local existingTool = Hotbar_Slot:FindFirstChildOfClass("Tool")
		if existingTool then existingTool:Destroy() end

		if not data.empty then
			local Class_Folder = Item_Folder:FindFirstChild(data.class)
			if Class_Folder then
				local Item = Class_Folder:FindFirstChild(data.id)
				if Item then
					local New_Item = Item:Clone()
					New_Item.Parent = Hotbar_Slot
					-- notify client of updated hotbars
					HotbarsRemote:FireClient(player, Hotbars)
				end
			end
		else
			-- empty slot: notify client (so UI removes icon)
			HotbarsRemote:FireClient(player, Hotbars)
		end
	end
end

-- Equip armor models onto character and update health
-- Reads Data_Player Armor table and places model children into Armor_Folder slots.
function Equip_Armor(player)
	local Char = workspace:FindFirstChild(player.Name) or player.Character
	if not Char then return end

	local Armor = Data_Player[player.UserId] and Data_Player[player.UserId].Armor
	local Armor_Folder_Char = Char:FindFirstChild("Armor_Folder")
	local Armor_Data_Folder = Replicated:FindFirstChild("Item") and Replicated.Item:FindFirstChild("Armor") or nil
	-- If Item_Setting contains armor info, keep backward compatibility
	if not Armor_Data_Folder and Replicated:FindFirstChild("Item_Setting") then
		Armor_Data_Folder = Item_Setting:FindFirstChild("Armor")
	end

	if not Armor or not Armor_Folder_Char or not Armor_Data_Folder then return end

	for key, data in pairs(Armor) do
		local Armor_Slot = Armor_Folder_Char:FindFirstChild(key)
		if not Armor_Slot then continue end

		-- remove existing model if present
		local ExistingModel = Armor_Slot:FindFirstChildOfClass("Model")
		if ExistingModel then
			ExistingModel:Destroy()
		end

		if not data.empty then
			local Class_Folder = Armor_Data_Folder:FindFirstChild(data.class)
			if Class_Folder then
				local Item = Class_Folder:FindFirstChild(data.id)
				if Item then
					local New_Item = Item:Clone()
					New_Item.Parent = Armor_Slot
					-- attempt to weld parts to character parts, and update health if necessary
					for _, v in pairs(New_Item:GetChildren()) do
						if v:IsA("BasePart") then
							v.CanCollide = false
							local Weld = v:FindFirstChildOfClass("Weld")
							if Weld then
								local targetPart = Char:FindFirstChild(v.Name)
								if targetPart then
									Weld.Part1 = targetPart
								end
							end
						end
					end
					Health_Up(player)
				end
			end
		else
			-- slot is empty, ensure removed
			local ItemModel = Armor_Slot:FindFirstChildOfClass("Model")
			if ItemModel then
				ItemModel:Destroy()
				Health_Up(player)
			end
		end
	end
end

-- Update player's humanoid MaxHealth from Data_Player value
function Health_Up(player)
	local Char = player.Character or player.CharacterAdded:Wait()
	local Humanoid = Char:FindFirstChild("Humanoid")
	if Humanoid and Data_Player[player.UserId] then
		local newMax = Data_Player[player.UserId].Health
		if type(newMax) == "number" then
			Humanoid.MaxHealth = newMax
			-- optional: adjust current health to new max if desired (not done here)
		end
	end
end

-- Equip tool handling (equip/unequip/swap)
-- Handles a player's request to equip a Tool object into their character.
EquipRemote.OnServerEvent:Connect(function(player, tool, namehotbars)
	if not tool then
		warn("Equip: tool is nil")
		return
	end

	local character = player.Character
	if not character then return end

	local currentHotbar = hotbarMap[player.UserId]
	local name_equip = character:FindFirstChildOfClass("Tool") -- tool currently equipped

	-- if same hotbar/tool clicked -> unequip
	if name_equip and name_equip.Name == tool.Name and namehotbars == currentHotbar then
		name_equip:Destroy()
		SelectRemote:FireClient(player, "unequip", tool.Name, namehotbars)
		hotbarMap[player.UserId] = nil
		return
	end

	-- otherwise equip/swap
	if name_equip then
		name_equip:Destroy()
		SelectRemote:FireClient(player, "swap", tool.Name, namehotbars)
	else
		SelectRemote:FireClient(player, "equip", tool.Name, namehotbars)
	end

	local tool_new = tool:Clone()
	tool_new.Parent = character
	hotbarMap[player.UserId] = namehotbars
end)

-- Looting / ProximityPrompt initialization
-- This sets up Triggered connections for drops inside workspace.Drop when Update_Player runs.
local function initDropPrompts()
	if not Drop_Folder then
		Drop_Folder = workspace:FindFirstChild("Drop")
		if not Drop_Folder then return end
	end

	for _, items in pairs(Drop_Folder:GetChildren()) do
		local ProximityPrompt = items:FindFirstChildOfClass("ProximityPrompt")
		if ProximityPrompt and not ProximityPrompt:GetAttribute("Connected") then
			ProximityPrompt:SetAttribute("Connected", true)

			ProximityPrompt.Triggered:Connect(function(clickedPlayer)
				-- ensure single-processing per trigger
				local Connect = ProximityPrompt:GetAttribute("Connected")
				if not Connect then return end
				ProximityPrompt:SetAttribute("Connected", false)

				local class = ProximityPrompt:GetAttribute("Class")
				local id = ProximityPrompt:GetAttribute("id")
				local ID = ProximityPrompt:GetAttribute("ID")

				if class and id then
					-- special handling when ID/backpack ID is present
					if ID and class == "Backpack" then
						local folder_armor = Item_Setting:FindFirstChild("Armor")
						local class_data = folder_armor and folder_armor:FindFirstChild(class)
						local id_item = class_data and class_data:FindFirstChild(id)
						if id_item then
							local ok, item = pcall(function() return require(id_item) end)
							if ok and item then
								Data_Player.AddItem(clickedPlayer, item, 1, ID)
								items:Destroy()
							end
						end
					else
						-- normal item pickup
						-- correct logical grouping: (class == "Gun" or class == "Melee") and id and not ID
						if (class == "Gun" or class == "Melee") and id and not ID then
							local folder = Item_Setting
							local class_data = folder and folder:FindFirstChild(class)
							local id_item = class_data and class_data:FindFirstChild(id)
							if id_item then
								local ok, item = pcall(function() return require(id_item) end)
								if ok and item then
									Data_Player.AddItem(clickedPlayer, item, 1)
									items:Destroy()
								end
							end
						else
							-- fallback: attempt to find in Item_Setting.Armor
							local folder_armor = Item_Setting:FindFirstChild("Armor")
							local class_data = folder_armor and folder_armor:FindFirstChild(class)
							local id_item = class_data and class_data:FindFirstChild(id)
							if id_item then
								local ok, item = pcall(function() return require(id_item) end)
								if ok and item then
									Data_Player.AddItem(clickedPlayer, item, 1)
									items:Destroy()
								end
							else
								-- final fallback: try generic Item folder
								local class_folder = Item_Folder:FindFirstChild(class)
								local id_item2 = class_folder and class_folder:FindFirstChild(id)
								if id_item2 then
									local clone = id_item2 -- some items are Instances, not modules
									-- If the dropped item is a tool/model that should be added to inventory, attempt to require or clone accordingly
									local ok, req = pcall(function() return require(id_item2) end)
									if ok and req then
										Data_Player.AddItem(clickedPlayer, req, 1)
										items:Destroy()
									else
										-- If require failed, skip (original logic used require on many paths)
										-- Optionally, implement a different path for model items if needed.
									end
								end
							end
						end
					end
				end
			end)
		end
	end
end

-- Combined Update_Player OnServerEvent handler
-- Runs Update(player), initializes drop prompts (once per drop), and sends GUI updates to client.
Update_Player_Remote.OnServerEvent:Connect(function(player)
	-- ensure player folders & character updated
	Update(player)

	-- initialize drop proximity prompts (because prompts set attribute "Connected")
	initDropPrompts()

	-- send player's data to client UIs
	local player_data = Data_Player[player.UserId]
	Update_Player_Remote:FireClient(player, player_data)
	Update_Backpack_Remote:FireClient(player)
end)

-- BindableEvent: UpdateCharacter used by PlayerAdded to request Update(player)
if UpdateCharacterBindable and UpdateCharacterBindable:IsA("BindableEvent") then
	UpdateCharacterBindable.Event:Connect(function(player)
		if player and player:IsA("Player") then
			Update(player)
		end
	end)
end

-- Player added/removed handling
local Players = game:GetService("Players")
Players.PlayerAdded:Connect(function(player)
	-- when a player character spawns, reset their data reference then trigger updates
	player.CharacterAdded:Connect(function(character)
		Data_Player[player.UserId] = nil

		-- notify any server-side listeners (original code used Fire on UpdateCharacter)
		if UpdateCharacterBindable and UpdateCharacterBindable:IsA("BindableEvent") then
			UpdateCharacterBindable:Fire(player)
		end

		-- add default items / initialize data
		if Data_Player.AddItem then

			-- call used Data_Player.AddItem(player) with no args
			local success, err = pcall(function() 
				Data_Player.AddItem(player)
			end)

			if not success then
				warn("Data_Player.AddItem failed for player:", player.Name, err)
			end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	hotbarMap[player.UserId] = nil
	-- keep Data_Player entries; original code did nil on CharacterAdded, not PlayerRemoving... tf
end)
