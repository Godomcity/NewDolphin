-- StarterPlayerScripts/QuizClient.lua
--!strict
-- 스테이지용 QuizClient (사다리 연출 + 새 퀘스트 플로우)
--
-- QuestPhase:
--   0: 입장 직후 / 첫 NPC 대화 전 (퀘스트1: 'NPC에게 말걸기')
--   1: 쓰레기 10개 정화 단계 (퀘스트2: '쓰레기 10개 정화')
--   2: 10개 정화 완료 후 NPC 대화 단계 (퀘스트3: 'NPC에게 말걸기')
--   3: 최종 포탈 단계 (퀘스트4: '다음 스테이지로 이동하기')

local Players                 = game:GetService("Players")
local RS                      = game:GetService("ReplicatedStorage")
local TweenService            = game:GetService("TweenService")
local ProximityPromptService  = game:GetService("ProximityPromptService")
local Workspace               = game:GetService("Workspace")
local CollectionService       = game:GetService("CollectionService")

local LP = Players.LocalPlayer

-- ★ 서버에서 받은 진행도 캐시
local SolvedQuiz: {[string]: boolean} = {}
local CutsceneFlags: {[string]: boolean} = {}

-- ========= 유틸/모듈 =========
local function tryRequire(inst: Instance?): any
	if not inst or not inst:IsA("ModuleScript") then return nil end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end

local ActionRouter =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("InteractionActionRouter"))
	or tryRequire(RS:FindFirstChild("InteractionActionRouter"))

local CutscenePlayer =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("Cutscene") and RS.Modules.Cutscene:FindFirstChild("CutscenePlayer"))
	or tryRequire(RS:FindFirstChild("CutscenePlayer"))

local PortalSpawnCutscene =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PortalSpawnCutscene"))
	or tryRequire(RS:FindFirstChild("PortalSpawnCutscene"))

-- ★ 사다리 연출 모듈
local LadderCinematic =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("LadderCinematic"))
	or tryRequire(RS:FindFirstChild("LadderCinematic"))

local playerLock = require(RS:WaitForChild("Modules"):WaitForChild("PlayerLock"))

-- ========= SFX 설정 / 유틸 =========
local SFX = {
	TrashClean  = "rbxassetid://4636006374",       -- 오브젝트 정화
	Wrong       = "rbxassetid://5521959695",       -- 오답
	ChoiceClick = "rbxassetid://9055474333",       -- 보기 클릭
	Correct     = "rbxassetid://114326413874741",  -- 정답
	Submit      = "rbxassetid://15675059323",      -- 제출 버튼 클릭
	QuizOpen    = "rbxassetid://89842591486388",   -- 퀴즈 팝업 열릴 때
	Ladder      = "rbxassetid://87523965330187",   -- 사다리 연출
}

local function playSfx(soundId: string?, volume: number?)
	if not soundId or soundId == "" then return end
	local parent = Workspace.CurrentCamera or LP:FindFirstChild("PlayerGui")
	if not parent then return end

	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.PlayOnRemove = false
	s.Parent = parent
	s:Play()

	s.Ended:Connect(function()
		s:Destroy()
	end)

	-- 혹시 Ended가 안 불려도 정리되도록 안전 타임아웃
	task.delay(5, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- ========= HUD / 퀘스트 / 가이드 버스 =========
local QuizHudBus: BindableEvent do
	local obj = RS:FindFirstChild("QuizHudBus")
	if obj and obj:IsA("BindableEvent") then
		QuizHudBus = obj
	else
		local ev = Instance.new("BindableEvent")
		ev.Name = "QuizHudBus"
		ev.Parent = RS
		QuizHudBus = ev
	end
end

local QuestProgressBus: BindableEvent do
	local obj = RS:FindFirstChild("QuestProgressBus")
	if obj and obj:IsA("BindableEvent") then
		QuestProgressBus = obj
	else
		local ev = Instance.new("BindableEvent")
		ev.Name = "QuestProgressBus"
		ev.Parent = RS
		QuestProgressBus = ev
	end
end

local QuestGuideBus: BindableEvent do
	local obj = RS:FindFirstChild("QuestGuideBus")
	if obj and obj:IsA("BindableEvent") then
		QuestGuideBus = obj
	else
		local ev = Instance.new("BindableEvent")
		ev.Name = "QuestGuideBus"
		ev.Parent = RS
		QuestGuideBus = ev
	end
end

local Hud = {
	Show = function(total:number)
		QuizHudBus:Fire("show", total)
	end,
	Progress = function(n:number, total:number)
		QuizHudBus:Fire("progress", { n = n, total = total })
	end,
	Correct = function(n:number, total:number)
		QuizHudBus:Fire("correct", { n = n, total = total })
	end,
	Wrong = function()
		QuizHudBus:Fire("wrong")
	end,
}

-- ========= Remotes =========
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local RF_Get   = Remotes:FindFirstChild("RF_Quiz_GetQuestion")
if not RF_Get then
	RF_Get = Instance.new("RemoteFunction")
	RF_Get.Name = "RF_Quiz_GetQuestion"
	RF_Get.Parent = Remotes
end

local RF_Check = Remotes:FindFirstChild("RF_Quiz_CheckAnswer")
if not RF_Check then
	RF_Check = Instance.new("RemoteFunction")
	RF_Check.Name = "RF_Quiz_CheckAnswer"
	RF_Check.Parent = Remotes
end

-- ★ 서버 결과 보고용 RemoteEvent (StageQuizResultService.lua 쪽에서 받음)
local RE_StageQuizResult = Remotes:FindFirstChild("RE_StageQuizResult") :: RemoteEvent?
if RE_StageQuizResult and not RE_StageQuizResult:IsA("RemoteEvent") then
	RE_StageQuizResult = nil
end

-- ★ Stage2 진행도 동기화용 Remotes
local RF_Stage2_GetProgress   = Remotes:WaitForChild("RF_Stage2_GetProgress") :: RemoteFunction
local RE_Stage2_QuestSync     = Remotes:WaitForChild("RE_Stage2_QuestSync") :: RemoteEvent
local RE_Stage2_CutsceneFlag  = Remotes:WaitForChild("RE_Stage2_CutsceneFlag") :: RemoteEvent
local RE_Stage2_ObjectCleaned = Remotes:WaitForChild("RE_Stage2_ObjectCleaned") :: RemoteEvent
local RE_Stage2_QuizSolved    = Remotes:WaitForChild("RE_Stage2_QuizSolved") :: RemoteEvent

local RE_Stage2_QuizRuntime   = Remotes:WaitForChild("RE_Stage2_QuizRuntime") :: RemoteEvent -- ★ 점수/시간 실시간 저장용

-- ========= 상수/태그 =========
local UI_NAME             = "QuizGui"
local TOTAL_QUESTIONS     = 10
local CUTSCENE_THRESHOLD  = 4       -- 4문제 맞추면 사다리 연출

local DIALOGUE_START_TAG  = "DialoguePrompt"
local QUIZ_TARGET_TAG     = "QuizPrompt"
local LOCAL_PROMPT_NAME   = "_ClientOnlyPrompt"

--- 사다리 템플릿/위치
local STAGE2_LADDER_NAME      = "Stage2Ladder"
local STAGE2_LADDER_FIXED_POS = Vector3.new(-59.745, 29.593, 125.927)

-- 🔹 사다리 템플릿 (ReplicatedStorage 안에 있어야 함)
local LADDER_TEMPLATE = RS:WaitForChild("Stage2Ladder")
local LADDER_POS      = STAGE2_LADDER_FIXED_POS

-- 🔹 카메라 연출용 포인트들 (테스트 스크립트 값 그대로)
local WIDE_POS   = Vector3.new(-3.0, 45.0, 150.0)
local MID_POS    = Vector3.new(-15.0, 38.0, 135.0)
local CLOSE_POS  = Vector3.new(-30.0, 33.0, 128.0)

local WIDE_FOV   = 78
local MID_FOV    = 68
local CLOSE_FOV  = 60
local CUT_EASE        = Enum.EasingStyle.Sine

-- 포탈(요청: Stage1 스타일, Stage2 고정 위치)
local PORTAL_FIXED_POS = Vector3.new(-160.87, 72.704, 91.992)

local QUEST_NPC_TAG       = "QuestNPC"
local FIRST_TRASH_TAG     = "QuestObject"
local PORTAL_TEMPLATE_NAME= "Potal"

-- 사다리 템플릿/위치
local LADDER_TEMPLATE_NAME = "Stage2Ladder"
local LADDER_FIXED_POS     = Vector3.new(-59.745, 29.593, 125.927)

-- ========= 상태 =========
local function getState()
	local pg = LP:WaitForChild("PlayerGui")
	local folder = pg:FindFirstChild("_QuizState")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "_QuizState"
		folder.Parent = pg
	end

	local function I(n:string)
		local v = folder:FindFirstChild(n)
		if not v then
			v = Instance.new("IntValue")
			v.Name = n
			v.Parent = folder
		end
		return v
	end

	local function B(n:string,d:boolean)
		local v = folder:FindFirstChild(n)
		if not v then
			v = Instance.new("BoolValue")
			v.Name = n
			v.Value = d
			v.Parent = folder
		end
		return v
	end

	return {
		Folder        = folder,
		Asked         = I("Asked"),
		Solved        = I("Solved"),
		QuestPhase    = I("QuestPhase"),   -- 0~3
		ExtraTrash    = I("ExtraTrash"),   -- 0~10
		HudShown      = B("HudShown", false),
		PortalSpawned = B("PortalSpawned", false),
		DoorCutDone   = B("DoorCutDone", false),
		ZoomPlayed    = B("ZoomPlayed", false),
	}
end

local STATE = getState()
local cutsceneSent = (STATE.Solved.Value >= CUTSCENE_THRESHOLD)

local busy = false
local currentPrompt: ProximityPrompt? = nil
local currentIsFirstTrash = false

-- ★ 퀴즈 전체 점수/시간 측정용
local quizStartedAt: number? = nil
local totalScore = 0
local savedElapsedBeforeReconnect = 0 -- ★ 재접속 전에 이미 진행된 시간(초)

-- ========= 태그 유틸 =========
local function isUnderTag(inst: Instance?, tagName: string): boolean
	local cur: Instance? = inst
	while cur do
		if CollectionService:HasTag(cur, tagName) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function isUnderQuestNPC(inst: Instance): boolean
	return isUnderTag(inst, QUEST_NPC_TAG)
end

local function isUnderFirstTrash(inst: Instance): boolean
	return isUnderTag(inst, FIRST_TRASH_TAG)
end

-- ========= SessionObjectId 헬퍼 =========
local function getCleanedObjectIdFromPrompt(prompt: Instance?): string?
	if not prompt then return nil end

	local cur: Instance? = prompt
	while cur and cur ~= Workspace do
		local idAttr = cur:GetAttribute("SessionObjectId")
		if typeof(idAttr) == "string" and idAttr ~= "" then
			return idAttr
		end

		local idVal = cur:FindFirstChild("SessionObjectId")
		if idVal and idVal:IsA("StringValue") and idVal.Value ~= "" then
			return idVal.Value
		end

		cur = cur.Parent
	end

	warn("[Stage2][QuizClient] SessionObjectId not found for prompt:", prompt:GetFullName())
	return nil
end

local function findBySessionObjectId(objectId: string): Instance?
	if objectId == "" then return nil end
	for _, inst in ipairs(Workspace:GetDescendants()) do
		local a = inst:GetAttribute("SessionObjectId")
		if typeof(a) == "string" and a == objectId then
			return inst
		end
		local s = inst:FindFirstChild("SessionObjectId")
		if s and s:IsA("StringValue") and s.Value == objectId then
			return inst
		end
	end
	return nil
end

-- ActionRouter.run 을 이용해서 로컬에서만 삭제
local function localDisappearByInstance(inst: Instance)
	if not ActionRouter or typeof(ActionRouter.run) ~= "function" then return end

	local ok, err = pcall(function()
		ActionRouter.run(inst, {
			fadeDuration = 0.35,
			delayDestroy = 0.0,
		}, {
			targetTags = { "Disappear", "VanishOnCorrect", "Box", "seaShell" },
		})
	end)
	if not ok then
		warn("[Stage2][QuizClient] localDisappearByInstance error:", err)
	end
end

local function localDisappearByPrompt(prompt: ProximityPrompt)
	if not prompt then return end
	localDisappearByInstance(prompt)
end

local function localDisappearByObjectId(objectId: string)
	local inst = findBySessionObjectId(objectId)
	if not inst then return end
	localDisappearByInstance(inst)
end


-- ========= 프롬프트 분류 =========
local function isDialogueStartPrompt(pp: ProximityPrompt): boolean
	if CollectionService:HasTag(pp, DIALOGUE_START_TAG) then
		return true
	end
	return isUnderQuestNPC(pp)
end

local function isQuizPrompt(pp: ProximityPrompt): boolean
	if CollectionService:HasTag(pp, QUIZ_TARGET_TAG) then return true end
	if isUnderFirstTrash(pp) then return true end
	if pp.Name == LOCAL_PROMPT_NAME then return true end
	return false
end

-- ========= 프롬프트 제어 =========
local function setPromptEnabled(pp: ProximityPrompt, enabled: boolean, dist:number?)
	pp.Enabled = enabled
	pp.MaxActivationDistance = enabled and (dist or 10) or 0
end

local function forEachQuizPrompt(fn: (ProximityPrompt) -> ())
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") and isQuizPrompt(inst) then
			fn(inst)
		end
	end
end

local function disableAllQuizPrompts()
	forEachQuizPrompt(function(pp)
		setPromptEnabled(pp, false, 0)
	end)
end

local function enableAllQuizPrompts()
	forEachQuizPrompt(function(pp)
		setPromptEnabled(pp, true, 10)
	end)
end

local function enableOnlyFirstTrashPrompt()
	forEachQuizPrompt(function(pp)
		if isUnderFirstTrash(pp) then
			setPromptEnabled(pp, true, 10)
		else
			setPromptEnabled(pp, false, 0)
		end
	end)
end

local function forEachNPCPrompt(fn: (ProximityPrompt) -> ())
	for _, inst in ipairs(CollectionService:GetTagged(QUEST_NPC_TAG)) do
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				fn(d)
			end
		end
	end
end

local function enableNPCPrompts()
	forEachNPCPrompt(function(pp)
		setPromptEnabled(pp, true, 10)
	end)
end

local function disableNPCPrompts()
	forEachNPCPrompt(function(pp)
		setPromptEnabled(pp, false, 0)
	end)
end

-- ========= 레거시 QuizScreen 제거 =========
local function killLegacyQuizScreens()
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then return end
	for _,g in ipairs(pg:GetChildren()) do
		if g:IsA("ScreenGui") and (g.Name == "QuizScreen" or g.Name == "QuizScreen(Clone)") then
			g:Destroy()
		end
	end
end

killLegacyQuizScreens()

-- ========= UI =========
type UIRefs = {
	gui: ScreenGui,
	root: Frame,
	bg: Frame,
	lblQ: TextLabel,
	lblScore: TextLabel,
	btns: {ImageButton},
	btnLabels: {TextLabel},
	btnAnswer: ImageButton
}

local function ensureUI(): ScreenGui
	local pg = LP:WaitForChild("PlayerGui")
	killLegacyQuizScreens()
	local gui = pg:WaitForChild(UI_NAME) :: ScreenGui
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return gui
end

local function getUIRefs(gui: ScreenGui): UIRefs
	local root = gui:WaitForChild("Frame") :: Frame
	local bg   = root:WaitForChild("BackGround") :: Frame
	local frame = bg:WaitForChild("Frame")
	local A = frame:WaitForChild("AButton") :: ImageButton
	local B = frame:WaitForChild("BButton") :: ImageButton
	local C = frame:WaitForChild("CButton") :: ImageButton
	local D = frame:WaitForChild("DButton") :: ImageButton
	local Answer = bg:WaitForChild("AnswerButton") :: ImageButton

	local qText  = bg:WaitForChild("QuestionText")  :: TextLabel
	local qScore = bg:WaitForChild("QuestionScore") :: TextLabel

	return {
		gui = gui,
		root = root,
		bg  = bg,
		lblQ = qText,
		lblScore = qScore,
		btns = {A,B,C,D},
		btnLabels = {
			(A:WaitForChild("TextLabel") :: TextLabel),
			(B:WaitForChild("TextLabel") :: TextLabel),
			(C:WaitForChild("TextLabel") :: TextLabel),
			(D:WaitForChild("TextLabel") :: TextLabel),
		},
		btnAnswer = Answer
	}
end

-- ========= 색/시각 =========
local BTN_IDLE_TINT        = Color3.fromRGB(255,255,255)
local SELECT_IMAGE_TINT    = Color3.fromRGB(210,210,210)
local BTN_CORRECT_TINT     = Color3.fromRGB(120,205,155)
local BTN_WRONG_TINT       = Color3.fromRGB(245,140,140)
local TWEEN_TIME           = 0.12

-- Answer 버튼 스프라이트
local SUBMIT_IDLE_IMAGE      = "rbxassetid://126747125602042"
local SUBMIT_SELECTED_IMAGE  = "rbxassetid://81469623772442"

local function tweenImageColor(imgBtn: ImageButton, toColor: Color3)
	TweenService:Create(imgBtn, TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		ImageColor3 = toColor
	}):Play()
end

local function setButtonVisual(imgBtn: ImageButton, kind: "idle"|"selected"|"correct"|"wrong")
	local map = {
		idle     = BTN_IDLE_TINT,
		selected = SELECT_IMAGE_TINT,
		correct  = BTN_CORRECT_TINT,
		wrong    = BTN_WRONG_TINT,
	}
	tweenImageColor(imgBtn, map[kind])
end

local function setButtonState(imgBtn: ImageButton, correct: boolean)
	setButtonVisual(imgBtn, correct and "correct" or "wrong")
end

local function showStroke(_: GuiButton, _: boolean) end
local function hideAllStrokes(_: {GuiButton}) end
-- ========= NPC 이동 =========
local function moveQuestNPCToSpawnOnce(): boolean
	local spawn = Workspace:FindFirstChild("NpcSpawnPart")
	if not (spawn and spawn:IsA("BasePart")) then
		warn("[QuizClient] NpcSpawnPart 를 찾지 못했습니다.")
		return false
	end

	local moved = false
	for _, inst in ipairs(CollectionService:GetTagged(QUEST_NPC_TAG)) do
		if inst:IsA("Model") then
			local ok = pcall(function()
				(inst :: Model):PivotTo((spawn :: BasePart).CFrame)
			end)
			if ok then moved = true end
		elseif inst:IsA("BasePart") then
			local ok = pcall(function()
				(inst :: BasePart).CFrame = (spawn :: BasePart).CFrame
			end)
			if ok then moved = true end
		end
	end

	if not moved then
		warn("[QuizClient] QuestNPC 태그가 붙은 NPC를 찾지 못했습니다.")
	end
	return moved
end

local function moveQuestNPCToSpawn()
	-- NPC / NpcSpawnPart 가 늦게 생성될 수 있으니 최대 5초간 재시도
	local deadline = os.clock() + 5
	while os.clock() < deadline do
		if moveQuestNPCToSpawnOnce() then
			print("[QuizClient] NPC 이동 완료(재시작/재입장 포함).")
			return
		end
		task.wait(0.3) -- 0.3초마다 다시 시도
	end
	warn("[QuizClient] NPC 이동 재시도 타임아웃(5초) – NpcSpawnPart 또는 QuestNPC 없음.")
end

-- ========= 유틸: 사다리 하위 파트만 투명 유지 =========
local function makeChildrenPartsTransparent(root: Instance, alpha: number)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent ~= root then
			d.Transparency = alpha
			for _,x in ipairs(d:GetDescendants()) do
				if x:IsA("Decal") or x:IsA("Texture") then x.Transparency = alpha end
			end
		end
	end
end

-- ★ 사다리 컷씬 (CutSceneCamPos -> CutSceneCamEndPos 한 번에 스무스 무빙)
local LadderCutBusy = false

local function playLadderCameraCutscene_thenSpawnThenZoom(): Instance?
	-- 한 번만 재생
	if STATE.ZoomPlayed.Value then return nil end

	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	if LadderCutBusy then return nil end

	LadderCutBusy = true
	STATE.ZoomPlayed.Value = true

	-- 카메라 백업
	local oldType = camera.CameraType
	local oldCF   = camera.CFrame
	local oldFOV  = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable

	-- 🔹 컷씬용 카메라 파트 찾기
	local startPart = Workspace:FindFirstChild("CutSceneCamPos")
	local endPart   = Workspace:FindFirstChild("CutSceneCamEndPos")

	-- 둘 다 없으면 그냥 기존 위치에서 아무 것도 안 함
	if not (startPart and endPart and startPart:IsA("BasePart") and endPart:IsA("BasePart")) then
		warn("[QuizClient] CutSceneCamPos / CutSceneCamEndPos 를 찾지 못했습니다.")
		camera.CameraType  = oldType
		camera.CFrame      = oldCF
		camera.FieldOfView = oldFOV
		LadderCutBusy = false
		return nil
	end

	local startCF = (startPart :: BasePart).CFrame
	local endCF   = (endPart   :: BasePart).CFrame

	-- 시작 세팅
	camera.CFrame      = startCF
	camera.FieldOfView = 70

	-- 🔹 사다리 드롭은 카메라가 움직이는 동안 약간 뒤에 시작
	local spawnedLadder: Instance? = nil
	task.delay(0.4, function()
		if not LadderCinematic or not LADDER_TEMPLATE then return end
		spawnedLadder = LadderCinematic.spawnAndAnimate({
			template   = LADDER_TEMPLATE,
			position   = LADDER_POS,
			parent     = workspace,
			dropHeight = 18,
			dropTime   = 0.8,
			bouncePower= 1.0,
			keepChildrenTransparent = true,
			soundId    = SFX.Ladder,
			soundVolume= 1,
		})
	end)

	-- 🔹 한 번에 스무스하게 startCF -> endCF 로만 이동 (중간 스탑 없음)
	local totalTime = 2.8 -- 필요하면 시간 조절
	local camTween = TweenService:Create(
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
	camTween:Play()
	camTween.Completed:Wait()

	-- 약간 더 보여주고
	task.wait(0.2)

	-- 원래 플레이어 카메라로 부드럽게 복귀
	local restoreTween = TweenService:Create(
		camera,
		TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			CFrame      = oldCF,
			FieldOfView = oldFOV,
		}
	)
	restoreTween:Play()
	restoreTween.Completed:Wait()

	camera.CameraType  = oldType
	LadderCutBusy = false

	-- 사다리 완전히 보이게 (원하면 유지)
	if spawnedLadder then
		makeChildrenPartsTransparent(spawnedLadder, 0)
	end

	return spawnedLadder
end

-- ========= 버튼 히트 =========
local function safeSet(obj: Instance, prop: string, value: any)
	local ok = pcall(function() (obj :: any)[prop] = value end)
	return ok
end

local function prepareButtonHitArea(btn: GuiButton)
	btn.AutoButtonColor = false
	btn.Active = true
	local baseZ = btn.ZIndex
	for _, d in ipairs(btn:GetDescendants()) do
		if d:IsA("GuiObject") and d ~= btn then
			safeSet(d, "Active", false)
			safeSet(d, "InputTransparent", true)
			d.ZIndex = math.max(0, baseZ - 1)
		end
	end
end

-- ========= DialogueBus =========
local function getDialogueBus(timeout:number?): BindableEvent?
	local b = RS:FindFirstChild("DialogueUIBus")
	if b and b:IsA("BindableEvent") then
		return b
	end
	b = RS:WaitForChild("DialogueUIBus", timeout or 5)
	if b and b:IsA("BindableEvent") then
		return b
	end
	return nil
end

-- ========= 퀘스트 상태 서버 동기화 =========
local isLoadingProgress = false

local function syncQuestToServer()
	if isLoadingProgress then return end
	if not RE_Stage2_QuestSync then return end

	local phase = STATE.QuestPhase.Value
	local extra = STATE.ExtraTrash.Value

	local ok, err = pcall(function()
		RE_Stage2_QuestSync:FireServer(phase, extra)
	end)
	if not ok then
		warn("[Stage2][QuizClient] syncQuestToServer failed:", err)
	end
end

local function applyQuestPhaseFromState()
	local phase = STATE.QuestPhase.Value
	local extra = STATE.ExtraTrash.Value

	if phase == 0 then
		-- [0] 첫 입장: NPC 대사
		disableAllQuizPrompts()
		enableNPCPrompts()
		if QuestGuideBus then
			QuestGuideBus:Fire("targetNPC")
		end
	elseif phase ==1 then
		enableAllQuizPrompts()

	elseif phase == 3 then
		-- [3] 쓰레기 10개 다 정화 후, NPC에게 다시 말 걸어야 하는 단계
		disableAllQuizPrompts()
		enableNPCPrompts()
		if QuestGuideBus then
			QuestGuideBus:Fire("targetNPC")
		end

	elseif phase >= 4 then
		-- [4+] 포탈로 이동하기 단계
		disableAllQuizPrompts()
		enableNPCPrompts()

		if QuestGuideBus then
			if _G.spawnedPortal then
				QuestGuideBus:Fire("targetPortal", _G.spawnedPortal)
			else
				QuestGuideBus:Fire("targetPortal")
			end
		end
	end

	-- QuestGui 동기화
	if QuestProgressBus then
		local questIndex = 1
		if phase <= 0 then
			questIndex = 1              -- 퀘스트1: NPC에게 말걸기
		elseif phase == 1 or phase == 2 then
			questIndex = 2              -- 퀘스트2: 쓰레기 10개 정화
		elseif phase == 3 then
			questIndex = 3              -- 퀘스트3: NPC에게 말걸기(두번째)
		else
			questIndex = 4              -- 퀘스트4: 다음 스테이지로 이동하기
		end

		QuestProgressBus:Fire(questIndex)

		if phase == 1 or phase == 2 then
			QuestProgressBus:Fire({
				type  = "trashProgress",
				count = math.clamp(extra, 0, 10),
				total = 10,
			})
		end
	end
end



-- ========= 한 문제 열기 =========
type QDto = { id: string, q: string, c: {string} }

local function openOneQuestion()
	if not RF_Get or not RF_Check then
		warn("[QuizClient] Remotes missing")
		busy = false
		return
	end
	
	playerLock.Lock({freezeCharacter = true, freezeCamera = true, disableInput = true})

	-- ★ 이미 모든 문제를 풀었다면 퀴즈 열지 않음
	if STATE.Solved.Value >= TOTAL_QUESTIONS then
		print("[Stage2][QuizClient] 이미 모든 문제 해결 → 퀴즈창 열지 않음")
		busy = false
		return
	end

	local gui = ensureUI()
	local UI  = getUIRefs(gui)
	local btns, lbls = UI.btns, UI.btnLabels

        -- 문제 1개 가져오기
        local q: QDto? = nil
        local choiceIdByIndex: {[number]: number} = {}
        -- ★ 지금까지 맞힌 문제 리스트 전달
        local solvedList = {}
        for qidStr, flag in pairs(SolvedQuiz) do
                if flag then table.insert(solvedList, qidStr) end
        end

        local ok, res = pcall(function()
                return (RF_Get :: RemoteFunction):InvokeServer(solvedList)
        end)
        if ok then
                if typeof(res) == "table" and res.ok == true and typeof(res.data) == "table" then
                        q = res.data
                else
                        q = res
                end
        end

        if q and typeof(q) == "table" then
                if not q.id and q.quizId then
                        q.id = q.quizId
                end

                if q.choices and typeof(q.choices) == "table" then
                        table.sort(q.choices, function(a, b)
                                return (tonumber(a.choiceNumber) or 0) < (tonumber(b.choiceNumber) or 0)
                        end)

                        local cTexts: {[number]: string} = {}
                        for _, ch in ipairs(q.choices) do
                                local idx = tonumber(ch.choiceNumber) or 0
                                if idx >= 1 and idx <= 4 then
                                        cTexts[idx] = tostring(ch.choiceText or ch.text or ch.title or "")
                                        choiceIdByIndex[idx] = tonumber(ch.quizChoiceId) or tonumber(ch.id) or idx
                                end
                        end

                        if next(cTexts) then
                                q.c = cTexts
                        end
                end
        end
	if not q or not q.id then gui.Enabled=false busy=false return end
	local currentQid = q.id
	local currentQidStr = tostring(currentQid)

	-- ★ 혹시 이미 푼 문제면 방어적으로 스킵
	if SolvedQuiz[currentQidStr] then
		print("[Stage2][QuizClient] 이미 푼 문제 받음 → 스킵:", currentQidStr)
		gui.Enabled = false
		busy = false
		return
	end

	-- ★ 첫 문제를 여는 순간 시작 시간 초기화 + 점수 리셋
	if not quizStartedAt then
		quizStartedAt = os.clock() - savedElapsedBeforeReconnect
		-- totalScore 는 loadStage2Progress()에서 복구되므로 여기서 리셋하지 않음
	end

	-- HUD
	if not STATE.HudShown.Value then
		Hud.Show(TOTAL_QUESTIONS)
		STATE.HudShown.Value = true
	end
	local idx = math.clamp(STATE.Solved.Value + 1, 1, TOTAL_QUESTIONS)
	Hud.Progress(STATE.Solved.Value, TOTAL_QUESTIONS)
	-- ★ 점수도 같이 표시
	UI.lblScore.Text = string.format("QUESTION %d / %d", idx, TOTAL_QUESTIONS)

	-- UI 초기화
	UI.root.Visible = true
	UI.lblQ.Text = q.q or ""
	for i=1,4 do
		lbls[i].Text = (q.c and q.c[i]) or ""
		btns[i].Active = true
		prepareButtonHitArea(btns[i])
		setButtonVisual(btns[i], "idle")
	end
	hideAllStrokes(btns)

	-- Answer 버튼 초기화
	UI.btnAnswer.AutoButtonColor = false
	UI.btnAnswer.Active, UI.btnAnswer.Visible = true, true
	UI.btnAnswer.Image = SUBMIT_IDLE_IMAGE
	UI.btnAnswer.ImageColor3 = Color3.fromRGB(255,255,255)

	gui.Enabled = true

	-- 퀴즈 팝업 사운드
	playSfx(SFX.QuizOpen)

	local inputLocked = false
	local selected: number? = nil
	-- ★ 이 문제에서 시도 횟수
	local attempts = 0

	busy = true
	STATE.Asked.Value += 1

	local conns: {RBXScriptConnection} = {}
	local function cleanupAll()
		for _,c in ipairs(conns) do
			pcall(function() c:Disconnect() end)
		end
		conns = {}
	end

	local function select(i:number)
		if inputLocked then return end
		if not btns[i].Active then return end
		selected = i
		for j=1,4 do
			setButtonVisual(btns[j], (j==i) and "selected" or "idle")
		end
		UI.btnAnswer.Image = SUBMIT_SELECTED_IMAGE

		-- 보기 클릭 사운드
		playSfx(SFX.ChoiceClick)
	end

	for i=1,4 do
		local b = btns[i]
		conns[#conns+1] = b.Activated:Connect(function() select(i) end)
		conns[#conns+1] = b.MouseButton1Click:Connect(function() select(i) end)
		conns[#conns+1] = b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				select(i)
			end
		end)
	end

	conns[#conns+1] = UI.btnAnswer.MouseButton1Click:Connect(function()
		-- 제출 버튼 클릭 사운드
		playSfx(SFX.Submit)

		if inputLocked then return end
		if not selected then
			local orig = UI.btnAnswer.Size
			TweenService:Create(UI.btnAnswer, TweenInfo.new(0.08), {Size = orig + UDim2.fromOffset(6,6)}):Play()
			task.delay(0.1, function()
				TweenService:Create(UI.btnAnswer, TweenInfo.new(0.08), {Size = orig}):Play()
			end)
			return
		end
		inputLocked = true

		-- ★ 이 문제에 대한 시도 횟수 증가
		attempts += 1

                local result = nil
                local choiceId = choiceIdByIndex[selected :: number] or selected :: number
                local quizStorageId = (q and q.quizStorageId) or currentQid
                local ok2, res2 = pcall(function()
                        return (RF_Check :: RemoteFunction):InvokeServer(choiceId, quizStorageId)
                end)
                if ok2 then result = res2 end

		local isCorrect = result and result.correct == true

		if isCorrect then
			-- 정답 사운드
			playSfx(SFX.Correct)
			playerLock.Unlock()
			-- ★ 시도 횟수에 따라 점수 부여
			local gained
			if attempts <= 1 then
				gained = 10
			elseif attempts == 2 then
				gained = 8
			elseif attempts == 3 then
				gained = 6
			else
				gained = 4
			end
			totalScore += gained

			-- ★ 현재까지 경과 시간 계산
			local elapsedSec = 0
			if quizStartedAt then
				elapsedSec = math.max(0, math.floor(os.clock() - quizStartedAt + 0.5))
			end

			-- ★ 서버에 점수/시간 실시간 저장
			if RE_Stage2_QuizRuntime then
				pcall(function()
					RE_Stage2_QuizRuntime:FireServer(totalScore, elapsedSec)
				end)
			end

			setButtonState(btns[selected :: number], true)

			task.delay(0.22, function()
				-- ★ 1) 이 qid 를 로컬/서버에 '푼 문제'로 기록
				local qidStr = tostring(currentQid)
				SolvedQuiz[qidStr] = true
				if RE_Stage2_QuizSolved then
					RE_Stage2_QuizSolved:FireServer(qidStr)
				end

				STATE.Solved.Value += 1
				local solved = STATE.Solved.Value

				Hud.Correct(solved, TOTAL_QUESTIONS)

				-- ★ 2) 오브젝트의 SessionObjectId 추출 → 로컬 삭제 + 서버 보고
				do
					local cleanedObjectId: string? = nil
					local anchorInst: Instance? = currentPrompt
					if anchorInst then
						cleanedObjectId = getCleanedObjectIdFromPrompt(anchorInst)
						if cleanedObjectId then
							print("[Stage2][QuizClient] cleaned objectId =", cleanedObjectId)
						end
					end

					-- 이 플레이어에게만 오브젝트 로컬 삭제
					if cleanedObjectId then
						localDisappearByObjectId(cleanedObjectId)
					elseif currentPrompt then
						localDisappearByPrompt(currentPrompt)
					end

					-- 서버에 정화된 오브젝트 ID 보고
					if cleanedObjectId and RE_Stage2_ObjectCleaned then
						RE_Stage2_ObjectCleaned:FireServer(cleanedObjectId)
					end
				end

				-- ★ 3) 기존 상위 태그 액션 (Box/seaShell/Disappear/DoorOpen/PortalNeonOn)
				do
					local anchorInst: Instance? = currentPrompt
					if anchorInst and ActionRouter then
						local targetTags = { "Box", "seaShell", "Disappear", "DoorOpen", "PortalNeonOn" }
						local ctx = { fadeDuration = 0.35, delayDestroy = 0.0, portalColor = Color3.fromRGB(0,255,120) }
						pcall(ActionRouter.run, anchorInst, ctx, {
							targetTags = targetTags,
							debounce   = true,
						})
					end
				end

				-- 쓰레기 10개 정화 진행 (QuestPhase = 1)
				if STATE.QuestPhase.Value == 1 then
					STATE.ExtraTrash.Value += 1
					local cleared = math.clamp(STATE.ExtraTrash.Value, 0, 10)

					-- 쓰레기 정화 사운드
					playSfx(SFX.TrashClean)

					if QuestProgressBus then
						QuestProgressBus:Fire({
							type  = "trashProgress",
							count = cleared,
							total = 10,
						})
					end

					if cleared >= 10 then
						STATE.QuestPhase.Value = 3
						if QuestProgressBus then
							QuestProgressBus:Fire("complete") -- 퀘스트2 완료
						end
						disableAllQuizPrompts()
						enableNPCPrompts()
						if QuestGuideBus then
							QuestGuideBus:Fire("targetNPC")
						end
					end
				end

				-- 4문제 이상 → NPC 이동 + 사다리 컷씬 (1회)
				if not cutsceneSent and solved >= CUTSCENE_THRESHOLD then
					cutsceneSent = true

					-- ★ 서버에도 컷씬 플래그 저장
					if RE_Stage2_CutsceneFlag then
						RE_Stage2_CutsceneFlag:FireServer("ladder_cut")
					end

					-- 퀴즈 UI는 바로 닫기
					if gui and gui.Enabled then
						gui.Enabled = false
					end

					local DELAY_BEFORE_LADDER_CUT = 1.2

					task.delay(DELAY_BEFORE_LADDER_CUT, function()
						pcall(moveQuestNPCToSpawn)
						playLadderCameraCutscene_thenSpawnThenZoom()
					end)
				end

				-- ★ 10문제 모두 맞춘 시점에 점수/시간 서버에 전송
				if solved >= TOTAL_QUESTIONS then
					local elapsed = 0
					if quizStartedAt then
						elapsed = math.max(0, os.clock() - quizStartedAt)
					end
					local timeSec = math.floor(elapsed + 0.5)

					if RE_StageQuizResult then
						pcall(function()
							(RE_StageQuizResult :: RemoteEvent):FireServer(totalScore, timeSec)
						end)
					else
						warn(("[QuizClient] RE_StageQuizResult missing; score=%d, time=%ds not sent")
							:format(totalScore, timeSec))
					end
				end

				-- 다음 문제/정리
				if currentPrompt then currentPrompt.Enabled = false end
				currentPrompt = nil
				currentIsFirstTrash = false
				gui.Enabled = false
				busy = false
				cleanupAll()
			end)
		else
			-- 오답 사운드
			playSfx(SFX.Wrong)

			Hud.Wrong()
			local i = selected :: number
			setButtonState(btns[i], false)
			btns[i].Active = false
			task.delay(0.35, function()
				if btns[i] and btns[i].Parent then
					btns[i].Active = true
					setButtonVisual(btns[i], "idle")
				end
				inputLocked = false
				selected = nil
				UI.btnAnswer.Image = SUBMIT_IDLE_IMAGE
			end)
		end
	end)
end

-- ========= 프롬프트 이벤트 =========
local GLOBAL_COOLDOWN_SEC = 0.6
local lastUseTick = 0

ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	if player ~= LP then return end
	local now = os.clock()
	if busy or (now - lastUseTick) < GLOBAL_COOLDOWN_SEC then return end
	lastUseTick = now

	-- 퀴즈 프롬프트
	if isQuizPrompt(prompt) then
		busy = true
		currentPrompt = prompt
		currentIsFirstTrash = isUnderFirstTrash(prompt)
		openOneQuestion()
		return
	end

	-- NPC 대화 프롬프트
	if isDialogueStartPrompt(prompt) then
		busy = true
		currentPrompt = prompt
		currentIsFirstTrash = false

		local DialogueBus = getDialogueBus(5)
		if not DialogueBus then
			warn("[QuizClient] DialogueUIBus 를 찾지 못했습니다.")
			busy = false
			currentPrompt = nil
			return
		end

		local phase = STATE.QuestPhase.Value
		local solved = STATE.Solved.Value
		local extra  = STATE.ExtraTrash.Value

		-- 어떤 대사 세트를 쓸지 (DialogueData.phases 인덱스)
		local questPhaseForDialogue: number

		if phase <= 0 then
			questPhaseForDialogue = 1
		elseif phase == 1 then
			questPhaseForDialogue = 3
		else
			questPhaseForDialogue = 4
		end

		-- 대화 중에는 NPC 프롬프트 잠시 비활성화
		disableNPCPrompts()

		DialogueBus:Fire("Play", {
			npc        = prompt.Parent,
			questPhase = questPhaseForDialogue,
			solved     = solved,
			total      = TOTAL_QUESTIONS,
		})

		local initialPhase = phase
		local finishedConn: RBXScriptConnection? = nil

		finishedConn = DialogueBus.Event:Connect(function(cmd:any)
			if cmd ~= "Finished" then return end
			if finishedConn then
				finishedConn:Disconnect()
				finishedConn = nil
			end

			-- 대화 시작 직전 phase 기준으로 분기
			if initialPhase == 0 then
				-- [1] 첫 NPC 대사 끝 → 퀘스트1 완료, 퀘스트2 시작
				STATE.QuestPhase.Value = 1

				if QuestProgressBus then
					QuestProgressBus:Fire("complete")
				end

				enableAllQuizPrompts()
				-- 첫 대화 이후에도 NPC 프롬프트 유지
				enableNPCPrompts()

				if QuestGuideBus then
					QuestGuideBus:Fire("targetMoreTrash") -- Arrow 쪽에서 숨기도록 구현됨
				end

			elseif initialPhase == 1 then
				-- [2] 진행 중에 NPC에게 말 걸었다가 끝난 경우
				enableNPCPrompts()
				if QuestGuideBus then
					QuestGuideBus:Fire("targetMoreTrash")
				end

			else
				-- [3] 쓰레기 10개 정화 완료 후 NPC 대화(Phase 2 이상)
				if STATE.QuestPhase.Value < 3 then
					STATE.QuestPhase.Value = 3
					QuestProgressBus:Fire("complete")
				end

				if QuestProgressBus then
					QuestProgressBus:Fire("complete") -- 퀘스트3 완료 → 퀘스트4
				end

				-- 포탈로 화살표 안내
				if QuestGuideBus then
					task.delay(1.0, function()
						if _G.spawnedPortal ~= nil then
							QuestGuideBus:Fire("targetPortal", _G.spawnedPortal)
						else
							QuestGuideBus:Fire("targetPortal")
						end
					end)
				end
			end

			busy = false
			currentPrompt = nil
		end)

		return
	end
end)

local function waitForSessionId(timeoutSec: number?)
	local deadline = os.clock() + (timeoutSec or 5)
	while os.clock() < deadline do
		local sid = LP:GetAttribute("sessionId")
		if typeof(sid) == "string" and sid ~= "" then
			print("[Stage2][QuizClient] sessionId ready:", sid)
			return
		end
		task.wait(0.1)
	end
	warn("[Stage2][QuizClient] sessionId not set in time → 진행도 없이 시작")
end

local function loadStage2Progress()
	isLoadingProgress = true

	local ok, res = pcall(function()
		return RF_Stage2_GetProgress:InvokeServer()
	end)
	if not ok or typeof(res) ~= "table" then
		warn("[Stage2][QuizClient] RF_Stage2_GetProgress failed:", res)
		isLoadingProgress = false
		return
	end

	SolvedQuiz    = res.quizSolved or {}
	CutsceneFlags = res.cutscenes or {}

	print("[Stage2][QuizClient] progress loaded. solved qids:", SolvedQuiz, "cutscenes:", CutsceneFlags)

	-- ★ 이미 푼 문제 개수 계산
	local solvedCount = 0
	for _, v in pairs(SolvedQuiz) do
		if v then solvedCount += 1 end
	end
	if solvedCount > 0 then
		solvedCount = math.clamp(solvedCount, 0, TOTAL_QUESTIONS)
		STATE.Solved.Value = solvedCount

		STATE.HudShown.Value = true
		Hud.Show(TOTAL_QUESTIONS)
		Hud.Progress(STATE.Solved.Value, TOTAL_QUESTIONS)
		--Hud.Correct(STATE.Solved.Value, TOTAL_QUESTIONS)
	end

	-- QuestPhase 복구
	local stageQuestPhase = tonumber(res.questPhase)
	if stageQuestPhase then
		-- 이상한 값 들어올 때 최소/최대 방어 (원하면 빼도 됨)
		if stageQuestPhase < 0 then
			stageQuestPhase = 0
		end
		STATE.QuestPhase.Value = stageQuestPhase
	end

	-------------------------------------------------------
	-- ★ extraTrash 보정: savedExtraTrash vs cleanedObjects
	-------------------------------------------------------
	local cleanedMap = res.cleanedObjects
	local cleanedCount = 0

	if typeof(cleanedMap) == "table" then
		for objectId, flag in pairs(cleanedMap) do
			if flag == true then
				cleanedCount += 1
			end
		end
	end

	-- 서버에 DataStore로 저장된 extraTrash (없으면 0)
	local savedExtraTrash = tonumber(res.extraTrash) or 0

	-- cleanedObjects 개수 기반으로 추정한 extraTrash
	-- (Stage2는 쓰레기 10개 정화 단계라 max 10)
	local derivedExtraTrash = math.clamp(cleanedCount, 0, 10)

	-- ★ 두 값 중 더 큰 쪽으로 최종 값 결정
	--   → “문제 풀고 바로 나가서 extraTrash sync 못 한 경우” 보정
	local finalExtraTrash = savedExtraTrash
	if derivedExtraTrash > finalExtraTrash then
		finalExtraTrash = derivedExtraTrash
	end

	STATE.ExtraTrash.Value = finalExtraTrash
	print(("[Stage2][QuizClient] ExtraTrash restored: saved=%d, derived=%d, final=%d")
		:format(savedExtraTrash, derivedExtraTrash, finalExtraTrash))

	-- ★ 저장된 점수 / 시간 복구
	if typeof(res.quizScore) == "number" then
		totalScore = res.quizScore
		print("[Stage2][QuizClient] restored score =", totalScore)
	end

	if typeof(res.quizTimeSec) == "number" then
		savedElapsedBeforeReconnect = math.max(0, res.quizTimeSec)
		print("[Stage2][QuizClient] restored elapsed time =", savedElapsedBeforeReconnect)
	end

	-- 퀘스트/가이드/UI 복구
	applyQuestPhaseFromState()

	task.delay(0.5, function()
		print("[Stage2][QuizClient] re-apply quest phase after delay")
		applyQuestPhaseFromState()
	end)

	-------------------------------------------------------
	-- ★ cleanedObjects → 오브젝트 로컬 삭제 (여러 번 재시도)
	-------------------------------------------------------
	if typeof(cleanedMap) == "table" then
		for objectId, flag in pairs(cleanedMap) do
			if flag then
				task.spawn(function()
					local deadline = os.clock() + 5  -- 최대 5초 동안 재시도
					local removed = false

					while os.clock() < deadline and not removed do
						local inst = findBySessionObjectId(objectId)
						if inst then
							print("[Stage2][QuizClient] auto-clean local object:", objectId, inst:GetFullName())
							localDisappearByInstance(inst)
							removed = true
							break
						end
						task.wait(0.3) -- 0.3초마다 다시 찾음
					end

					if not removed then
						warn("[Stage2][QuizClient] cleaned object not found for id:", objectId)
					end
				end)
			end
		end
	end

	-- 사다리 컷씬 이미 본 상태면 재입장 시 바로 상태 복구
	if CutsceneFlags["ladder_cut"] then
		print("[Stage2][QuizClient] ladder_cut already done in this session → skip ladder cutscene")
		STATE.ZoomPlayed.Value = true
		cutsceneSent = true

		-- 재입장 시에도 NPC를 바로 스폰 위치로 옮기기
		pcall(moveQuestNPCToSpawn)

		-- 사다리도 바로 만들어 두기
		task.defer(function()
			if LadderCinematic and LADDER_TEMPLATE then
				local ladder = LadderCinematic.spawnAndAnimate({
					template   = LADDER_TEMPLATE,
					position   = LADDER_POS,
					parent     = workspace,
					dropHeight = 0,
					dropTime   = 0,
					bouncePower= 0,
					keepChildrenTransparent = true,
					soundId    = nil,
				})

				if ladder then
					-- 사다리 하위 모든 파트/디칼/텍스처 투명하게
					makeChildrenPartsTransparent(ladder, 1)
				end
			end
		end)
	end

	isLoadingProgress = false
end


local function initStageFlow()
	STATE.QuestPhase.Value   = 0
	STATE.Solved.Value       = 0
	STATE.Asked.Value        = 0
	STATE.HudShown.Value     = false
	STATE.PortalSpawned.Value= false
	STATE.DoorCutDone.Value  = false
	STATE.ExtraTrash.Value   = 0

	quizStartedAt = nil
	totalScore = 0
	savedElapsedBeforeReconnect = 0

	disableAllQuizPrompts()
	enableNPCPrompts()

	if QuestGuideBus then
		QuestGuideBus:Fire("targetNPC")
	end

	-- ★ 세션 준비 후 서버 진행도 불러오기
	waitForSessionId(5)
	loadStage2Progress()
end

STATE.QuestPhase.Changed:Connect(syncQuestToServer)
STATE.ExtraTrash.Changed:Connect(syncQuestToServer)

initStageFlow()

print("업데이트 버전 4444")
print("[QuizClient] READY (퀘스트0~3, 쓰레기10개 정화, 4문제 사다리 연출, NPC/포탈 가이드 연동 + SFX + Score/Time)")
