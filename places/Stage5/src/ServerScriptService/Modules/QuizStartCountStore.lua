--!strict
-- QuizStartCountStore
-- 선생님이 "퀴즈 시작" 눌렀을 때
-- 같은 서버(현재 플레이스/JobId)에 있는 플레이어들 중 "선생님 제외" 인원 수를 계산해서 저장
-- + 정리(Clear) 기능 제공

local DataStoreService = game:GetService("DataStoreService")
local DS = DataStoreService:GetDataStore("QuizStartCount_v1")

export type CountRecord = {
	sessionId: string,
	stage: number,
	placeId: number,
	jobId: string,
	savedAt: number,
	teacherUserId: number,
	count: number, -- 선생님 제외
}

local M = {}

local function makeKey(sessionId: string, stage: number): string
	return ("SID:%s|STAGE:%d|K:QuizStartCount"):format(sessionId, stage)
end

local function withRetries<T>(fn: () -> T, retries: number): (boolean, any)
	local lastErr: any = nil
	for attempt = 1, retries + 1 do
		local ok, res = pcall(fn)
		if ok then return true, res end
		lastErr = res
		task.wait(0.15 * attempt)
	end
	return false, lastErr
end

local function clampRetries(retries: number?): number
	if typeof(retries) ~= "number" then return 3 end
	return math.clamp(math.floor(retries), 0, 10)
end

-- ✅ 모듈 내부에서 카운트 계산
function M.CountExcludingTeacher(players: {Player}, teacherUserId: number): number
	local n = 0
	for _, p in ipairs(players) do
		if p.UserId ~= teacherUserId then
			n += 1
		end
	end
	return n
end

-- ✅ 모듈 내부에서 저장(기본 overwrite=true)
function M.SaveCount(
	sessionId: string,
	stage: number,
	teacherUserId: number,
	count: number,
	overwrite: boolean?,
	retries: number?
): (boolean, string?)
	if typeof(sessionId) ~= "string" or sessionId == "" then
		return false, "missing_sessionId"
	end
	if typeof(stage) ~= "number" then
		return false, "missing_stage"
	end
	if typeof(count) ~= "number" or count < 0 then
		return false, "bad_count"
	end

	local k = makeKey(sessionId, stage)
	local r = clampRetries(retries)

	local record: CountRecord = {
		sessionId = sessionId,
		stage = stage,
		placeId = game.PlaceId,
		jobId = game.JobId,
		savedAt = os.time(),
		teacherUserId = teacherUserId,
		count = math.floor(count),
	}

	local ok, err = withRetries(function()
		DS:UpdateAsync(k, function(old)
			if old ~= nil and not overwrite then
				return old
			end
			return record
		end)
		return true
	end, r)

	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

-- ✅ 서버는 이것만 부르면 됨: "카운트 계산 + 저장" 원샷
function M.SaveFromPlayers(
	sessionId: string,
	stage: number,
	teacherUserId: number,
	players: {Player},
	overwrite: boolean?,
	retries: number?
): (boolean, string?, number?)
	local count = M.CountExcludingTeacher(players, teacherUserId)
	local ok, err = M.SaveCount(sessionId, stage, teacherUserId, count, overwrite, retries)
	return ok, err, count
end

-- ✅ 조회
function M.Get(sessionId: string, stage: number, retries: number?): (boolean, CountRecord?, string?)
	if typeof(sessionId) ~= "string" or sessionId == "" then
		return false, nil, "missing_sessionId"
	end
	if typeof(stage) ~= "number" then
		return false, nil, "missing_stage"
	end

	local k = makeKey(sessionId, stage)
	local r = clampRetries(retries)

	local ok, resOrErr = withRetries(function()
		return DS:GetAsync(k)
	end, r)

	if not ok then
		return false, nil, tostring(resOrErr)
	end

	return true, resOrErr, nil
end

-- ✅ 숫자만 편하게 가져오기 (없으면 nil)
function M.GetCount(sessionId: string, stage: number, retries: number?): (boolean, number?, string?)
	local ok, rec, err = M.Get(sessionId, stage, retries)
	if not ok then
		return false, nil, err
	end
	if rec == nil then
		return true, nil, nil
	end
	return true, tonumber(rec.count), nil
end

-- ✅ 정리(삭제): 특정 stage 하나만 삭제
function M.Clear(sessionId: string, stage: number, retries: number?): (boolean, string?)
	if typeof(sessionId) ~= "string" or sessionId == "" then
		return false, "missing_sessionId"
	end
	if typeof(stage) ~= "number" then
		return false, "missing_stage"
	end

	local k = makeKey(sessionId, stage)
	local r = clampRetries(retries)

	-- DataStore는 "nil 저장"으로 삭제하는 게 가장 호환 좋음
	local ok, err = withRetries(function()
		DS:RemoveAsync(k)
		return true
	end, r)

	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

-- ✅ 정리(삭제): 여러 stage를 한 번에 삭제
-- 예) ClearAllStages(sid, {0,1,2,3,4,5})
function M.ClearAllStages(sessionId: string, stages: {number}, retries: number?): (boolean, string?)
	if typeof(sessionId) ~= "string" or sessionId == "" then
		return false, "missing_sessionId"
	end
	local r = clampRetries(retries)

	for _, st in ipairs(stages) do
		if typeof(st) == "number" then
			local k = makeKey(sessionId, st)
			local ok, err = withRetries(function()
				DS:RemoveAsync(k)
				return true
			end, r)
			if not ok then
				return false, ("clear_failed_stage_%d:%s"):format(st, tostring(err))
			end
		end
	end

	return true, nil
end

-- ✅ 디버그 출력(선택)
function M.DebugPrint(sessionId: string, stage: number, retries: number?)
	local ok, rec, err = M.Get(sessionId, stage, retries)
	if not ok then
		warn("[QuizStartCountStore] DebugPrint Get failed:", err)
		return
	end
	if rec == nil then
		print(("[QuizStartCountStore] (empty) sid=%s stage=%d"):format(sessionId, stage))
		return
	end
	print(("[QuizStartCountStore] sid=%s stage=%d count=%d savedAt=%d placeId=%d jobId=%s"):format(
		rec.sessionId,
		rec.stage,
		rec.count,
		rec.savedAt,
		rec.placeId,
		rec.jobId
		))
end

return M
