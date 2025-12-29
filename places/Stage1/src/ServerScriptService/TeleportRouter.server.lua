-- ServerScriptService/TeleportRouter.server.lua
--!strict
-- 클라이언트: TeleportUtil.Go(targetPlaceId, { sessionId?, device?, reason?, meta? })
-- 서버: SessionRouter로 ReservedServerAccessCode 확보 → TeleportAsync 실행
-- 실패 시 TeleportToPrivateServer 1회 폴백
-- 실패/에러는 Remotes.Teleport_Result 로 개별 플레이어에게 전송

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local SessionRouter = require(script.Parent:WaitForChild("Modules"):WaitForChild("SessionRouter"))

-- Remotes 준비
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local REQ = Remotes:FindFirstChild("Teleport_Request")
if not REQ then
	REQ = Instance.new("RemoteEvent")
	REQ.Name = "Teleport_Request"
	REQ.Parent = Remotes
end

local RES = Remotes:FindFirstChild("Teleport_Result")
if not RES then
	RES = Instance.new("RemoteEvent")
	RES.Name = "Teleport_Result"
	RES.Parent = Remotes
end

-- 간단 쿨다운 (플레이어당 N초에 1회)
local COOLDOWN = 2.0
local lastTick: {[number]: number} = {}

local function can(plr: Player): boolean
	local now = os.clock()
	local prev = lastTick[plr.UserId] or 0
	if (now - prev) < COOLDOWN then
		return false
	end
	lastTick[plr.UserId] = now
	return true
end

-- 세션ID 추출
-- 우선순위:
--   1) payload.sessionId
--   2) Player.Attribute("sessionId")  (SessionBootstrap에서 채워줌)
local function extractSessionId(plr: Player, payload: any): string?
	if typeof(payload) == "table" and typeof(payload.sessionId) == "string" and #payload.sessionId > 0 then
		return payload.sessionId
	end

	local sidAttr = plr:GetAttribute("sessionId")
	if typeof(sidAttr) == "string" and #sidAttr > 0 then
		return sidAttr
	end

	return nil
end

local function fireError(plr: Player, code: string, msg: string)
	RES:FireClient(plr, {
		ok   = false,
		code = code,
		msg  = msg,
	})
end

REQ.OnServerEvent:Connect(function(plr: Player, payload: any)
	if not plr or not plr.Parent then
		return
	end

	if not can(plr) then
		-- 너무 자주 눌렀을 때는 굳이 에러를 보내지 않아도 됨(필요하면 코드 추가)
		return
	end

	if typeof(payload) ~= "table" then
		fireError(plr, "bad_payload", "invalid payload")
		return
	end

	local targetPlaceId = tonumber(payload.targetPlaceId)
	if not targetPlaceId then
		fireError(plr, "missing_target", "targetPlaceId is required.")
		return
	end

	local sessionId = extractSessionId(plr, payload)
	if not sessionId then
		fireError(plr, "missing_sessionId", "세션 코드가 없습니다. 로비에서 입장코드를 입력하세요.")
		return
	end

	-- 세션ID + PlaceId 조합으로 예약 서버 코드 가져오기/생성
	local okCode, reservedCode, err = SessionRouter.GetOrCreate(sessionId, targetPlaceId)
	if not okCode or not reservedCode then
		fireError(plr, "reserve_failed", tostring(err))
		return
	end

	-- TeleportOptions + TeleportData 구성
	local opts = Instance.new("TeleportOptions")
	opts.ReservedServerAccessCode = reservedCode

	local tpData: {[string]: any} = {
		sessionId   = sessionId,
		reason      = (typeof(payload.reason) == "string" and payload.reason) or "route",
		device      = (typeof(payload.device) == "string" and payload.device) or "pc",
		fromPlaceId = game.PlaceId,
	}

	-- 클라에서 meta를 넘겼다면 TeleportData에 같이 실어줌 (선택)
	if typeof(payload.meta) == "table" then
		tpData.meta = payload.meta
	end

	opts:SetTeleportData(tpData)

	-- 1차 시도: TeleportAsync (ReservedServerAccessCode 사용)
	local ok, err2 = pcall(function()
		TeleportService:TeleportAsync(targetPlaceId, { plr }, opts)
	end)
	if ok then
		return
	end

	-- 실패 시 폴백: 예전 API TeleportToPrivateServer
	local okOld, errOld = pcall(function()
		TeleportService:TeleportToPrivateServer(targetPlaceId, reservedCode, { plr }, nil, tpData)
	end)
	if not okOld then
		fireError(plr, "teleport_failed", tostring(err2) .. " / " .. tostring(errOld))
	end
end)

print("[TeleportRouter] READY (TeleportUtil + SessionRouter 통합)")
