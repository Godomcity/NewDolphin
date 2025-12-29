-- StarterPlayerScripts/QuizClient.client.lua
--!strict
-- [이 플레이스 전용 버전]
-- ❗ 여기서는 "퀴즈 문제"를 절대 띄우지 않고,
--    QuizPrompt 프롬프트를 누르면 서버로 컷씬 요청만 보내는 용도.
--
-- - 문제 UI(4지선다), HUD, 정답/오답 처리 전부 없음
-- - 포탈 스폰도 여기서는 안 함(필요하면 서버에서 처리)

local Players                = game:GetService("Players")
local RS                     = game:GetService("ReplicatedStorage")
local TweenService           = game:GetService("TweenService")
local CollectionService      = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace              = game:GetService("Workspace")

local LP = Players.LocalPlayer

-- ========= Remotes =========
local Net            = require(RS:WaitForChild("Modules"):WaitForChild("Net"))
local RE_CutsceneReq = Net.ensureRE("Quiz_CutsceneRequest")

-- (옵션) 컷씬 모듈을 직접 쓰진 않지만, 혹시 필요하면 사용 가능
local CutscenePlayer do
	local ok, mod = pcall(function()
		return require(RS:WaitForChild("Modules"):WaitForChild("Cutscene"):WaitForChild("CutscenePlayer"))
	end)
	CutscenePlayer = ok and mod or nil
end

-- ========= 설정 =========
local PROMPT_TAG              = "QuizPrompt"
local PROMPT_NAME_HINT        = "QuizPrompt"
local PROMPT_ATTR             = "IsQuizPrompt"
local CLIENT_ONLY_NAME_PREFIX = "_ClientOnlyPrompt"

-- 이 플레이스에서 "몇 스테이지용 컷씬"으로 보낼지 기본값
local STAGE_INDEX_DEFAULT = 1

-- ========= 상태 =========
local busy         = false
local cutsceneSent = false     -- 한 번만 서버로 요청 보내고 싶을 때 사용
local hooked: {[Instance]: boolean} = {}
local currentPrompt: ProximityPrompt? = nil

-- ★ 여기 추가: 발견한 모든 퀴즈 프롬프트를 모아두는 리스트 + 전체 on/off 플래그
local quizPrompts: {ProximityPrompt} = {}
local quizPromptsEnabled = false  -- 처음에는 전부 꺼진 상태

-- ========= QuizPrompt 제어용 Bus =========
local QuizPromptBus: BindableEvent do
	local obj = RS:FindFirstChild("QuizPromptBus")
	if obj and obj:IsA("BindableEvent") then
		QuizPromptBus = obj
	else
		local ev = Instance.new("BindableEvent")
		ev.Name = "QuizPromptBus"
		ev.Parent = RS
		QuizPromptBus = ev
	end
end

-- ========= 프롬프트 Enable/Disable 헬퍼 =========
local function setPromptEnabled(pp: ProximityPrompt, enabled: boolean, dist: number?)
	if not pp then return end
	pp.Enabled = enabled
	pp.MaxActivationDistance = enabled and (dist or 10) or 0
end

local function setAllQuizPromptsEnabled(enabled: boolean)
	quizPromptsEnabled = enabled
	for _, pp in ipairs(quizPrompts) do
		if pp and pp.Parent then
			setPromptEnabled(pp, enabled, 10)
		end
	end
end

-- QuizPromptBus 로 외부(다른 LocalScript)에서 제어 가능:
--   RS.QuizPromptBus:Fire("enableAll")
--   RS.QuizPromptBus:Fire("disableAll")
QuizPromptBus.Event:Connect(function(cmd: any)
	if cmd == "enableAll" then
		setAllQuizPromptsEnabled(true)
	elseif cmd == "disableAll" then
		setAllQuizPromptsEnabled(false)
	end
end)

-- ========= 유틸: 프롬프트가 어느 스테이지인지 추정 =========
local function guessStageFrom(inst: Instance?): number
	local p = inst
	while p do
		if p:IsA("Model") then
			local m = string.match(p.Name, "^Stage(%d+)Potal$")
			if m then
				return tonumber(m)
			end
		end
		local stAttr = p:GetAttribute("Stage")
		if typeof(stAttr) == "number" then
			return stAttr
		end
		p = p.Parent
	end
	return STAGE_INDEX_DEFAULT
end

-- ========= 퀴즈용 프롬프트 판별 =========
local function isQuizPrompt(pp: Instance): boolean
	if not pp or not pp:IsA("ProximityPrompt") then return false end

	-- 1) 태그로 붙은 경우
	if CollectionService:HasTag(pp, PROMPT_TAG) then
		return true
	end

	-- 2) 부모 쪽에 태그가 붙은 경우
	local p = pp.Parent
	while p do
		if CollectionService:HasTag(p, PROMPT_TAG) then
			return true
		end
		p = p.Parent
	end

	-- 3) 이름 힌트
	local n = pp.Name or ""
	if CLIENT_ONLY_NAME_PREFIX ~= "" then
		if string.sub(n, 1, #CLIENT_ONLY_NAME_PREFIX) == CLIENT_ONLY_NAME_PREFIX then
			return true
		end
	end
	if PROMPT_NAME_HINT ~= "" then
		local ln, hint = string.lower(n), string.lower(PROMPT_NAME_HINT)
		if string.find(ln, hint, 1, true) then
			return true
		end
	end

	-- 4) Attribute로 표시한 경우
	if pp:GetAttribute(PROMPT_ATTR) == true then
		return true
	end
	p = pp.Parent
	while p do
		if p:GetAttribute(PROMPT_ATTR) == true then
			return true
		end
		p = p.Parent
	end

	return false
end

-- ========= 프롬프트 Trigger 처리 (❗문제 UI 없음) =========
local function onTriggeredLocal(pp: ProximityPrompt)
	if not isQuizPrompt(pp) then return end
	if busy then return end
	if not quizPromptsEnabled then
		-- 아직 전체 QuizPrompt 비활성 단계라면 무시
		return
	end

	busy = true
	currentPrompt = pp

	-- 이 플레이스에서는 "문제"를 절대 띄우지 않고,
	-- 그냥 서버에 컷씬 요청만 보낸다.
	if not cutsceneSent then
		cutsceneSent = true

		local stage = guessStageFrom(pp)
		print("[QuizClient] QuizPrompt triggered (NO QUESTION MODE), request cutscene. stage =", stage)

		-- 서버에서 컷씬/텔레포트/포탈 스폰 등 처리
		RE_CutsceneReq:FireServer({
			reason = "noQuiz_here",  -- 서버에서 구분용 reason (원하면 바꿔도 됨)
			stage  = stage,
		})
	end

	-- 한 번만 반응하고 끝 (여러 번 누르고 싶으면 cutsceneSent 가드 제거)
	busy = false
	currentPrompt = nil
end

-- ========= 프롬프트 훅 =========
local function registerQuizPrompt(pp: ProximityPrompt)
	-- 리스트에 넣고, 현재 global 상태에 맞춰 enable/disable
	table.insert(quizPrompts, pp)
	setPromptEnabled(pp, quizPromptsEnabled, 10)
end

local function hookPrompt(pp: ProximityPrompt)
	if not pp or not pp:IsA("ProximityPrompt") then return end
	if hooked[pp] then return end
	if not isQuizPrompt(pp) then return end

	hooked[pp] = true

	-- ★ 여기서 더 이상 무조건 켜지 않음
	--    대신 registerQuizPrompt 에서 quizPromptsEnabled 값에 따라 설정
	registerQuizPrompt(pp)

	pp.RequiresLineOfSight = false

	pp.Triggered:Connect(function()
		onTriggeredLocal(pp)
	end)

	print("[QuizClient] hook QuizPrompt (NO-QUESTION MODE):", pp:GetFullName())
end

local function scanAll()
	-- 태그가 붙은 루트들 먼저
	for _, inst in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
		if inst:IsA("ProximityPrompt") then
			hookPrompt(inst)
		else
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("ProximityPrompt") then
					hookPrompt(d)
				end
			end
			inst.DescendantAdded:Connect(function(child)
				if child:IsA("ProximityPrompt") then
					hookPrompt(child)
				end
			end)
		end
	end

	-- 혹시 태그 없이 이름/Attribute로만 표시된 프롬프트들도 훅
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			if isQuizPrompt(d) then
				hookPrompt(d)
			end
		end
	end
end

scanAll()

-- 새로운 퀴즈용 오브젝트가 생성될 때도 훅
CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(function(inst)
	if inst:IsA("ProximityPrompt") then
		hookPrompt(inst)
	else
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				hookPrompt(d)
			end
		end
		inst.DescendantAdded:Connect(function(child)
			if child:IsA("ProximityPrompt") then
				hookPrompt(child)
			end
		end)
	end
end)

-- ClientOnlyPrompt 이름으로 생성되는 프롬프트도 자동 마킹
ProximityPromptService.PromptShown:Connect(function(pp)
	if not pp or not pp:IsA("ProximityPrompt") then return end
	local n = pp.Name or ""
	if string.sub(n, 1, #CLIENT_ONLY_NAME_PREFIX) == CLIENT_ONLY_NAME_PREFIX then
		if not pp:GetAttribute(PROMPT_ATTR) then
			pp:SetAttribute(PROMPT_ATTR, true)
		end
	end
end)

-- 혹시 다른 스크립트에서 Triggered를 직접 쏠 수도 있으니 한 번 더 가드
ProximityPromptService.PromptTriggered:Connect(function(pp, player)
	if player ~= LP then return end
	onTriggeredLocal(pp)
end)

-- ★ 초기에는 모든 QuizPrompt 비활성 상태 유지
setAllQuizPromptsEnabled(false)

print("[QuizClient] READY (NO-QUESTION MODE: QuizPrompt → 서버 컷씬 요청만 보냄, 기본은 비활성 / Bus로 on/off 제어 가능)")
