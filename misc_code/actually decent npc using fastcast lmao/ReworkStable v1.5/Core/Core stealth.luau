-- inside bots model
-- Core
--  require shared bot controller module 
local bot_controller = require(game.ReplicatedStorage.Modules.bot_controller)
local bot = script.Parent
	

--  configuration table passed into controller.create()
--  ALL behavior (gun, targeting, pathing) is driven only by these values
local default_settings = {

	----------------------------------------------------------------
	-- TEAM / TARGETING
	----------------------------------------------------------------

	team = "Dummy", 
	--  assigned to humanoid attribute "Team"
	--  used for friendly-fire filtering + target selection

	Outfit = "DomionWCRS", 
	Accessory = "DomionWCRS",
	-- Drip
	
	debugRespawn = true,
	-- respawn on death

	----------------------------------------------------------------
	-- WEAPON / BALLISTICS (FastCast)
	----------------------------------------------------------------

	projectile_speed = 3000, 
	--  studs/sec bullet velocity for FastCast

	max_distance = 4000, 
	--  max ray travel distance

	mag_size = 35, 
	--  bullets per magazine

	firerate = 600, 
	--  rounds per minute (RPM)

	pellets = 1, 
	--  shots per trigger pull (shotgun > 1)

	bullet_spread = 1.85,
	--  cone spread in degrees

	accuracy = 0.4,
	-- 0.0 = terrible aim, 1.0 = perfect

	reload_speed = 3.33, 
	--  seconds to reload

	damage = 2, 
	--  humanoid:TakeDamage per hit

	engagement_range = 50000,
	--  only targets enemies within this distance
	
	reaction_front_delay = 0.55,  -- almost instant
	reaction_side_delay  = 0.85,  -- medium
	reaction_back_delay  = 1.0,   -- slow

	reaction_memory_time = 0.4,   -- keep reacting if target briefly hidden
	
	target_steal_factor = 0.65, 

	----------------------------------------------------------------
	-- ANIMATIONS
	----------------------------------------------------------------

	idle_animation = 113048715186773,
	fire_animation = 133613312084742,
	reload_animation = 87796265878708,
	--  animation asset ids for animator tracks


	----------------------------------------------------------------
	-- SOUNDS
	----------------------------------------------------------------

	fire_sound_id = 96250718216960,
	reload_sound_id = 6052570694,

	fire_sound_pitch = 1,
	fire_sound_volume = 0.3,
	reload_sound_volume = 0.2,
	--  audio playback settings


	----------------------------------------------------------------
	-- PATHING / COMBAT MOVEMENT (NoobPath)
	----------------------------------------------------------------

	max_path_distance = 50000,
	--  clamp how far a path goal can be (prevents huge paths)

	desired_distance = 25,
	--  tactical spacing distance from enemy when visible
	
	retreat_threshold = 23.5,
	--  if closer than this, bot backs away

	path_update_cooldown = 0.3,
	--  minimum time between path recalculations

	goal_recalc_distance = 0.8,
	--  only recompute path if goal moved this much

	wander_dist_short = 10,           -- short wander distance (studs)
	wander_dist_medium = 40,         -- medium wander distance (studs)
	wander_dist_long = 120,          -- long wander distance (studs)

	wander_cooldown_min = 2,         -- minimum seconds between wander decisions
	wander_weights = {0.5,0.35,0.15},-- probability weights for short/medium/long wander

	alert_cooldown = 3,              -- seconds a source must wait before broadcasting again
	alert_response_cooldown = 1,     -- seconds a bot ignores repeat alerts (per receiver)
	alert_hold_time = 8,             -- seconds a received alert is held to prevent wander stealing
	alert_prefer_flank = 0.25,       -- chance an alert chooses "flank" vs "assist" when originating

	flank_distance = 20,             -- distance used when computing flank destination (studs)
	flank_behind_bias = 8,           -- how far behind the enemy the flank attempts to bias (studs)
	busy_keep_distance = 12,         -- if already closer than this to a target, consider the bot "busy"
	
	engage_flank_chance = 0.15,      -- chance this bot requests flanking when engaging
	----------------------------------------------------------------
	-- NOOBPATH AGENT SETTINGS
	----------------------------------------------------------------

	noobpath_speed = 16,
	--  humanoid movement speed

	noobpath_agent = {
		AgentRadius = 3.5,
		AgentHeight = 6,
		AgentCanClimb = true,
		AgentCanJump = true,
		AgentJumpHeight = 12,
		WaypointSpacing = 2,
		PathSettings = { SupportPartialPath = true },
	}
	--  passed directly into NoobPath.new()
}


--  create controller instance for this bot using provided settings
local ctrl = bot_controller.create(bot, default_settings)

local original_cframe = bot:GetPivot() or bot:FindFirstChild("HumanoidRootPart").CFrame
local original_parent = bot.Parent

-- clone template once at start
local bot_clone_template = bot:Clone()
bot_clone_template.Parent = nil -- keep template off workspace

if default_settings.debugRespawn then
	local humanoid = bot:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		task.spawn(function()
			task.wait(5) -- respawn delay

			-- destroy old controller
			if ctrl then
				ctrl:destroy()
				ctrl = nil
			end

			-- clone new bot from template
			local new_bot = bot_clone_template:Clone()
			new_bot.Parent = original_parent

			-- place at original spawn position
			local hrp = new_bot:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.CFrame = original_cframe
			end

			-- destroy the old bot model (dead one)
			if bot and bot.Parent then
				bot:Destroy()
			end

			-- reassign bot variable to new bot
			bot = new_bot

			-- create new controller for respawned bot
			ctrl = bot_controller.create(bot, default_settings)
			ctrl:start()
		end)
	end)
end

--  start heartbeat loop (targeting + pathing + firing)
ctrl:start()
-- end of Core