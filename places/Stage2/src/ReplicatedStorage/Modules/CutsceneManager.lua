-- ReplicatedStorage/Modules/CutsceneManager.lua
--!strict
-- 목적:
--  - 어떤 컷씬이든 시작할 때 이전 컷씬을 "정상 종료/강제 종료" 할 수 있게 공통 토큰 제공
--  - Tween / task.delay 콜백 / RBXScriptConnection 을 토큰에 등록
--  - StopAll() 시: 취소 플래그 + 트윈 Cancel + 연결 Disconnect + onCancel 훅 실행

local TweenService = game:GetService("TweenService")

export type Token = {
	id: number,
	name: string,
	cancelled: boolean,

	AddTween: (self: Token, tween: Tween) -> Tween,
	AddConnection: (self: Token, conn: RBXScriptConnection) -> RBXScriptConnection,
	Delay: (self: Token, sec: number, fn: () -> ()) -> (),
	OnCancel: (self: Token, fn: () -> ()) -> (),
	Finish: (self: Token) -> (),
	Cancel: (self: Token, reason: string?) -> (),
	IsActive: (self: Token) -> boolean,
}

local M = {}

local _nextId = 0
local _active: Token? = nil

local function newToken(name: string): Token
	_nextId += 1
	local myId = _nextId

	local tweens: {Tween} = {}
	local conns: {RBXScriptConnection} = {}
	local onCancelFns: {() -> ()} = {}

	local token = {} :: any
	token.id = myId
	token.name = name
	token.cancelled = false

	function token:IsActive(): boolean
		return (not token.cancelled) and (_active == token)
	end

	function token:AddTween(t: Tween): Tween
		table.insert(tweens, t)
		return t
	end

	function token:AddConnection(c: RBXScriptConnection): RBXScriptConnection
		table.insert(conns, c)
		return c
	end

	-- task.delay는 취소가 안 되므로, 콜백 내부에서 token:IsActive() 체크로 "무효화" 처리
	function token:Delay(sec: number, fn: () -> ())
		task.delay(sec, function()
			if token:IsActive() then
				fn()
			end
		end)
	end

	function token:OnCancel(fn: () -> ())
		table.insert(onCancelFns, fn)
	end

	function token:Finish()
		-- 내가 active면 정리
		if _active == token then
			_active = nil
		end
	end

	function token:Cancel(reason: string?)
		if token.cancelled then return end
		token.cancelled = true

		-- 트윈 중지
		for i = #tweens, 1, -1 do
			local tw = tweens[i]
			tweens[i] = nil
			if tw then
				pcall(function() tw:Cancel() end)
			end
		end

		-- 연결 해제
		for i = #conns, 1, -1 do
			local c = conns[i]
			conns[i] = nil
			if c then
				pcall(function() c:Disconnect() end)
			end
		end

		-- onCancel 훅 (카메라/컨트롤 복원 같은 것)
		for i = #onCancelFns, 1, -1 do
			local f = onCancelFns[i]
			onCancelFns[i] = nil
			if f then
				pcall(f)
			end
		end

		if _active == token then
			_active = nil
		end
	end

	return token :: Token
end

function M.StopAll(reason: string?)
	if _active then
		_active:Cancel(reason or "StopAll")
	end
end

function M.Begin(name: string): Token
	-- 새 컷씬 시작 시 이전 컷씬 강제 종료
	M.StopAll("Begin:" .. name)

	local t = newToken(name)
	_active = t
	return t
end

function M.GetActive(): Token?
	return _active
end

return M
