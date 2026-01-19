-- bullet_tracer_client (localscript)
-- client-side visual tracer only

print("bullet tracer client started")

local replicatedstorage = game:GetService("ReplicatedStorage")
local runservice = game:GetService("RunService")
local debris = game:GetService("Debris")
local workspace = workspace

local tracer_event = replicatedstorage:WaitForChild("bullet_tracer")

-- visual config
local BULLET_COLOR = Color3.fromRGB(25, 27, 42)
local TRAIL_COLOR = Color3.fromRGB(233, 247, 255)

local TRAIL_COLOR_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, BULLET_COLOR),
	ColorSequenceKeypoint.new(0.1, TRAIL_COLOR),
	ColorSequenceKeypoint.new(1, TRAIL_COLOR),
})

local TRAIL_TRANSPARENCY_SEQUENCE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(0.4, 0.7),
	NumberSequenceKeypoint.new(1, 1),
})

local TRAIL_WIDTH_SEQUENCE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 2),
	NumberSequenceKeypoint.new(0.5, 2),
	NumberSequenceKeypoint.new(1, 0),
})

local TRAIL_LIFETIME = 0.5
local TRAIL_MAX_LENGTH = 64
local MAX_LIFETIME = 1.5

-- active tracer storage
local active = {}

-- create a tracer part + trail
local function create_tracer(origin)
	-- invisible carrier part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Position = origin
	part.Parent = workspace

	-- attachments for trail
	local a0 = Instance.new("Attachment")
	a0.Parent = part

	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -1)
	a1.Parent = part

	-- trail
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = TRAIL_COLOR_SEQUENCE
	trail.Transparency = TRAIL_TRANSPARENCY_SEQUENCE
	trail.WidthScale = TRAIL_WIDTH_SEQUENCE
	trail.Lifetime = TRAIL_LIFETIME
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.MaxLength = TRAIL_MAX_LENGTH
	trail.Parent = part

	debris:AddItem(part, MAX_LIFETIME)

	return part
end

-- receive server events
tracer_event.OnClientEvent:Connect(function(mode, a, b)
	if mode == "start" then
		-- create a tracer with the same physics as the server bullet
		local origin = a
		local velocity = b

		local tracer = create_tracer(origin)

		active[tracer] = {
			part = tracer,
			pos = origin,
			vel = velocity,
			life = 0,
			dead = false,
		}

	elseif mode == "hit" then
		-- kill nearest tracer when server confirms enemy/world hit
		local hitpos = a

		for tracer, data in pairs(active) do
			if not data.dead and (data.pos - hitpos).Magnitude < 6 then
				data.dead = true
			end
		end
	end
end)


-- simulate tracer motion
runservice.RenderStepped:Connect(function(dt)
	for tracer, data in pairs(active) do
		data.life += dt

		if data.dead or data.life >= MAX_LIFETIME then
			active[tracer] = nil
			tracer:Destroy()
		else
			-- bullet drop (visual only)
			data.vel += Vector3.new(0, -10, 0) * dt
			data.pos += data.vel * dt

			tracer.Position = data.pos
			tracer.CFrame = CFrame.lookAt(data.pos, data.pos + data.vel)
		end
	end
end)
