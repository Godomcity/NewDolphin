-- LocalScript @ QuestGui/Frame
--!strict
-- 퀘스트 한 줄만 사용하는 버전 (Stage5/Stage2 공용으로도 사용 가능)
--  - Quest/Frame 안의 TextLabel "1" 하나만 사용
--  - QuestProgressBus:
--      :Fire("complete") / :Fire("next")  → 다음 퀘스트로, 마지막 이후에는 줄 긋기
--      :Fire({ type="trashProgress", count=n, total=10 }) → 2번 퀘스트 진행도 n/10 갱신
--      :Fire({ type="finalWait" })        → 포탈 탑승 후 "다른 사람을 기다려 주세요"(5번)로 변경
--      :Fire({ type="finalAllArrived" })  → 전원 도착 시 Quest UI 숨김

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService") -- ★ 슬라이드용

local LP = Players.LocalPlayer

local StageRolePolicy = require(RS:WaitForChild("Modules"):WaitForChild("StageRolePolicy"))

-- ===== 퀘스트 변경 사운드 =====
local QUEST_CHANGE_SFX_ID = "rbxassetid://7740696902"

local function playQuestChangeSfx()
	local parent = workspace.CurrentCamera or LP:FindFirstChild("PlayerGui")
	if not parent then return end

	local s = Instance.new("Sound")
	s.SoundId = QUEST_CHANGE_SFX_ID
	s.Volume = 1
	s.PlayOnRemove = false
	s.Parent = parent
	s:Play()

	s.Ended:Connect(function()
		s:Destroy()
	end)

	task.delay(5, function()
		if s and s.Parent then
			s:Destroy()
		end
	end)
end

-- ===== 퀘스트 텍스트 정의 =====
local MAX_QUEST_INDEX   = 6      -- ★ 1~6까지 사용
local TRASH_QUEST_INDEX = 2      -- ★ 2번 퀘스트가 쓰레기 정화
local TRASH_TOTAL       = 10     -- ★ 쓰레기 10개

local QUEST_TEXTS: {[number]: string} = {
	[1] = "NPC에게 말 걸기",
	[2] = "쓰레기 10개 정화하기 0/10",
	[3] = "NPC에게 말 걸기",
	[4] = "포탈 이용하기",
	[5] = "다른 사람을 기다리기",
	[6] = "완주 완료",
}

-- ===== UI 찾기 =====
local root      = script.Parent :: any
local questRoot = root:WaitForChild("Quest") :: Frame
local listFrame = questRoot:WaitForChild("Frame") :: Frame

-- 이름이 "1" 인 TextLabel만 사용
local questLabel = listFrame:WaitForChild("1") :: TextLabel
questLabel.RichText = true

-- ★ Quest 프레임 슬라이드용 기본 위치 & 트윈
local BASE_POS_QUEST: UDim2 = questRoot.Position
local currentTweenQuest: Tween? = nil

-- 슬라이드 설정값
local SLIDE_TIME   = 0.45        -- 애니메이션 시간
local SLIDE_OFFSET = -1.0        -- 왼쪽 화면 밖에서 시작(-1.0 만큼 왼쪽)

local teacherDisconnect: (() -> ())? = nil
local teacherBroadcastDisconnect: (() -> ())? = nil

local function hideQuestForTeacher(reason: string?)
        questRoot.Visible = false

        -- 상위 ScreenGui까지 있으면 통째로 끔(더 확실)
        local gui = root:FindFirstAncestorOfClass("ScreenGui")
        if gui then
                gui.Enabled = false
        end

        if teacherDisconnect then
                teacherDisconnect()
                teacherDisconnect = nil
        end

        if teacherBroadcastDisconnect then
                teacherBroadcastDisconnect()
                teacherBroadcastDisconnect = nil
        end

        print("[QuestClient] Teacher detected -> QuestGui hidden", reason)
end

local function ensureQuestHiddenForTeacher(): boolean
        local observeBroadcast = StageRolePolicy and StageRolePolicy.ObserveTeacherBroadcast
        if observeBroadcast then
                teacherBroadcastDisconnect = observeBroadcast(LP, function(_, isTeacher)
                        if isTeacher then
                                hideQuestForTeacher("(TeacherRoleUpdated)")
                        end
                end, 15)
        end

        if StageRolePolicy.WaitForRoleReplication(LP, 12) then
                if StageRolePolicy.IsTeacher(LP) then
                        hideQuestForTeacher("(initial)")
                        return true
                end
        end

        teacherDisconnect = StageRolePolicy.ObserveTeacher(LP, function(isTeacher: boolean, reason: string?)
                if isTeacher then
                        hideQuestForTeacher(reason)
                end
        end, { timeoutSec = 15 })

        return false
end

if ensureQuestHiddenForTeacher() then
        return
end

do
if StageRolePolicy.IsTeacher(LP) then
hideQuestForTeacher("(sync)")
return
end
end

-- ===== 상태 저장 =====
local function getStateFolder(): Folder
	local pg = LP:WaitForChild("PlayerGui")
	local f = pg:FindFirstChild("_QuestState") :: Folder?
	if not f then
		f = Instance.new("Folder")
		f.Name = "_QuestState"
		f.Parent = pg
	end
	return f
end

local function getCurrentIndexValue(): IntValue
	local f = getStateFolder()
	local v = f:FindFirstChild("CurrentQuest") :: IntValue?
	if not v then
		v = Instance.new("IntValue")
		v.Name = "CurrentQuest"
		v.Value = 1
		v.Parent = f
	end
	return v
end

local function getTrashClearedValue(): IntValue
	local f = getStateFolder()
	local v = f:FindFirstChild("TrashCleared") :: IntValue?
	if not v then
		v = Instance.new("IntValue")
		v.Name = "TrashCleared"
		v.Value = 0
		v.Parent = f
	end
	return v
end

local function getAllClearedValue(): BoolValue
	local f = getStateFolder()
	local v = f:FindFirstChild("AllCleared") :: BoolValue?
	if not v then
		v = Instance.new("BoolValue")
		v.Name = "AllCleared"
		v.Value = false
		v.Parent = f
	end
	return v
end

local currentIndexValue = getCurrentIndexValue()
local trashClearedValue = getTrashClearedValue()
local allClearedValue   = getAllClearedValue()

----------------------------------------------------------------
-- 1) 텍스트만 갱신하는 함수 (애니메이션 X)
----------------------------------------------------------------
local function updateQuestText()
	local idx      = math.clamp(currentIndexValue.Value, 1, MAX_QUEST_INDEX)
	local cleared  = math.clamp(trashClearedValue.Value, 0, TRASH_TOTAL)
	local finished = allClearedValue.Value

	local baseText = QUEST_TEXTS[idx] or ""

	-- 2번 퀘스트면 진행도 붙이기
	if idx == TRASH_QUEST_INDEX then
		local base = (QUEST_TEXTS[TRASH_QUEST_INDEX] or ""):gsub("%s*%d+/%d+%s*$", "")
		baseText = string.format("%s %d/%d", base, cleared, TRASH_TOTAL)
	end

	if finished then
		questLabel.Text = string.format("<s>%s</s>", baseText)
		questLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	else
		questLabel.Text = baseText
		questLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	questLabel.TextTransparency = 0
end

----------------------------------------------------------------
-- 2) Quest 프레임 슬라이드 애니메이션만 담당하는 함수
----------------------------------------------------------------
local function playQuestSlide()
	-- 기존 트윈 있으면 취소
	if currentTweenQuest then
		currentTweenQuest:Cancel()
		currentTweenQuest = nil
	end

	questRoot.Visible = true
	questRoot.Position = BASE_POS_QUEST + UDim2.fromScale(SLIDE_OFFSET, 0)

	local tInfo = TweenInfo.new(
		SLIDE_TIME,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	currentTweenQuest = TweenService:Create(questRoot, tInfo, {
		Position = BASE_POS_QUEST,
	})
	currentTweenQuest:Play()
end

local function hideQuestUI()
	if currentTweenQuest then
		currentTweenQuest:Cancel()
		currentTweenQuest = nil
	end
	questRoot.Visible = false
end

-- 처음 한 번 텍스트만 세팅
updateQuestText()
questRoot.Position = BASE_POS_QUEST

----------------------------------------------------------------
-- 퀘스트 진행 (인덱스 변경 + 사운드 + 슬라이드)
----------------------------------------------------------------
local function advanceQuest()
	local idx = math.clamp(currentIndexValue.Value, 1, MAX_QUEST_INDEX)

	if idx < MAX_QUEST_INDEX then
		idx += 1
		currentIndexValue.Value = idx
		playQuestChangeSfx()
	else
		-- 이미 마지막이면 complete 시 전체 완료 처리(줄 긋기)
		allClearedValue.Value = true
	end

	updateQuestText()
	playQuestSlide()
end

-- ===== QuestProgressBus =====
local BUS_NAME = "QuestProgressBus"
local bus = RS:FindFirstChild(BUS_NAME) :: BindableEvent?
if not bus then
	local ev = Instance.new("BindableEvent")
	ev.Name = BUS_NAME
	ev.Parent = RS
	bus = ev
end

bus.Event:Connect(function(payload: any)
	-- 0) 전원 도착 → Quest UI 숨김
	if typeof(payload) == "table" and payload.type == "finalAllArrived" then
		currentIndexValue.Value = 6
		allClearedValue.Value = true
		hideQuestUI()
		return
	end

	-- 0-2) 포탈 탑승/완주자 존 진입 → "다른 사람을 기다려 주세요"(5번)
	if typeof(payload) == "table" and payload.type == "finalWait" then
		currentIndexValue.Value = 5
		allClearedValue.Value = false
		playQuestChangeSfx()
		updateQuestText()
		playQuestSlide()
		return
	end

	-- 1) complete/next → 진행
	if payload == "complete" or payload == "next" then
		advanceQuest()
		return
	end

	-- 2) 숫자로 직접 인덱스 지정
	if typeof(payload) == "number" then
		local newIndex = math.clamp(payload, 1, MAX_QUEST_INDEX)

		-- 🔹 재입장 시: 3 또는 4가 들어오면 3으로 고정 (원래 로직 유지)
		if newIndex >= 3 then
			newIndex = 3
		end

		if newIndex ~= currentIndexValue.Value then
			currentIndexValue.Value = newIndex
			allClearedValue.Value = false
			playQuestChangeSfx()
			updateQuestText()
			playQuestSlide()
		else
			allClearedValue.Value = false
			updateQuestText()
		end
		return
	end

	-- 3) 쓰레기 정화 진행도 (2번 퀘스트)
	--    👉 여기서는 텍스트만 갱신하고, 프레임 슬라이드는 건드리지 않음
	if typeof(payload) == "table" and payload.type == "trashProgress" then
		local c = tonumber(payload.count)
		local total = tonumber(payload.total) or TRASH_TOTAL
		if c then
			trashClearedValue.Value = math.clamp(c, 0, total)
			updateQuestText()
		end
		return
	end
end)

print("[QuestClient] READY - 단일 TextLabel('1') 퀘스트(1~6번) + 진행도/완료 표시 + 변경 SFX + 인덱스 변경 시 Quest 프레임 슬라이드 + finalWait/finalAllArrived")
