-- ServerScriptService/FinalJumpEnter.server.lua
--!strict
-- Stage5(FinalZone) 단일 서버 전제:
-- 1) 전원 완주(선생님 제외, 허브 퀴즈 시작 시 저장한 인원수 기준) -> 즉시 QuestUI 숨김 -> 즉시 컷씬 시작 -> (딜레이 후) Hub 텔레포트
-- 2) 선생님 종료 -> 즉시 QuestUI 숨김 -> 즉시 컷씬 시작 -> (딜레이 후) Hub 텔레포트

local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ServerScriptService= game:GetService("ServerScriptService")
local TeleportService    = game:GetService("TeleportService")

local Roles = require(RS:WaitForChild("Modules"):WaitForChild("Roles"))
local sessionResume = require(script.Parent:WaitForChild("Modules"):WaitForChild("SessionResume"))
local hubStartState = require(script.Parent:WaitForChild("Modules"):WaitForChild("HubStartState"))

----------------------------------------------------------------
-- 설정
----------------------------------------------------------------
-- ✅ 허브에서 퀴즈 시작 때 저장했던 stage 값
local QUIZ_START_STAGE_INDEX = 1

-- ✅ 컷씬 길이(대략 22초) + 여유
local TELEPORT_DELAY_SEC = 25.0

-- ✅ Hub PlaceId로 바꿔줘
local HUB_PLACE_ID = 120816172838238

-- 텔레포트 이유(원하면 TeleportData로 같이 전달)
local TELEPORT_REASON = "final_zone"

-- 중복 시작 방지 락 (세션 단위)
local LOCK_TTL_SEC  = 60 * 10
local StartLockMap  = MemoryStoreService:GetHashMap("FinalSequenceLock_v2")

----------------------------------------------------------------
-- ✅ 인원수 저장소 모듈
----------------------------------------------------------------
local QuizStartCountStore = require(ServerScriptService.Modules:WaitForChild("QuizStartCountStore"))

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

-- 학생들이 “완주자 존 도착” 시 쏘는 이벤트
local RE_FinalJumpEnter = Remotes:FindFirstChild("FinalJump_Enter")
if not RE_FinalJumpEnter then
	RE_FinalJumpEnter = Instance.new("RemoteEvent")
	RE_FinalJumpEnter.Name = "FinalJump_Enter"
	RE_FinalJumpEnter.Parent = Remotes
end

-- 모든 클라가 받는 “컷씬 시작” 이벤트
local RE_PlayCutscene = Remotes:FindFirstChild("FinalJump_PlayCutscene")
if not RE_PlayCutscene then
	RE_PlayCutscene = Instance.new("RemoteEvent")
	RE_PlayCutscene.Name = "FinalJump_PlayCutscene"
	RE_PlayCutscene.Parent = Remotes
end

-- ✅ 전원 도착/종료 시 QuestUI 숨김 이벤트
local RE_AllArrived = Remotes:FindFirstChild("FinalJump_AllArrived")
if not RE_AllArrived then
	RE_AllArrived = Instance.new("RemoteEvent")
	RE_AllArrived.Name = "FinalJump_AllArrived"
	RE_AllArrived.Parent = Remotes
end

-- 선생님 “종료 버튼” 전용
local RE_TeacherEnd = Remotes:FindFirstChild("FinalJump_TeacherEnd")
if not RE_TeacherEnd then
	RE_TeacherEnd = Instance.new("RemoteEvent")
	RE_TeacherEnd.Name = "FinalJump_TeacherEnd"
	RE_TeacherEnd.Parent = Remotes
end

----------------------------------------------------------------
-- 유틸
----------------------------------------------------------------
local function isTeacher(plr: Player): boolean
        if RunService:IsStudio() then return true end
        local role = plr:GetAttribute("userRole")
        if Roles.isTeacherRole(role) then
                return true
        end

        local isTeacherAttr = plr:GetAttribute("isTeacher")
        if typeof(isTeacherAttr) == "boolean" then
                return isTeacherAttr
        end

        return false
end

local function getSessionIdFromPlayer(plr: Player): string?
	local sid = plr:GetAttribute("sessionId")
	if typeof(sid) == "string" and #sid > 0 then
		return sid
	end
	return nil
end

local function inferSessionIdFromServer(): string?
	for _, p in ipairs(Players:GetPlayers()) do
		local sid = getSessionIdFromPlayer(p)
		if sid then return sid end
	end
	return nil
end

----------------------------------------------------------------
-- ✅ 저장해둔 "기대 인원" 로드/캐시
----------------------------------------------------------------
local expectedCountBySession: {[string]: number} = {}
local expectedLoadedBySession: {[string]: boolean} = {}

local function loadExpectedCount(sessionId: string): number?
	if expectedLoadedBySession[sessionId] then
		return expectedCountBySession[sessionId]
	end
	expectedLoadedBySession[sessionId] = true

	local ok, rec, err = QuizStartCountStore.Get(sessionId, QUIZ_START_STAGE_INDEX, 1)
	if not ok then
		warn("[FinalJump] Failed to load expected count:", sessionId, err)
		return nil
	end
	if rec == nil then
		warn("[FinalJump] No expected count saved for session:", sessionId, "stage=", QUIZ_START_STAGE_INDEX)
		return nil
	end

	local n = tonumber((rec :: any).count)
	if not n or n < 0 then
		warn("[FinalJump] Bad expected count data:", sessionId, "value=", (rec :: any).count)
		return nil
	end

	expectedCountBySession[sessionId] = math.floor(n)
	print(("[FinalJump] Loaded expected student count=%d sid=%s stage=%d"):format(expectedCountBySession[sessionId], sessionId, QUIZ_START_STAGE_INDEX))
	return expectedCountBySession[sessionId]
end

local function getExpected(sessionId: string): number?
	local n = loadExpectedCount(sessionId)
	if typeof(n) == "number" and n >= 0 then
		return n
	end
	return nil
end

----------------------------------------------------------------
-- “세션 최종 시퀀스” 시작(세션당 1회만)
----------------------------------------------------------------
local function tryLock(sessionId: string): boolean
	local key = "lock:" .. sessionId

	local okGet, existing = pcall(function()
		return StartLockMap:GetAsync(key)
	end)
	if okGet and existing ~= nil then
		return false
	end

	local okSet = pcall(function()
		StartLockMap:SetAsync(key, true, LOCK_TTL_SEC)
	end)
	return okSet
end

local function teleportAllToHubLocal(sessionId: string)
	task.delay(TELEPORT_DELAY_SEC, function()
		local plrs = Players:GetPlayers()
		if #plrs == 0 then return end

		local ok, err = pcall(function()
			TeleportService:TeleportAsync(HUB_PLACE_ID, plrs, {
				sessionId = sessionId,
				reason = TELEPORT_REASON,
				device = "server",
				delaySec = TELEPORT_DELAY_SEC,
			})
		end)

		if not ok then
			warn("[FinalJump] TeleportAsync failed:", err)
		end
	end)
end

local function startFinalSequence(sessionId: string, source: string)
	if not tryLock(sessionId) then return end
	print(("[FinalJump] START FINAL SEQUENCE sid=%s source=%s"):format(sessionId, source))
	
	sessionResume.ClearSession(sessionId)
	hubStartState.Clear(sessionId)
	
	-- ✅ 즉시 QuestUI 숨김
	RE_AllArrived:FireAllClients()

	-- ✅ 즉시 컷씬 시작
	RE_PlayCutscene:FireAllClients("Play")

	-- ✅ 딜레이 후 Hub 텔레포트(이 서버에서 바로)
	teleportAllToHubLocal(sessionId)

	-- 정리(원하면 남겨두기)

end

----------------------------------------------------------------
-- 1) 전원 완주(entered 집계)
-- ✅ 기준: "허브에서 저장한 기대 인원수(학생 수)"
----------------------------------------------------------------
local entered: {[Player]: boolean} = {}
local enterCount = 0 -- 학생만 카운트
local allEnteredFired = false
local currentSessionId: string? = nil

local function printCount()
	if not currentSessionId then
		print(("[FinalJump] 인원(학생 기준): %d / ? (expected)"):format(enterCount))
		return
	end
	local expected = getExpected(currentSessionId)
	if expected then
		print(("[FinalJump] 인원(학생 기준): %d / %d (expected)"):format(enterCount, expected))
	else
		print(("[FinalJump] 인원(학생 기준): %d / ? (expected missing)"):format(enterCount))
	end
end

local function tryAllFinishedStart(sessionId: string)
	if allEnteredFired then return end
	currentSessionId = sessionId

	local expectedStudents = getExpected(sessionId)
	if not expectedStudents then
		return
	end

	if enterCount >= expectedStudents then
		allEnteredFired = true
		print("[FinalJump] (선생님 제외) 전원 완주(저장 인원 기준) -> FINAL SEQUENCE (IMMEDIATE CUTSCENE)")
		startFinalSequence(sessionId, "all_finished")
	end
end

RE_FinalJumpEnter.OnServerEvent:Connect(function(plr: Player, payload: any)
	payload = typeof(payload) == "table" and payload or {}

	-- 선생님은 완주 카운트 제외
        if not isTeacher(plr) then
                if not entered[plr] then
                        entered[plr] = true
                        enterCount += 1
		end
	end

	print(("[FinalJump] %s 완주 존 도착"):format(plr.Name))

	local sid = getSessionIdFromPlayer(plr) or inferSessionIdFromServer()
	if not sid then
		warn("[FinalJump] sessionId missing -> cannot evaluate expected count")
		return
	end

	-- ✅ 들어온 순간 expectedCount 로드(없으면 전원판정 불가)
	loadExpectedCount(sid)

        printCount()
        tryAllFinishedStart(sid)
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	if entered[plr] then
		entered[plr] = nil
		enterCount -= 1
		printCount()
	end
end)

----------------------------------------------------------------
-- 2) 선생님 종료 트리거
----------------------------------------------------------------
RE_TeacherEnd.OnServerEvent:Connect(function(plr: Player, payload: any)
	payload = typeof(payload) == "table" and payload or {}

	if not plr or not plr.Parent then return end
	if not isTeacher(plr) then
		warn("[FinalJump] Non-teacher tried to end:", plr.Name, plr.UserId)
		return
	end

	local sid = getSessionIdFromPlayer(plr) or inferSessionIdFromServer()
	if not sid then
		warn("[FinalJump] Teacher end: sessionId missing -> cannot start")
		return
	end

	currentSessionId = sid
	loadExpectedCount(sid)

	print("[FinalJump] Teacher END -> FINAL SEQUENCE (IMMEDIATE CUTSCENE)")
	startFinalSequence(sid, "teacher_end")
end)

print("[FinalJump] READY (Single-server): expectedCount via QuizStartCountStore -> when enterCount reaches expected -> immediately hideQuest + cutscene + teleport after delay")
