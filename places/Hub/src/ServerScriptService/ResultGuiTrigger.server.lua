-- ServerScriptService/ResultGuiTrigger.server.lua
--!strict
-- 허브에 들어온 플레이어 중에서
--  - TeleportData.reason == "final_zone"
--  - 또는 fromPlaceId == TARGET_STAGE_PLACE_ID
-- 인 경우에만 결과창 열기 신호(Remotes.RE_Result_Open)를 보낸다.
-- TeleportData 자체가 없는 경우에는, 디버그 옵션에 따라 항상 열어줄 수도 있음.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RS = ReplicatedStorage

-- ===== 설정 =====
local TARGET_STAGE_PLACE_ID = 92161002947426  -- 최종 결과를 모은 "스테이지 PlaceId"
local DEBUG_ALWAYS_OPEN_ON_JOIN = false       -- TeleportData 없어도 무조건 결과창 열고 싶으면 true

-- ===== Remotes 준비 =====
local Remotes = RS:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = RS
end

local RE_Result_Open = Remotes:FindFirstChild("RE_Result_Open")
if not RE_Result_Open then
	RE_Result_Open = Instance.new("RemoteEvent")
	RE_Result_Open.Name = "RE_Result_Open"
	RE_Result_Open.Parent = Remotes
end

-- RE_Result_CloseAll 은 StageResultBoardService 에서 이미 만들었다고 가정

-- ===== 유틸: 이 플레이어에게 결과창을 열어야 하는지 판단 =====
local function shouldOpenResultFor(player: Player): boolean
	-- JoinData 는 서버에서도 Player:GetJoinData() 로 볼 수 있다
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(joinData) ~= "table" then
		print(("[ResultGuiTrigger] %s: no JoinData (ok=%s)"):format(player.Name, tostring(ok)))
		return DEBUG_ALWAYS_OPEN_ON_JOIN
	end

	local td = joinData.TeleportData
	if typeof(td) ~= "table" then
		print(("[ResultGuiTrigger] %s: no TeleportData"):format(player.Name))
		return DEBUG_ALWAYS_OPEN_ON_JOIN
	end

	local reason      = td.reason or td.from
	local fromPlaceId = td.fromPlaceId
	local lastPlaceId = td.lastPlaceId

	print(("[ResultGuiTrigger] %s TeleportData reason=%s, fromPlaceId=%s, lastPlaceId=%s")
		:format(player.Name, tostring(reason), tostring(fromPlaceId), tostring(lastPlaceId)))

	-- 1) final_zone reason 으로 온 경우
	if reason == "final_zone" then
		print(("[ResultGuiTrigger] %s: reason=final_zone → 결과창 열기 대상"):format(player.Name))
		return true
	end

	-- 2) 예전 방식: 특정 스테이지 PlaceId 에서 바로 허브로 온 경우
	if typeof(fromPlaceId) == "number" and fromPlaceId == TARGET_STAGE_PLACE_ID then
		print(("[ResultGuiTrigger] %s: fromPlaceId=TARGET_STAGE_PLACE_ID → 결과창 열기 대상"):format(player.Name))
		return true
	end

	print(("[ResultGuiTrigger] %s: 결과창 조건에 해당하지 않음"):format(player.Name))
	return false
end

-- ===== PlayerAdded → 조건 맞으면 RE_Result_Open 쏘기 =====
local function onPlayerAdded(player: Player)
	-- JoinData 가 준비될 시간을 조금 준다
	task.delay(1.0, function()
		if not player.Parent then return end

		if shouldOpenResultFor(player) then
			print(("[ResultGuiTrigger] %s: RE_Result_Open.FireClient"):format(player.Name))
			RE_Result_Open:FireClient(player)
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- 이미 접속해 있는 플레이어(Studio 테스트용)
for _, plr in ipairs(Players:GetPlayers()) do
	onPlayerAdded(plr)
end

print("[ResultGuiTrigger] READY (Player.JoinData 검사 → RE_Result_Open.FireClient)")
