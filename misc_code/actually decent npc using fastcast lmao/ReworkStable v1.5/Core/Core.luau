--  require shared bot controller module 
local bot_controller = require(game.ReplicatedStorage.Modules.bot_controller)
local bot = script.Parent


--  configuration table passed into controller.create()
--  ALL behavior (gun, targeting, pathing) is driven only by these values
local default_settings = {

	----------------------------------------------------------------
	-- TEAM / TARGETING
	----------------------------------------------------------------

	team = "dummy", 
	--  assigned to humanoid attribute "Team"
	--  used for friendly-fire filtering + target selection


	----------------------------------------------------------------
	-- WEAPON / BALLISTICS (FastCast)
	----------------------------------------------------------------

	projectile_speed = 3000, 
	--  studs/sec bullet velocity for FastCast

	max_distance = 4000, 
	--  max ray travel distance

	mag_size = 35, 
	--  bullets per magazine

	firerate = 605, 
	--  rounds per minute (RPM)

	pellets = 1, 
	--  shots per trigger pull (shotgun > 1)

	bullet_spread = 1.5,
	--  cone spread in degrees

	reload_speed = 3.33, 
	--  seconds to reload

	damage = 1.1, 
	--  humanoid:TakeDamage per hit

	engagement_range = 50000,
	--  only targets enemies within this distance


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
	fire_sound_volume = 0.4,
	reload_sound_volume = 0.2,
	--  audio playback settings


	----------------------------------------------------------------
	-- PATHING / COMBAT MOVEMENT (NoobPath)
	----------------------------------------------------------------

	max_path_distance = 50000,
	--  clamp how far a path goal can be (prevents huge paths)

	desired_distance = 10,
	--  tactical spacing distance from enemy when visible

	retreat_threshold = 8.3,
	--  if closer than this, bot backs away

	path_update_cooldown = 0.3,
	--  minimum time between path recalculations

	goal_recalc_distance = 1,
	--  only recompute path if goal moved this much


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

--  start heartbeat loop (targeting + pathing + firing)
ctrl:start()
