-- ReplicatedStorage/QuizRemotes 를 항상 선생성 (클라 WaitForChild 무한대기 방지)
local RS = game:GetService("ReplicatedStorage")

local rem = RS:FindFirstChild("QuizRemotes")
if not rem then
	rem = Instance.new("Folder")
	rem.Name = "QuizRemotes"
	rem.Parent = RS
end

local function ensure(name: string)
	local ev = rem:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = rem
	end
	return ev
end

ensure("EV_StartQuiz")     -- 교사 UI -> 서버
ensure("RE_Cutscene")      -- 서버 -> 클라 (컷씬 명령)
ensure("RE_CutsceneDone")  -- 클라 -> 서버 (컷씬 종료 Ack)

print("[RemotesBootstrap] QuizRemotes ready")
