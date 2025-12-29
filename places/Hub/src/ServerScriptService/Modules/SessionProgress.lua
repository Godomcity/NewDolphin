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

local STAGE5 = 5

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
			currentStage = 2,
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
-- ★ 세션 삭제 (캐시 + DataStore)
-----------------------------------------------------
local function removeSession(key: string)
	if not key or key == "" then
		return
	end

	_sessions[key] = nil

	local ok, err = pcall(function()
		DS:RemoveAsync(key)
	end)

	if not ok then
		warn("[SessionProgress] removeSession failed:", err)
	else
		print("[SessionProgress] removed session progress key:", key)
	end
end

-----------------------------------------------------
-- StageData 생성
-----------------------------------------------------
local function ensureStage(sess: SessionData, stage: number): StageData
	local st = sess.stages[stage]
	if not st then
		st = {
			quizSolved = {},
			cutscenes = {},
			questPhase = 0,
			extraTrash = 0,
			cleanedObjects = {},
		}
		sess.stages[stage] = st
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
	return st
end

-----------------------------------------------------
-- Stage5 전용 (Player 기반)
-----------------------------------------------------
function M.GetSTAGE5State(plr: Player): StageData
	local key = keyFromPlayer(plr)
	if not key then
		return emptyStage()
	end
	return M.GetStageProgress(key, STAGE5)
end

function M.SetQuestState(plr: Player, phase: number, extra: number)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.SetQuestPhase(key, STAGE5, phase)
	M.SetExtraTrash(key, STAGE5, extra)
end

function M.SetCutsceneFlag(plr: Player, flag: string)
	local key = keyFromPlayer(plr)
	if not key then return end
	M.MarkCutscenePlayed(key, STAGE5, flag)
end

-----------------------------------------------------
-- ★ 삭제용 API (세션 종료시 사용)
-----------------------------------------------------

-- progressKey를 알고 있을 때 직접 삭제
function M.ClearByKey(key: string)
	removeSession(key)
end

-- sessionId + userId 기준 삭제
function M.ClearForSessionUser(sessionId: string, userId: number)
	if typeof(sessionId) ~= "string" or sessionId == "" then
		return
	end
	if typeof(userId) ~= "number" or userId <= 0 then
		return
	end

	local key = buildKey(sessionId, userId)
	removeSession(key)
end

-- Player 기준 삭제 (Player Attribute에 sessionId 있어야 함)
function M.ClearForPlayer(plr: Player)
	local key = keyFromPlayer(plr)
	if not key then return end
	removeSession(key)
end

-----------------------------------------------------
-- 🔥 추가: 세션ID 기준 전체 삭제
-----------------------------------------------------
-- 같은 sessionId를 가진 모든 유저의 진행도 삭제
function M.ClearSession(sessionId: string)
	if typeof(sessionId) ~= "string" or sessionId == "" then
		warn("[SessionProgress] ClearSession called with invalid sessionId")
		return
	end

	warn("[SessionProgress] ClearSession start for sessionId =", sessionId)

	-- 키 포맷이 "sessionId:u<userId>" 이므로, prefix를 "sessionId:" 로 잡는다.
	local prefix = sessionId .. ":"

	local okPages, pagesOrErr = pcall(function()
		return DS:ListKeysAsync(prefix, 0)
	end)

	if not okPages then
		warn("[SessionProgress] ClearSession ListKeysAsync failed:", pagesOrErr)
		return
	end

	local pages = pagesOrErr
	local removedCount = 0

	while true do
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)

		if not okPage or not page then
			warn("[SessionProgress] ClearSession GetCurrentPage failed:", page)
			break
		end

		for _, keyInfo in ipairs(page) do
			local keyName = keyInfo.KeyName
			removeSession(keyName)
			removedCount += 1
		end

		if pages.IsFinished then
			break
		end

		local okNext, errNext = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not okNext then
			warn("[SessionProgress] ClearSession AdvanceToNextPageAsync failed:", errNext)
			break
		end
	end

	warn(("[SessionProgress] ClearSession done. sessionId=%s, removed=%d"):format(sessionId, removedCount))
end

-----------------------------------------------------
-- 🔁 (선택) 전체 초기화: 모든 세션 진행도 삭제
-----------------------------------------------------
function M.ClearAll()
	warn("[SessionProgress] ClearAll start")

	local okPages, pagesOrErr = pcall(function()
		-- prefix="" 로 전체 키
		return DS:ListKeysAsync("", 0)
	end)

	if not okPages then
		warn("[SessionProgress] ClearAll ListKeysAsync failed:", pagesOrErr)
		return
	end

	local pages = pagesOrErr
	local removedCount = 0

	while true do
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)

		if not okPage or not page then
			warn("[SessionProgress] ClearAll GetCurrentPage failed:", page)
			break
		end

		for _, keyInfo in ipairs(page) do
			local keyName = keyInfo.KeyName
			removeSession(keyName)
			removedCount += 1
		end

		if pages.IsFinished then
			break
		end

		local okNext, errNext = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not okNext then
			warn("[SessionProgress] ClearAll AdvanceToNextPageAsync failed:", errNext)
			break
		end
	end

	warn(("[SessionProgress] ClearAll done. removed=%d"):format(removedCount))
end

return M
