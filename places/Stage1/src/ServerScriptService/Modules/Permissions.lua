-- ServerScriptService/Modules/Permissions.lua
--!strict

local Permissions = {}

function Permissions.isTeacher(plr: Player): boolean
	return plr:GetAttribute("isTeacher") == true
end

function Permissions.requireTeacher(plr: Player): boolean
	if Permissions.isTeacher(plr) then
		return true
	end
	warn(("[Permissions] blocked: %s(%d)"):format(plr.Name, plr.UserId))
	return false
end

return Permissions
