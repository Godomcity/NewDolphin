-- ReplicatedStorage/Modules/StageRolePolicy.lua
--!strict

local M = {}

-- ★ 선생님 계정(UserId) 목록
local TEACHER_USER_IDS: {[number]: boolean} = {
	[2783482612] = true, -- 여기에 선생님 UserId들 추가
	-- [123456789] = true,
}

function M.IsTeacher(plr: Player): boolean
	if not plr or not plr.UserId then
		return false
	end
	return TEACHER_USER_IDS[plr.UserId] == true
end

-- 이 플레이어가 "스테이지 클라이언트 흐름(퀴즈/컷씬/포탈)"을 스킵해야 하는지
function M.ShouldSkipStageClientFlow(plr: Player): boolean
	return M.IsTeacher(plr)
end

return M
