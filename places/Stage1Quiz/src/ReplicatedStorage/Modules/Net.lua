-- ReplicatedStorage/Modules/Net.lua
local RS = game:GetService("ReplicatedStorage")

local Remotes = RS:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"; Remotes.Parent = RS

local function ensureRF(name: string)
	local rf = Remotes:FindFirstChild(name)
	if not rf then rf = Instance.new("RemoteFunction"); rf.Name = name; rf.Parent = Remotes end
	return rf
end

local function ensureRE(name: string)
	local ev = Remotes:FindFirstChild(name)
	if not ev then ev = Instance.new("RemoteEvent"); ev.Name = name; ev.Parent = Remotes end
	return ev
end

return { Remotes = Remotes, ensureRF = ensureRF, ensureRE = ensureRE }
