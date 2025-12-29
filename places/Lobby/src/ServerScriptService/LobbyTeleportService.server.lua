-- ServerScriptService/LobbyTeleportService.server.lua
--!strict
-- 입장코드 + 개인토큰(tokenId) -> Dolphin API에서 userRole 확인 -> SessionRouter -> TeleportData에 userRole 포함

local TeleportService   = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local Net = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local SessionRouter = require(script.Parent:WaitForChild("Modules"):WaitForChild("SessionRouter"))

-- ✅ 허브(첫 목적지) PlaceId로 교체
local DEST_PLACE_ID = 120816172838238

-- Dolphin API
local BASE = "https://api.dolphincoding.kr/dolphincoding/v1"
local TOKEN_LOOKUP_URL = BASE .. "/courses/worlds/users/tokens/%s"

local ROBLOX_CLIENT_ID = "ROBLOX_CLIENT_ID"

-- ✅ 서버에서만 보관 (절대 LocalScript에 두지 말 것)
local ACCESS_TOKEN = "eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJjMWQyYzYzYy01YTZlLTRkYWQtYTUwZS02YjllYWU4MjE2YjMiLCJ1c2VyUm9sZSI6IlJPTEVfVEVBQ0hFUiIsImNvdXJzZUlkIjoxNjksInRva2VuVHlwZSI6IkFDQ0VTUyIsImV4cCI6MTc2NjgwMDQ3N30.r7IL-Kat88iRJYPjOm9T-3VlsewzWAm59oAF1kyC1TWphrYb8EMSdhSA8cb9fIlUGeaN7jVU87l6M8y1X-kkrg"

-- RemoteFunction: EntryScreen LocalScript에서 호출
local RF_JoinByCode = Net.ensureRF("RF_JoinByCode")

-- ───────── 유틸 ─────────
local function norm(s: string?): string
	return (s or ""):gsub("%s+",""):upper()
end

local function isValidCode(code: string): boolean
	code = norm(code)
	return (#code == 8) and (code:match("^[A-Z0-9]+$") ~= nil)
end

local function trim(s)
	return (s or ""):match("^%s*(.-)%s*$")
end

local function maskToken(s: string?): string
	if type(s) ~= "string" then return tostring(s) end
	if #s <= 12 then return "****" end
	return s:sub(1, 6) .. "..." .. s:sub(-4)
end

local function safeJsonDecode(body: string)
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	return ok and decoded or nil
end

-- ───────── Dolphin API: tokenId -> userRole/roomCode ─────────
type TokenLookupResponse = {
	accessToken: string?,
	accessTokenExpiresAt: string?,
	refreshTokenExpiresAt: string?,
	userRole: string?,
	roomCode: string?,
}

local function fetchUserRoleByTokenId(tokenId: string): (boolean, TokenLookupResponse?, string?)
	tokenId = trim(tokenId)
	if tokenId == "" then
		return false, nil, "missing_token"
	end

	local url = TOKEN_LOOKUP_URL:format(HttpService:UrlEncode(tokenId))

	local headers = {
		["Accept"] = "application/json",
		["X-CLIENT-ID"] = ROBLOX_CLIENT_ID,

		-- ✅ 이 엔드포인트가 인증 필요하면 켜야 함
		["accessToken"] = "Bearer " .. ACCESS_TOKEN,
	}

	print("[LobbyTeleport] Token lookup:", url, " tokenId=", maskToken(tokenId))

	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = headers,
		})
	end)

	if not ok then
		warn("[LobbyTeleport] RequestAsync failed:", res)
		return false, nil, "request_failed"
	end

	if not res.Success then
		warn(("[LobbyTeleport] token lookup HTTP %d %s"):format(res.StatusCode, tostring(res.StatusMessage)))
		-- 운영에서는 Body 로그는 최소화 추천 (민감정보 포함 가능)
		return false, nil, "http_" .. tostring(res.StatusCode)
	end

	local decoded = safeJsonDecode(res.Body or "")
	if type(decoded) ~= "table" then
		return false, nil, "bad_json"
	end

	return true, decoded :: any, nil
end

local function isTeacherRole(userRole: string?): boolean
	return userRole == "ROLE_TEACHER"
end

-- ───────── TeleportData ─────────
local function buildTeleportData(sessionId: string, entryCode: string, device: string, placeId: number, reservedCode: string, userRole: string?, roomCode: string?)
	return {
		version = 3,
		session = {
			id = sessionId,
			invite = entryCode,
			placeId = placeId,
			privateServerCode = reservedCode,
			roomCode = roomCode, -- 있으면 같이 넘김
		},
		player = {
			device = device,
			userRole = userRole,                 -- ✅ 핵심: 다음 place에서 선생님/학생 구분
			isTeacher = isTeacherRole(userRole), -- ✅ 편의 boolean도 같이
		},
		selectedStage = 1,

		-- 다음 플레이스에서도 같은 서버를 이어가도록 코드 캐시 동봉
		reservedCodes = {
			[tostring(placeId)] = reservedCode
		},
	}
end

-- ───────── 메인 핸들러 ─────────
RF_JoinByCode.OnServerInvoke = function(player: Player, payload: any)
	local entryCode = norm(tostring(payload and payload.entryCode or ""))
	local tokenId   = tostring(payload and payload.token or "") -- ✅ 개인 토큰ID(예: 2L4LG_HT)
	local device    = tostring(payload and payload.device or "desktop")

	print(("[LobbyTeleport] RF_JoinByCode from %s, code=%s, device=%s")
		:format(player.Name, entryCode, device))

	if not isValidCode(entryCode) then
		return { ok=false, error="invalid_code" }
	end
	if trim(tokenId) == "" then
		return { ok=false, error="invalid_token" }
	end

	-- ✅ 1) Dolphin API로 role 조회
	local okInfo, info, errInfo = fetchUserRoleByTokenId(tokenId)
	if not okInfo or not info then
		return { ok=false, error="token_lookup_failed", detail=errInfo }
	end

	local userRole = tostring(info.userRole or "")
	local roomCode = tostring(info.roomCode or "")

	if userRole == "" then
		return { ok=false, error="missing_userRole" }
	end

	print(("[LobbyTeleport] userRole=%s roomCode=%s"):format(userRole, roomCode))

	-- (선택) 서버에서만 참고하고 싶으면 Attribute로 저장 가능
	-- player:SetAttribute("UserRole", userRole)
	-- player:SetAttribute("RoomCode", roomCode)

	-- ✅ 2) 입장코드 → 세션ID(동일코드 = 동일 세션)
	local sessionId = "SID-" .. entryCode

	-- ✅ 3) 세션ID+placeId 조합으로 예약 서버 코드 조회/생성
	local okCode, reservedCode, err = SessionRouter.GetOrCreate(sessionId, DEST_PLACE_ID)
	if not okCode or not reservedCode then
		warn("[LobbyTeleport] Reserve/Get code failed:", err)
		return { ok=false, error="network_error" }
	end

	-- ✅ 4) 텔레포트 옵션 + 데이터
	local opts = Instance.new("TeleportOptions")
	opts.ReservedServerAccessCode = reservedCode

	local tpData = buildTeleportData(sessionId, entryCode, device, DEST_PLACE_ID, reservedCode, userRole, roomCode)
	opts:SetTeleportData(tpData)

	-- ✅ 5) 텔레포트
	local ok, tpErr = pcall(function()
		TeleportService:TeleportAsync(DEST_PLACE_ID, {player}, opts)
	end)
	if not ok then
		warn("[LobbyTeleport] TeleportAsync failed:", tpErr)
		return { ok=false, error="network_error" }
	end

	return { ok=true }
end

print("[LobbyTeleportService] READY — API(userRole) → SessionRouter → TeleportData include userRole")
