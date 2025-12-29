-- ServerScriptService/Modules/SessionRouter.lua
--!strict
-- 세션ID + targetPlaceId 조합으로 프라이빗(예약) 서버 코드를 MemoryStore에 캐시하고 재사용
-- 없으면 ReserveServer로 새로 만들고 저장

local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local MAP = MemoryStoreService:GetSortedMap("SESSION_RESERVED_CODES_V1")
local TTL_SEC = 6 * 60 * 60 -- 6시간 캐시(선택)

local M = {}

local function key(sessionId: string, placeId: number): string
	return string.format("sid:%s|pid:%d", sessionId, placeId)
end

-- 성공시 (true, code, nil), 실패시 (false, nil, err)
function M.GetOrCreate(sessionId: string, targetPlaceId: number): (boolean, string?, string?)
	if type(sessionId) ~= "string" or sessionId == "" then
		return false, nil, "missing_sessionId"
	end
	local k = key(sessionId, targetPlaceId)

	-- 1) 기존 코드 조회
	local okGet, value = pcall(function()
		return MAP:GetAsync(k)
	end)
	if okGet and typeof(value) == "table" and typeof(value.code) == "string" and #value.code > 0 then
		return true, value.code, nil
	end

	-- 2) 새로 예약 생성
	local okReserve, codeOrErr = pcall(function()
		return TeleportService:ReserveServer(targetPlaceId)
	end)
	if not okReserve then
		return false, nil, "reserve_failed:" .. tostring(codeOrErr)
	end
	local code: string = codeOrErr

	-- 3) 저장(만료는 선택적으로 사용)
	pcall(function()
		-- 일부 환경에서 expiration 전달 파라미터가 없을 수 있으므로 값만 넣어도 무방
		MAP:SetAsync(k, { code = code, createdAt = os.time() }, TTL_SEC)
	end)

	return true, code, nil
end

return M
