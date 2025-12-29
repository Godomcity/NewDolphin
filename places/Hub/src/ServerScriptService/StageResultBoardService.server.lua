-- ServerScriptService/StageResultBoardService.lua
--!strict
-- 허브에서 "세션 전체 결과(모든 스테이지 합산)" 조회 + 선생님 X버튼 → 모두 결과창 닫기 + 세션 데이터 삭제

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StageResultStore   = require(ServerScriptService.Modules:WaitForChild("StageMultiResultStore"))
local SessionResume      = require(ServerScriptService.Modules:WaitForChild("SessionResume"))
local SessionProgress    = require(ServerScriptService.Modules:WaitForChild("SessionProgress"))

-- ✅ 추가: "퀴즈 시작 인원수" 저장 정리용
local QuizStartCountStore = require(ServerScriptService.Modules:WaitForChild("QuizStartCountStore"))

local Permissions = require(ServerScriptService.Modules:WaitForChild("Permissions"))

----------------------------------------------------------------
-- Remotes 준비
----------------------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

-- 클라 → 서버: "이 세션의 전체 결과(모든 스테이지 합산) 주세요"
local RF_GetStageResults = Remotes:FindFirstChild("RF_GetStageResults")
if not RF_GetStageResults then
	RF_GetStageResults = Instance.new("RemoteFunction")
	RF_GetStageResults.Name = "RF_GetStageResults"
	RF_GetStageResults.Parent = Remotes
end

-- 클라(선생님) → 서버: "모두 결과창 닫아줘"
-- 서버 → 클라(전체): "결과창 닫아"
local RE_Result_CloseAll = Remotes:FindFirstChild("RE_Result_CloseAll")
if not RE_Result_CloseAll then
	RE_Result_CloseAll = Instance.new("RemoteEvent")
	RE_Result_CloseAll.Name = "RE_Result_CloseAll"
	RE_Result_CloseAll.Parent = Remotes
end

----------------------------------------------------------------
-- 유틸
----------------------------------------------------------------
local function safeNumber(v:any): number
	if typeof(v) == "number" then
		return v
	end
	local n = tonumber(v)
	return n or 0
end

local function safeString(v:any): string
	if typeof(v) == "string" then
		return v
	end
	return tostring(v or "")
end

local function getJoinCodeFromSessionId(sessionId: string?): string?
	if typeof(sessionId) ~= "string" or #sessionId == 0 then
		return nil
	end

	local joinCode = sessionId
	if not string.find(joinCode, "SID-", 1, true) then
		joinCode = "SID-" .. joinCode
	end
	return joinCode
end

----------------------------------------------------------------
-- 세션 데이터 삭제 유틸
--  - StageMultiResultStore: 해당 세션 결과 삭제
--  - SessionProgress: sessionId + userId 조합으로 플레이어별 삭제
--  - SessionResume: 세션에 속한 플레이어들의 마지막 위치 정보 삭제
--  - ✅ QuizStartCountStore: 퀴즈 시작 인원수 삭제
----------------------------------------------------------------
local _sessionCleared: {[string]: boolean} = {}

local function clearSessionData(sessionId: string)
	if _sessionCleared[sessionId] then
		-- 이미 이 서버에서 한 번 정리된 세션이면 재호출 방지
		return
	end
	_sessionCleared[sessionId] = true

	local joinCode = getJoinCodeFromSessionId(sessionId)

	-- 1) StageMultiResultStore 결과 삭제
	if joinCode then
		local okClear, errClear = pcall(function()
			StageResultStore.ClearSessionResult(joinCode)
		end)

		if not okClear then
			warn("[StageResultBoard] failed to clear StageResultStore for joinCode:", joinCode, errClear)
		else
			print("[StageResultBoard] StageResultStore cleared for joinCode:", joinCode)
		end
	end

	-- ✅ 1.5) QuizStartCountStore 정리(세션의 퀴즈 시작 인원수)
	-- 저장할 때 stage를 0으로 썼든, stageIndex(1~)로 썼든 둘 다 커버하려고 0~5 다 지움
	do
		local okQ, errQ = pcall(function()
			-- 너가 모듈에 ClearAllStages를 넣은 버전 기준
			if QuizStartCountStore.ClearAllStages then
				QuizStartCountStore.ClearAllStages(sessionId, {0, 1, 2, 3, 4, 5}, 3)
			else
				-- 혹시 ClearAllStages가 없으면 최소한 0~5 개별 삭제
				for _, st in ipairs({0, 1, 2, 3, 4, 5}) do
					QuizStartCountStore.Clear(sessionId, st, 3)
				end
			end
		end)

		if not okQ then
			warn("[StageResultBoard] QuizStartCountStore clear failed:", errQ)
		else
			print("[StageResultBoard] QuizStartCountStore cleared for sessionId:", sessionId)
		end
	end

        -- 2) 이 세션에 속한 모든 플레이어 데이터 삭제
        --    플레이어가 Hub에 없더라도 세션 ID만으로 일괄 정리되도록 서버 단에서 한 번만 호출
        do
                -- SessionResume 삭제 (userId 기준)
                local okResume, errResume = pcall(function()
                        SessionResume.ClearSession(sessionId)
                end)
                if not okResume then
                        warn("[StageResultBoard] SessionResume.ClearSession failed for", sessionId, errResume)
                else
                        print("[StageResultBoard] SessionResume cleared for session", sessionId)
                end

                -- SessionProgress 삭제 (sessionId + userId 기준)
                local okProg, errProg = pcall(function()
                        if SessionProgress.ClearSession then
                                SessionProgress.ClearSession(sessionId)
                        else
                                -- 혹시 ClearForSessionUser가 없고 ClearForPlayer만 있다면 대비
                                for _, plr in ipairs(Players:GetPlayers()) do
                                        if plr:GetAttribute("sessionId") == sessionId then
                                                SessionProgress.ClearForPlayer(plr)
                                        end
                                end
                        end
                end)
                if not okProg then
                        warn("[StageResultBoard] SessionProgress.ClearSession failed for", sessionId, errProg)
                else
                        print("[StageResultBoard] SessionProgress cleared for session", sessionId)
                end
        end
end

----------------------------------------------------------------
-- 결과 요청 처리
-- 반환 형태:
-- { ok=true, results = { {userId, name, totalScore, totalTimeSec}, ... } }
----------------------------------------------------------------
(RF_GetStageResults :: RemoteFunction).OnServerInvoke = function(player: Player)
	local sidAttr = player:GetAttribute("sessionId")
	if typeof(sidAttr) ~= "string" or #sidAttr == 0 then
		warn("[StageResultBoard] player has no sessionId:", player.Name)
		return { ok = false, reason = "no_sessionId" }
	end

	-- ★ sessionId(ABCDEF12)를 저장에 쓰인 joinCode 형식(SID-ABCDEF12)로 변환
	local joinCode = getJoinCodeFromSessionId(sidAttr)
	if not joinCode then
		return { ok = false, reason = "invalid_sessionId" }
	end

	print(("[StageResultBoard] sessionId=%s, joinCode=%s"):format(sidAttr, joinCode))

	local rawList:any = nil
	local ok, err = pcall(function()
		rawList = StageResultStore.GetSessionResult(joinCode)
	end)

	if not ok then
		warn("[StageResultBoard] GetSessionResult error:", err)
		return { ok = false, reason = "store_error" }
	end

	if type(rawList) ~= "table" then
		rawList = {}
	end

	local norm:{any} = {}
	for _, row in ipairs(rawList) do
		table.insert(norm, {
			userId       = tonumber(row.userId),
			name         = tostring(row.name or "Player"),
			totalScore   = tonumber(row.totalScore or row.score) or 0,
			totalTimeSec = tonumber(row.totalTimeSec or row.timeSec) or 0,
		})
	end

	print(("[StageResultBoard] session %s result count = %d"):format(joinCode, #norm))

	return {
		ok      = true,
		results = norm,
	}
end

----------------------------------------------------------------
-- 선생님이 X 버튼 누르면
-- 1) 해당 세션의 StageMultiResultStore 결과 삭제
-- 2) 해당 세션의 모든 플레이어에 대해
--    - SessionProgress 진행도 삭제
--    - SessionResume 마지막 위치 정보 삭제
-- 3) 전체 클라에 "닫기" 브로드캐스트
-- 4) ✅ QuizStartCountStore 정리
----------------------------------------------------------------
RE_Result_CloseAll.OnServerEvent:Connect(function(player: Player)
	
	if not Permissions.requireTeacher(player) then
		return
	end

	-- 3) UI 닫기 브로드캐스트
	RE_Result_CloseAll:FireAllClients()

	local sidAttr = player:GetAttribute("sessionId")
	if typeof(sidAttr) ~= "string" or #sidAttr == 0 then
		warn("[StageResultBoard] teacher has no sessionId; cannot clear session data:", player.Name)
		RE_Result_CloseAll:FireAllClients()
		return
	end

	local sessionId = sidAttr
	local joinCode = getJoinCodeFromSessionId(sessionId)

	print(("[StageResultBoard] Teacher %s closed result for sessionId=%s, joinCode=%s")
		:format(player.Name, sessionId, tostring(joinCode)))

	-- ★ 여기서 세션 관련 데이터 전부 정리 (+ QuizStartCountStore 포함)
	clearSessionData(sessionId)
end)

print("[StageResultBoardService] READY (totalScore/totalTimeSec scoreboard + session clear)")
