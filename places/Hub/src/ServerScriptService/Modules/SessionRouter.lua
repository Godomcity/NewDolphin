-- ServerScriptService/Modules/SessionRouter.lua
--!strict
-- 세션ID + targetPlaceId 조합으로 프라이빗(예약) 서버 코드를 MemoryStore에 캐시하고 재사용
-- 없으면 ReserveServer로 새로 만들고 저장
-- ⚠️ 동시 호출 시 서로 다른 코드가 생기지 않도록 UpdateAsync + pending 락 사용

local TeleportService      = game:GetService("TeleportService")
local MemoryStoreService   = game:GetService("MemoryStoreService")

local MAP     = MemoryStoreService:GetSortedMap("SESSION_RESERVED_CODES_V1")
local TTL_SEC = 6 * 60 * 60 -- 6시간 캐시

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

	-- 이 호출이 락 주인인지 구분하기 위한 id
	local requestId = string.format("%s-%d-%d", game.JobId, targetPlaceId, math.random(100000, 999999))

	----------------------------------------------------------------
	-- 1) UpdateAsync로 기존 코드 / pending 락 확인 또는 내가 락 잡기
	----------------------------------------------------------------
	local okUpdate, dataOrErr = pcall(function()
		return MAP:UpdateAsync(k, function(old)
			-- 이미 code 있으면 그대로 유지
			if typeof(old) == "table" then
				if typeof(old.code) == "string" and #old.code > 0 then
					return old
				end
				-- 다른 서버가 이미 pending 락을 잡았으면 그대로 둠
				if typeof(old.pending) == "string" and #old.pending > 0 then
					return old
				end
			end

			-- 아무도 안 잡고 있으면, 내가 pending 락을 잡는다
			return {
				pending   = requestId,
				createdAt = os.time(),
			}
		end, TTL_SEC)
	end)

	if not okUpdate then
		return false, nil, "update_failed:" .. tostring(dataOrErr)
	end

	local data = dataOrErr

	-- 1-1) 이미 code가 있었다면 그걸 바로 사용
	if typeof(data) == "table" and typeof(data.code) == "string" and #data.code > 0 then
		return true, data.code, nil
	end

	----------------------------------------------------------------
	-- 2) 내가 pending 락의 주인이라면 → 실제 ReserveServer 수행
	----------------------------------------------------------------
	if typeof(data) == "table" and data.pending == requestId then
		local okReserve, codeOrErr = pcall(function()
			return TeleportService:ReserveServer(targetPlaceId)
		end)
		if not okReserve then
			-- 실패 시 이 키를 지워서 다음 호출이 다시 시도할 수 있게 한다
			pcall(function()
				MAP:RemoveAsync(k)
			end)
			return false, nil, "reserve_failed:" .. tostring(codeOrErr)
		end

		local code: string = codeOrErr

		-- code 저장 (실패해도 텔레포트에는 영향 없음)
		pcall(function()
			MAP:SetAsync(k, {
				code      = code,
				createdAt = os.time(),
			}, TTL_SEC)
		end)

		return true, code, nil
	end

	----------------------------------------------------------------
	-- 3) 나는 락 주인이 아님 → 다른 서버가 ReserveServer 중.
	--    잠깐 기다리면서 code가 채워지기를 폴링.
	----------------------------------------------------------------
	for _ = 1, 10 do -- 최대 2초 정도 기다림
		task.wait(0.2)

		local okGet, value = pcall(function()
			return MAP:GetAsync(k)
		end)

		if okGet and typeof(value) == "table" and typeof(value.code) == "string" and #value.code > 0 then
			return true, value.code, nil
		end
	end

	return false, nil, "wait_code_timeout"
end

-------------------------------------------------
-- 세션 정리용: 해당 세션 + 플레이스로 예약 코드 삭제
-------------------------------------------------
function M.Clear(sessionId: string, targetPlaceId: number)
	local k = key(sessionId, targetPlaceId)
	local ok, err = pcall(function()
		MAP:RemoveAsync(k)
	end)
	if not ok then
		warn("[SessionRouter] Clear failed:", sessionId, targetPlaceId, err)
	end
end

return M
