local RunService = game:GetService("RunService")

local WALK_SPEED_THRESHOLD = 1
local CHECK_RATE = 0.1

local accumulator = 0
local trackedUnits = {}

local function setupUnit(unit)
	if trackedUnits[unit] then return end

	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")

	local idleAnim = unit:FindFirstChild("Idle")
	local walkAnim = unit:FindFirstChild("Walk")

	if not humanoid or not animator or not idleAnim or not walkAnim then
		return
	end

	local idleTrack = animator:LoadAnimation(idleAnim)
	local walkTrack = animator:LoadAnimation(walkAnim)

	idleTrack.Looped = true
	walkTrack.Looped = true

	idleTrack:Play()

	trackedUnits[unit] = {
		idle = idleTrack,
		walk = walkTrack,
		state = "Idle"
	}

	print("[Anim] Setup", unit.Name)
end

local function cleanupUnit(unit)
	local data = trackedUnits[unit]
	if not data then return end

	data.idle:Stop()
	data.walk:Stop()
	trackedUnits[unit] = nil

	print("[Anim] Cleanup", unit.Name)
end

local function scanForUnits()
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model")
			and model:GetAttribute("LastTarget") ~= nil
			and model:FindFirstChildOfClass("Humanoid") then
			setupUnit(model)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < CHECK_RATE then return end
	accumulator = 0

	scanForUnits()

	for unit, data in pairs(trackedUnits) do
		if not unit.Parent then
			cleanupUnit(unit)
			continue
		end

		local root = unit.PrimaryPart
		if not root then continue end

		local speed = root.AssemblyLinearVelocity.Magnitude

		if speed > WALK_SPEED_THRESHOLD then
			if data.state ~= "Walk" then
				data.idle:Stop()
				data.walk:Play()
				data.state = "Walk"
				print("[Anim]", unit.Name, "To WALK")
			end
		else
			if data.state ~= "Idle" then
				data.walk:Stop()
				data.idle:Play()
				data.state = "Idle"
				print("[Anim]", unit.Name, "To IDLE")
			end
		end
	end
end)
