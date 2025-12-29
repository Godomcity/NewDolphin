-- ServerScriptService/QuizService.lua
-- 원본 퀴즈를 로드하고, 코호트 시드 기반으로 "10문제만" 선정

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")

local M = {}
local cache = {}   -- [stage] = { title=..., questions={...} }

-- ============== 원본 로드 ==============
local function findModuleForStage(stage: number)
	local folder = ReplicatedStorage:FindFirstChild("QuizData")
	if not folder then return nil end
	local name1 = string.format("Stage%d", stage)
	local name2 = string.format("S%d", stage)
	local mod = folder:FindFirstChild(name1) or folder:FindFirstChild(name2)
	return (mod and mod:IsA("ModuleScript")) and mod or nil
end

local function normalize(raw, stage: number)
	if typeof(raw) == "string" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
		raw = ok and decoded or nil
	end
	if typeof(raw) ~= "table" then
		return { title = string.format("Stage %d", stage), questions = {} }
	end
	local title = raw.title or string.format("Stage %d", stage)
	local questions = raw.questions or raw.Questions or raw.items or {}
	for i, q in ipairs(questions) do
		if typeof(q) == "table" and q.id == nil then
			q.id = string.format("S%dQ%d", stage, i)
		end
	end
	return { title = title, questions = questions }
end

function M.Preload(stage: number)
	stage = tonumber(stage) or 1
	if cache[stage] then return cache[stage] end
	local mod = findModuleForStage(stage)
	if not mod then
		cache[stage] = { title = string.format("Stage %d", stage), questions = {} }
		return cache[stage]
	end
	local ok, raw = pcall(require, mod)
	cache[stage] = ok and normalize(raw, stage) or { title = string.format("Stage %d", stage), questions = {} }
	return cache[stage]
end

-- ============== 10문제 선정 ==============
local function cloneShallow(t)
	local r = {}
	for k,v in ipairs(t) do r[k] = v end
	return r
end

local function fallbackFill(stage: number, want: number, rng: Random)
	local out = {}
	-- 간단 산수/참거짓 혼합
	for i = 1, want do
		local a = rng:NextInteger(2, 9)
		local b = rng:NextInteger(2, 9)
		local sum = a + b
		if i % 3 == 0 then
			-- OX
			local truth = rng:NextInteger(0,1) == 1
			local wrong = sum + rng:NextInteger(1, 3)
			out[#out+1] = {
				id   = string.format("S%dF_OX_%d", stage, i),
				type = "ox",
				text = truth and string.format("%d + %d = %d", a, b, sum)
					or string.format("%d + %d = %d", a, b, wrong),
				answer = truth and "O" or "X",
			}
		else
			-- 객관식
			local correctIndex = rng:NextInteger(1, 4)
			local choices = {}
			for c = 1, 4 do
				choices[c] = (c == correctIndex) and sum or (sum + rng:NextInteger(1, 5))
			end
			out[#out+1] = {
				id      = string.format("S%dF_MC_%d", stage, i),
				type    = "mc",
				text    = string.format("%d + %d = ?", a, b),
				choices = choices,
				answer  = correctIndex,
			}
		end
	end
	return out
end

-- opts.seed 가 동일하면 모든 참여자가 같은 10문제/같은 순서
function M.SelectTen(stage: number, opts: {seed: number}? )
	local data = M.Preload(stage)
	local src  = data.questions or {}
	local TOTAL = 10

	local seed = (opts and tonumber(opts.seed)) or (os.time() % 10^6)
	local rng  = Random.new(seed)

	-- 원본 복사 후 섞기 (Fisher–Yates)
	local arr = cloneShallow(src)
	for i = #arr, 2, -1 do
		local j = rng:NextInteger(1, i)
		arr[i], arr[j] = arr[j], arr[i]
	end

	local out = {}
	for i = 1, math.min(TOTAL, #arr) do
		out[i] = arr[i]
		-- id 없으면 보강
		if out[i].id == nil then
			out[i].id = string.format("S%dQ%d", stage, i)
		end
	end

	-- 부족하면 더미로 채우기
	if #out < TOTAL then
		local fill = fallbackFill(stage, TOTAL - #out, rng)
		for _, q in ipairs(fill) do table.insert(out, q) end
	end

	return out  -- 길이 10 보장
end

function M.Reload(stage: number?)
	if stage ~= nil then cache[tonumber(stage) or 1] = nil else table.clear(cache) end
end

return M
