-- StarterPlayerScripts/QuizClient.lua
--!strict
-- [Stage1 전용]
-- QuizGui(정적) + QuizHUD + 퀘스트/화살표/문 컷씬/포탈 컷씬 연동
--
-- QuestPhase 요약:
--   0: 입장 직후 / 첫 NPC 대화 전 (퀘스트1: 'NPC에게 말걸기')
--   1: 튜토리얼 쓰레기 1개 정화 단계 (퀘스트2 진행 중)
--   2: 튜토리얼 쓰레기 정화 후, NPC에게 복귀 (퀘스트2 완료 직전 / 대사 후 완료)
--   3: 나머지 9개 정화 단계 (퀘스트3 진행 중)
--   4: 최종 대사/포탈 오픈 이후(완료 상태)

local Players                 = game:GetService("Players")
local RS                      = game:GetService("ReplicatedStorage")
local TweenService            = game:GetService("TweenService")
local ProximityPromptService  = game:GetService("ProximityPromptService")
local Workspace               = game:GetService("Workspace")
local CollectionService       = game:GetService("CollectionService")
local SoundService            = game:GetService("SoundService")

local LP = Players.LocalPlayer

-- 이미 푼 퀴즈/컷씬 정보 캐시 (서버에서 받아온 걸 들고 있는 용도)
local SolvedQuiz: {[string]: boolean} = {}
local CutsceneFlags: {[string]: boolean} = {}

-- ========= 유틸/모듈 =========
local function tryRequire(inst: Instance?): any
	if not inst or not inst:IsA("ModuleScript") then return nil end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end

-- ★ Stage1 로컬 삭제용: 기존 InteractionActionRouter 모듈 사용
local LocalObjectHider =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("InteractionActionRouter"))
	or tryRequire(RS:FindFirstChild("InteractionActionRouter"))

local CutscenePlayer =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("Cutscene") and RS.Modules.Cutscene:FindFirstChild("CutscenePlayer"))
	or tryRequire(RS:FindFirstChild("CutscenePlayer"))

local PortalMover =
	tryRequire(RS:FindFirstChild("PortalMover"))
	or tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PortalMover"))

local PortalSpawnCutscene =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PortalSpawnCutscene"))
	or tryRequire(RS:FindFirstChild("PortalSpawnCutscene"))

local CutsceneManager = require(RS:WaitForChild("Modules"):WaitForChild("CutsceneManager"))

local playerLock = require(RS:WaitForChild("Modules"):WaitForChild("PlayerLock"))

-- ========= SFX 정의/헬퍼 =========
local SFX: {[string]: string} = {
	TrashClean   = "rbxassetid://4636006374",       -- 오브젝트 정화 될 때
	Wrong        = "rbxassetid://5521959695",       -- 오답 시
	ChoiceClick  = "rbxassetid://9055474333",       -- 문제 클릭(보기 선택) 할 때
	Correct      = "rbxassetid://114326413874741",  -- 정답 시
	Submit       = "rbxassetid://15675059323",      -- 제출하기 버튼 눌렀을 때
	QuizOpen     = "rbxassetid://89842591486388",   -- 퀴즈 나올 때

	DoorOpen1    = "rbxassetid://103840356233584",  -- 4문제 풀고 문 열릴 때 사운드 1
	DoorOpen2    = "rbxassetid://6636232274",       -- 4문제 풀고 문 열릴 때 사운드 2

	PortalOpen   = "rbxassetid://2017454590",       -- 포탈 열릴 때
}

local function playSfx(name: string, volume: number?)
	local soundId = SFX[name]
	if not soundId then return end

	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume or 1
	s.RollOffMode = Enum.RollOffMode.Inverse
	s.Parent = SoundService

	s.Ended:Connect(function()
		if s then
			s:Destroy()
		end
	end)

	s:Play()
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

-- 서버에서 만들어주는 것(진행도 조회)
local RF_Stage1_GetProgress = Remotes:WaitForChild("RF_Stage1_GetProgress") :: RemoteFunction

-- 퀴즈 문제/정답 체크
local RF_Get = Remotes:FindFirstChild("RF_Quiz_GetQuestion")
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

-- 스테이지 결과 보고 (서버에서 생성)
local RE_StageQuizResult = Remotes:WaitForChild("RE_StageQuizResult") :: RemoteEvent

-- ★ Stage1 진행도 동기화용 Remotes
local RE_Stage1_ObjectCleaned = Remotes:WaitForChild("RE_Stage1_ObjectCleaned") :: RemoteEvent
local RE_Stage1_CutsceneFlag  = Remotes:WaitForChild("RE_Stage1_CutsceneFlag") :: RemoteEvent
local RE_Stage1_QuestSync     = Remotes:WaitForChild("RE_Stage1_QuestSync") :: RemoteEvent
local RE_Stage1_QuizSolved    = Remotes:WaitForChild("RE_Stage1_QuizSolved") :: RemoteEvent -- ★ 추가

-- ★ 새로 추가: 점수/시간 실시간 저장용
local RE_Stage1_QuizRuntime   = Remotes:WaitForChild("RE_Stage1_QuizRuntime") :: RemoteEvent

-- ★★★ 재입장/동기화용: 서버가 정화된 오브젝트 ID를 보내주면 로컬에서도 다시 삭제
if RE_Stage1_ObjectCleaned then
	RE_Stage1_ObjectCleaned.OnClientEvent:Connect(function(payload: any)
		-- 서버 구현에 따라 string 하나 또는 string 배열(table)로 올 수 있게 처리
		if typeof(payload) == "string" then
			localDisappearByObjectId(payload)
		elseif typeof(payload) == "table" then
			for _, oid in ipairs(payload) do
				if typeof(oid) == "string" then
					localDisappearByObjectId(oid)
				end
			end
		end
	end)
end

-- ========= 상수/태그 =========
local UI_NAME             = "QuizGui"
local TOTAL_QUESTIONS     = 10
local CUTSCENE_THRESHOLD  = 4

-- ★ 시도 횟수별 점수
local function getScoreForAttempt(attempt: number): number
	if attempt <= 1 then
		return 10
	elseif attempt == 2 then
		return 8
	elseif attempt == 3 then
		return 6
	else
		return 4
	end
end

local DIALOGUE_START_TAG  = "DialoguePrompt"
local QUIZ_TARGET_TAG     = "QuizPrompt"
local LOCAL_PROMPT_NAME   = "_ClientOnlyPrompt"

local QUEST_NPC_TAG       = "QuestNPC"
local FIRST_TRASH_TAG     = "QuestObject"
local PORTAL_TEMPLATE_NAME= "Potal"

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
		QuestPhase    = I("QuestPhase"),   -- 0~4
		ExtraTrash    = I("ExtraTrash"),   -- Phase3에서 정화한 9개 쓰레기 카운트
		Score         = I("Score"),        -- 퀴즈 점수 (시도별 가중치, UI에는 표시 X)
		QuizTimeSec   = I("QuizTimeSec"),  -- 2번 문제~10번 문제까지 걸린 시간(초)
		HudShown      = B("HudShown", false),
		PortalSpawned = B("PortalSpawned", false),
		DoorCutDone   = B("DoorCutDone", false),
	}
end

local STATE = getState()

local busy = false
local currentPrompt: ProximityPrompt? = nil
local currentIsFirstTrash = false
local spawnedPortal: Instance? = nil
local quizTimerStart: number? = nil

local isLoadingProgress = false

local CLEANED_IDS: {[string]: boolean} = {}

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

	-- 프롬프트에서 위로 올라가면서 SessionObjectId 를 찾는다
	local cur: Instance? = prompt
	while cur and cur ~= Workspace do
		-- Attribute 우선
		local idAttr = cur:GetAttribute("SessionObjectId")
		if typeof(idAttr) == "string" and idAttr ~= "" then
			return idAttr
		end

		-- StringValue 도 지원
		local idVal = cur:FindFirstChild("SessionObjectId")
		if idVal and idVal:IsA("StringValue") and idVal.Value ~= "" then
			return idVal.Value
		end

		cur = cur.Parent
	end

	warn("[QuizClient] SessionObjectId not found on ancestors of prompt:", prompt:GetFullName())
	return nil
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
	local root  = gui:WaitForChild("Frame") :: Frame
	local bg    = root:WaitForChild("BackGround") :: Frame
	local frame = bg:WaitForChild("Frame")
	local A = frame:WaitForChild("AButton") :: ImageButton
	local B = frame:WaitForChild("BButton") :: ImageButton
	local C = frame:WaitForChild("CButton") :: ImageButton
	local D = frame:WaitForChild("DButton") :: ImageButton
	local Answer = bg:WaitForChild("AnswerButton") :: ImageButton

	local qText  = bg:WaitForChild("QuestionText")  :: TextLabel
	local qScore = bg:WaitForChild("QuestionScore") :: TextLabel

	qScore.Visible = true

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

-- ========= 문 오픈 컷씬 + NPC 이동 =========
local function playDoorCutscene(stage:number)
	playSfx("DoorOpen1")
	playSfx("DoorOpen2")

	pcall(function()
		if PortalMover then
			PortalMover.Open(stage, 6, 0.6)
		end
	end)

	local cutDur = 3
	pcall(function()
		if CutscenePlayer then
			CutscenePlayer.PlayPortalOpen(stage, {
				duration  = cutDur,
				allowSkip = true,
			})
		end
	end)

	task.delay(0, function()
		pcall(function()
			if PortalMover and PortalMover.FadeOut then
				PortalMover.FadeOut(stage, 0)
			end
		end)
	end)
end

local function moveQuestNPCToSpawn()
	local spawn = Workspace:FindFirstChild("NpcSpawnPart")
	if not (spawn and spawn:IsA("BasePart")) then
		warn("[QuizClient] NpcSpawnPart 를 찾지 못했습니다.")
		return
	end
	for _, inst in ipairs(CollectionService:GetTagged(QUEST_NPC_TAG)) do
		if inst:IsA("Model") then
			pcall(function() (inst :: Model):PivotTo((spawn :: BasePart).CFrame) end)
		elseif inst:IsA("BasePart") then
			pcall(function() (inst :: BasePart).CFrame = (spawn :: BasePart).CFrame end)
		end
	end
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
local function syncQuestToServer()
	if isLoadingProgress then return end
	if not RE_Stage1_QuestSync then return end

	local phase = STATE.QuestPhase.Value
	local extra = STATE.ExtraTrash.Value

	local ok, err = pcall(function()
		RE_Stage1_QuestSync:FireServer(phase, extra)
	end)
	if not ok then
		warn("[QuizClient] syncQuestToServer failed:", err)
	end
end

-- 퀘스트 단계에 따라 프롬프트/가이드 복구 + QuestGui 동기화
local function applyQuestPhaseFromState()
	local phase = STATE.QuestPhase.Value
	local extra = STATE.ExtraTrash.Value

	if phase <= 0 then
		disableAllQuizPrompts()
		enableNPCPrompts()
		if QuestGuideBus then
			QuestGuideBus:Fire("targetNPC")
		end

	elseif phase == 1 then
		enableOnlyFirstTrashPrompt()
		disableNPCPrompts()
		if QuestGuideBus then
			QuestGuideBus:Fire("targetFirstTrash")
		end

	elseif phase == 2 then
		disableAllQuizPrompts()
		enableNPCPrompts()
		if QuestGuideBus then
			QuestGuideBus:Fire("targetNPC")
		end

	elseif phase == 3 then
		-- 🔵 기존 phase 3 로직 유지
		enableAllQuizPrompts()
		enableNPCPrompts()

		if QuestGuideBus then
			if extra >= 9 then
				QuestGuideBus:Fire("targetNPC")
			else
				QuestGuideBus:Fire("targetMoreTrash")
			end
		end

	elseif phase >= 4 then
		-- ✅ 퀘스트 완전히 끝난 상태
		-- 더 이상 쓰레기/NPc 가이드는 필요 없음
		disableAllQuizPrompts()
		--disableNPCPrompts()

		if QuestGuideBus then
			if spawnedPortal then
				QuestGuideBus:Fire("targetPortal", spawnedPortal)
			else
				QuestGuideBus:Fire("targetPortal")
			end
		end
		
	end

	if QuestProgressBus then
		local questIndex = 1

		if phase <= 0 then
			questIndex = 1
		elseif phase == 1 then
			questIndex = 2
		elseif phase == 2 then
			questIndex = 3
		elseif phase == 3 then
			questIndex = 3
		elseif phase >= 4 then
			questIndex = 4
		end

		QuestProgressBus:Fire(questIndex)

		if phase >= 3 then
			QuestProgressBus:Fire({
				type  = "trashProgress",
				count = extra,
				total = 9,
			})
		end
	end
end

-- ========= LocalObjectHider 헬퍼 =========

-- SessionObjectId 로 Workspace 에서 오브젝트 찾기
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

-- InteractionActionRouter.run 을 이용해서
-- Disappear / Box / seaShell 태그 기준으로 이펙트+페이드+Destroy 실행
local function localDisappearByInstance(inst: Instance)
	if not LocalObjectHider or typeof(LocalObjectHider.run) ~= "function" then return end

	local ok, err = pcall(function()
		LocalObjectHider.run(inst, {
			fadeDuration = 0.35,
			delayDestroy = 0.0,
		}, {
			targetTags = { "Disappear", "VanishOnCorrect", "Box", "seaShell" },
		})
	end)
	if not ok then
		warn("[QuizClient] localDisappearByInstance error:", err)
	end
end

local function localDisappearByPrompt(prompt: ProximityPrompt)
	if not prompt then return end
	localDisappearByInstance(prompt)
end

local function localDisappearByObjectId(objectId: string)
	if objectId == "" then return end

	-- ★ 항상 셋에 기록해 둔다 (나중에 재적용 가능)
	CLEANED_IDS[objectId] = true

	-- 실제 인스턴스 찾기
	local inst = findBySessionObjectId(objectId)
	if not inst then
		warn("[QuizClient] localDisappearByObjectId: instance NOT FOUND for id =", objectId)
		return
	end

	print("[QuizClient] localDisappearByObjectId: found", objectId, "→", inst:GetFullName())
	localDisappearByInstance(inst)
end

-- ★ CLEANED_IDS 기준으로 한 번 더 전체 적용
local function reapplyCleanedObjects()
	for objectId, _ in pairs(CLEANED_IDS) do
		local inst = findBySessionObjectId(objectId)
		if inst then
			print("[QuizClient] reapply cleaned:", objectId, "→", inst:GetFullName())
			localDisappearByInstance(inst)
		else
			warn("[QuizClient] reapply cleaned: still NOT FOUND for id =", objectId)
		end
	end
end

-- ★ 서버에서 받은 CleanedFlags 기준으로, 이미 정화된 오브젝트를 모두 로컬에서 제거
local function applyCleanedObjectsToWorld()
	-- 현재 씬에 있는 모든 QuizPrompt 순회
	forEachQuizPrompt(function(pp)
		-- 이 프롬프트가 어떤 SessionObjectId 를 가지는지 찾아보고
		local id = getCleanedObjectIdFromPrompt(pp)
		if id and CleanedFlags[id] then
			print("[QuizClient] auto-disappear cleaned prompt:", pp:GetFullName(), "id=", id)
			-- 이 플레이어에게만 서서히 투명+삭제
			localDisappearByPrompt(pp)
		end
	end)
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
	-- 이미 다 풀었으면 퀴즈 더 안 열기
	if STATE.Solved.Value >= TOTAL_QUESTIONS then
		print("[QuizClient] all questions already solved, ignore quiz prompt")
		busy = false
		return
	end

	local gui = ensureUI()
	local UI  = getUIRefs(gui)
	local btns, lbls = UI.btns, UI.btnLabels

	------------------------------------------------------
	-- ★ 지금까지 푼 문제 id들(SolvedQuiz)을 리스트로 만들어서 서버에 넘김
	------------------------------------------------------
	local solvedList = {}
	for qidStr, flag in pairs(SolvedQuiz) do
		if flag then
			table.insert(solvedList, qidStr)
		end
	end

        local q: QDto? = nil
        local choiceIdByIndex: {[number]: number} = {}
        local ok, res = pcall(function()
                -- solvedList 를 인자로 넘김
                return (RF_Get :: RemoteFunction):InvokeServer(solvedList)
        end)
        if ok then
                -- 서버가 { ok=true, data=dto } 형태로 줄 수 있으므로 풀어서 사용
                if typeof(res) == "table" and res.ok == true and typeof(res.data) == "table" then
                        q = res.data
                else
                        q = res
                end
        end

        if q and typeof(q) == "table" then
                -- 서버 응답 필드 보정: quizId → id, choices → c 배열
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

	if not q or not q.id then
		print("[QuizClient] no more unsolved questions from server")
		gui.Enabled = false
		busy = false
		return
	end

	local currentQid = q.id
	local currentQidStr = tostring(currentQid)

	-- 혹시 서버가 실수로 이미 푼 문제를 주면 방어
	if SolvedQuiz[currentQidStr] then
		print("[QuizClient] server returned solved qid, skip:", currentQidStr)
		gui.Enabled = false
		busy = false
		return
	end

	playSfx("QuizOpen")

	if not STATE.HudShown.Value then
		Hud.Show(TOTAL_QUESTIONS)
		STATE.HudShown.Value = true
	end
	local idx = math.clamp(STATE.Solved.Value + 1, 1, TOTAL_QUESTIONS)
	Hud.Progress(STATE.Solved.Value, TOTAL_QUESTIONS)
	UI.lblScore.Text = string.format("QUESTION %d / %d", idx, TOTAL_QUESTIONS)

	if idx == 2 and not quizTimerStart then
		quizTimerStart = os.clock()
		print("[QuizClient] Quiz timer started at question 2")
	end

	UI.root.Visible = true
	UI.lblQ.Text = q.q or ""
	for i=1,4 do
		lbls[i].Text = (q.c and q.c[i]) or ""
		btns[i].Active = true
		prepareButtonHitArea(btns[i])
		setButtonVisual(btns[i], "idle")
	end
	hideAllStrokes(btns)

	UI.btnAnswer.AutoButtonColor = false
	UI.btnAnswer.Active, UI.btnAnswer.Visible = true, true
	UI.btnAnswer.Image = SUBMIT_IDLE_IMAGE
	UI.btnAnswer.ImageColor3 = Color3.fromRGB(255,255,255)

	gui.Enabled = true
	local inputLocked = false
	local selected: number? = nil
	local attemptCount = 0
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

		playSfx("ChoiceClick")

		for j=1,4 do
			setButtonVisual(btns[j], (j==i) and "selected" or "idle")
		end
		UI.btnAnswer.Image = SUBMIT_SELECTED_IMAGE
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
		if inputLocked then return end

		playSfx("Submit")

		if not selected then
			local orig = UI.btnAnswer.Size
			TweenService:Create(UI.btnAnswer, TweenInfo.new(0.08), {Size = orig + UDim2.fromOffset(6,6)}):Play()
			task.delay(0.1, function()
				TweenService:Create(UI.btnAnswer, TweenInfo.new(0.08), {Size = orig}):Play()
			end)
			return
		end

		inputLocked = true
		attemptCount += 1

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
			playSfx("Correct")
			playerLock.Unlock()
			setButtonState(btns[selected :: number], true)

			task.delay(0.22, function()
				-- 시도 횟수에 따른 점수 가산 (UI에는 표시 X)
				local addScore = getScoreForAttempt(attemptCount)
				STATE.Score.Value += addScore

				SolvedQuiz[currentQid] = true

				print(string.format(
					"[QuizClient] Correct! attempt=%d, +%d점, total=%d점",
					attemptCount, addScore, STATE.Score.Value
					))

				-- ★ 여기서까지 score 는 갱신 완료

				-- ★ 타이머가 켜져 있으면 현재까지 경과 시간 갱신
				if quizTimerStart then
					local elapsed = os.clock() - quizTimerStart
					local sec = math.max(0, math.floor(elapsed + 0.5))
					STATE.QuizTimeSec.Value = sec
				end

				-- ★ 서버에 현재 score/time 실시간 전송 (중간에 나가도 여기까지는 저장됨)
				if RE_Stage1_QuizRuntime then
					local curScore = STATE.Score.Value
					local curTime  = STATE.QuizTimeSec.Value
					RE_Stage1_QuizRuntime:FireServer(curScore, curTime)
				end

				STATE.Solved.Value += 1
				local solved = STATE.Solved.Value

				-- ★ qid를 문자열로 통일해서 로컬/서버 둘 다 저장
				local qidStr = tostring(currentQid)
				SolvedQuiz[qidStr] = true

				-- 서버에 '이 qid 풀었다' 보고 (문자열로)
				if RE_Stage1_QuizSolved then
					RE_Stage1_QuizSolved:FireServer(qidStr)
				end

				Hud.Progress(solved, TOTAL_QUESTIONS)
				Hud.Correct(solved, TOTAL_QUESTIONS)

				-- 10번째 문제 끝났으면 타이머 종료 + 시간 저장 + 서버(최종 결과) 보고
				if solved == TOTAL_QUESTIONS then
					if quizTimerStart then
						local elapsed = os.clock() - quizTimerStart
						local sec = math.max(0, math.floor(elapsed + 0.5))
						STATE.QuizTimeSec.Value = sec
						print(string.format("[QuizClient] Quiz finished in %d seconds", sec))
					end

					if RE_StageQuizResult and RE_StageQuizResult:IsA("RemoteEvent") then
						local finalScore = STATE.Score.Value
						local finalTime  = STATE.QuizTimeSec.Value
						print(string.format("[QuizClient] Send result to server: score=%d, time=%ds", finalScore, finalTime))
						RE_StageQuizResult:FireServer(finalScore, finalTime)
					end
				end

				Hud.Correct(solved, TOTAL_QUESTIONS)

				--------------------------------------------------
				-- ★ 1) 먼저 SessionObjectId 추출
				--------------------------------------------------
				local cleanedObjectId: string? = nil
				do
					local anchorInst: Instance? = currentPrompt
					if anchorInst then
						cleanedObjectId = getCleanedObjectIdFromPrompt(anchorInst)
						if cleanedObjectId then
							print("[QuizClient] cleaned objectId =", cleanedObjectId)
						end
					end
				end

				--------------------------------------------------
				-- ★ 2) 이 플레이어에게만 오브젝트 로컬 삭제
				--------------------------------------------------
				do
					if cleanedObjectId then
						-- SessionObjectId 를 알고 있으면 그걸로 찾기
						localDisappearByObjectId(cleanedObjectId)
					elseif currentPrompt then
						-- 혹시 id를 못 찾았을 때는 프롬프트 기준으로라도 제거
						localDisappearByPrompt(currentPrompt)
					end
				end

				--------------------------------------------------
				-- ★ 3) 서버에 정화된 오브젝트 ID 보고
				--------------------------------------------------
				if cleanedObjectId and RE_Stage1_ObjectCleaned then
					RE_Stage1_ObjectCleaned:FireServer(cleanedObjectId)
				else
					warn("[QuizClient] cleanedObjectId nil → 서버에 보고하지 못함")
				end

				if currentIsFirstTrash and STATE.QuestPhase.Value < 2 then
					playSfx("TrashClean")

					STATE.QuestPhase.Value = 2
					disableAllQuizPrompts()
					enableNPCPrompts()

					if QuestGuideBus then
						QuestGuideBus:Fire("targetNPC")
					end

					if currentPrompt then currentPrompt.Enabled = false end
					currentPrompt = nil
					currentIsFirstTrash = false
					gui.Enabled = false
					busy = false
					cleanupAll()
					return
				end

				if not currentIsFirstTrash and STATE.QuestPhase.Value >= 3 then
					STATE.ExtraTrash.Value += 1

					playSfx("TrashClean")

					local cleared = math.clamp(STATE.ExtraTrash.Value, 0, 9)

					if QuestProgressBus then
						QuestProgressBus:Fire({
							type  = "trashProgress",
							count = cleared,
							total = 9,
						})
					end

					if cleared >= 9 and QuestGuideBus then
						QuestGuideBus:Fire("targetNPC")
					end
				end

				if not STATE.DoorCutDone.Value and solved >= CUTSCENE_THRESHOLD then
					STATE.DoorCutDone.Value = true
					gui.Enabled = false
					cleanupAll()

					if CutsceneFlags["portal_open"] then
						print("[QuizClient] Door cutscene already done in this session → skip animation")

						pcall(function()
							if PortalMover then
								PortalMover.Open(1, 6, 0.1)
								PortalMover.FadeOut(1, 0)
							end
							moveQuestNPCToSpawn()
						end)
					else
						if RE_Stage1_CutsceneFlag then
							RE_Stage1_CutsceneFlag:FireServer("portal_open")
						end

						local delaySec = 1.2
						task.delay(delaySec, function()
							pcall(function()
								playDoorCutscene(1)
								moveQuestNPCToSpawn()
							end)
						end)
					end
				end

				if STATE.QuestPhase.Value >= 3 and solved >= TOTAL_QUESTIONS then
					if QuestProgressBus then
						print("[QuizClient] All questions solved → Quest3 complete (strike-through)")
						QuestProgressBus:Fire("complete")
					end
				end

				if currentPrompt then currentPrompt.Enabled = false end
				currentPrompt = nil
				currentIsFirstTrash = false
				gui.Enabled = false
				busy = false
				cleanupAll()
			end)
		else
			playSfx("Wrong")

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

	if isQuizPrompt(prompt) then
		busy = true
		currentPrompt = prompt
		currentIsFirstTrash = isUnderFirstTrash(prompt)
		openOneQuestion()
		return
	end

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

		local questPhaseForDialogue = 1

		if phase <= 0 then
			questPhaseForDialogue = 1
		elseif phase == 2 then
			questPhaseForDialogue = 2
		elseif phase >= 3 then
			if solved >= TOTAL_QUESTIONS and extra >= 9 then
				questPhaseForDialogue = 4
			else
				questPhaseForDialogue = 3
			end
		end

		local finalDialogue = (questPhaseForDialogue == 4)

		if finalDialogue then
			if prompt then
				prompt.Enabled = false
				prompt.MaxActivationDistance = 0
			end
			disableNPCPrompts()
			if QuestGuideBus then
				QuestGuideBus:Fire("hide")
			end
		else
			disableNPCPrompts()
		end

		DialogueBus:Fire("Play", {
			npc        = prompt.Parent,
			questPhase = questPhaseForDialogue,
			solved     = solved,
			total      = TOTAL_QUESTIONS,
		})

		local finishedConn: RBXScriptConnection? = nil
		finishedConn = DialogueBus.Event:Connect(function(cmd:any)
			if cmd ~= "Finished" then return end
			if finishedConn then
				finishedConn:Disconnect()
				finishedConn = nil
			end

			local curPhase  = STATE.QuestPhase.Value
			local curSolved = STATE.Solved.Value
			local curExtra  = STATE.ExtraTrash.Value

			if curPhase == 0 then
				STATE.QuestPhase.Value = 1

				if QuestProgressBus then
					QuestProgressBus:Fire("complete")
				end

				enableOnlyFirstTrashPrompt()
				disableNPCPrompts()

				if QuestGuideBus then
					QuestGuideBus:Fire("targetFirstTrash")
				end

			elseif curPhase == 2 then
				if QuestProgressBus then
					QuestProgressBus:Fire("complete")
				end

				STATE.QuestPhase.Value = 3
				enableAllQuizPrompts()
				enableNPCPrompts()

				if QuestProgressBus then
					QuestProgressBus:Fire({
						type  = "trashProgress",
						count = STATE.ExtraTrash.Value,
						total = 9,
					})
				end

				if QuestGuideBus then
					QuestGuideBus:Fire("targetMoreTrash")
				end

			else
				if questPhaseForDialogue == 3 then
					enableNPCPrompts()
					if QuestGuideBus then
						QuestGuideBus:Fire("targetMoreTrash")
					end
				end

				if finalDialogue and not STATE.PortalSpawned.Value then
					STATE.PortalSpawned.Value = true
					STATE.QuestPhase.Value = 4

					task.delay(0.2, function()
						if QuestProgressBus then
							QuestProgressBus:Fire("complete")
						end
					end)

					if QuestGuideBus then
						task.delay(1.0, function()
							if spawnedPortal then
								QuestGuideBus:Fire("targetPortal", spawnedPortal)
							else
								QuestGuideBus:Fire("targetPortal")
							end
						end)
					end
				end
			end

			busy = false
			currentPrompt = nil
		end)

		return
	end
end)

-- ========= 초기 세팅 =========
local function normalizeSolvedQuiz(raw)
	local map = {}
	if typeof(raw) ~= "table" then return map end

	for k, v in pairs(raw) do
		-- 서버는 k="qid", v=true 형태(map)
		if typeof(k) == "string" and v == true then
			map[k] = true
		end
	end

	return map
end


local function loadStageProgress()
	isLoadingProgress = true

	local ok, res = pcall(function()
		return RF_Stage1_GetProgress:InvokeServer()
	end)
	if not ok or typeof(res) ~= "table" then
		warn("[QuizClient] RF_Stage1_GetProgress failed:", res)
		isLoadingProgress = false
		return
	end

	SolvedQuiz = normalizeSolvedQuiz(res.quizSolved)
	CutsceneFlags = res.cutscenes or {}

	print("[QuizClient] Stage1 progress loaded. solved qids:", SolvedQuiz, "cutscenes:", CutsceneFlags)

	-- ===== 이미 푼 퀴즈 개수 → HUD 복구 =====
	local solvedCount = 0
	for _, v in pairs(SolvedQuiz) do
		if v then
			solvedCount += 1
		end
	end

	if solvedCount > 0 then
		solvedCount = math.clamp(solvedCount, 0, TOTAL_QUESTIONS)
		STATE.Solved.Value = solvedCount

		STATE.HudShown.Value = true
		Hud.Show(TOTAL_QUESTIONS)
		Hud.Progress(STATE.Solved.Value, TOTAL_QUESTIONS)
	end

	-- ===== 서버에서 받은 QuestPhase / ExtraTrash =====
	local stageQuestPhase = tonumber(res.questPhase)
	if stageQuestPhase then
		-- 혹시 이상한 값 들어온 경우 방어
		if stageQuestPhase < 0 then
			stageQuestPhase = 0
		elseif stageQuestPhase >= 4 then
			stageQuestPhase = 4    -- 재입장 시에는 최대 4까지만 사용
		end
		STATE.QuestPhase.Value = stageQuestPhase
	end

	-- ★ cleanedObjects 기준으로 "실제 정화 개수" 계산 + 셋에 기록
	local cleanedMap = res.cleanedObjects
	local cleanedCount = 0
	if typeof(cleanedMap) == "table" then
		for objectId, flag in pairs(cleanedMap) do
			if typeof(objectId) == "string" and flag == true then
				CLEANED_IDS[objectId] = true
				cleanedCount += 1
			end
		end
	end

	-- 서버에 저장된 extraTrash (없으면 0)
	local savedExtraTrash = tonumber(res.extraTrash) or 0

	-- ★ fallback: cleanedObjects 개수를 기반으로 한 extraTrash 추정 값
	--   (튜토리얼 쓰레기가 cleanedObjects 에 같이 들어가 있다면
	--    필요하면 -1 해서 보정할 수 있음. 일단은 그대로 사용.)
	local derivedExtraTrash = math.clamp(cleanedCount-1, 0, 9)

	-- ★ 두 값 비교해서 더 큰 쪽을 사용 (나가기 직전에 저장이 안 된 상황을 보완)
	local finalExtraTrash = savedExtraTrash
	if derivedExtraTrash > finalExtraTrash then
		finalExtraTrash = derivedExtraTrash
	end

	STATE.ExtraTrash.Value = finalExtraTrash

	-- ===== 점수/시간 복원 =====
	local savedScore = tonumber(res.quizScore)
	if savedScore then
		STATE.Score.Value = savedScore
	end

	local savedTime = tonumber(res.quizTimeSec)
	if savedTime then
		STATE.QuizTimeSec.Value = savedTime
	end

	-- ===== 퀘스트/가이드/UI 복구 =====
	applyQuestPhaseFromState()

	task.delay(0.5, function()
		print("[QuizClient] re-apply quest phase after delay")
		applyQuestPhaseFromState()
	end)

	----------------------------------------------------------------
	-- ★ 이미 정화된 오브젝트들 → 두 번에 걸쳐 재적용
	----------------------------------------------------------------
	-- 위에서 cleanedMap 을 돌면서 CLEANED_IDS 는 이미 채워둔 상태
	-- 지금 한 번 적용
	reapplyCleanedObjects()

	-- 오브젝트가 나중에 생기는 경우를 대비해서 1초 뒤에 한 번 더
	task.delay(1.0, function()
		reapplyCleanedObjects()
	end)

	-- 문 컷씬 이미 봤으면 바로 열린 상태로 맞추기
	if CutsceneFlags["portal_open"] then
		print("[QuizClient] portal_open already done in this session → apply door open state")

		STATE.DoorCutDone.Value = true

		pcall(function()
			if PortalMover then
				PortalMover.Open(1, 6, 0.1)
				PortalMover.FadeOut(1, 0)
			end
			moveQuestNPCToSpawn()
		end)
	end

	isLoadingProgress = false
end


local function waitForSessionId(timeoutSec: number?)
	local deadline = os.clock() + (timeoutSec or 5)
	while os.clock() < deadline do
		local sid = LP:GetAttribute("sessionId")
		if typeof(sid) == "string" and sid ~= "" then
			print("[QuizClient] sessionId ready:", sid)
			return
		end
		task.wait(0.1)
	end
	warn("[QuizClient] sessionId not set in time → 진행도 없이 시작")
end

local function initStage1Flow()
	STATE.QuestPhase.Value    = 0
	STATE.Solved.Value        = 0
	STATE.Asked.Value         = 0
	STATE.Score.Value         = 0
	STATE.QuizTimeSec.Value   = 0
	STATE.HudShown.Value      = false
	STATE.PortalSpawned.Value = false
	STATE.DoorCutDone.Value   = false
	STATE.ExtraTrash.Value    = 0

	quizTimerStart = nil

	disableAllQuizPrompts()
	enableNPCPrompts()

	waitForSessionId(5)
	loadStageProgress()
end

STATE.QuestPhase.Changed:Connect(syncQuestToServer)
STATE.ExtraTrash.Changed:Connect(syncQuestToServer)

initStage1Flow()

print("[QuizClient][Stage1] READY (퀴즈/퀘스트/HUD/점수/시간/문 컷씬/포탈 컷씬, 세션 진행도 + 로컬 오브젝트 삭제 복구 포함)")
