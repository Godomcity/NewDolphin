-- ServerScriptService/TeleportOnRequest.server.lua
--!strict
-- RemoteEvent "Teleport_Request" 수신 → 같은 프라이빗 서버 보장 시도
-- - reservedCode 있으면 사용
-- - 없으면 JoinData/플레이어 속성/서버 캐시에서 찾기
-- - 그래도 없으면 (옵션) ReserveServer로 새 코드 생성

local TeleportService   = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

-- ===== 설정 =====
local NEXT_PLACE_ID              = 110807604104301--110579663083129 -- 목적지
local COOLDOWN_SEC               = 2.0
local ENSURE_PRIVATE_IF_MISSING  = true            -- 코드 없으면 새로 예약할지

-- ===== Remotes =====
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local RE_TeleportRequest = Remotes:FindFirstChild("Teleport_Request") or Instance.new("RemoteEvent", Remotes)
RE_TeleportRequest.Name  = "Teleport_Request"

-- ===== 서버 캐시(동일 서버 내 재사용) =====
local SERVER_CODE_CACHE: {[number]: string} = {}

-- ===== 유틸 =====
local lastCall: {[number]: number} = {}
local function canTeleport(plr: Player): boolean
	local now = os.clock()
	local prev = lastCall[plr.UserId] or 0
	if (now - prev) < COOLDOWN_SEC then return false end
	lastCall[plr.UserId] = now
	return true
end

local function tryReadReservedFromJoin(plr: Player, placeId: number): string?
	local ok, join = pcall(function() return plr:GetJoinData() end)
	if not ok or type(join) ~= "table" then return nil end
	local td = join.TeleportData
	if type(td) ~= "table" then return nil end

	-- 1) reservedCodes 맵에서 찾기
	if type(td.reservedCodes) == "table" then
		local hit = td.reservedCodes[tostring(placeId)]
		if type(hit) == "string" and #hit > 0 then return hit end
	end
	-- 2) 세션 정보에 실려온 코드 (같은 placeId라면)
	if type(td.session) == "table" then
		local sid = td.session.placeId
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
	return (type(hit)=="string" and #hit>0) and hit or nil
end

local function writeCodeBackToAttr(plr: Player, placeId: number, code: string)
	if not code or #code == 0 then return end
	local map = {}
	do
		local txt = plr:GetAttribute("ReservedCodesJson")
		if type(txt) == "string" and #txt > 0 then
			local ok, dec = pcall(HttpService.JSONDecode, HttpService, txt)
			if ok and type(dec) == "table" then map = dec end
		end
	end
	map[tostring(placeId)] = code
	plr:SetAttribute("ReservedCodesJson", HttpService:JSONEncode(map))
end

local function ensureReservedCode(plr: Player, payload: any): string?
	-- 0) payload 우선
	if type(payload) == "table" then
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
	-- 3) 플레이어 속성(저장해둔 맵)
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
		if ok and type(codeOrErr)=="string" and #codeOrErr>0 then
			SERVER_CODE_CACHE[NEXT_PLACE_ID] = codeOrErr
			writeCodeBackToAttr(plr, NEXT_PLACE_ID, codeOrErr)
			return codeOrErr
		else
			warn("[Teleport] ReserveServer failed:", tostring(codeOrErr))
		end
	end
	return nil
end

local function buildTeleportData(plr: Player, payload: any, chosenCode: string?)
	local reason  = (type(payload)=="table" and payload.reason) or "portal"
	local device  = (type(payload)=="table" and payload.device) or "pc"
	local stage   = (type(payload)=="table" and payload.selectedStage) or 1

	-- 기존 TeleportData 가져와 유지(있으면)
	local base: any = {}
	local ok, join = pcall(function() return plr:GetJoinData() end)
	if ok and type(join)=="table" and type(join.TeleportData)=="table" then
		-- 얕은 복사
		for k,v in pairs(join.TeleportData) do base[k]=v end
	end

	base.from          = base.from or "portal"
	base.reason        = reason
	base.selectedStage = stage
	base.device        = device
	base.requester     = plr.UserId

	-- 다음 홉에서도 재사용할 수 있게 주입
	if chosenCode then
		base.reservedCodes = base.reservedCodes or {}
		base.reservedCodes[tostring(NEXT_PLACE_ID)] = chosenCode
		base.session = base.session or {}
		base.session.placeId = NEXT_PLACE_ID
		base.session.privateServerCode = chosenCode
	end
	return base
end

-- ===== 핸들러 =====
RE_TeleportRequest.OnServerEvent:Connect(function(plr: Player, payload: any)
	if not plr or not plr.Parent then return end
	if not canTeleport(plr) then
		warn("[Teleport] cooldown:", plr.Name)
		return
	end
	-- 정책 체크 자리
	-- if not serverAllows(plr, payload) then return end

	-- 코드 확보(여러 경로 → 필요 시 자동 생성)
	local code = ensureReservedCode(plr, payload)

	local tdata = buildTeleportData(plr, payload, code)
	local opts  = Instance.new("TeleportOptions")
	opts:SetTeleportData(tdata)

	if code then
		opts.ReservedServerAccessCode = code
	end

	-- 1차 시도
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(NEXT_PLACE_ID, {plr}, opts)
	end)
	if ok then return end

	warn("[Teleport] TeleportAsync failed:", tostring(err))

	-- 코드가 있으면 구버전 API 폴백
	if code then
		local ok2, err2 = pcall(function()
			TeleportService:TeleportToPrivateServer(NEXT_PLACE_ID, code, {plr}, nil, tdata)
		end)
		if ok2 then return end
		warn("[Teleport] TeleportToPrivateServer failed:", tostring(err2))
	end

	-- 마지막 폴백: 공개 서버(코드 없이)
	local opts2 = Instance.new("TeleportOptions")
	opts2:SetTeleportData(tdata)
	pcall(function()
		TeleportService:TeleportAsync(NEXT_PLACE_ID, {plr}, opts2)
	end)
end)

print("[TeleportServer] READY — resilient private-server teleport to", NEXT_PLACE_ID)
