-- inside StarterPlayerScripts
-- ClientWeaponEF (local)
local replicateSound = game.ReplicatedStorage.Remotes.Replication.ReplicateSound
local replicateFX = game.ReplicatedStorage.Remotes.Replication.ReplicateFX
local replicatedStorage = game.ReplicatedStorage
local players = game:GetService("Players")
local debris = game:GetService("Debris")


local function playSound(originOrSoundId, maybeSoundId, maybeVolume, maybePlayback)
	-- normalize parameters: allow server to send either (originCharacter, soundId, volume, playbackSpeed)
	-- or legacy (soundId, volume, playbackSpeed) if needed
	local originCharacter, soundId, volume, playbackSpeed

	if typeof(originOrSoundId) == "Instance" and originOrSoundId:IsA("Model") then
		originCharacter = originOrSoundId
		soundId = maybeSoundId
		volume = maybeVolume
		playbackSpeed = maybePlayback
	else
		originCharacter = nil
		soundId = originOrSoundId
		volume = maybeSoundId
		playbackSpeed = maybeVolume
	end

	if not soundId or soundId == "" then return end

	-- try find humanoid root part to parent the sound so it panners correctly
	local parentTarget = nil
	if originCharacter and originCharacter.Parent ~= nil then
		parentTarget = originCharacter:FindFirstChild("HumanoidRootPart")
	end
	-- fallback to workspace so sound can still be heard by everyone
	if not parentTarget then
		parentTarget = workspace
	end

	local sound = Instance.new("Sound")
	sound.Parent = parentTarget
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 300

	-- safely wait for load then play and auto-clean
	local ok, err = pcall(function()
		repeat task.wait(0.02) until sound.IsLoaded
	end)
	-- even if IsLoaded polling fails, attempt to play anyway
	sound:Play()
	debris:AddItem(sound, sound.TimeLength or 5)
end

local replicateBullet = game.ReplicatedStorage.Remotes.Replication.ReplicateBullet
local fastCast = require(game.ReplicatedStorage.Modules.FastCastRedux)
local caster = fastCast.new()

local bulletParams = RaycastParams.new()
bulletParams.FilterDescendantsInstances = {workspace.Tracers}
bulletParams.FilterType = Enum.RaycastFilterType.Exclude
--local behavior = caster.newBehavior()

local function replicate(origin, direction, bulletSpeed, newBehavior, tracer, playerReplicated, ignoreList, firingMethod, maxDistance)
	if firingMethod ~= "Projectile" then return end

	local localBehavior = fastCast.newBehavior()
	localBehavior.MaxDistance = maxDistance or 3000  -- use value sent by server
	localBehavior.CosmeticBulletTemplate = tracer
	localBehavior.CosmeticBulletContainer = workspace:FindFirstChild("Tracers") or workspace

	local behaviorParams = RaycastParams.new()
	behaviorParams.FilterDescendantsInstances = ignoreList or {}
	behaviorParams.FilterType = Enum.RaycastFilterType.Exclude
	localBehavior.RaycastParams = behaviorParams
	localBehavior.Acceleration = (newBehavior and newBehavior.Acceleration) or Vector3.zero

	caster:Fire(origin, direction.Unit, bulletSpeed, localBehavior)
end

local function lengthChanged(cast, lastPoint, rayDir, displacement, segmentVelocity, bullet)
	if bullet then
		local currentPoint = lastPoint + (rayDir * displacement/2)
		bullet.CFrame = CFrame.lookAt(currentPoint, lastPoint)
	end
end

local function castTerminating(cast)
	local bullet = cast.RayInfo.CosmeticBulletObject
	if bullet then
		bullet:Destroy() 
	end
end

replicateFX.OnClientEvent:Connect(function(fxType, position, cframe, targetInstance, impactType)
	if fxType ~= "impact" then return end

	local impactRoot = replicatedStorage:FindFirstChild("FX") and replicatedStorage.FX:FindFirstChild("Impact")
	if not impactRoot then return end

	local chosenType = impactType or "Hit"
	local materialFolder = impactRoot:FindFirstChild(chosenType) or impactRoot:FindFirstChild("Hit")
	if not materialFolder then return end

	local function spawnEmitter(emitterTemplate)
		local attach = Instance.new("Attachment")
		attach.Parent = workspace.Terrain
		attach.WorldCFrame = cframe

		local emitter = emitterTemplate:Clone()
		emitter.Parent = attach
		emitter.Enabled = true
		emitter:Emit(emitterTemplate:GetAttribute("EmitCount") or 10)
		emitter.Enabled = false

		debris:AddItem(attach, 5)
	end

	local parts = {}
	for _, v in ipairs(materialFolder:GetChildren()) do
		if v:IsA("BasePart") then table.insert(parts, v) end
	end

	if #parts > 0 then
		local chosenPart = parts[math.random(1,#parts)]
		for _, v in ipairs(chosenPart:GetChildren()) do
			if v:IsA("ParticleEmitter") then spawnEmitter(v) end
		end
	else
		for _, template in ipairs(materialFolder:GetChildren()) do
			for _, desc in ipairs(template:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then spawnEmitter(desc) end
			end
		end
	end
end)


replicateBullet.OnClientEvent:Connect(replicate)
caster.LengthChanged:Connect(lengthChanged)
caster.CastTerminating:Connect(castTerminating)
replicateSound.OnClientEvent:Connect(playSound)