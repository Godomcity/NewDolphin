-- StarterPlayerScripts/TeacherHubUI.client.lua
--!strict
-- 퀴즈 시작: 이미지 버튼 → 서버에 "Stage1 시작"만 알림
-- 실제 텔레포트는 QuizRunService(StartCohort)에서 한 번에 처리
-- 버튼 위치: {-0.01, 0}, {0.5, 0}
-- 상단 중앙 안내 문구: "선생님이 게임을 시작하기 전까지 기다리세요."

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")

local p  = Players.LocalPlayer
local pg = p:WaitForChild("PlayerGui")

-- Remotes
local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local RF_OpenStage   = Net.ensureRF("Hub_OpenStage")

-- 더 이상 여기서는 TeleportUtil, STAGE1_PLACE_ID 사용 안 함
-- 텔레포트는 전부 서버(QuizRunService)에서 처리

-- UI Root
local gui = Instance.new("ScreenGui")
gui.Name = "TeacherHubUI"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.Parent = pg

-- 안내 문구 (상단 중앙)
local notice = Instance.new("TextLabel")
notice.Name = "TopNotice"
notice.AnchorPoint = Vector2.new(0.5, 0)
notice.Position = UDim2.fromScale(0.5, 0.03)
notice.Size = UDim2.fromScale(0.7, 0.06)
notice.BackgroundTransparency = 0.25
notice.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
notice.TextColor3 = Color3.fromRGB(255, 255, 255)
notice.TextTransparency = 0
notice.Text = "선생님이 게임을 시작하기 전까지 기다려 주세요."
notice.TextScaled = true
notice.Font = Enum.Font.GothamSemibold
notice.ZIndex = 5
notice.Parent = gui

local shadow = Instance.new("UIStroke")
shadow.Thickness = 1
shadow.Color = Color3.fromRGB(0, 0, 0)
shadow.Transparency = 0.3
shadow.Parent = notice

local cornerN = Instance.new("UICorner")
cornerN.CornerRadius = UDim.new(0, 10)
cornerN.Parent = notice

-- 버튼 크기
local BTN_SIZE = UDim2.fromScale(
	(UIS.TouchEnabled and not UIS.KeyboardEnabled) and 0.20 or 0.14,
	0.08
)

-- 이미지 버튼 (좌측 중앙, X -0.01 / Y 0.5)
local btn = Instance.new("ImageButton")
btn.Name = "StartStage1"
btn.AnchorPoint = Vector2.new(0, 0.5)
btn.Position = UDim2.new(-0.01, 0, 0.5, 0)  -- 요청한 좌표
btn.Size = BTN_SIZE
btn.BackgroundTransparency = 1
btn.Image = "rbxassetid://96065503121570"
btn.ScaleType = Enum.ScaleType.Fit
btn.Visible = false
btn.Parent = gui

Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

-- PC Hover 효과
if not UIS.TouchEnabled then
	btn.MouseEnter:Connect(function()
		TweenService:Create(
			btn,
			TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(BTN_SIZE.X.Scale * 1.04, BTN_SIZE.Y.Scale * 1.04) }
		):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(
			btn,
			TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = BTN_SIZE }
		):Play()
	end)
end

-- 교사 권한일 때만 버튼 노출
local function updateRole()
	btn.Visible = (p:GetAttribute("userRole") == "ROLE_TEACHER")
end

updateRole()
p:GetAttributeChangedSignal("Role"):Connect(updateRole)

-- 클릭: 서버 알림만 보내고, 실제 텔레포트는 서버가 담당
btn.Activated:Connect(function()
	btn.Visible = false
	-- 클릭 피드백
	TweenService:Create(
		btn,
		TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(BTN_SIZE.X.Scale * 0.96, BTN_SIZE.Y.Scale * 0.96) }
	):Play()

	task.delay(0.06, function()
		TweenService:Create(
			btn,
			TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = BTN_SIZE }
		):Play()
	end)

	-- 선생님 쪽 안내 문구는 버튼 누르면 숨김 (학생들은 그대로 안내 유지)
	notice.Visible = false

	-- 서버에 Stage1 오픈 요청(비차단)
	task.spawn(function()
		local ok, err = pcall(function()
			-- 서버: Hub_OpenStage.OnServerInvoke / 또는 OnServerEvent 안에서
			--       QuizRunService.StartCohort(1, 플레이어 리스트) 호출
			return RF_OpenStage:InvokeServer(1)
		end)
		if not ok then
			warn("[TeacherHubUI] RF_OpenStage invoke failed:", err)
		end
	end)

	-- ❌ 여기서 더 이상 TeleportUtil.Go 호출하지 않음
	-- ✅ 서버 QuizRunService 가 hub_portal 컷씬 → teleportToNextPlace 로
	--    선생님 + 학생을 같은 예약코드로 Stage1에 보내 줌
end)
