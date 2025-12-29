-- ServerScriptService/Modules/SessionProgress.lua
--!strict
-- ★ 플레이어별 진행도 저장되는 버전 (sessionId + userId 조합 key)
-- ★ DataStore 기반 (세션/개인 단위로 퀘스트/퀴즈/컷씬/삭제 오브젝트 저장)

local DataStoreService = game:GetService("DataStoreService")

local DS = DataStoreService:GetDataStore("SessionProgress_v2") -- 새 스키마

export type StageData = {
	quizSolved: {[string]: boolean},
	cutscenes: {[string]: boolean},
	questPhase: number,
	extraTrash: number,
	cleanedObjects: {[string]: boolean},

	-- ★ 추가: 퀴즈 점수/시간
	quizScore: number,
	quizTimeSec: number,
}

export type SessionData = {
	id: string,
	currentStage: number?,
	stages: {[number]: StageData},
	createdAt: number,
	updatedAt: number,
}

local M = {}

local _sessions: {[string]: SessionData} = {}

local STAGE1 = 4

-----------------------------------------------------
-- progressKey = sessionId:u<userId>
-----------------------------------------------------
local function buildKey(sessionId: string, userId: number): string
	return string.format("%s:u%d", sessionId, userId)
end

local function keyFromPlayer(plr: Player): string?
	local sid = plr:GetAttribute("sessionId")
	if typeof(sid) ~= "string" or sid == "" then return nil end
	return buildKey(sid, plr.UserId)
end

-----------------------------------------------------
-- 세션 로드/세이브
-----------------------------------------------------
local function ensureSession(key: string): SessionData
	local sess = _sessions[key]
	if sess then return sess end

	-- DataStore load
	local stored: any = nil
	local ok, res = pcall(function()
		return DS:GetAsync(key)
	end)
	if ok and typeof(res) == "table" then
		stored = res
	end

	if stored then
		sess = stored :: SessionData
	else
		sess = {
			id = key,
			currentStage = 4,
			stages = {},
			createdAt = os.time(),
			updatedAt = os.time(),
		}
	end

	_sessions[key] = sess
	return sess
end

local function saveSession(key: string)
	local sess = _sessions[key]
	if not sess then return end

	sess.updatedAt = os.time()
	pcall(function()
		DS:SetAsync(key, sess)
	end)
end

-----------------------------------------------------
-- StageData 생성
-----------------------------------------------------
local function ensureStage(sess: SessionData, stage: number): StageData
	local st = sess.stages[stage]

	if not st then
		-- ★ 신규 생성
		st = {
			quizSolved = {},
			cutscenes = {},
			questPhase = 0,
			extraTrash = 0,
			cleanedObjects = {},
			quizScore = 0,
			quizTimeSec = 0,
		}
		sess.stages[stage] = st
	else
		-- ★ 예전에 저장된 데이터 호환용(필드 없으면 기본값 세팅)
		st.quizSolved = st.quizSolved or {}
		st.cutscenes = st.cutscenes or {}
		st.cleanedObjects = st.cleanedObjects or {}
		st.questPhase = st.questPhase or 0
		st.extraTrash = st.extraTrash or 0
		st.quizScore = st.quizScore or 0
		st.quizTimeSec = st.quizTimeSec or 0
	end

	return st
end

local function emptyStage(): StageData
	return {
		quizSolved = {},
		cutscenes = {},
		questPhase = 0,
		extraTrash = 0,
		cleanedObjects = {},
		quizScore = 0,
		quizTimeSec = 0,
	}
end

-----------------------------------------------------
-- API: 퀴즈 정답
-----------------------------------------------------
function M.MarkQuizSolved(key: string, stage: number, qid: string)
	local sess = ensureSession(key)
	local st = ensureStage(sess, stage)
	st.quizSolved[qid] = true
	saveSession(key)
end

-----------------------------------------------------
-- ★ 추가 API: 퀴즈 점수/시간
-----------------------------------------------------
function M.SetQuizRuntime(key: string, stage: number, score: number, timeSec: number)
	local sess = ensureSession(key)
	local st = ensureStage(sess, stage)

	local nScore = math.max(0, math.floor(score))
	local nTime  = math.max(0, math.floor(timeSec))

	st.quizScore = nScore
	st.quizTimeSec = nTime

	saveSession(key)
end

-----------------------------------------------------
-- API: 컷씬 완료
-----------------------------------------------------
function M.MarkCutscenePlayed(key: string, stage: number, cut: string)
	local sess = ensureSession(key)
	local st = ensureStage(sess, stage)
	st.cutscenes[cut] = true
	saveSession(key)
end

-----------------------------------------------------
-- API: QuestPhase / ExtraTrash
-----------------------------------------------------
function M.SetQuestPhase(key: string, stage: number, phase: number)
	local sess = ensureSession(key)
	local st = ensureStage(sess, stage)
	st.questPhase = math.max(0, phase)
	saveSession(key)
end

function M.SetExtraTrash(key: string, stage: number, count: number)
	local sess = ensureSession(key)
	local st = ensureStage(sess, stage)
	st.extraTrash = math.max(0, count)
	saveSession(key)
end

-----------------------------------------------------
-- API: 삭제된 오브젝트 기록
-----------------------------------------------------
function M.MarkObjectCleaned(key: string, stage: number, objectId: string)
	local sess = ensureSession(key)
	local st = ensureStage(sess, stage)
	st.cleanedObjects[objectId] = true
	saveSession(key)
end

-----------------------------------------------------
-- StageProgress DTO
-----------------------------------------------------
function M.GetStageProgress(key: string, stage: number): StageData
	-- ★ 여기서도 무조건 ensureSession을 호출해서
	--    DataStore에 저장된 내용까지 포함해서 읽어온다.
	local sess = ensureSession(key)
	local st = sess.stages[stage]
	if not st then
		return emptyStage()
	end
	-- ensureStage 로 필드 채운 상태 보장하고 싶으면:
	return ensureStage(sess, stage)
end

-----------------------------------------------------
-- Stage1 전용 (Player 기반)
-----------------------------------------------------
function M.GetStage1State(plr: Player): StageData
	local key = keyFromPlayer(plr)
	if not key then
		return emptyStage()
	end
	return M.GetStageProgress(key, STAGE1)
end

function M.SetQuestState(plr: Player, phase: number, extra: number)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.SetQuestPhase(key, STAGE1, phase)
	M.SetExtraTrash(key, STAGE1, extra)
end

function M.SetCutsceneFlag(plr: Player, flag: string)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.MarkCutscenePlayed(key, STAGE1, flag)
end

-- (필요하면 나중에 편하게 쓰라고 Stage1 전용 helper도 추가 가능)
function M.SetStage1QuizRuntime(plr: Player, score: number, timeSec: number)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.SetQuizRuntime(key, STAGE1, score, timeSec)
end

return M
