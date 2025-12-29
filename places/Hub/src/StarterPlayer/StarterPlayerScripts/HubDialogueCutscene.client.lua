-- StarterPlayerScripts/DialogueUI.client.lua
--!strict
-- RS.DialogueUIBus:Fire("Play", { npc=<Instance>, questPhase=<number>, text=..., lines=... })

local Players      = game:GetService("Players")
local RS           = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace    = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local LP = Players.LocalPlayer

-- ===== 공통 유틸 =====
local function tryRequire(inst: Instance?): any
	if not inst or not inst:IsA("ModuleScript") then return nil end
	local ok, m = pcall(require, inst)
	return ok and m or nil
end

-- ★ 포탈 컷씬
local PortalSpawnCutscene =
	tryRequire(RS:FindFirstChild("Modules") and RS.Modules:FindFirstChild("PortalSpawnCutscene"))
	or tryRequire(RS:FindFirstChild("PortalSpawnCutscene"))

local playerLock = require(RS:WaitForChild("Modules"):WaitForChild("PlayerLock"))

local PORTAL_TRIGGER_TEXT = "다음 스테이지로 가는 해류 포탈을 열어드릴게요."

-- ★ 쓰레기 퀘스트 총 개수(QuestGui와 맞추기)
local TRASH_TOTAL = 10

-- ★ 각 phase "기본" 퀘스트 문구
local QUEST_HINT_BASE: {[number]: string} = {
	[1] = "QUEST : 쓰레기 10개 정화하기 0/10",
	[2] = "QUEST : 쓰레기 10개 정화하기 0/10",
	[3] = "QUEST : 쓰레기 10개 정화하기",
	[4] = "QUEST : 다음 스테이지로 이동하기"
}

----------------------------------------------------------------
-- ===== 사운드 정의 / 프리로드 (NPC 별 시작 사운드 포함) =====
----------------------------------------------------------------
local SFX_IDS: {[string]: string} = {
	PortalOpen           = "rbxassetid://2017454590",          -- 포탈 열릴 때
	DialogueNext         = "rbxassetid://103307955424380",     -- 다음 버튼

	-- NPC별 시작 사운드
	DialogueStart_Crab      = "rbxassetid://17417730290",      -- 꽃게
	DialogueStart_Dolphin   = "rbxassetid://9114124227",       -- 돌고래
	DialogueStart_Shark     = "rbxassetid://9116302511",       -- 상어
	DialogueStart_Seahorse  = "rbxassetid://858508159",        -- 해마
	DialogueStart_Turtle    = "rbxassetid://128255388820084",  -- 거북이

	-- 매핑 안된 NPC용 기본 사운드(그냥 꽃게랑 동일하게 둠)
	DialogueStart_Default   = "rbxassetid://17417730290",
}

-- npc.Name → 시작 사운드 key 매핑 (한글/영문 둘 다 지원)
local NPC_START_SFX_BY_NAME: {[string]: string} = {
	["꽃게"]     = "DialogueStart_Crab",
	["Crab"]     = "DialogueStart_Crab",

	["돌핀"]     = "DialogueStart_Dolphin",
	["Dolphin"]  = "DialogueStart_Dolphin",

	["상어"]     = "DialogueStart_Shark",
	["Shark"]    = "DialogueStart_Shark",

	["해마"]     = "DialogueStart_Seahorse",
	["Seahorse"] = "DialogueStart_Seahorse",

	["거북이"]   = "DialogueStart_Turtle",
	["Turtle"]   = "DialogueStart_Turtle",
}

-- ★ 캐릭터 이미지 ID (초상화)
local PORTRAIT_IDS: {[string]: string} = {
	Crab     = "rbxassetid://107885850244980",   -- 꽃게
	Dolphin  = "rbxassetid://119823066460625",   -- 돌고래
	Shark    = "rbxassetid://128763543129712",   -- 상어
	Seahorse = "rbxassetid://107443638479021",   -- 해마
	Turtle   = "rbxassetid://83537201398552",    -- 거북이
	Default  = "rbxassetid://128875011792933",   -- 기본은 꽃게로
}

-- npc.Name → Portrait key 매핑 (한글/영문)
local NPC_PORTRAIT_BY_NAME: {[string]: string} = {
	["꽃게"]     = "Crab",
	["Crab"]     = "Crab",

	["돌핀"]     = "Dolphin",
	["Dolphin"]  = "Dolphin",

	["상어"]     = "Shark",
	["Shark"]    = "Shark",

	["해마"]     = "Seahorse",
	["Seahorse"] = "Seahorse",

	["거북이"]   = "Turtle",
	["Turtle"]   = "Turtle",
}

local SFX_CACHE: {[string]: Sound} = {}

do
	local soundsToPreload = {}

	for name, id in pairs(SFX_IDS) do
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = id
		s.Volume = 1
		s.RollOffMode = Enum.RollOffMode.Inverse
		s.Looped = false
		s.Parent = SoundService

		SFX_CACHE[name] = s
		table.insert(soundsToPreload, s)
	end

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(soundsToPreload)
		end)
	end)
end

-- ★★★ 여기부터 추가: NPC 초상화 이미지 미리 로딩 ★★★
do
	local preloadImages = {}

	-- PlayerGui 밑에 보이지 않는 ScreenGui 하나 만들어서 붙여 놓고 프리로드
	local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui")
	local holderGui = Instance.new("ScreenGui")
	holderGui.Name = "_PortraitPreloadGui"
	holderGui.IgnoreGuiInset = true
	holderGui.ResetOnSpawn = false
	holderGui.Enabled = false
	holderGui.Parent = pg

	for key, id in pairs(PORTRAIT_IDS) do
		local img = Instance.new("ImageLabel")
		img.Name = "PortraitPreload_" .. key
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(0, 0) -- 화면에 안 보이게 0크기
		img.Position = UDim2.fromOffset(0, 0)
		img.Image = id
		img.Visible = false
		img.Parent = holderGui
		table.insert(preloadImages, img)
	end

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(preloadImages)
		end)
		-- 다 로딩되면 깔끔하게 정리
		if holderGui then
			holderGui:Destroy()
		end
	end)
end

local function playSfx(name: string, volume: number?)
	local s = SFX_CACHE[name]
	if not s then return end

	if volume then
		s.Volume = volume
	end

	s.TimePosition = 0
	s:Play()
end

local function playStartSfxForNpc(npc: Instance?)
	local key: string? = nil
	if npc then
		key = NPC_START_SFX_BY_NAME[npc.Name]
	end

	if key and SFX_CACHE[key] then
		playSfx(key)
	else
		playSfx("DialogueStart_Default")
	end
end

-- ★ NPC → Portrait 이미지 ID
local function getPortraitIdForNpc(npc: Instance?): string
	if not npc then
		return PORTRAIT_IDS.Default
	end
	local key = NPC_PORTRAIT_BY_NAME[npc.Name]
	if key and PORTRAIT_IDS[key] then
		return PORTRAIT_IDS[key]
	end
	return PORTRAIT_IDS.Default
end

-- ========= Dialogue Bus =========
local DialogueBus = RS:FindFirstChild("DialogueUIBus")
if not DialogueBus then
	DialogueBus = Instance.new("BindableEvent")
	DialogueBus.Name = "DialogueUIBus"
	DialogueBus.Parent = RS
end
local bus = DialogueBus :: BindableEvent

-- ========= DialogueData =========
local DialogueData = tryRequire(RS:FindFirstChild("DialogueData"))

local DefaultLines: {string} = {
	"안녕하세요! 퀴즈에 참여해 주세요.",
	"문제는 총 10개이고, 정답 4개면 문이 열립니다.",
	"모두 맞추면 포탈이 생성됩니다.",
}

local function getLinesFromDialogueData(questPhase: number?): {any}?
	if not DialogueData then return nil end

	if type(DialogueData.phases) == "table" and questPhase and DialogueData.phases[questPhase] then
		return DialogueData.phases[questPhase]
	end

	if questPhase == 1 and type(DialogueData.phase1) == "table" then
		return DialogueData.phase1
	elseif questPhase == 2 and type(DialogueData.phase2) == "table" then
		return DialogueData.phase2
	elseif questPhase == 3 and type(DialogueData.phase3_incomplete) == "table" then
		return DialogueData.phase3_incomplete
	elseif questPhase == 4 and type(DialogueData.phase4_final) == "table" then
		return DialogueData.phase4_final
	end

	if type(DialogueData.lines) == "table" then
		return DialogueData.lines
	end

	if type(DialogueData) == "table" and #DialogueData > 0 then
		return DialogueData
	end

	return nil
end

local function toStringOrNil(v:any): string?
	if type(v) == "string" then return v end
	if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
	if type(v) == "table" then
		local s = v.text or v.Text or v.line or v.content or v.message or v.caption or v[1]
		if type(s) == "string" then return s end
	end
	return nil
end

local function normalizeLines(input:any, questPhase:number?): {string}
	if input ~= nil then
		if type(input) == "string" then
			return { input }
		end
		if type(input) == "table" then
			if input.lines and type(input.lines) == "table" then
				input = input.lines
			end
			if type(input) == "table" then
				local out = {}
				for _, v in ipairs(input) do
					local s = toStringOrNil(v)
					if s then table.insert(out, s) end
				end
				if #out > 0 then return out end
			end
		end
	end

	local fromModule = getLinesFromDialogueData(questPhase)
	if fromModule then
		local out = {}
		for _, v in ipairs(fromModule) do
			local s = toStringOrNil(v)
			if s then table.insert(out, s) end
		end
		if #out > 0 then return out end
	end

	local out = {}
	for _, v in ipairs(DefaultLines) do
		local s = toStringOrNil(v)
		if s then table.insert(out, s) end
	end
	if #out == 0 then
		out = { "..." }
	end
	return out
end

-- ========= PlayerGui 쪽 퀘스트 상태 읽기 (쓰레기 개수) =========
local function getTrashProgressFromState(): (number, number)
	local pg = LP:FindFirstChild("PlayerGui")
	if not pg then return 0, TRASH_TOTAL end

	local stateFolder = pg:FindFirstChild("_QuestState")
	if not stateFolder then return 0, TRASH_TOTAL end

	local trashVal = stateFolder:FindFirstChild("TrashCleared")
	local count = 0
	if trashVal and trashVal:IsA("IntValue") then
		count = trashVal.Value
	end

	return math.clamp(count, 0, TRASH_TOTAL), TRASH_TOTAL
end

-- ========= UI 생성 =========
local function buildUI(): ScreenGui
	local pg = LP:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("DialogueGui")
	if gui then return gui end

	gui = Instance.new("ScreenGui")
	gui.Name = "DialogueGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9000
	gui.Enabled = false
	gui.Parent = pg

	local bg = Instance.new("Frame")
	bg.Name = "BG"
	bg.BackgroundColor3 = Color3.fromRGB(0,0,0)
	bg.BackgroundTransparency = 0.35
	bg.Size = UDim2.fromScale(1,1)
	bg.Active = true
	bg.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5,1)
	panel.Position = UDim2.fromScale(0.5, 1.02)
	panel.Size = UDim2.fromScale(0.9, 0.26)
	panel.BackgroundColor3 = Color3.fromRGB(24,28,36)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = bg
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 18)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0,12); pad.PaddingBottom = UDim.new(0,12)
	pad.PaddingLeft = UDim.new(0,16); pad.PaddingRight = UDim.new(0,16)
	pad.Parent = panel
	panel.ZIndex = 2

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1,0.24)
	title.Text = "대화"
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(210,230,255)
	title.Parent = panel
	title.ZIndex = 3

	local body = Instance.new("TextLabel")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0,0.28)
	-- ★ 우측에 캐릭터 이미지를 두기 위해 텍스트 영역을 살짝 줄임
	body.Size = UDim2.fromScale(0.7,0.54)
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Font = Enum.Font.Gotham
	body.TextScaled = true
	body.TextColor3 = Color3.fromRGB(240,240,240)
	body.Parent = panel
	body.ZIndex = 3

	-- ★ Porbody.ZIndex = 3
	local portrait = Instance.new("ImageLabel")
	portrait.Name = "Portrait"
	portrait.BackgroundTransparency = 1
	portrait.AnchorPoint = Vector2.new(1,0)
	portrait.Position = UDim2.fromScale(1.12, -3.15) -- Body와 같은 Y, 오른쪽 상단
	portrait.Size = UDim2.fromScale(0.5, 5)     -- 남은 영역에 적당히
	portrait.Image = ""
	portrait.ScaleType = Enum.ScaleType.Fit
	portrait.Visible = false
	portrait.ZIndex = 1
	portrait.Parent = panel
	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(0, 16)
	portraitCorner.Parent = portrait

	local nextBtn = Instance.new("TextButton")
	nextBtn.Name = "Next"
	nextBtn.AnchorPoint = Vector2.new(1,1)
	nextBtn.Position = UDim2.fromScale(0.99, 0.98)
	nextBtn.Size = UDim2.fromScale(0.18, 0.26)
	nextBtn.Text = "다음"
	nextBtn.Font = Enum.Font.GothamBold
	nextBtn.TextScaled = true
	nextBtn.TextColor3 = Color3.new(1,1,1)
	nextBtn.BackgroundColor3 = Color3.fromRGB(46,120,255)
	Instance.new("UICorner", nextBtn).CornerRadius = UDim.new(0,12)
	nextBtn.Visible = false
	nextBtn.Parent = panel
	nextBtn.ZIndex = 3

return gui
end
	

local GUI = buildUI()
local running   = false
local nextConn  : RBXScriptConnection? = nil
local clickConn : RBXScriptConnection? = nil

-- ========= 애니/표시 =========
local function slideIn(panel: Frame)
	panel.Visible = true
	TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.5, 0.96)
	}):Play()
end

local function slideOutAndClose(gui: ScreenGui, panel: Frame)
	TweenService:Create(panel, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		Position = UDim2.fromScale(0.5, 1.02)
	}):Play()
	task.wait(0.22)
	gui.Enabled = false
	panel.Visible = false
	playerLock.Unlock()
	
	bus:Fire("Finished")

end

-- ★ isTyping 지원 typewriter
local function typewrite(label: TextLabel, text: string, cps: number?, state: {isTyping:boolean, skip:boolean}?)
	cps = cps or 35
	label.Text = ""

	if state then
		state.isTyping = true
		state.skip = false
	end

	for i = 1, #text do
		if state and state.skip then
			label.Text = text
			break
		end
		label.Text = string.sub(text, 1, i)
		task.wait(1/(cps :: number))
	end

	if state then
		state.isTyping = false
	end
end

-- ========= 포탈 컷씬 =========
local function playPortalCutsceneAndWait()
	if not PortalSpawnCutscene then
		warn("[DialogueUI] PortalSpawnCutscene 모듈을 찾지 못했습니다.")
		return
	end

	-- 포탈 열릴 때 사운드
	playSfx("PortalOpen")

	pcall(function()
		PortalSpawnCutscene.play({
			templateName   = "Potal",
			parent         = Workspace,
			targetPosition = Vector3.new(-160.87, 72.704, 91.992),
			camStartPath   = "CamPos",
			camEndPath     = "CamEndPos",
			camAnchorsUseOrientation = true,
		})
	end)

	task.wait(2.5)
end

-- ========= 시퀀스 =========
local function runDialogueSequence(npc: Instance?, src:any, questPhase:number?)
	if running then return end
	running = true

	local bg      = GUI:FindFirstChild("BG") :: Frame
	local panel   = bg:FindFirstChild("Panel") :: Frame
	local title   = panel:FindFirstChild("Title") :: TextLabel
	local body    = panel:FindFirstChild("Body")  :: TextLabel
	local nextBtn = panel:FindFirstChild("Next") :: TextButton
	local portrait = panel:FindFirstChild("Portrait") :: ImageLabel?

	GUI.Enabled = true
	panel.Position = UDim2.fromScale(0.5, 1.02)
	panel.Visible  = true
	-- ★ NPC별 시작 사운드
	playStartSfxForNpc(npc)

	-- ★ NPC 이미지 세팅
	if portrait then
		local imgId = getPortraitIdForNpc(npc)
		portrait.Image = imgId or ""
		portrait.Visible = (imgId ~= nil and imgId ~= "")
	end

	local lines = normalizeLines(src, questPhase)
	title.Text = npc and npc.Name or "대화"

	-- ★ 현재 phase 에 해당하는 퀘스트 문구 구성
	local questHintText: string? = nil
	local base = questPhase and QUEST_HINT_BASE[questPhase] or nil
	if base then
		if questPhase == 3 then
			local cleared, total = getTrashProgressFromState()
			questHintText = string.format("%s %d/%d", base, cleared, total)
		else
			questHintText = base
		end
	end

	local normalCount = #lines
	local totalCount  = normalCount + ((questHintText and 1) or 0)

	local idx = 1

	local typingState = {
		isTyping = false,
		skip = false,
	}

	local portalCutscenePlayed  = false
	local portalCutscenePlaying = false

	-- ★ 현재 줄 텍스트 저장해서, 클릭 시 한 번에 채우기
	local currentText = ""

	local function showCurrentLine()
		local text: string
		local isHintLine = (questHintText ~= nil and idx == totalCount)

		if isHintLine then
			text = questHintText or ""
			body.TextColor3 = Color3.fromRGB(255, 230, 100)
		else
			text = lines[idx] or ""
			body.TextColor3 = Color3.fromRGB(240,240,240)
		end

		currentText = text
		body.Text = ""
		nextBtn.Visible      = false

		typewrite(body, currentText, 35, typingState)

		nextBtn.Visible = true
	end

	local function cleanup()
		running = false
		if nextConn then nextConn:Disconnect(); nextConn = nil end
		if clickConn then clickConn:Disconnect(); clickConn = nil end
	end

	local function handleAdvance(playNextSound: boolean)
		if portalCutscenePlaying then
			return
		end

		-- ★ 타이핑 중이면: 현재 줄을 한 번에 채우고 끝
		if typingState.isTyping then
			typingState.skip = true
			body.Text = currentText
			typingState.isTyping = false
			return
		end

		if playNextSound then
			playSfx("DialogueNext")
		end

		local isHintLine   = (questHintText ~= nil and idx == totalCount)
		local currentLineText  = (idx <= normalCount) and (lines[idx] or "") or ""

		-- 포탈 컷씬 트리거
		if (not isHintLine)
			and (not portalCutscenePlayed)
			and typeof(currentLineText) == "string"
			and string.find(currentLineText, "다음 구역으로 갈 수 있는 포탈을 열어줄게…", 1, true) ~= nil
		then
			portalCutscenePlayed  = true
			portalCutscenePlaying = true
			nextBtn.Visible = false

			GUI.Enabled  = false
			panel.Visible = false
			playerLock.Unlock()
			playPortalCutsceneAndWait()

			portalCutscenePlaying = false

			idx += 1
			if idx <= totalCount then
				GUI.Enabled = true
				panel.Position = UDim2.fromScale(0.5, 1.02)
				panel.Visible  = true
				showCurrentLine()
				return
			else
				GUI.Enabled = true
				slideOutAndClose(GUI, panel)
				cleanup()
				return
			end
		end

		-- 일반 진행
		idx += 1
		if idx <= totalCount then
			showCurrentLine()
		else
			nextBtn.Visible = false
			slideOutAndClose(GUI, panel)
			cleanup()
		end
	end

	if nextConn then nextConn:Disconnect() end
	if clickConn then clickConn:Disconnect() end

	nextConn = nextBtn.MouseButton1Click:Connect(function()
		-- 버튼으로 넘길 때만 사운드
		handleAdvance(true)
	end)

	clickConn = bg.InputBegan:Connect(function(input, _gp)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			-- 배경 탭은 조용히(사운드 없이) 넘김
			handleAdvance(false)
		end
	end)

	slideIn(panel)
	showCurrentLine()
end

-- ========= Bus 연결 =========
bus.Event:Connect(function(cmd:any, payload:any)
	if cmd == "Play" then
		local npc        = payload and payload.npc
		local src        = payload and (payload.text or payload.lines or payload.sequence) or nil
		local questPhase = payload and payload.questPhase
		playerLock.Lock({freezeMovement = true, freezeCamera = true, disableInput = true})
		runDialogueSequence(npc, src, questPhase)
		
	elseif cmd == "Close" or cmd == "Finished" then
		playerLock.Unlock()
		local bg    = GUI:FindFirstChild("BG") :: Frame
		local panel = bg and (bg:FindFirstChild("Panel") :: Frame)
		if panel then
			playerLock.Unlock()
			GUI.Enabled = false
			panel.Visible = false
			local portrait = panel:FindFirstChild("Portrait")
			if portrait and portrait:IsA("ImageLabel") then
				portrait.Visible = false
			end
		else
			GUI.Enabled = false
		end
		running = false
	end
end)

print("[DialogueUI] READY (phase별 대사 + 포탈 컷씬 + 타이핑/스킵 + 퀘스트 문구 + NPC별 SFX + Portrait)")
