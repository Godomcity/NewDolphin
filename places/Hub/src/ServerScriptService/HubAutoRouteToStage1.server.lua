-- ServerScriptService/HubAutoRouteToStage1.server.lua
--!strict
-- Hub 재입장 시: HubStartState(started=true)면 즉시 Stage1로 텔레포트
-- ✅ (추가) 재입장자는 QuizStartCountStore count +1 (1회만)

local Players          = game:GetService("Players")
local TeleportService  = game:GetService("TeleportService")
local RunService       = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local HubStartState = require(game.ServerScriptService:WaitForChild("Modules"):WaitForChild("HubStartState"))

-- ✅ 추가: 인원수 저장 모듈
local QuizStartCountStore = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("QuizStartCountStore"))

-- (선택) SessionRouter가 있으면 사용 (세션 프라이빗 서버 유지)
local SessionRouter do
	local ok, mod = pcall(function()
		return require(game.ServerScriptService:WaitForChild("Modules"):WaitForChild("SessionRouter"))
	end)
	if ok then SessionRouter = mod end
end

--local TEACHER_USER_ID = 2783482612
local STAGE1_PLACE_ID = 99318205197051

local function getSessionId(plr: Player): string?
	local sid = plr:GetAttribute("sessionId")
	if typeof(sid) == "string" and #sid > 0 then
		return sid
	end
	return nil
end

local function teleportStage1(plr: Player, sessionId: string)
	if plr:GetAttribute("HubAutoRoutedToStage1") == true then return end
	plr:SetAttribute("HubAutoRoutedToStage1", true)

	----------------------------------------------------------------
	-- ✅ (추가) “재입장 카운트 +1” (중복 방지 포함)
	-- started=true인 상태에서 Hub로 다시 들어온 순간을 “재입장”으로 보고 +1
	----------------------------------------------------------------
	--do
	--	local okInc, errInc, didInc = QuizStartCountStore.IncrementOnRejoinOnce(
	--		sessionId,
	--		1, -- Stage1
	--		TEACHER_USER_ID,
	--		plr.UserId,
	--		3
	--	)

	--	if not okInc then
	--		warn("[HubAutoRoute] IncrementOnRejoinOnce failed:", errInc)
	--		-- 실패해도 텔포는 계속 진행
	--	elseif didInc then
	--		print(("[HubAutoRoute] rejoin count +1 sid=%s uid=%d"):format(sessionId, plr.UserId))
	--	end
	--end

	if RunService:IsStudio() then
		warn(("[HubAutoRoute] (Studio) Teleport skip: %s -> %d"):format(plr.Name, STAGE1_PLACE_ID))
		return
	end

	-- 1) reservedCode 확보 (세션 유지 우선)
	local reservedCode = nil
	if SessionRouter then
		local okCode, code, err = SessionRouter.GetOrCreate(sessionId, STAGE1_PLACE_ID)
		if okCode and type(code) == "string" and #code > 0 then
			reservedCode = code
		else
			warn("[HubAutoRoute] SessionRouter failed:", err)
		end
	end

	-- 2) 폴백: ReserveServer
	if not reservedCode then
		local ok, codeOrErr = pcall(function()
			return TeleportService:ReserveServer(STAGE1_PLACE_ID)
		end)
		if ok and type(codeOrErr) == "string" and #codeOrErr > 0 then
			reservedCode = codeOrErr
		else
			warn("[HubAutoRoute] ReserveServer failed:", codeOrErr)
			plr:SetAttribute("HubAutoRoutedToStage1", false)
			return
		end
	end

	-- 3) TeleportData
	local opts = Instance.new("TeleportOptions")
	opts.ReservedServerAccessCode = reservedCode
	opts:SetTeleportData({
		version = 1,
		reason = "hub_rejoin_started_true",
		sessionId = sessionId,
		privateServerCode = reservedCode,
		fromPlaceId = game.PlaceId,
	})

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(STAGE1_PLACE_ID, { plr }, opts)
	end)
	if not ok then
		warn("[HubAutoRoute] TeleportAsync failed:", err)
		plr:SetAttribute("HubAutoRoutedToStage1", false)
	end
end

Players.PlayerAdded:Connect(function(plr: Player)
	task.defer(function()
		local sid = getSessionId(plr)
		if not sid then return end

		local started = HubStartState.IsStarted(sid)
		if started then
			teleportStage1(plr, sid)
		end
	end)
end)

print("[HubAutoRouteToStage1] READY")
