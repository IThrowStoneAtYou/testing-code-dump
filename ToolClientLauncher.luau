-- Watches Backpack and Character for Tools and starts ClientMain for each valid tool.
-- i have to do this :sob:

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local clientModules = ReplicatedStorage:WaitForChild("Modules")
local ClientMain = require(clientModules:WaitForChild("ClientMain"))

local toolInstances = {} -- map Tool -> ClientMain instance

local function safeDisconnectConn(conn)
	if conn then
		pcall(function() conn:Disconnect() end)
	end
end

local function tryInitTool(tool)
	if not tool or not tool:IsA("Tool") then return end

	-- Heuristic: only start for tools that have a Config or a Handle
	if not tool:FindFirstChild("Config") and not tool:FindFirstChild("Handle") then
		return
	end

	if toolInstances[tool] then
		return
	end

	local ok, instOrErr = pcall(function()
		-- WaitForChild here 
		local _ = tool:WaitForChild("Config")
		return ClientMain.init(tool, player)
	end)

	if not ok then
		warn("[ToolClientLauncher] ClientMain.init error for tool", tool.Name, instOrErr)
		return
	end

	toolInstances[tool] = instOrErr

	-- cleanup when tool is removed from game
	local ancestryConn
	ancestryConn = tool.AncestryChanged:Connect(function(_, parent)
		if not tool:IsDescendantOf(game) then
			local inst = toolInstances[tool]
			if inst then
				pcall(function() inst:disconnectAll() end)
				toolInstances[tool] = nil
			end
			safeDisconnectConn(ancestryConn)
		end
	end)
end

local function scanContainer(container)
	for _, child in ipairs(container:GetChildren()) do
		tryInitTool(child)
	end
end

local function onBackpackChildAdded(child) tryInitTool(child) end
local function onCharacterChildAdded(child) tryInitTool(child) end

local function setup()
	if not player then
		warn("[ToolClientLauncher] no LocalPlayer yet")
		return
	end

	local backpack = player:WaitForChild("Backpack")
	scanContainer(backpack)
	backpack.ChildAdded:Connect(onBackpackChildAdded)

	if player.Character then
		scanContainer(player.Character)
		player.Character.ChildAdded:Connect(onCharacterChildAdded)
	end

	player.CharacterAdded:Connect(function(char)
		if char then
			scanContainer(char)
			char.ChildAdded:Connect(onCharacterChildAdded)
		end
	end)
end

setup()
