-- ServerScriptService/Modules/PlayerPassThrough.lua
--!strict
-- 플레이어들끼리 서로 충돌하지 않게(통과) 설정하는 모듈

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local GROUP_PLAYERS = "PlayersNoCollide"

local M = {}

local function ensureGroup()
	-- 그룹 생성(없으면)
	local ok = pcall(function()
		PhysicsService:CreateCollisionGroup(GROUP_PLAYERS)
	end)
	-- 이미 있으면 에러 나는데 무시해도 됨
end

local function setGroupNoCollideWithSelf()
	-- PlayersNoCollide 그룹끼리 충돌 X
	PhysicsService:CollisionGroupSetCollidable(GROUP_PLAYERS, GROUP_PLAYERS, false)
end

local function applyToDescendants(model: Instance)
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			-- 네트워크 전체에 통일되게 서버에서 세팅
			pcall(function()
				PhysicsService:SetPartCollisionGroup(inst, GROUP_PLAYERS)
			end)
		end
	end
end

local function hookCharacter(plr: Player)
	local function onChar(char: Model)
		-- 캐릭터 파트가 생성되기 전에 일부가 없을 수 있어서 한 번 딜레이 후 적용
		task.defer(function()
			if not char or not char.Parent then return end
			applyToDescendants(char)

			-- 악세서리/툴이 나중에 붙는 경우도 있어서 ChildAdded도 훅
			char.DescendantAdded:Connect(function(inst)
				if inst:IsA("BasePart") then
					pcall(function()
						PhysicsService:SetPartCollisionGroup(inst, GROUP_PLAYERS)
					end)
				end
			end)
		end)
	end

	if plr.Character then onChar(plr.Character) end
	plr.CharacterAdded:Connect(onChar)
end

function M.Enable()
	ensureGroup()
	setGroupNoCollideWithSelf()

	-- 현재/신규 플레이어 모두 적용
	for _, plr in ipairs(Players:GetPlayers()) do
		hookCharacter(plr)
	end
	Players.PlayerAdded:Connect(hookCharacter)
end

return M
