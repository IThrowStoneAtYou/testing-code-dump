-- Utils modules
local Utils = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

function Utils.createSound(parent, soundId, playbackSpeed)  -- Removed 'volume' parameter
	local sound = Instance.new("Sound")
	sound.Parent = parent or workspace
	sound.SoundId = (tostring(soundId):match("^rbxassetid://") and soundId) or ('rbxassetid://'..tostring(soundId))
	sound.RollOffMaxDistance = 300
	sound.RollOffMinDistance = 10
	sound.RollOffMode = Enum.RollOffMode.Linear
	-- Volume is now controlled by the Sound object itself
	if playbackSpeed ~= nil then sound.PlaybackSpeed = playbackSpeed end
	return sound
end

-- Create animation object and load on given humanoid
function Utils.createAnimation(humanoid, id)
	if not id or id == "" then return nil end
	local animObject = Instance.new("Animation")
	animObject.AnimationId = 'rbxassetid://'..tostring(id)
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
	local ok, track = pcall(function() return animator:LoadAnimation(animObject) end)
	if ok then return track end
	return nil
end

-- Raycast helper
function Utils.raycast(origin, direction, range, ignoreList, filterType)
	range = range or 1000
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = ignoreList or {}
	rayParams.FilterType = filterType or Enum.RaycastFilterType.Exclude
	return workspace:Raycast(origin, direction.Unit * range, rayParams)
end

-- Tween helper: plays tween and schedules cleanup
function Utils.tweenAndCleanup(instance, tweenInfo, properties)
	local tween = TweenService:Create(instance, tweenInfo, properties)
	tween:Play()
	-- Do not call Destroy() immediately, allow automatic GC; schedule with Debris for objects that need removing
	return tween
end

-- Safe wait loader — waits until Sound is loaded
function Utils.waitForLoaded(sound)
	repeat RunService.Heartbeat:Wait() until sound.IsLoaded or sound.TimeLength > 0
end

return Utils
