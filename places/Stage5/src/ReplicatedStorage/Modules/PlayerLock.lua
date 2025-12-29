-- ReplicatedStorage/Modules/PlayerLock2.lua
--!strict
-- PlayerModule(Controls)로 이동만 정지 + 카메라 Scriptable 고정 + (옵션) 입력 Sink

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local LP = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local M = {}

export type LockOptions = {
	freezeMovement: boolean?, -- 기본 true (PlayerModule Controls)
	freezeCamera: boolean?,   -- 기본 true (Scriptable)
	disableInput: boolean?,   -- 기본 false (원하면 전체 입력 Sink)
	cameraCFrame: CFrame?,    -- nil이면 잠그는 순간 카메라 위치로 고정
}

local ACTION_NAME = "__PLAYERLOCK2_INPUT__"

local state = {
	locked = false,

	-- PlayerModule Controls
	controls = nil :: any,
	playerModule = nil :: any,

	-- camera restore
	prevCamType = nil :: Enum.CameraType?,
	prevCamSubject = nil :: Instance?,
	lockCamCFrame = nil :: CFrame?,
	renderConn = nil :: RBXScriptConnection?,

	lastOpts = nil :: LockOptions?,
}

local function bindInputSink()
	ContextActionService:BindAction(
		ACTION_NAME,
		function()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.UserInputType.Keyboard,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.MouseButton2,
		Enum.UserInputType.MouseButton3,
		Enum.UserInputType.MouseMovement,
		Enum.UserInputType.MouseWheel,
		Enum.UserInputType.Gamepad1,
		Enum.UserInputType.Touch
	)
end

local function unbindInputSink()
	pcall(function()
		ContextActionService:UnbindAction(ACTION_NAME)
	end)
end

local function getControls(): any?
	if state.controls then return state.controls end

	local ps = LP:WaitForChild("PlayerScripts")
	local pm = ps:WaitForChild("PlayerModule")

	local ok, playerModule = pcall(require, pm)
	if not ok then return nil end

	local controls = nil
	-- 보통 GetControls()가 있음
	if type(playerModule) == "table" and type(playerModule.GetControls) == "function" then
		controls = playerModule:GetControls()
	else
		-- 혹시 구조가 다른 경우 대비
		controls = playerModule.Controls or playerModule.controls
	end

	if controls then
		state.playerModule = playerModule
		state.controls = controls
	end

	return controls
end

local function stopMovement()
	local controls = getControls()
	if controls and type(controls.Disable) == "function" then
		controls:Disable()
	end
end

local function resumeMovement()
	local controls = state.controls or getControls()
	if controls and type(controls.Enable) == "function" then
		controls:Enable()
	end
end

local function applyCameraLock(lockCFrame: CFrame)
	if state.prevCamType == nil then
		state.prevCamType = Camera.CameraType
		state.prevCamSubject = Camera.CameraSubject
	end

	state.lockCamCFrame = lockCFrame
	Camera.CameraType = Enum.CameraType.Scriptable

	if state.renderConn then state.renderConn:Disconnect() end
	state.renderConn = RunService.RenderStepped:Connect(function()
		if state.lockCamCFrame then
			Camera.CFrame = state.lockCamCFrame
		end
	end)
end

local function restoreCamera()
	if state.renderConn then
		state.renderConn:Disconnect()
		state.renderConn = nil
	end

	if state.prevCamType ~= nil then
		Camera.CameraType = state.prevCamType
	end
	if state.prevCamSubject ~= nil then
		Camera.CameraSubject = state.prevCamSubject
	end

	state.prevCamType = nil
	state.prevCamSubject = nil
	state.lockCamCFrame = nil
end

function M.IsLocked(): boolean
	return state.locked
end

function M.Lock(opts: LockOptions?)
	opts = opts or {}
	state.lastOpts = opts

	local freezeMovement = (opts.freezeMovement ~= false)
	local freezeCamera = (opts.freezeCamera ~= false)
	local disableInput = (opts.disableInput == true)

	if state.locked then
		if freezeCamera and opts.cameraCFrame then
			applyCameraLock(opts.cameraCFrame)
		end
		return
	end

	state.locked = true

	if disableInput then
		bindInputSink()
	end

	if freezeMovement then
		stopMovement()
	end

	if freezeCamera then
		applyCameraLock(opts.cameraCFrame or Camera.CFrame)
	end
end

function M.Unlock()
	if not state.locked then return end
	state.locked = false

	unbindInputSink()
	restoreCamera()
	resumeMovement()

	state.lastOpts = nil
end

return M
