local BackpackManager = {}

local Backpack_Data = {}

function BackpackManager.SaveBackpackData(p,player,ID,Data)
	
	if not Backpack_Data[ID] then
		
		Backpack_Data[ID] = Data
		
	elseif Backpack_Data[ID] then
		
		Backpack_Data[ID] = Data
	end
	--print(Backpack_Data)

end

function BackpackManager.GetAllBackpacks(ID)
	local data = Backpack_Data[ID]
	if not data then
		--print("Not Data")
	else
		
		--print(Backpack_Data)
	end
	return data
end

return BackpackManager
