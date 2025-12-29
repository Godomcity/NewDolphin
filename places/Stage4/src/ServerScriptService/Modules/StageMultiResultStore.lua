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
-- joinCode: 입장코드(세션 코드)
-- stageIndex: 현재 스테이지 번호 (1~5)
-- player: Player
-- score: 해당 스테이지 점수
-- timeSec: 해당 스테이지 시간(초)
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

			-- 이름 최신화(혹시 바뀌었을 수도 있으니)
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
-- 반환: { players = { {userId, name, totalScore, totalTimeSec, stages={...}}, ... } }
-- 정렬: totalScore 내림차순, 동점이면 totalTimeSec 오름차순
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

return M
