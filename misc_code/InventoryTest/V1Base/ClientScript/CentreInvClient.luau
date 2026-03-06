-- CentreInvClient

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- Disable default Backpack UI
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

-- Player / Character / GUI references
local player = Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local playerGui = player:WaitForChild("PlayerGui")

local InventoryGui = playerGui:WaitForChild("Inventory")
local CustomHotBarGui = playerGui:WaitForChild("CustomHotBarGui")
local Main_Hotbar = CustomHotBarGui:WaitForChild("Main_Hotbar")

-- Remote events 
local GuiManager = ReplicatedStorage:WaitForChild("Gui_Inventory_Manager")
local RemoteFolder = GuiManager:WaitForChild("Remote")
local Gui_Drop = GuiManager:WaitForChild("Gui_Drop")

local Update_Player = RemoteFolder:WaitForChild("Update_Player")
local EquipRemote = RemoteFolder:WaitForChild("Equip")
local AddItem_Remote = RemoteFolder:WaitForChild("Hotbars")
local SelectRemote = RemoteFolder:WaitForChild("Select")
local DropUi_Remote = Gui_Drop:WaitForChild("Drop_Ui_Remote")
local DropUiTemplate = Gui_Drop:WaitForChild("Drop_Ui")

-- Local references inside Inventory GUI
local Equip_Armor = InventoryGui:FindFirstChild("Equip_Frame") and InventoryGui.Equip_Frame:FindFirstChild("Equip_Armor")
local Pocket_Gui = InventoryGui.MainFrame and InventoryGui.MainFrame:FindFirstChild("Pockets")
local Backpack_Gui = InventoryGui.MainFrame and InventoryGui.MainFrame:FindFirstChild("Backpack")
local Hotbat_Gui = InventoryGui:FindFirstChild("Hotbars")

-- State
local Hotbar_Save = {}
local image_visible = true
local lastSwitchTime = 0
local cooldownTime = 0 -- seconds

local inputKeys = {
	["One"] = {txt = "Hotbar1"},
	["Two"] = {txt = "Hotbar2"},
	["Three"] = {txt = "Hotbar3"},
	["Four"] = {txt = "Hotbar4"},
}

-- Helper function: create new item label in a slot (ImageLabel + optional amount)
-- This creates the visible icon/text for an inventory slot.
local function NewLabel(parent, Data)
	if not parent or not Data then return end

	local new_image = Instance.new("ImageLabel")
	new_image.Name = Data.class or "Item"
	new_image.Parent = parent
	new_image.Image = Data.image or ""
	new_image.Size = UDim2.new(0.9,0,0.9,0)
	new_image.Position = UDim2.new(0.5,0,0.5,0)
	new_image.AnchorPoint = Vector2.new(0.5,0.5)
	new_image.Transparency = 1

	-- Create or update amount TextLabel
	local amount_text = parent:FindFirstChild("Amount")
	if not amount_text then
		amount_text = Instance.new("TextLabel")
		amount_text.Name = "Amount"
		amount_text.Parent = parent
		amount_text.Position = UDim2.new(0.6,0,0.7,0)
		amount_text.TextColor3 = Color3.fromRGB(255,255,255)
		amount_text.Size = UDim2.new(0.3,0,0.3,0)
		amount_text.TextSize = 16
		amount_text.BackgroundTransparency = 1

		-- keep original font if available
		pcall(function()
			amount_text.FontFace = Font.fromName("Balthazar",Enum.FontWeight.Bold,Enum.FontStyle.Normal)
		end)
	end

	if Data.amount and Data.amount >= 2 then
		amount_text.Text = "x"..tostring(Data.amount)
	else
		amount_text.Text = ""
	end
end

-- Helper function: attach hover select behavior to a slot
-- Adds MouseEnter/MouseLeave handlers that show a selection overlay.
local function attachHoverSelect(slot)
	if not slot or not slot:IsA("Instance") then return end
	-- don't attach twice
	if slot:FindFirstChild("__HoverSelectConnection") then return end

	-- create marker to indicate connections exist
	local marker = Instance.new("BoolValue")
	marker.Name = "__HoverSelectConnection"
	marker.Parent = slot

	-- MouseEnter/Leave handlers (ImageLabel expected)
	if slot:IsA("ImageLabel") or slot:IsA("ImageButton") then
		slot.MouseEnter:Connect(function()
			-- create select overlay if missing
			local select_slot = slot:FindFirstChild("Select")
			if not select_slot then
				local new_folder = Instance.new("Folder")
				new_folder.Parent = slot
				new_folder.Name = "Select"

				local new_select = Instance.new("ImageLabel")
				new_select.Name = "S"
				new_select.Position = UDim2.new(0.5, 0,0.5, 0)
				new_select.AnchorPoint = Vector2.new(0.5,0.5)
				new_select.Size = UDim2.new(0.85,0,0.85,0)
				new_select.Parent = new_folder
				new_select.Image = "rbxassetid://103039219995349"
				new_select.Transparency = 1
				new_select.ImageTransparency = 0.4
				new_select.ImageColor3 = Color3.fromRGB(255,255,255)

				local info = TweenInfo.new(0.1,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,-1,true)
				local tweena = TweenService:Create(new_select,info,{Size = UDim2.new(0.8,0,0.8,0)})
				local tween_tran = TweenService:Create(new_select,info,{ImageTransparency = 0.7})
				tweena:Play()
				tween_tran:Play()

				-- If inventory closes, remove selection overlay
				InventoryGui.Changed:Connect(function(property)
					if property == "Enabled" then
						if new_folder and new_folder.Parent then
							new_folder:Destroy()
						end
					end
				end)
			end
		end)

		slot.MouseLeave:Connect(function()
			local select_slot = slot:FindFirstChild("Select")
			if select_slot then
				select_slot:Destroy()
			end
		end)
	end
end

-- Function: scan and attach hover handlers for Backpack, Pocket, Hotbars, Equip Armor
-- dynamic slots get hover behavior for selection visuals.
local function connectHoverForContainers()
	-- Equip Armor
	if Equip_Armor then
		for _,v in pairs(Equip_Armor:GetChildren()) do
			if v:IsA("ImageLabel") or v:IsA("ImageButton") then
				attachHoverSelect(v)
			end
		end
	end

	-- Hotbars
	if Hotbat_Gui then
		for _,v in pairs(Hotbat_Gui:GetChildren()) do
			if v:IsA("ImageLabel") or v:IsA("ImageButton") then
				attachHoverSelect(v)
			end
		end
	end

	-- Pocket
	if Pocket_Gui then
		for _,v in pairs(Pocket_Gui:GetChildren()) do
			if v:IsA("ImageLabel") or v:IsA("ImageButton") then
				attachHoverSelect(v)
			end
		end
	end

	-- Backpack (scan existing and future items)
	if Backpack_Gui then
		for _,v in pairs(Backpack_Gui:GetChildren()) do
			if v:IsA("ImageLabel") or v:IsA("ImageButton") then
				attachHoverSelect(v)
			end
		end
	end
end

-- Function: refresh backpack UI when Update_Player fires (creates/destroys slot contents)
-- Updates Hotbars, Armor, Backpack, and Pocket based on server data.
local function handleUpdatePlayer(Player_Data)
	if not Player_Data then return end

	local Backpack = Player_Data.Backpack
	local Pocket = Player_Data.Pockets
	local Armor = Player_Data.Armor
	local Hotbars = Player_Data.Hotbars

	-- HOTBARS update
	if Hotbars and Hotbat_Gui then
		for key, data in pairs(Hotbars) do
			local Hotbat_Frame = Hotbat_Gui:FindFirstChild(key)
			if Hotbat_Frame then
				-- remove old ImageLabel/TextLabel children
				for _, child in ipairs(Hotbat_Frame:GetChildren()) do
					if child:IsA("ImageLabel") or child:IsA("TextLabel") then
						child:Destroy()
					end
				end

				-- add new content if not empty
				if not data.empty then
					NewLabel(Hotbat_Frame, data)
				end
			else
				warn("Hotbat_Frame not found for key:", key)
			end
		end
	end

	-- ARMOR update
	if Armor and Equip_Armor then
		for key,data in pairs(Armor) do
			local Armor_Frame = Equip_Armor:FindFirstChild(key)
			if not Armor_Frame then
				-- missing frame, skip
			else
				local imagelabel = Armor_Frame:FindFirstChildOfClass("ImageLabel")
				local textlabel = Armor_Frame:FindFirstChildOfClass("TextLabel")
				if not data.empty then
					if not imagelabel then
						NewLabel(Armor_Frame, data)
					end
				else
					if imagelabel then imagelabel:Destroy() end
					if textlabel then textlabel:Destroy() end
				end
			end
		end
	end

	-- BACKPACK update
	if Backpack and Backpack_Gui then
		if next(Backpack) then
			-- if template slots exist, populate them
			local Backpack_slot = Backpack_Gui:FindFirstChildOfClass("ImageLabel")
			if Backpack_slot then
				for key,data in pairs(Backpack) do
					local Backpack_Frame = Backpack_Gui:FindFirstChild(key)
					if Backpack_Frame then
						Backpack_Frame.Visible = true
						local imagelabel = Backpack_Frame:FindFirstChildOfClass("ImageLabel")
						local textlabel = Backpack_Frame:FindFirstChildOfClass("TextLabel")
						if imagelabel and data.empty then
							if imagelabel then imagelabel:Destroy() end
							if textlabel then textlabel:Destroy() end
						end
						if not data.empty and not imagelabel then
							NewLabel(Backpack_Frame, data)
						end
					end
				end
			else
				-- no template slots: create placeholder ImageLabel slots then add content
				for key,data in pairs(Backpack) do
					-- create slot if doesn't exist
					local Backpack_Frame = Backpack_Gui:FindFirstChild(key)
					if not Backpack_Frame then
						local new_image = Instance.new("ImageLabel")
						new_image.Name = key
						new_image.Parent = Backpack_Gui
						new_image.Image = "rbxassetid://135433152032870"
						new_image.ImageColor3 = Color3.fromRGB(62, 62, 62)
						new_image.Size = UDim2.new(0.1, 0,0.225, 0)
						new_image.Position = UDim2.new(0.5,0,0.5,0)
						new_image.AnchorPoint = Vector2.new(0.5,0.5)
						new_image.Transparency = 1
						new_image.ImageTransparency = 0.6

						local stroke = Instance.new("UIStroke")
						stroke.Parent = new_image
						stroke.Thickness = 1.5
						stroke.Color = Color3.fromRGB(180, 180, 180)
						stroke.Transparency = 0.5
						stroke.ZIndex = 1

						local ui = Instance.new("UIAspectRatioConstraint")
						ui.Parent = new_image
						Backpack_Frame = new_image
					end

					-- add content if not empty
					local imagelabel = Backpack_Frame:FindFirstChildOfClass("ImageLabel")
					if not data.empty and not imagelabel then
						NewLabel(Backpack_Frame, data)
					elseif data.empty and imagelabel then
						imagelabel:Destroy()
						local txt = Backpack_Frame:FindFirstChildOfClass("TextLabel")
						if txt then txt:Destroy() end
					end
				end
			end
		else
			-- empty backpack, clear visuals
			for _,v in pairs(Backpack_Gui:GetChildren()) do
				if v:IsA("ImageLabel") or v:IsA("ImageButton") then
					v:Destroy()
				end
			end
		end
	end

	-- POCKET update
	if Pocket and Pocket_Gui then
		for key,data in pairs(Pocket) do
			local Pocket_Frame = Pocket_Gui:FindFirstChild(key)
			if Pocket_Frame then
				local imagelabel = Pocket_Frame:FindFirstChildOfClass("ImageLabel")
				local textlabel = Pocket_Frame:FindFirstChildOfClass("TextLabel")

				if not data.empty then
					if not imagelabel then
						NewLabel(Pocket_Frame, data)
					end
					if textlabel then
						if data.amount and data.amount >= 2 then
							textlabel.Text = "x"..data.amount
						else
							textlabel.Text = ""
						end
					end
				else
					-- clear visuals if empty
					if imagelabel then imagelabel:Destroy() end
					if textlabel then textlabel.Text = "" end
				end
			end
		end
	end

	-- hover handlers are attached after UI changes
	connectHoverForContainers()
end

-- Function: handle AddItem_Remote (Hotbar update)
-- Updates hotbar icons based on server hotbar data
local function onHotbarUpdate(hotbar)
	if not hotbar then return end
	Hotbar_Save = hotbar

	if InventoryGui and Main_Hotbar then
		for i, data in pairs(hotbar) do
			local Hotbar_Slot = Main_Hotbar:FindFirstChild(i)
			if Hotbar_Slot then
				local icon_check = Hotbar_Slot:FindFirstChild("Selected")
				local text_check = Hotbar_Slot:FindFirstChild("ToolName")
				local image_check = Hotbar_Slot:FindFirstChild("icon")

				if not data.empty then
					if text_check and not text_check.Visible and image_check then
						text_check.Visible = true
						image_check.Visible = image_visible
						if data.image then image_check.Image = data.image end
						if data.id then text_check.Text = data.id end
					else
						-- Update item image and text
						if image_check and data.image then image_check.Image = data.image end
						if text_check and data.id then text_check.Text = data.id end
					end
				else
					-- empty slot: hide visuals
					if image_check then image_check.Visible = false end
					if text_check then text_check.Visible = false end
					if icon_check then icon_check.Visible = false end
				end
			end
		end
	end
end

-- Function: switch weapon via remote
-- Sends a request to server to equip a tool from the given slot/folder
local function switchWeapon(tool, charName, folderName)
	if not tool then return end
	local currentTime = tick()
	if currentTime - lastSwitchTime >= cooldownTime then
		lastSwitchTime = currentTime
		EquipRemote:FireServer(tool, charName, folderName)
	end
end

-- Input handlers: hotbar keys and inventory toggle (B)
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end

	-- Toggle inventory with B
	if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.B then
		if InventoryGui.Enabled then
			InventoryGui.Enabled = false
			local openSound = script:FindFirstChild("Sound") and script.Sound:FindFirstChild("OpenGui")
			if openSound then pcall(function() openSound:Play() end) end
		else
			InventoryGui.Enabled = true
			local openSound = script:FindFirstChild("Sound") and script.Sound:FindFirstChild("OpenGui")
			if openSound then pcall(function() openSound:Play() end) end
			-- ask server to update player data
			pcall(function() Update_Player:FireServer() end)
		end
	end

	-- Hotbar number keys
	if input.UserInputType == Enum.UserInputType.Keyboard then
		for keyName, data in pairs(inputKeys) do
			if input.KeyCode == Enum.KeyCode[keyName] then
				local hotbar_folder = player:FindFirstChild("Inventory") and player.Inventory:FindFirstChild(data.txt)
				local tool
				if hotbar_folder then
					tool = hotbar_folder:FindFirstChildOfClass("Tool")
				end
				switchWeapon(tool, char.Name, data.txt)
			end
		end
	end
end)

-- Selected toggles (remote) - marks a hotbar slot as selected
SelectRemote.OnClientEvent:Connect(function(action, name, namehotbars)
	for _,v in pairs(Main_Hotbar:GetChildren()) do
		if v:IsA("ImageButton") or v:IsA("ImageLabel") then
			local toolname = v:FindFirstChild("ToolName")
			local selected = v:FindFirstChild("Selected")
			if selected then
				selected.Visible = false
				if action == "equip" and toolname and toolname.Text == name and v.Name == namehotbars then
					selected.Visible = true
				elseif action == "swap" and toolname and toolname.Text == name and v.Name == namehotbars then
					selected.Visible = true
				end
			end
		end
	end
end)

-- Hotbar AddItem remote
AddItem_Remote.OnClientEvent:Connect(onHotbarUpdate)

-- Update_Player remote - update whole inventory UI
Update_Player.OnClientEvent:Connect(function(Player_Data)
	-- Update visuals
	handleUpdatePlayer(Player_Data)

	-- hover selects connected after update
	connectHoverForContainers()
end)

-- Drop UI remote - shows transient drop notification with tweening
DropUi_Remote.OnClientEvent:Connect(function(data)
	-- data expected to contain .image
	local new_ui = DropUiTemplate:Clone()
	new_ui.Parent = CustomHotBarGui
	new_ui.Position = UDim2.new(1.2,0,0.5,0)

	local image = new_ui:FindFirstChild("ImageLabel")
	if image and data and data.image then
		image.Image = data.image
		image.BackgroundTransparency = 1
	end

	local text = new_ui:FindFirstChild("TextLabel")
	local uistroke = new_ui:FindFirstChild("UIStroke")

	local tweenInfo_new_ui = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out, 0, false, 0)
	local tweenInfo_new_ui_e = TweenInfo.new(0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0)

	local goal_f = {
		Position = UDim2.new(0.928, 0, 0.5, 0)
	}

	local ends_f = {
		Position = UDim2.new(0.928, 0, 0.7, 0),
		Transparency = 1
	}

	local goal_f_image = {
		ImageTransparency = 1
	}

	local goal_f_text = {
		Transparency = 1
	}

	local image_tw = image and TweenService:Create(
		image, 
		tweenInfo_new_ui_e, 
		goal_f_image
	)
	local text_tw = text and TweenService:Create(
		text, 
		tweenInfo_new_ui_e, 
		goal_f_text
	)

	local stroke_tw = uistroke and TweenService:Create(
		uistroke, 
		tweenInfo_new_ui_e, 
		goal_f_text
	)

	local new_ui_tw = TweenService:Create(
		new_ui, tweenInfo_new_ui, 
		goal_f
	)
	local new_ui_tw_e = TweenService:Create(
		new_ui, 
		tweenInfo_new_ui_e,
		ends_f
	)

	new_ui_tw:Play()
	new_ui_tw.Completed:Wait()

	new_ui_tw_e:Play()
	if image_tw then image_tw:Play() end
	if text_tw then text_tw:Play() end
	if stroke_tw then stroke_tw:Play() end

	-- optionally destroy after animation finishes to keep UI clean
	new_ui_tw_e.Completed:Connect(function()
		if new_ui and new_ui.Parent then
			new_ui:Destroy()
		end
	end)
end)

-- Initial setup: attach hover handlers for existing slots
connectHoverForContainers()

-- request initial data from server
pcall(function()
	Update_Player:FireServer()
end)
