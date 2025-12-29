-- ServerScriptService/Modules/StageMultiResultStore.lua
--!strict
-- 여러 스테이지(1~5)의 퀴즈 결과를
-- "입장코드(joinCode)" 단위로 DataStore에 저장/조회하는 모듈

local DataStoreService = game:GetService("DataStoreService")

local M = {}

M.STAGE_COUNT = 5
M.DATASTORE_NAME = "StageMultiResult_v1"

local store = DataStoreService:GetDataStore(M.DATASTORE_NAME)

export type StageResult = {
	score: number,
	timeSec: number,
}

export type PlayerResult = {
	name: string,
	stages: {[number]: StageResult},
	totalScore: number,
	totalTimeSec: number,
}

export type SessionData = {
	players: {[string]: PlayerResult}, -- key = tostring(userId)
	stageCount: number,
	updatedAt: number,
}

----------------------------------------------------------------
-- 내부 유틸
----------------------------------------------------------------
local function asNumber(v: any, default: number): number
	if typeof(v) == "number" and v == v then
		return v
	end
	return default
end

local function sessionKey(joinCode: string): string
	return string.format("SESSION_%s", tostring(joinCode))
end

----------------------------------------------------------------
-- 스테이지 결과 저장
----------------------------------------------------------------
function M.SaveStageResult(joinCode: string, stageIndex: number, player: Player, score: number, timeSec: number)
	if not joinCode or joinCode == "" then
		warn("[StageMultiResultStore] joinCode is empty, skip save")
		return
	end
	if stageIndex < 1 or stageIndex > M.STAGE_COUNT then
		warn("[StageMultiResultStore] invalid stageIndex:", stageIndex)
		return
	end
	if not player or player.UserId <= 0 then
		return
	end

	local key = sessionKey(joinCode)
	local userIdStr = tostring(player.UserId)

	local nScore   = asNumber(score, 0)
	local nTimeSec = asNumber(timeSec, 0)
	if nScore < 0 then nScore = 0 end
	if nTimeSec < 0 then nTimeSec = 0 end

	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old: SessionData?)
			old = old or {
				players = {},
				stageCount = M.STAGE_COUNT,
				updatedAt = 0,
			}

			old.players = old.players or {}

			local p: PlayerResult = old.players[userIdStr] or {
				name = player.Name,
				stages = {},
				totalScore = 0,
				totalTimeSec = 0,
			}

			-- 스테이지별 점수/시간 기록
			p.stages[stageIndex] = {
				score = nScore,
				timeSec = nTimeSec,
			}

			-- 총합 다시 계산
			local totalScore = 0
			local totalTimeSec = 0
			for i = 1, M.STAGE_COUNT do
				local s = p.stages[i]
				if s then
					totalScore += asNumber(s.score, 0)
					totalTimeSec += asNumber(s.timeSec, 0)
				end
			end
			p.totalScore = totalScore
			p.totalTimeSec = totalTimeSec

			-- 이름 최신화
			p.name = player.Name

			old.players[userIdStr] = p
			old.updatedAt = os.time()

			return old
		end)
	end)

	if not ok then
		warn("[StageMultiResultStore] SaveStageResult FAILED:", err)
	else
		print(string.format(
			"[StageMultiResultStore] Saved stage result (code=%s, stage=%d, user=%s, score=%d, time=%ds)",
			tostring(joinCode), stageIndex, player.Name, nScore, nTimeSec
			))
	end
end

----------------------------------------------------------------
-- 세션(joinCode) 전체 결과 조회
----------------------------------------------------------------
function M.GetSessionResult(joinCode: string): ({[string]: any})?
	if not joinCode or joinCode == "" then
		return nil
	end

	local key = sessionKey(joinCode)

	local ok, data = pcall(function()
		return store:GetAsync(key)
	end)

	if not ok then
		warn("[StageMultiResultStore] GetSessionResult FAILED:", data)
		return nil
	end
	if not data or not data.players then
		return nil
	end

	local resultList = {}

	for userIdStr, p in pairs(data.players) do
		table.insert(resultList, {
			userId = tonumber(userIdStr),
			name = p.name or "Player",
			totalScore = asNumber(p.totalScore, 0),
			totalTimeSec = asNumber(p.totalTimeSec, 0),
			stages = p.stages or {},
		})
	end

	table.sort(resultList, function(a, b)
		if a.totalScore ~= b.totalScore then
			return a.totalScore > b.totalScore -- 높은 점수 우선
		end
		return a.totalTimeSec < b.totalTimeSec -- 점수 같으면 더 빠른 시간 우선
	end)

	return resultList
end

----------------------------------------------------------------
-- ★ 한 플레이어의 결과만 삭제
--   joinCode: 세션 코드
--   userId  : 삭제할 유저 ID
----------------------------------------------------------------
function M.ClearPlayerResult(joinCode: string, userId: number)
	if not joinCode or joinCode == "" then
		return
	end
	if typeof(userId) ~= "number" or userId <= 0 then
		return
	end

	local key = sessionKey(joinCode)
	local userIdStr = tostring(userId)

	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old: SessionData?)
			if not old or not old.players then
				return old
			end

			-- 해당 플레이어만 제거
			old.players[userIdStr] = nil

			-- 아무도 안 남으면 전체 세션 삭제(키 제거)
			local hasAny = false
			for _, _ in pairs(old.players) do
				hasAny = true
				break
			end
			if not hasAny then
				print("[StageMultiResultStore] ClearPlayerResult: last player removed, deleting session key:", joinCode)
				return nil -- UpdateAsync에서 nil 반환하면 해당 키 Remove와 동일
			end

			old.updatedAt = os.time()
			return old
		end)
	end)

	if not ok then
		warn("[StageMultiResultStore] ClearPlayerResult FAILED:", err)
	else
		print(string.format(
			"[StageMultiResultStore] Cleared player result (code=%s, userId=%d)",
			tostring(joinCode), userId
			))
	end
end

----------------------------------------------------------------
-- 세션(joinCode) 전체 결과 삭제
----------------------------------------------------------------
function M.ClearSessionResult(joinCode: string)
	if not joinCode or joinCode == "" then
		return
	end

	local key = sessionKey(joinCode)

	local ok, err = pcall(function()
		store:RemoveAsync(key)
	end)

	if not ok then
		warn("[StageMultiResultStore] ClearSessionResult FAILED:", err)
	else
		print("[StageMultiResultStore] Cleared session result for joinCode:", joinCode)
	end
end

return M
