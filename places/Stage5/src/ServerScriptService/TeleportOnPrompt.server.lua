-- ServerScriptService/TeleportOnRequest.server.lua
--!strict
-- RemoteEvent "Teleport_Request" 수신 → NEXT_PLACE_ID 로 텔레포트
-- - 이전 TeleportData 를 그대로 복사해서 사용
-- - TeleportData.session.id (세션 ID)는 건드리지 않고 유지
-- - reason = "final_zone" (또는 payload.reason) 을 기록
-- - 같은 프라이빗 서버를 최대한 재사용

local TeleportService   = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

-------------------------------------------------------
-- 설정
-------------------------------------------------------
local NEXT_PLACE_ID              = 120816172838238 -- 이 스크립트가 보내고 싶은 목적지 PlaceId
local COOLDOWN_SEC               = 2.0
local ENSURE_PRIVATE_IF_MISSING  = true

-------------------------------------------------------
-- Remotes
-------------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local RE_TeleportRequest = Remotes:FindFirstChild("Teleport_Request")
if not RE_TeleportRequest then
	RE_TeleportRequest = Instance.new("RemoteEvent")
	RE_TeleportRequest.Name = "Teleport_Request"
	RE_TeleportRequest.Parent = Remotes
end

-------------------------------------------------------
-- 상태 / 유틸
-------------------------------------------------------
local lastCall: {[number]: number}      = {}
local isTeleporting: {[number]: boolean} = {}
local SERVER_CODE_CACHE: {[number]: string} = {}

local function canStartTeleport(plr: Player): boolean
	if isTeleporting[plr.UserId] then
		warn("[TeleportServer] already teleporting:", plr.Name)
		return false
	end

	local now  = os.clock()
	local prev = lastCall[plr.UserId] or 0
	if (now - prev) < COOLDOWN_SEC then
		warn("[TeleportServer] cooldown:", plr.Name)
		return false
	end

	lastCall[plr.UserId] = now
	return true
end

local function markTeleportStart(plr: Player)
	isTeleporting[plr.UserId] = true
end

local function markTeleportEnd(plr: Player)
	isTeleporting[plr.UserId] = false
end

local function tryReadReservedFromJoin(plr: Player, placeId: number): string?
	local ok, join = pcall(function() return plr:GetJoinData() end)
	if not ok or type(join) ~= "table" then return nil end
	local td = join.TeleportData
	if type(td) ~= "table" then return nil end

	if type(td.reservedCodes) == "table" then
		local hit = td.reservedCodes[tostring(placeId)]
		if type(hit) == "string" and #hit > 0 then return hit end
	end

	if type(td.session) == "table" then
		local sid   = td.session.placeId
		local pcode = td.session.privateServerCode
		if tonumber(sid) == placeId and type(pcode) == "string" and #pcode > 0 then
			return pcode
		end
	end

	return nil
end

local function tryReadReservedFromAttr(plr: Player, placeId: number): string?
	local json = plr:GetAttribute("ReservedCodesJson")
	if type(json) ~= "string" or #json == 0 then return nil end
	local ok, map = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(map) ~= "table" then return nil end
	local hit = map[tostring(placeId)]
	return (type(hit) == "string" and #hit > 0) and hit or nil
end

local function writeCodeBackToAttr(plr: Player, placeId: number, code: string)
	if not code or #code == 0 then return end
	local map = {}
	do
		local txt = plr:GetAttribute("ReservedCodesJson")
		if type(txt) == "string" and #txt > 0 then
			local ok, dec = pcall(HttpService.JSONDecode, HttpService, txt)
			if ok and type(dec) == "table" then
				map = dec
			end
		end
	end
	map[tostring(placeId)] = code
	plr:SetAttribute("ReservedCodesJson", HttpService:JSONEncode(map))
end

local function ensureReservedCode(plr: Player, payload: any): string?
	-- 0) payload 우선
	if typeof(payload) == "table" then
		local code0 = payload.reservedCode or payload.accessCode or payload.code
		if type(code0) == "string" and #code0 > 0 then return code0 end
	end

	-- 1) 서버 캐시
	if type(SERVER_CODE_CACHE[NEXT_PLACE_ID]) == "string" and #SERVER_CODE_CACHE[NEXT_PLACE_ID] > 0 then
		return SERVER_CODE_CACHE[NEXT_PLACE_ID]
	end

	-- 2) JoinData → TeleportData
	local fromJoin = tryReadReservedFromJoin(plr, NEXT_PLACE_ID)
	if fromJoin then
		SERVER_CODE_CACHE[NEXT_PLACE_ID] = fromJoin
		return fromJoin
	end

	-- 3) 플레이어 Attribute
	local fromAttr = tryReadReservedFromAttr(plr, NEXT_PLACE_ID)
	if fromAttr then
		SERVER_CODE_CACHE[NEXT_PLACE_ID] = fromAttr
		return fromAttr
	end

	-- 4) 필요 시 새 예약
	if ENSURE_PRIVATE_IF_MISSING then
		local ok, codeOrErr = pcall(function()
			return TeleportService:ReserveServer(NEXT_PLACE_ID)
		end)
		if ok and type(codeOrErr) == "string" and #codeOrErr > 0 then
			SERVER_CODE_CACHE[NEXT_PLACE_ID] = codeOrErr
			writeCodeBackToAttr(plr, NEXT_PLACE_ID, codeOrErr)
			return codeOrErr
		else
			warn("[TeleportServer] ReserveServer failed:", tostring(codeOrErr))
		end
	end

	return nil
end

-------------------------------------------------------
-- TeleportData 생성 (기존 데이터 + final_zone reason, 등)
-------------------------------------------------------
local function buildTeleportData(plr: Player, payload: any, chosenCode: string?)
	if typeof(payload) ~= "table" then
		payload = {}
	end

	-- 기본 reason: final_zone (payload.reason 이 있으면 덮어써도 됨)
	local reason = payload.reason or "final_zone"

	-- 디바이스 / 스테이지 정보: payload → Attribute 순
	local device = payload.device or plr:GetAttribute("FinalJumpDevice")
	if device ~= "mobile" and device ~= "pc" then
		device = "pc"
	end

	local stage  = payload.selectedStage or plr:GetAttribute("FinalJumpStage") or 1
	stage = tonumber(stage) or 1

	-- 🔹 기존 TeleportData 를 통째로 복사 (세션 ID 포함)
	local base: any = {}
	local ok, join = pcall(function() return plr:GetJoinData() end)
	if ok and type(join) == "table" and type(join.TeleportData) == "table" then
		for k, v in pairs(join.TeleportData) do
			base[k] = v
		end
	end

	-- 여기서 session.id 는 일부러 안 건드린다
	if typeof(base.session) ~= "table" then
		base.session = {}
	end
	-- base.session.id 는 그대로 유지
	-- 필요하다면 목적지 관련 필드만 추가/수정
	base.session.placeId           = NEXT_PLACE_ID
	base.session.privateServerCode = chosenCode or base.session.privateServerCode

	-- fromPlaceId / lastPlaceId 업데이트 (안 쓰면 그냥 참고용)
	base.fromPlaceId = base.fromPlaceId or game.PlaceId
	base.lastPlaceId = game.PlaceId

	-- 기타 메타 정보 업데이트
	base.reason        = reason
	base.from          = base.from or reason
	base.selectedStage = stage
	base.device        = device
	base.requester     = plr.UserId

	-- 프라이빗 코드 맵
	if chosenCode then
		base.reservedCodes = base.reservedCodes or {}
		base.reservedCodes[tostring(NEXT_PLACE_ID)] = chosenCode
	end

	print(("[TeleportServer] buildTeleportData: sessionId=%s, reason=%s, fromPlaceId=%s → NEXT_PLACE_ID=%d")
		:format(
			(typeof(base.session)=="table" and tostring(base.session.id)) or "nil",
			tostring(base.reason),
			tostring(base.fromPlaceId),
			NEXT_PLACE_ID
		))

	return base
end

-------------------------------------------------------
-- 메인 핸들러
-------------------------------------------------------
RE_TeleportRequest.OnServerEvent:Connect(function(plr: Player, payload: any)
	if not plr or not plr.Parent then return end
	if not canStartTeleport(plr) then return end

	markTeleportStart(plr)

	-- 프라이빗 코드 확보
	local code  = ensureReservedCode(plr, payload)
	local tdata = buildTeleportData(plr, payload, code)

	local opts = Instance.new("TeleportOptions")
	opts:SetTeleportData(tdata)
	if code then
		opts.ReservedServerAccessCode = code
	end

	print(("[TeleportServer] TeleportAsync %s → %d"):format(plr.Name, NEXT_PLACE_ID))

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(NEXT_PLACE_ID, {plr}, opts)
	end)
	if ok then
		return
	end

	warn("[TeleportServer] TeleportAsync failed:", tostring(err))
	markTeleportEnd(plr)

	-- 프라이빗 서버 폴백
	if code then
		local ok2, err2 = pcall(function()
			TeleportService:TeleportToPrivateServer(NEXT_PLACE_ID, code, {plr}, nil, tdata)
		end)
		if ok2 then
			markTeleportStart(plr)
			return
		end
		warn("[TeleportServer] TeleportToPrivateServer failed:", tostring(err2))
	end

	-- 마지막 폴백: 공개 서버
	local opts2 = Instance.new("TeleportOptions")
	opts2:SetTeleportData(tdata)
	pcall(function()
		TeleportService:TeleportAsync(NEXT_PLACE_ID, {plr}, opts2)
	end)
end)

print("[TeleportServer] READY — keeps TeleportData.session.id and teleports to", NEXT_PLACE_ID)
