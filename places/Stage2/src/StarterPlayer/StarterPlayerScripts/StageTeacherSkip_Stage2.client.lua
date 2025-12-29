-- StarterPlayerScripts/StageTeacherSkip_Stage1.client.lua
--!strict
-- Stage2 교사용 스킵(이름은 Stage1이지만, Stage2 사다리/포탈에 맞춰둔 버전)
-- 선생님으로 들어오면:
--  - 퀴즈/퀘스트 관련 프롬프트 비활성화
--  - 쓰레기/정리 대상 오브젝트 로컬 정리
--  - 사다리 LadderCinematic.spawnInstant 로 즉시 소환
--  - NPC를 최종 위치로 이동
--  - 포탈은 이미 나와 있는 상태로만 보여줌 (컷씬/카메라 연출 없이)

wait(2)

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local ReplicatedFirst    = game:GetService("ReplicatedFirst")
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

local teacherFlowStarted = false

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

-- ===== Stage에서 이미 쓰던 모듈들 재사용 =====
local LocalObjectHider =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("InteractionActionRouter"))
	or tryRequire(RS:FindFirstChild("InteractionActionRouter"))

-- ★ PortalMover 는 더 이상 사용하지 않음

-- ★ 사다리 모듈 (spawnInstant 사용)
local LadderCinematic =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("LadderCinematic"))
	or tryRequire(RS:FindFirstChild("LadderCinematic"))

-- ★ Stage2 사다리 템플릿 / 위치 (QuizClient와 동일 값)
local LADDER_TEMPLATE: Instance? = RS:FindFirstChild("Stage2Ladder")
local LADDER_POS = Vector3.new(-59.745, 29.593, 125.927)

-- 포탈 템플릿 (Potal)
local PortalTemplate: Model? = nil
do
        local t = ReplicatedFirst:FindFirstChild("Potal")
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
-- 0) Tag / 상수
----------------------------------------------------------------
local QUIZ_PROMPT_TAG     = "QuizPrompt"
local DIALOGUE_TAG        = "DialoguePrompt"
local QUEST_NPC_TAG       = "QuestNPC"
local FIRST_TRASH_TAG     = "QuestObject"
local LOCAL_PROMPT_NAME   = "_ClientOnlyPrompt"

local DISAPPEAR_TAGS = { "Disappear", "VanishOnCorrect", "Box", "seaShell" }

----------------------------------------------------------------
-- 1) 퀴즈/퀘스트 관련 ProximityPrompt 비활성화
----------------------------------------------------------------
local function isStagePrompt(pp: ProximityPrompt): boolean
	if CollectionService:HasTag(pp, QUIZ_PROMPT_TAG) then
		return true
	end
	if CollectionService:HasTag(pp, DIALOGUE_TAG) then
		return true
	end

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
-- 2) LocalObjectHider 로 정리 대상 오브젝트 정리
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
-- 3) NPC 최종 위치
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

----------------------------------------------------------------
-- 4) 선생님용 포탈 스폰
----------------------------------------------------------------
local function spawnPortalForTeacher(): Instance?
        if not PortalTemplate then
                warn("[StageTeacherSkip_Stage1] PortalTemplate 'Potal' not found in ReplicatedFirst")
                return nil
        end

	local targetPos = Vector3.new(-161.618, 68.906, 143.565)
	local clone = PortalTemplate:Clone()
	clone.Name = "Potal_TeacherView"
	clone.Parent = Workspace

	local pivot = PortalTemplate:GetPivot()
	local targetCF = CFrame.fromMatrix(targetPos, pivot.RightVector, pivot.UpVector)
	clone:PivotTo(targetCF)

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
-- 5) 선생님용 사다리 스폰: LadderCinematic.spawnInstant + Stage2 고정 좌표
----------------------------------------------------------------
local function spawnLadderForTeacher(): Instance?
	if not LadderCinematic then
		warn("[StageTeacherSkip_Stage1] LadderCinematic 모듈을 찾지 못했습니다")
		return nil
	end

	if typeof(LadderCinematic.spawnInstant) ~= "function" then
		warn("[StageTeacherSkip_Stage1] LadderCinematic.spawnInstant 가 없습니다")
		return nil
	end

	if not LADDER_TEMPLATE then
		warn("[StageTeacherSkip_Stage1] Stage2Ladder 템플릿을 찾지 못했습니다")
		return nil
	end

	print("[StageTeacherSkip_Stage1] Spawning ladder for teacher at", LADDER_POS)

	local ladder = LadderCinematic.spawnInstant({
		template = LADDER_TEMPLATE,
		position = LADDER_POS,
		parent   = Workspace,
		-- 필요하면 옵션 더 넣기:
		-- keepChildrenTransparent = false,
		-- soundId = "rbxassetid://...",
		-- soundVolume = 1,
	})

	if not ladder then
		warn("[StageTeacherSkip_Stage1] spawnInstant returned nil")
	else
		print("[StageTeacherSkip_Stage1] Ladder spawned OK:", ladder:GetFullName())
	end

	return ladder
end

----------------------------------------------------------------
-- 6) 포탈 가이드
----------------------------------------------------------------
local function guideToPortal(portal: Instance?)
	if not QuestGuideBus then return end

	if portal then
		QuestGuideBus:Fire("targetPortal", portal)
	else
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

        print("[StageTeacherSkip_Stage2] Teacher detected → show cleared state, skip Stage flows", reason)

        task.defer(function()
                disableStagePromptsForTeacher()
                cleanAllStageTrashForTeacher()
                moveQuestNPCToSpawn()

                local ladder = spawnLadderForTeacher()
                local portal = spawnPortalForTeacher()

                guideToPortal(portal or ladder)
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

                warn("[StageTeacherSkip_Stage2] Teacher flag not detected after delay. Running student flow.")
        end

        if StageRolePolicy and StageRolePolicy.ObserveTeacher and StageRolePolicy.WaitForRoleReplication then
                task.spawn(function()
                        StageRolePolicy.WaitForRoleReplication(LP, 12)

                        if detectTeacher() then
                                startTeacherFlow("(post-spawn)")
                                return
                        end

                        local disconnect: (() -> ())? = nil

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
                                warn("[StageTeacherSkip_Stage2] Teacher flag not detected after delay. Running student flow.")
                                if disconnect then
                                        disconnect()
                                end
                        end)
                end)

                return
        end

        task.spawn(fallback)
end

monitorTeacherFlag()
