-- ServerScriptService/QuizRunService.lua
--!strict
-- 흐름 변경:
--  - 선생님이 "퀴즈 시작" → 각 참가자에게 허브 포탈 컷씬(type="hub_portal") 송신
--  - 컷씬 ACK 수신 시: 즉시 Stage1로 텔레포트
--  - (타임아웃 폴백 제거: 이제 컷씬 ACK 후에만 텔레포트)
--  - 10문제 완료 시 포탈 드롭 연출(PortalMover.SpawnAndDrop) 유지

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local TeleportService   = game:GetService("TeleportService")
local RunService        = game:GetService("RunService")

local ServerScriptService = game:GetService("ServerScriptService")
local Permissions = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("Permissions"))


local NEXT_PLACE_ID   = 99318205197051--99318205197051--92161002947426
local HUB_PORTAL_PATH = "Level.HubPortal" -- (보존) 기본 경로

-- ===== 모듈 =====
local Net         = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local QuizService = require(script.Parent:WaitForChild("QuizService"))
local PortalMover = require(script.Parent:WaitForChild("PortalMover"))
local hubStartState = require(game.ServerScriptService:WaitForChild("Modules"):WaitForChild("HubStartState"))

-- (선택) SessionRouter가 있으면 사용
local SessionRouter do
	local ok, mod = pcall(function()
		local m = script.Parent:FindFirstChild("Modules"); m = m and m:FindFirstChild("SessionRouter")
		return m and require(m)
	end)
	if ok then SessionRouter = mod end
end

-- ===== Remotes =====
local RF_Start        = Net.ensureRF("QuizRun_Start")
local RF_Submit       = Net.ensureRF("QuizRun_Submit")
local RF_GetProg      = Net.ensureRF("QuizRun_GetProgress")
local RE_Progress     = Net.ensureRE("QuizRun_Progress")
local RE_Interact     = Net.ensureRE("QuizRun_Interaction")
local RE_GroupUpdate  = Net.ensureRE("QuizRun_GroupUpdate")
local RE_Cutscene     = Net.ensureRE("Quiz_Cutscene")
local RE_CutsceneDone = Net.ensureRE("Quiz_CutsceneDone")

-- ===== 정책 =====
local TOTAL = 10
local MARK  = 4

-- ===== 상태 =====
-- state[player] = { stage,total,idx,cleared,attempts,score,order }
local state  : {[Player]: {stage:number,total:number,idx:number,cleared:number,attempts:number,score:number,order:{any}}} = {}
-- groups[stage] = { participants, completed, seed, order, spawnedNext, reservedCode?, promptRef?, promptConn? }
type G = {
	participants:{[Player]:boolean},
	completed:{[Player]:boolean},
	seed:number?,
	order:{any}?,
	spawnedNext:boolean,
	reservedCode:string?,
	promptRef: ProximityPrompt?,
	promptConn: RBXScriptConnection?
}
local groups : {[number]: G} = {}
local cutsceneDone  : {[number]: {[Player]:boolean}} = {}

-- ===== 유틸 =====
local function gOf(stage:number): G
	stage = tonumber(stage) or 1
	groups[stage] = groups[stage] or {
		participants = {},
		completed    = {},
		seed         = nil,
		order        = nil,
		spawnedNext  = false,
		reservedCode = nil,
		promptRef    = nil,
		promptConn   = nil,
	}
	return groups[stage]
end

local function sanitizeQuestionForClient(q:any)
	if not q then return nil end
	local t:any = {}
	for k,v in pairs(q) do
		if k ~= "answer" and k ~= "explain" then
			t[k] = v
		end
	end
	return t
end

local function pushProgress(pl: Player, st:any)
	RE_Progress:FireClient(pl, {
		stage    = st.stage,
		total    = st.total,
		cleared  = st.cleared,
		nextIdx  = st.idx,
		score    = st.score,
		mark     = MARK,
	})
end

local function broadcastGroup(stage:number)
	local g = gOf(stage)
	local totalP, doneP = 0, 0
	for _ in pairs(g.participants) do totalP += 1 end
	for _,ok in pairs(g.completed) do if ok then doneP += 1 end end

	for pl,_ in pairs(g.participants) do
		if pl.Parent == Players then
			RE_GroupUpdate:FireClient(pl, {
				stage       = stage,
				participants= totalP,
				completed   = doneP,
			})
		end
	end
end

local function allParticipantsDone(stage:number)
	local g = groups[stage]
	if not g then return false end
	local any = false
	for pl,_ in pairs(g.participants) do
		any = true
		if not g.completed[pl] then
			return false
		end
	end
	return any
end

local function ensureRun(pl:Player, stage:number)
	local st = state[pl]
	if st and st.stage == stage then return st end

	local g = gOf(stage)
	if not g.seed  then g.seed  = (os.time() % 10^6) + math.random(1000,9999) end
	if not g.order then g.order = QuizService.SelectTen(stage, { seed = g.seed }) end

	st = {
		stage    = stage,
		total    = TOTAL,
		idx      = 1,
		cleared  = 0,
		attempts = 0,
		score    = 0,
		order    = g.order :: {any},
	}
	state[pl] = st
	return st
end

-- (보존) 허브 포탈 ProximityPrompt 찾기 - 현재 흐름에서는 사용하지 않음
local function getHubPortalPrompt(): ProximityPrompt?
	local function findByPath(root: Instance, path: string): Instance?
		local cur: Instance = root
		for seg in string.gmatch(path, "[^%.]+") do
			cur = cur:FindFirstChild(seg)
			if not cur then return nil end
		end
		return cur
	end

	local portalRoot = findByPath(Workspace, HUB_PORTAL_PATH)
	if portalRoot then
		local inside = portalRoot:FindFirstChild("Portal_Inside")
		if inside then
			local pp = inside:FindFirstChildOfClass("ProximityPrompt")
			if pp then return pp end
		end
		local pp = portalRoot:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pp then return pp end
	end

	local candidate = Workspace:FindFirstChild("HubPortal", true)
	if candidate then
		local pp = candidate:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pp then return pp end
	end

	return nil
end

-- ===== 예약 코드 보장 (SessionRouter 미사용 폴백용) =====
local function ensureReservedForNextPlace(stage:number): string?
	local g = gOf(stage)
	if g.reservedCode and #g.reservedCode > 0 then
		return g.reservedCode
	end

	local ok, codeOrErr = pcall(function()
		return TeleportService:ReserveServer(NEXT_PLACE_ID)
	end)
	if ok and type(codeOrErr) == "string" and #codeOrErr > 0 then
		g.reservedCode = codeOrErr
		return g.reservedCode
	else
		warn("[QuizRun] ReserveServer failed:", tostring(codeOrErr))
		return nil
	end
end

-- 완료 처리(포탈 드롭 유지)
local function onPlayerFinished(pl: Player, st:any)
	local g = gOf(st.stage)
	g.completed[pl] = true
	broadcastGroup(st.stage)

	if allParticipantsDone(st.stage) then
		local nextStage = st.stage + 1
		if not g.spawnedNext then
			g.spawnedNext = true
			local targetPos = Vector3.new(-249.289, 22.578, 21.106)
			local dropTime  = 1.2

			for p,_ in pairs(g.participants) do
				if p.Parent == Players then
					RE_Cutscene:FireClient(p, {
						type      = "portal_spawn_at",
						stage     = nextStage,
						targetPos = targetPos,
						dropTime  = dropTime,
					})
				end
			end

			if PortalMover and PortalMover.SpawnAndDrop then
				PortalMover.SpawnAndDrop(nextStage, {
					targetPosition   = targetPos,
					dropHeight       = 40,
					delayBeforeDrop  = 0.2,
					dropTime         = dropTime,
				})
			end
		end

		for p,_ in pairs(g.participants) do
			if p.Parent == Players then
				RE_Interact:FireClient(p, {
					type  = "all_done",
					stage = st.stage,
					next  = nextStage,
				})
			end
		end
	else
		RE_Interact:FireClient(pl, {
			type  = "wait",
			stage = st.stage,
		})
	end
end

local function endRun(pl:Player)
	state[pl] = nil
end

-- 이동/제어
local function setFrozen(pl:Player, on:boolean)
	local ch = pl.Character
	if not ch then return end

	local hum = ch:FindFirstChildOfClass("Humanoid")
	local hrp = ch:FindFirstChild("HumanoidRootPart")

	if hum then
		if on then
			hum.WalkSpeed  = 0
			hum.JumpPower  = 0
			hum.AutoRotate = false
		else
			hum.WalkSpeed  = 16
			hum.JumpPower  = 50
			hum.AutoRotate = true
		end
	end

	if hrp then
		hrp.AssemblyLinearVelocity  = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hrp.Anchored                = on
	end
end

local TeleportDataUtil =
	require(game.ServerScriptService.Modules.TeleportDataUtil)

local function buildTeleportData(pl: Player, stage: number)
	local base = TeleportDataUtil.buildBase(pl)

	return {
		version = 3,

		player = {
			userRole  = base.player.userRole,
			isTeacher = base.player.isTeacher,
			device    = base.player.device,
			selectedStage = stage,
		},

		session = {
			id                = base.session.id,
			roomCode          = base.session.roomCode,
			fromPlaceId       = game.PlaceId,
			placeId           = NEXT_PLACE_ID,
			privateServerCode = nil, -- 나중에 채움
		},
	}
end


-- 텔레포트(세션ID 기준 동일 프라이빗 서버 보장)
local function teleportToNextPlace(pl: Player, stage: number)
	if not pl or pl.Parent ~= Players then return end
	setFrozen(pl, false)

	if RunService:IsStudio() then
		warn(("[QuizRun] (Studio) Teleport skip: %s -> %d"):format(pl.Name, NEXT_PLACE_ID))
		return
	end

	--------------------------------------------------
	-- 1) sessionId 확보 (Attribute 기준)
	--------------------------------------------------
	local sessionId: string? = nil
	local sidAttr = pl:GetAttribute("sessionId")
	if typeof(sidAttr) == "string" and #sidAttr > 0 then
		sessionId = sidAttr
	end

	--------------------------------------------------
	-- 2) SessionRouter.GetOrCreate 로 예약 코드 확보
	--------------------------------------------------
	local reservedCode: string? = nil

	if SessionRouter and sessionId and sessionId ~= "" then
		-- SessionRouter 자체가 이미 pcall을 내부에서 쓰기 때문에
		-- 여기서는 그냥 직접 결과만 받으면 됨
		local okCode, code, err = SessionRouter.GetOrCreate(sessionId :: string, NEXT_PLACE_ID)

		if okCode and type(code) == "string" and #code > 0 then
			reservedCode = code
			print(("[QuizRun] SessionRouter OK sid=%s, place=%d, code=%s"):
				format(tostring(sessionId), NEXT_PLACE_ID, code))
		else
			warn(("[QuizRun] SessionRouter failed sid=%s, err=%s"):
				format(tostring(sessionId), tostring(err)))
		end
	end

	--------------------------------------------------
	-- 3) SessionRouter가 없거나 실패하면, 기존 ReserveServer 폴백
	--------------------------------------------------
	if not reservedCode then
		reservedCode = ensureReservedForNextPlace(stage)
		if reservedCode then
			warn("[QuizRun] fallback ReserveServer (no SessionRouter mapping)")
		end
	end

	--------------------------------------------------
	-- 4) TeleportData 구성 (session.id 포함)
	--------------------------------------------------
	local tpData:any = buildTeleportData(pl, stage)

	-- 세션 정보(있으면)
	tpData.session = {
		id                = sessionId,
		fromPlaceId       = game.PlaceId,
		placeId           = NEXT_PLACE_ID,
		privateServerCode = reservedCode,
	}

	if reservedCode then
		tpData.reservedCodes = tpData.reservedCodes or {}
		tpData.reservedCodes[tostring(NEXT_PLACE_ID)] = reservedCode
	else
		warn("[QuizRun] No ReservedServer code → public server teleport (same-server not guaranteed).")
	end

	local opts = Instance.new("TeleportOptions")
	if reservedCode then
		opts.ReservedServerAccessCode = reservedCode
	end
	opts:SetTeleportData(tpData)

	--------------------------------------------------
	-- 5) 실제 텔레포트
	--------------------------------------------------
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(NEXT_PLACE_ID, { pl }, opts)
	end)
	if not ok then
		warn(("[QuizRun] Teleport failed: %s : %s"):format(pl.Name, tostring(err)))
	end
end

-- ===== 포탈 프롬프트 바인딩(보존용, 현재 흐름에선 미사용) =====
local function ensureHubPromptBound(stage:number)
	local g = gOf(stage)
	if g.promptConn and g.promptRef then return end

	local pp = getHubPortalPrompt()
	if not pp then
		warn("[QuizRun] HubPortal ProximityPrompt not found")
		return
	end

	pp.Enabled  = false
	g.promptRef = pp

	g.promptConn = pp.Triggered:Connect(function(plr: Player)
		if not g.participants[plr] then return end
		if not (cutsceneDone[stage] and cutsceneDone[stage][plr]) then
			return
		end
		if state[plr] == nil then
			-- 이미 텔레포트가 진행 중일 수 있음
		end
		teleportToNextPlace(plr, stage)
	end)
end

-- ===== 공개 API =====
local M = {}

-- 선생님이 "퀴즈 시작" 눌렀을 때 호출
function M.StartCohort(stage:number, playersList:{Player}? )
	stage = tonumber(stage) or 1
	local list = playersList or Players:GetPlayers()

	local g = gOf(stage)
	g.participants = {}
	g.completed    = {}
	g.seed         = (os.time() % 10^6) + math.random(1000,9999)
	g.order        = QuizService.SelectTen(stage, { seed = g.seed })
	g.spawnedNext  = false
	cutsceneDone[stage]  = {}

	-- (보존용) 다음 플레이스 예약 코드 미리 확보 (SessionRouter 미사용 시에만 의미 있음)
	ensureReservedForNextPlace(stage)

	print(("[QuizRun] StartCohort stage=%d participants=%d"):format(stage, #list))
	
	do
		
		local teacher: Player? = nil
		for _, pl in ipairs(list) do
			if Permissions.isTeacher(pl) then
				teacher = pl
				break
			end
		end
		
		local sid = teacher and teacher:GetAttribute("sessionId")
		if typeof(sid) == "string" and #sid > 0 then
			hubStartState.SetStarted(sid)
		else
			-- 선생님 sessionId가 없을 수도 있으니, 참가자 중 아무나로 폴백
			for _,pl in ipairs(list) do
				local s = pl:GetAttribute("sessionId")
				if typeof(s) == "string" and #s > 0 then
					hubStartState.SetStarted(s)
					break
				end
			end
		end
	end
	
	for _,pl in ipairs(list) do
		if pl and pl.Parent == Players then
			setFrozen(pl, true)
			g.participants[pl] = true
			g.completed[pl]    = false

			-- 허브 포탈 "활성화" 컷씬(문 열기 X)
			RE_Cutscene:FireClient(pl, {
				type       = "hub_portal",
				stage      = stage,
				portalPath = HUB_PORTAL_PATH,
				--camera = {
				--	flip    = true,
				--	dist    = 20,
				--	height  = 7,
				--	side    = 0,
				--	dollyIn = 5,
				--	dur     = 0.5,
				--},
			})

			-- 🔸 타임아웃 폴백 제거:
			-- 컷씬이 끝난 뒤, 클라이언트에서 Quiz_CutsceneDone RE 로 ACK 보낼 때만 텔레포트.
		end
	end
end

RE_CutsceneDone.OnServerEvent:Connect(function(player, payload)
	local stage = tonumber(payload and payload.stage) or 1

	-- ✅ 중복 텔레포트 방지 (ACK 중복/네트워크 재전송 방어)
	if player:GetAttribute("TeleportingToStage1") == true then
		return
	end

	local g = groups[stage]
	local isParticipant = (g ~= nil and g.participants[player] == true)

	-- ✅ 참가자가 아니면 "세션 시작됨"인지로 복구 판단
	if not isParticipant then
		local sid = player:GetAttribute("sessionId")
		local started = false
		if typeof(sid) == "string" and #sid > 0 then
			started = hubStartState.IsStarted(sid)
		end

		if not started then
			warn("[QuizRun] ACK but not in cohort and not started:", player.Name)
			return
		end

		-- started면 stage는 1로 고정(허브→Stage1 라우팅 목적)
		stage = 1
		g = gOf(stage)
	end

	-- ✅ 컷씬 완료 체크 (그룹이 있는 경우만 기록)
	cutsceneDone[stage] = cutsceneDone[stage] or {}
	if cutsceneDone[stage][player] then return end
	cutsceneDone[stage][player] = true

	player:SetAttribute("TeleportingToStage1", true)

	-- ✅ 컷씬 끝남 → 텔레포트
	teleportToNextPlace(player, stage)
end)

-- ===== 퀴즈 RF =====
RF_Start.OnServerInvoke = function(pl: Player, stage:number)
	stage = tonumber(stage) or 1
	local g = gOf(stage)
	if not g.participants[pl] then
		return { ok=false, error="not_in_cohort" }
	end

	local st = ensureRun(pl, stage)
	local q  = st.order[st.idx]
	pushProgress(pl, st)

	return {
		ok       = true,
		error    = nil,
		question = sanitizeQuestionForClient(q),
		total    = st.total,
	}
end

RF_Submit.OnServerInvoke = function(pl: Player, payload:any)
	local stage = tonumber(payload.stage) or 1
	local g = gOf(stage)
	if not g.participants[pl] then
		return { ok=false, error="not_in_cohort" }
	end

	local st = ensureRun(pl, stage)
	local q  = st.order[st.idx]
	if not q then
		return { ok=false, error="no_question" }
	end

	if payload.qid and q.id and tostring(payload.qid) ~= tostring(q.id) then
		return { ok=false, error="stale_question" }
	end

	st.attempts += 1
	local ans = payload.answer
	local correct = false

	if q.type == "ox" then
		correct = tostring(ans):upper() == tostring(q.answer):upper()
	elseif q.type == "mc" then
		correct = tonumber(ans) == tonumber(q.answer)
	else
		local function norm(s:string?): string
			return (tostring(s or ""):gsub("%s+",""):lower())
		end
		correct = norm(ans) == norm(q.answer)
	end

	if correct then
		-- 시도 횟수별 점수
		st.score += (st.attempts <= 1 and 10)
			or (st.attempts == 2 and 8)
			or (st.attempts == 3 and 6)
			or 4

		st.cleared += 1

		if st.cleared == MARK then
			RE_Interact:FireClient(pl, { type="mid", stage=stage, cleared=st.cleared })
		end

		if st.cleared >= st.total then
			pushProgress(pl, st)
			onPlayerFinished(pl, st)
			state[pl] = nil
			return {
				ok      = true,
				error   = nil,
				correct = true,
				done    = true,
				score   = st.score,
			}
		end

		st.idx      += 1
		st.attempts  = 0
		local nxt    = st.order[st.idx]
		pushProgress(pl, st)

		return {
			ok           = true,
			error        = nil,
			correct      = true,
			done         = false,
			nextQuestion = sanitizeQuestionForClient(nxt),
			score        = st.score,
		}
	else
		pushProgress(pl, st)
		return {
			ok       = true,
			error    = nil,
			correct  = false,
			attempts = st.attempts,
		}
	end
end

RF_GetProg.OnServerInvoke = function(pl: Player)
	local st = state[pl]
	if not st then
		return { ok=true, error=nil, idle=true }
	end
	return {
		ok      = true,
		error   = nil,
		stage   = st.stage,
		cleared = st.cleared,
		total   = st.total,
		nextIdx = st.idx,
		score   = st.score,
		mark    = MARK,
	}
end

-- ===== 이탈 정리 =====
Players.PlayerRemoving:Connect(function(pl: Player)
	state[pl] = nil
	for stage,g in pairs(groups) do
		if g.participants[pl] ~= nil then
			g.participants[pl] = nil
			g.completed[pl]    = nil
			broadcastGroup(stage)
		end
	end
end)

print("[QuizRunService] READY (hub_portal cutscene → ACK 후 텔레포트)")
return M
