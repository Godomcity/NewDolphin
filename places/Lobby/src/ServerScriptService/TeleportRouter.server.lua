-- ServerScriptService/TeleportRouter.server.lua
--!strict
-- 클라이언트: Remotes.Teleport_Request:FireServer({ targetPlaceId=..., sessionId?=..., reason?, device? })
-- 서버: SessionRouter로 예약코드 확보 → TeleportAsync(ReservedServerAccessCode) 실행
-- 실패 시 TeleportToPrivateServer로 1회 폴백

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
local REQ = Remotes:FindFirstChild("Teleport_Request") or Instance.new("RemoteEvent")
REQ.Name = "Teleport_Request"
REQ.Parent = Remotes

local RES = Remotes:FindFirstChild("Teleport_Result") or Instance.new("RemoteEvent")
RES.Name = "Teleport_Result"
RES.Parent = Remotes

-- 간단 쿨다운
local COOLDOWN = 2.0
local lastTick: {[number]: number} = {}
local function can(plr: Player): boolean
	local now = os.clock()
	local prev = lastTick[plr.UserId] or 0
	if (now - prev) < COOLDOWN then return false end
	lastTick[plr.UserId] = now
	return true
end

local function extractSessionId(plr: Player, payload: any): string?
	-- 1) payload.sessionId
	if typeof(payload) == "table" and typeof(payload.sessionId) == "string" and #payload.sessionId > 0 then
		return payload.sessionId
	end
	-- 2) Player Attribute
	local sidAttr = plr:GetAttribute("sessionId")
	if typeof(sidAttr) == "string" and #sidAttr > 0 then
		return sidAttr
	end
	return nil
end

REQ.OnServerEvent:Connect(function(plr: Player, payload: any)
	if not plr or not plr.Parent then return end
	if not can(plr) then return end

	local targetPlaceId = (typeof(payload) == "table" and tonumber(payload.targetPlaceId)) or nil
	if not targetPlaceId then
		RES:FireClient(plr, { ok=false, code="missing_target", msg="targetPlaceId is required." })
		return
	end

	local sessionId = extractSessionId(plr, payload)
	if not sessionId then
		RES:FireClient(plr, { ok=false, code="missing_sessionId", msg="세션 코드가 없습니다. 로비에서 입장코드를 입력하세요." })
		return
	end

	local okCode, reservedCode, err = SessionRouter.GetOrCreate(sessionId, targetPlaceId)
	if not okCode or not reservedCode then
		RES:FireClient(plr, { ok=false, code="reserve_failed", msg=tostring(err) })
		return
	end

	local opts = Instance.new("TeleportOptions")
	opts.ReservedServerAccessCode = reservedCode
	opts:SetTeleportData({
		sessionId   = sessionId,
		reason      = (typeof(payload)=="table" and payload.reason) or "route",
		device      = (typeof(payload)=="table" and payload.device) or "pc",
		fromPlaceId = game.PlaceId,
	})

	local ok, err2 = pcall(function()
		TeleportService:TeleportAsync(targetPlaceId, { plr }, opts)
	end)
	if not ok then
		-- 폴백(구 API)
		local okOld, errOld = pcall(function()
			TeleportService:TeleportToPrivateServer(targetPlaceId, reservedCode, { plr }, nil, { sessionId = sessionId })
		end)
		if not okOld then
			RES:FireClient(plr, { ok=false, code="teleport_failed", msg=tostring(err2).." / "..tostring(errOld) })
		end
	end
end)

print("[TeleportRouter] READY")
