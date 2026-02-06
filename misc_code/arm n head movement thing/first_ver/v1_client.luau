-- StarterPlayerScripts
local runservice = game:GetService("RunService")
local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")

local player = players.LocalPlayer
local camera = workspace.CurrentCamera
local event = replicatedstorage:WaitForChild("LookEvent")

-- settings

local updaterate = 1/60
local accumulated = 0

local headhor = 0.8
local headvert = 0.7
local updatespeed = 0.5


-- cached character part

local character
local humanoid
local head
local torso
local neck
local rightshoulder
local leftshoulder

local neckorg
local rightorg
local leftorg

local mouse = player:GetMouse()

local function bindcharacter(char)
	character = char
	humanoid = char:WaitForChild("Humanoid")

	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return
	end

	head = char:WaitForChild("Head")
	torso = char:WaitForChild("Torso")

	neck = torso:WaitForChild("Neck")
	rightshoulder = torso:WaitForChild("Right Shoulder")
	leftshoulder = torso:WaitForChild("Left Shoulder")

	neckorg = neck.C0
	rightorg = rightshoulder.C0
	leftorg = leftshoulder.C0
end

bindcharacter(player.Character or player.CharacterAdded:Wait())
player.CharacterAdded:Connect(bindcharacter)

local function hastool()
	for _, v in ipairs(character:GetChildren()) do
		if v:IsA("Tool") then
			return true
		end
	end
	return false
end

local function updatechar()
	if not character or not torso then
		return
	end

	local headpos = head.Position
	local campos = camera.CFrame.Position
	local torsolook = torso.CFrame.LookVector

	local dist = (headpos - campos).Magnitude
	if dist < 0.001 then
		return
	end

	local diff = headpos.Y - campos.Y

	-- head tracking
	local pitch = -(math.asin(diff/dist) * headvert)
	local yaw = -(((headpos - campos).Unit):Cross(torsolook)).Y * headhor

	local targetneck = neckorg * CFrame.Angles(pitch, 0, yaw)
	neck.C0 = neck.C0:Lerp(targetneck, updatespeed)

	-- arm control
	if hastool() then
		-- uses camera look direction directly 
		local look = camera.CFrame.LookVector
		local x = math.asin(look.Y) -- fixed sign

		local _, ry, rz = rightshoulder.C0:ToEulerAnglesXYZ()
		local _, ly, lz = leftshoulder.C0:ToEulerAnglesXYZ()

		local rtarget = CFrame.new(rightshoulder.C0.Position) * CFrame.Angles(x, ry, rz)
		local ltarget = CFrame.new(leftshoulder.C0.Position) * CFrame.Angles(x, ly, lz)

		rightshoulder.C0 = rightshoulder.C0:Lerp(rtarget, updatespeed)
		leftshoulder.C0 = leftshoulder.C0:Lerp(ltarget, updatespeed)
	else
		-- smooth reset
		rightshoulder.C0 = rightshoulder.C0:Lerp(rightorg, updatespeed)
		leftshoulder.C0 = leftshoulder.C0:Lerp(leftorg, updatespeed)
	end
end

-- updates pose and always replicates to server
runservice.RenderStepped:Connect(function(dt)
	updatechar()

	accumulated += dt
	if accumulated >= updaterate then
		accumulated = 0

		-- always send (no CameraMode gate)
		event:FireServer(neck.C0, rightshoulder.C0, leftshoulder.C0)
	end
end)
