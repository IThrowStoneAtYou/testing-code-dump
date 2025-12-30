-- ToolClient Local
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientMain = require(ReplicatedStorage.Modules:WaitForChild("ClientMain"))
local player = game.Players.LocalPlayer
local tool = script.Parent

-- init client main for this tool
local ok, instance = pcall(function() return ClientMain.init(tool, player) end)
if not ok then
	warn("ClientMain init failed:", instance)
end
