-- ReplicatedStorage/Modules/Cutscene/CutscenePlayer.lua
-- 포탈 오픈 컷씬 (끝나면 서버에 Quiz_CutsceneDone 신호 송신)

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UIS               = game:GetService("UserInputService")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LP     = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local Net             = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local RE_CutsceneDone = Net.ensureRE("Quiz_CutsceneDone")

local Cutscene = {}
local _busy = false

local function getControls()
	local pm = LP:FindFirstChildOfClass("PlayerScripts")
	pm = pm and pm:FindFirstChild("PlayerModule")
	if not pm then return nil end
	local ok, mod = pcall(require, pm)
	if not ok or not mod.GetControls then return nil end
	return mod:GetControls()
end

local function findPortal(stage:number)
	local s01 = Workspace:FindFirstChild("Stage01")
	if s01 then
		local m = s01:FindFirstChild(string.format("Stage%dPotal", stage))
		if m then return m end
	end
	return Workspace:FindFirstChild(string.format("Stage%dPotal", stage))
end

----------------------------------------------------------------
-- 포탈 오픈 컷씬 (스킵 불가 버전)
----------------------------------------------------------------
function Cutscene.PlayPortalOpen(stage:number, opts:table?)
	if _busy then return end
	_busy = true
	opts = opts or {}

	local totalDur = tonumber(opts.duration) or 3.0

	local controls = getControls(); if controls then controls:Disable() end

	local oldType = camera.CameraType
	local oldCF   = camera.CFrame
	local oldFOV  = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	local function finalize()
		camera.CameraType  = oldType
		camera.CFrame      = oldCF
		camera.FieldOfView = oldFOV
		if controls then controls:Enable() end
		_busy = false
		print("[Cutscene] done -> FireServer Quiz_CutsceneDone")
		RE_CutsceneDone:FireServer({ type = "portal_open", stage = stage })
	end

	----------------------------------------------------
	-- 1) Workspace 안의 카메라 파트 먼저 시도
	--    CutSceneCamPos / CutSceneCamEndPos
	--    없으면 CamPos / CamEndPos 도 허용
	----------------------------------------------------
	local camStartPart =
		Workspace:FindFirstChild("CutSceneCamPos")
		--or Workspace:FindFirstChild("CamPos")

	local camEndPart =
		Workspace:FindFirstChild("CutSceneCamEndPos")
		--or Workspace:FindFirstChild("CamEndPos")

	if camStartPart and camEndPart
		and camStartPart:IsA("BasePart")
		and camEndPart:IsA("BasePart")
	then
		-- ✅ 우리가 배치한 파트에서 파트로 그대로 이동
		local startCF = (camStartPart :: BasePart).CFrame
		local endCF   = (camEndPart   :: BasePart).CFrame

		camera.CFrame      = startCF
		camera.FieldOfView = tonumber(opts.startFov) or 70

		local tween = TweenService:Create(
			camera,
			TweenInfo.new(
				totalDur,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut
			),
			{
				CFrame      = endCF,
				FieldOfView = tonumber(opts.endFov) or 76,
			}
		)
		tween:Play()
		tween.Completed:Wait()

		finalize()
		return
	end

	----------------------------------------------------
	-- 2) 위 파트들을 못 찾으면, 기존 포탈 기준 컷씬으로 폴백
	----------------------------------------------------
	local portal = findPortal(stage)
	if not portal then
		warn("[Cutscene] portal & camera parts not found, finalize immediately")
		finalize()
		return
	end

	local pivot = (portal:IsA("Model") and portal:GetPivot())
		or CFrame.new(portal:GetBoundingBox())
	local front = pivot.LookVector

	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = { portal }
		local hit = workspace:Raycast(pivot.Position + pivot.UpVector * 2, front * 6, params)
		if hit then front = -front end
	end

	local target = pivot.Position + front * 0.2
	local up     = pivot.UpVector

	local startCF = CFrame.lookAt(target + front * 30 + up * 5, target)
	local finalCF = CFrame.lookAt(target + front * 15 + up * 2,  target)

	camera.CFrame      = startCF
	camera.FieldOfView = 70

	local tween = TweenService:Create(
		camera,
		TweenInfo.new(
			totalDur,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		{
			CFrame      = finalCF,
			FieldOfView = 76,
		}
	)
	tween:Play()
	tween.Completed:Wait()

	finalize()
end


----------------------------------------------------------------
-- 포탈 스폰 컷씬 (원래부터 스킵 없음)
----------------------------------------------------------------
function Cutscene.PlayPortalSpawnAt(payload)
	if _busy then return end
	_busy = true

	local stage        = tonumber(payload.stage) or 1
	local targetPos    = payload.targetPos :: Vector3
	local dropTime     = tonumber(payload.dropTime)    or 1.0
	local dropDelay    = tonumber(payload.dropDelay)   or 0.2
	local dropHeight   = tonumber(payload.dropHeight)  or 40
	local camBack      = tonumber(payload.camBack)     or 20   -- 월드 Z축 뒤로 빠지는 거리
	local lookUpBelow  = tonumber(payload.lookUpBelow) or 0    -- 포탈보다 카메라를 얼마나 아래에서 올려다볼지

	local RunService   = game:GetService("RunService")
	local controls = getControls(); if controls then controls:Disable() end

	-- 카메라 백업 및 스크립트 모드
	local oldType, oldCF, oldFOV = camera.CameraType, camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	-- 이징(서버 드롭과 동기: OutCubic)
	local function outCubic(t) return 1 - (1 - t) ^ 3 end

	-- 인트로
	local startPortalY = targetPos.Y + dropHeight
	local introPortal  = Vector3.new(targetPos.X, startPortalY, targetPos.Z)
	local introCamPos  = Vector3.new(targetPos.X, startPortalY - lookUpBelow, targetPos.Z - camBack)
	camera.CFrame      = CFrame.lookAt(introCamPos, introPortal, Vector3.yAxis)
	camera.FieldOfView = 76

	local startTime = os.clock() + dropDelay

	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()

		if now < startTime then
			camera.CFrame = CFrame.lookAt(introCamPos, introPortal, Vector3.yAxis)
			return
		end

		local t = math.clamp((now - startTime) / dropTime, 0, 1)
		local f = outCubic(t)

		local curY = targetPos.Y + (1 - f) * dropHeight
		local portalPos = Vector3.new(targetPos.X, curY, targetPos.Z)

		local camPos = Vector3.new(targetPos.X, curY - lookUpBelow, targetPos.Z - camBack)
		camera.CFrame = CFrame.lookAt(camPos, portalPos, Vector3.yAxis)

		if t >= 1 then
			conn:Disconnect(); conn = nil

			local settleCamY = targetPos.Y - math.max(lookUpBelow - 2, 0)
			local settlePos  = Vector3.new(targetPos.X, settleCamY, targetPos.Z - camBack)
			local finalLook  = CFrame.lookAt(settlePos, targetPos, Vector3.yAxis)

			local tw = TweenService:Create(
				camera,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ CFrame = finalLook, FieldOfView = 72 }
			)
			tw:Play()
			tw.Completed:Wait()

			camera.CameraType  = oldType
			camera.CFrame      = oldCF
			camera.FieldOfView = oldFOV
			if controls then controls:Enable() end
			_busy = false
		end
	end)
end

return Cutscene
