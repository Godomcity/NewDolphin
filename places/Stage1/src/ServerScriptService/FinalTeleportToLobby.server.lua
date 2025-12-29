-- ServerScriptService/FinalTeleportToLobby.server.lua
--!strict
-- MessagingService(BROADCAST_TOPIC) 수신 → (delaySec 후) sessionId 플레이어들을 로비 PlaceId로 텔레포트
-- + 중복 브로드캐스트 방지(sessionId 기준 dedupe)
-- ✅ 변경: TEACHER_USER_ID 제거, Player Attribute(isTeacher/userRole/roomCode) 기반 권한 판별
-- ✅ 변경: TeleportData에 userRole/isTeacher/roomCode 유지해서 다음 place에서도 그대로 복원 가능

local Players              = game:GetService("Players")
local TeleportService      = game:GetService("TeleportService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ServerScriptService  = game:GetService("ServerScriptService")
local MessagingService     = game:GetService("MessagingService")
local RunService           = game:GetService("RunService")

local SessionRouter = require(ServerScriptService.Modules:WaitForChild("SessionRouter"))

-- ===== 설정 =====
local LOBBY_PLACE_ID      = 120816172838238
local COOLDOWN_SEC        = 2.0
local BROADCAST_TOPIC     = "FinalTeleportAll"

-- “클라에서 직접 FinalTeleport_Request 쏠 때” 쓸 기본 딜레이
local TELEPORT_DELAY_SEC  = 25.0

-- ✅ 허용 reason 목록
local ALLOW_REASONS = {
	final_zone = true,
	quiz_end   = false, -- 필요하면 true로
}

-- ✅ 같은 sessionId 메시지 중복 처리 방지(서버당 1회)
local handledSession: {[string]: boolean} = {}

-- ===== Remotes =====
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local RE_FinalTeleport = Remotes:FindFirstChild("FinalTeleport_Request") :: RemoteEvent?
if not RE_FinalTeleport then
	RE_FinalTeleport = Instance.new("RemoteEvent")
	RE_FinalTeleport.Name = "FinalTeleport_Request"
	RE_FinalTeleport.Parent = Remotes
end

-- ===== 쿨다운 (RemoteEvent용) =====
local lastCall: {[number]: number} = {}

local function canBroadcast(plr: Player): boolean
	local now = os.clock()
	local prev = lastCall[plr.UserId] or 0
	if (now - prev) < COOLDOWN_SEC then
		return false
	end
	lastCall[plr.UserId] = now
	return true
end

-- ✅ 선생님 판별: Attribute 기반
local function isTeacher(plr: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return plr:GetAttribute("isTeacher") == true
end

-- ===== sessionId 추출 =====
local function extractSessionId(plr: Player, payload: any): string?
	if typeof(payload) == "table" and typeof(payload.sessionId) == "string" and #payload.sessionId > 0 then
		return payload.sessionId
	end

	local sidAttr = plr:GetAttribute("sessionId")
	if typeof(sidAttr) == "string" and #sidAttr > 0 then
		return sidAttr
	end

	local ok, joinData = pcall(function()
		return plr:GetJoinData()
	end)
	if ok and typeof(joinData) == "table" then
		local td = joinData.TeleportData
		if typeof(td) == "table" then
			if typeof(td.session) == "table" and typeof(td.session.id) == "string" and #td.session.id > 0 then
				return td.session.id
			end
			if typeof(td.sessionId) == "string" and #td.sessionId > 0 then
				return td.sessionId
			end
		end
	end

	return nil
end

-- ===== role/roomCode 추출 (Attribute 우선) =====
local function extractUserRole(plr: Player, payload: any?): string?
	if typeof(payload) == "table" and typeof(payload.userRole) == "string" and payload.userRole ~= "" then
		return payload.userRole
	end

	local r = plr:GetAttribute("userRole")
	if typeof(r) == "string" and r ~= "" then
		return r
	end

	local ok, joinData = pcall(function()
		return plr:GetJoinData()
	end)
	if ok and typeof(joinData) == "table" and typeof(joinData.TeleportData) == "table" then
		local td = joinData.TeleportData
		local p = td.player
		if typeof(p) == "table" and typeof(p.userRole) == "string" and #p.userRole > 0 then
			return p.userRole
		end
	end

	return nil
end

local function extractRoomCode(plr: Player, payload: any?): string?
	if typeof(payload) == "table" and typeof(payload.roomCode) == "string" and payload.roomCode ~= "" then
		return payload.roomCode
	end

	local rc = plr:GetAttribute("roomCode")
	if typeof(rc) == "string" and rc ~= "" then
		return rc
	end

	local ok, joinData = pcall(function()
		return plr:GetJoinData()
	end)
	if ok and typeof(joinData) == "table" and typeof(joinData.TeleportData) == "table" then
		local td = joinData.TeleportData
		local sess = td.session
		if typeof(sess) == "table" and typeof(sess.roomCode) == "string" and #sess.roomCode > 0 then
			return sess.roomCode
		end
	end

	return nil
end

-- ===== TeleportData 구성 =====
-- - 기존 TeleportData를 최대한 유지(복사)하면서
-- - session.id / player.userRole / player.isTeacher / session.roomCode 를 "확실히" 넣어줌
local function buildTeleportData(plr: Player, payload: any, sessionId: string, reservedCode: string?)
	local reason = (typeof(payload) == "table" and payload.reason) or "final_zone"
	local device = (typeof(payload) == "table" and payload.device) or tostring(plr:GetAttribute("Device") or "pc")

	local userRole = extractUserRole(plr, payload)
	local roomCode = extractRoomCode(plr, payload)
	local teacherBool = isTeacher(plr)

	-- 기존 TeleportData 복사(있으면)
	local base: any = {}
	local ok, joinData = pcall(function()
		return plr:GetJoinData()
	end)
	if ok and typeof(joinData) == "table" and typeof(joinData.TeleportData) == "table" then
		for k, v in pairs(joinData.TeleportData) do
			base[k] = v
		end
	end

	-- 공통 메타
	base.version    = tonumber(base.version) or 3
	base.reason     = reason
	base.device     = device
	base.fromPlaceId = game.PlaceId

	-- sessionId(구/신 스키마 모두 세팅)
	base.sessionId = sessionId

	base.session = base.session or {}
	base.session.id      = sessionId
	base.session.placeId = LOBBY_PLACE_ID
	if reservedCode then
		base.session.privateServerCode = reservedCode
	end
	if roomCode and roomCode ~= "" then
		base.session.roomCode = roomCode
	end

	-- player role
	base.player = base.player or {}
	if userRole and userRole ~= "" then
		base.player.userRole = userRole
	end
	base.player.isTeacher = teacherBool

	-- reservedCodes 캐시
	if reservedCode then
		base.reservedCodes = base.reservedCodes or {}
		base.reservedCodes[tostring(LOBBY_PLACE_ID)] = reservedCode
	end

	return base
end

-- ===== 실제 텔레포트 수행 =====
local function teleportOnePlayer(plr: Player, payload: any?)
	if not plr or not plr.Parent then return end

	local sessionId = extractSessionId(plr, payload)
	if not sessionId then
		warn("[FinalTeleport] missing sessionId for", plr.Name, "→ 공개 서버로 폴백(세션 보장 불가)")
	end

	local reservedCode: string? = nil
	if sessionId then
		local okCode, code, err = SessionRouter.GetOrCreate(sessionId, LOBBY_PLACE_ID)
		if not okCode or not code then
			warn("[FinalTeleport] SessionRouter.GetOrCreate failed:", err)
		else
			reservedCode = code
		end
	end

	local tdata = buildTeleportData(plr, payload, sessionId or "NO_SESSION", reservedCode)

	local opts = Instance.new("TeleportOptions")
	opts:SetTeleportData(tdata)
	if reservedCode then
		opts.ReservedServerAccessCode = reservedCode
	end

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(LOBBY_PLACE_ID, { plr }, opts)
	end)
	if ok then return end

	warn("[FinalTeleport] TeleportAsync failed:", err)

	-- 구 API 폴백
	if reservedCode then
		local okOld, errOld = pcall(function()
			TeleportService:TeleportToPrivateServer(LOBBY_PLACE_ID, reservedCode, { plr }, nil, tdata)
		end)
		if okOld then return end
		warn("[FinalTeleport] TeleportToPrivateServer failed:", errOld)
	end

	-- 마지막 폴백(공개)
	local opts2 = Instance.new("TeleportOptions")
	opts2:SetTeleportData(tdata)
	pcall(function()
		TeleportService:TeleportAsync(LOBBY_PLACE_ID, { plr }, opts2)
	end)
end

-- ✅ 현재 서버에서 해당 sessionId 플레이어만 텔레포트
local function teleportSessionPlayersHere(sessionId: string, payload: any)
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("sessionId") == sessionId then
			teleportOnePlayer(p, payload)
		end
	end
end

----------------------------------------------------------------
-- ✅ MessagingService 수신: (딜레이 후) 텔레포트 실행 + reason 체크 + dedupe
----------------------------------------------------------------
local function subscribeFinalTeleportAll()
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(BROADCAST_TOPIC, function(message)
			local data = message.Data
			if typeof(data) ~= "table" then return end

			local sid = data.sessionId
			if typeof(sid) ~= "string" or sid == "" then return end

			-- ✅ reason 체크
			local reason = tostring(data.reason)
			if not ALLOW_REASONS[reason] then
				warn("[FinalTeleport] ignore broadcast by reason:", reason)
				return
			end

			-- ✅ dedupe
			if handledSession[sid] then
				warn("[FinalTeleport] duplicate broadcast ignored sid=", sid, "jobId=", game.JobId)
				return
			end
			handledSession[sid] = true

			local delaySec = tonumber(data.delaySec) or 0
			print(("[FinalTeleport] Broadcast received sid=%s reason=%s delay=%.2f placeId=%d jobId=%s userRole=%s roomCode=%s")
				:format(
					sid,
					reason,
					delaySec,
					game.PlaceId,
					game.JobId,
					tostring(data.userRole),
					tostring(data.roomCode)
				))

			task.delay(delaySec, function()
				teleportSessionPlayersHere(sid, data)
			end)
		end)
	end)

	if not ok then
		warn("[FinalTeleport] SubscribeAsync failed:", err)
	else
		print("[FinalTeleport] Subscribed to topic:", BROADCAST_TOPIC)
	end
end

subscribeFinalTeleportAll()

----------------------------------------------------------------
-- ✅ RemoteEvent: 선생님 트리거 → 브로드캐스트(딜레이 포함)
----------------------------------------------------------------
RE_FinalTeleport.OnServerEvent:Connect(function(plr: Player, payload: any)
	if not plr or not plr.Parent then return end
	if not canBroadcast(plr) then
		warn("[FinalTeleport] cooldown blocked for", plr.Name)
		return
	end

	-- ✅ TEACHER_USER_ID 대신 Attribute 기반 권한
	if not isTeacher(plr) then
		warn("[FinalTeleport] Non-teacher blocked:", plr.Name, plr.UserId)
		return
	end

	local reason = tostring((typeof(payload) == "table" and payload.reason) or "")
	if not ALLOW_REASONS[reason] then
		warn("[FinalTeleport] blocked by reason:", reason)
		return
	end

	local sessionId = extractSessionId(plr, payload)
	if not sessionId then
		warn("[FinalTeleport] missing sessionId for", plr.Name, "→ 세션 전체 텔레포트 불가 (요청자만 이동)")
		teleportOnePlayer(plr, payload)
		return
	end

	-- dedupe
	if handledSession[sessionId] then
		warn("[FinalTeleport] already handled sid=", sessionId, "jobId=", game.JobId)
		return
	end
	handledSession[sessionId] = true

	local data = {
		sessionId = sessionId,
		reason    = reason,
		device    = (typeof(payload) == "table" and payload.device) or tostring(plr:GetAttribute("Device") or "pc"),
		delaySec  = TELEPORT_DELAY_SEC,

		-- ✅ 같이 실어두면 다른 서버에서 로그/검증/디버그에 도움됨
		userRole  = tostring(plr:GetAttribute("userRole") or ""),
		roomCode  = tostring(plr:GetAttribute("roomCode") or ""),
	}

	local ok, pubErr = pcall(function()
		MessagingService:PublishAsync(BROADCAST_TOPIC, data)
	end)

	if not ok then
		warn("[FinalTeleport] PublishAsync failed:", pubErr, "→ 현재 서버만이라도 딜레이 후 텔레포트")
		task.delay(TELEPORT_DELAY_SEC, function()
			teleportSessionPlayersHere(sessionId, data)
		end)
	else
		print("[FinalTeleport] Broadcast FinalTeleportAll sid=", sessionId, "reason=", reason, "delaySec=", TELEPORT_DELAY_SEC)
	end
end)

print("[FinalTeleport] READY — Attribute(isTeacher) 기반 권한 + TeleportData(userRole/roomCode 유지) + Broadcast(dedupe/reason)")
