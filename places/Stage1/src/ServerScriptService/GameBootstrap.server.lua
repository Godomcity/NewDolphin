-- ServerScriptService/GameBootstrap.lua
-- 텔레포트 데이터로 속성 세팅 + 화이트리스트 기반 Role 강제 오버라이드

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Roles = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Roles"))
local RoleConfig = require(script.Parent:WaitForChild("RoleConfig"))

local function applyFromTeleportData(player: Player, td: table)
        if not td then return end
        local function setAttr(k, v) player:SetAttribute(k, v) end

        if td.session then
                setAttr("SessionId", tostring(td.session.id or ""))
                setAttr("InviteCode", tostring(td.session.invite or ""))
                setAttr("Role", tostring(td.session.role or "")) -- 호환용
                setAttr("PartyId", tostring(td.session.partyId or ""))
        end
        if td.player then
                setAttr("Device", tostring(td.player.device or "")) -- "mobile"|"desktop"
                -- 최신 스키마: TeleportData.player.userRole
                setAttr("userRole", tostring(td.player.userRole or ""))
        end

        if typeof(td.userRole) == "string" and td.userRole ~= "" then
                setAttr("userRole", td.userRole)
        end

        setAttr("SelectedStage", tonumber(td.selectedStage or 1))
end

local function enforceRoleOverride(player: Player, td: table?)
        -- userRole > legacy session.role > optional whitelist fallback
        local role = ""
        if td then
                if td.player and typeof((td.player :: any).userRole) == "string" then
                        role = td.player.userRole
                elseif typeof((td :: any).userRole) == "string" then
                        role = td.userRole
                elseif td.session and typeof((td.session :: any).role) == "string" then
                        role = td.session.role
                end
        end

        if role == "" then
                -- 호환: 기존 Role/TEACHER_IDS 기반
                for userId in pairs(RoleConfig.TEACHER_IDS) do
                        if player.UserId == userId then
                                role = Roles.TEACHER
                                break
                        end
                end
        end

        player:SetAttribute("Role", tostring(role or ""))
        player:SetAttribute("userRole", tostring(role or ""))
        player:SetAttribute("isTeacher", Roles.isTeacherRole(role))
end

Players.PlayerAdded:Connect(function(plr)
        local td
        pcall(function() td = TeleportService:GetPlayerTeleportData(plr) end)

        -- 텔레포트 데이터 반영(있으면)
        if td then
                applyFromTeleportData(plr, td)
        else
                -- 기본값
                plr:SetAttribute("SelectedStage", 1)
        end

        -- ✅ 최종 Role은 텔레포트 데이터/ROLE_TEACHER 기반으로 동기화
        enforceRoleOverride(plr, td)
end)
