-- Rigging modules
local Rigging = {}
local CollectionService = game:GetService("CollectionService")

function Rigging.createMotor6D(p0, p1, c0, c1)
	local motor6d = Instance.new("Motor6D")
	motor6d.Parent = p0
	motor6d.C0 = c0 or CFrame.new()
	motor6d.C1 = c1 or CFrame.new()
	motor6d.Part0 = p0
	motor6d.Part1 = p1
	motor6d.Name = p1.Name
	CollectionService:AddTag(motor6d, "ToolRigJoint")
	return motor6d
end

function Rigging.destroyRigTags(character)
	for _,v in pairs(character:GetDescendants()) do
		if CollectionService:HasTag(v, "ToolRigJoint") then
			v:Destroy()
		end
	end
end

return Rigging
