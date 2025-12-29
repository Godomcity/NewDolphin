-- 클라이언트 부트: 플랫폼 라우팅
local RS = game:GetService("ReplicatedStorage")

local Device = require(RS.Modules.DeviceProfile)

local platform = Device.platform()
if platform == "mobile" then
	require(RS.Modules.Platform.MobileMain).init()
else
	require(RS.Modules.Platform.DesktopMain).init()
end

-- (선택) 공통: 서버 프로필 프리패치/네트워크 초기화 등은 여기서 진행
-- local Network = require(RS.Modules.Network)
-- local profile = Network.invokeServer("RF_GetProfile")
