-- ReplicatedStorage/Modules/Cutscene/CutscenePlayer.lua
-- 포탈 오픈 컷씬 (끝나면 서버에 Quiz_CutsceneDone 신호 송신)

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UIS               = game:GetService("UserInputService")
local Debris            = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP     = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Net             = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net"))
local RE_CutsceneDone = Net.ensureRE("Quiz_CutsceneDone")

local Cutscene = {}
local _busy = false

local function getControls()
	local pm = LP:FindFirstChildOfClass("PlayerScripts")
	pm = pm and pm:FindFirstChild("PlayerModule")
	if not pm then return nil end
	local ok, mod = pcall(require, pm)
	if not ok or not mod.GetControls then return nil end
	return mod:GetControls()
end

local function letterbox(show:boolean, dur:number?)
	dur = dur or 0.25
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	local gui = pg:FindFirstChild("CutsceneLetterbox")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "CutsceneLetterbox"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 9500
		gui.Parent = pg

		local top = Instance.new("Frame"); top.Name="Top"; top.Parent=gui
		top.BackgroundColor3 = Color3.new(0,0,0)
		top.AnchorPoint = Vector2.new(0.5,0); top.Position = UDim2.fromScale(0.5,0)
		top.Size = UDim2.new(1,0,0,0)

		local bottom = Instance.new("Frame"); bottom.Name="Bottom"; bottom.Parent=gui
		bottom.BackgroundColor3 = Color3.new(0,0,0)
		bottom.AnchorPoint = Vector2.new(0.5,1); bottom.Position = UDim2.fromScale(0.5,1)
		bottom.Size = UDim2.new(1,0,0,0)
	end
	local h = show and math.floor(camera.ViewportSize.Y * 0.10) or 0
	TweenService:Create(gui.Top,    TweenInfo.new(dur), {Size = UDim2.new(10,0,0,h)}):Play()
	TweenService:Create(gui.Bottom, TweenInfo.new(dur), {Size = UDim2.new(10,0,0,h)}):Play()
end

local function showSkipHint(enable:boolean)
	local pg = LP:FindFirstChildOfClass("PlayerGui")
	local gui = pg:FindFirstChild("CutsceneSkip")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "CutsceneSkip"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 9600
		gui.Enabled = false
		gui.Parent = pg

		local lbl = Instance.new("TextLabel"); lbl.Name="Hint"; lbl.Parent=gui
		lbl.AnchorPoint = Vector2.new(1,1)
		lbl.Position   = UDim2.fromScale(0.98, 0.95)
		lbl.Size       = UDim2.fromScale(0.46, 0.06)
		lbl.BackgroundTransparency = 0.25
		lbl.BackgroundColor3 = Color3.fromRGB(20,20,20)
		lbl.TextColor3 = Color3.new(1,1,1)
		lbl.TextScaled = true
		lbl.Font = Enum.Font.GothamMedium
		lbl.Text = UIS.TouchEnabled and "화면을 탭하면 건너뜀" or "SPACE 키로 건너뛰기"
		Instance.new("UICorner", lbl).CornerRadius = UDim.new(0,10)
	end
	gui.Enabled = enable
end

local function findPortal(stage:number)
	return workspace.Stage01:FindFirstChild(string.format("Stage%dPotal", stage))
end

-- 공개 API
function Cutscene.PlayPortalOpen(stage:number, opts:table?)
	if _busy then return end
	_busy = true
	opts = opts or {}

	local controls = getControls(); if controls then controls:Disable() end

	local oldType = camera.CameraType
	local oldCF   = camera.CFrame
	local oldFOV  = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	local function finalize()
		showSkipHint(false)
		letterbox(false, 0.2)
		camera.CameraType  = oldType
		camera.CFrame      = oldCF
		camera.FieldOfView = oldFOV
		if controls then controls:Enable() end
		_busy = false
		print("[Cutscene] done -> FireServer Quiz_CutsceneDone")
		RE_CutsceneDone:FireServer({ type = "portal_open", stage = stage })
	end

	letterbox(true, 0.2)
	task.delay(0.15, function() showSkipHint(true) end)

	local skipped = false
	local conn1, conn2
	if opts.allowSkip ~= false then
		conn1 = UIS.InputBegan:Connect(function(input, gp)
			if gp then return end
			if input.KeyCode == Enum.KeyCode.Space then skipped = true end
		end)
		conn2 = UIS.TouchEnded:Connect(function() skipped = true end)
	end

	local portal = findPortal(stage)
	if not portal then
		warn("[Cutscene] portal not found, finalize immediately")
		if conn1 then conn1:Disconnect() end
		if conn2 then conn2:Disconnect() end
		finalize(); return
	end

	-- 문 앞 방향 자동 판별
	local pivot = (portal:IsA("Model") and portal:GetPivot()) or CFrame.new(portal:GetBoundingBox())
	local front = pivot.LookVector
	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Blacklist
		params.FilterDescendantsInstances = { portal }
		local hit = workspace:Raycast(pivot.Position + pivot.UpVector*2, front*6, params)
		if hit then front = -front end
	end

	local target = pivot.Position + front * 0.2
	local up     = pivot.UpVector
	local A = CFrame.lookAt(target + front * 12 + up * 4, target)
	local B = CFrame.lookAt(target + front *  8 + up * 3, target)
	local C = CFrame.lookAt(target + front *  4 + up * 2, target)

	local function step(toCF, fov, dur)
		if skipped then camera.CFrame = toCF; if fov then camera.FieldOfView = fov end; return true end
		local goals = { CFrame = toCF }; if fov then goals.FieldOfView = fov end
		local tw = TweenService:Create(camera, TweenInfo.new(dur or 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), goals)
		tw:Play()
		local skipConn
		if opts.allowSkip ~= false then
			skipConn = UIS.InputBegan:Connect(function(input, gp)
				if gp then return end
				if input.KeyCode == Enum.KeyCode.Space then
					skipped = true; tw:Cancel(); camera.CFrame = toCF; if fov then camera.FieldOfView = fov end
				end
			end)
		end
		tw.Completed:Wait()
		if skipConn then skipConn:Disconnect() end
		return skipped
	end

	camera.CFrame = A; camera.FieldOfView = 70
	if step(B, 72, 0.7) then if conn1 then conn1:Disconnect() end; if conn2 then conn2:Disconnect() end; finalize(); return end

	-- 효과음(선택)
	local ok,_ = pcall(function()
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://12222128"
		s.Volume = 0.35; s.RollOffMaxDistance = 120; s.Parent = portal
		s:Play(); Debris:AddItem(s, 3)
	end)

	if step(C, 74, 0.8) then if conn1 then conn1:Disconnect() end; if conn2 then conn2:Disconnect() end; finalize(); return end
	if step(C * CFrame.new(0,0,-1.5), 76, 0.7) then if conn1 then conn1:Disconnect() end; if conn2 then conn2:Disconnect() end; finalize(); return end

	if conn1 then conn1:Disconnect() end
	if conn2 then conn2:Disconnect() end
	finalize()
end

function Cutscene.PlayPortalSpawnAt(payload)
	if _busy then return end
	_busy = true

	local stage        = tonumber(payload.stage) or 1
	local targetPos    = payload.targetPos :: Vector3
	local dropTime     = tonumber(payload.dropTime)    or 1.0
	local dropDelay    = tonumber(payload.dropDelay)   or 0.2
	local dropHeight   = tonumber(payload.dropHeight)  or 40
	local camBack      = tonumber(payload.camBack)     or 20   -- 월드 Z축 뒤로 빠지는 거리
	local lookUpBelow  = tonumber(payload.lookUpBelow) or 0    -- 포탈보다 카메라를 얼마나 아래에서 올려다볼지

	local RunService   = game:GetService("RunService")
	local controls = getControls(); if controls then controls:Disable() end

	-- 카메라 백업 및 스크립트 모드
	local oldType, oldCF, oldFOV = camera.CameraType, camera.CFrame, camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable

	-- 이징(서버 드롭과 동기: OutCubic)
	local function outCubic(t) return 1 - (1 - t) ^ 3 end

	-- 인트로: 포탈 시작 높이 위/아래 관계 설정 (카메라는 Z만 뒤로, X는 포탈과 정렬)
	local startPortalY = targetPos.Y + dropHeight
	local introPortal  = Vector3.new(targetPos.X, startPortalY, targetPos.Z)
	local introCamPos  = Vector3.new(targetPos.X, startPortalY - lookUpBelow, targetPos.Z - camBack)
	camera.CFrame      = CFrame.lookAt(introCamPos, introPortal, Vector3.yAxis)
	camera.FieldOfView = 76

	-- 드롭 시작 시각
	local startTime = os.clock() + dropDelay

	-- 프레임 업데이트: 포탈과 카메라가 함께 하강 (카메라는 Z고정, X고정, Y만 변화)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()

		-- 드롭 전 대기: 인트로 구도 유지
		if now < startTime then
			camera.CFrame = CFrame.lookAt(introCamPos, introPortal, Vector3.yAxis)
			return
		end

		-- 0~1 보간
		local t = math.clamp((now - startTime) / dropTime, 0, 1)
		local f = outCubic(t)

		-- 포탈 현재 높이(서버 드롭과 동일 곡선)
		local curY = targetPos.Y + (1 - f) * dropHeight
		local portalPos = Vector3.new(targetPos.X, curY, targetPos.Z)

		-- 카메라: X는 포탈 X, Z는 targetPos.Z - camBack(고정), Y는 포탈보다 lookUpBelow만큼 아래
		local camPos = Vector3.new(targetPos.X, curY - lookUpBelow, targetPos.Z - camBack)
		camera.CFrame = CFrame.lookAt(camPos, portalPos, Vector3.yAxis)

		-- 종료 처리
		if t >= 1 then
			conn:Disconnect(); conn = nil
			-- 착지 후 살짝 안정화(카메라는 여전히 월드 Z축 뒤, 약간만 위로 보정)
			local settleCamY = targetPos.Y - math.max(lookUpBelow - 2, 0)
			local settlePos  = Vector3.new(targetPos.X, settleCamY, targetPos.Z - camBack)
			local finalLook  = CFrame.lookAt(settlePos, targetPos, Vector3.yAxis)

			local tw = TweenService:Create(
				camera,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ CFrame = finalLook, FieldOfView = 72 }
			)
			tw:Play()
			tw.Completed:Wait()

			-- 복구
			camera.CameraType  = oldType
			camera.CFrame      = oldCF
			camera.FieldOfView = oldFOV
			if controls then controls:Enable() end
			_busy = false
		end
	end)
end


return Cutscene
