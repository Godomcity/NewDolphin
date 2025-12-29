-- ServerScriptService/LobbyResumeBootstrap.server.lua
--!strict
-- 로비에 접속한 플레이어가 이전에 진행하던 세션/스테이지가 있으면
-- 같은 세션의 같은 프라이빗 서버로 자동 텔레포트 + 디버그 로그

local Players           = game:GetService("Players")
local TeleportService   = game:GetService("TeleportService")

local RS = game:GetService("ReplicatedStorage")

local SessionResume = require(script.Parent:WaitForChild("Modules"):WaitForChild("SessionResume"))
local SessionRouter = require(script.Parent:WaitForChild("Modules"):WaitForChild("SessionRouter"))

local RESUME_EXPIRE_SEC = 60 * 30 -- 30분

local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local RE_Gui = Remotes:FindFirstChild("RE_LobbyResume_TeleportingGui")
if not RE_Gui then
	RE_Gui = Instance.new("RemoteEvent")
	RE_Gui.Name = "RE_LobbyResume_TeleportingGui"
	RE_Gui.Parent = Remotes
end

local function buildTeleportDataForResume(sessionId: string, device: string, placeId: number, reservedCode: string?, stage: number?)
	return {
		version = 2,
		session = {
			id = sessionId,
			placeId = placeId,
			privateServerCode = reservedCode,
		},
		player = {
			device = device,
		},
		selectedStage = stage or 1,
		reservedCodes = {
			[tostring(placeId)] = reservedCode,
		},
		reason = "resume",
	}
end

local function tryAutoResume(player: Player)
	print(string.format("[LobbyResume] tryAutoResume start. LobbyJobId=%s player=%s", game.JobId, player.Name))

	local resume = SessionResume.Get(player.UserId)
	print("[LobbyResume] Resume data:", resume)

	if not resume then
		-- ✅ 재입장 없음 → TeleportingGui 종료
		RE_Gui:FireClient(player, { mode = "hide", reason = "no_resume" })
		print("[LobbyResume] no resume data, stay in lobby")
		return
	end

	if resume.updatedAt and os.time() - resume.updatedAt > RESUME_EXPIRE_SEC then
		SessionResume.Clear(player.UserId)
		-- ✅ 만료 → 종료
		RE_Gui:FireClient(player, { mode = "hide", reason = "resume_expired" })
		print("[LobbyResume] resume expired, clear and ignore")
		return
	end
	
	RE_Gui:FireClient(player, { mode = "show", reason = "resume_found" })
	
	local sessionId     = resume.sessionId
	local targetPlaceId = resume.placeId
	local stage         = resume.stage

	if not sessionId or not targetPlaceId then
		print("[LobbyResume] invalid resume fields, stay in lobby")
		return
	end

	-- 한 번 사용한 Resume 정보는 바로 제거
	SessionResume.Clear(player.UserId)

	print(string.format(
		"[LobbyResume] GetOrCreate sid=%s pid=%d for player=%s",
		sessionId, targetPlaceId, player.Name
		))

	local okCode, reservedCode, err = SessionRouter.GetOrCreate(sessionId, targetPlaceId)
	print("[LobbyResume] GetOrCreate result:", okCode, reservedCode, err)

	if not okCode or not reservedCode then
		warn("[LobbyResume] Reserve/Get code failed:", err)
		return
	end

	-- device 추출 (이전 TeleportData에서 가져오거나 기본 desktop)
	local device = "desktop"
	local okJD, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if okJD and typeof(joinData) == "table" then
		local td = joinData.TeleportData
		if typeof(td) == "table" and typeof((td :: any).player) == "table" then
			local dev = (td :: any).player.device
			if typeof(dev) == "string" then
				device = dev
			end
		end
	end

	local tpData = buildTeleportDataForResume(sessionId, device, targetPlaceId, reservedCode, stage)

	local opts = Instance.new("TeleportOptions")
	opts.ReservedServerAccessCode = reservedCode
	opts:SetTeleportData(tpData)

	print(string.format(
		"[LobbyResume] TeleportAsync to pid=%d reservedCode=%s from LobbyJobId=%s player=%s",
		targetPlaceId, tostring(reservedCode), game.JobId, player.Name
		))

	local okTp, tpErr = pcall(function()
		TeleportService:TeleportAsync(targetPlaceId, { player }, opts)
	end)

	if not okTp then
		warn("[LobbyResume] TeleportAsync failed, fallback to TeleportToPrivateServer:", tpErr)

		local okOld, errOld = pcall(function()
			TeleportService:TeleportToPrivateServer(
				targetPlaceId,
				reservedCode,
				{ player },
				nil,
				tpData
			)
		end)

		if not okOld then
			warn("[LobbyResume] TeleportToPrivateServer failed as well:", errOld)
		end
	end
end

Players.PlayerAdded:Connect(function(player: Player)
	task.delay(2, function()
		if not player.Parent then
			return
		end

		tryAutoResume(player)
	end)
end)

print("[LobbyResumeBootstrap] READY (debug)")
