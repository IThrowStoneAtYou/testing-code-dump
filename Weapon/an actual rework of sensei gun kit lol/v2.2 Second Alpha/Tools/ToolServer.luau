
-- inside tool
-- ToolServer
--task.wait(0.5)

local tool = script.Parent
local player = script:FindFirstAncestorWhichIsA("Player") or game.Players:GetPlayerFromCharacter(script.Parent.Parent)

local myCharacter, myHumanoid, myRoot

local function refreshServerCharacterReferences()
	myCharacter = player.Character
	if myCharacter then
		myHumanoid = myCharacter:WaitForChild("Humanoid")
		myRoot = myCharacter:WaitForChild("HumanoidRootPart")
	end
end

local config = require(tool:WaitForChild('Config'))

local tags = game:GetService("CollectionService")

local teammates = {}
local enemies = {}

local function refreshEnemiesAndTeammates()
	-- ensure character refs are valid
	refreshServerCharacterReferences()

	teammates = {}
	enemies = {}

	-- cannot compare teams without our humanoid
	if not myHumanoid then
		return
	end

	local myTeam = myHumanoid:GetAttribute("Team")

	for _, v in ipairs(workspace:GetChildren()) do
		if v:IsA("Model") then
			local hum = v:FindFirstChildOfClass("Humanoid")
			if hum then
				local team = hum:GetAttribute("Team")

				if team == myTeam then
					table.insert(teammates, v)
				else
					table.insert(enemies, v)
				end
			end
		end
	end
end

local function createMotor6d(p0, p1, c0, c1)
	-- attaches tool part to character part using motor6d
	local motor6d = Instance.new("Motor6D")

	motor6d.Name = p1.Name
	motor6d.Part0 = p0
	motor6d.Part1 = p1
	motor6d.C0 = c0 or CFrame.new()
	motor6d.C1 = c1 or CFrame.new()

	motor6d.Parent = p0

	tags:AddTag(motor6d, "ToolRigJoint")
end

local function onEquip()
	task.wait()

	local currentCharacter = tool.Parent
	if not currentCharacter or not currentCharacter:IsA("Model") then 
		return 
	end

	-- Remove default grip once
	local rightGrip = currentCharacter:FindFirstChild("RightGrip", true)
	if rightGrip then
		rightGrip:Destroy()
	end

	local rigging = config.Rigging
	if not rigging or #rigging == 0 then return end

	for _, v in ipairs(rigging) do
		local p0 = currentCharacter:FindFirstChild(v.Part0, true)
		local p1 = tool:FindFirstChild(v.Part1, true)

		if p0 and p1 then
			createMotor6d(p0, p1, v.C0, v.C1)
		else
			if not p0 then warn("Missing rig Part0:", v.Part0) end
			if not p1 then warn("Missing rig Part1:", v.Part1) end
		end
	end
end

local function onUnequip()
	for _,v in pairs(myCharacter:GetDescendants()) do
		if tags:HasTag(v, "ToolRigJoint") then
			v:Destroy()
		end
	end
end

local function verifyProjectile()
	-- none. sadly.
	-- nan.
end

local function onHit(player, humanoid, hitPart)
	
	if humanoid and humanoid.Parent == myCharacter then
		return
	end
	
	local distanceFromRoot = (hitPart.Position - humanoid.Parent.PrimaryPart.Position).Magnitude

	local ricochetTags = config.RichochetTags
	local isDeflectionSurface = false

	for _,v in pairs(ricochetTags) do
		if tags:HasTag(hitPart, v) or tags:HasTag(hitPart.Parent, v) then
			isDeflectionSurface = true
		end
	end

	if tool.Parent == myCharacter and isDeflectionSurface == false then
		if distanceFromRoot < 6 then
			if humanoid and 
				(
					humanoid:GetAttribute("Team") ~= myHumanoid:GetAttribute("Team") 
						or config.TeamKillingEnabled == true
						or humanoid:GetAttribute("Team") == nil
				) 

					and humanoid.Health > 0 then

				local result = true

				if result == true then
					local multipliers = config.DamageMultipliers
					local damage = config.Damage

					if multipliers[hitPart.Name] ~= nil then
						damage = damage * multipliers[hitPart.Name]
					end

					humanoid:TakeDamage(damage)

					if humanoid.Health <= 0 then
						tool.VerifyHit:FireClient(player, damage)
					end
				end
			end
		end
	end
end

refreshEnemiesAndTeammates()

local childAddedConnection = workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model") and child:FindFirstChild("Humanoid") then
		refreshEnemiesAndTeammates()
	end
end)

local childRemovedConnection = workspace.ChildRemoved:Connect(function(child)
	if child:IsA("Model") and child:FindFirstChild("Humanoid") then
		refreshEnemiesAndTeammates()
	end
end)

tool.VerifyHit.OnServerEvent:Connect(onHit)
tool.Equipped:Connect(onEquip)
tool.Unequipped:Connect(onUnequip)

player.CharacterAdded:Connect(function(newCharacter)
	myCharacter = newCharacter
	myHumanoid = newCharacter:WaitForChild("Humanoid")
	myRoot = newCharacter:WaitForChild("HumanoidRootPart")
end)

-- Call initially
if player.Character then
	refreshServerCharacterReferences()
end
-- end of ToolServer
