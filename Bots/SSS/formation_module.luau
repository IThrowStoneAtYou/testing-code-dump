-- formation_module (modules)
-- formation geometry, file ordering, slot packing and gap filling utilities
local module = {}

-- build a file order centered (center, right, left, right2, left2...)
function module.build_file_order(columns)
	-- return file ordering centered
--	print("formation_module.build_file_order called", columns)
	local order = {}
	local center = math.floor((columns - 1) / 2) + 1
	table.insert(order, center)
	for i = 1, columns do
		local r = center + i
		local l = center - i
		if r <= columns then table.insert(order, r) end
		if l >= 1 then table.insert(order, l) end
	end
	return order
end

-- rebuiltslots: preserve bot objects but reorder slots using center-out file order
function module.rebuiltslots(company)
	-- rebuild slots with center-out file ordering while preserving bot objects
	print("formation_module.rebuiltslots called")
	local rows = company.rows
	local columns = math.ceil(company.maxslots / rows)
	local fileorder = module.build_file_order(columns)

	local pool = {}
	for i = 1, company.maxslots do
		local bot = company.slots[i]
		if bot and bot ~= false then
			table.insert(pool, bot)
		end
	end

	local newslots = {}
	local index = 1

	for row = 0, rows - 1 do
		for _, file in ipairs(fileorder) do
			local slot = row * columns + file
			if slot <= company.maxslots then
				local bot = pool[index]
				if bot then
					newslots[slot] = bot
					bot:SetAttribute("slot", slot)
					index += 1
				else
					newslots[slot] = false
				end
			end
		end
	end

	company.slots = newslots
end

-- fillgaps: compress slots forward within each file (rear ranks move forward)
function module.fillgaps(company)
	-- compress slots forward within each file so rear ranks fill holes
--	print("formation_module.fillgaps called")
	local rows = company.rows
	local columns = math.ceil(company.maxslots / rows)
	local slots = company.slots

	local changed = true
	while changed do
		changed = false
		for file = 1, columns do
			for row = 1, rows do
				local slot = (row - 1) * columns + file
				if slot <= company.maxslots and slots[slot] == false then
					for r = row + 1, rows do
						local backslot = (r - 1) * columns + file
						if backslot <= company.maxslots and slots[backslot] and slots[backslot] ~= false then
							slots[slot] = slots[backslot]
							slots[backslot] = false
							slots[slot]:SetAttribute("slot", slot)
							changed = true
							break
						end
					end
				end
			end
		end
	end
end

-- check if a bot is in front rank (first row)
function module.is_front_rank(company, bot)
	-- check if bot slot is in front rank relative to company's rows/columns
	if not company or not bot then return false end
	local slot = bot:GetAttribute("slot")
	if not slot then return false end
	local columns = math.ceil(company.maxslots / company.rows)
	return slot <= columns
end

-- update formation: move bots to their anchored positions
function module.update_formation(company, anchor_cframe, spacing, stoptolerance)
	-- move each bot to calculated slot position relative to anchor
--	print("formation_module.update_formation called") -- ts just spamming alot
	if not company then return end
	local columns = math.ceil(company.maxslots / company.rows)
	for slot = 1, company.maxslots do
		local bot = company.slots[slot]
		if bot and bot ~= false then
			local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
			local root = bot:FindFirstChild("HumanoidRootPart")
			if humanoid and root then
				local row = math.floor((slot - 1) / columns)
				local file = ((slot - 1) % columns) + 1

				local cf = anchor_cframe * CFrame.new(
					(file - (columns + 1) / 2) * spacing.side,
					0,
					row * spacing.front + spacing.back
				)

				local target = cf.Position
				local dist = (root.Position - target).Magnitude

				if dist > stoptolerance then
					humanoid:MoveTo(target)
					bot:SetAttribute("targetx", target.X)
					bot:SetAttribute("targetz", target.Z)
				else
					-- stop movement
					pcall(function() humanoid:Move(Vector3.zero) end)
				end
			end
		end
	end
end

return module
