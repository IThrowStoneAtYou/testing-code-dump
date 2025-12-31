-- ClientKeybindHandler Modules
-- Handles desktop/keyboard/mouse input for ClientMain.
local UserInputService = game:GetService("UserInputService")

local ClientKeybindHandler = {}
ClientKeybindHandler.__index = ClientKeybindHandler

function ClientKeybindHandler.new(clientMain)
	local self = setmetatable({}, ClientKeybindHandler)
	self.client = clientMain
	self._conns = {}
	return self
end

function ClientKeybindHandler:bindActions()
	-- InputBegan: keyboard keys
	self._conns.inputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not self.client.toolEquipped then return end

		-- Reload
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.R then
			pcall(function() self.client:reload() end)
		end
	end)

	-- Mouse buttons (use Player:GetMouse())
	if self.client.mouse then
		self._conns.mouseButton2Down = self.client.mouse.Button2Down:Connect(function()
			if not self.client.toolEquipped then return end
			pcall(function() self.client:scopeIn() end)
		end)
		self._conns.mouseButton2Up = self.client.mouse.Button2Up:Connect(function()
			if not self.client.toolEquipped then return end
			pcall(function() self.client:scopeOut() end)
		end)
	end
end

function ClientKeybindHandler:unbindActions()
	for name, conn in pairs(self._conns) do
		if conn and conn.Disconnect then
			pcall(function() conn:Disconnect() end)
		end
		self._conns[name] = nil
	end
end

return ClientKeybindHandler
