-- Tracer module (client)
local Tracer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FastCast = require(ReplicatedStorage.Modules.Shared.FastCastRedux)

-- SINGLE GLOBAL CASTER
local caster = FastCast.new()

function Tracer.newBehavior(tracerTemplate, tracerContainer, acceleration, raycastParams, maxDistance)
	local behavior = caster.newBehavior()
	behavior.CosmeticBulletTemplate = tracerTemplate
	behavior.CosmeticBulletContainer = tracerContainer or workspace
	behavior.Acceleration = acceleration or Vector3.new(0,0,0)
	behavior.RaycastParams = raycastParams
	behavior.MaxDistance = maxDistance or 3000
	return behavior
end

function Tracer.getCaster()
	return caster
end

return Tracer
