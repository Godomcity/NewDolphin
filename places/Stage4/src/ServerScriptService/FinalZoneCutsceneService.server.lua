-- ServerScriptService/FinalZoneEndOrchestrator.server.lua
--!strict
-- 통합 종료 오케스트레이터
--
-- A) FinalZone_EndRequest(기존):
--   1) 모든 서버에 FinalZone 컷씬 재생 브로드캐스트
--   2) 텔레포트 브로드캐스트는 "선생님 서버"에서 딱 1번만 발사 (delaySec로 컷씬 끝난 뒤 Hub)
--   reason = "final_zone_end"
--
-- B) Quiz_EndRequest(신규):
--   1) 모든 서버에 "정리+엔딩 컷씬" 브로드캐스트
--   2) 텔레포트 브로드캐스트는 "선생님 서버"에서 딱 1번만 발사 (delaySec 후 Hub)
--   reason = "quiz_end"

local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local RunService       = game:GetService("RunService")

local Roles = require(RS:WaitForChild("Modules"):WaitForChild("Roles"))
local sessionResume = require(script.Parent:WaitForChild("Modules"):WaitForChild("SessionResume"))
local hubStartState = require(script.Parent:WaitForChild("Modules"):WaitForChild("HubStartState"))
----------------------------------------------------------------
-- Remotes 보장
----------------------------------------------------------------
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

-- 서버 → 클라 : 컷씬 재생 (단방향)
local RE_PlayCutscene = Remotes:FindFirstChild("FinalJump_PlayCutscene") :: RemoteEvent?
if not RE_PlayCutscene then
	RE_PlayCutscene = Instance.new("RemoteEvent")
	RE_PlayCutscene.Name = "FinalJump_PlayCutscene"
	RE_PlayCutscene.Parent = Remotes
end

-- 클라(선생님) → 서버 : FinalZone 종료 요청(기존)
local RE_FinalEnd = Remotes:FindFirstChild("FinalZone_EndRequest") :: RemoteEvent?
if not RE_FinalEnd then
	RE_FinalEnd = Instance.new("RemoteEvent")
	RE_FinalEnd.Name = "FinalZone_EndRequest"
	RE_FinalEnd.Parent = Remotes
end

-- 클라(선생님) → 서버 : 퀴즈 종료 요청(신규)
local RE_QuizEnd = Remotes:FindFirstChild("Quiz_EndRequest") :: RemoteEvent?
if not RE_QuizEnd then
	RE_QuizEnd = Instance.new("RemoteEvent")
	RE_QuizEnd.Name = "Quiz_EndRequest"
	RE_QuizEnd.Parent = Remotes
end

----------------------------------------------------------------
-- 설정
----------------------------------------------------------------
-- 컷씬 브로드캐스트 채널
local CUTSCENE_CHANNEL_FINAL = "FinalCutscene_Global_v1"
local CUTSCENE_CHANNEL_QUIZ  = "QuizEnd_Global_v1"

-- 텔레포트 브로드캐스트 채널 (FinalTeleportToLobby.server.lua의 BROADCAST_TOPIC과 동일)
local TELEPORT_CHANNEL = "FinalTeleportAll"

-- 컷씬 총 길이(초) + 여유
local FINAL_CUTSCENE_SEC = 25.0
local QUIZ_ENDING_SEC    = 25.0

-- FinalTeleportToLobby.server.lua 에서 허용해야 하는 reason
local REASON_FINAL = "final_zone"
--local REASON_QUIZ  = "quiz_end"

-- ✅ 중복 방지(sessionId 기준 1회)
local alreadyHandled: {[string]: boolean} = {}

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

local function getSessionIdFrom(plr: Player, payload: any): string?
	if typeof(payload) == "table" and typeof(payload.sessionId) == "string" and #payload.sessionId > 0 then
		return payload.sessionId
	end
	local sid = plr:GetAttribute("sessionId")
	if typeof(sid) == "string" and #sid > 0 then
		return sid
	end
	return nil
end

local function hasSessionPlayerHere(sessionId: string): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("sessionId") == sessionId then
			return true
		end
	end
	return false
end

----------------------------------------------------------------
-- (A) 이 서버에서 컷씬 신호 보내기
----------------------------------------------------------------
local function fireCutsceneThisServer(payload: any)
	-- 1) 신규 클라용: table payload
	RE_PlayCutscene:FireAllClients(payload)

	-- 2) 기존 FinalZone 클라 호환: "Play"
	--    (FinalZone 전용에서는 기존처럼 "Play"를 받는 코드가 있을 수 있어서 같이 보내줌)
	if typeof(payload) == "table" and payload.compatPlay == true then
		RE_PlayCutscene:FireAllClients("Play")
	end
end

----------------------------------------------------------------
-- (B) 텔레포트 브로드캐스트는 "선생님 서버"에서 딱 1번만
----------------------------------------------------------------
local function broadcastTeleportOnce(sessionId: string, reason: string, delaySec: number)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TELEPORT_CHANNEL, {
			sessionId = sessionId,
			reason    = reason,
			device    = "server",
			delaySec  = delaySec,
		})
	end)
	if not ok then
		warn("[EndOrchestrator] teleport PublishAsync failed:", err)
	end
end

----------------------------------------------------------------
-- 1) 모든 서버: FinalZone 컷씬 수신 → FinalZone 컷씬만 재생
----------------------------------------------------------------
pcall(function()
	MessagingService:SubscribeAsync(CUTSCENE_CHANNEL_FINAL, function(message)
		local data = message.Data
		if typeof(data) ~= "table" then return end
		if data.kind ~= "Play" then return end

		local sid = data.sessionId
		if typeof(sid) ~= "string" or sid == "" then return end
		if alreadyHandled[sid] then return end
		if not hasSessionPlayerHere(sid) then return end

		alreadyHandled[sid] = true

		fireCutsceneThisServer({
			mode = "FinalZone",
			cleanup = false,
			compatPlay = true, -- ✅ 기존 "Play"도 같이 쏘는 호환 모드
			source = "MessagingService",
		})
	end)
end)

----------------------------------------------------------------
-- 2) 모든 서버: QuizEnd 엔딩 수신 → 정리 + 엔딩 재생
----------------------------------------------------------------
pcall(function()
	MessagingService:SubscribeAsync(CUTSCENE_CHANNEL_QUIZ, function(message)
		local data = message.Data
		if typeof(data) ~= "table" then return end
		if data.kind ~= "QuizEnd" then return end

		local sid = data.sessionId
		if typeof(sid) ~= "string" or sid == "" then return end
		if alreadyHandled[sid] then return end
		if not hasSessionPlayerHere(sid) then return end

		alreadyHandled[sid] = true

		fireCutsceneThisServer({
			mode = "Ending",     -- ✅ 네가 만든 클라(정리→엔딩)에서 이걸 받으면 됨
			cleanup = true,
			source = "MessagingService",
		})
	end)
end)

----------------------------------------------------------------
-- 3) 선생님: FinalZone 종료 요청(기존)
----------------------------------------------------------------
RE_FinalEnd.OnServerEvent:Connect(function(plr: Player, payload: any)
	if not plr or not plr.Parent then return end
	if not isTeacher(plr) then
		warn(("[EndOrchestrator] Non-teacher blocked(Final): %s(%d)"):format(plr.Name, plr.UserId))
		return
	end

	local sid = getSessionIdFrom(plr, payload)
	if not sid then
		warn("[EndOrchestrator] missing sessionId(Final)")
		return
	end
	if alreadyHandled[sid] then
		warn("[EndOrchestrator] already handled sid(Final)=", sid)
		return
	end
	alreadyHandled[sid] = true

	-- (A) 로컬 즉시
	fireCutsceneThisServer({
		mode = "FinalZone",
		cleanup = false,
		compatPlay = true,
		source = "TeacherLocal",
	})

	-- (B) 다른 서버 컷씬
	pcall(function()
		MessagingService:PublishAsync(CUTSCENE_CHANNEL_FINAL, {
			kind      = "Play",
			sessionId = sid,
		})
	end)

	-- (C) 텔레포트 브로드캐스트 딱 1번
	broadcastTeleportOnce(sid, REASON_FINAL, FINAL_CUTSCENE_SEC)
end)

----------------------------------------------------------------
-- 4) 선생님: 퀴즈 종료 요청(신규)
----------------------------------------------------------------
RE_QuizEnd.OnServerEvent:Connect(function(plr: Player, payload: any)
	if not plr or not plr.Parent then return end
	if not isTeacher(plr) then
		warn(("[EndOrchestrator] Non-teacher blocked(Quiz): %s(%d)"):format(plr.Name, plr.UserId))
		return
	end

	local sid = getSessionIdFrom(plr, payload)
	if not sid then
		warn("[EndOrchestrator] missing sessionId(Quiz)")
		return
	end
	if alreadyHandled[sid] then
		warn("[EndOrchestrator] already handled sid(Quiz)=", sid)
		return
	end
	alreadyHandled[sid] = true

	-- (A) 로컬 즉시: 정리+엔딩
	fireCutsceneThisServer({
		mode = "Ending",
		cleanup = true,
		source = "TeacherLocal",
	})

	-- (B) 다른 서버도 정리+엔딩
	pcall(function()
		MessagingService:PublishAsync(CUTSCENE_CHANNEL_QUIZ, {
			kind      = "QuizEnd",
			sessionId = sid,
		})
	end)

	-- (C) 텔레포트 브로드캐스트 딱 1번
	broadcastTeleportOnce(sid, REASON_FINAL, QUIZ_ENDING_SEC)
	--sessionResume.ClearSession(sid)
	hubStartState.Clear(sid)
end)

print("[EndOrchestrator] READY (FinalZone + QuizEnd unified)")
