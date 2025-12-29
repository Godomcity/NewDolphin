-- StarterPlayerScripts/LadderCutsceneTest.client.lua
--!strict
-- F6 키로 "사다리 컷씬" 테스트
-- Workspace.CutSceneCamPos -> CutSceneCamEndPos 로 스무스하게 이동 + 사다리 드롭

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local ReplicatedFirst  = game:GetService("ReplicatedFirst")
local CAS              = game:GetService("ContextActionService")
local Workspace        = game:GetService("Workspace")
local TweenService     = game:GetService("TweenService")

local LP     = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local Modules         = RS:WaitForChild("Modules")
local LadderCinematic = require(Modules:WaitForChild("LadderCinematic"))

local LADDER_TEMPLATE = ReplicatedFirst:WaitForChild("Stage2Ladder")  -- 템플릿 이름 맞춰줘
local LADDER_POS      = Vector3.new(-59.745, 29.593, 125.927)

-- 🔹 예전용 카메라 포인트( CutSceneCamPos 없을 때만 사용되는 폴백 )
local WIDE_POS   = Vector3.new(-3.0, 45.0, 150.0)
local MID_POS    = Vector3.new(-15.0, 38.0, 135.0)
local CLOSE_POS  = Vector3.new(-30.0, 33.0, 128.0)

local WIDE_FOV   = 78
local MID_FOV    = 68
local CLOSE_FOV  = 60

local BUSY         = false
local COOLDOWN_SEC = 1.8

local function playLadderCutscene3s()
	if BUSY then return end
	if not camera then return end
	BUSY = true

	-- 기존 카메라 상태 백업
	local oldType = camera.CameraType
	local oldCF   = camera.CFrame
	local oldFOV  = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable

	----------------------------------------------------------------
	-- 🔹 컷씬용 카메라 파트 우선 사용: CutSceneCamPos -> CutSceneCamEndPos
	----------------------------------------------------------------
	local startPart = Workspace:FindFirstChild("CutSceneCamPos")
	local endPart   = Workspace:FindFirstChild("CutSceneCamEndPos")

	local useParts = startPart
		and endPart
		and startPart:IsA("BasePart")
		and endPart:IsA("BasePart")

	-- 사다리 드롭은 카메라가 움직이는 동안 약간 뒤에 시작
	task.delay(0.4, function()
		LadderCinematic.spawnAndAnimate({
			template   = LADDER_TEMPLATE,
			position   = LADDER_POS,
			parent     = workspace,
			dropHeight = 18,
			dropTime   = 0.8,   -- 떨어지는 시간
			bouncePower= 1.0,
			keepChildrenTransparent = true,
			soundId    = "rbxassetid://87523965330187",
			soundVolume= 1,
		})
	end)

	if useParts then
		------------------------------------------------------------
		-- ✅ 새 방식: 파트에서 파트로 한 번에 스무스 이동
		------------------------------------------------------------
		local startCF = (startPart :: BasePart).CFrame
		local endCF   = (endPart   :: BasePart).CFrame

		-- 시작 세팅
		camera.CFrame      = startCF
		camera.FieldOfView = 70

		local totalTime = 2.8 -- 필요하면 시간 조절

		local tween = TweenService:Create(
			camera,
			TweenInfo.new(
				totalTime,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),
			{
				CFrame      = endCF,
				FieldOfView = 60, -- 마지막에 살짝 줌인 느낌
			}
		)
		tween:Play()
		tween.Completed:Wait()

	else
		------------------------------------------------------------
		-- 🔁 폴백: 옛날 WIDE/MID/CLOSE 3단계 컷씬
		------------------------------------------------------------
		local function lookAtFrom(pos: Vector3): CFrame
			return CFrame.new(pos, LADDER_POS)
		end

		-- STEP 1: 전체샷
		camera.CFrame      = lookAtFrom(WIDE_POS)
		camera.FieldOfView = WIDE_FOV

		local t1 = TweenService:Create(
			camera,
			TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				CFrame      = lookAtFrom(WIDE_POS),
				FieldOfView = WIDE_FOV,
			}
		)
		t1:Play()
		t1.Completed:Wait()

		-- STEP 2: 중간샷
		local t2 = TweenService:Create(
			camera,
			TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				CFrame      = lookAtFrom(MID_POS),
				FieldOfView = MID_FOV,
			}
		)
		t2:Play()
		t2.Completed:Wait()

		-- STEP 3: 클로즈업
		local t3 = TweenService:Create(
			camera,
			TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{
				CFrame      = lookAtFrom(CLOSE_POS),
				FieldOfView = CLOSE_FOV,
			}
		)
		t3:Play()
		t3.Completed:Wait()
	end

	-- 약간만 더 보여주고 복귀
	task.wait(0.2)

	camera.CameraType  = oldType
	camera.CFrame      = oldCF
	camera.FieldOfView = oldFOV

	BUSY = false
end

local function onAction(_, state, _)
	if state == Enum.UserInputState.Begin then
		playLadderCutscene3s()
	end
end

CAS:BindAction("LadderCutsceneTest", onAction, false, Enum.KeyCode.F6)
print(("[LadderCutsceneTest] READY — F6: 사다리 컷씬 (Stage2Ladder @ %s)"):format(tostring(LADDER_POS)))
