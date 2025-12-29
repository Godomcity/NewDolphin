-- ServerScriptService/SessionBootstrap.server.lua
--!strict
-- 플레이어가 텔레포트로 들어왔을 때 TeleportData.sessionId를 Player.Attribute("sessionId")로 복원

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(plr: Player)
	local sid: string? = nil
	local ok, joinData = pcall(function()
		return plr:GetJoinData()
	end)
	if ok and typeof(joinData) == "table" then
		local td = joinData.TeleportData
		if typeof(td) == "table" and typeof(td.sessionId) == "string" and #td.sessionId > 0 then
			sid = td.sessionId
		end
	end

	if not plr:GetAttribute("sessionId") and sid then
		plr:SetAttribute("sessionId", sid)
	end
end)

print("[SessionBootstrap] READY")
