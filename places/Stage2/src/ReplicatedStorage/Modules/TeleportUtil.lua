-- ReplicatedStorage/Modules/TeleportUtil.lua
-- 클라이언트 공통 텔레포트 헬퍼
-- 사용 예시:
--   local TeleportUtil = require(RS.Modules.TeleportUtil)
--   TeleportUtil.Go(76543127078033, { reason = "stage_clear" })

local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:WaitForChild("Remotes")
local REQ = Remotes:WaitForChild("Teleport_Request")
local RES = Remotes:WaitForChild("Teleport_Result")

-- (선택) 디바이스 판별을 DeviceProfile에 통일하고 싶으면 사용
local DeviceProfile = RS:FindFirstChild("Modules")
	and RS.Modules:FindFirstChild("DeviceProfile")

local M = {}

local function guessDevice(): string
	if DeviceProfile then
		local ok, platform = pcall(function()
			local Mod = require(DeviceProfile)
			return Mod.platform and Mod.platform() or (Mod.isMobile and (Mod.isMobile() and "mobile" or "desktop") or "pc")
		end)
		if ok and type(platform) == "string" then
			if platform == "mobile" then return "mobile" end
			return "pc"
		end
	end

	-- Fallback: 간단 판별
	local UIS = game:GetService("UserInputService")
	if UIS.TouchEnabled and not UIS.KeyboardEnabled then
		return "mobile"
	end
	return "pc"
end

-- 공통 텔레포트 호출
-- opts:
--   sessionId (선택): 없으면 서버가 Player.Attribute("sessionId")에서 찾음
--   device    (선택): "mobile"|"pc" (기본: 자동 추론)
--   reason    (선택): "route" 등 추적용 문자열
--   meta      (선택): 추가 데이터 테이블 (서버에서 payload.meta로 수신 가능)
function M.Go(targetPlaceId: number, opts: {}?)
	opts = opts or {}

	local payload: {[string]: any} = {
		targetPlaceId = targetPlaceId,
		sessionId     = opts.sessionId,
		device        = opts.device or guessDevice(),
		reason        = opts.reason or "route",
	}

	if opts.meta ~= nil then
		payload.meta = opts.meta
	end

	REQ:FireServer(payload)
end

-- 텔레포트 결과 핸들러 바인딩 (에러 UI 등)
-- handler(resultTable)
--   resultTable 예시:
--     { ok=false, code="missing_sessionId", msg="..." }
function M.BindResult(handler: (any) -> ()): RBXScriptConnection
	return RES.OnClientEvent:Connect(handler)
end

return M
