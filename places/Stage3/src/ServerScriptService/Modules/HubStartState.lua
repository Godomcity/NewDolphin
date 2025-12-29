-- ServerScriptService/Modules/HubStartState.lua
--!strict
-- Hub에서 퀴즈 시작 여부를 "세션 단위"로 저장 / 조회 / 삭제

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
local TTL_SEC = 6 * 60 * 60 -- 6시간 (원하면 늘려도 됨)

----------------------------------------------------------------
-- 타입
----------------------------------------------------------------
export type StartState = {
	started: boolean,
	startedAt: number,
	byUserId: number?,
}

----------------------------------------------------------------
-- 내부 유틸
----------------------------------------------------------------
local function makeKey(sessionId: string): string
	return "SID:" .. sessionId
end

----------------------------------------------------------------
-- API
----------------------------------------------------------------
local HubStartState = {}

-- ▶ 시작 상태 저장
function HubStartState.SetStarted(sessionId: string, byUserId: number?): (boolean, string?)
	if sessionId == "" then
		return false, "invalid_sessionId"
	end

	local state: StartState = {
		started   = true,
		startedAt = os.time(),
		byUserId = byUserId,
	}

	local key = makeKey(sessionId)

	-- MemoryStore
	pcall(function()
		MEM_MAP:SetAsync(key, state, TTL_SEC)
	end)

	-- DataStore
	pcall(function()
		DS:SetAsync(key, state)
	end)

	return true, nil
end

-- ▶ 시작 여부 조회
function HubStartState.IsStarted(sessionId: string): (boolean, StartState?)
	if sessionId == "" then
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

-- ▶ 시작 상태 삭제 (내가 원할 때 호출)
function HubStartState.Clear(sessionId: string): boolean
	if sessionId == "" then
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

----------------------------------------------------------------
-- 디버그용 (선택)
----------------------------------------------------------------
function HubStartState._DebugDump(sessionId: string)
	local key = makeKey(sessionId)
	print("MEM:", pcall(function() return MEM_MAP:GetAsync(key) end))
	print("DS :", pcall(function() return DS:GetAsync(key) end))
end

return HubStartState
