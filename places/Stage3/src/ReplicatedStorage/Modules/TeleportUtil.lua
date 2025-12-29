-- ReplicatedStorage/Modules/TeleportUtil.lua
local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local REQ = Remotes:WaitForChild("Teleport_Request")
local RES = Remotes:WaitForChild("Teleport_Result")

local M = {}

function M.Go(targetPlaceId: number, opts: {}?)
	REQ:FireServer({
		targetPlaceId = targetPlaceId,
		sessionId = opts and opts.sessionId or nil,
		device    = opts and opts.device or "pc",
		reason    = opts and opts.reason or "route",
	})
end

-- 에러 UI 필요하면 이 이벤트를 구독해서 사용자에게 안내
function M.BindResult(handler)
	return RES.OnClientEvent:Connect(handler)
end

return M
