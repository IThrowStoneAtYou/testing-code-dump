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

-- sets the Rank attribute based on the bot's slot position
function module.apply_rank_from_slot(company, bot)
	-- determine which row the bot belongs to and store it as Rank
	if not company or not bot then return end

	local slot = bot:GetAttribute("slot")
	if not slot then return end

	local columns = math.ceil(company.maxslots / company.rows)
	local row = math.floor((slot - 1) / columns)

	-- rank is row index + 1 (front rank = 1)
	bot:SetAttribute("Rank", row + 1)
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

					-- update Rank after slot change
					module.apply_rank_from_slot(company, bot)

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
	local rows = company.rows
	local columns = math.ceil(company.maxslots / rows)
	local slots = company.slots

	-- convert destroyed bots to false
	for i = 1, #slots do
		if slots[i] and (slots[i] == false or not slots[i].Parent) then
			slots[i] = false
		end
	end

	-- vertical compression: pull bots forward
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
							module.apply_rank_from_slot(company, slots[slot])

							changed = true
							break
						end
					end
				end
			end
		end
	end

	-- horizontal compression: shift empty columns left
	local file = 1
	while file <= columns do
		local empty = true
		for row = 1, rows do
			local slot = (row - 1) * columns + file
			if slot <= company.maxslots and slots[slot] and slots[slot] ~= false then
				empty = false
				break
			end
		end

		if empty then
			for f = file + 1, columns do
				for row = 1, rows do
					local from = (row - 1) * columns + f
					local to = (row - 1) * columns + (f - 1)
					if from <= company.maxslots then
						slots[to] = slots[from]
						if slots[to] and slots[to] ~= false then
							slots[to]:SetAttribute("slot", to)
							module.apply_rank_from_slot(company, slots[to])
						end
						slots[from] = false
					end
				end
			end
			columns -= 1
		else
			file += 1
		end
	end
end

-- is_front_rank: check if a bot is in front rank (first row)
function module.is_front_rank(company, bot)
	-- check if bot slot is in front rank relative to company's rows/columns
	if not company or not bot then return false end
	local slot = bot:GetAttribute("slot")
	if not slot then return false end
	local columns = math.ceil(company.maxslots / company.rows)
	return slot <= columns
end

function module.update_formation(company, anchor_cframe, spacing, stoptolerance)
	-- moves bots into formation starting from center file and spreading outward

	if not company then return end

	local rows = company.rows
	local columns = math.ceil(company.maxslots / rows)
	local center_file = math.ceil(columns / 2)

	-- initialize reform timer ONCE per reform
	if not company._form_start then
		company._form_start = os.clock()
	end

	local elapsed = os.clock() - company._form_start

	for slot = 1, company.maxslots do
		local bot = company.slots[slot]
		if bot and bot ~= false then
			local humanoid = bot:FindFirstChildWhichIsA("Humanoid")
			local root = bot:FindFirstChild("HumanoidRootPart")
			if humanoid and root then

				-- compute row + file
				local row = math.floor((slot - 1) / columns)
				local file = ((slot - 1) % columns) + 1

				-- how far this file is from center
				local file_dist = math.abs(file - center_file)

				-- strict entry delay (controls spread speed)
				local entry_delay = file_dist * 0.1

				-- not allowed to move yet
				if elapsed < entry_delay then
					humanoid:Move(Vector3.zero)
					humanoid.WalkSpeed = 16
					continue
				end

				-- compute target position
				local cf = anchor_cframe * CFrame.new(
					(file - center_file) * spacing.side,
					0,
					row * spacing.front + spacing.back
				)

				local target = cf.Position
				local dist = (root.Position - target).Magnitude

				-- movement
				if dist > stoptolerance then
					if dist > 30 then
						humanoid.WalkSpeed = 30
					elseif dist > 15 then
						humanoid.WalkSpeed = 24
					else
						humanoid.WalkSpeed = 16
					end

					humanoid:MoveTo(target)
				else
					humanoid:Move(Vector3.zero)
					humanoid.WalkSpeed = 16
				end
			end
		end
	end
end

return module
