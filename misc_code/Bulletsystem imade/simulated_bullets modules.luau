-- simulated_bullets modules (OOP)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local bulletsModule = {}
bulletsModule.activeBullets = {}

local debugFolder = Workspace:FindFirstChild("bullet_debug_folder")
if not debugFolder then
	debugFolder = Instance.new("Folder")
	debugFolder.Name = "bullet_debug_folder"
	debugFolder.Parent = Workspace
end

local defaultSettings = {
	speed = 100,
	gravity = Vector3.new(0,-196.2,0),
	lifetime = 5,
	maxDistance = 500,
	expirationMode = "time",
	debug = false,
	debugColor = Color3.new(1,0,0),
	debugDuration = 0.1,
	raycastParams = nil,
	pierce = 0,
	ricochet = 0,
	onHit = nil,
	onExpire = nil,
	onPierce = nil,
	onRicochet = nil,
}

-- reusable raycast params
local baseRaycastParams = RaycastParams.new()
baseRaycastParams.FilterDescendantsInstances = {debugFolder}
baseRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local function createRayParams(custom)
	if custom then
		local params = custom:Clone()
		params.FilterDescendantsInstances = params.FilterDescendantsInstances or {}
		table.insert(params.FilterDescendantsInstances, debugFolder)
		params.FilterType = Enum.RaycastFilterType.Exclude
		return params
	else
		return baseRaycastParams
	end
end

-- Bullet class
local Bullet = {}
Bullet.__index = Bullet

function Bullet.new(position, direction, settings)
	local self = setmetatable({}, Bullet)
	settings = settings or {}

	self.position = position
	self.velocity = direction.Unit * (settings.speed or defaultSettings.speed)
	self.gravity = settings.gravity or defaultSettings.gravity
	
	self.lifetime = settings.lifetime or defaultSettings.lifetime
	self.maxDistance = settings.maxDistance or defaultSettings.maxDistance
	self.expirationMode = settings.expirationMode or defaultSettings.expirationMode
	
	self.debug = (settings.debug == nil) and defaultSettings.debug or settings.debug
	self.debugColor = settings.debugColor or defaultSettings.debugColor
	self.debugDuration = settings.debugDuration or defaultSettings.debugDuration
	
	self.timeAlive = 0
	self.distanceTraveled = 0
	
	self.raycastParams = createRayParams(settings.raycastParams)
	
	self.pierce = (settings.pierce ~= nil) and settings.pierce or defaultSettings.pierce
	self.ricochet = (settings.ricochet ~= nil) and settings.ricochet or defaultSettings.ricochet

	-- callbacks
	self.onHit = settings.onHit
	self.onExpire = settings.onExpire
	self.onPierce = settings.onPierce
	self.onRicochet = settings.onRicochet

	table.insert(bulletsModule.activeBullets, self)
	return self
end

-- prepare a bullet for firing
function bulletsModule.prepare(settings)
	local prepared = {}
	prepared.settings = settings or {}

	function prepared:Fire(position, direction)
		return Bullet.new(position, direction, self.settings)
	end

	return prepared
end

-- parallel heartbeat with desync → single sync
RunService.Heartbeat:ConnectParallel(function(dt)
	
	task.desynchronize()
	debug.profilebegin("BulletBeingSimulated_Modules")  -- parallel thread profile

	local toSync = {}
	for i = #bulletsModule.activeBullets, 1, -1 do
		local b = bulletsModule.activeBullets[i]

		-- integrate velocity and gravity (desynchronized)
		b.velocity += b.gravity * dt
		local move = b.velocity * dt
		local nextPos = b.position + move

		b.timeAlive += dt
		b.distanceTraveled += move.Magnitude

		local expired = (b.expirationMode == "time" and b.timeAlive >= b.lifetime) or
			(b.expirationMode == "distance" and b.distanceTraveled >= b.maxDistance)

		-- store main-thread actions
		table.insert(toSync, {
			bullet = b,
			from = b.position,
			to = nextPos,
			move = move,
			expired = expired
		})

		-- update position desynced
		b.position = nextPos
	end

	debug.profileend()  -- end parallel physics profile

	task.synchronize()

	local removeIndices = {}

	for i = #toSync, 1, -1 do
		local info = toSync[i]
		local b = info.bullet

		-- raycast for this bullet
		local result = Workspace:Raycast(info.from, info.move, b.raycastParams)

		-- debug drawing
		if b.debug then
			local line = {from = info.from, to = (result and result.Position or info.to), color = b.debugColor, duration = b.debugDuration}
			local part = Instance.new("Part")
			part.Name = "debugpart"
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Material = Enum.Material.Neon
			part.Color = line.color
			
			local length = (line.to - line.from).Magnitude
			part.Size = Vector3.new(0.05, 0.05, length)
			part.CFrame = CFrame.new(line.from, line.to) * CFrame.new(0, 0, -length/2)
			part.Parent = debugFolder
			
			task.delay(line.duration, function()
				if part and part.Parent then part:Destroy() end
			end)
		end

		-- pierce / ricochet / hit / expire logic
		if result then
			if b.pierce > 0 then
				if b.onPierce then
					pcall (b.onPierce, b, result.Instance, result.Position)
				end
				
				b.pierce -= 1
				b.position = result.Position
			elseif b.ricochet > 0 then
				if b.onRicochet then
					pcall (b.onRicochet, b, result.Instance, result.Position)
				end
				
				b.ricochet -= 1
				
				local incoming = b.velocity.Unit
				local normal = result.Normal
				
				b.velocity = (incoming - 2 * incoming:Dot(normal) * normal) * b.velocity.Magnitude
				b.position = result.Position
			else
				if b.onHit then
					pcall(b.onHit, b, result.Instance, result.Position) 
				end
				
				table.insert(removeIndices, i)
			end
		elseif info.expired then
			if b.onExpire then
				pcall(b.onExpire, b) 
			end
			table.insert(removeIndices, i)
		end
	end

	-- remove expired bullets
	for _, idx in ipairs(removeIndices) do
		table.remove(bulletsModule.activeBullets, idx)
	end
end)

return bulletsModule
