-- ServerScriptService/HubService.lua
--!strict
-- 선생님이 [퀴즈 시작] → 현재 접속자 "전원" 코호트로 고정, 시작 신호 발사
-- + QuizStartCountStore에 "선생님 제외 인원" 저장

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local SoundService         = game:GetService("SoundService")
local ServerScriptService  = game:GetService("ServerScriptService")

local Net        = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local QuizRun    = require(script.Parent:WaitForChild("QuizRunService"))
local PortalUtil = require(script.Parent:WaitForChild("PortalUtil"))

-- ✅ 권한 모듈 (핵심)
local Permissions = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("Permissions"))

-- ✅ 인원수 저장 모듈
local QuizStartCountStore = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("QuizStartCountStore"))

local RF_OpenStage   = Net.ensureRF("Hub_OpenStage")
local RE_PortalState = Net.ensureRE("Hub_PortalState")

-- ★ 퀴즈 시작 사운드
local QUIZ_START_SFX_ID = "rbxassetid://131845870598154"

local quizStartSound = SoundService:FindFirstChild("QuizStartSfx")
if not quizStartSound then
	quizStartSound = Instance.new("Sound")
	quizStartSound.Name = "QuizStartSfx"
	quizStartSound.SoundId = QUIZ_START_SFX_ID
	quizStartSound.Volume = 1
	quizStartSound.RollOffMode = Enum.RollOffMode.Inverse
	quizStartSound.Parent = SoundService
end

local function setPortalOpen(stage: number, open: boolean)
	PortalUtil.SetPortalOpen(stage, open)
	RE_PortalState:FireAllClients(stage, open)
end

-- 기본: Stage1 포탈은 닫힘
setPortalOpen(1, false)

-- ✅ sessionId 추출 (Attribute 기준)
local function getSessionId(plr: Player): string?
	local sid = plr:GetAttribute("sessionId")
	if typeof(sid) == "string" and sid ~= "" then
		return sid
	end
	return nil
end

----------------------------------------------------------------
-- 🟢 메인: 스테이지 오픈 요청
----------------------------------------------------------------
RF_OpenStage.OnServerInvoke = function(player: Player, stage: any)
	stage = tonumber(stage) or 1

	-- ✅ 교사 권한 확인 (단일 진실)
	if not Permissions.requireTeacher(player) then
		return { ok = false, error = "forbidden" }
	end

	-- ✅ 세션 아이디 확보
	local sessionId = getSessionId(player)
	if not sessionId then
		warn("[HubService] missing sessionId on teacher:", player.Name)
		return { ok = false, error = "missing_sessionId" }
	end

	-- 현재 접속자 전원
	local players = Players:GetPlayers()

	----------------------------------------------------------------
	-- ✅ 퀴즈 시작 시점 인원 수 저장 (교사 제외)
	----------------------------------------------------------------
	do
		local okSave, errSave, count = QuizStartCountStore.SaveFromPlayers(
			sessionId,
			stage,
			nil,        -- ❗ UserId 기반 제외 제거
			players,
			true,       -- overwrite
			3           -- retries
		)

		if not okSave then
			warn("[HubService] QuizStartCountStore.SaveFromPlayers failed:", errSave)
		else
			print(("[HubService] saved start count sid=%s stage=%d count=%s")
				:format(sessionId, stage, tostring(count)))
		end
	end

	-- ★ 퀴즈 시작 사운드
	if stage == 1 and quizStartSound then
		quizStartSound.TimePosition = 0
		quizStartSound:Play()
	end

	-- 포탈 오픈
	setPortalOpen(stage, true)

	-- ✅ 실제 코호트 시작
	QuizRun.StartCohort(stage, players)

	return { ok = true, sessionId = sessionId, stage = stage }
end
