-- DragDrop Server Script

local Data_Player = require(game.ServerScriptService.GuiScript.Data_Player)
local BackpackManager = require(game.ServerScriptService.GuiScript.BackpackManager)

local Item_Folder = game.ReplicatedStorage.Gui_Inventory_Manager.Item

-------Remote--------------
local DragDrop_RF = game.ReplicatedStorage.Gui_Inventory_Manager.Gui_Manager.Drag_Drop
local Update_Backpack = game.ReplicatedStorage.Gui_Inventory_Manager.Gui_Manager.Update_Backpack
local Update_Player = game.ReplicatedStorage.Gui_Inventory_Manager.Remote.Update_Player
local DropUi_Remote = game.ReplicatedStorage.Gui_Inventory_Manager.Gui_Drop.Drop_Ui_Remote

local POCKET_PATTERN = "^Pocket%d"
local HOTBAR_PATTERN = "^Hotbar%d"
local _HOTBAR_PATTERN = "^_Hotbar%d"

local function SwapItems(container1, index1, container2, index2,player)
	local temp = container1[index1]
	container1[index1] = container2[index2]
	container2[index2] = temp
	Update_Player:FireClient(player,Data_Player[player.UserId])
	print(Data_Player)
	Unequip(player)
	return "Swap",Data_Player[player.UserId]
end

local function MoveItem(container1, index1, container2, index2,player)

	container2[index2] = container1[index1]
	container1[index1] = {empty = true}
	print(Data_Player)
	Unequip(player)
	return "Drop_Empty",Data_Player[player.UserId]
end

function backpack(pocket,first,armor,last,player)

	armor[last] = pocket[first]
	pocket[first] = {empty = true}

	local allBackpacks = BackpackManager.GetAllBackpacks(armor[last].Backpack_ID)
	local Backpack_Data = Data_Player[player.UserId].Backpack

	if not armor[last].empty then
		if allBackpacks then
			Data_Player[player.UserId].Backpack = allBackpacks

			Update_Player:FireClient(player,Data_Player[player.UserId])
			Update_Backpack:FireClient(player)
			print(Data_Player)
			return"Drop_Empty"
		else
			for i = 1, armor[last].slot do
				Backpack_Data[i] = {empty = true}
			end

			Update_Player:FireClient(player,Data_Player[player.UserId])
			Update_Backpack:FireClient(player)
		end
		return"Drop_Empty"
	end
end

function Unequip(player)
	local char = game.Workspace:FindFirstChild(player.Name)
	local Item = char:FindFirstChildOfClass("Tool")
	if Item then
		Item:Destroy()
	end
end

function Drop(con,first,player)
	local char = game.Workspace:FindFirstChild(player.Name)

	if con[first].class == "Gun" or con[first].class == "Melee" then

		local item_folder = Item_Folder:FindFirstChild(con[first].class)

		if item_folder and char then

			local Item = char:FindFirstChildOfClass("Tool")
			if Item then
				Item:Destroy()
			end

			local humanoidrootpart = char:FindFirstChild("HumanoidRootPart")
			local item_id = item_folder:FindFirstChild(con[first].id)

			if item_id and humanoidrootpart then

				local new_item = item_id:Clone()
				new_item.Parent = workspace:FindFirstChild("Drop")
				new_item.Name = con[first].id
				local newCFrame = humanoidrootpart.CFrame * CFrame.new(0, 0, -4) -- -4 หน่วยด้านหน้า
				new_item:SetPrimaryPartCFrame(newCFrame)
				local ProximityPrompt = Instance.new("ProximityPrompt")
				ProximityPrompt.Parent = new_item
				ProximityPrompt.Name = con[first].id
				ProximityPrompt:SetAttribute("Class",con[first].class)
				ProximityPrompt:SetAttribute("id",con[first].id)

				DropUi_Remote:FireClient(player,con[first])
				con[first] = {empty = true}
				return"Drop",Data_Player[player.UserId]
			end
		end
	else
		local armor_folder = Item_Folder.Armor:FindFirstChild(con[first].class)
		local Backpack = Data_Player[player.UserId].Backpack
		local Armor = Data_Player[player.UserId].Armor
		if armor_folder and char then

			local humanoidrootpart = char:FindFirstChild("HumanoidRootPart")
			local newCFrame = humanoidrootpart.CFrame * CFrame.new(0, 0, -4) -- -4 หน่วยด้านหน้า			
			local item_id = armor_folder:FindFirstChild(con[first].id)
			local new_item = item_id:Clone()
			new_item.Parent = workspace:FindFirstChild("Drop")

			if item_id and humanoidrootpart then
				new_item.Name = con[first].id
				local ProximityPrompt = Instance.new("ProximityPrompt")
				ProximityPrompt.Parent = new_item
				ProximityPrompt.Name = con[first].id
				ProximityPrompt:SetAttribute("Class",con[first].class)
				ProximityPrompt:SetAttribute("ID",con[first].Backpack_ID)
				ProximityPrompt:SetAttribute("id",con[first].id)
				new_item:SetPrimaryPartCFrame(newCFrame)

				if next(Backpack) and con[first].class == "Backpack" then
					BackpackManager:SaveBackpackData(player, con[first].Backpack_ID, Data_Player[player.UserId].Backpack)
					DropUi_Remote:FireClient(player,con[first])
					con[first] = {empty = true}
					Data_Player[player.UserId].Backpack = {}

					return"Drop",Data_Player[player.UserId]
				end	


				if con[first].health then
					DropUi_Remote:FireClient(player,con[first])
					con[first] = {empty = true}
					return"Drop",Data_Player[player.UserId]	
				end			
			end
		end
	end
end

function Drop_Pocket(con,first,player)

	local char = game.Workspace:FindFirstChild(player.Name)
	local armor_folder = Item_Folder.Armor:FindFirstChild(con[first].class)
	local Backpack = Data_Player[player.UserId].Backpack
	local Armor = Data_Player[player.UserId].Armor

	if armor_folder and char then

		local humanoidrootpart = char:FindFirstChild("HumanoidRootPart")
		local newCFrame = humanoidrootpart.CFrame * CFrame.new(0, 0, -4) -- -4 Front unit			
		local item_id = armor_folder:FindFirstChild(con[first].id)

		if item_id and humanoidrootpart then
			local new_item = item_id:Clone()
			new_item.Parent = workspace:FindFirstChild("Drop")
			if con[first].Backpack_ID then
				new_item.Name = con[first].id
				new_item:SetPrimaryPartCFrame(newCFrame)
				local ProximityPrompt = Instance.new("ProximityPrompt")
				ProximityPrompt.Parent = new_item
				ProximityPrompt.Name = con[first].id
				ProximityPrompt:SetAttribute("Class",con[first].class)
				ProximityPrompt:SetAttribute("ID",con[first].Backpack_ID)
				ProximityPrompt:SetAttribute("id",con[first].id)

				DropUi_Remote:FireClient(player,con[first])
				con[first] = {empty = true}

				if next(Backpack) then
				else
					Data_Player[player.UserId].Backpack = {}
				end

				return"Drop",Data_Player[player.UserId]
			end
		end
	end
end


DragDrop_RF.OnServerInvoke = function(player, First, Last)

	--print(First.."/"..Last)

	local Pocket = Data_Player[player.UserId].Pockets
	local Armor = Data_Player[player.UserId].Armor
	local Backpack = Data_Player[player.UserId].Backpack
	local Hotbars = Data_Player[player.UserId].Hotbars

	local First_Target = tonumber(First)
	local Last_Target = tonumber(Last)

	if Last == "Drop" then

		if string.match(First, POCKET_PATTERN) then	
			if Pocket[First].class == "Backpack" then
				return Drop_Pocket(Pocket,First,player)
			end
			return Drop(Pocket,First,player)
		end

		if string.match(First, HOTBAR_PATTERN) then	
			return Drop(Hotbars,First,player)
		end

		if First_Target then
			return Drop(Backpack,First_Target,player)
		end

		if First =="Head" then Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health 	return Drop(Armor,First,player) end
		if First =="Body" then Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health	return Drop(Armor,First,player) end
		if First =="Arm" then Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health	return Drop(Armor,First,player) end
		if First =="Backpack" then	return Drop(Armor,First,player) end
		if First =="Mask" then Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health	return Drop(Armor,First,player) end
		if First =="Pants" then Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health	return Drop(Armor,First,player) end
	end

	if string.match(First, HOTBAR_PATTERN) and string.match(Last, HOTBAR_PATTERN) then --Hotbar_DragDrop---------------------HotbarZone-----------------------------
		if not Hotbars[First].empty and Hotbars[Last].empty then
			return MoveItem(Hotbars, First, Hotbars, Last,player)
		elseif not Hotbars[First].empty and not Hotbars[Last].empty then
			return SwapItems(Hotbars, First, Hotbars, Last,player)
		end
	end

	if string.match(First, HOTBAR_PATTERN) and string.match(Last, POCKET_PATTERN) then --Hotbar To Pocket
		if not Hotbars[First].empty and Pocket[Last].empty then
			return MoveItem(Hotbars, First, Pocket, Last,player)
		elseif not Hotbars[First].empty and not Pocket[Last].empty then
			return SwapItems(Hotbars, First, Pocket, Last,player)
		end
	end

	if string.match(First, HOTBAR_PATTERN) and Last_Target then--------------------------Hotbar To Backpack
		if not Hotbars[First].empty and Backpack[Last_Target].empty then
			return MoveItem(Hotbars, First, Backpack, Last_Target,player)
		elseif not Hotbars[First].empty and not Backpack[Last_Target].empty then
			return SwapItems(Hotbars, First, Backpack, Last_Target,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and string.match(Last, POCKET_PATTERN) then --Pocket_DragDrop---------------------PocketZone-----------------------------
		if Pocket[Last].empty and not Pocket[First].empty then
			return MoveItem(Pocket, First, Pocket, Last,player)
		elseif not Pocket[Last].empty and not Pocket[First].empty then
			return SwapItems(Pocket, First, Pocket, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and Last == "Head" then--Pocket To Head
		if not Pocket[First].empty and Pocket[First].class == "Head" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Pocket[First].health
			return MoveItem(Pocket, First, Armor, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and Last == "Arm" then--Pocket To Arm
		if not Pocket[First].empty and Pocket[First].class == "Arm" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Pocket[First].health
			return MoveItem(Pocket, First, Armor, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and Last == "Body" then--Pocket To Body
		if not Pocket[First].empty and Pocket[First].class == "Body" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Pocket[First].health
			return MoveItem(Pocket, First, Armor, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and Last == "Pants" then--Pocket To Pants
		if not Pocket[First].empty and Pocket[First].class == "Pants" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Pocket[First].health
			return MoveItem(Pocket, First, Armor, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and Last == "Mask" then--Pocket To Mask
		if not Pocket[First].empty and Pocket[First].class == "Mask" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Pocket[First].health
			return MoveItem(Pocket, First, Armor, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and string.match(Last, HOTBAR_PATTERN) then --Pocket To Hotbar
		if Hotbars[Last].empty and not Pocket[First].empty and Pocket[First].class == "Gun" then
			return MoveItem(Pocket, First, Hotbars, Last,player)
		elseif not Hotbars[Last].empty and not Pocket[First].empty then
			return SwapItems(Pocket, First, Hotbars, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and string.match(Last, HOTBAR_PATTERN) then --Pocket To Hotbar
		if Hotbars[Last].empty and not Pocket[First].empty and Pocket[First].class == "Melee" then
			return MoveItem(Pocket, First, Hotbars, Last,player)
		elseif not Hotbars[Last].empty and not Pocket[First].empty then
			return SwapItems(Pocket, First, Hotbars, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and Last_Target then -------------------------Pocket To Backpack
		if Pocket[First].class == "Backpack" then
			return"ComeBack"
		end
		if Backpack[Last_Target].empty and not Pocket[First].empty then
			return MoveItem(Pocket, First, Backpack, Last_Target,player)
		elseif not Backpack[Last_Target].empty and not Pocket[First].empty then
			return SwapItems(Pocket, First, Backpack, Last_Target,player)
		end
	end

	if First_Target and Last_Target then ------------------------------------------------Backpack_DragDrop---------------------BackpackZone-----------------------------
		if Backpack[Last_Target].empty and not Backpack[First_Target].empty then
			return MoveItem(Backpack, First_Target, Backpack, Last_Target,player)
		elseif not Backpack[Last_Target].empty and not Backpack[First_Target].empty then
			return SwapItems(Backpack, First_Target, Backpack, Last_Target,player)
		end
	end

	if First_Target and string.match(Last, POCKET_PATTERN) then--------------------------Backpack To Pocket
		if Pocket[Last].empty and not Backpack[First_Target].empty then
			return MoveItem(Backpack, First_Target, Pocket, Last,player)
		elseif not Pocket[Last].empty and not Backpack[First_Target].empty then
			return SwapItems(Backpack, First_Target, Pocket, Last,player)
		end
	end

	if First_Target and string.match(Last, HOTBAR_PATTERN) then---------------------------Backpack To Hotbar
		if Hotbars[Last].empty and not Backpack[First_Target].empty and Backpack[First_Target].class == "Gun" or Backpack[First_Target].class == "Melee" then
			return MoveItem(Backpack, First_Target, Hotbars, Last,player)
		elseif not Hotbars[Last].empty and not Backpack[First_Target].empty then
			return SwapItems(Backpack, First_Target, Hotbars, Last,player)
		end
	end

	if First_Target and Last == "Head" then------------------------------------------------Backpack To Head
		if not Backpack[First_Target].empty and Backpack[First_Target].class == "Head" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Backpack[First_Target].health
			return MoveItem(Backpack, First_Target, Armor, Last,player)
		end
	end

	if First_Target and Last == "Arm" then------------------------------------------------Backpack To Arm
		if not Backpack[First_Target].empty and Backpack[First_Target].class == "Arm" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Backpack[First_Target].health
			return MoveItem(Backpack, First_Target, Armor, Last,player)
		end
	end

	if First_Target and Last == "Body" then------------------------------------------------Backpack To Body
		if not Backpack[First_Target].empty and Backpack[First_Target].class == "Body" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Backpack[First_Target].health
			return MoveItem(Backpack, First_Target, Armor, Last,player)
		end
	end

	if First_Target and Last == "Pants" then------------------------------------------------Backpack To Pants
		if not Backpack[First_Target].empty and Backpack[First_Target].class == "Pants" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Backpack[First_Target].health
			return MoveItem(Backpack, First_Target, Armor, Last,player)
		end
	end

	if First_Target and Last == "Mask" then------------------------------------------------Backpack To Mask
		if not Backpack[First_Target].empty and Backpack[First_Target].class == "Mask" and Armor[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health + Backpack[First_Target].health
			return MoveItem(Backpack, First_Target, Armor, Last,player)
		end
	end

	if string.match(First, POCKET_PATTERN) and Last == "Backpack" then-------------------Pocket To BackpackSlot/Equip_Backpack
		if Armor[Last].empty and Pocket[First].class == "Backpack" then		
			return backpack(Pocket,First,Armor,Last,player)
		end
	end

	if First == "Backpack" and string.match(Last, POCKET_PATTERN) then---------------------BackpackSlot To Pocket/UnEquip_Backpack
		if not Armor[First].empty and Pocket[Last].empty then
			BackpackManager:SaveBackpackData(player, Armor[First].Backpack_ID, Data_Player[player.UserId].Backpack)
			Pocket[Last] = Armor[First]
			Armor[First] = {empty = true}
			Data_Player[player.UserId].Backpack = {}
			Update_Backpack:FireClient(player,Data_Player[player.UserId])
			print(Data_Player)
			return "Drop_Empty"
		end
	end

	if First == "Head" and string.match(Last, POCKET_PATTERN) then------------------------HeadSlot To Packet/UnEquip_Head---------------------ArmorZone-----------------------------
		if not Armor[First].empty and Pocket[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Pocket, Last,player)
		end
	end

	if First == "Head" and Last_Target then-----------------------------------------------HeadSlot To Backpack/UnEquip_Head
		if not Armor[First].empty and Backpack[Last_Target].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Backpack, Last_Target,player)
		end
	end

	if First == "Arm" and string.match(Last, POCKET_PATTERN) then------------------------ArmSlot To Packet/UnEquip_Arm
		if not Armor[First].empty and Pocket[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Pocket, Last,player)
		end
	end

	if First == "Arm" and Last_Target then-----------------------------------------------Arm To Backpack/UnEquip_Head
		if not Armor[First].empty and Backpack[Last_Target].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Backpack, Last_Target,player)
		end
	end

	if First == "Body" and string.match(Last, POCKET_PATTERN) then------------------------BodySlot To Packet/UnEquip_Body
		if not Armor[First].empty and Pocket[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Pocket, Last,player)
		end
	end

	if First == "Body" and Last_Target then-----------------------------------------------Body To Backpack/UnEquip_Head
		if not Armor[First].empty and Backpack[Last_Target].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Backpack, Last_Target,player)
		end
	end

	if First == "Pants" and string.match(Last, POCKET_PATTERN) then------------------------PantsSlot To Packet/UnEquip_Pants
		if not Armor[First].empty and Pocket[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Pocket, Last,player)
		end
	end

	if First == "Pants" and Last_Target then-----------------------------------------------Pants To Backpack/UnEquip_Head
		if not Armor[First].empty and Backpack[Last_Target].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Backpack, Last_Target,player)
		end
	end

	if First == "Mask" and string.match(Last, POCKET_PATTERN) then------------------------MaskSlot To Packet/UnEquip_Mask
		if not Armor[First].empty and Pocket[Last].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Pocket, Last,player)
		end
	end

	if First == "Mask" and Last_Target then-----------------------------------------------Mask To Backpack/UnEquip_Head
		if not Armor[First].empty and Backpack[Last_Target].empty then
			Data_Player[player.UserId].Health = Data_Player[player.UserId].Health - Armor[First].health
			return MoveItem(Armor, First, Backpack, Last_Target,player)
		end
	end

	Update_Player:FireClient(player,Data_Player[player.UserId])
	return "ComeBack"
end
