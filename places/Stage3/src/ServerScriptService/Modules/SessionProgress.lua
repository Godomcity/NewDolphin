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

local STAGE3 = 3

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
			-- ★ Stage3 플레이스이므로 기본 currentStage = 3
			currentStage = STAGE3,
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
		st = {
			quizSolved     = {},
			cutscenes      = {},
			questPhase     = 0,
			extraTrash     = 0,
			cleanedObjects = {},

			-- ★ 새 필드 기본값
			quizScore   = 0,
			quizTimeSec = 0,
		}
		sess.stages[stage] = st
	else
		-- ★ 옛 데이터 방어: 필드가 없으면 기본값 채워주기
		if st.quizScore == nil then
			st.quizScore = 0
		end
		if st.quizTimeSec == nil then
			st.quizTimeSec = 0
		end
	end
	return st
end

local function emptyStage(): StageData
	return {
		quizSolved     = {},
		cutscenes      = {},
		questPhase     = 0,
		extraTrash     = 0,
		cleanedObjects = {},

		quizScore   = 0,
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
-- ★ API: 퀴즈 점수/시간 기록
-----------------------------------------------------
function M.SetQuizResult(key: string, stage: number, score: number, timeSec: number)
	local sess = ensureSession(key)
	local st = ensureStage(sess, stage)

	local nScore   = tonumber(score)   or 0
	local nTimeSec = tonumber(timeSec) or 0

	st.quizScore   = math.max(0, nScore)
	st.quizTimeSec = math.max(0, nTimeSec)

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

	-- 옛 데이터 보정
	if st.quizScore == nil then
		st.quizScore = 0
	end
	if st.quizTimeSec == nil then
		st.quizTimeSec = 0
	end

	return st
end

-----------------------------------------------------
-- Stage3 전용 (Player 기반)
-----------------------------------------------------
function M.GetStage3State(plr: Player): StageData
	local key = keyFromPlayer(plr)
	if not key then
		return emptyStage()
	end
	return M.GetStageProgress(key, STAGE3)
end

function M.SetQuestState(plr: Player, phase: number, extra: number)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.SetQuestPhase(key, STAGE3, phase)
	M.SetExtraTrash(key, STAGE3, extra)
end

function M.SetCutsceneFlag(plr: Player, flag: string)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.MarkCutscenePlayed(key, STAGE3, flag)
end

-- ★ 필요하면 StageQuizResultService 쪽에서 이 함수를 호출해서
--   Stage3의 총 점수/시간을 DataStore에 같이 남길 수 있음.
function M.SetQuizResultForStage3(plr: Player, score: number, timeSec: number)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.SetQuizResult(key, STAGE3, score, timeSec)
end

return M
