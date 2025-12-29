-- ReplicatedStorage/Modules/Net.lua
--!strict

local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local function ensureRF(name: string): RemoteFunction
	local rf = Remotes:FindFirstChild(name)
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = Remotes
	end
	return rf :: RemoteFunction
end

local function ensureRE(name: string): RemoteEvent
	local re = Remotes:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = Remotes
	end
	return re :: RemoteEvent
end

return {
	Remotes = Remotes,
	ensureRF = ensureRF,
	ensureRE = ensureRE,
}
