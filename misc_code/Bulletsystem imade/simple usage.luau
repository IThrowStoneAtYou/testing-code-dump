local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Bullets = require(ReplicatedStorage.SimulatedBulletActor:WaitForChild("simulated_bullets"))

local shooter = script.Parent

-- prepare settings once
local bulletShooter = Bullets.prepare({
	speed = 1500,
	gravity = Vector3.new(0, -250, 0),
	expirationMode = "distance",
	lifetime = 5,
	maxDistance = 7000,
	debug = true,
	debugColor = Color3.new(0,1,0),
	debugDuration = 0.1,
	pierce = 0,
	ricochet = 0,
	
	onHit = function(b,p,pos) 
		print("Hit", p.Name) 
	end,
	
	onExpire = function(b)
		print("Bullet expired at", b.position)
	end
})

-- fire bullets repeatedly
while true do
	bulletShooter:Fire(shooter.Position, shooter.CFrame.LookVector)
	task.wait(0.05)
end
