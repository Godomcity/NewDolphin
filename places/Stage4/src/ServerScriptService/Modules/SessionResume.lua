-- ServerScriptService/Modules/SessionResume.lua
--!strict
-- 플레이어가 "마지막으로 어느 세션/스테이지에 있었는지"를 저장/조회하는 모듈
--  - Save(player, sessionId, stage, placeId, userRole)
--  - Get(userId) -> { sessionId, stage, placeId, updatedAt, userRole }?
--  - Clear(userId)                 -- 특정 유저만 초기화
--  - ClearSession(sessionId)       -- 특정 세션에 속한 모든 유저 초기화
--  - ClearAll()                    -- (옵션) 전체 초기화

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

-----------------------------------------------------
-- Save / Get / Clear (기존)
-----------------------------------------------------

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

-- 세션과 상관 없이, 특정 유저 한 명의 Resume 슬롯 비우기
function M.Clear(userId: number)
	local key = getKey(userId)

	local ok, err = pcall(function()
		RESUME_DS:RemoveAsync(key)
	end)

	if not ok then
		warn("[SessionResume] Clear failed:", err)
	end
end

-----------------------------------------------------
-- 🔥 추가: sessionId 기반 전체 초기화
-----------------------------------------------------

-- 특정 sessionId에 해당하는 모든 유저의 Resume 데이터 제거
--   예) 선생님이 "이 세션 종료" 버튼 눌렀을 때:
--       SessionResume.ClearSession(sessionId)
function M.ClearSession(sessionId: string)
	if type(sessionId) ~= "string" or sessionId == "" then
		warn("[SessionResume] ClearSession called with invalid sessionId")
		return
	end

	warn("[SessionResume] ClearSession start for sessionId =", sessionId)

	-- KEY_PREFIX("U:")로 시작하는 모든 키를 훑으면서,
	-- 저장된 data.sessionId가 인자로 받은 sessionId와 같은 것만 RemoveAsync.
	local okPages, pagesOrErr = pcall(function()
		-- pageSize = 0 → 서버가 적절히 결정 (문서 기준)
		return RESUME_DS:ListKeysAsync(KEY_PREFIX, 0)
	end)

	if not okPages then
		warn("[SessionResume] ClearSession ListKeysAsync failed:", pagesOrErr)
		return
	end

	local pages = pagesOrErr
	local removedCount = 0

	while true do
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)

		if not okPage or not page then
			warn("[SessionResume] ClearSession GetCurrentPage failed:", page)
			break
		end

		for _, keyInfo in ipairs(page) do
			local keyName = keyInfo.KeyName

			-- 키마다 실제 데이터 조회해서 sessionId 비교
			local okGet, data = pcall(function()
				return RESUME_DS:GetAsync(keyName)
			end)

			if okGet and typeof(data) == "table" then
				local resume = data :: ResumeData
				if resume.sessionId == sessionId then
					local okRem, errRem = pcall(function()
						RESUME_DS:RemoveAsync(keyName)
					end)
					if not okRem then
						warn("[SessionResume] ClearSession RemoveAsync failed for", keyName, errRem)
					else
						removedCount += 1
					end
				end
			elseif not okGet then
				warn("[SessionResume] ClearSession GetAsync failed for", keyName, data)
			end
		end

		-- 더 이상 페이지가 없으면 종료
		if pages.IsFinished then
			break
		end

		-- 다음 페이지로
		local okNext, errNext = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not okNext then
			warn("[SessionResume] ClearSession AdvanceToNextPageAsync failed:", errNext)
			break
		end
	end

	warn(("[SessionResume] ClearSession done. sessionId=%s, removed=%d"):format(sessionId, removedCount))
end

-----------------------------------------------------
-- 🔁 (선택) 전체 초기화: 모든 유저 Resume 데이터 제거
-----------------------------------------------------
-- 정말 전체 리셋이 필요할 때만 사용 (테스트/관리자용)
function M.ClearAll()
	warn("[SessionResume] ClearAll start")

	local okPages, pagesOrErr = pcall(function()
		return RESUME_DS:ListKeysAsync(KEY_PREFIX, 0)
	end)

	if not okPages then
		warn("[SessionResume] ClearAll ListKeysAsync failed:", pagesOrErr)
		return
	end

	local pages = pagesOrErr
	local removedCount = 0

	while true do
		local okPage, page = pcall(function()
			return pages:GetCurrentPage()
		end)

		if not okPage or not page then
			warn("[SessionResume] ClearAll GetCurrentPage failed:", page)
			break
		end

		for _, keyInfo in ipairs(page) do
			local keyName = keyInfo.KeyName
			local okRem, errRem = pcall(function()
				RESUME_DS:RemoveAsync(keyName)
			end)
			if not okRem then
				warn("[SessionResume] ClearAll RemoveAsync failed for", keyName, errRem)
			else
				removedCount += 1
			end
		end

		if pages.IsFinished then
			break
		end

		local okNext, errNext = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not okNext then
			warn("[SessionResume] ClearAll AdvanceToNextPageAsync failed:", errNext)
			break
		end
	end

	warn(("[SessionResume] ClearAll done. removed=%d"):format(removedCount))
end

return M
