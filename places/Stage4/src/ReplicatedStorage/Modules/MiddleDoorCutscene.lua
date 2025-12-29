-- ReplicatedStorage/Modules/MiddleDoorCutscene.lua
--!strict

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace    = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")

local CUTSCENE_TIME = 3.0   -- 카메라 / 문 이동 / 페이드 모두 3초

local M = {}

local function getFadeTargets(root: Instance): {Instance}
	local t = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			table.insert(t, d)
		end
	end
	return t
end

local function getMoveParts(root: Instance): {BasePart}
	local t = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(t, d)
		end
	end
	return t
end

-- 🔊 공용 사운드 재생 함수
local function playSound(soundId: string, volume: number?)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

----------------------------------------------------
-- ★ LocalPlayer 컨트롤 / Humanoid 헬퍼
----------------------------------------------------
local function getControls()
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local ps = lp:FindFirstChildOfClass("PlayerScripts")
	if not ps then return nil end
	local pm = ps:FindFirstChild("PlayerModule")
	if not pm or not pm:IsA("ModuleScript") then return nil end

	local ok, mod = pcall(require, pm)
	if not ok or not mod.GetControls then return nil end

	local ok2, controls = pcall(function()
		return mod:GetControls()
	end)
	if not ok2 then return nil end

	return controls
end

local function getLocalHumanoid(): Humanoid?
	local lp = Players.LocalPlayer
	if not lp then return nil end
	local char = lp.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

----------------------------------------------------
-- 1) 기존 : 카메라 + 문 컷씬 (플레이어 잠금 추가)
----------------------------------------------------
function M.Play()
	local lp = Players.LocalPlayer
	if not lp then return end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	local startPart = Workspace:FindFirstChild("CutSceneCamPos") :: BasePart?
	local endPart   = Workspace:FindFirstChild("CutSceneEndCamPos") :: BasePart?
	if not (startPart and endPart) then
		warn("[MiddleDoorCutscene] CutSceneCamPos / CutSceneEndCamPos 를 찾지 못했습니다.")
		return
	end

	local stage4 = Workspace:FindFirstChild("Stage4")
	if not stage4 then
		warn("[MiddleDoorCutscene] Stage4 를 찾지 못했습니다.")
		return
	end

	local middleDoor = stage4:FindFirstChild("MiddleDoor") :: Model?
	if not middleDoor then
		warn("[MiddleDoorCutscene] MiddleDoor 모델을 찾지 못했습니다.")
		return
	end

	----------------------------------------------------
	-- 카메라 세팅 + 상태 백업
	----------------------------------------------------
	local prevType    = cam.CameraType
	local prevSubject = cam.CameraSubject
	local prevCFrame  = cam.CFrame

	-- ★ 플레이어 컨트롤 & 이동 잠금
	local controls = getControls()
	if controls then
		pcall(function()
			controls:Disable()
		end)
	end

	local humanoid = getLocalHumanoid()
	local oldWalkSpeed: number? = nil
	local oldJumpPower: number? = nil
	local oldJumpHeight: number? = nil
	local oldAutoRotate: boolean? = nil

	if humanoid then
		oldWalkSpeed   = humanoid.WalkSpeed
		oldJumpPower   = humanoid.JumpPower
		oldJumpHeight  = humanoid.JumpHeight
		oldAutoRotate  = humanoid.AutoRotate

		humanoid.WalkSpeed  = 0
		humanoid.JumpPower  = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end

	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame     = startPart.CFrame

	local camTweenInfo = TweenInfo.new(
		CUTSCENE_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)

	local camTween = TweenService:Create(cam, camTweenInfo, {
		CFrame = endPart.CFrame
	})

	----------------------------------------------------
	-- MiddleDoor 전체 파츠 이동 + 페이드
	----------------------------------------------------
	local moveParts    = getMoveParts(middleDoor)
	local fadeTargets  = getFadeTargets(middleDoor)

	local doorTweenInfo = TweenInfo.new(
		CUTSCENE_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)

	local dropDistance = 6.0

	-- 🔊 ★ 문이 내려가기 시작하는 타이밍에 사운드 2개 재생
	playSound("rbxassetid://103840356233584", 1)
	playSound("rbxassetid://6636232274", 0.8)

	-- 이동 트윈
	local moveTweens = {}
	for _, part in ipairs(moveParts) do
		part.CanCollide = false -- 내려갈 때 충돌 끄기
		local startCf = part.CFrame
		local goalCf  = startCf * CFrame.new(0, -dropDistance, 0)

		local tw = TweenService:Create(part, doorTweenInfo, {
			CFrame = goalCf
		})
		table.insert(moveTweens, tw)
	end

	-- 투명도 트윈
	local fadeTweens = {}
	for _, inst in ipairs(fadeTargets) do
		local ok = pcall(function()
			local tw = TweenService:Create(inst, doorTweenInfo, { Transparency = 1 })
			table.insert(fadeTweens, tw)
		end)
		if not ok then
			warn("[MiddleDoorCutscene] Transparency 트윈 실패:", inst:GetFullName())
		end
	end

	----------------------------------------------------
	-- 동시에 재생
	----------------------------------------------------
	camTween:Play()
	for _, tw in ipairs(moveTweens) do tw:Play() end
	for _, tw in ipairs(fadeTweens) do tw:Play() end

	camTween.Completed:Wait()

	----------------------------------------------------
	-- 최종 충돌 OFF (안전 장치)
	----------------------------------------------------
	for _, part in ipairs(moveParts) do
		part.CanCollide = false
	end

	----------------------------------------------------
	-- 카메라 복구
	----------------------------------------------------
	if humanoid and humanoid.Parent then
		-- 캐릭터를 다시 바라보는 기본 카메라
		cam.CameraType    = Enum.CameraType.Custom
		cam.CameraSubject = humanoid
	else
		cam.CameraType    = prevType
		cam.CameraSubject = prevSubject
		cam.CFrame        = prevCFrame
	end

	----------------------------------------------------
	-- ★ 이동/점프/회전 + 컨트롤 복구
	----------------------------------------------------
	if humanoid and humanoid.Parent then
		if oldWalkSpeed ~= nil then
			humanoid.WalkSpeed = oldWalkSpeed
		end
		if oldJumpPower ~= nil then
			humanoid.JumpPower = oldJumpPower
		end
		if oldJumpHeight ~= nil then
			humanoid.JumpHeight = oldJumpHeight
		end
		if oldAutoRotate ~= nil then
			humanoid.AutoRotate = oldAutoRotate
		end
	end

	if controls then
		pcall(function()
			controls:Enable()
		end)
	end
end

----------------------------------------------------
-- 2) 새 버전 : 카메라 고정, 문만 연출 (플레이어 잠금 X)
----------------------------------------------------
function M.PlayDoorOnly()
	local stage4 = Workspace:FindFirstChild("Stage4")
	if not stage4 then
		warn("[MiddleDoorCutscene] Stage4 를 찾지 못했습니다. (PlayDoorOnly)")
		return
	end

	local middleDoor = stage4:FindFirstChild("MiddleDoor") :: Model?
	if not middleDoor then
		warn("[MiddleDoorCutscene] MiddleDoor 모델을 찾지 못했습니다. (PlayDoorOnly)")
		return
	end

	-- MiddleDoor 전체 파츠 이동 + 페이드
	local moveParts    = getMoveParts(middleDoor)
	local fadeTargets  = getFadeTargets(middleDoor)

	local doorTweenInfo = TweenInfo.new(
		CUTSCENE_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.InOut
	)

	local dropDistance = 6.0

	local moveTweens = {}
	for _, part in ipairs(moveParts) do
		part.CanCollide = false
		local startCf = part.CFrame
		local goalCf  = startCf * CFrame.new(0, -dropDistance, 0)

		local tw = TweenService:Create(part, doorTweenInfo, {
			CFrame = goalCf
		})
		table.insert(moveTweens, tw)
	end

	local fadeTweens = {}
	for _, inst in ipairs(fadeTargets) do
		local ok = pcall(function()
			local tw = TweenService:Create(inst, doorTweenInfo, { Transparency = 1 })
			table.insert(fadeTweens, tw)
		end)
		if not ok then
			warn("[MiddleDoorCutscene] Transparency 트윈 실패(PlayDoorOnly):", inst:GetFullName())
		end
	end

	-- 카메라는 손대지 않고 문만 트윈
	for _, tw in ipairs(moveTweens) do tw:Play() end
	for _, tw in ipairs(fadeTweens) do tw:Play() end

	-- 대충 컷씬 시간만큼 기다렸다가 충돌 정리
	task.wait(CUTSCENE_TIME)

	for _, part in ipairs(moveParts) do
		part.CanCollide = false
	end
end

return M
