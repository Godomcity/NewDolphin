-- ReplicatedStorage/Modules/UI/Toast.lua
-- 씬에 배치된 CircleIcon(+Confirm)만 사용해 에러 패널을 표시
-- 상단 토스트(show) 기능은 그대로 두고, 패널(panel)은 정적 노드 이용

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UIS = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local Toast = {}

-- ===== 이미지 에셋(사용자 제공) =====
local DEFAULT_ASSETS = {
	invalid_code = { icon = "rbxassetid://111991704036207", cta = "rbxassetid://100750247838405" },
	token_expired = { icon = "rbxassetid://81850713765262",  cta = "rbxassetid://108197149058789" },
	server_full   = { icon = "rbxassetid://73999881029519",  cta = "rbxassetid://123067039264815" },
	network_error = { icon = "rbxassetid://78858733698151",  cta = "rbxassetid://100750247838405" },
	common = { close = "rbxassetid://0", shadow = "rbxassetid://1316045217" },
}
local TITLES = {
	invalid_code  = "입장코드 오류",
	token_expired = "토큰 만료",
	server_full   = "정원 초과",
	network_error = "네트워크 오류",
}
local TITLE_COLOR = Color3.fromRGB(40,40,40)

local assets = table.clone(DEFAULT_ASSETS)
local QUEUE, showing = {}, false

-- ===== util =====
local function isMobile() return UIS.TouchEnabled and not UIS.KeyboardEnabled end
local function getPlayerGui()
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	if not pg then pg = Instance.new("PlayerGui"); pg.Parent = LP end
	return pg
end
local function getRootGui(name)
	local pg = getPlayerGui()
	local root = pg:FindFirstChild(name or "ToastGui")
	if not root then
		root = Instance.new("ScreenGui")
		root.Name = name or "ToastGui"
		root.IgnoreGuiInset = true
		root.ResetOnSpawn = false
		root.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		root.DisplayOrder = 10000
		root.Parent = pg
	end
	return root
end

-- ===== A) 상단 아이콘 토스트(자동 사라짐) - 기존 유지 =====
local function animateOut(frame, toY)
	return TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, toY or -20),
		BackgroundTransparency = 1,
	})
end
local function animateIn(frame, fromY)
	frame.Visible = true
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.new(0.5, 0, 0, fromY or -20)
	TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 0,
	}):Play()
end

local function createToastFrame(root, kind, message, opts)
	local safeTop = GuiService:GetGuiInset().Y
	local padTop = 14 + (safeTop > 0 and safeTop or 12)

	local container = root:FindFirstChild("Container") :: Frame
	if not container then
		container = Instance.new("Frame")
		container.Name = "Container"
		container.Size = UDim2.fromScale(1, 0)
		container.BackgroundTransparency = 1
		container.Position = UDim2.fromOffset(0, padTop)
		container.Parent = root

		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 8)
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.VerticalAlignment = Enum.VerticalAlignment.Top
		lay.Parent = container
	end

	local w = isMobile() and 0.94 or 0.6
	local frame = Instance.new("Frame")
	frame.Name = "Toast_"..kind
	frame.Size = UDim2.fromScale(w, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = Color3.fromRGB(255,255,255)
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Parent = container

	Instance.new("UICorner", frame).CornerRadius = UDim.new(0,12)
	local stroke = Instance.new("UIStroke", frame); stroke.Thickness = 2; stroke.Color = Color3.fromRGB(235,235,235)
	local pad = Instance.new("UIPadding", frame)
	pad.PaddingTop    = UDim.new(0, isMobile() and 10 or 8)
	pad.PaddingBottom = UDim.new(0, isMobile() and 10 or 8)
	pad.PaddingLeft   = UDim.new(0, 10)
	pad.PaddingRight  = UDim.new(0, 10)

	local grid = Instance.new("UIGridLayout", frame)
	grid.CellPadding = UDim2.new(0,8,0,4)
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.FillDirectionMaxCells = 3
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.CellSize = UDim2.new(0,48,0,48)

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(48,48)
	icon.Image = (assets[kind] and assets[kind].icon) or DEFAULT_ASSETS[kind].icon
	icon.Parent = frame

	local textWrap = Instance.new("Frame")
	textWrap.BackgroundTransparency = 1
	textWrap.Size = UDim2.new(1, -(48 + 48 + 8*3), 1, 0)
	textWrap.LayoutOrder = 2
	textWrap.Parent = frame

	local tbLay = Instance.new("UIListLayout", textWrap)
	tbLay.Padding = UDim.new(0,2)
	tbLay.FillDirection = Enum.FillDirection.Vertical
	tbLay.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tbLay.VerticalAlignment = Enum.VerticalAlignment.Center

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1,0,0,isMobile() and 20 or 18)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Font = Enum.Font.GothamBold
	title.TextSize = isMobile() and 18 or 16
	title.TextColor3 = TITLE_COLOR
	title.Text = (TITLES[kind] or "알림")
	title.Parent = textWrap

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1,0,0,isMobile() and 24 or 22)
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Font = Enum.Font.Gotham
	body.TextWrapped = true
	body.TextTruncate = Enum.TextTruncate.AtEnd
	body.TextSize = isMobile() and 16 or 14
	body.TextColor3 = Color3.fromRGB(70,70,70)
	body.Text = message or ""
	body.Parent = textWrap

	local actionBtn = Instance.new("ImageButton")
	actionBtn.BackgroundTransparency = 1
	actionBtn.Size = UDim2.fromOffset(48,48)
	actionBtn.LayoutOrder = 3
	actionBtn.Image = (assets[kind] and assets[kind].cta) or DEFAULT_ASSETS[kind].cta
	actionBtn.Parent = frame
	actionBtn.Activated:Connect(function()
		local tw = animateOut(frame); tw:Play(); tw.Completed:Wait(); frame:Destroy()
	end)

	if assets.common.shadow and assets.common.shadow ~= "" then
		local sh = Instance.new("ImageLabel")
		sh.BackgroundTransparency = 1; sh.ZIndex = 0; sh.Image = assets.common.shadow
		sh.ScaleType = Enum.ScaleType.Slice; sh.SliceCenter = Rect.new(10,10,118,118)
		sh.Size = UDim2.new(1,24,1,24); sh.Position = UDim2.new(0,-12,0,-8); sh.ImageTransparency = 0.25
		sh.Parent = frame
	end

	animateIn(frame, -20)
	task.delay((opts and opts.duration) or 3.2, function()
		if frame and frame.Parent then local tw = animateOut(frame,-20); tw:Play(); tw.Completed:Wait(); if frame then frame:Destroy() end end
	end)
end

-- ===== B) 패널(정적 노드 사용) =====
local Static = { circle=nil, confirm=nil, confirmConn=nil, origZ=nil }

-- 바인딩: 외부에서 명시적으로 넘겨줄 수도 있음
function Toast.bindStatic(circleIcon: Instance?, confirmBtn: Instance?)
	Static.circle = circleIcon
	Static.confirm = confirmBtn
	-- 기본적으로 숨김
	if Static.circle then Static.circle.Visible = false end
end

-- 내부 자동 검색(EntryScreen > Background > Wrapper > CircleIcon > Confirm)
local function autoBindStatic()
	if Static.circle and Static.confirm then return true end
	local pg = getPlayerGui()
	local entry = pg:FindFirstChild("EntryScreen")
	if not entry then return false end
	local wrapper = entry:FindFirstChild("Wrapper", true)
	if not wrapper then return false end
	local entryCard = wrapper:FindFirstChild("EntryCard", true)
	if not entryCard then return false end
	local circle = entryCard:FindFirstChild("CircleIcon")
	if not circle then return false end
	local confirm = circle:FindFirstChild("Confirm")
	if not confirm then return false end
	Static.circle, Static.confirm = circle, confirm
	Static.circle.Visible = false
	return true
end

-- 패널 본체(정적 사용)
local function showStaticPanel(kind, opts)
	opts = opts or {}
	if not (Static.circle and Static.confirm) then
		if not autoBindStatic() then
			warn("[Toast] CircleIcon/Confirm 정적 노드를 찾지 못했어요. Wrapper 아래에 배치했는지 확인하세요.")
			return Instance.new("BindableEvent").Event
		end
	end

	local circle, confirm = Static.circle, Static.confirm

	-- 이미지 교체
	circle.Image = (assets[kind] and assets[kind].icon) or DEFAULT_ASSETS[kind].icon
	if confirm:IsA("ImageButton") then
		confirm.Image = (assets[kind] and assets[kind].cta) or DEFAULT_ASSETS[kind].cta
	end

	-- ZIndex 올려서 항상 위에 보이도록
	Static.origZ = circle.ZIndex
	circle.ZIndex = math.max(Static.origZ or 1, 100)
	if confirm.ZIndex <= circle.ZIndex then confirm.ZIndex = circle.ZIndex + 1 end

	-- 표시
	circle.Visible = true
	circle.Active = true

	-- 닫기 처리
	local done = Instance.new("BindableEvent")
	if Static.confirmConn then Static.confirmConn:Disconnect() end
	Static.confirmConn = confirm.Activated:Connect(function()
		if typeof(opts.onConfirm) == "function" then pcall(opts.onConfirm) end
		circle.Visible = false
		circle.Active = false
		if Static.origZ then circle.ZIndex = Static.origZ end
		done:Fire(); done:Destroy()
	end)

	-- 자동 닫기 옵션
	if opts.autoDismiss then
		task.delay(opts.duration or 3.0, function()
			if circle and circle.Visible then
				circle.Visible = false
				circle.Active = false
				if Static.origZ then circle.ZIndex = Static.origZ end
				done:Fire(); done:Destroy()
			end
		end)
	end

	return done.Event
end

-- 큐 처리(패널/토스트 공용)
local function pumpQueue()
	if showing then return end
	showing = true
	while #QUEUE > 0 do
		local item = table.remove(QUEUE, 1)
		if item.mode == "toast" then
			createToastFrame(getRootGui("ToastGui"), item.kind, item.message, item.opts)
			task.wait(0.25 + ((item.opts and item.opts.duration) or 3.2))
		else
			local ev = showStaticPanel(item.kind, item.opts)
			ev:Wait()
			task.wait(0.1)
		end
	end
	showing = false
end

-- ===== Public API =====
function Toast.configure(map)
	for k, v in pairs(map or {}) do
		if typeof(v) == "table" then
			assets[k] = assets[k] or {}
			for kk, vv in pairs(v) do assets[k][kk] = vv end
		else
			assets[k] = v
		end
	end
end

-- 상단 토스트
function Toast.show(kind, message, opts) table.insert(QUEUE, {mode="toast", kind=kind, message=message, opts=opts}); pumpQueue() end
function Toast.invalidCode(message, opts)   Toast.show("invalid_code",  message, opts) end
function Toast.tokenExpired(message, opts)  Toast.show("token_expired", message, opts) end
function Toast.serverFull(message, opts)    Toast.show("server_full",   message, opts) end
function Toast.networkError(message, opts)  Toast.show("network_error", message, opts) end

-- 정적 패널
function Toast.panel(kind, _title, _body, opts) table.insert(QUEUE, {mode="panel", kind=kind, opts=opts}); pumpQueue() end

function Toast.dismissAll()
	-- 정적 패널 숨기기
	if Static.circle then Static.circle.Visible = false end
	for _, guiName in ipairs({"ToastGui"}) do
		local root = getRootGui(guiName)
		if root then for _, child in ipairs(root:GetChildren()) do child:Destroy() end end
	end
	table.clear(QUEUE); showing = false
end

return Toast
