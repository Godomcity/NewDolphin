local frame = script.Parent
local imagelabel = frame.ImageLabel
local imagebutton = imagelabel.ImageButton

imagebutton.MouseButton1Click:Connect(function()
	
	frame.Visible = false
	
end)