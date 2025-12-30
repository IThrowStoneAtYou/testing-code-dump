-- ClientMobileHandler
-- Handles mobile buttons via ContextActionService for ClientMain.
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local ClientMobileHandler = {}
ClientMobileHandler.__index = ClientMobileHandler

function ClientMobileHandler.new(clientMain)
	local self = setmetatable({}, ClientMobileHandler)
	self.client = clientMain
	self.bound = false
	return self
end

-- Internal action callbacks
function ClientMobileHandler:_fireAction(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		self.client:activated()
	elseif inputState == Enum.UserInputState.End then
		self.client:deactivated()
	end
	return Enum.ContextActionResult.Sink
end

function ClientMobileHandler:_zoomAction(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		self.client:scopeIn()
	elseif inputState == Enum.UserInputState.End then
		self.client:scopeOut()
	end
	return Enum.ContextActionResult.Sink
end

function ClientMobileHandler:_reloadAction(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		self.client:reload()
	end
	return Enum.ContextActionResult.Sink
end

function ClientMobileHandler:bindActions()
	if self.bound then 
		return
	end
	
	if not UserInputService.TouchEnabled then
		return 
	end

	-- Bind actions
	ContextActionService:BindAction("Gun_Fire", function(...) return self:_fireAction(...) end, false)
	ContextActionService:BindAction("Gun_Reload", function(...) return self:_reloadAction(...) end, false)
	
	if self.client.config and self.client.config.ZoomEnabled then
		ContextActionService:BindAction("Gun_Zoom", function(...) return self:_zoomAction(...) end, false)
	end

	-- Configure visuals / positions
	
	pcall(function()  -- figure out why these button wont appear...
		ContextActionService:SetImage("Gun_Fire", 'rbxassetid://8961981049')
		ContextActionService:SetPosition("Gun_Fire", UDim2.new(1, -70, 0, 10))
		ContextActionService:GetButton("Gun_Fire").Size = UDim2.new(0, 70, 0, 70)

		ContextActionService:SetImage("Gun_Reload", 'rbxassetid://8908047394')
		ContextActionService:SetPosition("Gun_Reload", UDim2.new(1, -110, 0, -40))

		if self.client.config and self.client.config.ZoomEnabled then
			ContextActionService:SetImage("Gun_Zoom", 'rbxassetid://8908047094')
			ContextActionService:SetPosition("Gun_Zoom", UDim2.new(1, -70, 0, -90))
		end
	end)

	self.bound = true
end

function ClientMobileHandler:unbindActions()
	if not self.bound then
		return 
	end
	
	ContextActionService:UnbindAction("Gun_Fire")
	ContextActionService:UnbindAction("Gun_Reload")
	ContextActionService:UnbindAction("Gun_Zoom")
	
	self.bound = false
end

return ClientMobileHandler
