-- ServerScriptService/QuizRemoteService.server.lua
--!strict
local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local QuizProvider = require(script.Parent:WaitForChild("Modules"):WaitForChild("QuizProvider"))
local SessionProgress = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("SessionProgress"))

local STAGE_INDEX = 4

local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local function ensureRF(name: string): RemoteFunction
	local rf = Remotes:FindFirstChild(name)
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = Remotes
	end
	return rf :: RemoteFunction
end

local RF_Get   = ensureRF("RF_Quiz_GetQuestion")
local RF_Check = ensureRF("RF_Quiz_CheckAnswer")

-- (선택) 접속 시 커서 초기화
Players.PlayerAdded:Connect(function(plr)
	pcall(function() QuizProvider.ResetPlayer(plr) end)
end)

RF_Get.OnServerInvoke = function(plr: Player, solvedList: any?)
	local ok, dto = pcall(function()
		-- ★ solvedList 를 QuizProvider 로 넘겨줌
		return QuizProvider.GetNextQuestion(plr, solvedList)
	end)
	if not ok then
		warn("[QuizRemoteService] GetNextQuestion error:", dto)
		return nil
	end
	-- 클라가 기대: {id=string, q=string, c={string}} 또는 nil
	return dto
end

RF_Check.OnServerInvoke = function(plr: Player, qid: any, choiceIndex: any)
	if typeof(qid) ~= "string" then return { correct = false, reason = "bad_qid" } end
	if typeof(choiceIndex) ~= "number" then return { correct = false, reason = "bad_choice" } end
	if choiceIndex < 1 or choiceIndex > 4 then return { correct = false, reason = "out_of_range" } end

	local ok, res = pcall(function()
		return QuizProvider.CheckAnswer(plr, qid, choiceIndex)
	end)
	if not ok then
		warn("[QuizRemoteService] CheckAnswer error:", res)
		return { correct = false, reason = "server_error" }
	end

	local isCorrect = (res and res.correct == true)

	-- ★ 정답이면 SessionProgress에 기록
	if isCorrect then
		local sid = plr:GetAttribute("sessionId")
		if type(sid) == "string" and sid ~= "" then
			SessionProgress.MarkQuizSolved(sid, STAGE_INDEX, qid)
		end
	end

	return { correct = isCorrect }
end

print("[QuizRemoteService] READY: RF_Quiz_GetQuestion / RF_Quiz_CheckAnswer")
