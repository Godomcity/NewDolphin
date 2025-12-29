-- ServerScriptService/SessionBootstrap.server.lua
--!strict
-- 플레이어가 텔레포트로 들어왔을 때
-- TeleportData 안에 있는 sessionId/session.id 를 Player.Attribute("sessionId") 로 복원
-- + userRole / isTeacher / roomCode 도 같이 복원
-- + Stage3에서는 SessionResume에 "지금 Stage3에 있다" 라는 정보도 저장
-- + 디버그용으로 JobId / TeleportData 로그

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService          = game:GetService("RunService")

local SessionResume = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("SessionResume"))

local playerPassThrough = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerPassThrough"))
playerPassThrough.Enable()

local STAGE_NUMBER = 3

----------------------------------------------------------------
-- TeleportData Extractors
----------------------------------------------------------------
local function extractSessionId(td: any): string?
        if typeof(td) ~= "table" then return nil end

        -- ① 옛 구조: TeleportData.sessionId
        if typeof(td.sessionId) == "string" and #td.sessionId > 0 then
                return td.sessionId
        end

        -- ② 신 구조: TeleportData.session.id
        local sess = (td :: any).session
        if typeof(sess) == "table" and typeof((sess :: any).id) == "string" and #((sess :: any).id) > 0 then
                return (sess :: any).id
        end

        return nil
end

local function extractUserRole(td: any): string?
        if typeof(td) ~= "table" then return nil end

        -- ✅ 권장: TeleportData.player.userRole
        local p = (td :: any).player
        if typeof(p) == "table" and typeof((p :: any).userRole) == "string" and #((p :: any).userRole) > 0 then
                return (p :: any).userRole
        end

        -- (호환) TeleportData.userRole
        if typeof((td :: any).userRole) == "string" and #((td :: any).userRole) > 0 then
                return (td :: any).userRole
        end

        -- (호환) TeleportData.session.player.userRole
        local sess = (td :: any).session
        if typeof(sess) == "table" then
                local sp = (sess :: any).player
                if typeof(sp) == "table" and typeof((sp :: any).userRole) == "string" and #((sp :: any).userRole) > 0 then
                        return (sp :: any).userRole
                end
        end

        return nil
end

local function extractRoomCode(td: any): string?
        if typeof(td) ~= "table" then return nil end

        -- ✅ 권장: TeleportData.session.roomCode
        local sess = (td :: any).session
        if typeof(sess) == "table" and typeof((sess :: any).roomCode) == "string" and #((sess :: any).roomCode) > 0 then
                return (sess :: any).roomCode
        end

        -- (호환) TeleportData.roomCode
        if typeof((td :: any).roomCode) == "string" and #((td :: any).roomCode) > 0 then
                return (td :: any).roomCode
        end

        return nil
end

local function isTeacherRole(role: string?): boolean
        return role == "ROLE_TEACHER"
end

local function extractJoinData(plr: Player): any?
        local ok, joinData = pcall(function()
                return plr:GetJoinData()
        end)
        if not ok or typeof(joinData) ~= "table" then
                return nil
        end
        return joinData
end

----------------------------------------------------------------
-- Debug
----------------------------------------------------------------
local function debugPrintJoinData(plr: Player, joinData: any?)
        if typeof(joinData) ~= "table" then
                print("[Stage3 SessionBootstrap]", plr.Name, "JoinData missing")
                return
        end

        local td = joinData.TeleportData
        if typeof(td) ~= "table" then
                print("[Stage3 SessionBootstrap]", plr.Name, "TeleportData missing")
                return
        end

        local sess = (td :: any).session
        local sid  = extractSessionId(td)
        local priv = nil
        local reason = (td :: any).reason
        local fromPlaceId = (td :: any).fromPlaceId

        local userRole = extractUserRole(td)
        local roomCode = extractRoomCode(td)

        if typeof(sess) == "table" then
                priv = (sess :: any).privateServerCode
        end

        print(string.format(
                "[Stage3 SessionBootstrap] JobId=%s PlaceId=%d Player=%s sessionId=%s privateCode=%s fromPlaceId=%s reason=%s userRole=%s roomCode=%s",
                game.JobId,
                game.PlaceId,
                plr.Name,
                tostring(sid),
                tostring(priv),
                tostring(fromPlaceId),
                tostring(reason),
                tostring(userRole),
                tostring(roomCode)
                ))
end

----------------------------------------------------------------
-- Main
----------------------------------------------------------------
Players.PlayerAdded:Connect(function(plr: Player)
        print(string.format(
                "[Stage3 SessionBootstrap] PlayerAdded JobId=%s PlaceId=%d Player=%s",
                game.JobId, game.PlaceId, plr.Name
                ))

        local joinData = extractJoinData(plr)
        local td = (typeof(joinData) == "table") and joinData.TeleportData or nil

        -- 1) sessionId 복원
        do
                local sid = plr:GetAttribute("sessionId")
                if typeof(sid) ~= "string" or sid == "" then
                        local extracted = extractSessionId(td)
                        if extracted and extracted ~= "" then
                                plr:SetAttribute("sessionId", extracted)
                        elseif RunService:IsStudio() then
                                -- Studio 디버그 폴백
                                local fakeSid = string.format("local-%d-%d", plr.UserId, os.time())
                                plr:SetAttribute("sessionId", fakeSid)
                        end
                end
        end

        -- 2) userRole / isTeacher / roomCode 복원
        do
                local roleAttr = plr:GetAttribute("userRole")
                if typeof(roleAttr) ~= "string" or roleAttr == "" then
                        local role = extractUserRole(td)
                        if role and role ~= "" then
                                plr:SetAttribute("userRole", role)
                                plr:SetAttribute("isTeacher", isTeacherRole(role))
                        end
                else
                        -- 이미 있으면 boolean만 보정
                        plr:SetAttribute("isTeacher", isTeacherRole(roleAttr))
                end

                local roomAttr = plr:GetAttribute("roomCode")
                if typeof(roomAttr) ~= "string" or roomAttr == "" then
                        local rc = extractRoomCode(td)
                        if rc and rc ~= "" then
                                plr:SetAttribute("roomCode", rc)
                        end
                end
        end

        local finalSid = plr:GetAttribute("sessionId")
        print(("[Stage3 SessionBootstrap] %s sessionId=%s userRole=%s isTeacher=%s roomCode=%s"):format(
                plr.Name,
                tostring(finalSid),
                tostring(plr:GetAttribute("userRole")),
                tostring(plr:GetAttribute("isTeacher")),
                tostring(plr:GetAttribute("roomCode"))
                ))

        -- 디버그 로그
        debugPrintJoinData(plr, joinData)

        -- 3) Stage3 재접속용 Resume 저장
        if typeof(finalSid) == "string" and finalSid ~= "" then
                print(("[Stage3 SessionBootstrap] Save Resume: userId=%d sid=%s stage=%d placeId=%d"):format(
                        plr.UserId, finalSid, STAGE_NUMBER, game.PlaceId
                        ))
                SessionResume.Save(plr, finalSid, STAGE_NUMBER, game.PlaceId)
        end
end)

print("[Stage3 SessionBootstrap] READY (sessionId + userRole/isTeacher/roomCode + SessionResume + debug)")
