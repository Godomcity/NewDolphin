-- ServerScriptService/RoleConfig.lua
-- 임시 교사 화이트리스트: 여기에 UserId 추가하면 해당 유저는 교사로 강제 설정됨
local RoleConfig = {}

RoleConfig.TEACHER_IDS = {
	[2783482612] = true,  -- ✅ 요청한 선생님 계정
	-- [1234567890] = true, -- 필요시 추가
}

return RoleConfig
