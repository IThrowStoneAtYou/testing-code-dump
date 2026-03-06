-- example of item setting
local setting = {
	
	name = "RocketLauncher", -- name for identify
	id = "RocketLauncher", -- assets names
	amount = 0, -- ??
	maxstack = 1, -- max stacks
	image = "rbxassetid://106850765771032",
	class = "Gun" -- can be "Gun" or "Melee"
	-- other ids/class:
	-- Armor = Arm, Body, Head, Mask, Pants
	-- Backpack = Backpack
}

--[[

-- extras:
-- Backpack
	class = Backpack:
	slot = 35, -- how many cell extra when equiped
	Backpack_ID = 0, -- ????
	Owner = false -- also ???

-- Armor
	class = Arm, Body, Head, Mask, Pants
	health = 100 -- this set amount of max health

--]]

return setting
