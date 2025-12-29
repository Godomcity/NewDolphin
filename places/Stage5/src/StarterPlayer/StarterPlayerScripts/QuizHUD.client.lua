-- StarterPlayerScripts/QuizHUD.lua
--!strict
-- ReplicatedStorage.QuizHudBus (BindableEvent)를 받아서
-- HUDGui (Frame/BackGround/BarBackGround/Bar, ProgressText)를 업데이트
-- - 정답: 초록 화면 플래시 + 가운데 동그라미 링 연출
-- - 오답: 빨간 화면 플래시
-- - Bar 는 X 스케일만 늘어나고, Y 스케일은 0.4 고정

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local StarterGuiService = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local LP = Players.LocalPlayer

type UIRefs = {
	gui: ScreenGui,
	frame: Frame,
	bg: Frame,
	barBG: Frame,
	bar: Frame,
	txt: TextLabel,
}

local TWEEN_FILL              = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_SCREEN_IN_WRONG   = TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TWEEN_SCREEN_OUT_WRONG  = TweenInfo.new(0.20, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TWEEN_SCREEN_IN_CORRECT  = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local TWEEN_SCREEN_OUT_CORRECT = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local ui: UIRefs? = nil
local totalQuestions = 0
local curSolved = 0
local flashBusy = false

-- ========= HUDGui 구조 해석 =========
local function buildUIRefs(gui: ScreenGui): UIRefs?
	-- HUDGui 안 어디에 있어도 되게 재귀 검색
	local frame = gui:FindFirstChild("Frame", true) :: Frame?
	if not frame then return nil end

	-- BackGround / BarBackGround / Bar / ProgressText 를 이름 기준으로 찾는다
	local bg    = frame:FindFirstChild("BackGround", true) :: Frame?
	local barBG = bg and bg:FindFirstChild("BarBackGround", true) :: Frame?
	local bar   = barBG and barBG:FindFirstChild("Bar", true) :: Frame?
	local txt   = frame:FindFirstChild("ProgressText", true) :: TextLabel?

	if frame and bg and barBG and bar and txt then
		return {
			gui   = gui,
			frame = frame,
			bg    = bg,
			barBG = barBG,
			bar   = bar,
			txt   = txt,
		}
	end

	return nil
end

-- ========= UI 보장 =========
local function ensureUI(): UIRefs?
	if ui then return ui end

	local pg = LP:WaitForChild("PlayerGui")

	local playerGuiHUD = pg:FindFirstChild("HUDGui") :: ScreenGui?
	if playerGuiHUD then
		ui = buildUIRefs(playerGuiHUD)
		if not ui then
			warn("[QuizHUD] PlayerGui.HUDGui 구조가 달라 StarterGui 템플릿으로 교체합니다.")
			playerGuiHUD:Destroy()
			ui = nil
		end
	end

	if not ui then
		local template = StarterGuiService:FindFirstChild("HUDGui")
		if template and template:IsA("ScreenGui") then
			local clone = template:Clone()
			clone.ResetOnSpawn = false
			clone.Parent = pg
			ui = buildUIRefs(clone)
		end
	end

	if not ui then
		warn("[QuizHUD] HUDGui 구조를 찾지 못했습니다. HUDGui/Frame/BackGround/BarBackGround/Bar, ProgressText 를 확인하세요.")
		return nil
	end

	-- 진행 텍스트를 플래시 프레임보다 위로 올리기
	ui.txt.ZIndex = 42  -- Overlay가 40이니까 이것보다 크게

	return ui
end

-- ========= 전체 화면 플래시 =========
local function getOrCreateFlashOverlay(): Frame?
	local u = ensureUI(); if not u then return nil end
	local gui = u.gui

	local overlay = gui:FindFirstChild("FlashOverlay")
	if overlay and overlay:IsA("Frame") then
		return overlay :: Frame
	end

	overlay = Instance.new("Frame")
	overlay.Name = "FlashOverlay"
	overlay.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 40
	overlay.Visible = true
	overlay.Parent = gui

	return overlay :: Frame
end

-- ========= 정답 동그라미 링 =========
local function getOrCreateResultRing(): Frame?
	local u = ensureUI(); if not u then return nil end
	local gui = u.gui

	local ring = gui:FindFirstChild("ResultRing")
	if ring and ring:IsA("Frame") then
		return ring :: Frame
	end

	ring = Instance.new("Frame")
	ring.Name = "ResultRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.25, 0.25) -- 기본 크기
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 41
	ring.Visible = false
	ring.Parent = gui

	-- ★ 완전 동그라미 유지
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = ring

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ring

	-- ★ 빨간 링
	local stroke = Instance.new("UIStroke")
	stroke.Parent = ring
	stroke.Thickness = 30          -- 두께(원하면 조절)
	stroke.Color = Color3.fromRGB(255, 0, 0)
	stroke.Transparency = 1

	-- 스케일 애니메이션용 UIScale
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = ring

	return ring :: Frame
end


local function playCorrectRing()
	local ring = getOrCreateResultRing()
	if not ring then return end

	local stroke = ring:FindFirstChildOfClass("UIStroke")
	local scale = ring:FindFirstChildOfClass("UIScale")

	if not stroke or not scale then return end

	-- 초기 상태 리셋
	ring.Visible = true
	stroke.Transparency = 0
	scale.Scale = 0.6

	-- 안쪽에서 밖으로 커지면서 사라지는 연출
	local growInfo = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

	local growTween = TweenService:Create(scale, growInfo, { Scale = 1.2 })
	local fadeTween = TweenService:Create(stroke, fadeInfo, { Transparency = 1 })

	growTween:Play()
	growTween.Completed:Connect(function()
		fadeTween:Play()
		fadeTween.Completed:Connect(function()
			ring.Visible = false
		end)
	end)
end

local function flashScreen(color: Color3, isCorrect: boolean?)
	if flashBusy then return end
	local overlay = getOrCreateFlashOverlay()
	if not overlay then return end

	flashBusy = true
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 1

	local tInInfo  = isCorrect and TWEEN_SCREEN_IN_CORRECT  or TWEEN_SCREEN_IN_WRONG
	local tOutInfo = isCorrect and TWEEN_SCREEN_OUT_CORRECT or TWEEN_SCREEN_OUT_WRONG

	local tIn = TweenService:Create(overlay, tInInfo, {
		BackgroundTransparency = 0.6,
	})
	local tOut = TweenService:Create(overlay, tOutInfo, {
		BackgroundTransparency = 1,
	})

	-- 정답일 때 가운데 동그라미 링 재생
	if isCorrect then
		playCorrectRing()
	end

	tIn:Play()
	tIn.Completed:Connect(function()
		tOut:Play()
		tOut.Completed:Connect(function()
			flashBusy = false
		end)
	end)
end

-- ========= Bar / 텍스트 표시 =========
local function setBarRatio(ratio: number)
	local u = ensureUI(); if not u then return end
	ratio = math.clamp(ratio, 0, 1)
	TweenService:Create(u.bar, TWEEN_FILL, {
		Size = UDim2.fromScale(ratio, 0.4),
	}):Play()
end

local function increaseBarStep(step: number)
	local u = ensureUI(); if not u then return end
	local cur = u.bar.Size.X.Scale
	local newRatio = math.clamp(cur + step, 0, 1)
	TweenService:Create(u.bar, TWEEN_FILL, {
		Size = UDim2.fromScale(newRatio, 0.4),
	}):Play()
end

local function setText(n: number, total: number)
	local u = ensureUI(); if not u then return end
	u.txt.Text = string.format("진행 %d/%d", math.clamp(n, 0, total), total)
end

-- ========= QuizHudBus 이벤트 처리 =========
local function onShow(payload: any)
	local u = ensureUI(); if not u then return end

	if typeof(payload) == "number" then
		totalQuestions = math.max(payload, 0)
	end
	curSolved = 0

	u.gui.Enabled = true
	u.frame.Visible = true
	u.bar.Size = UDim2.fromScale(0, 0.4)
	setText(0, totalQuestions)
end

local function onProgress(payload: any)
	local u = ensureUI(); if not u then return end
	if typeof(payload) == "table" then
		totalQuestions = math.max(payload.total or totalQuestions, 0)
		curSolved = math.clamp(payload.n or curSolved, 0, totalQuestions)
	end

	setText(curSolved, totalQuestions)
	if totalQuestions > 0 then
		setBarRatio(curSolved / totalQuestions)
	else
		setBarRatio(0)
	end
end

local function onCorrect(payload: any)
	local u = ensureUI(); if not u then return end

	if typeof(payload) == "table" then
		totalQuestions = math.max(payload.total or totalQuestions, 0)
		curSolved = math.clamp(payload.n or curSolved, 0, totalQuestions)
	end

	setText(curSolved, totalQuestions)

	local step = (totalQuestions > 0) and (1 / totalQuestions) or 0.1
	increaseBarStep(step)

	flashScreen(Color3.fromRGB(120, 255, 160), true)
end

local function onWrong()
	flashScreen(Color3.fromRGB(255, 120, 120), false)
end

-- ========= 메인 =========
task.spawn(function()
	local anyObj = RS:WaitForChild("QuizHudBus")
	if not anyObj or not anyObj:IsA("BindableEvent") then
		warn("[QuizHUD] QuizHudBus 가 BindableEvent 가 아닙니다. ReplicatedStorage 아래에 BindableEvent 로 만들어 주세요.")
		return
	end
	local bus = anyObj :: BindableEvent

	bus.Event:Connect(function(cmd: any, payload: any)
		if cmd == "show" then
			onShow(payload)
		elseif cmd == "progress" then
			onProgress(payload)
		elseif cmd == "correct" then
			onCorrect(payload)
		elseif cmd == "wrong" then
			onWrong()
		end
	end)
end)

print("[QuizHUD] READY (정답 플래시 + 링 연출)")
