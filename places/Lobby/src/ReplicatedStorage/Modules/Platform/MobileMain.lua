-- 모바일 전용 초기화(큰 버튼/간격, 터치 가이드 등)
local Device   = require(script.Parent.Parent.DeviceProfile)
local UiPolicy = require(script.Parent.Parent.UiPolicy)
local InputMap = require(script.Parent.Parent.InputMap)

local M = {}

function M.init()
	-- 예시: "AbilityPrimary" 액션을 모바일 버튼으로 노출
	InputMap.bindAction(
		"AbilityPrimary",
		{
			mobileIcon = "rbxassetid://125015865569530",
			position   = UDim2.fromScale(0.9, 0.9),
			size       = UDim2.fromOffset(84, 84),
			desktopKeys = { Enum.KeyCode.F }, -- 데스크톱도 같이 지원(테스트 겸)
		},
		function() -- onBegan
			-- 예: 차지 시작/대기
			-- print("AbilityPrimary Begin (mobile)")
		end,
		function() -- onEnded
			-- 예: 스킬 발동
			-- print("AbilityPrimary End (mobile)")
		end
	)
end

return M
