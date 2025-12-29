local Players      = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local frame      = script.Parent
local imagelabel = frame.ImageLabel
local imagebutton = imagelabel.ImageButton

local CLICK_SOUND_ID = "rbxassetid://15675059323"

-- 🔹 재입장(Resume)인 경우 프레임 안 보이게
local function applyResumeVisibility()
	local isResume = player:GetAttribute("IsResumeJoin")
	if isResume == true then
		frame.Visible = false
	end
end

-- 처음 로드 시 한 번 체크
applyResumeVisibility()

-- 혹시 Attribute가 나중에 세팅될 수도 있으니, 변화도 감시
player:GetAttributeChangedSignal("IsResumeJoin"):Connect(applyResumeVisibility)

-- 기존 클릭 처리
imagebutton.MouseButton1Click:Connect(function()
	-- 🔊 클릭 사운드 재생
	local s = Instance.new("Sound")
	s.SoundId = CLICK_SOUND_ID
	s.Volume = 1
	s.Parent = SoundService
	s:Play()

	s.Ended:Connect(function()
		s:Destroy()
	end)

	-- UI 숨기기
	frame.Visible = false
end)
