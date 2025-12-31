-- ServerMain Modules: centralized replication handlers, minimal VerifyHit routing, and rigging integration.

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
local VerifyHitRemote = RemotesFolder:WaitForChild("VerifyHit")

local Utils = require(ReplicatedStorage.Modules:WaitForChild("Utils"))
local Rigging = require(ReplicatedStorage.Modules:WaitForChild("Rigging"))

local _perToolListeners = {} -- map tool -> { connections = { RBXScriptConnection, ... } }

local function safeDisconnect(conn)
	if conn then
		pcall(function() conn:Disconnect() end)
	end
end

local function disconnectAll(conns)
	if not conns then return end
	for _, c in ipairs(conns) do safeDisconnect(c) end
end

local function removeToolWeldsFromCharacter(tool, character)
	if not tool or not character then return end

	for _, desc in ipairs(character:GetDescendants()) do
		local destroyed = false
		if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("Motor6D") then
			local p0 = desc.Part0
			local p1 = desc.Part1
			if (p0 and p0:IsDescendantOf(tool)) or (p1 and p1:IsDescendantOf(tool)) then destroyed = true end
			if not destroyed and desc.Attachment0 and desc.Attachment0:IsDescendantOf(tool) then destroyed = true end
			if not destroyed and desc.Attachment1 and desc.Attachment1:IsDescendantOf(tool) then destroyed = true end
		end

		if not destroyed and desc.Name == "RightGrip" and (desc:IsA("Weld") or desc:IsA("Motor6D")) then
			local p1 = desc.Part1
			if p1 and p1:IsDescendantOf(tool) then destroyed = true end
		end

		if destroyed then
			pcall(function() desc:Destroy() end)
		end
	end
end

local function createMotorsWithConfig(tool, character)
	if not tool or not character then return false end

	local config
	local okCfg, cfg = pcall(function() return require(tool:WaitForChild("Config")) end)
	config = okCfg and cfg or nil

	if config and config.Rigging and type(config.Rigging) == "table" and #config.Rigging > 0 then
		local createdAny = false
		for _, rigCfg in ipairs(config.Rigging) do
			local p0 = character:FindFirstChild(rigCfg.Part0) or character:FindFirstChildWhichIsA("BasePart")
			local p1 = tool:FindFirstChild(rigCfg.Part1) or tool:FindFirstChildWhichIsA("BasePart")
			if p0 and p1 then
				pcall(function()
					Rigging.createMotor6D(p0, p1, rigCfg.C0 or CFrame.new(), rigCfg.C1 or CFrame.new())
				end)
				createdAny = true
			end
		end
		if createdAny then return true end
	end

	-- Fallback rigging
	local handPart = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not handPart then
		for _, v in ipairs(character:GetChildren()) do
			if v:IsA("BasePart") and string.find(v.Name:lower(), "right") then
				handPart = v
				break
			end
		end
	end

	local toolPart = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
	if not (handPart and toolPart) then
		return false
	end

	pcall(function()
		Rigging.createMotor6D(handPart, toolPart, CFrame.new(), CFrame.new())
	end)
	return true
end

local function applyRigging(tool, character)
	if not tool or not character then return end
	removeToolWeldsFromCharacter(tool, character)
	local ok = createMotorsWithConfig(tool, character)
	if not ok then
		warn("[ServerMain] applyRigging: fallback failed for tool:", tool:GetFullName())
	end
end

local function watchForLateWelds(tool, character)
	if not tool or not character then return end

	if _perToolListeners[tool] and _perToolListeners[tool].connections then
		disconnectAll(_perToolListeners[tool].connections)
	end
	_perToolListeners[tool] = { connections = {} }

	local function onDescendantAdded(desc)
		task.delay(0.01, function()
			if not desc or not desc:IsDescendantOf(character) then return end

			local needsRemove = false
			if desc:IsA("Weld") or desc:IsA("WeldConstraint") or desc:IsA("Motor6D") then
				local p0 = desc.Part0
				local p1 = desc.Part1
				if (p0 and p0:IsDescendantOf(tool)) or (p1 and p1:IsDescendantOf(tool)) then
					needsRemove = true
				end
				if not needsRemove and desc.Attachment0 and desc.Attachment0:IsDescendantOf(tool) then needsRemove = true end
				if not needsRemove and desc.Attachment1 and desc.Attachment1:IsDescendantOf(tool) then needsRemove = true end
			end

			if not needsRemove and desc.Name == "RightGrip" and (desc:IsA("Weld") or desc:IsA("Motor6D")) then
				local p1 = desc.Part1
				if p1 and p1:IsDescendantOf(tool) then needsRemove = true end
			end

			if needsRemove then
				pcall(function() desc:Destroy() end)
				applyRigging(tool, character)
			end
		end)
	end

	local descConn = character.DescendantAdded:Connect(onDescendantAdded)
	table.insert(_perToolListeners[tool].connections, descConn)

	local ancestryConn
	ancestryConn = tool.AncestryChanged:Connect(function(_, parent)
		if not tool:IsDescendantOf(game) then
			disconnectAll(_perToolListeners[tool].connections)
			_perToolListeners[tool] = nil
			safeDisconnect(ancestryConn)
		end
	end)
	table.insert(_perToolListeners[tool].connections, ancestryConn)
end

-- Replication handlers
local initialized = false
local function ensureReplicationHandlers()
	if initialized then return end
	initialized = true

	ReplicateSound.OnServerEvent:Connect(function(player, soundId, playbackSpeed)
		if not player or not player.Character or not player.Character:FindFirstChild("Humanoid") or player.Character.Humanoid.Health <= 0 then
			return
		end
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player then
				pcall(function() ReplicateSound:FireClient(other, player, soundId, playbackSpeed) end)
			end
		end
	end)

	ReplicateBullet.OnServerEvent:Connect(function(player, origin, direction, speed, newBehavior, tracer)
		if not player or not player.Character or not player.Character:FindFirstChild("Humanoid") then return end
		if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
		if origin.Magnitude > 100000 or direction.Magnitude > 1e6 or direction ~= direction then return end
		for _,other in ipairs(Players:GetPlayers()) do
			if other ~= player and other.Character and other.Character:FindFirstChild("Humanoid") and other.Character.Humanoid.Health > 0 then
				pcall(function()
					ReplicateBullet:FireClient(other, player, origin, direction, speed, newBehavior, tracer)
				end)
			end
		end
	end)

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

	VerifyHitRemote.OnServerEvent:Connect(function(player, toolArg, humanoid, hitPart, hitPosition)
		if not player then return end
		if typeof(toolArg) ~= "Instance" or not toolArg:IsA("Tool") then
			return
		end

		local playerChar = player and player.Character
		if not playerChar or toolArg.Parent ~= playerChar then
			return
		end

		pcall(function()
			ServerMain.onHit(player, toolArg, humanoid, hitPart, hitPosition)
		end)
	end)
end

-- onHit: server-side damage application
function ServerMain.onHit(playerFiring, tool, humanoidArg, hitPartArg, hitPositionArg)
	if not playerFiring then return end
	if not humanoidArg or not humanoidArg:IsA("Humanoid") then return end

	local playerCharacter = playerFiring.Character
	if not playerCharacter or tool.Parent ~= playerCharacter then return end

	local targetHumanoid = humanoidArg
	local targetCharacter = targetHumanoid.Parent
	if not targetCharacter or not targetCharacter:IsA("Model") then return end

	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	local hitPosition = (typeof(hitPositionArg) == "Vector3" and hitPositionArg)
		or (hitPartArg and hitPartArg:IsA("BasePart") and hitPartArg.Position)
		or targetRoot.Position

	-- team check + config
	local attackerHumanoid = playerCharacter:FindFirstChild("Humanoid")
	local ok, cfg = pcall(function() return require(tool:WaitForChild("Config")) end)
	local config = ok and cfg or nil

	if attackerHumanoid then
		local aTeam = attackerHumanoid:GetAttribute("Team")
		local tTeam = targetHumanoid:GetAttribute("Team")
		if aTeam and tTeam and aTeam == tTeam then
			if config and config.TeamKillingEnabled then
				-- allowed
			else
				return
			end
		end
	end

	-- damage calculation
	local damage = (config and config.Damage) or 0
	if hitPartArg and hitPartArg:IsA("BasePart") and hitPartArg:IsDescendantOf(targetCharacter) then
		local mult = config and config.DamageMultipliers and config.DamageMultipliers[hitPartArg.Name]
		if mult then
			damage = damage * mult
		end
	end

	if damage <= 0 then return end

	pcall(function() targetHumanoid:TakeDamage(damage) end)

	if targetHumanoid.Health <= 0 then
		pcall(function() VerifyHitRemote:FireClient(playerFiring, tool, damage) end)
	end
end

-- registerTool: bind rigging and lifecycle behavior
function ServerMain.registerTool(tool)
	ensureReplicationHandlers()
	if not tool or not tool:IsA("Tool") then return end

	local function onToolEquipped()
		local character = tool.Parent
		if character and character:IsA("Model") then
			task.wait(0.02)
			applyRigging(tool, character)
			watchForLateWelds(tool, character)
		end
	end

	local function onToolUnequipped()
		local character = tool.Parent
		if character and character:IsA("Model") then
			pcall(function() Rigging.destroyRigTags(character) end)
			removeToolWeldsFromCharacter(tool, character)
		end

		if _perToolListeners[tool] and _perToolListeners[tool].connections then
			disconnectAll(_perToolListeners[tool].connections)
			_perToolListeners[tool] = nil
		end
	end

	tool.Equipped:Connect(onToolEquipped)
	tool.Unequipped:Connect(onToolUnequipped)

	-- If tool already parented to a character, re-apply rigging on that player's CharacterAdded
	if tool.Parent and tool.Parent:IsA("Model") then
		local player = Players:GetPlayerFromCharacter(tool.Parent)
		if player then
			player.CharacterAdded:Connect(function(character)
				task.wait(0.02)
				if tool.Parent == character then
					applyRigging(tool, character)
					watchForLateWelds(tool, character)
				end
			end)
		end
	end

	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			if _perToolListeners[tool] and _perToolListeners[tool].connections then
				disconnectAll(_perToolListeners[tool].connections)
				_perToolListeners[tool] = nil
			end
		end
	end)
end

return ServerMain
