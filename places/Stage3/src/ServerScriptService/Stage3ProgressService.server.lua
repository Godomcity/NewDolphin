--!strict
-- Stage3 진행도(퀴즈/퀘스트/컷씬/cleanedObjects) + 클라 동기화

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService= game:GetService("ServerScriptService")

local SessionProgress = require(ServerScriptService.Modules:WaitForChild("SessionProgress"))

local STAGE_INDEX = 3  -- ★ Stage3

--------------------------------------------------
-- Remotes 준비
--------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function ensureRF(name: string): RemoteFunction
	local obj = Remotes:FindFirstChild(name)
	if obj and obj:IsA("RemoteFunction") then
		return obj
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = Remotes
	return rf
end

local function ensureRE(name: string): RemoteEvent
	local obj = Remotes:FindFirstChild(name)
	if obj and obj:IsA("RemoteEvent") then
		return obj
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = Remotes
	return re
end

local RF_Stage3_GetProgress   = ensureRF("RF_Stage3_GetProgress")
local RE_Stage3_QuestSync     = ensureRE("RE_Stage3_QuestSync")
local RE_Stage3_CutsceneFlag  = ensureRE("RE_Stage3_CutsceneFlag")
local RE_Stage3_ObjectCleaned = ensureRE("RE_Stage3_ObjectCleaned")
local RE_Stage3_QuizSolved    = ensureRE("RE_Stage3_QuizSolved")

--------------------------------------------------
-- key = sessionId:u<userId>
--------------------------------------------------
local function getKey(plr: Player): string?
	local sid = plr:GetAttribute("sessionId")
	if typeof(sid) ~= "string" or sid == "" then
		warn("[Stage3ProgressService] no sessionId for", plr.Name)
		return nil
	end
	return string.format("%s:u%d", sid, plr.UserId)
end

--------------------------------------------------
-- RemoteFunction: 클라에서 Stage3 진행도 요청
--------------------------------------------------
RF_Stage3_GetProgress.OnServerInvoke = function(plr: Player)
	local key = getKey(plr)
	if not key then
		-- sessionId 없으면 빈 진행도
		return {
			quizSolved     = {},
			cutscenes      = {},
			questPhase     = 0,
			extraTrash     = 0,
			cleanedObjects = {},
			quizScore      = 0,
			quizTimeSec    = 0,
		}
	end

	-- ★ Stage3 진행도 읽기
	local st = SessionProgress.GetStage3State(plr)

	-- 디버그용 카운트
	local cleanedCount = 0
	for _, flag in pairs(st.cleanedObjects or {}) do
		if flag then cleanedCount += 1 end
	end

	local solvedCount = 0
	for _, flag in pairs(st.quizSolved or {}) do
		if flag then solvedCount += 1 end
	end

	print(("[Stage3ProgressService] GetProgress plr=%s key=%s phase=%d extra=%d cleaned=%d solved=%d score=%d time=%d")
		:format(
			plr.Name,
			key,
			st.questPhase or 0,
			st.extraTrash or 0,
			cleanedCount,
			solvedCount,
			st.quizScore or 0,
			st.quizTimeSec or 0
		)
	)

	-- 클라가 기대하는 구조에 맞춰 반환
	return {
		quizSolved     = st.quizSolved     or {},
		cutscenes      = st.cutscenes      or {},
		questPhase     = st.questPhase     or 0,
		extraTrash     = st.extraTrash     or 0,
		cleanedObjects = st.cleanedObjects or {},
		quizScore      = st.quizScore      or 0,
		quizTimeSec    = st.quizTimeSec    or 0,
	}
end

--------------------------------------------------
-- RemoteEvent: 퀘스트 상태 동기화 (클라 → 서버)
--------------------------------------------------
RE_Stage3_QuestSync.OnServerEvent:Connect(function(plr: Player, phase: any, extra: any)
	local key = getKey(plr)
	if not key then return end

	local nPhase = tonumber(phase) or 0
	local nExtra = tonumber(extra) or 0

	print(("[Stage3ProgressService] QuestSync plr=%s key=%s phase=%d extra=%d")
		:format(plr.Name, key, nPhase, nExtra))

	-- Stage3용 퀘스트 상태 저장
	SessionProgress.SetQuestState(plr, nPhase, nExtra)
end)

--------------------------------------------------
-- RemoteEvent: 컷씬 플래그 (클라 → 서버)
--------------------------------------------------
RE_Stage3_CutsceneFlag.OnServerEvent:Connect(function(plr: Player, flag: any)
	local key = getKey(plr)
	if not key then return end

	local flagStr = tostring(flag)

	print(("[Stage3ProgressService] CutsceneFlag plr=%s key=%s flag=%s")
		:format(plr.Name, key, flagStr))

	SessionProgress.SetCutsceneFlag(plr, flagStr)
end)

--------------------------------------------------
-- RemoteEvent: 오브젝트 정화 기록 (클라 → 서버)
--------------------------------------------------
RE_Stage3_ObjectCleaned.OnServerEvent:Connect(function(plr: Player, objectId: any)
	local key = getKey(plr)
	if not key then return end

	local idStr = tostring(objectId)
	if idStr == "" then return end

	print(("[Stage3ProgressService] ObjectCleaned plr=%s key=%s objectId=%s")
		:format(plr.Name, key, idStr))

	-- ★ Stage3 인덱스로 기록
	SessionProgress.MarkObjectCleaned(key, STAGE_INDEX, idStr)
end)

--------------------------------------------------
-- RemoteEvent: 퀴즈 정답 기록 (클라 → 서버)
--------------------------------------------------
RE_Stage3_QuizSolved.OnServerEvent:Connect(function(plr: Player, qid: any)
	local key = getKey(plr)
	if not key then return end

	local qidStr = tostring(qid)
	if qidStr == "" then return end

	print(("[Stage3ProgressService] QuizSolved plr=%s key=%s qid=%s")
		:format(plr.Name, key, qidStr))

	-- ★ Stage3 인덱스로 퀴즈 정답 저장
	SessionProgress.MarkQuizSolved(key, STAGE_INDEX, qidStr)
end)

print("[Stage3ProgressService] READY (Stage3 progress + cleanedObjects + quizSolved 기록)")
