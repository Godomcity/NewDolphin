-- LocalScript (StarterGui/EntryScreen 안)
--!strict

local CONFIG = {
	MOCK = { delaySec = 0.5, failRate = 0.0 },
	LOADING = { preDelay = 0.6, dotSize = 10, dotGap = 10, color = Color3.fromRGB(40,140,255) },
}

local Players           = game:GetService("Players")
local UIS               = game:GetService("UserInputService")
local TeleportService   = game:GetService("TeleportService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")  -- ★ 사운드 재생용
local Debris            = game:GetService("Debris")        -- ★ 사운드 정리용

local Net    = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local Toast  = require(ReplicatedStorage.Modules.UI.Toast)
local UIRefs = require(ReplicatedStorage.Modules.UI.UIRefs)

-- 기존: 입장 코드로 조인(지금 단계에서는 호출 안 함 / 남겨만 둠)
local RF_JoinByCode = Net.ensureRF("RF_JoinByCode")

-- ✅ 추가: "보내기만" 하는 RemoteEvent (서버 아직 없어도 클라가 멈추지 않음)
-- Net 모듈에 ensureRE가 있어야 함 (없으면 아래 주석 참고)
local RE_SubmitPersonalToken = Net.ensureRE("RE_SubmitPersonalToken")

local player = Players.LocalPlayer
local ui     = UIRefs.bind(script.Parent)

local entryBox = ui.EnterTextBox
local tokenBox = ui.TokenTextBox
local enterBtn = ui.EnterButton or ui.TextButton

-- ★ 사운드 ID
local CLICK_SFX_ID = "rbxassetid://15675059323"
local ERROR_SFX_ID = "rbxassetid://87519554692663"

-- ★ 사운드 유틸
local function playSfx(id: string?)
	if not id or id == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 1
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	Debris:AddItem(sound, 3)
end

local function playClick()
	playSfx(CLICK_SFX_ID)
end

local function playError()
	playSfx(ERROR_SFX_ID)
end

-- ===== 유틸
local function norm(s) return (s or ""):gsub("%s+", ""):upper() end
local function isValidEntryCode(code) code = norm(code); return #code == 8 and code:match("^[A-Z0-9]+$") ~= nil end
local function isValidToken(token) token = (token or ""):match("^%s*(.-)%s*$"); return #token >= 8 end
local function isMobile() return UIS.TouchEnabled and not UIS.KeyboardEnabled end

----------------------------------------------------------------
-- ★ EntryScreen 동안 움직임/카메라/줌 잠금 (PlayerModule Controls Disable)
----------------------------------------------------------------
local controlsLocked = false
local controlsObj: any = nil
local charAddedConn: RBXScriptConnection? = nil

local function setHumanoidFrozen(on: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if on then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	else
		-- 기본값(프로젝트에서 다른 값 쓰면 여기만 맞춰주면 됨)
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
		humanoid.AutoRotate = true
	end
end

local function getControls()
	local ps = player:WaitForChild("PlayerScripts")
	local pm = ps:FindFirstChild("PlayerModule")
	if not pm then return nil end

	local ok, mod = pcall(require, pm)
	if not ok or type(mod) ~= "table" then return nil end
	if type((mod :: any).GetControls) ~= "function" then return nil end

	local ok2, controls = pcall(function()
		return (mod :: any):GetControls()
	end)
	if not ok2 then return nil end

	return controls
end

local function lockControls()
	if controlsLocked then return end
	controlsLocked = true

	controlsObj = getControls()
	if controlsObj and typeof((controlsObj :: any).Disable) == "function" then
		pcall(function()
			(controlsObj :: any):Disable()
		end)
	end

	setHumanoidFrozen(true)

	if charAddedConn then charAddedConn:Disconnect() end
	charAddedConn = player.CharacterAdded:Connect(function()
		task.wait(0.05)
		if not controlsLocked then return end
		setHumanoidFrozen(true)
		if controlsObj and typeof((controlsObj :: any).Disable) == "function" then
			pcall(function()
				(controlsObj :: any):Disable()
			end)
		end
	end)
end

local function unlockControls()
	if not controlsLocked then return end
	controlsLocked = false

	if charAddedConn then
		charAddedConn:Disconnect()
		charAddedConn = nil
	end

	if controlsObj and typeof((controlsObj :: any).Enable) == "function" then
		pcall(function()
			(controlsObj :: any):Enable()
		end)
	end
	controlsObj = nil

	setHumanoidFrozen(false)
end

-- EntryScreen이 떠있는 동안은 잠금
lockControls()

----------------------------------------------------------------
-- ===== 로딩 점(3개)
----------------------------------------------------------------
local loadingFrame : Frame
local loadingRun = false

local function ensureLoadingDots()
	if loadingFrame and loadingFrame.Parent then return loadingFrame end
	local dotSize, gap = CONFIG.LOADING.dotSize, CONFIG.LOADING.dotGap
	local totalW = dotSize*3 + gap*2
	local f = Instance.new("Frame")
	f.Name = "LoadingDots"
	f.AnchorPoint = Vector2.new(0.5,1)
	f.Position = UDim2.new(0.5,0,1,-14)
	f.Size = UDim2.fromOffset(totalW, dotSize)
	f.BackgroundTransparency = 1
	f.Visible = false
	f.ZIndex = (enterBtn and enterBtn.ZIndex or 1) + 1
	f.Parent = ui.EntryCard

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, gap)
	layout.Parent = f

	for i=1,3 do
		local dot = Instance.new("Frame")
		dot.Name = "Dot"..i
		dot.Size = UDim2.fromOffset(dotSize, dotSize)
		dot.BackgroundColor3 = CONFIG.LOADING.color
		dot.BorderSizePixel = 0
		dot.BackgroundTransparency = 0.2
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)
		local s = Instance.new("UIScale"); s.Scale = 1; s.Parent = dot
		dot.Parent = f
	end
	loadingFrame = f
	return f
end

local function startLoading()
	local frame = ensureLoadingDots()
	frame.Visible = true
	loadingRun = true
	task.spawn(function()
		local tUp   = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tDown = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local onA, offA = 0, 0.6
		local upS, dnS  = 1.25, 1
		local idx = 1
		while loadingRun and frame.Parent do
			for j=1,3 do
				local k = ((idx + j - 2) % 3) + 1
				local dot = frame:FindFirstChild("Dot"..k)
				if dot then
					local s = dot:FindFirstChildOfClass("UIScale")
					TweenService:Create(dot, tUp, {BackgroundTransparency=onA}):Play()
					if s then TweenService:Create(s, tUp, {Scale=upS}):Play() end
					task.delay(0.18, function()
						if loadingRun and dot.Parent then
							TweenService:Create(dot, tDown, {BackgroundTransparency=offA}):Play()
							if s then TweenService:Create(s, tDown, {Scale=dnS}):Play() end
						end
					end)
					task.wait(0.11)
				end
			end
			idx += 1
		end
	end)
end

local function stopLoading()
	loadingRun = false
	if loadingFrame and loadingFrame.Parent then loadingFrame.Visible = false end
end

-- ===== Busy
local isBusy = false
local function setBusy(b)
	isBusy = b
	if enterBtn then enterBtn.Active = not b end
	if entryBox then entryBox.TextEditable = not b end
	if tokenBox then tokenBox.TextEditable = not b end
end

-- 텔레포트 실패 → 로딩 끄고 토스트
TeleportService.TeleportInitFailed:Connect(function(plr, result, msg)
	if plr ~= player then return end
	print(("[Entry] TeleportInitFailed: %s (%s)"):format(tostring(result), tostring(msg)))
	stopLoading()
	setBusy(false)

	-- ★ 에러 사운드
	playError()

	local kind = (result == Enum.TeleportResult.GameFull) and "server_full" or "network_error"
	Toast.panel(kind, "", "", { style="circle", anchor=ui.EntryCard, attach="over", confirmText="확인" })
end)

-- ===== 제출
local function submit()
	if isBusy then return end

	local entryCode = norm(entryBox and entryBox.Text or "")
	local token     = (tokenBox and tokenBox.Text or ""):match("^%s*(.-)%s*$")

	print(("[Entry] submit() called. code=%s tokenLen=%d device=%s")
		:format(entryCode, #token, isMobile() and "mobile" or "desktop"))

	if not isValidEntryCode(entryCode) then
		print("[Entry] invalid entry code")
		playError()

		Toast.panel("invalid_code", "", "", {
			style="circle", anchor=entryBox, attach="over", confirmText="확인",
			onConfirm=function() if entryBox then entryBox.Text=""; entryBox:CaptureFocus() end end,
		})
		return
	end

	if not isValidToken(token) then
		print("[Entry] invalid token")
		playError()

		Toast.panel("token_expired", "", "", {
			style="circle", anchor=tokenBox, attach="over", confirmText="확인",
			onConfirm=function() if tokenBox then tokenBox.Text=""; tokenBox:CaptureFocus() end end,
		})
		return
	end

	-- ✅ 여기까지만: "서버에 보내기만" (서버 아직 구현 안 해도 클라 안 멈춤)
	pcall(function()
		RE_SubmitPersonalToken:FireServer({
			token = token,
			entryCode = entryCode,
			device = isMobile() and "mobile" or "desktop",
		})
	end)

	setBusy(true)
	startLoading()
	task.wait(CONFIG.LOADING.preDelay)

	local okServer, res = pcall(function()
		return RF_JoinByCode:InvokeServer({
			entryCode = entryCode,
			token     = token,
			device    = isMobile() and "mobile" or "desktop",
		})
	end)

	print("[Entry] RF_JoinByCode returned:", okServer, res and res.ok, res and res.error)

	if not okServer or not res or not res.ok then
		stopLoading()
		playError()

		local errKind = (res and res.error) or "network_error"
		local anchor = ui.EntryCard
		if errKind == "invalid_code" then anchor = entryBox
		elseif errKind == "invalid_token" or errKind == "token_expired" then errKind = "token_expired"; anchor = tokenBox end

		Toast.panel(errKind, "", "", {
			style="circle", anchor=anchor, attach="over", confirmText="확인",
			onConfirm=function()
				if anchor == entryBox then entryBox.Text=""; entryBox:CaptureFocus()
				elseif anchor == tokenBox then tokenBox.Text=""; tokenBox:CaptureFocus() end
			end,
		})
		setBusy(false)
		return
	end
	
end

-- ===== 트리거 바인딩 (모두 submit)
if enterBtn then
	enterBtn.Activated:Connect(function()
		print("[Entry] EnterButton.Activated")
		playClick()
		submit()
	end)
end

-- 토큰 박스에서 Enter
if tokenBox then
	tokenBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			print("[Entry] TokenTextBox Enter")
			submit()
		end
	end)
end

-- 입장코드 박스에서 Enter도 허용
if entryBox then
	entryBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			print("[Entry] EnterTextBox Enter")
			submit()
		end
	end)
	-- 입력 정규화
	entryBox:GetPropertyChangedSignal("Text"):Connect(function()
		local t = entryBox.Text or ""
		t = t:gsub("%s+", ""):gsub("[^%da-zA-Z]", ""):upper()
		if #t > 8 then t = t:sub(1,8) end
		if entryBox.Text ~= t then entryBox.Text = t end
	end)
end

-- 포커스 안 가고 Return만 눌러도 제출(선택)
UIS.InputBegan:Connect(function(input, gp)
	if gp or isBusy then return end
	if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		print("[Entry] Global Enter key")
		submit()
	end
end)

----------------------------------------------------------------
-- (선택) EntryScreen을 나중에 끌 때 조작 잠금 해제하고 싶으면:
-- unlockControls()
----------------------------------------------------------------

--[[
📌 만약 Net.ensureRE가 없다면(에러 난다면), 아래처럼 대체할 수 있어:

local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local RE_SubmitPersonalToken = Remotes:FindFirstChild("RE_SubmitPersonalToken") or Instance.new("RemoteEvent")
RE_SubmitPersonalToken.Name = "RE_SubmitPersonalToken"
RE_SubmitPersonalToken.Parent = Remotes
]]
