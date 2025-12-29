-- StarterPlayerScripts/StageTeacherSkip_Stage1.client.lua
--!strict
-- Stage1 전용
-- 선생님으로 들어오면:
--  - Stage1 퀴즈/퀘스트 관련 프롬프트 비활성화
--  - Stage1 쓰레기/정리 대상 오브젝트 로컬에서 정리 (InteractionActionRouter 사용)
--  - Stage1 문은 이미 열린 상태 (PortalMover.Open/FadeOut)
--  - NPC를 최종 위치로 이동
--  - 포탈은 이미 나와 있는 상태로만 보여줌 (컷씬/카메라 연출 없이)
--  → 재입장 시 진행도 복원된 느낌처럼, 선생님은 처음부터 "다 끝난 상태"만 보게 됨

wait(5)

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local Workspace          = game:GetService("Workspace")
local CollectionService  = game:GetService("CollectionService")

local LP = Players.LocalPlayer

-- ===== 공통 tryRequire =====
local function tryRequire(inst: Instance?): any
        if not inst or not inst:IsA("ModuleScript") then return nil end
        local ok, m = pcall(require, inst)
        return ok and m or nil
end

-- ===== 역할 모듈 =====
local StageRolePolicy =
        tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("StageRolePolicy"))
        or tryRequire(RS:FindFirstChild("StageRolePolicy"))

local function detectTeacher(): boolean
        if StageRolePolicy and typeof(StageRolePolicy.IsTeacher) == "function" then
                local ok, res = pcall(function()
                        return StageRolePolicy.IsTeacher(LP)
                end)
                if ok and res then
                        return true
                end
        end

        if StageRolePolicy and typeof(StageRolePolicy.ShouldSkipStageClientFlow) == "function" then
                local ok, res = pcall(function()
                        return StageRolePolicy.ShouldSkipStageClientFlow(LP)
                end)
                if ok and res then
                        return true
                end
        end

        return false
end

-- ===== Stage1 에서 이미 쓰던 모듈들 재사용 =====
local LocalObjectHider =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("InteractionActionRouter"))
	or tryRequire(RS:FindFirstChild("InteractionActionRouter"))

local PortalMover =
	tryRequire(RS:FindFirstChild("PortalMover"))
	or tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PortalMover"))

-- 포탈 템플릿 (DialogueUI/PortalSpawnCutscene 에서 쓰던 "Potal" 기준)
local PortalTemplate: Model? = nil
do
	local t = RS:FindFirstChild("Potal")
	if t and t:IsA("Model") then
		PortalTemplate = t
	end
end

local QuestGuideBus: BindableEvent? do
	local obj = RS:FindFirstChild("QuestGuideBus")
	if obj and obj:IsA("BindableEvent") then
		QuestGuideBus = obj
	end
end

----------------------------------------------------------------
-- 0) Tag / 상수 (QuizClient와 맞추기)
----------------------------------------------------------------
local QUIZ_PROMPT_TAG     = "QuizPrompt"
local DIALOGUE_TAG        = "DialoguePrompt"
local QUEST_NPC_TAG       = "QuestNPC"
local FIRST_TRASH_TAG     = "QuestObject"
local LOCAL_PROMPT_NAME   = "_ClientOnlyPrompt"

-- InteractionActionRouter 에서 사용하는 삭제 대상 태그들
local DISAPPEAR_TAGS = { "Disappear", "VanishOnCorrect", "Box", "seaShell" }

local teacherFlowStarted = false
local teacherBroadcastDisconnect: (() -> ())? = nil

----------------------------------------------------------------
-- 1) 퀴즈/퀘스트 관련 ProximityPrompt 비활성화
----------------------------------------------------------------
local function isStagePrompt(pp: ProximityPrompt): boolean
	-- 퀴즈 태그
	if CollectionService:HasTag(pp, QUIZ_PROMPT_TAG) then
		return true
	end
	-- 대화 태그
	if CollectionService:HasTag(pp, DIALOGUE_TAG) then
		return true
	end

	-- NPC/튜토리얼 쓰레기 아래 프롬프트도 포함
	local cur: Instance? = pp
	while cur do
		if CollectionService:HasTag(cur, QUEST_NPC_TAG) then
			return true
		end
		if CollectionService:HasTag(cur, FIRST_TRASH_TAG) then
			return true
		end
		cur = cur.Parent
	end

	-- 로컬 전용 프롬프트 이름
	if pp.Name == LOCAL_PROMPT_NAME then
		return true
	end

	return false
end

local function disableStagePromptsForTeacher()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			local pp = inst :: ProximityPrompt
			if isStagePrompt(pp) then
				pp.Enabled = false
				pp.MaxActivationDistance = 0
				pp.HoldDuration = 0
			end
		end
	end

	-- 나중에 프롬프트가 생기는 경우도 막기
	Workspace.DescendantAdded:Connect(function(inst)
		if inst:IsA("ProximityPrompt") then
			local pp = inst :: ProximityPrompt
			if isStagePrompt(pp) then
				pp.Enabled = false
				pp.MaxActivationDistance = 0
				pp.HoldDuration = 0
			end
		end
	end)
end

----------------------------------------------------------------
-- 2) LocalObjectHider 를 이용해서 "정리 대상" 오브젝트 싹 정리
--    → 재입장 시 cleanedObjects 기준으로 지워지는 것처럼, 선생님은 바로 정리된 상태만 보게
----------------------------------------------------------------
local function localDisappearByInstance(inst: Instance)
	if not LocalObjectHider or typeof(LocalObjectHider.run) ~= "function" then return end

	local ok, err = pcall(function()
		LocalObjectHider.run(inst, {
			fadeDuration = 0.35,
			delayDestroy = 0.0,
		}, {
			targetTags = DISAPPEAR_TAGS,
		})
	end)
	if not ok then
		warn("[StageTeacherSkip_Stage1] localDisappearByInstance error:", err)
	end
end

local function isDisappearTarget(inst: Instance): boolean
	for _, tag in ipairs(DISAPPEAR_TAGS) do
		if CollectionService:HasTag(inst, tag) then
			return true
		end
	end
	return false
end

local function cleanAllStageTrashForTeacher()
	if not LocalObjectHider then
		warn("[StageTeacherSkip_Stage1] LocalObjectHider(InteractionActionRouter) not found")
		return
	end

	for _, inst in ipairs(Workspace:GetDescendants()) do
		if isDisappearTarget(inst) then
			localDisappearByInstance(inst)
		end
	end
end

----------------------------------------------------------------
-- 3) 문 오픈 상태 & NPC 최종 위치 (QuizClient 의 결과 상태만 반영)
----------------------------------------------------------------
local function moveQuestNPCToSpawn()
	local spawn = Workspace:FindFirstChild("NpcSpawnPart")
	if not (spawn and spawn:IsA("BasePart")) then
		warn("[StageTeacherSkip_Stage1] NpcSpawnPart 를 찾지 못했습니다.")
		return
	end

	for _, inst in ipairs(CollectionService:GetTagged(QUEST_NPC_TAG)) do
		if inst:IsA("Model") then
			local ok, err = pcall(function()
				(inst :: Model):PivotTo((spawn :: BasePart).CFrame)
			end)
			if not ok then
				warn("[StageTeacherSkip_Stage1] PivotTo failed:", err)
			end
		elseif inst:IsA("BasePart") then
			local ok, err = pcall(function()
				(inst :: BasePart).CFrame = (spawn :: BasePart).CFrame
			end)
			if not ok then
				warn("[StageTeacherSkip_Stage1] Move NPC part failed:", err)
			end
		end
	end
end

local function applyDoorOpenedVisual()
	if not PortalMover then
		warn("[StageTeacherSkip_Stage1] PortalMover 모듈을 찾지 못했습니다. 문 오픈 스킵")
		return
	end

	local ok, err = pcall(function()
		-- Stage1 기준: stageIndex = 1, doorIndex = 6 (QuizClient 에서 쓰던 값과 맞춰야 함)
		if PortalMover.Open then
			PortalMover.Open(1, 6, 0.1)
		end
		if PortalMover.FadeOut then
			PortalMover.FadeOut(1, 0)
		end
	end)

	if not ok then
		warn("[StageTeacherSkip_Stage1] applyDoorOpenedVisual failed:", err)
	end
end

----------------------------------------------------------------
-- 4) 선생님용 포탈 스폰 (컷씬/카메라 없이, 템플릿만 복제해서 활성화)
----------------------------------------------------------------
local function spawnPortalForTeacher(): Instance?
	if not PortalTemplate then
		warn("[StageTeacherSkip_Stage1] PortalTemplate 'Potal' not found in ReplicatedStorage")
		return nil
	end

	-- DialogueUI/PortalSpawnCutscene 에서 사용하던 좌표 그대로 사용
	local targetPos = Vector3.new(-241.601, 26.539, 18.286)
	local clone = PortalTemplate:Clone()
	clone.Name = "Potal_TeacherView"
	clone.Parent = Workspace

	-- 템플릿의 기본 Pivot 방향을 유지한 채 위치만 맞추기
	local pivot = PortalTemplate:GetPivot()
	local targetCF = CFrame.fromMatrix(targetPos, pivot.RightVector, pivot.UpVector)
	clone:PivotTo(targetCF)

	-- ProximityPrompt / ParticleEmitter 활성화
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			local pp = d :: ProximityPrompt
			pp.Enabled = true
			if pp.MaxActivationDistance <= 0 then
				pp.MaxActivationDistance = 10
			end
		elseif d:IsA("ParticleEmitter") then
			local pe = d :: ParticleEmitter
			pe.Enabled = true
			pe:Clear()
			local ok = pcall(function()
				pe:FastForward(0.25)
			end)
			if not ok then
				pe:Emit(1)
			end
		end
	end

	print("[StageTeacherSkip_Stage1] Spawned portal for teacher at", targetPos)
	return clone
end

----------------------------------------------------------------
-- 5) 포탈 가이드 맞춰주기
----------------------------------------------------------------
local function guideToPortal(portal: Instance?)
	if not QuestGuideBus then return end

	if portal then
		QuestGuideBus:Fire("targetPortal", portal)
	else
		-- 태그 붙어 있으면 그걸로 한 번 더 시도
		local taggedPortal: Instance? = nil
		for _, inst in ipairs(CollectionService:GetTagged("Stage1Portal")) do
			taggedPortal = inst
			break
		end

		if taggedPortal then
			QuestGuideBus:Fire("targetPortal", taggedPortal)
		else
			QuestGuideBus:Fire("targetPortal")
		end
	end
end

----------------------------------------------------------------
-- 메인 실행
----------------------------------------------------------------
local function startTeacherFlow(reason: string?)
        if teacherFlowStarted then return end
        teacherFlowStarted = true

        if teacherBroadcastDisconnect then
                teacherBroadcastDisconnect()
                teacherBroadcastDisconnect = nil
        end

        print("[StageTeacherSkip_Stage1] Teacher detected → show cleared state, skip Stage1 flows", reason)

	task.defer(function()
		-- 1) 먼저 프롬프트 막기 (선생님은 트리거 자체가 안 되도록 → 컷씬/문제 스킵)
		disableStagePromptsForTeacher()

		-- 2) 쓰레기/정리 대상 오브젝트 싹 정리
		cleanAllStageTrashForTeacher()

		-- 3) 문은 이미 열린 상태 + NPC는 최종 위치로
		applyDoorOpenedVisual()
		moveQuestNPCToSpawn()

		-- 4) 포탈 템플릿을 바로 스폰 (컷씬 없이)
		local portal = spawnPortalForTeacher()

		-- 5) 가이드가 있다면 포탈 쪽으로 향하게
		guideToPortal(portal)
	end)
end

local function monitorTeacherFlag()
        local function fallback()
                local deadline = os.clock() + 12
                while os.clock() < deadline do
                        if detectTeacher() then
                                startTeacherFlow("(fallback)")
                                return
                        end
                        task.wait(0.5)
                end

                warn("[StageTeacherSkip_Stage1] Teacher flag not detected after delay. Running student flow.")
        end

        if StageRolePolicy and StageRolePolicy.ObserveTeacher and StageRolePolicy.WaitForRoleReplication then
                task.spawn(function()
                        StageRolePolicy.WaitForRoleReplication(LP, 12)

                        if detectTeacher() then
                                startTeacherFlow("(post-spawn)")
                                return
                        end

                        local disconnect: (() -> ())? = nil

                        local observeBroadcast = StageRolePolicy and StageRolePolicy.ObserveTeacherBroadcast
                        if observeBroadcast then
                                teacherBroadcastDisconnect = observeBroadcast(LP, function(_, isTeacher)
                                        if isTeacher then
                                                startTeacherFlow("(TeacherRoleUpdated)")
                                        end
                                end, 12)
                        end

                        local function onTeacherChanged(isTeacher: boolean, reason: string?)
                                if not isTeacher or teacherFlowStarted then
                                        return
                                end

                                if disconnect then
                                        disconnect()
                                end
                                startTeacherFlow(reason)
                        end

                        disconnect = StageRolePolicy.ObserveTeacher(LP, function(isTeacher: boolean, reason: string?)
                                onTeacherChanged(isTeacher, reason)
                        end, { timeoutSec = 12 })

                        task.delay(15, function()
                                if teacherFlowStarted then return end
                                warn("[StageTeacherSkip_Stage1] Teacher flag not detected after delay. Running student flow.")
                                if disconnect then
                                        disconnect()
                                end
                        end)
                end)

                return
        end

        -- StageRolePolicy가 없거나 실패하는 경우에도 최소한 한 번 더 확인한다
        task.spawn(fallback)
end

monitorTeacherFlag()
