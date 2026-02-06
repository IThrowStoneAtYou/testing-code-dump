-- client arm thing
local runservice = game:GetService("RunService")
local players = game:GetService("Players")
local replicatedstorage = game:GetService("ReplicatedStorage")

local player = players.LocalPlayer
local camera = workspace.CurrentCamera
local event = replicatedstorage:WaitForChild("LookEvent")

-- settings
local updaterate = 1/15
local accumulated = 0
local headhor = 0.8
local headvert = 0.8
local updatespeed = 0.5

-- cached character parts
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
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end

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
		if v:IsA("Tool") then return true end
	end
	return false
end

local control_mode = "cursor" -- "camera" or "cursor"

local function updatechar()		-- this math are cursed.
	if not character or not torso then return end

	local headpos = head.Position
	local torsolook = torso.CFrame.LookVector

	local aimpos
	local vec

	if control_mode == "cursor" then
		aimpos = mouse.Hit.Position
		vec = (aimpos - headpos)
	else
		aimpos = camera.CFrame.Position
		vec = (headpos - aimpos)
	end

	local dist = vec.Magnitude
	if dist < 0.001 then return end

	local diff = vec.Y

	-- head rotation
	local pitch = -(math.asin(diff/dist) * headvert)
	local yaw = -(vec.Unit:Cross(torsolook)).Y * headhor

	local targetneck = neckorg * CFrame.Angles(pitch, 0, yaw)
	neck.C0 = neck.C0:Lerp(targetneck, updatespeed)

	-- arm rotation
	if hastool() then
		local look
		if control_mode == "cursor" then
			look = (mouse.Hit.Position - headpos).Unit
		else
			look = camera.CFrame.LookVector
		end

		local x = math.asin(look.Y)
		local _, ry, rz = rightshoulder.C0:ToEulerAnglesXYZ()
		local _, ly, lz = leftshoulder.C0:ToEulerAnglesXYZ()

		local rtarget = CFrame.new(rightshoulder.C0.Position) * CFrame.Angles(x, ry, rz)
		local ltarget = CFrame.new(leftshoulder.C0.Position) * CFrame.Angles(x, ly, lz)

		rightshoulder.C0 = rightshoulder.C0:Lerp(rtarget, updatespeed)
		leftshoulder.C0 = leftshoulder.C0:Lerp(ltarget, updatespeed)
	else
		rightshoulder.C0 = rightshoulder.C0:Lerp(rightorg, updatespeed)
		leftshoulder.C0 = leftshoulder.C0:Lerp(leftorg, updatespeed)
	end
end

-- cache for server-replicated targets
local replicatedTargets = {} -- [player] = {neck, rs, ls}

-- receive server updates
event.OnClientEvent:Connect(function(fromplayer, neckc0, rsc0, lsc0)
	if fromplayer == player then 
		return 
	end
	
	replicatedTargets[fromplayer] = {neck = neckc0, rs = rsc0, ls = lsc0}
end)

-- smooth tween server poses
local function tweenReplicated(dt)
	for otherPlayer, data in pairs(replicatedTargets) do
		local char = otherPlayer.Character
		
		if not char then
			replicatedTargets[otherPlayer] = nil
			continue
		end

		local torso = char:FindFirstChild("Torso")
		
		if not torso then continue end

		local neck = torso:FindFirstChild("Neck")
		local rs = torso:FindFirstChild("Right Shoulder")
		local ls = torso:FindFirstChild("Left Shoulder")
		
		if not neck or not rs or not ls then continue end

		local factor = math.clamp(dt * 10, 0, 1)
		neck.C0 = neck.C0:Lerp(data.neck, factor)
		rs.C0 = rs.C0:Lerp(data.rs, factor)
		ls.C0 = ls.C0:Lerp(data.ls, factor)
	end
end

-- main update loop
runservice.RenderStepped:Connect(function(dt)
	updatechar()

	accumulated += dt
	if accumulated >= updaterate then
		accumulated = 0
		event:FireServer(neck.C0, rightshoulder.C0, leftshoulder.C0)
	end

	tweenReplicated(dt)
end)
