-- ServerScriptService/Modules/SessionResume.lua
--!strict
-- 플레이어가 "마지막으로 어느 세션/스테이지에 있었는지"를 저장/조회하는 모듈
--  - Save(player, sessionId, stage, placeId, userRole)
--  - Get(userId) -> { sessionId, stage, placeId, updatedAt, userRole }?
--  - Clear(userId)

local DataStoreService = game:GetService("DataStoreService")

-- DataStore 이름은 필요에 따라 바꿔도 됨 (버전 변경 시 뒤에 _v2 등)
local RESUME_DS = DataStoreService:GetDataStore("SessionResume_v1")

export type ResumeData = {
sessionId: string,
stage: number?,
placeId: number?,
updatedAt: number?,
userRole: string?,
}

local KEY_PREFIX = "U:"

local M = {}

local function getKey(userId: number): string
	return KEY_PREFIX .. tostring(userId)
end

-- 플레이어가 특정 세션/스테이지에 "안착"했을 때 호출
--  예: Stage2 입구에 도착했을 때 Save(player, sid, 2, Stage2PlaceId)
function M.Save(player: Player, sessionId: string, stage: number?, placeId: number?, userRole: string?)
local key = getKey(player.UserId)

local toSave: ResumeData = {
sessionId = sessionId,
stage = stage,
placeId = placeId,
updatedAt = os.time(),
userRole = userRole,
}

	local ok, err = pcall(function()
		-- 간단히 SetAsync 사용 (너무 자주 저장하면 쿨다운 걸릴 수 있으니, 중요한 순간에만 Save 호출!)
		RESUME_DS:SetAsync(key, toSave)
	end)

	if not ok then
		warn("[SessionResume] Save failed:", err)
	end
end

-- 재접속 시 userId로 마지막 상태 조회
function M.Get(userId: number): ResumeData?
	local key = getKey(userId)

	local ok, data = pcall(function()
		return RESUME_DS:GetAsync(key)
	end)

	if not ok then
		warn("[SessionResume] Get failed:", data)
		return nil
	end

	if data == nil then
		return nil
	end

	-- 타입 단언
	local resume = data :: ResumeData
	return resume
end

-- 세션이 완전히 끝났을 때(최종 결과 보고 종료 같은 타이밍)에 호출해서 슬롯 비우기
function M.Clear(userId: number)
	local key = getKey(userId)

	local ok, err = pcall(function()
		RESUME_DS:RemoveAsync(key)
	end)

	if not ok then
		warn("[SessionResume] Clear failed:", err)
	end
end

return M
