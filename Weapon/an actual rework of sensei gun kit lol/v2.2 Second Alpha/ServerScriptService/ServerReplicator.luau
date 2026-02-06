-- inside ServerScriptService
-- ServerReplicator
local replicateSound = game.ReplicatedStorage.Remotes.Replication.ReplicateSound
local replicateBullet = game.ReplicatedStorage.Remotes.Replication.ReplicateBullet
local replicateFX = game.ReplicatedStorage.Remotes.Replication.ReplicateFX

local activeBullets = 0

local function fireSoundForAll(player, soundId, volume, playbackSpeed)
	for _, otherPlayer in pairs(game.Players:GetPlayers()) do
		if otherPlayer ~= player then
			replicateSound:FireClient(otherPlayer, soundId, volume, playbackSpeed)
		end
	end
end

local function replicate(player, origin, direction, bulletSpeed, newBehavior, tracer, firingMethod)
	if tracer ~= nil then
		for _,v in pairs(game.Players:GetChildren()) do
			if v ~= player then
				replicateBullet:FireClient(v, origin, direction, bulletSpeed, newBehavior, tracer, true, {player.Character}, "Projectile")
			end
		end
	end
end

local function playerJoined(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")

		if player.Team ~= nil then
			humanoid:SetAttribute("Team", player.Team)
		end

		task.wait(0.1)
		for _,v in pairs(character:GetDescendants()) do
			if v.Parent:IsA("Accessory") and v:IsA("BasePart") then
				v.CanCollide = false
				v.CanQuery = false
			end
		end
	end)
end

game.Players.PlayerAdded:Connect(playerJoined)
replicateBullet.OnServerEvent:Connect(replicate)

replicateSound.OnServerEvent:Connect(function(player, soundId, volume, playbackSpeed)
	-- player = the sender (server supplies automatically), forward player's character as first arg
	local originCharacter = player.Character
	for _, otherPlayer in pairs(game.Players:GetPlayers()) do
		if otherPlayer ~= player then
			-- forward (originCharacter, soundId, volume, playbackSpeed)
			replicateSound:FireClient(otherPlayer, originCharacter, soundId, volume, playbackSpeed)
		end
	end
end)


replicateFX.OnServerEvent:Connect(function(player, fxType, position, cframe, targetInstance, impactType)
	if fxType == "impact" then
		for _, otherPlayer in pairs(game.Players:GetPlayers()) do
			if otherPlayer ~= player then
				replicateFX:FireClient(otherPlayer, fxType, position, cframe, nil, impactType)
			end
		end
	end
end)

-- end of ServerReplicator