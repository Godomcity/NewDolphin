-- StarterPlayerScripts/FinalZoneCutscene.client.lua
--!strict
-- Stage5(FinalZone) 엔딩 컷씬
-- ✅ 서버(Remotes.FinalJump_PlayCutscene) 신호 수신
-- ✅ FinalZoneBeamClient에 있던 "정리(QuizGui/대사UI/다른 컷씬 중단/카메라 리셋)" 로직을 이 파일로 이식

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Lighting     = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

----------------------------------------------------------------
-- safe require
----------------------------------------------------------------
local function tryRequire(inst: Instance?): any
	if not inst or not inst:IsA("ModuleScript") then return nil end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end

----------------------------------------------------------------
-- Optional modules (있으면 사용, 없으면 폴백)
----------------------------------------------------------------
local Modules = RS:FindFirstChild("Modules")
local CutsceneManager = tryRequire(Modules and Modules:FindFirstChild("CutsceneManager"))
local CameraReset     = tryRequire(Modules and Modules:FindFirstChild("CameraReset"))
local playerLock = tryRequire(Modules and Modules:FindFirstChild("PlayerLock"))

----------------------------------------------------------------
-- Remotes / Bus
----------------------------------------------------------------
local Remotes = RS:WaitForChild("Remotes")
local RE_PlayCutscene = Remotes:WaitForChild("FinalJump_PlayCutscene") :: RemoteEvent

-- ====== 컷씬 호출용 버스(클라 내부 호출용) ======
local CutsceneBus: BindableEvent do
	local existing = RS:FindFirstChild("FinalZoneCutsceneBus")
	if existing and existing:IsA("BindableEvent") then
		CutsceneBus = existing
	else
		CutsceneBus = Instance.new("BindableEvent")
		CutsceneBus.Name = "FinalZoneCutsceneBus"
		CutsceneBus.Parent = RS
	end
end

----------------------------------------------------------------
-- Stage5 전용 루트 / 이름
----------------------------------------------------------------
local FINALZONE_NAME         = "FinalZone"
local CHARACTER_FOLDER_NAME  = "Character"
local PORTAL_FOLDER_NAME     = "Coral_Portal"
local ENERGY_PART_NAME       = "energe"
local SOURCE_PART_NAME       = "BeamPart"

local ORDER = { "Dolphin_m", "Turtle_m", "Shark_m", "Seahorse_m", "Crab_m" }

-- Stage5 전용 루트
local finalRoot = workspace:WaitForChild("Fianl")
local ABS_CAM_POS        = finalRoot:WaitForChild("ZomCamPos").Position
local CAM_TO_ABS_DUR     = 1.60
local HOLD_AFTER_LIGHT   = 3.0

----------------------------------------------------------------
-- 파라미터
----------------------------------------------------------------
local BEAM_COLOR   = Color3.fromRGB(60, 220, 255)
local WIDTH_ON     = 0.28
local RAMP_TIME    = 0.55
local GAP_TIME     = 0.80

local THICK_WIDTH  = 0.60
local THICKEN_TIME = 0.35

local CAM_OPEN_GEM_DUR = 1.20
local CAM_FOV_WIDE     = 72
local CAM_FOV_OPEN_IN  = 70

local CAM_CHAR_DUR   = 1.50
local CAM_CHAR_HOLD  = 0.50
local CAM_FOV_MED    = 66
local CHAR_DIST      = 12
local CHAR_HEIGHT    = 6
local DEFAULT_YAW    = 25

local CAM_END_DUR    = 1.80
local CAM_FOV_TIGHT  = 62
local END_DIST       = 10
local END_HEIGHT     = 7
local END_YAW        = -10

local OPEN_DIST      = 42
local OPEN_HEIGHT    = 18
local OPEN_YAW       = DEFAULT_YAW + 180

-- 사운드
local SOUND_MOVE        = "rbxassetid://9114374439"
local SOUND_BEAM        = "rbxassetid://4580947745"
local SOUND_GEM         = "rbxassetid://7369745305"
local SOUND_BEAM_GATHER = "rbxassetid://5862482798"

local function playOneShot(parent: Instance?, soundId: string?, volume: number?)
	if not soundId or soundId == "" then return end
	parent = parent or camera or workspace
	if not parent then return end

	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.Parent = parent
	s:Play()

	s.Ended:Connect(function()
		if s then s:Destroy() end
	end)

	task.delay(5, function()
		if s and s.Parent then s:Destroy() end
	end)
end


----------------------------------------------------------------
-- ✅ 엔딩 후처리: UI OFF + Blur(0→20 유지)
----------------------------------------------------------------
local ENDING_BLUR_NAME = "EndingBlur"
local ENDING_BLUR_TARGET_SIZE = 20
local ENDING_BLUR_TWEEN_TIME = 0.6

local function disableAllUI()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end
	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") then
			gui.Enabled = false
		end
	end
end

local function fadeInEndingBlur()
	local blur = Lighting:FindFirstChild(ENDING_BLUR_NAME) :: BlurEffect?
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = ENDING_BLUR_NAME
		blur.Size = 0
		blur.Enabled = false
		blur.Parent = Lighting
	end

	blur.Enabled = true
	blur.Size = 0

	local ti = TweenInfo.new(ENDING_BLUR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(blur, ti, { Size = ENDING_BLUR_TARGET_SIZE }):Play()
end


----------------------------------------------------------------
-- UI / 컷씬 정리(BeamClient에서 가져온 부분)
----------------------------------------------------------------
local function setQuizGuiEnabled(enabled: boolean)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end

	local quizGui = pg:FindFirstChild("QuizGui")
	if quizGui and quizGui:IsA("ScreenGui") then
		quizGui.Enabled = enabled
	end

	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") and string.find(gui.Name, "Quiz") then
			gui.Enabled = enabled
		end
	end
end

-- ✅ DialogueUI는 "GUI.Enabled" 대신 "BG.Visible"로 제어하도록 바뀌었으니
-- 여기서는 BindableEvent Close로 닫는 게 제일 안전함
local function closeDialogueUI(enabled)
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end

	local dialogueGui = pg:FindFirstChild("DialogueGui")
	if dialogueGui and dialogueGui:IsA("ScreenGui") then
		dialogueGui.Enabled = enabled
		print("꺼짐")
	end
	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") and string.find(gui.Name, "Dialogue") then
			gui.Enabled = enabled
		end
	end
	game.SoundService:WaitForChild("PortalOpen"):Stop()
end

local function restoreCamera()
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = 70
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		camera.CameraSubject = hum
	end
end

-- ✅ 퀴즈 종료/엔딩 시작 전 정리
local function cleanupForEnding()
	-- 카메라 리셋(가능하면 모듈 사용)
	if CameraReset and type(CameraReset.ResetOnce) == "function" then
		pcall(function()
			CameraReset.ResetOnce("cleanupForEnding")
		end)
	else
		restoreCamera()
		task.wait()
	end

	setQuizGuiEnabled(false)
	closeDialogueUI(false)

	-- 다른 컷씬/예약 중단(가능하면)
	if CutsceneManager and type(CutsceneManager.StopAll) == "function" then
		pcall(function()
			CutsceneManager.StopAll("quiz_end_cleanup")
		end)
	end

	-- StopAll 이후에도 Scriptable 잔재가 남는 경우 방지
	if CameraReset and type(CameraReset.ResetOnce) == "function" then
		pcall(function()
			CameraReset.ResetOnce("cleanupForEnding(after StopAll)")
		end)
	else
		restoreCamera()
	end
end

----------------------------------------------------------------
-- 상태 / 유틸
----------------------------------------------------------------
local _isPlaying = false
local _activeBeams: {Beam} = {}
local _playNonce = 0 -- 중복/재진입/취소

local function ensureAttachment(part: BasePart)
	local att = part:FindFirstChildOfClass("Attachment")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "Cutscene_Attachment"
		att.Parent = part
	end
	return att
end

local function createBeam(sourcePart: BasePart, targetPart: BasePart): Beam
	local a0 = ensureAttachment(sourcePart)
	local a1 = ensureAttachment(targetPart)

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(BEAM_COLOR)
	beam.Brightness = 2.0
	beam.LightEmission = 0.6
	beam.LightInfluence = 0
	beam.Transparency = NumberSequence.new(0)
	beam.FaceCamera = true
	beam.Segments = 10
	beam.Width0 = 0.0
	beam.Width1 = 0.0
	beam.Name = "CutsceneBeam"
	beam.Parent = sourcePart

	local ti = TweenInfo.new(RAMP_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(beam, ti, { Width0 = WIDTH_ON }):Play()
	TweenService:Create(beam, ti, { Width1 = WIDTH_ON }):Play()

	playOneShot(sourcePart, SOUND_BEAM, 1)
	return beam
end

local function cleanupBeams()
	for i = #_activeBeams, 1, -1 do
		local b = _activeBeams[i]
		if b and b.Parent then b:Destroy() end
		_activeBeams[i] = nil
	end
end

local function thickenAllBeams(targetWidth: number, dur: number)
	local ti = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, b in ipairs(_activeBeams) do
		if b and b.Parent then
			TweenService:Create(b, ti, { Width0 = targetWidth }):Play()
			TweenService:Create(b, ti, { Width1 = targetWidth }):Play()
		end
	end
	task.wait(dur)
end

local function makeShotCFrame(targetPos: Vector3, distance: number, height: number, degYaw: number): CFrame
	local yaw = math.rad(degYaw)
	local backDir = (CFrame.fromEulerAnglesYXZ(0, yaw, 0).LookVector) * -1
	local pos = targetPos + (backDir * distance) + Vector3.new(0, height, 0)
	return CFrame.lookAt(pos, targetPos, Vector3.yAxis)
end

local function tweenCamera(cf: CFrame, dur: number, newFov: number?, withMoveSfx: boolean?)
	-- 컷씬 중엔 Scriptable 고정
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
	end

	local ti = TweenInfo.new(dur, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
	TweenService:Create(camera, ti, { CFrame = cf }):Play()
	if newFov then
		TweenService:Create(camera, ti, { FieldOfView = newFov }):Play()
	end

	if withMoveSfx == nil or withMoveSfx == true then
		playOneShot(camera, SOUND_MOVE, 0.8)
	end

	task.wait(dur)
end

local function setPortalNeon(folder: Instance, neonOn: boolean, color: Color3?)
	for _, inst in ipairs(folder:GetDescendants()) do
		if inst:IsA("BasePart") then
			if neonOn then
				inst.Material = Enum.Material.Neon
				if color then inst.Color = color end
			else
				inst.Material = Enum.Material.SmoothPlastic
			end
		end
	end
end

local function preResetCameraOneFrame()
	-- 외부 컷씬/스크립트로 꼬인 상태를 먼저 정상화
	if CameraReset and type(CameraReset.ResetOnce) == "function" then
		pcall(function()
			CameraReset.ResetOnce("preResetCameraOneFrame")
		end)
	else
		restoreCamera()
		task.wait()
	end
end

----------------------------------------------------------------
-- 컷씬 본체
----------------------------------------------------------------
local function playFinalZoneCutscene()
	if _isPlaying then return end

	_isPlaying = true
	_playNonce += 1
	local myNonce = _playNonce

	-- ✅ 엔딩 시작 전에 정리(BeamClient에서 가져온 핵심)
	cleanupForEnding()

	-- 다른 컷씬 강제 종료(있으면)
	if CutsceneManager and type(CutsceneManager.StopAll) == "function" then
		pcall(function()
			CutsceneManager.StopAll("FinalZoneStart")
		end)
	end

	cleanupBeams()
	preResetCameraOneFrame()

	local FinalZone = finalRoot:FindFirstChild(FINALZONE_NAME)
	if not FinalZone then
		_isPlaying = false
		warn("[Stage5] FinalZone 없음")
		return
	end

	local CharacterFolder = FinalZone:FindFirstChild(CHARACTER_FOLDER_NAME)
	local PortalFolder    = FinalZone:FindFirstChild(PORTAL_FOLDER_NAME)
	if not CharacterFolder or not PortalFolder then
		_isPlaying = false
		warn("[Stage5] Character 또는 Coral_Portal 폴더 없음")
		return
	end

	local energyPart = PortalFolder:FindFirstChild(ENERGY_PART_NAME) :: BasePart?
	if not energyPart or not energyPart:IsA("BasePart") then
		_isPlaying = false
		warn("[Stage5] energe 파트 없음")
		return
	end
	ensureAttachment(energyPart)

	-- 카메라 저장
	local originalType = camera.CameraType
	local originalCF   = camera.CFrame
	local originalFOV  = camera.FieldOfView

	local ok, err = pcall(function()
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil

		local portalPivot = PortalFolder:GetPivot()
		local openTarget  = portalPivot.Position
		local openCF      = makeShotCFrame(openTarget, OPEN_DIST, OPEN_HEIGHT, OPEN_YAW)

		camera.CFrame      = openCF
		camera.FieldOfView = CAM_FOV_WIDE
		task.wait(0.05)

		local openGemCF do
			local camPart = finalRoot:FindFirstChild("FinalCutSceneCamPos")
			if camPart and camPart:IsA("BasePart") then
				openGemCF = camPart.CFrame
			else
				openGemCF = makeShotCFrame(
					energyPart.Position,
					OPEN_DIST * 0.72,
					OPEN_HEIGHT * 0.95,
					OPEN_YAW
				)
			end
		end
		tweenCamera(openGemCF, CAM_OPEN_GEM_DUR, CAM_FOV_OPEN_IN, true)

		local yawBase = DEFAULT_YAW
		for idx, modelName in ipairs(ORDER) do
			-- ✅ 중간 취소(다른 시스템이 _playNonce를 올리면 즉시 종료)
			if myNonce ~= _playNonce then return end

			local model = CharacterFolder:FindFirstChild(modelName)
			if not model then
				task.wait(GAP_TIME)
				continue
			end

			local sourcePart = model:FindFirstChild(SOURCE_PART_NAME, true) :: BasePart?
			if not sourcePart or not sourcePart:IsA("BasePart") then
				task.wait(GAP_TIME)
				continue
			end

			local tpos = sourcePart.Position
			local cf   = makeShotCFrame(tpos, CHAR_DIST, CHAR_HEIGHT, yawBase)

			tweenCamera(cf, CAM_CHAR_DUR, CAM_FOV_MED, (idx == 1))
			task.wait(0.05)

			local beam = createBeam(sourcePart, energyPart)
			table.insert(_activeBeams, beam)

			task.wait(CAM_CHAR_HOLD)

			if idx == #ORDER then
				local fixedCF = CFrame.lookAt(ABS_CAM_POS, energyPart.Position, Vector3.yAxis)
				tweenCamera(fixedCF, CAM_TO_ABS_DUR, CAM_FOV_MED, true)

				playOneShot(energyPart, SOUND_BEAM_GATHER, 1)
				thickenAllBeams(THICK_WIDTH, THICKEN_TIME)

				local endCF = makeShotCFrame(energyPart.Position, END_DIST, END_HEIGHT, END_YAW + 180)
				tweenCamera(endCF, CAM_END_DUR, CAM_FOV_TIGHT, true)

				energyPart.Color = Color3.fromRGB(0, 255, 120)
				setPortalNeon(PortalFolder, true, Color3.fromRGB(0, 255, 120))
				playOneShot(energyPart, SOUND_GEM, 1)
			end

			task.wait(GAP_TIME)
		end

		task.wait(HOLD_AFTER_LIGHT)
		cleanupBeams()
	end)

	-- 복구
	camera.CFrame      = originalCF
	camera.FieldOfView = originalFOV
	camera.CameraType  = originalType
	restoreCamera()
	-- ✅ 컷씬 종료 후: UI OFF + 블러
	disableAllUI()
	fadeInEndingBlur()
	playerLock.Lock({freezeMovement = true, freezeCamera = true, disableInput = true})
	if not ok then
		warn("[Stage5] FinalZoneCutscene error:", err)
	end

	_isPlaying = false
end

----------------------------------------------------------------
-- ✅ 트리거들
----------------------------------------------------------------
-- 1) 클라 내부 버스
CutsceneBus.Event:Connect(function(cmd: any)
	if cmd == "Play" or cmd == "play" then
		playFinalZoneCutscene()
	elseif cmd == "Cleanup" or cmd == "cleanup" then
		_playNonce += 1 -- 진행 중이면 즉시 취소
		cleanupForEnding()
	end
end)

-- 2) ✅ 서버 RemoteEvent
RE_PlayCutscene.OnClientEvent:Connect(function(payload: any)
	-- FinalZoneBeamClient 스타일(payload table)도 지원
	if typeof(payload) == "table" then
		if payload.cleanup == true then
			_playNonce += 1 -- 진행 중이면 즉시 취소
			cleanupForEnding()
		end

		local mode = tostring(payload.mode or "")
		if mode == "" or mode == "Ending" or mode == "FinalZone" then
			task.defer(playFinalZoneCutscene)
		end
		return
	end

	if payload == nil or payload == "Play" or payload == "play" then
		task.defer(playFinalZoneCutscene)
	elseif payload == "Cleanup" or payload == "cleanup" then
		_playNonce += 1
		cleanupForEnding()
	end
end)

-- 컷씬 중 리셋/재스폰 간섭 방지
player.CharacterAdded:Connect(function()
	if _isPlaying then return end
	if CameraReset and type(CameraReset.ResetOnce) == "function" then
		pcall(function()
			CameraReset.ResetOnce("CharacterAdded")
		end)
	else
		restoreCamera()
	end
end)

print("[Stage5] FinalZoneCutscene READY (Bus + RemoteEvent + Cleanup/StopAll/CameraReset)")
