-- 모바일/PC 구분 + 공통 정책
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")

local M = {}

function M.isMobile()
	-- 터치 가능 && 하드키보드 의존 없음 기준
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function M.isDesktop()
	return not M.isMobile()
end

function M.platform()
	return M.isMobile() and "mobile" or "desktop"
end

-- 기기별 UI 정책(필요 시 숫자만 바꿔도 전역 반영)
M.Policy = {
	mobile = {
		uiScale   = 1.05,   -- 모바일은 약간 키움
		padding   = 10,
		hitSize   = 56,     -- 터치 최소 권장 44~56px
		fontScale = 1.0,
	},
	desktop = {
		uiScale   = 1.0,
		padding   = 8,
		hitSize   = 40,
		fontScale = 1.0,
	},
}

-- 현재 플랫폼 정책 반환
function M.getPolicy()
	return M.isMobile() and M.Policy.mobile or M.Policy.desktop
end

-- 노치/세이프영역 여백(px) 추출(필요 시 사용)
function M.getSafeInset()
	local topLeft, bottomRight = GuiService:GetGuiInset()
	return {
		top    = topLeft.Y,
		left   = topLeft.X,
		bottom = bottomRight.Y,
		right  = bottomRight.X,
	}
end

return M
