-- StarterPlayerScripts/FinalZoneBeamClient.client.lua
--!strict

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS           = game:GetService("ReplicatedStorage")
local Lighting     = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local CutsceneManager = require(RS:WaitForChild("Modules"):WaitForChild("CutsceneManager"))
local CameraReset     = require(RS:WaitForChild("Modules"):WaitForChild("CameraReset"))

local playerLock = require(RS:WaitForChild("Modules"):WaitForChild("PlayerLock"))

-- ====== 컷씬 호출용 버스 ======
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

local bus = RS:WaitForChild("QuestGuideBus", 10)

-- ===== 경로/이름 =====
local FINALZONE_NAME         = "FinalZone"
local CHARACTER_FOLDER_NAME  = "Character"
local PORTAL_FOLDER_NAME     = "Coral_Portal"
local ENERGY_PART_NAME       = "energe"
local SOURCE_PART_NAME       = "BeamPart"

local ORDER = { "Dolphin_m", "Turtle_m", "Shark_m", "Seahorse_m", "Crab_m" }

-- ===== 빔 파라미터 =====
local BEAM_COLOR   = Color3.fromRGB(60, 220, 255)
local WIDTH_ON     = 0.28
local RAMP_TIME    = 0.55
local GAP_TIME     = 0.80
local THICK_WIDTH  = 0.60
local THICKEN_TIME = 0.35

-- ===== 카메라 파라미터 =====
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

local ABS_CAM_POS    = Vector3.new(-141.293, -481.119, -573.874)
local CAM_TO_ABS_DUR = 1.60

local HOLD_AFTER_LIGHT = 3.0

-- ===== 사운드 =====
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
		if s and s.Parent then
			s:Destroy()
		end
	end)
end

-- ✅ 모든 UI 비활성화
local function disableAllUI()
	local pg = player:FindFirstChild("PlayerGui")
	if not pg then return end

	for _, gui in ipairs(pg:GetChildren()) do
		if gui:IsA("ScreenGui") then
			gui.Enabled = false
		end
	end
end

-- ===== 블러(컷씬 종료 후) =====
local ENDING_BLUR_NAME = "EndingBlur"
local ENDING_BLUR_TARGET_SIZE = 20
local ENDING_BLUR_TWEEN_TIME = 0.6

local function getOrCreateEndingBlur(): BlurEffect
	local blur = Lighting:FindFirstChild(ENDING_BLUR_NAME) :: BlurEffect?
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = ENDING_BLUR_NAME
		blur.Size = 0
		blur.Enabled = false
		blur.Parent = Lighting
	end
	return blur
end

local function fadeInEndingBlur()
	local blur = getOrCreateEndingBlur()
	blur.Enabled = true
	blur.Size = 0

	local ti = TweenInfo.new(ENDING_BLUR_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(blur, ti, { Size = ENDING_BLUR_TARGET_SIZE }):Play()
	-- ✅ 유지: 끄거나 0으로 내리지 않는 한 계속 20 유지
end

-- ===== 상태 =====
local _isPlaying = false
local _activeBeams: {Beam} = {}

-- ✅ QuizGui 끄기/켜기 유틸
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

local function closeDialogueUI(enabled: boolean)
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

-- ✅ 퀴즈 종료/엔딩 시작 전 정리
-- (중간 컷씬을 끊는 상황이라, 여기서는 Custom으로 복귀가 필요)
local function cleanupForEnding()
	-- 컷씬 강제 종료를 위해 일단 기본 카메라로 돌려놓고
	CameraReset.ResetOnce("cleanupForEnding")

	setQuizGuiEnabled(false)
	closeDialogueUI(false)

	pcall(function()
		CutsceneManager.StopAll("quiz_end_cleanup")
	end)

	-- StopAll로 Scriptable 잔재가 남았을 수 있으니 한 번 더 기본으로
	CameraReset.ResetOnce("cleanupForEnding(after StopAll)")
end

-- ===== 유틸 =====
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
	-- 컷씬 중엔 Scriptable 유지(혹시 외부에서 Custom로 바꿔도 다시 고정)
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

-- ===== 컷씬 본체 =====
local function playFinalZoneCutscene()
	if _isPlaying then return end
	_isPlaying = true
	playerLock.Lock({freezeMovement = true, freezeCamera = false, disableInput = true})
	-- ✅ 컷씬 시작하면 카메라 1회 초기화
	CameraReset.ResetOnce("cutscene start")

	-- 다른 컷씬 정리(예약 포함)
	pcall(function()
		CutsceneManager.StopAll("FinalZoneStart")
	end)

	setQuizGuiEnabled(false)
	closeDialogueUI(false)
	cleanupBeams()

	local FinalZone = workspace:FindFirstChild(FINALZONE_NAME)
	if not FinalZone then _isPlaying = false; warn("FinalZone 없음"); return end

	local CharacterFolder = FinalZone:FindFirstChild(CHARACTER_FOLDER_NAME)
	local PortalFolder    = FinalZone:FindFirstChild(PORTAL_FOLDER_NAME)
	if not CharacterFolder or not PortalFolder then
		_isPlaying = false; warn("Character 또는 Coral_Portal 폴더 없음"); return
	end

	local energyPart = PortalFolder:FindFirstChild(ENERGY_PART_NAME) :: BasePart?
	if not energyPart or not energyPart:IsA("BasePart") then
		_isPlaying = false; warn("energe 파트 없음"); return
	end
	ensureAttachment(energyPart)

	-- ✅ 여기부터는 “파이널 컷씬 카메라 따라가기” (Scriptable 고정)
	local originalType = camera.CameraType
	local originalCF   = camera.CFrame
	local originalFOV  = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil

	local ok, err = pcall(function()
		local portalPivot = PortalFolder:GetPivot()
		local openTarget  = portalPivot.Position
		local openCF      = makeShotCFrame(openTarget, OPEN_DIST, OPEN_HEIGHT, OPEN_YAW)

		camera.CFrame      = openCF
		camera.FieldOfView = CAM_FOV_WIDE
		task.wait(0.05)

		local openGemCF do
			local camPart = workspace:FindFirstChild("FinalCutSceneCamPos")
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
			local model = CharacterFolder:FindFirstChild(modelName)
			if not model then continue end

			local sourcePart = model:FindFirstChild(SOURCE_PART_NAME, true) :: BasePart?
			if not sourcePart or not sourcePart:IsA("BasePart") then continue end

			local tpos = sourcePart.Position
			local cf   = makeShotCFrame(tpos, CHAR_DIST, CHAR_HEIGHT, yawBase)
			tweenCamera(cf, CAM_CHAR_DUR, CAM_FOV_MED, idx == 1)

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

	bus:Fire("off")
	disableAllUI()

	-- ✅ 컷씬 끝나자마자 블러(0 -> 20 서서히) + 유지
	fadeInEndingBlur()

	if not ok then
		warn("[Cutscene] error: ", err)
	end

	_isPlaying = false
end

-- ===== 컷씬 버스 수신 =====
CutsceneBus.Event:Connect(function(cmd: any)
	if cmd == "Play" or cmd == "play" then
		playFinalZoneCutscene()
	end
end)

-- ===== 서버에서 보내는 컷씬 시작 신호(Remotes.FinalJump_PlayCutscene) =====
do
	local remotes = RS:WaitForChild("Remotes")
	local ev = remotes:WaitForChild("FinalJump_PlayCutscene") :: RemoteEvent

	ev.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			if payload.cleanup == true then
				cleanupForEnding()
			end
			local mode = tostring(payload.mode or "")
			if mode == "Ending" or mode == "FinalZone" then
				task.defer(playFinalZoneCutscene)
			end
			return
		end

		if payload == nil or payload == "Play" or payload == "play" then
			task.defer(playFinalZoneCutscene)
		end
	end)
end

-- 컷씬 중 리셋 금지 (간섭 방지)
player.CharacterAdded:Connect(function()
	if _isPlaying then return end
	CameraReset.ResetOnce("CharacterAdded")
end)

local UserInputService = game:GetService("UserInputService")

--UserInputService.InputBegan:Connect(function(input, gp)
--	if gp then return end
--	if input.KeyCode == Enum.KeyCode.F6 then
--		playFinalZoneCutscene()
--	end
--end)

print("[FinalZoneCutscene] READY")
