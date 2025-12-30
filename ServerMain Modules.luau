-- ServerMain Modules
-- Handles replication and server-side validate/damage logic per-tool.
local ServerMain = {}
ServerMain.__index = ServerMain

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Replication")
local ReplicateSound = RemotesFolder:WaitForChild("ReplicateSound")
local ReplicateBullet = RemotesFolder:WaitForChild("ReplicateBullet")
local ReplicateImpactSound = RemotesFolder:WaitForChild("ReplicateImpactSound")

local Utils = require(ReplicatedStorage.Modules:WaitForChild("Utils"))

local initialized = false	

-- set up global replication handlers (run once)
local function ensureReplicationHandlers()
	if initialized then return end
	initialized = true

	-- replicate sound from client to other clients
	ReplicateSound.OnServerEvent:Connect(function(player, soundId, playbackSpeed)
		-- validate player is alive
		if not player or not player.Character or not player.Character:FindFirstChild("Humanoid") or player.Character.Humanoid.Health <= 0 then
			return
		end

		-- replicate to all other players only (player does not play duplicate)
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				ReplicateSound:FireClient(other, player, soundId, playbackSpeed)
			end
		end
	end)

	-- replicate visual bullets (basic validation)
	ReplicateBullet.OnServerEvent:Connect(function(player, origin, direction, speed, newBehavior, tracer)
		-- basic sanity checks
		if not player or not player.Character or not player.Character:FindFirstChild("Humanoid") then return end
		if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
		if origin.Magnitude > 100000 or direction.Magnitude > 1e6 or direction ~= direction then return end -- guard NaN
		-- forward to others
		for _,other in ipairs(Players:GetPlayers()) do
			if other ~= player and other.Character and other.Character:FindFirstChild("Humanoid") and other.Character.Humanoid.Health > 0 then
				pcall(function()
					ReplicateBullet:FireClient(other, player, origin, direction, speed, newBehavior, tracer)
				end)
			end
		end
	end)

	-- replicate impact sounds to others
	ReplicateImpactSound.OnServerEvent:Connect(function(player, impactType, hitPosition, hitNormal)
		if not player then return end
		if typeof(hitPosition) ~= "Vector3" then return end
		if hitPosition.Magnitude > 100000 then return end
		for _,other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				pcall(function() ReplicateImpactSound:FireClient(other, impactType, hitPosition, hitNormal) end)
			end
		end
	end)
end

-- server-side raycast helper uses Utils.raycast; keep simple wrapper for distance/sanity
local function validatePositionNearPlayer(player, pos, maxDistance)
	if not player or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then 
		return false
	end

	local rootPos = player.Character.HumanoidRootPart.Position
	return (pos - rootPos).Magnitude <= (maxDistance or 100)
end

-- handle VerifyHit from client
function ServerMain.onHit(playerFiring, tool, humanoidArg, hitPartArg, hitPositionArg)
	if not playerFiring then return end
	if not humanoidArg or not humanoidArg:IsA("Humanoid") then return end

	-- sanity: ensure tool belongs to player
	local playerCharacter = playerFiring.Character
	if not playerCharacter or tool.Parent ~= playerCharacter then 
		return
	end

	-- resolve target
	local targetHumanoid = humanoidArg
	local targetCharacter = targetHumanoid.Parent

	if not targetCharacter or not targetCharacter:IsA("Model") then
		return -- just realize this lmao
	end

	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")

	if not targetRoot then return end

	local hitPosition = (typeof(hitPositionArg) == "Vector3" and hitPositionArg)
		or (hitPartArg and hitPartArg:IsA("BasePart") and hitPartArg.Position)
		or targetRoot.Position

	-- team check
	local attackerHumanoid = playerCharacter:FindFirstChild("Humanoid")
	if attackerHumanoid then
		local aTeam = attackerHumanoid:GetAttribute("Team")
		local tTeam = targetHumanoid:GetAttribute("Team")
		if aTeam and tTeam and aTeam == tTeam and not require(tool:WaitForChild("Config")).TeamKillingEnabled then
			return
		end
	end

	-- damage calculation from tool config
	local config = require(tool:WaitForChild("Config"))
	local damage = config.Damage or 0

	if hitPartArg and hitPartArg:IsA("BasePart") and hitPartArg:IsDescendantOf(targetCharacter) then
		local mult = config.DamageMultipliers and config.DamageMultipliers[hitPartArg.Name]
		if mult then
			damage = damage * mult
		end
	end

	if damage <= 0 then return end

	-- apply damage
	targetHumanoid:TakeDamage(damage)

	-- if killed, notify firing client
	if targetHumanoid.Health <= 0 then
		pcall(function() 
			tool.VerifyHit:FireClient(playerFiring, damage)
		end)
	end
end

-- register a tool
function ServerMain.registerTool(tool)
	ensureReplicationHandlers()

	if not tool then return end

	-- Add rigging handling to tool equipped/unequipped
	local Rigging = require(ReplicatedStorage.Modules:WaitForChild("Rigging"))

	-- Function to apply custom rigging and remove default welds
	local function applyRigging(character)
		if not character or not character:IsA("Model") then return end

		-- First, remove any existing default welds (like "RightGrip")
		local rightArm = character:FindFirstChild("Right Arm")
		if rightArm then
			-- Remove any existing RightGrip weld (Roblox auto-created)
			local rightGrip = rightArm:FindFirstChild("RightGrip")
			if rightGrip then
				rightGrip:Destroy()
			end

			-- Also remove any other welds that might be connecting to the tool
			for _, child in pairs(rightArm:GetChildren()) do
				if child:IsA("Weld") or child:IsA("Motor6D") then
					local part1 = child.Part1
					if part1 and part1:IsDescendantOf(tool) then
						child:Destroy()
					end
				end
			end
		end

		-- Now apply our custom rigging
		local config = require(tool:WaitForChild("Config"))
		if config.Rigging then
			for _, rigConfig in ipairs(config.Rigging) do
				local part0 = character:FindFirstChild(rigConfig.Part0)
				local part1 = tool:FindFirstChild(rigConfig.Part1)

				if part0 and part1 then
					Rigging.createMotor6D(part0, part1, rigConfig.C0, rigConfig.C1)
				else
					warn("[Rigging] Could not find parts:", rigConfig.Part0, "or", rigConfig.Part1)
				end
			end
		end
	end
	
	local function bindCharacter(player)
		player.CharacterAdded:Connect(function(character)
			task.wait() -- allow character to finish loading

			if tool.Parent == character then
				applyRigging(character)
			end
		end)
	end

	if tool.Parent:IsA("Model") then
		local player = Players:GetPlayerFromCharacter(tool.Parent)
		if player then
			bindCharacter(player)
		end
	end

	-- Function to clean up rigging
	local function cleanupRigging(character)
		if not character or not character:IsA("Model") then return end
		Rigging.destroyRigTags(character)
	end

	-- Handle equipped event
	tool.Equipped:Connect(function()
		local character = tool.Parent
		if character and character:IsA("Model") then
			-- Wait a frame to ensure Roblox's default welds are created
			task.wait()

			-- Apply our rigging (this will remove default welds and create our Motor6D)
			applyRigging(character)

			-- Set up a listener to catch any late-created default welds
			-- This handles the case where Roblox creates the weld after our initial cleanup
			local rightArm = character:FindFirstChild("Right Arm")
			if rightArm then
				-- Check periodically for a few frames to catch late welds
				for i = 1, 5 do
					task.wait(0.05)
					local rightGrip = rightArm:FindFirstChild("RightGrip")
					if rightGrip then
						rightGrip:Destroy()
						break
					end
				end
			end
		end
	end)

	-- Handle unequipped event
	tool.Unequipped:Connect(function()
		local character = tool.Parent
		if character and character:IsA("Model") then
			cleanupRigging(character)

			-- Also manually destroy any welds connecting to the tool
			for _, descendant in pairs(character:GetDescendants()) do
				if descendant:IsA("Weld") or descendant:IsA("Motor6D") then
					local part1 = descendant.Part1
					if part1 and part1:IsDescendantOf(tool) then
						descendant:Destroy()
					end
				end
			end
		end
	end)

	-- Handle tool being removed/destroyed
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			-- Tool is being removed, clean up any rigging
			local character = tool.Parent
			if character and character:IsA("Model") then
				cleanupRigging(character)
			end
		end
	end)

	if tool:FindFirstChild("VerifyHit") and tool.VerifyHit:IsA("RemoteEvent") then
		tool.VerifyHit.OnServerEvent:Connect(function(player, humanoid, hitPart, hitPosition)
			ServerMain.onHit(player, tool, humanoid, hitPart, hitPosition)
		end)
	else
		warn("[ServerMain] VerifyHit RemoteEvent missing on tool:", tool:GetFullName())
	end
end

return ServerMain

