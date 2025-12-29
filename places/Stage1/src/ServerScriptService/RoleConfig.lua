-- ServerScriptService/RoleConfig.lua
-- 임시 교사 화이트리스트: 여기에 UserId 추가하면 해당 유저는 교사로 강제 설정됨
local RoleConfig = {}

RoleConfig.TEACHER_IDS = {
        -- userRole/ROLE_TEACHER 기반으로 판별하므로 기본값은 비워둠
        -- [1234567890] = true,
}

return RoleConfig
