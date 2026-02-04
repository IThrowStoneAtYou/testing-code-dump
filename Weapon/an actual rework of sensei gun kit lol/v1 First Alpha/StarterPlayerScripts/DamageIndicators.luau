-- inside StarterPlayerScripts
-- DamageIndicators (local)
local tweenService = game:GetService("TweenService")
local runService = game:GetService("RunService")
local hud = Instance.new("ScreenGui")
local player = game.Players.LocalPlayer
hud.Parent = player:WaitForChild("PlayerGui")
hud.Name = "MouseContainer"
hud.IgnoreGuiInset = false

local mouse = game.Players.LocalPlayer:GetMouse()
local frame = Instance.new("Frame")
frame.Parent = hud
frame.Name = "MouseFrame"
frame.Transparency = 1

local currentHitmarker = nil
local currentHitmarkerLifetime = 0
local currentHitmarkerDamage = 0

local function stepped()
	frame.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
end

local function createSound(id)
	local sound = Instance.new("Sound")
	sound.Parent = script
	sound.SoundId = 'rbxassetid://'..id
	sound.RollOffMaxDistance = 300
	sound.RollOffMinDistance = 10
	sound.RollOffMode = Enum.RollOffMode.Linear

	return sound
end

local function heartbeat(step)
	if currentHitmarker then
		if currentHitmarkerLifetime > 0 then
			currentHitmarkerLifetime = currentHitmarkerLifetime - step
		else
			currentHitmarker:Destroy()
			currentHitmarker = nil
			currentHitmarkerDamage = 0
			currentHitmarkerLifetime = 0
		end
	end
end

local function sound(obj)
	local clone = obj:Clone()
	clone.Parent = script
	clone:Play()
	
	game.Debris:AddItem(clone, obj.TimeLength)
end

local function fx(showDamage, showHitmarker)
	local ti = TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true)
	local rotTi = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
	
	if showDamage then
		currentHitmarker.TextSize = 20
		currentHitmarker.Rotation = math.random(-30,30)
		
		local rotTween = tweenService:Create(currentHitmarker, rotTi, {Rotation = 0})
		rotTween:Play(); rotTween:Destroy()

		local tween = tweenService:Create(currentHitmarker, ti, {TextSize = 30})
		tween:Play(); tween:Destroy()
	end
	
	local previous = frame:FindFirstChild("Hitmark")
	if previous then
		previous:Destroy()
	end
	
	if showHitmarker then
		local hitmarker = script.Hitmark:Clone()
		hitmarker.Parent = frame
		hitmarker.Size = UDim2.new(0,60,0,60)
		
		hitmarker.Rotation = math.random(-40,40)
		
		local hitmarkTween = tweenService:Create(hitmarker, rotTi, {Rotation = 0, Size = UDim2.new(0,30,0,30)})
		hitmarkTween:Play(); hitmarkTween:Destroy()
		
		game.Debris:AddItem(hitmarker, 1)
	end
end

function _G.IndicateDamage(damage, kill, hitSound, killSound, showDamage, showHitmarker)
	if not currentHitmarker then
		if showDamage then
			local clone = script.Indication:Clone()
			clone.Parent = frame
			clone.Position = UDim2.new(0.5, 0, 0.5, 40)
			clone.Text = damage
			
			currentHitmarkerLifetime = 1
			currentHitmarkerDamage = damage
			currentHitmarker = clone
		end
		
		fx(showDamage, showHitmarker)
	else
		if showDamage then
			local newDamage = currentHitmarkerDamage + damage
			currentHitmarker.Text = newDamage
			currentHitmarkerDamage = newDamage
			currentHitmarkerLifetime = 1
			
			if kill then
				currentHitmarker.Text = "KILL"
				currentHitmarker.TextColor3 = Color3.fromRGB(255,0,0)
			else
				currentHitmarker.TextColor3 = Color3.fromRGB(255,255,255)
			end
		end
		
		fx(showDamage, showHitmarker)
	end
	
	if kill then
		if killSound ~= nil then
			sound(createSound(killSound))
		end
	else
		if hitSound ~= nil then
			sound(createSound(hitSound))
		end
	end
	
	--[[
	local newPos = UDim2.new(0.5, math.random(-50, 50), 0.5, math.random(-50, 50))
	local tween = tweenService:Create(clone, TweenInfo.new(0.5), {Position = newPos})
	tween:Play(); tween:Destroy()
	
	game.Debris:AddItem(clone, 1)
	--]]
end

local function setupDamageIndicators()
	-- destroy old GUI if it exists
	local old = player:FindFirstChild("PlayerGui"):FindFirstChild("MouseContainer")
	if old then old:Destroy() end

	local tweenService = game:GetService("TweenService")
	local runService = game:GetService("RunService")

	local hud = Instance.new("ScreenGui")
	hud.Parent = player:WaitForChild("PlayerGui")
	hud.Name = "MouseContainer"
	hud.IgnoreGuiInset = false

	local mouse = player:GetMouse()
	local frame = Instance.new("Frame")
	frame.Parent = hud
	frame.Name = "MouseFrame"
	frame.Transparency = 1

	local currentHitmarker = nil
	local currentHitmarkerLifetime = 0
	local currentHitmarkerDamage = 0

	local function stepped()
		frame.Position = UDim2.new(0, mouse.X, 0, mouse.Y)
	end

	local function heartbeat(step)
		if currentHitmarker then
			if currentHitmarkerLifetime > 0 then
				currentHitmarkerLifetime = currentHitmarkerLifetime - step
			else
				currentHitmarker:Destroy()
				currentHitmarker = nil
				currentHitmarkerDamage = 0
				currentHitmarkerLifetime = 0
			end
		end
	end

	local function createSound(id)
		local sound = Instance.new("Sound")
		sound.Parent = script
		sound.SoundId = 'rbxassetid://'..id
		sound.RollOffMaxDistance = 300
		sound.RollOffMinDistance = 10
		sound.RollOffMode = Enum.RollOffMode.Linear
		return sound
	end

	local function sound(obj)
		local clone = obj:Clone()
		clone.Parent = script
		clone:Play()
		game.Debris:AddItem(clone, obj.TimeLength)
	end

	local function fx(showDamage, showHitmarker)
		-- simplified for brevity, same as before
		local ti = TweenInfo.new(0.05, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true)
		local rotTi = TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)

		if showDamage then
			currentHitmarker.TextSize = 20
			currentHitmarker.Rotation = math.random(-30,30)

			local rotTween = tweenService:Create(currentHitmarker, rotTi, {Rotation = 0})
			rotTween:Play(); rotTween:Destroy()

			local tween = tweenService:Create(currentHitmarker, ti, {TextSize = 30})
			tween:Play(); tween:Destroy()
		end

		local previous = frame:FindFirstChild("Hitmark")
		if previous then
			previous:Destroy()
		end

		if showHitmarker then
			local hitmarker = script.Hitmark:Clone()
			hitmarker.Parent = frame
			hitmarker.Size = UDim2.new(0,60,0,60)

			hitmarker.Rotation = math.random(-40,40)

			local hitmarkTween = tweenService:Create(hitmarker, rotTi, {Rotation = 0, Size = UDim2.new(0,30,0,30)})
			hitmarkTween:Play(); hitmarkTween:Destroy()

			game.Debris:AddItem(hitmarker, 1)
		end
	end

	function _G.IndicateDamage(damage, kill, hitSound, killSound, showDamage, showHitmarker)
		-- same logic as original _G.IndicateDamage
		
		if not currentHitmarker then
			if showDamage then
				local clone = script.Indication:Clone()
				clone.Parent = frame
				clone.Position = UDim2.new(0.5, 0, 0.5, 40)
				clone.Text = damage

				currentHitmarkerLifetime = 1
				currentHitmarkerDamage = damage
				currentHitmarker = clone
			end

			fx(showDamage, showHitmarker)
		else
			if showDamage then
				local newDamage = currentHitmarkerDamage + damage
				currentHitmarker.Text = newDamage
				currentHitmarkerDamage = newDamage
				currentHitmarkerLifetime = 1

				if kill then
					currentHitmarker.Text = "KILL"
					currentHitmarker.TextColor3 = Color3.fromRGB(255,0,0)
				else
					currentHitmarker.TextColor3 = Color3.fromRGB(255,255,255)
				end
			end

			fx(showDamage, showHitmarker)
		end

		if kill then
			if killSound ~= nil then
				sound(createSound(killSound))
			end
		else
			if hitSound ~= nil then
				sound(createSound(hitSound))
			end
		end
	end

	runService.RenderStepped:Connect(stepped)
	runService.Heartbeat:Connect(heartbeat)
end

-- initial setup
setupDamageIndicators()

-- re-setup on respawn
player.CharacterAdded:Connect(function()
	setupDamageIndicators()
end)

runService.RenderStepped:Connect(stepped)
runService.Heartbeat:Connect(heartbeat)