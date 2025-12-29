-- ReplicatedStorage/Modules/Roles.lua
--!strict

local Roles = {}

Roles.TEACHER = "ROLE_TEACHER"

function Roles.isTeacherRole(role: any): boolean
	return typeof(role) == "string" and role == Roles.TEACHER
end

return Roles
