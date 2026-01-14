-- ClientMain Modules: client-side tool handler adapted to centralized remotes.

local ClientMain = {}
ClientMain.__index = ClientMain

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local ModulesFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClientMain")
local ClientKeybindHandler = require(ModulesFolder:WaitForChild("ClientKeybindHandler"))
local ClientMobileHandler = require(ModulesFolder:WaitForChild("ClientMobileHandler"))

local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Replication")
local ReplicateSound = RemotesFolder:WaitForChild("ReplicateSound")
local ReplicateBullet = RemotesFolder:WaitForChild("ReplicateBullet")
local ReplicateImpactSound = RemotesFolder:WaitForChild("ReplicateImpactSound")
local VerifyHitRemote = RemotesFolder:WaitForChild("VerifyHit")

local Utils = require(ReplicatedStorage.Modules:WaitForChild("Utils"))
local Tracer = require(ReplicatedStorage.Modules.Client:WaitForChild("Tracer"))
local FastCast = require(ReplicatedStorage.Modules.Shared:WaitForChild("FastCastRedux"))

function ClientMain.new(tool, player)
	assert(tool and player, "tool and player required")
	local self = setmetatable({}, ClientMain)

	self.tool = tool
	self.player = player
	self.character = player.Character or player.CharacterAdded:Wait()
	self.humanoid = self.character:WaitForChild("Humanoid")
	self.root = self.character:WaitForChild("HumanoidRootPart")
	self.camera = workspace.CurrentCamera

	self.Utils = Utils
	self.Tracer = Tracer
	self.fastCast = Tracer.getCaster()

	-- safe require of Config (should exist)
	local ok, cfg = pcall(function() return require(tool:WaitForChild("Config")) end)
	self.config = ok and cfg or {}

	self.guiTemplate = ModulesFolder:FindFirstChild("GUI")

	self.firingPoint = tool:FindFirstChild("FiringPoint", true) or tool.Handle and tool.Handle:FindFirstChild("FiringPoint", true)
	if not self.firingPoint then
		local att = Instance.new("Attachment")
		att.Name = "FiringPoint"
		att.Parent = tool:FindFirstChildOfClass("BasePart") or tool
		self.firingPoint = att
	end

	-- animations & sounds helpers
	local function createAnim(id) if not id then return nil end return Utils.createAnimation(self.humanoid, id) end
	local function createSnd(id) if not id then return nil end return Utils.createSound(tool:FindFirstChild("Handle") or tool, id) end

	self.equipAnimation = createAnim(self.config.EquipAnimation)
	self.idleAnimation = createAnim(self.config.IdleAnimation)
	self.fireAnimation = createAnim(self.config.FireAnimation)
	self.reloadAnimation = createAnim(self.config.ReloadAnimation)
	self.reloadFinishAnimation = createAnim(self.config.ReloadFinishAnimation)

	self.fireSound = createSnd(self.config.FireSound)
	self.reloadSound = createSnd(self.config.ReloadSound)
	self.reloadFinishSound = createSnd(self.config.ReloadFinishSound)

	-- state
	self.gui = nil
	self.toolEquipped = false
	self.lastFired = 0
	self.mouseDown = false
	self.reloading = false
	self.magSize = self.config.MagSize or 0
	self.ammo = self.magSize
	self.teammates = {}
	self.enemies = {}
	self.activeCosmeticBullets = {}
	self.cameraRecoil = require(ReplicatedStorage.Modules:WaitForChild("spring")).create()

	self.mouse = player:GetMouse()
	self.RNG = Random.new()
	self.TAU = math.pi * 2

	self._connections = {}
	self._fastCastConns = {}

	self.keybindHandler = ClientKeybindHandler.new(self)
	self.mobileHandler = ClientMobileHandler.new(self)

	self.bulletSpeed = self.config.ProjectileSpeed or 3000
	self.behaviorTemplate = Tracer.newBehavior(
		self.config.TracerTemplate,
		self.config.TracerContainer,
		self.config.ProjectileAcceleration or Vector3.new(0,0,0),
		self:_makeBulletParams(),
		self.config.ProjectileMaxDistance or 3000
	)

	return self
end

function ClientMain:_makeBulletParams()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = {}
	table.insert(ignoreList, self.character)
	if self.config.TracerContainer and typeof(self.config.TracerContainer) == "Instance" then
		table.insert(ignoreList, self.config.TracerContainer)
	end
	if self.config.IgnoreTeammates == true then
		for _, tm in ipairs(self.teammates) do
			if tm and tm:IsA("Model") then table.insert(ignoreList, tm) end
		end
	end
	params.FilterDescendantsInstances = ignoreList
	return params
end

function ClientMain:refreshEnemiesAndTeammates()
	self.teammates = {}
	self.enemies = {}
	for _,v in pairs(workspace:GetChildren()) do
		if v:IsA("Model") and v:FindFirstChild("Humanoid") then
			local team = v.Humanoid:GetAttribute("Team")
			if team == self.humanoid:GetAttribute("Team") then
				table.insert(self.teammates, v)
			else
				table.insert(self.enemies, v)
			end
		end
	end
end

function ClientMain:refreshGui()
	if self.gui then
		local charges = self.gui:FindFirstChild("ChargesLeft", true)
		if charges then
			charges.Text = tostring(self.ammo)
			charges.BackgroundColor3 = (self.ammo <= 0) and Color3.fromRGB(255,0,0) or Color3.fromRGB(0,0,0)
		end
	end
end

function ClientMain:isInFirstPerson()
	local head = self.character:FindFirstChild("Head")
	if not head then return false end
	local dist = (self.camera.CFrame.Position - head.Position).Magnitude
	return dist < 1
end

function ClientMain:scopeIn()
	if self.gui and self:isInFirstPerson() and self.toolEquipped and self.config.ZoomEnabled then
		UserInputService.MouseDeltaSensitivity = 0.3
		self.camera.FieldOfView = 30
		if self.config.AimDownSights then
			self.tool:SetAttribute("Aiming", true)
		end
	end
end

function ClientMain:scopeOut()
	if self.gui and self.config.ZoomEnabled then
		UserInputService.MouseDeltaSensitivity = 1
		self.camera.FieldOfView = 70
		if self.config.AimDownSights then
			self.tool:SetAttribute("Aiming", false)
		end
	end
end

function ClientMain:playSuppressionSound()
	if not self.config.SuppressionEnabled then return end
	local cam = workspace.CurrentCamera
	if not cam then return end

	local fx = ReplicatedStorage:FindFirstChild("FX")
	local suppressionFolder = fx and (fx:FindFirstChild("Suppression") or fx:FindFirstChild("Suppresion"))
	if not suppressionFolder then return end

	local sounds = {}
	for _,child in ipairs(suppressionFolder:GetDescendants()) do
		if child:IsA("Sound") then table.insert(sounds, child) end
	end
	if #sounds == 0 then return end

	local chosen = sounds[self.RNG:NextInteger(1, #sounds)]:Clone()
	chosen.PlaybackSpeed = math.random(95,105)/100
	chosen.RollOffMode = Enum.RollOffMode.Linear
	chosen.Parent = cam
	chosen:Play()
	Debris:AddItem(chosen, chosen.TimeLength > 0 and chosen.TimeLength or 2)
end

function ClientMain:playImpactSound(impactType, hitPosition, hitNormal)
	local fx = ReplicatedStorage:FindFirstChild("FX")
	local impactFolder = fx and (fx:FindFirstChild(impactType) or fx:FindFirstChild("Impact") or fx:FindFirstChild("FleshImpact"))
	if not impactFolder then return end

	local impactSounds = {}
	for _, child in ipairs(impactFolder:GetChildren()) do
		if child:IsA("Sound") then table.insert(impactSounds, child) end
	end
	if #impactSounds == 0 then return end

	local chosen = impactSounds[self.RNG:NextInteger(1,#impactSounds)]:Clone()
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = hitPosition
	attachment.WorldCFrame = CFrame.new(hitPosition, hitPosition + (hitNormal or Vector3.new(0,1,0)))
	attachment.Parent = workspace.Terrain

	chosen.Parent = attachment
	chosen.PlaybackSpeed = math.random(95,105)/100
	chosen:Play()
	Debris:AddItem(attachment, chosen.TimeLength > 0 and chosen.TimeLength + 0.5 or 2.5)

	pcall(function()
		ReplicateImpactSound:FireServer(impactType, hitPosition, hitNormal)
	end)
end

function ClientMain:ricochet(hitPosition, hitNormal, incomingVelocity)
	if not incomingVelocity or incomingVelocity.Magnitude == 0 then return end
	local inDir = incomingVelocity.Unit
	local reflectDir = (inDir - (2 * inDir:Dot(hitNormal) * hitNormal)).Unit

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = hitPosition
	attachment.WorldCFrame = CFrame.new(hitPosition, hitPosition + hitNormal)
	attachment.Parent = workspace.Terrain

	local fx = ReplicatedStorage:FindFirstChild("FX")
	if fx and fx:FindFirstChild("Sparks") then
		local sparks = fx.Sparks:Clone()
		sparks.Parent = attachment
		if sparks:IsA("ParticleEmitter") then sparks:Emit() end
	end

	local ricFolder = fx and fx:FindFirstChild("Ricochet")
	local ricSounds = {}
	if ricFolder then
		for _,c in ipairs(ricFolder:GetChildren()) do if c:IsA("Sound") then table.insert(ricSounds, c) end end
	end

	if #ricSounds > 0 then
		local chosen = ricSounds[self.RNG:NextInteger(1,#ricSounds)]:Clone()
		chosen.Parent = attachment
		chosen.PlaybackSpeed = math.random(90,110)/100
		chosen:Play()
		Debris:AddItem(chosen, chosen.TimeLength > 0 and chosen.TimeLength or 2)

		pcall(function() 
			ReplicateImpactSound:FireServer("Ricochet", hitPosition, hitNormal) 
		end)
	end

	Debris:AddItem(attachment, 2)

	local newOrigin = hitPosition + reflectDir * 0.25
	local params = self:_makeBulletParams()
	if params.FilterDescendantsInstances then table.insert(params.FilterDescendantsInstances, attachment) end

	local ricBehavior = Tracer.newBehavior(
		self.config.TracerTemplate,
		self.config.TracerContainer,
		self.config.ProjectileAcceleration or Vector3.new(0,0,0),
		params,
		self.config.ProjectileMaxDistance or 3000
	)

	local ricCast = self.fastCast:Fire(newOrigin, reflectDir, self.bulletSpeed * (self.config.RicochetSpeedMultiplier or 0.6), ricBehavior)
	if ricCast then
		ricCast.UserData = {
			PiercedHumanoids = 0,
			HitHumanoids = {},
			Owner = self.character,
			IsRicochet = true
		}
	end

	pcall(function()
		ReplicateBullet:FireServer(newOrigin, reflectDir, self.bulletSpeed * (self.config.RicochetSpeedMultiplier or 0.6), nil, self.config.TracerTemplate)
	end)
end

function ClientMain:rayHit(cast, result, segmentVelocity, cosmeticBullet)
	if not self.toolEquipped then return end
	if not cast or not result then return end
	if cast.UserData and cast.UserData.VisualOnly then return end

	local hitPart = result.Instance
	if not hitPart then return end

	local model = hitPart:FindFirstAncestorOfClass("Model")
	local hitHumanoid = model and model:FindFirstChildOfClass("Humanoid")

	-- Non-humanoid surface
	if not hitHumanoid then
		local canRicochet = false
		for _, tag in ipairs(self.config.RichochetTags or {}) do
			if CollectionService:HasTag(hitPart, tag) then canRicochet = true break end
		end

		if canRicochet then
			self:ricochet(result.Position, result.Normal, segmentVelocity)

		else
			self:playImpactSound("Impact", result.Position, result.Normal)
		end
		return
	end

	-- team check
	local myTeam = self.humanoid:GetAttribute("Team")
	local hitTeam = hitHumanoid:GetAttribute("Team")
	if myTeam and hitTeam and myTeam == hitTeam and not self.config.TeamKillingEnabled then
		self:playImpactSound("Impact", result.Position, result.Normal)
		return
	end

	-- duplicate guard
	cast.UserData.HitHumanoids = cast.UserData.HitHumanoids or {}
	if cast.UserData.HitHumanoids[hitHumanoid] then return end
	cast.UserData.HitHumanoids[hitHumanoid] = true

	-- flesh impact + server verify
	self:playImpactSound("FleshImpact", result.Position, result.Normal)

	pcall(function()
		VerifyHitRemote:FireServer(self.tool, hitHumanoid, hitPart, result.Position)
	end)

	-- piercing behavior
	if not self.config.HumanoidPierceEnabled then return end

	cast.UserData.PiercedHumanoids = (cast.UserData.PiercedHumanoids or 0) + 1
	local limit = self.config.HumanoidPierceLimit or 0
	if cast.UserData.PiercedHumanoids >= limit then
		pcall(function()
			self.fastCast:Terminate(cast)
		end)
		return
	end

	local newOrigin = result.Position + segmentVelocity.Unit * 0.2
	local newDir = segmentVelocity.Unit
	local params = self:_makeBulletParams()
	table.insert(params.FilterDescendantsInstances, model)

	local newBehavior = Tracer.newBehavior(
		self.config.TracerTemplate,
		self.config.TracerContainer,
		self.config.ProjectileAcceleration or Vector3.new(0,0,0),
		params,
		self.config.ProjectileMaxDistance or 3000
	)

	local newCast = self.fastCast:Fire(newOrigin, newDir, self.bulletSpeed, newBehavior)
	if newCast then
		newCast.UserData = {
			PiercedHumanoids = cast.UserData.PiercedHumanoids,
			HitHumanoids = cast.UserData.HitHumanoids,
			Owner = self.character
		}
	end
end

function ClientMain:lengthChanged(cast, lastPoint, rayDir, displacement, segmentVelocity, cosmeticBullet)
	if cosmeticBullet then
		local pos = lastPoint + rayDir * displacement
		cosmeticBullet.CFrame = CFrame.lookAt(pos - rayDir, pos)
		self.activeCosmeticBullets[cosmeticBullet] = true
	end

	if not self.config.SuppressionEnabled then return end
	if not cast or not cast.UserData or cast.UserData.Suppressed then return end

	local cam = workspace.CurrentCamera
	if not cam then return end

	local bulletPos = lastPoint + rayDir * displacement
	if (bulletPos - cam.CFrame.Position).Magnitude > (self.config.SuppressionRadius or 12) then return end
	if cast.UserData.Owner == self.character then return end

	cast.UserData.Suppressed = true
	self:playSuppressionSound()
end

function ClientMain:castTerminating(cast)
	if cast and cast.RayInfo and cast.RayInfo.CosmeticBulletObject then
		local bullet = cast.RayInfo.CosmeticBulletObject
		self.activeCosmeticBullets[bullet] = nil
		if bullet and bullet.Parent then pcall(function() bullet:Destroy() end) end
	end
end

function ClientMain:cleanupAllCosmeticBullets()
	for bullet,_ in pairs(self.activeCosmeticBullets) do
		if bullet and typeof(bullet) == "Instance" and bullet.Parent then
			pcall(function() bullet:Destroy() end)
		end
	end
	self.activeCosmeticBullets = {}
end

function ClientMain:performChecksForFiring()
	if not self.humanoid or self.humanoid.Health <= 0 then return false end
	if self.ammo <= 0 or self.reloading then return false end
	return true
end

function ClientMain:fire()
	if not self:performChecksForFiring() then return end

	self.cameraRecoil:shove(Vector3.new(self.config.VerticalRecoil or 0, self.config.HorizontalRecoil or 0, 0))

	local origin = self.firingPoint.WorldPosition
	local direction = (self.mouse.Hit.Position - origin)
	if UserInputService.TouchEnabled then
		local vp = self.camera.ViewportSize / 2
		direction = self.camera:ViewportPointToRay(vp.X, vp.Y).Direction
	end

	for i = 1, (self.config.Pellets or 1) do
		local spread = self.config.BulletSpread or 0
		local cf = CFrame.new(Vector3.new(0,0,0), direction)
		local dir = (cf * CFrame.fromOrientation(0,0,self.RNG:NextNumber(0,self.TAU)) * CFrame.fromOrientation(math.rad(self.RNG:NextNumber(-spread,spread)), math.rad(self.RNG:NextNumber(-spread,spread)), 0)).LookVector

		local cast = self.fastCast:Fire(origin, dir, self.bulletSpeed, self.behaviorTemplate)
		if cast then
			cast.UserData = {
				PiercedHumanoids = 0,
				HitHumanoids = {},
				Owner = self.character
			}
		end

		pcall(function()
			ReplicateBullet:FireServer(origin, dir, self.bulletSpeed, nil, self.config.TracerTemplate)
		end)
	end

	if self.fireSound then
		local snd = self.fireSound:Clone()
		snd.Parent = self.firingPoint
		snd:Play()
		pcall(function()
			ReplicateSound:FireServer(snd.SoundId, snd.PlaybackSpeed)
		end)
		Debris:AddItem(snd, snd.TimeLength)
	end

	if self.fireAnimation then 
		pcall(function() self.fireAnimation:Play() end)
	end

	self.ammo = math.max(0, self.ammo - 1)
	self:refreshGui()
end

function ClientMain:reload()
	if self.reloading then return end
	if not self.toolEquipped then return end
	if self.ammo >= self.magSize then return end

	self.reloading = true

	if self.config.ReloadMethod == "EntireClip" then
		if self.reloadAnimation then pcall(function() self.reloadAnimation:Play() end) end
		if self.reloadSound then
			local snd = self.reloadSound:Clone()
			snd.Parent = self.firingPoint
			snd:Play()
			pcall(function() ReplicateSound:FireServer(snd.SoundId, snd.PlaybackSpeed) end)
			Debris:AddItem(snd, snd.TimeLength)
		end

		task.wait(self.config.ReloadSpeed or 3)

		if not self.toolEquipped then
			self.reloading = false
			return
		end

		self.ammo = self.magSize
		self.reloading = false
		self:refreshGui()
		return
	end

	-- INDIVIDUAL
	if self.config.ReloadMethod == "Individually" then
		while self.ammo < self.magSize do
			if not self.toolEquipped or self.humanoid.Health <= 0 then
				self.reloading = false
				return
			end

			if self.reloadAnimation then
				pcall(function()
					self.reloadAnimation:Stop()
					self.reloadAnimation:Play()
				end)
			end

			if self.reloadSound then
				local snd = self.reloadSound:Clone()
				snd.Parent = self.firingPoint
				snd:Play()
				pcall(function() ReplicateSound:FireServer(snd.SoundId, snd.PlaybackSpeed) end)
				Debris:AddItem(snd, snd.TimeLength)
			end

			task.wait(self.config.ReloadSpeed or 0.4)

			if not self.toolEquipped then
				self.reloading = false
				return
			end

			self.ammo += 1
			self:refreshGui()
		end

		if self.reloadFinishAnimation then pcall(function() self.reloadFinishAnimation:Play() end) end
		if self.reloadFinishSound then
			local snd = self.reloadFinishSound:Clone()
			snd.Parent = self.firingPoint
			snd:Play()
			pcall(function() ReplicateSound:FireServer(snd.SoundId, snd.PlaybackSpeed) end)
			Debris:AddItem(snd, snd.TimeLength)
		end

		self.reloading = false
	end
end

function ClientMain:activated() self.mouseDown = true end
function ClientMain:deactivated() self.mouseDown = false end

function ClientMain:renderStepped(dt)
	if self.gui and not UserInputService.TouchEnabled then
		local gm = self.gui:FindFirstChild("Mouse")
		if gm then pcall(function() gm.Position = UDim2.new(0, self.mouse.X, 0, self.mouse.Y) end) end
	end

	if self.toolEquipped then
		if self.config.PlayerFacesMouse3rdPerson and not UserInputService.TouchEnabled then
			local pos = self.mouse.Hit.Position
			local lookToPosVector = Vector3.new(pos.X, self.root.Position.Y, pos.Z)
			self.root.CFrame = CFrame.lookAt(self.root.Position, lookToPosVector)
		end

		if (self.config.VerticalRecoil and self.config.VerticalRecoil > 0) or (self.config.HorizontalRecoil and self.config.HorizontalRecoil > 0) then
			local recoilUpdated = self.cameraRecoil:update(dt)
			local x,y,z = recoilUpdated.X, recoilUpdated.Y, recoilUpdated.Z
			self.camera.CFrame = self.camera.CFrame * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
		end
	end
end

function ClientMain:heartbeat()
	if self.mouseDown and not self.reloading and self.ammo > 0 then
		local now = tick()
		if now - self.lastFired > 60/(self.config.Firerate or 600) then
			self:fire()
			self.lastFired = now
		end
	elseif self.ammo <= 0 and self.config.AutoReloadOnEmpty then
		self:reload()
	end
end

function ClientMain:killEvent(damage)
	-- reserved for VerifyHit client event (kill feedback)
end

-- Remote handlers
function ClientMain:_onReplicateSound(player, soundId, playbackSpeed)
	local character = player and player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChildWhichIsA("BasePart") or workspace
	local sound = Utils.createSound(root, soundId, nil, playbackSpeed)
	Utils.waitForLoaded(sound)
	sound:Play()
	Debris:AddItem(sound, sound.TimeLength)
end

function ClientMain:_onReplicateBullet(ownerPlayer, origin, direction, speed, newBehavior, tracer)
	if ownerPlayer == self.player then return end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	if ownerPlayer and ownerPlayer.Character then 
		table.insert(ignore, ownerPlayer.Character)
	end
	if self.config.TracerContainer then
		table.insert(ignore, self.config.TracerContainer) 
	end
	params.FilterDescendantsInstances = ignore

	local visualBehavior = Tracer.newBehavior(self.config.TracerTemplate, self.config.TracerContainer, self.config.ProjectileAcceleration or Vector3.new(0,0,0), params, self.config.ProjectileMaxDistance or 3000)
	local cast = self.fastCast:Fire(origin, direction, speed, visualBehavior)
	if cast then
		cast.UserData = {
			VisualOnly = true,
			Owner = ownerPlayer and ownerPlayer.Character
		}
	end
end

function ClientMain:_onReplicateImpactSound(impactType, hitPosition, hitNormal)
	local cam = workspace.CurrentCamera
	if cam and (hitPosition - cam.CFrame.Position).Magnitude > 200 then return end

	local fx = ReplicatedStorage:FindFirstChild("FX")
	local impactFolder = fx and fx:FindFirstChild(impactType)
	if not impactFolder and impactType == "FleshImpact" then
		impactFolder = fx and fx:FindFirstChild("Impact")
	end
	if not impactFolder then return end

	local impactSounds = {}
	for _, child in ipairs(impactFolder:GetChildren()) do
		if child:IsA("Sound") then table.insert(impactSounds, child) end
	end
	if #impactSounds == 0 then return end

	local chosen = impactSounds[self.RNG:NextInteger(1,#impactSounds)]
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = hitPosition
	attachment.WorldCFrame = CFrame.new(hitPosition, hitPosition + (hitNormal or Vector3.new(0,1,0)))
	attachment.Parent = workspace.Terrain

	local sound = chosen:Clone()
	sound.Parent = attachment
	sound.PlaybackSpeed = math.random(95,105)/100
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound:Play()
	Debris:AddItem(attachment, sound.TimeLength > 0 and sound.TimeLength + 0.5 or 2.5)
end

function ClientMain:rebindAnimations()
	local function createAnim(id)
		if not id then return nil end
		return Utils.createAnimation(self.humanoid, id)
	end

	self.equipAnimation = createAnim(self.config.EquipAnimation)
	self.idleAnimation = createAnim(self.config.IdleAnimation)
	self.fireAnimation = createAnim(self.config.FireAnimation)
	self.reloadAnimation = createAnim(self.config.ReloadAnimation)
	self.reloadFinishAnimation = createAnim(self.config.ReloadFinishAnimation)
end

function ClientMain:connectAll()
	-- FastCast events
	table.insert(self._fastCastConns, self.fastCast.LengthChanged:Connect(function(...) self:lengthChanged(...) end))
	table.insert(self._fastCastConns, self.fastCast.CastTerminating:Connect(function(...) self:castTerminating(...) end))
	table.insert(self._fastCastConns, self.fastCast.RayHit:Connect(function(...) self:rayHit(...) end))

	-- Remotes (centralized)
	table.insert(self._connections, ReplicateSound.OnClientEvent:Connect(function(...) self:_onReplicateSound(...) end))
	table.insert(self._connections, ReplicateBullet.OnClientEvent:Connect(function(...) self:_onReplicateBullet(...) end))
	table.insert(self._connections, ReplicateImpactSound.OnClientEvent:Connect(function(...) self:_onReplicateImpactSound(...) end))

	-- VerifyHit outbound from server
	table.insert(self._connections, VerifyHitRemote.OnClientEvent:Connect(function(...)
		local args = {...}
		local toolArg = args[1]
		if toolArg ~= self.tool then return end
		local damage = args[2]
		self:killEvent(damage)
	end))

	-- Tool events
	table.insert(self._connections, self.tool.Activated:Connect(function() self:activated() end))
	table.insert(self._connections, self.tool.Deactivated:Connect(function() self:deactivated() end))
	table.insert(self._connections, self.tool.Equipped:Connect(function() self:equipped() end))
	table.insert(self._connections, self.tool.Unequipped:Connect(function() self:unequipped() end))

	-- core loops & respawn
	table.insert(self._connections, RunService.RenderStepped:Connect(function(dt) self:renderStepped(dt) end))
	table.insert(self._connections, RunService.Heartbeat:Connect(function() self:heartbeat() end))
	table.insert(self._connections, self.player.CharacterAdded:Connect(function(ch) self:handleRespawn(ch) end))

	self.keybindHandler:bindActions()
end

function ClientMain:disconnectAll()
	-- fastCast conns
	for _,c in ipairs(self._fastCastConns) do
		if c then pcall(function() c:Disconnect() end) end
	end
	self._fastCastConns = {}

	-- normal conns
	for _,c in ipairs(self._connections) do
		if c then pcall(function() c:Disconnect() end) end
	end
	self._connections = {}

	-- input handlers
	if self.keybindHandler then self.keybindHandler:unbindActions() end
	if self.mobileHandler then self.mobileHandler:unbindActions() end
end

function ClientMain:equipped()
	self.toolEquipped = true
	if self.mobileHandler then self.mobileHandler:unbindActions() end

	if self.gui then pcall(function() self.gui:Destroy() end) end
	self.gui = nil

	if UserInputService.TouchEnabled and self.mobileHandler then
		self.mobileHandler:bindActions()
	end

	if self.equipAnimation then pcall(function() self.equipAnimation:Play() end) end
	if self.idleAnimation then pcall(function() self.idleAnimation:Play() end) end

	self.gui = self.guiTemplate and self.guiTemplate:Clone()
	if self.gui then
		self.gui.Parent = self.player:WaitForChild("PlayerGui")
		self.gui.IgnoreGuiInset = UserInputService.TouchEnabled
	end
	self:refreshGui()

	UserInputService.MouseIconEnabled = false
end

function ClientMain:unequipped()
	self.mouseDown = false
	self.toolEquipped = false

	if self.mobileHandler then self.mobileHandler:unbindActions() end
	if self.idleAnimation then pcall(function() self.idleAnimation:Stop() end) end
	UserInputService.MouseIconEnabled = true
	self:scopeOut()

	self:cleanupAllCosmeticBullets()
	if self.fastCast and self.fastCast.TerminateAll then pcall(function() self.fastCast:TerminateAll() end) end

	for _,anim in ipairs({
		self.equipAnimation,
		self.idleAnimation,
		self.fireAnimation,
		self.reloadAnimation,
		self.reloadFinishAnimation
		}) do
		if anim then pcall(function() anim:Stop() end) end
	end

	if self.gui then pcall(function() self.gui:Destroy() end) end
	self.gui = nil
end

function ClientMain:handleRespawn(newCharacter)
	wait(0.1)
	self:unequipped()
	self:cleanupAllCosmeticBullets()

	if self.fastCast and self.fastCast.TerminateAll then pcall(function() self.fastCast:TerminateAll() end) end

	self.behaviorTemplate.RaycastParams = self:_makeBulletParams()

	local ok = pcall(function()
		self.character = newCharacter
		self.humanoid = self.character:WaitForChild("Humanoid", 2)
		self.root = self.character:WaitForChild("HumanoidRootPart", 2)
	end)

	if not ok then
		wait(0.5)
		if newCharacter then
			self.character = newCharacter
			self.humanoid = self.character:WaitForChild("Humanoid")
			self.root = self.character:WaitForChild("HumanoidRootPart")
		end
	end

	if self._humanoidDiedConn then pcall(function() self._humanoidDiedConn:Disconnect() end) end

	if self.humanoid then
		self._humanoidDiedConn = self.humanoid.Died:Connect(function()
			self:unequipped()
		end)
	end

	self:rebindAnimations()
	self:refreshEnemiesAndTeammates()

	self.mouseDown = false
	self.reloading = false
	self.lastFired = 0

	if self.toolEquipped then
		wait(0.5)
		if self.tool and self.tool.Parent == self.character then
			self:equipped()
		end
	end
end

function ClientMain.init(tool, player)
	local instance = ClientMain.new(tool, player)
	instance:refreshEnemiesAndTeammates()
	instance:connectAll()
	instance:unequipped()
	return instance
end

return ClientMain
