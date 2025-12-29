-- ServerScriptService/StageQuizResultService.lua
--!strict
-- 각 스테이지에서 클라가 보낸 퀴즈 결과(score/time)를
-- ★ 세션ID(sessionId) + stageIndex 기준으로 StageMultiResultStore에 저장

local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local Players              = game:GetService("Players")
local ServerScriptService  = game:GetService("ServerScriptService")

local StageResultStore = require(ServerScriptService.Modules:WaitForChild("StageMultiResultStore"))

----------------------------------------------------------------
-- ★ 여기만 스테이지마다 다르게 설정!
----------------------------------------------------------------
local STAGE_INDEX = 5 -- Stage1=1, Stage2=2, ... Stage5=5

----------------------------------------------------------------
-- Remotes 준비
----------------------------------------------------------------
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

-- (1) 최종 결과용: 클라에서 RE_StageQuizResult:FireServer(score, timeSec)
local RE_StageQuizResult = Remotes:FindFirstChild("RE_StageQuizResult")
if not RE_StageQuizResult then
	RE_StageQuizResult = Instance.new("RemoteEvent")
	RE_StageQuizResult.Name = "RE_StageQuizResult"
	RE_StageQuizResult.Parent = Remotes
end

-- (2) 런타임(매 문제마다) 저장용: 클라에서 RE_Stage1_QuizRuntime:FireServer(score, timeSec)
local RE_Stage1_QuizRuntime = Remotes:FindFirstChild("RE_Stage1_QuizRuntime")
if not RE_Stage1_QuizRuntime then
	RE_Stage1_QuizRuntime = Instance.new("RemoteEvent")
	RE_Stage1_QuizRuntime.Name = "RE_Stage1_QuizRuntime"
	RE_Stage1_QuizRuntime.Parent = Remotes
end

----------------------------------------------------------------
-- Player:GetJoinData() 에서 TeleportData 읽어서 세션ID/스테이지 인덱스 Attribute로 보정
-- (SessionBootstrap가 이미 sessionId를 Attribute에 넣어줬다면, 여기서는 보정만 하는 정도)
----------------------------------------------------------------
local function extractSessionIdFromJoinData(player: Player): string?
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then
		return nil
	end

	local td = joinData.TeleportData
	if typeof(td) ~= "table" then
		return nil
	end

	-- ① 예전 구조: TeleportData.sessionId
	if typeof(td.sessionId) == "string" and #td.sessionId > 0 then
		return td.sessionId
	end

	-- ② 지금 구조: TeleportData.session.id
	local sess = (td :: any).session
	if typeof(sess) == "table" and typeof(sess.id) == "string" and #sess.id > 0 then
		return sess.id
	end

	return nil
end

local function applyTeleportDataToPlayer(player: Player)
	-- sessionId Attribute 보정
	if not player:GetAttribute("sessionId") then
		local sid = extractSessionIdFromJoinData(player)
		if sid and sid ~= "" then
			player:SetAttribute("sessionId", sid)
		end
	end

	-- stageIndex Attribute 보정
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then
		return
	end

	local td = joinData.TeleportData
	if typeof(td) ~= "table" then
		return
	end

	local stageIndex = (td :: any).stageIndex
	if type(stageIndex) == "number" then
		player:SetAttribute("StageIndex", stageIndex)
	else
		player:SetAttribute("StageIndex", STAGE_INDEX)
	end
end

Players.PlayerAdded:Connect(function(player)
	applyTeleportDataToPlayer(player)
end)

----------------------------------------------------------------
-- 공통 저장 함수: 최종/런타임 둘 다 여기로
----------------------------------------------------------------
local function saveResultFromClient(player: Player, scoreAny: any, timeAny: any, sourceTag: string)
	if not player or player.UserId <= 0 then
		return
	end

	-- ★ sessionId 우선 Attribute에서 읽고, 없으면 JoinData에서 시도
	local sessionId = player:GetAttribute("sessionId")
	if not sessionId or sessionId == "" then
		sessionId = extractSessionIdFromJoinData(player)
		if sessionId and sessionId ~= "" then
			player:SetAttribute("sessionId", sessionId)
		end
	end

	if not sessionId or sessionId == "" then
		warn("[StageQuizResultService] Player", player.Name, "has no sessionId, skip (source:", sourceTag, ")")
		return
	end

	local stageIndexAttr = player:GetAttribute("StageIndex")
	local stageIndex = STAGE_INDEX
	if typeof(stageIndexAttr) == "number" then
		stageIndex = stageIndexAttr
	end

	local score = (typeof(scoreAny) == "number") and scoreAny or 0
	local timeSec = (typeof(timeAny) == "number") and timeAny or 0

	if score < 0 then score = 0 end
	if timeSec < 0 then timeSec = 0 end

	print(string.format(
		"[StageQuizResultService][%s] sessionId=%s, stage=%d, player=%s, score=%d, time=%ds",
		sourceTag,
		tostring(sessionId),
		stageIndex,
		player.Name,
		score,
		timeSec
		))

	-- ★ 첫 번째 인자로 sessionId 전달 (StageMultiResultStore에서는 그냥 "키"로 쓰면 됨)
	StageResultStore.SaveStageResult(sessionId, stageIndex, player, score, timeSec)
end

----------------------------------------------------------------
-- RemoteEvent 핸들러: 클라 → 서버 결과 보고
----------------------------------------------------------------

-- ① 예전처럼 "10문제 완료 시" 최종 결과
RE_StageQuizResult.OnServerEvent:Connect(function(player: Player, scoreAny: any, timeAny: any)
	saveResultFromClient(player, scoreAny, timeAny, "Final")
end)

-- ② 새로 추가: "정답 맞출 때마다" 들어오는 런타임 결과
RE_Stage1_QuizRuntime.OnServerEvent:Connect(function(player: Player, scoreAny: any, timeAny: any)
	saveResultFromClient(player, scoreAny, timeAny, "Runtime")
end)

print("[StageQuizResultService] READY (StageIndex =", STAGE_INDEX, ", key=sessionId, RuntimeSave=ON)")
