-- Registers tool templates on the server and calls ServerMain.registerTool for each valid Tool.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")

local ServerMain = require(ReplicatedStorage.Modules:WaitForChild("ServerMain"))

local function registerToolIfValid(tool)
	if not tool or not tool:IsA("Tool") then return end
	
	-- only register weapons that have Config
	if not tool:FindFirstChild("Config") then
		return
	end

	pcall(function() ServerMain.registerTool(tool) end)
end

-- Register tools in StarterPack
for _, tool in ipairs(StarterPack:GetChildren()) do
	registerToolIfValid(tool)
end

StarterPack.ChildAdded:Connect(registerToolIfValid)
