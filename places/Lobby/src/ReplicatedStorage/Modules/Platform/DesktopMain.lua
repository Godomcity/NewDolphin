-- 데스크톱 전용 초기화(단축키 가이드, 마우스 오버 등)
local InputMap = require(script.Parent.Parent.InputMap)

local M = {}

function M.init()
	InputMap.bindAction(
		"AbilityPrimary",
		{
			desktopKeys = { Enum.KeyCode.F }, -- 키보드 F
			-- 모바일 아이콘 지정해도 무시됨(데스크톱이므로)
		},
		function() -- onBegan
			-- print("AbilityPrimary Begin (desktop)")
		end,
		function() -- onEnded
			-- print("AbilityPrimary End (desktop)")
		end
	)
end

return M
