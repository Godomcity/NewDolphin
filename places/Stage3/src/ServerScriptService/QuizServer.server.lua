-- ServerScriptService/QuizServer.server.lua
-- 목적:
-- 1) 서버가 외부 퀴즈 API를 GET/POST 해서 클라에 전달
-- 2) "입장 시 미리 GET(워밍업)" + singleflight(동시 호출 1번만) + 캐시로 안정화
--
-- 필수:
-- Game Settings > Security > Allow HTTP Requests = ON
--
-- 배치:
-- 1) 이 스크립트: ServerScriptService/QuizServer.server.lua
-- 2) QuizApi 모듈(토큰 포함): ServerScriptService/Modules/QuizApi.lua  (아래 require 경로 맞춰줘)
-- 3) ReplicatedStorage/Remotes 는 서버가 자동 생성

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

-- ⚠️ 토큰 노출 방지: QuizApi 모듈은 반드시 ServerScriptService 아래에 두기
-- 예: ServerScriptService/Modules/QuizApi.lua
local QuizApi = require(SSS:WaitForChild("Modules"):WaitForChild("QuizApi"))

-- ===== Remotes (서버가 생성/소유) =====
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local RF_Get = Remotes:FindFirstChild("RF_Quiz_GetQuestion")
if not RF_Get then
	RF_Get = Instance.new("RemoteFunction")
	RF_Get.Name = "RF_Quiz_GetQuestion"
	RF_Get.Parent = Remotes
end

local RF_Submit = Remotes:FindFirstChild("RF_Quiz_CheckAnswer")
if not RF_Submit then
	RF_Submit = Instance.new("RemoteFunction")
	RF_Submit.Name = "RF_Quiz_CheckAnswer"
	RF_Submit.Parent = Remotes
end

-- ===== Singleflight 캐시 =====
-- 동시 요청이 들어와도 GET은 1번만 날리고, 나머지는 결과를 기다렸다가 동일 응답을 받음
local cachedDto: any? = nil
local cachedAt = 0
local CACHE_TTL = 15 -- 초 (원하면 조절)

local inFlight = false
local waiters: { BindableEvent } = {}

local function finishAll(result)
	for _, ev in ipairs(waiters) do
		ev:Fire(result)
		ev:Destroy()
	end
	waiters = {}
end

local function getQuestionShared()
	-- [QUIZ][CACHE] 캐시가 살아있으면 즉시 반환
	if cachedDto and (os.clock() - cachedAt) < CACHE_TTL then
		return { ok = true, data = cachedDto, source = "cache" }
	end

	-- [QUIZ][SINGLEFLIGHT] 이미 누가 GET 중이면 기다렸다가 같은 결과 받기
	if inFlight then
		local ev = Instance.new("BindableEvent")
		table.insert(waiters, ev)
		local result = ev.Event:Wait()
		return result
	end

	inFlight = true

	-- [QUIZ][RETRY] 3회 재시도 (일시 장애/레이트 대비)
	local lastErr = nil
	for i = 1, 3 do
		local dto, err = QuizApi.GetQuestionWithErr()
		if dto then
			cachedDto = dto
			cachedAt = os.clock()
			inFlight = false

			local okRes = { ok = true, data = dto, source = "fresh" }
			finishAll(okRes)
			return okRes
		end
		lastErr = err
		task.wait(0.5 * i)
	end

	inFlight = false
	local failRes = { ok = false, error = "get_failed", last = lastErr }
	finishAll(failRes)
	return failRes
end

-- ===== 입장 시 미리 GET(워밍업) =====
-- 첫 상호작용 때 "question not ready" / 지연을 줄이는 용도
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		local res = getQuestionShared()
		if not res.ok then
			warn(("[QuizServer] warmup failed for %s: %s"):format(player.Name, tostring(res.error)))
		end
	end)
end)

-- ===== 서버 시작 시도 워밍업(선택) =====
task.spawn(function()
	local res = getQuestionShared()
	if not res.ok then
		warn("[QuizServer] boot warmup failed:", res.error, res.last and res.last.msg)
	end
end)

-- ===== RemoteFunction: 문제 가져오기 =====
-- 클라가 solvedList를 보내도, 현재는 "한 문제"만 쓰는 구조라 그냥 shared 반환
-- (나중에 solvedList 기반으로 다음 문제를 고르는 로직으로 확장 가능)
RF_Get.OnServerInvoke = function(player: Player, solvedList: any)
	-- [QUIZ][GET] 서버에서 안정화된 DTO 반환
	return getQuestionShared()
end

-- ===== RemoteFunction: 정답 제출하기 =====
-- 클라 호출: InvokeServer(quizChoiceId, quizStorageId)
RF_Submit.OnServerInvoke = function(player: Player, quizChoiceId: any, quizStorageId: any)
	local cid = tonumber(quizChoiceId) or 0
	local sid = tostring(quizStorageId or "")

	if cid == 0 or sid == "" then
		return { ok = false, error = "bad_payload" }
	end

	-- [QUIZ][SUBMIT] POST 제출
	local result, err = QuizApi.SubmitAnswerWithErr(sid, cid)
	if not result then
		return { ok = false, error = "submit_failed", last = err }
	end

	-- 클라가 쓰기 쉬운 형태로 반환
	return {
		ok = true,
		correct = (result.isCorrect == true),
		feedback = result.feedback,
		explanation = result.explanation,
		earnedScore = result.earnedScore,
		maxScore = result.maxScore,
		gradingStatus = result.gradingStatus,
		attemptCount = result.attemptCount,
	}
end

print("[QuizServer] READY (singleflight + warmup)")
