-- ServerScriptService/Modules/TeleportDataUtil.lua
--!strict

local TeleportDataUtil = {}

function TeleportDataUtil.buildBase(player: Player)
	return {
		player = {
			userRole  = player:GetAttribute("userRole"),
			isTeacher = player:GetAttribute("isTeacher") == true,
			device    = player:GetAttribute("Device"),
		},
		session = {
			id       = player:GetAttribute("sessionId"),
			roomCode = player:GetAttribute("roomCode"),
		},
	}
end

return TeleportDataUtil
