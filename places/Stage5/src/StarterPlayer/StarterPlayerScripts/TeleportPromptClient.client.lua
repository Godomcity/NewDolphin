-- StarterPlayerScripts/TeleportPromptClient.client.lua
--!strict

local Players                = game:GetService("Players")
local RS                     = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService      = game:GetService("CollectionService")
local UserInputService       = game:GetService("UserInputService")
local Workspace              = game:GetService("Workspace")

local LP = Players.LocalPlayer

local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = RS

local RE_FinalJumpEnter = Remotes:FindFirstChild("FinalJump_Enter") :: RemoteEvent?
if not RE_FinalJumpEnter then
	RE_FinalJumpEnter = Instance.new("RemoteEvent")
	RE_FinalJumpEnter.Name = "FinalJump_Enter"
	RE_FinalJumpEnter.Parent = Remotes
end

-- (선택) 서버가 "전원 도착" 알림을 쏘면 받기 위한 RE
-- 서버에서: Remotes.FinalJump_AllArrived:FireAllClients() 같은 식으로 사용
local RE_AllArrived = Remotes:FindFirstChild("FinalJump_AllArrived") :: RemoteEvent?
if not RE_AllArrived then
	RE_AllArrived = Instance.new("RemoteEvent")
	RE_AllArrived.Name = "FinalJump_AllArrived"
	RE_AllArrived.Parent = Remotes
end

local QuestGuideBus: BindableEvent? do
	local obj = RS:FindFirstChild("QuestGuideBus")
	if obj and obj:IsA("BindableEvent") then
		QuestGuideBus = obj
	end
end

-- ★ QuestProgressBus (퀘스트 문구 변경용)
local QuestProgressBus: BindableEvent? do
	local obj = RS:FindFirstChild("QuestProgressBus")
	if obj and obj:IsA("BindableEvent") then
		QuestProgressBus = obj
	end
end

local TELEPORT_TAG    = "Stage2Potal"
local GLOBAL_COOLDOWN = 1.0
local lastUse = 0

-- ★ 이 서버에서 Final_JumpSpawnPart 를 쓰는지 여부
local hasFinalJumpTicket = false

local function guessDevice()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "mobile"
	end
	return "pc"
end

local function hasStage2Tag(pp: ProximityPrompt)
	local cur: Instance? = pp
	while cur do
		if CollectionService:HasTag(cur, TELEPORT_TAG) then
			return true
		end
		cur = cur.Parent
	end
	return false
end

local function guessStageFromInst(inst: Instance?)
	if not inst then return 1 end
	local cur: Instance? = inst
	while cur do
		local num = string.match(cur.Name, "Stage0*(%d+)") or string.match(cur.Name, "Stage(%d+)")
		if num then return tonumber(num) or 1 end
		cur = cur.Parent
	end
	return 1
end

local function teleportToFinalJumpSpawn()
	local map = Workspace:FindFirstChild("Final_Jumpmap")
	if not map then
		warn("[TeleportClient] Final_Jumpmap 없음")
		return
	end

	local sp = map:FindFirstChild("Final_JumpSpawnPart")
	if not sp or not sp:IsA("BasePart") then
		warn("[TeleportClient] SpawnPart 없음")
		return
	end

	local char = LP.Character or LP.CharacterAdded:Wait()
	local hrp = char:WaitForChild("HumanoidRootPart") :: BasePart

	hrp.CFrame = sp.CFrame + sp.CFrame.LookVector * 2 + Vector3.new(0, 3, 0)
	print("[TeleportClient] Final_JumpSpawnPart 로 이동")
end

-- ★ 리스폰하면, 티켓 있으면 다시 Final_JumpSpawnPart 로 보내기
LP.CharacterAdded:Connect(function(_char)
	if not hasFinalJumpTicket then
		return
	end

	-- 스폰 직후 약간 딜레이 줘서 SpawnLocation 세팅 끝난 뒤에 덮어쓰기
	task.spawn(function()
		task.wait(0.1)
		teleportToFinalJumpSpawn()
	end)
end)

-- ★ 서버에서 "전원 도착" 신호 오면 QuestUI 숨김
RE_AllArrived.OnClientEvent:Connect(function()
	if QuestProgressBus then
		QuestProgressBus:Fire({ type = "finalAllArrived" })
	end
end)

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if player ~= LP then return end
	if not hasStage2Tag(prompt) then return end

	local now = os.clock()
	if (now - lastUse) < GLOBAL_COOLDOWN then return end
	lastUse = now

	local stage = guessStageFromInst(prompt)
	print(("[TeleportClient] Stage2Potal OK → Final_JumpSpawnPart 이동 (stage=%d)"):format(stage))

	-- 1) 퀘스트 문구를 "대기"로 변경 (포탈 탄 순간)
	if QuestProgressBus then
		QuestProgressBus:Fire({ type = "finalWait" })
	end

	-- 2) 처음 포탈 탈 때도 텔레포트
	teleportToFinalJumpSpawn()

	-- 3) 이 서버에서는 이후부터 계속 Final_JumpSpawnPart 사용
	hasFinalJumpTicket = true

	-- 4) 서버에 "포탈 탔다" 알림
	RE_FinalJumpEnter:FireServer({
		reason        = "stage2_final_jump",
		promptName    = prompt.Name,
		promptPath    = prompt:GetFullName(),
		selectedStage = stage,
		device        = guessDevice(),
	})

	-- 5) 가이드 숨김
	if QuestGuideBus then
		QuestGuideBus:Fire("hide")
	end
end)

print("[TeleportClient] READY (with QuestProgressBus finalWait + FinalJump_AllArrived listener)")
