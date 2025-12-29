-- ServerScriptService/Modules/HubStartState.lua
--!strict
-- Hub에서 "퀴즈 시작됨" 여부를 세션(sessionId) 단위로 저장 / 조회 / 삭제

local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService   = game:GetService("DataStoreService")

----------------------------------------------------------------
-- 저장소
----------------------------------------------------------------
local MEM_MAP = MemoryStoreService:GetSortedMap("HubStarted_MEM_V1")
local DS      = DataStoreService:GetDataStore("HubStarted_DS_V1")

----------------------------------------------------------------
-- 설정
----------------------------------------------------------------
local TTL_SEC = 6 * 60 * 60 -- 6시간 (원하면 변경)

----------------------------------------------------------------
-- 타입
----------------------------------------------------------------
export type StartState = {
	started: boolean,
	startedAt: number,
}

----------------------------------------------------------------
-- 내부 유틸
----------------------------------------------------------------
local function makeKey(sessionId: string): string
	return "SID:" .. sessionId
end

local function isValidSessionId(sessionId: any): boolean
	return (typeof(sessionId) == "string" and #sessionId > 0)
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
local HubStartState = {}

-- ▶ 시작 상태 저장 (sessionId 기준)
function HubStartState.SetStarted(sessionId: string): (boolean, string?)
	if not isValidSessionId(sessionId) then
		return false, "invalid_sessionId"
	end

	local state: StartState = {
		started   = true,
		startedAt = os.time(),
	}

	local key = makeKey(sessionId)

	-- MemoryStore (빠른 조회 + TTL)
	pcall(function()
		MEM_MAP:SetAsync(key, state, TTL_SEC)
	end)

	-- DataStore (영속)
	pcall(function()
		DS:SetAsync(key, state)
	end)

	return true, nil
end

-- ▶ 시작 여부 조회
function HubStartState.IsStarted(sessionId: string): (boolean, StartState?)
	if not isValidSessionId(sessionId) then
		return false, nil
	end

	local key = makeKey(sessionId)

	-- 1) MemoryStore 우선
	local okMem, mem = pcall(function()
		return MEM_MAP:GetAsync(key)
	end)

	if okMem and typeof(mem) == "table" and mem.started == true then
		return true, mem :: StartState
	end

	-- 2) DataStore 폴백
	local okDs, ds = pcall(function()
		return DS:GetAsync(key)
	end)

	if okDs and typeof(ds) == "table" and ds.started == true then
		-- 캐시 복구
		pcall(function()
			MEM_MAP:SetAsync(key, ds, TTL_SEC)
		end)
		return true, ds :: StartState
	end

	return false, nil
end

-- ▶ 시작 상태 삭제 (sessionId 기준으로만 삭제)
function HubStartState.Clear(sessionId: string): boolean
	if not isValidSessionId(sessionId) then
		return false
	end

	local key = makeKey(sessionId)

	-- MemoryStore 삭제
	pcall(function()
		MEM_MAP:RemoveAsync(key)
	end)

	-- DataStore 삭제
	pcall(function()
		DS:RemoveAsync(key)
	end)

	return true
end

return HubStartState
