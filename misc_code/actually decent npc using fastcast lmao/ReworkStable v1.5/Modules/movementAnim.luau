-- ModuleScript: movementAnim
-- Handles bot idle and walking animations based on humanoid state

local module = {}

-- settings table: {humanoid = Humanoid, idle_anim_id = number, walk_anim_id = number}
function module.create(settings)
	assert(settings and settings.humanoid, "movementAnim.create: humanoid required")

	local self = {}
	self.humanoid = settings.humanoid
	self.animator = self.humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", self.humanoid)

	-- animations
	local function create_track(anim_id)
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(anim_id)
		return self.animator:LoadAnimation(anim)
	end

	self.idle_track = create_track(settings.idle_anim_id)
	self.walk_track = create_track(settings.walk_anim_id)

	self.current_track = nil

	-- plays the desired track and stops the previous one
	local function play_track(track)
		if self.current_track == track then return end
		if self.current_track then
			pcall(function() self.current_track:Stop() end)
		end
		
		self.current_track = track
		if track then pcall(function() track:Play() end) end
	end

	-- main update function (call every frame or via RunService heartbeat)
	function self:update()
		if not self.humanoid or self.humanoid.Health <= 0 then
			play_track(nil)
			return
		end

		local state = self.humanoid:GetState()
		local vel = self.humanoid.RootPart and self.humanoid.RootPart.Velocity or Vector3.new()
		local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

		-- determine animation
		if state == Enum.HumanoidStateType.Seated
			or state == Enum.HumanoidStateType.Freefall
			or state == Enum.HumanoidStateType.Jumping
			or state == Enum.HumanoidStateType.Physics
			or speed < 0.1 then
			play_track(self.idle_track)
		else
			play_track(self.walk_track)
		end
	end

	-- start automatic heartbeat update
	function self:start()
		if self.conn then return end
		self.conn = game:GetService("RunService").Heartbeat:Connect(function()
			self:update()
		end)
	end

	function self:stop()
		if self.conn then
			self.conn:Disconnect()
			self.conn = nil
		end
		play_track(nil)
	end

	return self
end

return module
