-- StarterPlayerScripts / ResultGui / LocalScript
--!strict
-- 서버에서 Remotes.RE_Result_Open 을 쏴 줄 때만 결과창 표시
-- 서버(StageResultBoardService.lua)에서 받아온 "세션 전체 결과(모든 스테이지 합산)"을
-- 1~15등 이름만 세 구역(1~3 / 4~9 / 10~15)에 채워서 보여준다.
-- 선생님이 X 버튼 누르면 모든 플레이어의 ResultGui 닫힘
-- + 결과창 열리면 캐릭터 이동/점프 입력 잠금, 닫히면 해제
-- + 결과창 열리면 카메라 고정, 닫히면 원복

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LP = Players.LocalPlayer
local pg = LP:WaitForChild("PlayerGui")

----------------------------------------------------------------
-- 설정
----------------------------------------------------------------
-- ★ Studio에서 항상 켜보고 싶으면 true
local DEBUG_FORCE_SHOW = false

----------------------------------------------------------------
-- 교사 여부 (서버 SessionBootstrap이 내려준 Attribute 기준)
----------------------------------------------------------------
local function isTeacher(): boolean
	return LP:GetAttribute("isTeacher") == true
end

----------------------------------------------------------------
-- Remotes
----------------------------------------------------------------
local Remotes            = ReplicatedStorage:WaitForChild("Remotes")
local RF_GetStageResults = Remotes:WaitForChild("RF_GetStageResults") :: RemoteFunction
local RE_Result_CloseAll = Remotes:WaitForChild("RE_Result_CloseAll") :: RemoteEvent
local RE_Result_Open     = Remotes:WaitForChild("RE_Result_Open")     :: RemoteEvent

----------------------------------------------------------------
-- UI 참조
----------------------------------------------------------------
local gui         = script.Parent :: ScreenGui
local rootFrame   = gui:WaitForChild("Frame") :: Frame
local resultImage = rootFrame:WaitForChild("ResultImage") :: Frame
local xButton     = resultImage:WaitForChild("XButton") :: GuiButton

-- 1~3등 영역
local topNickFrame    = resultImage:WaitForChild("1,2,3NickNameFrame") :: Frame
local topNickTemplate = topNickFrame:WaitForChild("NickNameText") :: TextLabel

-- 4~9등 영역
local midNickFrame    = resultImage:WaitForChild("4,5,6,7,8,9NickNameFrame") :: Frame
local midNickTemplate = midNickFrame:WaitForChild("NickNameText") :: TextLabel

-- 10~15등 영역
local bottomNickFrame    = resultImage:WaitForChild("10,11,12,13,14,15NickNameFrame") :: Frame
local bottomNickTemplate = bottomNickFrame:WaitForChild("NickNameText") :: TextLabel

-- 처음엔 안보이게
rootFrame.Visible = false
gui.Enabled = true

-- ★ 선생님에게만 X 버튼 보이도록 (Attribute 기반)
do
	local teacher = isTeacher()
	xButton.Visible = teacher
	xButton.Active  = teacher
end

-- 서버에서 Attribute가 나중에 세팅될 수도 있으니(텔레포트 직후), 변경 감지해서 버튼 갱신
LP:GetAttributeChangedSignal("isTeacher"):Connect(function()
	local teacher = isTeacher()
	xButton.Visible = teacher
	xButton.Active  = teacher
end)

----------------------------------------------------------------
-- 카메라 고정(열릴 때) / 해제(닫힐 때)
-- - 열릴 때 현재 시점에서 Scriptable로 고정
-- - 닫힐 때 원래 CameraType/CameraSubject 복구
----------------------------------------------------------------
local camLocked = false
local origCameraType: Enum.CameraType? = nil
local origCameraSubject: Instance? = nil
local origCamCFrame: CFrame? = nil

local function lockCamera()
	if camLocked then return end
	camLocked = true

	local camera = Workspace.CurrentCamera
	origCameraType = camera.CameraType
	origCameraSubject = camera.CameraSubject
	origCamCFrame = camera.CFrame

	camera.CameraType = Enum.CameraType.Scriptable
	if origCamCFrame then
		camera.CFrame = origCamCFrame
	end
end

local function unlockCamera()
	if not camLocked then return end
	camLocked = false

	local camera = Workspace.CurrentCamera
	if origCameraType then
		camera.CameraType = origCameraType
	else
		camera.CameraType = Enum.CameraType.Custom
	end

	if origCameraSubject then
		camera.CameraSubject = origCameraSubject
	end
end

----------------------------------------------------------------
-- 이동/점프 입력 잠금(열릴 때) / 해제(닫힐 때)
-- - PlayerModule Controls Disable/Enable (PC/모바일 모두)
-- - 혹시 Controls를 못 얻는 환경을 대비해서 Humanoid 속도도 폴백으로 제어
----------------------------------------------------------------
local PlayerModule: any = nil
local Controls: any = nil
local controlsLocked = false

local function getControls()
	if Controls then
		return Controls
	end

	local ps = LP:WaitForChild("PlayerScripts")
	local pm = ps:FindFirstChild("PlayerModule")
	if not pm then
		pm = ps:WaitForChild("PlayerModule", 5)
	end

	if pm then
		local ok, m = pcall(require, pm)
		if ok and m and m.GetControls then
			PlayerModule = m
			Controls = m:GetControls()
		end
	end

	return Controls
end

local function lockPlayerControls()
	if controlsLocked then return end
	controlsLocked = true

	local c = getControls()
	if c and c.Disable then
		c:Disable()
	end

	-- 폴백(혹시 Controls를 못 얻는 경우)
	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		-- 원복용 저장(한 번만)
		if hum:GetAttribute("ResultGui_OrigWalkSpeed") == nil then
			hum:SetAttribute("ResultGui_OrigWalkSpeed", hum.WalkSpeed)
		end
		if hum:GetAttribute("ResultGui_OrigJumpPower") == nil then
			hum:SetAttribute("ResultGui_OrigJumpPower", hum.JumpPower)
		end

		hum.WalkSpeed = 0
		hum.JumpPower = 0
	end

	-- ✅ 카메라 고정
	lockCamera()
end

local function unlockPlayerControls()
	if not controlsLocked then return end
	controlsLocked = false

	local c = getControls()
	if c and c.Enable then
		c:Enable()
	end

	local char = LP.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local ws = hum:GetAttribute("ResultGui_OrigWalkSpeed")
		local jp = hum:GetAttribute("ResultGui_OrigJumpPower")

		if typeof(ws) == "number" then
			hum.WalkSpeed = ws
		end
		if typeof(jp) == "number" then
			hum.JumpPower = jp
		end

		hum:SetAttribute("ResultGui_OrigWalkSpeed", nil)
		hum:SetAttribute("ResultGui_OrigJumpPower", nil)
	end

	-- ✅ 카메라 원복
	unlockCamera()
end

-- 리스폰해도 결과창이 열려 있으면 계속 잠금 유지(이동/점프 + 카메라)
LP.CharacterAdded:Connect(function()
	if rootFrame.Visible then
		task.defer(lockPlayerControls)
	end
end)

----------------------------------------------------------------
-- 유틸: 자식 클리어 (템플릿/레이아웃은 유지)
----------------------------------------------------------------
local function clearChildrenButKeepTemplate(parent: Frame, template: TextLabel)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("TextLabel") and child ~= template then
			child:Destroy()
		end
	end
end

----------------------------------------------------------------
-- 결과 UI 채우기
-- results: { {userId, name, totalScore, totalTimeSec, ...}, ... }
--  ▶ 여기서는 "이름만" 사용
--  ▶ 선생님 제외는 이제 UserId 하드코딩 대신,
--     (권장) 서버가 row.isTeacher를 같이 내려주면 그걸로 스킵.
--  ▶ 아직 서버가 isTeacher를 안 내려주면: 그냥 전원 표시(가장 안전한 동작)
----------------------------------------------------------------
local function renderResults(results: {any})
	-- 세 영역 모두 정리
	clearChildrenButKeepTemplate(topNickFrame, topNickTemplate)
	clearChildrenButKeepTemplate(midNickFrame, midNickTemplate)
	clearChildrenButKeepTemplate(bottomNickFrame, bottomNickTemplate)

	-- 템플릿은 숨겨놓기
	topNickTemplate.Visible    = false
	midNickTemplate.Visible    = false
	bottomNickTemplate.Visible = false

	local visibleRank = 0

	for _, row in ipairs(results) do
		-- (권장) 서버가 row.isTeacher 내려주면 학생 화면에서만 선생님 제외 가능
		-- 지금은 서버 코드가 아직 그걸 안 보낼 수도 있으니, 없으면 그냥 표시한다.
		local rowIsTeacher = (row and row.isTeacher == true)

		if (not isTeacher()) and rowIsTeacher then
			-- 학생이면 선생님 row 숨김
			continue
		end

		visibleRank += 1
		if visibleRank > 15 then
			break
		end

		local name = row.name or row.playerName or "Player"
		local labelParent: Frame
		local template: TextLabel

		if visibleRank <= 3 then
			labelParent = topNickFrame
			template = topNickTemplate
		elseif visibleRank <= 9 then
			labelParent = midNickFrame
			template = midNickTemplate
		else
			labelParent = bottomNickFrame
			template = bottomNickTemplate
		end

		local t = template:Clone()
		t.Text = tostring(name)
		t.Visible = true
		t.Parent = labelParent
	end
end

----------------------------------------------------------------
-- 서버에서 결과 받아오기 + 표시
----------------------------------------------------------------
local function fetchAndShow()
	local ok, data = pcall(function()
		return RF_GetStageResults:InvokeServer()
	end)

	if not ok or type(data) ~= "table" or not data.ok then
		warn("[ResultGui] RF_GetStageResults failed:", ok, data and data.reason)
		return
	end

	local results = data.results or {}
	print("[ResultGui] results count =", #results)

	if #results == 0 then
		warn("[ResultGui] no results")
		return
	end

	renderResults(results)
	rootFrame.Visible = true
	lockPlayerControls()
end

----------------------------------------------------------------
-- X 버튼: 선생님만 "전체 닫기" 요청
----------------------------------------------------------------
xButton.Activated:Connect(function()
	if not isTeacher() then
		return
	end

	-- 1) 내 것 먼저 닫기
	rootFrame.Visible = false
	unlockPlayerControls()

	-- 2) 서버에 요청
	RE_Result_CloseAll:FireServer()
end)

-- 서버에서 브로드캐스트 되는 "전체 닫기"
RE_Result_CloseAll.OnClientEvent:Connect(function()
	rootFrame.Visible = false
	unlockPlayerControls()
end)

----------------------------------------------------------------
-- 서버 신호: 결과창 열기
----------------------------------------------------------------
RE_Result_Open.OnClientEvent:Connect(function()
	print("[ResultGui] RE_Result_Open 수신 → fetchAndShow()")
	fetchAndShow()
end)

----------------------------------------------------------------
-- Studio 디버그용: 강제로 바로 켜보기
----------------------------------------------------------------
if DEBUG_FORCE_SHOW then
	task.defer(function()
		print("[ResultGui] DEBUG_FORCE_SHOW=true → fetchAndShow()")
		fetchAndShow()
	end)
end

print("[ResultGui] READY (서버 RE_Result_Open 수신 시 total scoreboard 표시)")
