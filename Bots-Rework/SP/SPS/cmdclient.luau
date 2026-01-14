local replicatedstorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")

local player = players.LocalPlayer
local send = replicatedstorage:WaitForChild("botcmd"):WaitForChild("send")

print("localcmds started")

local function build_ui()
	print("build_ui called")

	local gui = Instance.new("ScreenGui")
	gui.Parent = player:WaitForChild("PlayerGui")

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromScale(0.4, 0.05)
	box.Position = UDim2.fromScale(0.3, 0.9)
	box.PlaceholderText = "/fire2"
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = gui

	-- this sends gui text to the server chat parser
	box.FocusLost:Connect(function(enter)
		print("gui submit", enter)

		if enter then
			send:FireServer(box.Text)
			box.Text = ""
		end
	end)
end

build_ui()
