--!strict
-- Dialog(leaf) 종료 → UI Start(클라로) → UI Finish 수신 → 태그된 ProximityPrompt 활성화
-- 서버 훅 + 풍부한 로그 + (Goodbye 비활성화) + InUse 변화 로그

local RunService         = game:GetService("RunService")
local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")

if RunService:IsClient() then
	warn("[Dialog>UI] 이 스크립트는 ServerScriptService의 Script 여야 합니다.")
	return
end

-- 구조 타입(레거시 Dialog 지원)
type RbxDialogChoice = Instance & { ResponseDialog: string }
type RbxDialog       = Instance & {
	InUse: boolean?,
	DialogChoiceSelected: RBXScriptSignal<(Player, RbxDialogChoice) -> ()>,
	GoodbyeChoiceActive: boolean?,
}

-- ====== 설정 ======
local DEBUG               = true
local NPC_TAG             = "QuestNPC"          -- Dialog를 담은 파트/모델에 부착
local PROMPT_TAG          = "QuestLeverPrompt"  -- ProximityPrompt(또는 컨테이너)에 부착
local PROMPT_TIMEOUT_SEC  = 30.0                -- 0=무제한
local ONE_TIME_USE        = true
local DIALOG_END_TIMEOUT  = 8.0
local EXTRA_COOLDOWN_SEC  = 0.35
local HARD_FAILSAFE_SEC   = 10.0
local FORCE_GOODBYE_OFF   = true                -- 기본 Goodbye 버튼 비활성화

local function LOG(...) if DEBUG then print("[Dialog>UI]", ...) end end
local function WARN(...) warn("[Dialog>UI]", ...) end

-- ====== Remotes ======
local function ensureRemotes()
	local folder = RS:FindFirstChild("DialogueRemotes")
	if not folder then
		folder = Instance.new("Folder"); folder.Name = "DialogueRemotes"; folder.Parent = RS
		LOG("Created ReplicatedStorage/DialogueRemotes")
	end
	local start = folder:FindFirstChild("Start") :: RemoteEvent
	if not start then start = Instance.new("RemoteEvent"); start.Name="Start"; start.Parent=folder; LOG("Created RemoteEvent Start") end
	local finish = folder:FindFirstChild("Finish") :: RemoteEvent
	if not finish then finish = Instance.new("RemoteEvent"); finish.Name="Finish"; finish.Parent=folder; LOG("Created RemoteEvent Finish") end
	return start, finish
end
local RE_Start, RE_Finish = ensureRemotes()

-- ====== 유틸 ======
local function isLeafChoice(choiceInst: Instance): boolean
	for _, ch in ipairs(choiceInst:GetChildren()) do
		if ch:IsA("DialogChoice") then return false end
	end
	return true
end

local function partOrHeadCFrame(root: Instance): CFrame
	if root:IsA("BasePart") then
		return root.CFrame
	elseif root:IsA("Model") then
		local head = root:FindFirstChild("Head") or root:FindFirstChild("HumanoidRootPart")
		if head and head:IsA("BasePart") then return head.CFrame end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then return (d :: BasePart).CFrame end
		end
	end
	return CFrame.new()
end

local function setPromptGate(p: ProximityPrompt, userId: number?)
	if userId then p:SetAttribute("AllowedUserId", userId) else p:SetAttribute("AllowedUserId", nil) end
end

local hookedPrompt: { [ProximityPrompt]: boolean } = {}
local function hookPrompt(p: ProximityPrompt)
	if hookedPrompt[p] then return end
	hookedPrompt[p] = true
	LOG("Hook Prompt:", p:GetFullName())

	p.Triggered:Connect(function(player: Player)
		local allowed = p:GetAttribute("AllowedUserId")
		if allowed and allowed ~= player.UserId then
			WARN(("권한 없음 by %s → %s"):format(player.Name, p:GetFullName()))
			return
		end
		LOG(("Prompt used by %s → %s"):format(player.Name, p:GetFullName()))
		if ONE_TIME_USE then
			setPromptGate(p, nil); p.Enabled = false; LOG("Prompt OFF (one-time):", p:GetFullName())
		end
	end)
end

local function forEachTaggedPrompt(fn: (ProximityPrompt)->())
	for _, inst in ipairs(CollectionService:GetTagged(PROMPT_TAG)) do
		if inst:IsA("ProximityPrompt") then
			fn(inst)
		elseif inst:IsA("BasePart") or inst:IsA("Model") then
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("ProximityPrompt") then fn(d) end
			end
		end
	end
end

local function activateTaggedPromptsFor(player: Player)
	forEachTaggedPrompt(function(p)
		hookPrompt(p)
		setPromptGate(p, player.UserId)
		p.Enabled = true
		LOG(("Prompt ON for %s → %s"):format(player.Name, p:GetFullName()))
		if PROMPT_TIMEOUT_SEC > 0 then
			task.delay(PROMPT_TIMEOUT_SEC, function()
				if p and p:GetAttribute("AllowedUserId") == player.UserId then
					setPromptGate(p, nil); p.Enabled = false
					LOG(("Prompt timeout → OFF: %s"):format(p:GetFullName()))
				end
			end)
		end
	end)
end

-- Dialog 종료 감지 → 클라에 Start 쏘기
local function waitDialogEndThenStart(player: Player, dialog: RbxDialog, npc: Instance, leafResponse: string?)
	local started = false
	local function fireStart(tag: string)
		if started then return end
		started = true
		RE_Start:FireClient(player, {
			npcName        = npc.Name,
			npcWorldCFrame = partOrHeadCFrame(npc),
			leafResponse   = leafResponse,
			_dbg           = "server:"..tag,
		})
		LOG(("FireClient(Start) → %s, tag=%s"):format(player.Name, tag))
	end

	task.spawn(function()
		local t0 = os.clock()
		local okHas = pcall(function() return dialog.InUse end)
		if okHas then
			-- InUse false 될 때까지 대기
			while true do
				local ok, inUse = pcall(function() return dialog.InUse end)
				if not ok or not inUse then break end
				if os.clock() - t0 > DIALOG_END_TIMEOUT then
					WARN("InUse 대기 타임아웃 → 폴백 진행")
					break
				end
				task.wait(0.05)
			end
		else
			task.wait(1.25)
		end
		if EXTRA_COOLDOWN_SEC > 0 then task.wait(EXTRA_COOLDOWN_SEC) end
		fireStart("after-wait")
	end)

	task.delay(HARD_FAILSAFE_SEC, function()
		fireStart("hard-failsafe")
	end)
end

-- ====== NPC 훅킹 ======
local hookedDialog: { [Instance]: boolean } = {}

local function hookNPCWithDialog(npc: Instance)
	if not (npc:IsA("Model") or npc:IsA("BasePart")) then return end
	LOG("Hook NPC:", npc:GetFullName())

	local function hookOneDialog(dlgInst: Instance)
		if hookedDialog[dlgInst] then return end
		if dlgInst.ClassName ~= "Dialog" then return end
		hookedDialog[dlgInst] = true
		LOG("Hook Dialog:", dlgInst:GetFullName())

		local dialog: RbxDialog = dlgInst :: RbxDialog

		-- 옵션: Goodbye 버튼 강제 비활성화(실수 방지)
		if FORCE_GOODBYE_OFF then
			pcall(function() dialog.GoodbyeChoiceActive = false end)
		end

		-- InUse 변화 로그(진단용)
		pcall(function()
			dialog:GetPropertyChangedSignal("InUse"):Connect(function()
				LOG(("InUse -> %s (%s)"):format(tostring(dialog.InUse), dlgInst:GetFullName()))
			end)
		end)

		dialog.DialogChoiceSelected:Connect(function(player: Player, choice: RbxDialogChoice)
			if not player or not choice then return end
			if not isLeafChoice(choice :: Instance) then
				LOG("DialogChoice selected(leaf 아님): " .. choice.Name)
				return
			end

			local leafResponse = ""
			local ok, resp = pcall(function() return choice.ResponseDialog end)
			if ok and typeof(resp) == "string" and #resp > 0 then leafResponse = resp end

			LOG(string.format("leaf 선택 by %s (npc=%s, dlg=%s, resp=%q)",
				player.Name, npc.Name, (dlgInst :: Instance):GetFullName(), leafResponse))

			waitDialogEndThenStart(player, dialog, npc, leafResponse)
		end)
	end

	for _, d in ipairs(npc:GetDescendants()) do
		if d:IsA("Dialog") then hookOneDialog(d) end
	end
	if npc:IsA("BasePart") then
		for _, c in ipairs(npc:GetChildren()) do
			if c:IsA("Dialog") then hookOneDialog(c) end
		end
	end
end

-- 초기 스캔 + 프롬프트 훅
do
	local npcs  = CollectionService:GetTagged(NPC_TAG)
	local proms = CollectionService:GetTagged(PROMPT_TAG)
	LOG(("Initial scan: NPC_TAG=%s(%d), PROMPT_TAG=%s(%d)"):format(NPC_TAG, #npcs, PROMPT_TAG, #proms))
	for _, npc in ipairs(npcs)  do hookNPCWithDialog(npc) end
	forEachTaggedPrompt(function(p) hookPrompt(p) end)
end

-- 태그 추가 감지
CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(function(inst)
	LOG("Tag added(NPC):", inst:GetFullName()); hookNPCWithDialog(inst)
end)
CollectionService:GetInstanceAddedSignal(PROMPT_TAG):Connect(function(inst)
	LOG("Tag added(PROMPT):", inst:GetFullName())
	if inst:IsA("ProximityPrompt") then hookPrompt(inst)
	elseif inst:IsA("BasePart") or inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("ProximityPrompt") then hookPrompt(d) end
		end
	end
end)

-- UI 종료 → 프롬프트 활성화
RE_Finish.OnServerEvent:Connect(function(player: Player)
	LOG(("Finish 수신 → Prompt ON for %s"):format(player.Name))
	activateTaggedPromptsFor(player)
end)

-- 플레이어 이탈 정리
Players.PlayerRemoving:Connect(function(plr)
	forEachTaggedPrompt(function(p)
		if p:GetAttribute("AllowedUserId") == plr.UserId then
			setPromptGate(p, nil); p.Enabled = false
			LOG(("PlayerLeaving → Prompt OFF: %s"):format(p:GetFullName()))
		end
	end)
end)
