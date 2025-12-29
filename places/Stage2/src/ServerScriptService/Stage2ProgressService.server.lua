-- ServerScriptService/Stage1ProgressService.lua
--!strict
-- Stage1 진행도(퀴즈/퀘스트/컷씬/cleanedObjects) + 클라 동기화

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService= game:GetService("ServerScriptService")

local SessionProgress = require(ServerScriptService.Modules:WaitForChild("SessionProgress"))

local STAGE_INDEX = 2

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

local RF_Stage1_GetProgress   = ensureRF("RF_Stage2_GetProgress")
local RE_Stage1_QuestSync     = ensureRE("RE_Stage2_QuestSync")
local RE_Stage1_CutsceneFlag  = ensureRE("RE_Stage2_CutsceneFlag")
local RE_Stage1_ObjectCleaned = ensureRE("RE_Stage2_ObjectCleaned")
local RE_Stage1_QuizSolved    = ensureRE("RE_Stage2_QuizSolved") -- ★ 퀴즈 정답 보고
local RE_Stage1_QuizRuntime   = ensureRE("RE_Stage2_QuizRuntime") -- ★ 점수/시간 실시간 저장

--------------------------------------------------
-- key = sessionId:u<userId>
--------------------------------------------------
local function getKey(plr: Player): string?
	local sid = plr:GetAttribute("sessionId")
	if typeof(sid) ~= "string" or sid == "" then
		warn("[Stage1ProgressService] no sessionId for", plr.Name)
		return nil
	end
	return string.format("%s:u%d", sid, plr.UserId)
end

--------------------------------------------------
-- RemoteFunction: 클라에서 Stage1 진행도 요청
--------------------------------------------------
RF_Stage1_GetProgress.OnServerInvoke = function(plr: Player)
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

	local st = SessionProgress.GetStage1State(plr)

	-- cleanedObjects 개수 세기 (디버그용)
	local cleanedCount = 0
	for _, flag in pairs(st.cleanedObjects or {}) do
		if flag then cleanedCount += 1 end
	end

	print(("[Stage1ProgressService] GetProgress plr=%s key=%s phase=%d extra=%d cleaned=%d score=%d time=%d")
		:format(plr.Name, key, st.questPhase or 0, st.extraTrash or 0, cleanedCount, st.quizScore or 0, st.quizTimeSec or 0))

	return st
end

--------------------------------------------------
-- RemoteEvent: 퀘스트 상태 동기화 (클라 → 서버)
--------------------------------------------------
RE_Stage1_QuestSync.OnServerEvent:Connect(function(plr: Player, phase: any, extra: any)
	local key = getKey(plr)
	if not key then return end

	local nPhase = tonumber(phase) or 0
	local nExtra = tonumber(extra) or 0

	print(("[Stage1ProgressService] QuestSync plr=%s phase=%d extra=%d")
		:format(plr.Name, nPhase, nExtra))

	SessionProgress.SetQuestState(plr, nPhase, nExtra)
end)

--------------------------------------------------
-- RemoteEvent: 컷씬 플래그 (클라 → 서버)
--------------------------------------------------
RE_Stage1_CutsceneFlag.OnServerEvent:Connect(function(plr: Player, flag: any)
	local key = getKey(plr)
	if not key then return end

	local flagStr = tostring(flag)

	print(("[Stage1ProgressService] CutsceneFlag plr=%s key=%s flag=%s")
		:format(plr.Name, key, flagStr))

	SessionProgress.SetCutsceneFlag(plr, flagStr)
end)

--------------------------------------------------
-- RemoteEvent: 오브젝트 정화 기록 (클라 → 서버)
--------------------------------------------------
RE_Stage1_ObjectCleaned.OnServerEvent:Connect(function(plr: Player, objectId: any)
	local key = getKey(plr)
	if not key then return end

	local idStr = tostring(objectId)
	if idStr == "" then return end

	print(("[Stage1ProgressService] ObjectCleaned plr=%s key=%s objectId=%s")
		:format(plr.Name, key, idStr))

	SessionProgress.MarkObjectCleaned(key, STAGE_INDEX, idStr)
end)

--------------------------------------------------
-- RemoteEvent: 퀴즈 정답 기록 (클라 → 서버)
--------------------------------------------------
RE_Stage1_QuizSolved.OnServerEvent:Connect(function(plr: Player, qid: any)
	local key = getKey(plr)
	if not key then return end

	local qidStr = tostring(qid)
	if qidStr == "" then return end

	print(("[Stage1ProgressService] QuizSolved plr=%s key=%s qid=%s")
		:format(plr.Name, key, qidStr))

	-- SessionProgress 에 퀴즈 정답 저장
	SessionProgress.MarkQuizSolved(key, STAGE_INDEX, qidStr)
end)

--------------------------------------------------
-- ★ RemoteEvent: 퀴즈 점수/시간 실시간 기록 (클라 → 서버)
--------------------------------------------------
RE_Stage1_QuizRuntime.OnServerEvent:Connect(function(plr: Player, scoreAny: any, timeAny: any)
	local key = getKey(plr)
	if not key then return end

	local score   = tonumber(scoreAny) or 0
	local timeSec = tonumber(timeAny) or 0

	if score < 0 then score = 0 end
	if timeSec < 0 then timeSec = 0 end

	print(("[Stage1ProgressService] QuizRuntime plr=%s key=%s score=%d time=%ds")
		:format(plr.Name, key, score, timeSec))

	SessionProgress.SetQuizRuntime(key, STAGE_INDEX, score, timeSec)
end)

print("[Stage1ProgressService] READY (Stage1 progress + cleanedObjects + quizSolved + quizRuntime 기록)")
