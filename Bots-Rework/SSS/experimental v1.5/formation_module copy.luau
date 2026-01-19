-- formation_module (modules)
-- formation geometry, file ordering, slot packing and gap filling utilities
local module = {}

-- build_file_order: return file ordering centered (center, right, left, right2, left2...)
function module.build_file_order(columns)
-- return file ordering centered
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
	local rows = company.rows
	local columns = math.ceil(company.maxslots / rows)
	local fileorder = module.build_file_order(columns)

	local pool = {}
	for i = 1, company.maxslots do
		local bot = company.slots[i]
		if bot and bot ~= false then table.insert(pool, bot) end
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

function module.fillgaps(company)
	-- this compresses bots forward (rows) and inward (columns) without skipping empty columns
	print("formation_module.fillgaps called")

	local rows = company.rows
	local columns = math.ceil(company.maxslots / rows)
	local slots = company.slots

	-- vertical compression (pull bots forward in each file)
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

	-- horizontal compression (remove empty columns safely)
	local file = 1
	while file <= columns do
		local empty = true

		-- check if this column is completely empty
		for row = 1, rows do
			local slot = (row - 1) * columns + file
			if slot <= company.maxslots and slots[slot] and slots[slot] ~= false then
				empty = false
				break
			end
		end

		if empty then
			-- shift all columns behind this one to the left
			for f = file + 1, columns do
				for row = 1, rows do
					local from = (row - 1) * columns + f
					local to = (row - 1) * columns + (f - 1)

					if from <= company.maxslots then
						slots[to] = slots[from]
						if slots[to] and slots[to] ~= false then
							slots[to]:SetAttribute("slot", to)
						end
						slots[from] = false
					end
				end
			end

			-- do NOT increment file
			-- recheck same column index again because new data shifted in
		else
			file += 1
		end
	end
end


--[[
function module.fillgaps(company)
--	print("formation_module.fillgaps called")

	local rows = company.rows
	local columns = math.ceil(company.maxslots / rows)
	local slots = company.slots

	-- vertical compression
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

	-- horizontal compression
	for file = 1, columns do
		-- check if entire column is empty
		local empty = true
		for row = 1, rows do
			local slot = (row - 1) * columns + file
			if slot <= company.maxslots and slots[slot] and slots[slot] ~= false then
				empty = false
				break
			end
		end

		-- shift all columns behind it left
		if empty then
			for f = file + 1, columns do
				for row = 1, rows do
					local from = (row - 1) * columns + f
					local to = (row - 1) * columns + (f - 1)

					if from <= company.maxslots then
						slots[to] = slots[from]
						if slots[to] and slots[to] ~= false then
							slots[to]:SetAttribute("slot", to)
						end
						slots[from] = false
					end
				end
			end
		end
	end
end
--[[]]

-- is_front_rank: check if a bot is in front rank (first row)
function module.is_front_rank(company, bot)
	-- check if bot slot is in front rank relative to company's rows/columns
	if not company or not bot then return false end
	local slot = bot:GetAttribute("slot")
	if not slot then return false end
	local columns = math.ceil(company.maxslots / company.rows)
	return slot <= columns
end

-- update_formation: move bots to their anchored positions, use speed boost when far
function module.update_formation(company, anchor_cframe, spacing, stoptolerance)
-- move each bot to calculated slot position relative to anchor and apply distance-based speed boost
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

				-- movement with speed boost if far from slot
				if dist > stoptolerance then
					-- very far -> sprint, medium -> jog, close -> normal
					if dist > 25 then
						pcall(function() humanoid.WalkSpeed = 28 end)
					elseif dist > 12 then
						pcall(function() humanoid.WalkSpeed = 23 end)
					else
						pcall(function() humanoid.WalkSpeed = 16 end)
					end

					humanoid:MoveTo(target)
					bot:SetAttribute("targetx", target.X)
					bot:SetAttribute("targetz", target.Z)
				else
					-- stop and restore default speed
					pcall(function() humanoid.WalkSpeed = 16 end)
					pcall(function() humanoid:Move(Vector3.zero) end)
				end
			end
		end
	end
end

return module
