-- 화면마다 동일한 규칙으로 UIScale/패딩/히트존 적용
local Device = require(script.Parent.DeviceProfile)

local M = {}

-- ScreenGui에 UIScale 적용
function M.applyScreenScale(screenGui: ScreenGui)
	local pol = Device.getPolicy()
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = pol.uiScale
	uiScale.Parent = screenGui
	return uiScale
end

-- 공통 버튼 스타일(크기/패딩/라운드 등) 적용 헬퍼
function M.styleButton(btn: GuiButton)
	local pol = Device.getPolicy()
	btn.AutoButtonColor = true
	if btn:IsA("ImageButton") or btn:IsA("TextButton") then
		-- 터치/마우스 공통으로 '히트존' 확보(투명 클릭 영역)
		local hit = Instance.new("Frame")
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromOffset(pol.hitSize, pol.hitSize)
		hit.AnchorPoint = Vector2.new(0.5, 0.5)
		hit.Position = UDim2.fromScale(0.5, 0.5)
		hit.Name = "HitArea"
		hit.ZIndex = btn.ZIndex - 1
		hit.Parent = btn
	end
end

return M
