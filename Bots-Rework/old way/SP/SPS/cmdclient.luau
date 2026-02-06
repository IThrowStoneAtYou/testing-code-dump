-- localcmds (localscript)

local replicatedstorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local player = players.LocalPlayer
local send = replicatedstorage:WaitForChild("botcmd"):WaitForChild("send")

print("localcmds started")

local gui_name = "bot_command_gui"

local function destroy_old_ui()
	-- removes existing gui to prevent duplicates

	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end

	local old = pg:FindFirstChild(gui_name)
	if old then
		old:Destroy()
	end
end

local function build_ui()
	-- creates command textbox ui
	print("build_ui called")
	debug.profilebegin("build_ui")

	local playergui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = gui_name
	gui.ResetOnSpawn = false
	gui.Parent = playergui

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromScale(0.4, 0.05)
	box.Position = UDim2.fromScale(0.3, 0.9)
	box.PlaceholderText = "/fire2"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = gui

	-- sends gui text to server
	box.FocusLost:Connect(function(enter)
		print("gui submit", enter)

		if enter and box.Text ~= "" then
			send:FireServer(box.Text)
			box.Text = ""
		end
	end)
	
	debug.profileend()
end

local function on_character_added(character)
	-- rebuild ui after respawn
	print("character added")
	debug.profilebegin("build_ui")
	
	destroy_old_ui()
	build_ui()
end

-- initial build
if player.Character then
	on_character_added(player.Character)
end

-- rebuild on respawn
player.CharacterAdded:Connect(on_character_added)
