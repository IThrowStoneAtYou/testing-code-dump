-- ModuleScript: noobpath_factory
--  factory that creates and configures a NoobPath instance for a bot
local module = {}

--  services + dependency (noobpath) assumed in ReplicatedStorage.Modules
local replicatedstorage = game:GetService("ReplicatedStorage")
local noobpath = require(replicatedstorage.Modules:WaitForChild("NoobPath"))

--  create(bot_model, humanoid, agent_params, speed, on_stop_cb)
-- bot_model: Model that NoobPath will control
-- humanoid: Humanoid instance used for MoveTo/Jump checks
-- agent_params: table passed to NoobPath.new() as agent params
-- speed: optional speed to set on the returned NoobPath instance
-- on_stop_cb: optional callback run when NoobPath traps or errors (safe pcall)
function module.create(bot_model, humanoid, agent_params, speed, on_stop_cb)
	--  basic validation
	if not bot_model or not bot_model:IsA("Model") then return nil end
	if not humanoid or not humanoid:IsA("Humanoid") then return nil end

	agent_params = agent_params or {}

	--  internal bindable events that NoobPath expects for callbacks
	local move_finished_event = Instance.new("BindableEvent")
	local jump_finished_event = Instance.new("BindableEvent")

	--  safe move callback wrapping humanoid:MoveTo
	local function move_callback(destination)
		if not humanoid or humanoid.Health <= 0 then
			task.spawn(function() pcall(function() move_finished_event:Fire(false) end) end)
			return
		end
		local ok = pcall(function() humanoid:MoveTo(destination) end)
		if not ok then
			task.spawn(function() pcall(function() move_finished_event:Fire(false) end) end)
			return
		end
		local conn
		conn = humanoid.MoveToFinished:Connect(function(reached)
			pcall(function() move_finished_event:Fire(reached) end)
			if conn then conn:Disconnect() end
		end)
	end

	--  safe jump callback that sets humanoid.Jump and fires when landed
	local function jump_callback()
		if not humanoid or humanoid.Health <= 0 then
			task.spawn(function() pcall(function() jump_finished_event:Fire() end) end)
			return
		end
		pcall(function() humanoid.Jump = true end)
		local conn
		conn = humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				pcall(function() jump_finished_event:Fire() end)
				if conn then conn:Disconnect() end
			end
		end)
		-- fallback timeout to ensure the event always fires
		task.delay(2, function()
			if conn and conn.Connected then
				pcall(function() jump_finished_event:Fire() end)
				if conn then conn:Disconnect() end
			end
		end)
	end

	--  attempt to create NoobPath with wrapped callbacks
	local ok, np = pcall(function()
		return noobpath.new(bot_model, agent_params, move_callback, jump_callback, jump_finished_event.Event, move_finished_event.Event)
	end)
	if not ok or not np then return nil end

	--  configure returned instance safely
	np.Timeout = false
	np.Visualize = false
	np.Speed = speed or np.Speed

	--  connect trapped/error to stop path and call optional on_stop_cb
	pcall(function()
		np.Trapped:Connect(function()
			pcall(function() np:Stop() end)
			if type(on_stop_cb) == "function" then
				pcall(on_stop_cb)
			end
		end)
		np.Error:Connect(function()
			pcall(function() np:Stop() end)
			if type(on_stop_cb) == "function" then
				pcall(on_stop_cb)
			end
		end)
	end)

	return np
end

return module
