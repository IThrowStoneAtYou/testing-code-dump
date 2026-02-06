-- inside tool
-- ToolClient (local)
--task.wait(0.5)

local tool = script.Parent
local config = require(tool:WaitForChild('Config'))

local player = game.Players.LocalPlayer
local character, humanoid, root
local firingPoint

local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local function createAnimation(id)
	if not id or id == "" then
		warn("Animation ID missing or invalid")
		return nil
	end

	local animObject = Instance.new("Animation")
	animObject.AnimationId = 'rbxassetid://'..id

	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
	local success, loadedAnim = pcall(function()
		return animator:LoadAnimation(animObject)
	end)

	if success then
		return loadedAnim
	else
		warn("Failed to load animation with ID:", id)
		return nil
	end
end

local function createSound(id, volume, pitch)
	if not id or id == "" then
		warn("Sound ID missing or invalid")
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Parent = tool:FindFirstChild("Handle") or tool
	sound.SoundId = 'rbxassetid://'..id
	sound.Volume = volume or 1
	sound.PlaybackSpeed = pitch or 1
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 300
	sound.RollOffMode = Enum.RollOffMode.Linear
	return sound
end

local runService = game:GetService("RunService")
local tags = game:GetService("CollectionService")
local userInputService = game:GetService("UserInputService")
local contextActionService = game:GetService("ContextActionService")

local spring = require(game.ReplicatedStorage.Modules.spring)
local fastCast = require(game.ReplicatedStorage.Modules.FastCastRedux)
local caster = fastCast.new()
local cameraRecoil = spring.create()

local teammates = {}
local enemies = {}

local bulletParams = RaycastParams.new()
bulletParams.FilterDescendantsInstances = {}
bulletParams.FilterType = Enum.RaycastFilterType.Exclude

local bulletSpeed = config.ProjectileSpeed

local behavior = fastCast.newBehavior()
behavior.RaycastParams = bulletParams
behavior.CosmeticBulletTemplate = config.TracerTemplate
behavior.CosmeticBulletContainer = config.TracerContainer
behavior.Acceleration = config.ProjectileAcceleration or Vector3.new()
behavior.MaxDistance = 3000

-- build and apply a safe FilterDescendantsInstances list
local function updateBulletFilter()
	-- construct only valid Instance objects for the filter
	local list = {}

	-- add character if valid
	if character and typeof(character) == "Instance" then
		table.insert(list, character)
	end

	-- add tracer container from config if it's a valid Instance
	if config and config.TracerContainer and typeof(config.TracerContainer) == "Instance" then
		table.insert(list, config.TracerContainer)
	end

	-- if ignoring teammates, add each teammate Instance (not the table)
	if config and config.IgnoreTeammates == true and teammates then
		for _, t in ipairs(teammates) do
			if t and typeof(t) == "Instance" then
				table.insert(list, t)
			end
		end
	end

	-- apply to bulletParams and the fastCast behavior
	bulletParams.FilterDescendantsInstances = list
	bulletParams.FilterType = Enum.RaycastFilterType.Exclude

	-- ensure behavior uses the updated params
	if behavior then
		behavior.RaycastParams = bulletParams
	end
end

-- initial apply (safe even when character/config not ready)
updateBulletFilter()

local firingPoint = nil

if not tool:FindFirstChild("FiringPoint", true) then
	-- cannot find a firing point so let's make one
	firingPoint = Instance.new("Attachment")
	firingPoint.Parent = tool:FindFirstChildOfClass("BasePart")
	firingPoint.Name = "FiringPoint"
else
	firingPoint = tool:FindFirstChild("FiringPoint", true)
end

local RNG = Random.new()
local TAU = math.pi * 2

local idleAnimation
local fireAnimation
local reloadFinishAnimation
local reloadAnimation
local equipAnimation

local function rebuildAnimations()
	-- recreate tracks because animator changes on respawn
	-- this is the only fix i came up with since sensen gun kit is cursed. (probably roblox upd)
	idleAnimation = createAnimation(config.IdleAnimation)
	fireAnimation = createAnimation(config.FireAnimation)
	reloadFinishAnimation = createAnimation(config.ReloadFinishAnimation)
	reloadAnimation = createAnimation(config.ReloadAnimation)
	equipAnimation = createAnimation(config.EquipAnimation)
end

local fireSound = createSound(config.FireSound, config.FireSoundVolume)
local reloadSound = createSound(config.ReloadSound, config.ReloadSoundVolume)
local reloadFinishSound = createSound(config.ReloadFinishSound, config.ReloadFinishSoundVolume)

local gui = nil
local toolEquipped = false

local lastFired = 0
local mouseDown = false

local reloading = false

local ammo = config.MagSize
local magSize = config.MagSize

local function refreshCharacterReferences()
	character = player.Character or player.CharacterAdded:Wait()
	if not character then return end

	humanoid = character:WaitForChild("Humanoid")
	root = character:WaitForChild("HumanoidRootPart")

	-- recreate firing point safely
	firingPoint = tool:FindFirstChild("FiringPoint", true)
	if not firingPoint then
		local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildOfClass("BasePart")
		if handle then
			firingPoint = Instance.new("Attachment")
			firingPoint.Name = "FiringPoint"
			firingPoint.Parent = handle
		end
	end

	-- rebuild animations for the new humanoid
	rebuildAnimations()

	-- update raycast filter now that character/humanoid changed
	updateBulletFilter()
end

-- call initially
refreshCharacterReferences()

local function refreshGui()
	if not gui or not gui.Parent then
		return
	end

	local label = gui:FindFirstChild("ChargesLeft")
	if not label then
		return
	end

	label.Text = tostring(ammo)

	if ammo <= 0 then
		label.BackgroundColor3 = Color3.fromRGB(255,0,0)
	else
		label.BackgroundColor3 = Color3.fromRGB(0,0,0)
	end
end

local function raycast(origin, endPos, ignoreList)
	for _,v in pairs(teammates) do
		table.insert(ignoreList, v)
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local direction = (endPos - origin)

	local result = workspace:Raycast(origin, direction, rayParams)
	return result
end

local function isInFirstPerson()
	local dist = (camera.CFrame.Position - character:WaitForChild("Head").Position).Magnitude
	if dist < 1 then
		return true
	else
		return false
	end
end

local function scopeIn()
	if gui and isInFirstPerson() and toolEquipped then
		if config.ZoomEnabled then
			userInputService.MouseDeltaSensitivity = 0.3
			camera.FieldOfView = 30
		end

		if config.AimDownSights then
			tool.FirstPersonArms:SetAttribute("Aiming", true)
		end
	end
end

local function scopeOut()
	if gui then
		if config.ZoomEnabled then
			userInputService.MouseDeltaSensitivity = 1
			camera.FieldOfView = 70
		end

		if config.AimDownSights then
			tool.FirstPersonArms:SetAttribute("Aiming", false)
		end
	end
end

local function performChecksForFiring()
	if humanoid.Health <= 0 then
		return
	end

	if raycast(root.Position, tool.Handle.FiringPoint.WorldPosition, {character, tool}) ~= nil then
		return
	end

	if ammo <= 0 then
		return
	end

	if reloading then
		return
	end

	return true
end

local function refreshEnemiesAndTeammates()
	teammates = {}
	enemies = {}

	for _, v in ipairs(workspace:GetChildren()) do
		if v:IsA("Model") then
			local hum = v:FindFirstChildOfClass("Humanoid")
			if hum then
				-- read team attribute defensively
				local team = hum:GetAttribute("Team") or nil

				-- put model into proper list
				if team ~= nil and humanoid then
					-- if our own humanoid doesn't exist yet, treat as enemy for now
					if humanoid and humanoid:GetAttribute("Team") == team then
						table.insert(teammates, v)
					else
						table.insert(enemies, v)
					end
				else
					-- fallback: unknown teams are enemies
					table.insert(enemies, v)
				end
			end
		end
	end

	-- apply the updated teammates list to the raycast filter
	updateBulletFilter()
end

local function ricochet(hitPosition, hitNormal, originalNormal)
	local reflectedNormal = originalNormal - (2 * originalNormal:Dot(hitNormal) * hitNormal)

	local direction = ((hitPosition + reflectedNormal) - hitPosition)

	local attachment = Instance.new("Attachment")
	attachment.Parent = workspace.Terrain
	attachment.WorldPosition = hitPosition
	attachment.Name = "FXattach"

	local sparks = game.ReplicatedStorage.FX.Sparks:Clone()
	sparks.Parent = attachment
	sparks.Enabled = false
	sparks:Emit(20)

	local sound = game.ReplicatedStorage.FX.Ricochet:Clone()
	sound.Parent = attachment
	sound.PlaybackSpeed = math.random(90, 110)/100
	sound:Play()

	game.Debris:AddItem(attachment, 2)
	task.delay(2, function()
		if attachment and attachment.Parent ~= nil then
			attachment:Destroy()
		end
	end)

	if config.FiringMethod == "Projectile" then
		caster:Fire(hitPosition, direction, bulletSpeed/2, behavior)
		game.ReplicatedStorage.Remotes.Replication.ReplicateBullet:FireServer(hitPosition, direction, bulletSpeed, behavior, config.TracerTemplate, "Projectile")
	end
end

local function hit(hitPart, hitPosition, hitNormal)
	local enemyHumanoid = hitPart.Parent:FindFirstChild("Humanoid")

	if enemyHumanoid and 
		(
			enemyHumanoid:GetAttribute("Team") ~= humanoid:GetAttribute("Team") 
				or config.TeamKillingEnabled == true
				or enemyHumanoid:GetAttribute("Team") == nil
		) 

			and enemyHumanoid.Health > 0 then	

		local multipliers = config.DamageMultipliers
		local displayDamage = config.Damage

		if multipliers[hitPart.Name] ~= nil then
			displayDamage = displayDamage * multipliers[hitPart.Name]
		end

		tool.VerifyHit:FireServer(enemyHumanoid, hitPart)
		_G.IndicateDamage(displayDamage, false, config.HitSound, config.KillSound, config.DamageIndicationNumber, config.DamageIndicationHitmarker)
	end
end

local function activated()
	mouseDown = true
end

local function deactivated()
	mouseDown = false
end

local reloadSoundInstance = nil
local reloadFinishSoundInstance = nil

local function reload()
	if not reloading and ammo < magSize and toolEquipped then
		reloading = true

		if config.ReloadMethod == "EntireClip" then
			if config.ReloadSound and config.ReloadSound ~= "" then
				reloadSoundInstance = createSound(config.ReloadSound, config.ReloadSoundVolume)
				if reloadSoundInstance then
					reloadSoundInstance:Play()
					game.ReplicatedStorage.Remotes.Replication.ReplicateSound:FireServer(reloadSoundInstance.SoundId, config.ReloadSoundVolume, 1)
				end
			end

			if reloadAnimation then
				reloadAnimation:Play()
			end

			local reloadTime = config.ReloadSpeed or 3
			local startTime = tick()
			repeat
				task.wait()
				if not toolEquipped then
					reloading = false
					if reloadSoundInstance then reloadSoundInstance:Stop() end
					return
				end
			until tick() - startTime >= reloadTime

			ammo = magSize
			reloading = false

		elseif config.ReloadMethod == "Individually" then
			local toReload = magSize - ammo
			for i = 1, toReload do
				if not toolEquipped then
					reloading = false
					if reloadSoundInstance then reloadSoundInstance:Stop() end
					if reloadFinishSoundInstance then reloadFinishSoundInstance:Stop() end
					return
				end

				if reloadAnimation then
					reloadAnimation:Play()
				end

				if config.ReloadSound and config.ReloadSound ~= "" then
					reloadSoundInstance = createSound(config.ReloadSound, config.ReloadSoundVolume)
					if reloadSoundInstance then
						reloadSoundInstance:Play()
						game.ReplicatedStorage.Remotes.Replication.ReplicateSound:FireServer(reloadSoundInstance.SoundId, config.ReloadSoundVolume, 1)
						game.Debris:AddItem(reloadSoundInstance, reloadSoundInstance.TimeLength)
					end
				end

				task.wait(config.ReloadSpeed or 0.5)
			end

			if reloadFinishAnimation then
				reloadFinishAnimation:Play()
			end

			if config.ReloadFinishSound and config.ReloadFinishSound ~= "" then
				reloadFinishSoundInstance = createSound(config.ReloadFinishSound, config.ReloadFinishSoundVolume)
				if reloadFinishSoundInstance then
					reloadFinishSoundInstance:Play()
					game.ReplicatedStorage.Remotes.Replication.ReplicateSound:FireServer(reloadFinishSoundInstance.SoundId, config.ReloadFinishSoundVolume, 1)
				end
			end

			ammo = magSize
			reloading = false
		end

		refreshGui()
	end
end

local function fire()
	if performChecksForFiring() == nil then return end

	-- apply camera recoil
	cameraRecoil:shove(Vector3.new(config.VerticalRecoil, config.HorizontalRecoil, 0))

	local origin = firingPoint.WorldPosition
	local direction = (mouse.Hit.Position - origin).Unit

	for i = 1, config.Pellets do
		local spread = config.BulletSpread
		local directionalCF = CFrame.new(Vector3.new(), direction)
		local dir = (directionalCF *
			CFrame.fromOrientation(0,0,RNG:NextNumber(0,TAU)) *
			CFrame.fromOrientation(
				math.rad(RNG:NextNumber(-spread,spread)),
				math.rad(RNG:NextNumber(-spread,spread)),
				math.rad(RNG:NextNumber(-spread,spread))
			)
		).LookVector

		if config.FiringMethod == "Projectile" then
			local shotBehavior = fastCast.newBehavior()
			shotBehavior.MaxDistance = config.MaxDistance or 3000
			shotBehavior.CosmeticBulletTemplate = config.TracerTemplate
			shotBehavior.CosmeticBulletContainer = config.TracerContainer
			shotBehavior.RaycastParams = behavior.RaycastParams
			shotBehavior.Acceleration = behavior.Acceleration

			caster:Fire(origin, dir, bulletSpeed, shotBehavior)

			game.ReplicatedStorage.Remotes.Replication.ReplicateBullet:FireServer(
				origin,
				dir,
				bulletSpeed,
				shotBehavior,
				config.TracerTemplate,
				"Projectile",
				config.MaxDistance  -- pass MaxDistance to client
			)
		end
	end

	-- emit all particle emitters inside firingPoint (muzzle flash, smoke, sparks, etc)
	for _, obj in ipairs(firingPoint:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			local count = obj:GetAttribute("EmitCount") or 10
			obj:Emit(count)
		end
	end

	-- play fire sound
	local randomizedPitch = 1
	if config.FireSoundAdjustPitch then
		local base = config.FireSoundPitch * 100
		randomizedPitch = math.random(base-10, base+10)/100
	end

	if fireSound then
		local soundClone = createSound(config.FireSound, config.FireSoundVolume, randomizedPitch)
		soundClone.Parent = firingPoint
		soundClone:Play()
		game.Debris:AddItem(soundClone, soundClone.TimeLength)

		game.ReplicatedStorage.Remotes.Replication.ReplicateSound:FireServer(
			soundClone.SoundId,
			config.FireSoundVolume,
			randomizedPitch
		)
	end

	if fireAnimation then fireAnimation:Play() end

	ammo = ammo - 1
	refreshGui()
end

local replicatedStorage = game:GetService("ReplicatedStorage")
local fxFolder = replicatedStorage:WaitForChild("FX"):WaitForChild("Impact") 

-- spawn impact FX based on material/type
local function spawnImpactFX(hitPart, hitPosition, hitNormal)
	-- determine impact type using tags and material
	local impactType = "Hit"
	local tagsService = game:GetService("CollectionService")

	-- humanoid hits use "Hit"
	if hitPart and hitPart.Parent and hitPart.Parent:FindFirstChild("Humanoid") then
		impactType = "Hit"
	else
		-- deflection surfaces take priority
		if tagsService:HasTag(hitPart, "DeflectionSurface") or tagsService:HasTag(hitPart.Parent, "DeflectionSurface") then
			impactType = "Metal"
		else
			-- tag-based overrides from config.RichochetTags
			local tagFound = false
			for _, tag in ipairs(config.RichochetTags) do
				if tagsService:HasTag(hitPart, tag) or tagsService:HasTag(hitPart.Parent, tag) then
					impactType = "Metal"
					tagFound = true
					break
				end
			end

			-- material mapping fallback
			if not tagFound then
				local materialMap = {
					[Enum.Material.Wood] = "Wood",
					[Enum.Material.Grass] = "Ground",
					[Enum.Material.Ground] = "Ground",
					[Enum.Material.Sand] = "Sand",
					[Enum.Material.Concrete] = "Stone",
					[Enum.Material.Brick] = "Stone",
					[Enum.Material.Glass] = "Glass",
				}
				impactType = materialMap[hitPart.Material] or "Ground"
			end
		end
	end

	-- spawn local FX (same logic as before)
	local fxFolder = replicatedStorage:WaitForChild("FX"):WaitForChild("Impact")
	local materialFolder = fxFolder:FindFirstChild(impactType)
	if materialFolder then
		-- try use parts inside the folder as templates
		local parts = {}
		for _, v in pairs(materialFolder:GetChildren()) do
			if v:IsA("Part") then
				table.insert(parts, v)
			end
		end

		if #parts > 0 then
			local chosenPart = parts[math.random(1, #parts)]
			for _, v in pairs(chosenPart:GetChildren()) do
				if v:IsA("ParticleEmitter") then
					local attachment = Instance.new("Attachment")
					attachment.Parent = workspace.Terrain
					attachment.WorldCFrame = CFrame.lookAt(hitPosition, hitPosition - (hitPart.Position - hitPosition).Unit)
					local emitter = v:Clone()
					emitter.Parent = attachment
					emitter.Enabled = true
					emitter:Emit(v:GetAttribute("EmitCount") or 10)
					emitter.Enabled = false
					game.Debris:AddItem(attachment, 5)
				end
			end
		else
			-- fallback: clone emitters directly from materialFolder children if not Parts
			for _, template in ipairs(materialFolder:GetChildren()) do
				for _, desc in ipairs(template:GetDescendants()) do
					if desc:IsA("ParticleEmitter") then
						local attachment = Instance.new("Attachment")
						attachment.Parent = workspace.Terrain
						attachment.WorldCFrame = CFrame.lookAt(hitPosition, hitPosition - (hitPart.Position - hitPosition).Unit)
						local emitter = desc:Clone()
						emitter.Parent = attachment
						emitter.Enabled = true
						emitter:Emit(desc:GetAttribute("EmitCount") or 10)
						emitter.Enabled = false
						game.Debris:AddItem(attachment, 5)
					end
				end
			end
		end
	end

	-- replicate impact FX to other players and include the chosen impactType so they can pick correct FX
	game.ReplicatedStorage.Remotes.Replication.ReplicateFX:FireServer(
		"impact",
		hitPosition,
		CFrame.lookAt(hitPosition, hitPosition + hitNormal),
		hitPart,
		impactType
	)
end

local function rayHit(cast, result, segmentVelocity, bullet)
	local hitPart = result.Instance
	local hitPosition = result.Position
	local hitNormal = result.Normal

	local isDeflectionSurface = false
	local ricochetTags = config.RichochetTags

	for _, v in pairs(ricochetTags) do
		if tags:HasTag(hitPart, v) or tags:HasTag(hitPart.Parent, v) then
			isDeflectionSurface = true
			break
		end
	end

	-- determine if the hit is a humanoid
	local isHumanoidHit = hitPart.Parent:FindFirstChild("Humanoid") ~= nil

	-- spawn impact FX
	spawnImpactFX(hitPart, hitPosition, hitNormal)

	if isDeflectionSurface then
		-- ricochet for deflection surfaces
		ricochet(hitPosition, hitNormal, segmentVelocity.Unit)
	elseif not isHumanoidHit then
		-- only call hit() for non-humanoids
		hit(hitPart, hitPosition, hitNormal)
	else
		-- for humanoids, use "Hit" FX only, damage handled elsewhere
		hit(hitPart, hitPosition, hitNormal)
	end
end

local function lengthChanged(cast, lastPoint, rayDir, displacement, segmentVelocity, bullet)
	if bullet then
		local currentPoint = lastPoint + (rayDir * displacement)

		local start = lastPoint + (rayDir * displacement/2)
		local endPos = currentPoint

		bullet.CFrame = CFrame.lookAt(start, endPos)

		if config.DynamicTracerScaling then
			local distance = (currentPoint - lastPoint).Magnitude
			bullet.Size = Vector3.new(config.DynamicTracerScalingSize, config.DynamicTracerScalingSize, distance)
		end
	end
end

local function castTerminating(cast)
	if cast.RayInfo.CosmeticBulletObject then
		cast.RayInfo.CosmeticBulletObject:Destroy()
	end
end

local function keyPress(input)
	if input.KeyCode == Enum.KeyCode.R then
		reload()
	end
end

local function heartbeat()
	if mouseDown and not reloading and ammo > 0 then
		local now = tick()

		if now - lastFired > 60/config.Firerate then
			fire()
			lastFired = now
		end
	end
end

local function renderStepped(dt)
	if gui and not userInputService.TouchEnabled then
		if gui:FindFirstChild("Mouse") then
			gui.Mouse.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
		end
	end

	if toolEquipped then
		if config.PlayerFacesMouse3rdPerson and not userInputService.TouchEnabled then
			local pos = mouse.Hit.Position
			local lookToPosVector = Vector3.new(pos.X, root.Position.Y, pos.Z)

			root.CFrame = CFrame.lookAt(root.Position, lookToPosVector)
		end

		if config.VerticalRecoil > 0 or config.HorizontalRecoil > 0 then
			local recoilUpdated = cameraRecoil:update(dt)
			local x,y,z = recoilUpdated.X, recoilUpdated.Y, recoilUpdated.Z

			camera.CFrame = camera.CFrame * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
		end
	end
end

local function killEvent(damage)
	_G.IndicateDamage(damage, true, config.HitSound, config.KillSound, config.DamageIndicationNumber, config.DamageIndicationHitmarker)
end

local function mobileContextButtons(actionName, inputState, inputObject)
	if actionName == "Fire" then
		if inputState == Enum.UserInputState.Begin then
			activated()
		elseif inputState == Enum.UserInputState.End then
			deactivated()
		end
	elseif actionName == "Zoom" then
		if inputState == Enum.UserInputState.Begin then
			scopeIn()
		elseif inputState == Enum.UserInputState.End then
			scopeOut()
		end
	elseif actionName == "Reload" then
		reload()
	end
end

local function setUpMobileButtons()
	if userInputService.TouchEnabled then
		contextActionService:BindAction("Fire", mobileContextButtons, true)
		contextActionService:BindAction("Reload", mobileContextButtons, true)
		if config.ZoomEnabled then
			contextActionService:BindAction("Zoom", mobileContextButtons, true)
		end

		contextActionService:SetImage("Fire", 'rbxassetid://8961981049')
		contextActionService:SetPosition("Fire", UDim2.new(1,-70, 0, 10))
		contextActionService:GetButton("Fire").Size = UDim2.new(0,70,0,70)

		contextActionService:SetImage("Reload", 'rbxassetid://8908047394')
		contextActionService:SetPosition("Reload", UDim2.new(1,-110,0,-40))

		if config.ZoomEnabled then
			contextActionService:SetImage("Zoom", 'rbxassetid://8908047094')
			contextActionService:SetPosition("Zoom", UDim2.new(1,-70,0,-90))
		end
	end
end

local function destroyMobileButtons()
	contextActionService:UnbindAction("Fire")
	contextActionService:UnbindAction("Reload")
	contextActionService:UnbindAction("Zoom")
end

local function getGuiTemplate()
	-- do NOT index script.GUI directly
	local guiTemplate = script:FindFirstChild("GUI")

	if not guiTemplate then
		warn("toolclient: GUI missing inside local script")
		return nil
	end

	return guiTemplate
end

local function equipped()
	toolEquipped = true

	refreshCharacterReferences()

	setUpMobileButtons()

	-- play equip animation once
	if equipAnimation then
		equipAnimation:Play()
	end

	if idleAnimation then
		idleAnimation:Play(0)
	end

	userInputService.MouseIconEnabled = false

	-- safe gui clone
	local guiTemplate = getGuiTemplate()
	if guiTemplate then
		gui = guiTemplate:Clone()
		gui.Parent = player:WaitForChild("PlayerGui")

		if userInputService.TouchEnabled then
			gui.IgnoreGuiInset = true
		else
			gui.IgnoreGuiInset = false
		end

		refreshGui()
	else
		gui = nil
	end
end

local function unequipped()
	-- handles full cleanup and stops every animation/sound safely
	mouseDown = false
	toolEquipped = false

	destroyMobileButtons()

	-- stop reload animation + sounds
	if reloadAnimation and reloadAnimation.IsPlaying then
		reloadAnimation:Stop()
	end
	if reloadSoundInstance then
		reloadSoundInstance:Stop()
	end
	if reloadFinishSoundInstance then
		reloadFinishSoundInstance:Stop()
	end

	-- stop idle
	if idleAnimation then
		idleAnimation:Stop()
	end

	-- stop equip animation
	if equipAnimation and equipAnimation.IsPlaying then
		equipAnimation:Stop()
	end

	userInputService.MouseIconEnabled = true
	scopeOut()

	if gui then
		gui:Destroy()
		gui = nil
	end

	reloading = false
end

unequipped()
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

mouse.Button2Down:Connect(scopeIn)
mouse.Button2Up:Connect(scopeOut)

tool.VerifyHit.OnClientEvent:Connect(killEvent)

caster.LengthChanged:Connect(lengthChanged)
caster.CastTerminating:Connect(castTerminating)
caster.RayHit:Connect(rayHit)

userInputService.InputBegan:Connect(keyPress)

runService.RenderStepped:Connect(renderStepped)
runService.Heartbeat:Connect(heartbeat)
humanoid.Died:Connect(unequipped)
tool.Equipped:Connect(equipped)
tool.Unequipped:Connect(unequipped)

tool.Activated:Connect(activated)
tool.Deactivated:Connect(deactivated)

player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	root = newCharacter:WaitForChild("HumanoidRootPart")

	-- Reconnect humanoid.Died event for new character
	humanoid.Died:Connect(unequipped)

	refreshCharacterReferences()
end)

if player.Character then
	refreshCharacterReferences()
end

player.CharacterRemoving:Connect(function()
	unequipped()
end)

-- Reinitialize when new character is loaded
player.CharacterAppearanceLoaded:Connect(function()
	refreshCharacterReferences()
	refreshEnemiesAndTeammates()
end)

local guiTemplate = script:FindFirstChild("GUI")
if guiTemplate then
	guiTemplate.IgnoreGuiInset = userInputService.TouchEnabled
end
-- end of ToolClient
