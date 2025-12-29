-- ServerScriptService/ResumeFlagBootstrap.server.lua
--!strict
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(plr: Player)
	local ok, joinData = pcall(function()
		return plr:GetJoinData()
	end)

	if not ok or typeof(joinData) ~= "table" then
		return
	end

	local td = joinData.TeleportData
	if typeof(td) ~= "table" then
		return
	end

	-- LobbyResumeBootstrap 에서 보낸 reason = "resume" 체크
	local reason = (td :: any).reason
	if reason == "resume" then
		plr:SetAttribute("IsResumeJoin", true)
		print("[ResumeFlagBootstrap]", plr.Name, "IsResumeJoin = true")
	end
end)

print("[ResumeFlagBootstrap] READY")