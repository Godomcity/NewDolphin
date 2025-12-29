-- LocalScript
-- script.Parent = (TextLabel들이 들어있는) Frame

local frame = script.Parent

-- 프로젝트 공용 디바이스 판별(권장)
local RS = game:GetService("ReplicatedStorage")
local Device = require(RS:WaitForChild("Modules"):WaitForChild("DeviceProfile"))

local questionscoretextSize = script.Parent.Parent:WaitForChild("QuestionScore"):WaitForChild("UITextSizeConstraint")

local maxSize = Device.isMobile() and 14 or 35

-- frame 아래(자식/후손) TextLabel들의 UITextSizeConstraint를 찾아서 일괄 적용
for _, inst in ipairs(frame:GetDescendants()) do
	if inst:IsA("UITextSizeConstraint") then
		inst.MaxTextSize = maxSize
	end
end
questionscoretextSize.MaxTextSize = maxSize