-- StarterPlayerScripts/QuizHUD.client.lua
-- 상단 진행 HUD: "정화 X/10" + [■■■□|□□□□□□] (4/10 마커)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local RE_Progress = Net.ensureRE("QuizRun_Progress")

local p = Players.LocalPlayer
local pg = p:WaitForChild("PlayerGui")
-- HUD 생성
local gui = Instance.new("ScreenGui")
gui.Name = "QuizHUD"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pg

-- 컨테이너
local wrap = Instance.new("Frame")
wrap.BackgroundTransparency = 1
wrap.Size = UDim2.fromScale(1, 0.12)
wrap.Position = UDim2.fromScale(0, 0)
wrap.Parent = gui

-- 라벨
local label = Instance.new("TextLabel")
label.BackgroundTransparency = 1
label.Text = "정화 0/10"
label.Font = Enum.Font.GothamBold
label.TextScaled = true
label.TextColor3 = Color3.fromRGB(250, 250, 250)
label.Size = UDim2.fromScale(0.3, 0.5)
label.Position = UDim2.fromScale(0.02, 0.1)
label.Parent = wrap

-- 진행 바
local bar = Instance.new("Frame")
bar.BackgroundTransparency = 0.15
bar.BackgroundColor3 = Color3.fromRGB(255,255,255)
bar.Size = UDim2.fromScale(UIS.TouchEnabled and not UIS.KeyboardEnabled and 0.86 or 0.6, 0.28)
bar.Position = UDim2.fromScale(0.02, 0.62)
bar.Parent = wrap
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)

-- 내부 10칸
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Left
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Padding = UDim.new(0, 4)
list.Parent = bar

local cells = {}
for i=1,10 do
	local cell = Instance.new("Frame")
	cell.Name = "Cell"..i
	cell.BackgroundColor3 = Color3.fromRGB(30, 180, 250)
	cell.BackgroundTransparency = 0.75
	cell.Size = UDim2.new(1/10, -4, 1, -8)
	cell.Position = UDim2.new(0,0,0,4)
	cell.Parent = bar
	Instance.new("UICorner", cell).CornerRadius = UDim.new(0,6)
	cells[i] = cell
end

-- 4/10 마커 (작은 역삼각형 느낌)
local marker = Instance.new("Frame")
marker.Size = UDim2.new(1/10, -4, 0, 8)
marker.BackgroundTransparency = 1
marker.Parent = bar

local markTri = Instance.new("Frame")
markTri.Size = UDim2.new(0, 10, 0, 10)
markTri.AnchorPoint = Vector2.new(0.5, 1)
markTri.Position = UDim2.new(0.5, 0, 0, 0)
markTri.BackgroundColor3 = Color3.fromRGB(255, 200, 60)
markTri.Rotation = 45 -- 다이아몬드 → 역삼각 느낌
markTri.Parent = marker

local function placeMarker(idx)
	idx = math.clamp(idx, 1, 10)
	-- idx 셀의 x 오프셋 계산: UIListLayout 패딩 고려해서 단순히 Position.X.Scale로 배치
	local scalePer = 1/10
	marker.Position = UDim2.new(scalePer*(idx-1), (idx-1)*(-4), 0, -8)
end

placeMarker(4)

-- 업데이트
local function updateHUD(data)
	if not data then return end
	local cleared, total, mark = data.cleared or 0, data.total or 10, data.mark or 4
	label.Text = string.format("정화 %d/%d", cleared, total)

	for i=1,10 do
		local cell = cells[i]
		if cell then
			if i <= cleared then
				cell.BackgroundTransparency = 0.1
			else
				cell.BackgroundTransparency = 0.75
			end
		end
	end
	placeMarker(mark)
end

RE_Progress.OnClientEvent:Connect(updateHUD)
