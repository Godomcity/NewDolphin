-- ServerScriptService/TeleportOnRequest.server.lua

--!strict
-- ⚠️ Deprecated: TeleportRouter + SessionRouter 로 대체됨
-- 이 스크립트는 더 이상 텔레포트를 수행하지 않는다.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	return
end

local RE_TeleportRequest = Remotes:FindFirstChild("Teleport_Request")
if not RE_TeleportRequest or not RE_TeleportRequest:IsA("RemoteEvent") then
	return
end

RE_TeleportRequest.OnServerEvent:Connect(function(plr, payload)
	warn(("[TeleportOnRequest] DEPRECATED handler called from %s, ignore."):format(plr.Name))
	-- 아무 것도 하지 않음. 실제 텔레포트는 TeleportRouter.server.lua 에서 처리.
end)

print("[TeleportOnRequest] DEPRECATED (use TeleportRouter instead)")
