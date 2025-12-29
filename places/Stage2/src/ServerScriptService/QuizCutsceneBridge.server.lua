-- ServerScriptService/QuizCutsceneBridge.server.lua
--!strict
local RS = game:GetService("ReplicatedStorage")

-- Remotes 보장
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then Remotes = Instance.new("Folder"); Remotes.Name = "Remotes"; Remotes.Parent = RS end
local function ensureRE(name: string)
	local re = Remotes:FindFirstChild(name)
	if not re then re = Instance.new("RemoteEvent"); re.Name = name; re.Parent = Remotes end
	return re
end
local RE_CutsceneReq  = ensureRE("Quiz_CutsceneRequest") -- C->S
local RE_Cutscene     = ensureRE("Quiz_Cutscene")        -- S->C
local RE_CutsceneDone = ensureRE("Quiz_CutsceneDone")    -- C->S (선택)

local lastAt: {[number]: number} = {}

RE_CutsceneReq.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then return end
	if payload.reason ~= "quiz4" then return end

	local now = os.clock()
	if (lastAt[player.UserId] or 0) + 2 > now then return end
	lastAt[player.UserId] = now

	local stage = tonumber(payload.stage) or 1
	RE_Cutscene:FireClient(player, { type = "portal_open", stage = stage })
end)

RE_CutsceneDone.OnServerEvent:Connect(function(player, _)
	print(("[CutsceneDone] %s"):format(player.Name))
	-- 필요시 텔레포트/다음 단계 처리
end)

print("[QuizCutsceneBridge] READY")
