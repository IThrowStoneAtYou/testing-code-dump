-- DragDrop Client local

local Screengui_Inventory = script.Parent.Parent

local MainFrame = script.Parent.Parent.MainFrame
local Equp_Frame = script.Parent.Parent.Equip_Frame

local Backpack_Frame = MainFrame.Backpack
local Pockets_Frame = MainFrame.Pockets

local DropZone = Screengui_Inventory.DropZone

local Equip_Armor = Equp_Frame.Equip_Armor

local Hotbars = Screengui_Inventory.Hotbars
local Description =Screengui_Inventory.Description_Frame.Description_Text

local CutomHotbars = Screengui_Inventory.Parent:FindFirstChild("CustomHotBarGui")
local Hotbars_ = CutomHotbars.Main_Hotbar

----Remote Event---------
local DragDrop_RF = game.ReplicatedStorage.Gui_Inventory_Manager.Gui_Manager.Drag_Drop
local Update_Backpack = game.ReplicatedStorage.Gui_Inventory_Manager.Gui_Manager.Update_Backpack
local Update_Player = game.ReplicatedStorage.Gui_Inventory_Manager.Remote.Update_Player

----Service--------------
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-------------------------
local First_Target = nil
local Drag = false
local Connect
local OpenGui = script.Parent.Parent.Sound.OpenGui
local EnterGui = script.Parent.Parent.Sound.EnterGui
local Data_PlayerSave

Update_Player.OnClientEvent:Connect(function(Player_Data)
	Data_PlayerSave = Player_Data
end)

if Pockets_Frame then
	for key,data in pairs(Pockets_Frame:GetChildren()) do
		if data:IsA("ImageLabel") then
			data.InputBegan:Connect(function(input)----DragItem)
				if Data_PlayerSave then
					local slot = Data_PlayerSave.Pockets[data.Name]
					if not slot.empty then
						if Description then
							local typing = true
							local typingCoroutine = coroutine.create(function()
								for i = 1, #slot.name do
									if not typing then 
										break
									end

									Description.Text = slot.name:sub(1, i)
									task.wait(0.001)
								end
							end)
							coroutine.resume(typingCoroutine)
						end
					end
				end

				if input.UserInputType == Enum.UserInputType.MouseButton1 and not Drag then
					DragF(data,input)		
				end				
			end)

			data.InputBegan:Connect(function(input)
				UIS.InputEnded:Connect(function(input)----DropItem	

					if input.UserInputType == Enum.UserInputType.MouseButton1 and Drag then
						DropF(data,input)
					end				
				end)		
			end)		
		end		
	end
end

if Equip_Armor then
	for key,data in pairs(Equip_Armor:GetChildren()) do
		if data:IsA("ImageLabel") then
			data.InputBegan:Connect(function(input)----DragItem
				if input.UserInputType == Enum.UserInputType.MouseButton1 and not Drag then
					DragF(data,input)		
				end				
			end)

			data.InputBegan:Connect(function(input)
				UIS.InputEnded:Connect(function(input)----DropItem	
					if input.UserInputType == Enum.UserInputType.MouseButton1 and Drag then
						DropF(data,input)
					end				
				end)		
			end)		
		end		
	end
end

Update_Backpack.OnClientEvent:Connect(function(player)
	if Backpack_Frame then
		for key,data in pairs(Backpack_Frame:GetChildren()) do
			if data:IsA("ImageLabel") then
				data.InputBegan:Connect(function(input)----DragItem
					if input.UserInputType == Enum.UserInputType.MouseButton1 and not Drag then	
						DragF(data,input)		
					end				
				end)

				data.InputBegan:Connect(function(input)
					UIS.InputEnded:Connect(function(input)----DropItem	

						if input.UserInputType == Enum.UserInputType.MouseButton1 and Drag then
							DropF(data,input)
						end				
					end)		
				end)		
			end		
		end
	end
end)

if Hotbars then
	for key,data in pairs(Hotbars:GetChildren()) do
		if data:IsA("ImageLabel") then
			data.InputBegan:Connect(function(input)----DragItem
				if input.UserInputType == Enum.UserInputType.MouseButton1 and not Drag then
					DragF(data,input)		
				end				
			end)

			data.InputBegan:Connect(function(input)
				UIS.InputEnded:Connect(function(input)----DropItem	
					if input.UserInputType == Enum.UserInputType.MouseButton1 and Drag then
						DropF(data,input)
					end				
				end)		
			end)		
		end		
	end
end

if DropZone then
	for key,data in pairs(DropZone:GetChildren()) do
		if data:IsA("ImageLabel") then
			data.InputBegan:Connect(function(input)----DragItem
				if input.UserInputType == Enum.UserInputType.MouseButton1 and not Drag then
					DragF(data,input)		
				end				
			end)

			data.InputBegan:Connect(function(input)
				UIS.InputEnded:Connect(function(input)----DropItem	
					if input.UserInputType == Enum.UserInputType.MouseButton1 and Drag then
						DropF(data,input)
					end				
				end)		
			end)		
		end		
	end
end

if Hotbars_ then
	for key,data in pairs(Hotbars_:GetChildren()) do
		if data:IsA("ImageLabel") then
			data.InputBegan:Connect(function(input)----DragItem

				if input.UserInputType == Enum.UserInputType.MouseButton1 and not Drag then
					DragF(data,input)		
				end				
			end)

			data.InputBegan:Connect(function(input)
				UIS.InputEnded:Connect(function(input)----DropItem	

					if input.UserInputType == Enum.UserInputType.MouseButton1 and Drag then
						DropF(data,input)
					end				
				end)		
			end)		
		end		
	end
end

function DragF(data,input)
	local image = data:FindFirstChildOfClass("ImageLabel")
	local text = data:FindFirstChild("Amount")

	if image and text then
		image.Parent = Screengui_Inventory
		image.Size = UDim2.new(.04,0,0.08,0)
		image.Position = UDim2.new(0,input.Position.X,0,input.Position.Y)

		text.Parent = Screengui_Inventory
		text.Size = UDim2.new(.01,0,.02,0)
		text.Position = UDim2.new(0,input.Position.X+10,0,input.Position.Y+20)

		local image_drag = Screengui_Inventory:FindFirstChildOfClass("ImageLabel")
		local text_drag = Screengui_Inventory:FindFirstChild("Amount")

		if image_drag and text_drag then
			Connect = UIS.InputChanged:Connect(function(input)

				if input.UserInputType == Enum.UserInputType.MouseMovement then
					image.Parent = Screengui_Inventory
					image.Size = UDim2.new(.04,0,0.08,0)
					image.Position = UDim2.new(0,input.Position.X,0,input.Position.Y)

					text.Parent = Screengui_Inventory
					text.Size = UDim2.new(.02,0,.04,0)
					text.Position = UDim2.new(0,input.Position.X+10,0,input.Position.Y+20)
				end							
			end)

			First_Target = data
			Drag = true
		end	
	end			
end

function DropF(data,input)
	Drag = false

	local image_drag = Screengui_Inventory:FindFirstChildOfClass("ImageLabel")
	local text_drag = Screengui_Inventory:FindFirstChild("Amount")

	if image_drag and text_drag then	
		if First_Target.Parent.Name == data.Parent.Name then
			if First_Target.Name == data.Name then
				image_drag.Parent = First_Target
				image_drag.Position = UDim2.new(0.5,0,0.5,0)
				image_drag.Size = UDim2.new(0.9,0,0.9,0)					

				text_drag.Parent = First_Target
				text_drag.Position = UDim2.new(0.6,0,0.7,0)
				text_drag.Size = UDim2.new(0.3,0,0.3,0)
				Drag = false	

				if Connect then
					Connect:Disconnect()
					Connect = nil
				end	

				return
			end
		end

		local result,player_data = DragDrop_RF:InvokeServer(First_Target.Name,data.Name)
		Data_PlayerSave = player_data

		if result == "Drop_Empty" then
			Update_Player:FireServer(player_data)
			local image_drop = data:FindFirstChildOfClass("ImageLabel")
			local text_drop = data:FindFirstChild("Amount")
			if First_Target and not image_drop and not text_drop then
				image_drag.Parent = data
				image_drag.Position = UDim2.new(0.5,0,0.5,0)
				image_drag.Size = UDim2.new(0.9,0,0.9,0)					

				text_drag.Parent = data
				text_drag.Position = UDim2.new(0.6,0,0.7,0)
				text_drag.Size = UDim2.new(0.3,0,0.3,0)

				Drag = false	

				if Connect then
					Connect:Disconnect()
					Connect = nil
				end
				return
			end	
		end

		if result == "Swap" then
			Update_Player:FireServer(player_data)
			local image_drop = data:FindFirstChildOfClass("ImageLabel")
			local text_drop = data:FindFirstChild("Amount")


			if First_Target and image_drop and text_drop then

				--[[
				image_drag.Parent = data
				image_drag.Position = UDim2.new(0.5,0,0.5,0)
				image_drag.Size = UDim2.new(0.9,0,0.9,0)					

				text_drag.Parent = data
				text_drag.Position = UDim2.new(0.6,0,0.7,0)
				text_drag.Size = UDim2.new(0.3,0,0.3,0)
				
				image_drop.Parent = First_Target
				image_drop.Position = UDim2.new(0.5,0,0.5,0)
				image_drop.Size = UDim2.new(0.9,0,0.9,0)					

				text_drop.Parent = First_Target
				text_drop.Position = UDim2.new(0.6,0,0.7,0)
				text_drop.Size = UDim2.new(0.3,0,0.3,0)
				]]

				image_drag:Destroy()
				text_drag:Destroy()
				image_drop:Destroy()
				text_drop:Destroy()

				if Connect then
					Connect:Disconnect()
					Connect = nil
				end
				Drag = false	
				return
			end											
		end			

		if result == "ComeBack" then
			image_drag.Parent = First_Target
			image_drag.Position = UDim2.new(0.5,0,0.5,0)
			image_drag.Size = UDim2.new(0.9,0,0.9,0)					

			text_drag.Parent = First_Target
			text_drag.Position = UDim2.new(0.6,0,0.7,0)
			text_drag.Size = UDim2.new(0.3,0,0.3,0)

			Drag = false	

			if Connect then
				Connect:Disconnect()
				Connect = nil
			end			

			return
		end

		if result == "Drop" then
			Update_Player:FireServer(player_data)
			image_drag:Destroy()
			text_drag:Destroy()

			Drag = false	

			if Connect then
				Connect:Disconnect()
				Connect = nil
			end	

			return
		end

	end
end