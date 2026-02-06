-- ServerScriptService
-- replicates neck + shoulder C0 from client to everyone (R6 only, no math)

local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")

local event = replicatedstorage:WaitForChild("LookEvent")

-- cache joints so we don't search every packet
local jointcache = {} -- [player] = {neck, rs, ls}

-- caches torso joints for a character
local function cachejoints(player, char)
	local torso = char:WaitForChild("Torso")

	jointcache[player] = {
		neck = torso:WaitForChild("Neck"),
		rs = torso:WaitForChild("Right Shoulder"),
		ls = torso:WaitForChild("Left Shoulder"),
	}
end

-- setup cache on spawn
players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		cachejoints(player, char)
	end)

	player.CharacterRemoving:Connect(function()
		jointcache[player] = nil
	end)
end)

-- applies C0 to everyone except the sender to prevent feedback jitter
event.OnServerEvent:Connect(function(player, neckc0, rsc0, lsc0)
	for _, other in ipairs(players:GetPlayers()) do
		if other ~= player then
			event:FireClient(other, player, neckc0, rsc0, lsc0)
		end
	end
end)
