-- ServerScriptService/QuizApiService.server.lua
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(RS:WaitForChild("Modules"):WaitForChild("Net"))
local RE_CutsceneReq = Net.ensureRE("Quiz_CutsceneRequest") -- 클라→서버
local RE_Cutscene    = Net.ensureRE("Quiz_Cutscene")        -- 서버→클라

local COOL = 2
local last = {}

local function stageFrom(payload)
	local s = (payload and payload.stage) or 1
	s = tonumber(s) or 1
	return s < 1 and 1 or s
end

RE_CutsceneReq.OnServerEvent:Connect(function(plr, payload)
	local now = os.clock()
	if last[plr] and now - last[plr] < COOL then return end
	last[plr] = now

	local stage = stageFrom(payload)
	print(string.format("[QuizAPI] CUTSCENE FIRE: uid=%d stage=%s", plr.UserId, tostring(stage)))
	RE_Cutscene:FireClient(plr, { type = "portal_open", stage = stage })
end)

Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
