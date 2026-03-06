local Data_Player = {}

local Pockets_Amount = 7

function Data_Player.AddItem(player,add_item,add_amount,ID) 
	if not Data_Player[player.UserId] then
		
		Data_Player[player.UserId] = {
			Hotbars = {
				Hotbar1 = {empty = true},
				Hotbar2 = {empty = true},
				Hotbar3 = {empty = true},
				Hotbar4 = {empty = true}
			},
			Pockets = {},
			Backpack = {},
			Armor = {
				Head = {empty = true},
				Mask = {empty = true},
				Body = {empty = true},
				Pants = {empty = true},
				Arm = {empty = true},
				Backpack = {empty = true}
			},
			Health = 100
		}
		
		
		for i = 1, Pockets_Amount do
			Data_Player[player.UserId].Pockets["Pocket"..i] = {empty = true}
		end
	end
	
	if add_item then
		local Pockets = Data_Player[player.UserId].Pockets
		local Backpack = Data_Player[player.UserId].Backpack
		Filter_Data(add_item,add_amount,Pockets,Backpack,player,ID)
	end
end

function Filter_Data(add_item, add_amount, Pockets,Backpack,player,ID)
	
	local function Hash(input)
		return string.gsub(game:GetService("HttpService"):GenerateGUID(false), "-", "")
	end
	
	
	-- จัดเรียง Pockets ตามชื่อ (เช่น Pocket1, Pocket2, ...)
	local sortedKeys = {}
	for key in pairs(Pockets) do
		table.insert(sortedKeys, key)
	end

	table.sort(sortedKeys, function(a, b)
		local numA = tonumber(a:match("%d+")) -- ดึงตัวเลขจากชื่อ เช่น "Pocket1" จะได้ 1
		local numB = tonumber(b:match("%d+"))
		return numA < numB -- เรียงจากน้อยไปมาก
	end)

	-- วนลูปตามลำดับที่จัดเรียง
	for _, key in ipairs(sortedKeys) do
		local data = Pockets[key]
		if add_amount == 0 then
			break
		end

		-- ถ้ามีไอเท็มชนิดเดียวกันและยังไม่เต็ม
		if not data.empty and data.id == add_item.id and data.amount < add_item.maxstack then
			local space_left = add_item.maxstack - data.amount
			local to_add = math.min(space_left, add_amount)

			data.amount = data.amount + to_add
			add_amount = add_amount - to_add
		elseif add_amount > 0 and data.empty then
			print(key) -- พิมพ์ชื่อช่อง เช่น Pocket1, Pocket2, ...
			if add_item.class == "Backpack" then
				data.id = add_item.id
				data.name = add_item.name
				data.amount = to_add
				data.image = add_item.image
				data.maxstack = add_item.maxstack
				data.class = add_item.class
				data.slot = add_item.slot
				data.Owner = player.UserId
				data.health = add_item.health
				data.empty = false
				if ID then
					data.Backpack_ID = ID
				else
					data.Backpack_ID = Hash(os.time() .. math.random())
				end
			end
			-- ถ้าช่องว่างและยังมีจำนวนเหลือ
			local to_add = math.min(add_item.maxstack, add_amount)

			data.id = add_item.id
			data.name = add_item.name
			data.amount = to_add
			data.image = add_item.image
			data.maxstack = add_item.maxstack
			data.class = add_item.class
			data.slot = add_item.slot
			data.Owner = player.UserId
			data.health = add_item.health
			data.empty = false
			add_amount = add_amount - to_add
		end
	end

	if add_amount > 0 then
		if next(Backpack) then
			for _, data in pairs(Backpack) do
				if add_amount == 0 then
					break
				end

				-- ถ้ามีไอเท็มชนิดเดียวกันและยังไม่เต็ม
				if not data.empty and data.id == add_item.id and data.amount < add_item.maxstack then
					local space_left = add_item.maxstack - data.amount
					local to_add = math.min(space_left, add_amount)

					data.amount = data.amount + to_add
					add_amount = add_amount - to_add
				elseif add_amount > 0 and data.empty and add_item.class ~= "Backpack" then
					-- ถ้าช่องว่างและยังมีจำนวนเหลือ
					local to_add = math.min(add_item.maxstack, add_amount)

					data.id = add_item.id
					data.name = add_item.name
					data.amount = to_add
					data.image = add_item.image
					data.maxstack = add_item.maxstack
					data.class = add_item.class
					data.health = add_item.health
					data.empty = false
					add_amount = add_amount - to_add
				else
					print("PocketFull")
				end
			end
		else
			warn("Not enough space in inventory! Remaining: " .. add_amount)
		end
	end
end
return Data_Player
