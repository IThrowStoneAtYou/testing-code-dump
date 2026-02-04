-- inside StarterPlayerScripts
-- ClientWeaponEF (local)
local replicateSound = game.ReplicatedStorage.Remotes.Replication.ReplicateSound

local function playSound(player, soundId, volume, playbackSpeed)
	local character = player.Character
	if not character then return end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local sound = Instance.new("Sound")
	sound.Parent = root
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.PlaybackSpeed = playbackSpeed or 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 300

	repeat task.wait(0.02) until sound.IsLoaded
	sound:Play()
	game.Debris:AddItem(sound, sound.TimeLength)
end

local replicateBullet = game.ReplicatedStorage.Remotes.Replication.ReplicateBullet
local fastCast = require(game.ReplicatedStorage.Modules.FastCastRedux)
local caster = fastCast.new()

local bulletParams = RaycastParams.new()
bulletParams.FilterDescendantsInstances = {workspace.Tracers}
bulletParams.FilterType = Enum.RaycastFilterType.Exclude

local camera = workspace.CurrentCamera

local behavior = caster.newBehavior()

local function replicate(origin, direction, bulletSpeed, newBehavior, tracer, playerReplicated, ignoreList, firingMethod)
	behavior.CosmeticBulletTemplate = tracer
	behavior.CosmeticBulletContainer = workspace:FindFirstChild("Tracers") or workspace
	bulletParams.FilterDescendantsInstances = ignoreList or {}
	behavior.RaycastParams = bulletParams
	behavior.MaxDistance = 10000
	behavior.Acceleration = newBehavior.Acceleration

	if firingMethod == "Projectile" then
		caster:Fire(origin, direction, bulletSpeed, behavior)
	end
end

local function lengthChanged(cast, lastPoint, rayDir, displacement, segmentVelocity, bullet)
	if bullet then
		local currentPoint = lastPoint + (rayDir * displacement/2)
		bullet.CFrame = CFrame.lookAt(currentPoint, lastPoint)
	end
end
local function castTerminating(cast)
	local bullet = cast.RayInfo.CosmeticBulletObject

	bullet:Destroy()
end

replicateBullet.OnClientEvent:Connect(replicate)
caster.LengthChanged:Connect(lengthChanged)
caster.CastTerminating:Connect(castTerminating)
replicateSound.OnClientEvent:Connect(playSound)