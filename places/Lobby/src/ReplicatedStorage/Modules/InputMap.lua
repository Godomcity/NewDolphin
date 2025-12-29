-- "하나의 액션"을 PC(키보드/마우스)와 모바일(터치 버튼)로 동시에 바인딩
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")

local Device   = require(script.Parent.DeviceProfile)
local UiPolicy = require(script.Parent.UiPolicy)

local M = {}

local gui -- 모바일 온스크린 버튼 컨테이너(필요 시 1회 생성)
local function getGui()
	if gui and gui.Parent then return gui end
	gui = Instance.new("ScreenGui")
	gui.Name = "InputGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	UiPolicy.applyScreenScale(gui)
	return gui
end

-- 단일 액션 바인딩(이름, 옵션, 콜백들)
-- opts = { desktopKeys = {Enum.KeyCode.F}, mobileIcon = "rbxassetid://...", position = UDim2, size = UDim2 }
function M.bindAction(name: string, opts: {}, onBegan, onEnded)
	opts = opts or {}
	local isMobile = Device.isMobile()

	-- Desktop: 키 바인딩
	if Device.isDesktop() then
		local keys = opts.desktopKeys or { Enum.KeyCode.F }
		ContextActionService:BindAction(
			name,
			function(_, state)
				if state == Enum.UserInputState.Begin then
					if onBegan then onBegan() end
				elseif state == Enum.UserInputState.End then
					if onEnded then onEnded() end
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			table.unpack(keys)
		)
	end

	-- Mobile: 온스크린 버튼
	if isMobile then
		local root = getGui()
		local btn = Instance.new("ImageButton")
		btn.Name = name .. "_Button"
		btn.BackgroundTransparency = 1
		btn.Size = opts.size or UDim2.fromOffset(72, 72)
		btn.AnchorPoint = Vector2.new(1, 1)
		btn.Position = opts.position or UDim2.fromScale(0.95, 0.92)
		btn.Image = opts.mobileIcon or "rbxassetid://133227522295154"
		btn.Parent = root
		UiPolicy.styleButton(btn)

		btn.MouseButton1Down:Connect(function()
			if onBegan then onBegan() end
		end)
		btn.MouseButton1Up:Connect(function()
			if onEnded then onEnded() end
		end)
		btn.TouchLongPress:Connect(function(_, state)
			-- 드래그 유지 등 확장 시 활용
			if state == Enum.LongPressState.End and onEnded then onEnded() end
		end)
	end
end

function M.unbindAction(name: string)
	pcall(function() ContextActionService:UnbindAction(name) end)
	-- 모바일 버튼 제거
	if gui and gui.Parent then
		local b = gui:FindFirstChild(name .. "_Button")
		if b then b:Destroy() end
	end
end

return M
