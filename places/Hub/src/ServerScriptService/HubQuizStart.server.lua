-- ServerScriptService/HubQuizStart.server.lua
--!strict
local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = RS

local function ensureRE(name: string): RemoteEvent
	local ev = Remotes:FindFirstChild(name) :: RemoteEvent
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = Remotes
	end
	return ev
end

local EV_QuizStartRequest = ensureRE("EV_QuizStartRequest") -- 클라 → 서버
local EV_QuizStarted      = ensureRE("EV_QuizStarted")      -- 서버 → 모든 클라(포탈 컷씬)

EV_QuizStartRequest.OnServerEvent:Connect(function(player)
	-- TODO: (선택) teacher 권한 체크가 필요하면 여기서 검사
	-- ex) if not player:GetAttribute("role") == "teacher" then return end

	-- 포탈 컷씬 트리거
	EV_QuizStarted:FireAllClients()

	-- TODO: (선택) 허브 퀴즈 서비스 시작 / 포탈 오브젝트 열기 / 다음 단계 로직
	-- require(ServerScriptService.Modules.QuizService).StartForSession(player)  -- 예시
end)
