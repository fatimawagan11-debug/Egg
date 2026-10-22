--[[
    Constipated Hub | Steal An Egg
    UI: Venyx UI Library (black)
    Humanized movement · Steal Panel · Multi-tier priority · Safety webhooks
    Remotes: ActiveAssets / Eggs / Treadmills (open-source DKHUB-class)
]]

local ENV = (typeof(getgenv) == "function" and getgenv()) or _G
if ENV.ConstipatedSAEUnload then pcall(ENV.ConstipatedSAEUnload) end

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")

local LP = Players.LocalPlayer
while not LP do task.wait() LP = Players.LocalPlayer end
local Camera = Workspace.CurrentCamera

-- ===================== FLAGS =====================
local F = {
	-- Steal
	autoSteal = false,
	goToEgg = "Tween",
	delivery = "Tween",
	tweenSpeed = 90,
	stealDelay = 0.4,
	humanize = true,
	humanizeJitter = 0.15,
	instantSteal = false,
	stealFromOthers = true,
	antiGuard = true,
	dropSafeZone = true,
	stealFirst = "Rarest first",
	minRarity = "All",
	minIncomeOn = false,
	minIncome = 0,
	wantedMutation = "None",
	priority1 = "None",
	priority2 = "None",
	priority3 = "None",
	priority4 = "None",
	stealPanel = true,
	stealPanelMax = 12,
	stealPanelDist = 400,

	-- Farm
	autoCollect = true,
	autoHatch = false,
	autoPlace = false,
	fastHatch = true,
	autoFuse = false,
	autoTreadmill = false,
	autoUpgradeTreadmill = false,
	autoUpgradeBase = false,
	autoEquipBest = false,
	autoSell = false,
	protectMutated = true,
	keepBestEach = true,
	treadmillMult = 1,
	upgradeDelay = 1.5,
	autoQuest = false,
	autoBoss = false,

	-- Player (stealth apply)
	speedOn = false,
	walkSpeed = 24,
	jumpOn = false,
	jumpPower = 60,
	infJump = false,
	antiAfk = true,
	noclip = false,
	fly = false,
	flySpeed = 50,
	antiTrap = true,
	antiRagdoll = true,
	trapCrush = true,
	hazardImmune = true,
	fpsCapOn = false,
	fpsCap = 60,

	-- ESP sections
	espEggs = true,
	espGuards = true,
	espPlayers = false,
	espCarriers = true,
	espPlots = false,
	espZones = false,
	espOwnBlue = true,
	espShowDist = true,
	espMaxDist = 800,
	espMinRarity = "All",

	-- Safety
	staffAutoLeave = false,
	guardAlert = true,
	watchlist = "", -- comma names
	webhookUrl = "",
	panicWebhook = true,
}

local S = {
	unloaded = false,
	conns = {},
	stealThread = nil,
	eggHL = {},
	guardHL = {},
	playerHL = {},
	plotHL = {},
	panelGui = nil,
	panelButtons = {},
	noclipConn = nil,
	flyBV = nil,
	lastStaffCheck = 0,
	lastUpgrade = 0,
	savedCF = nil,
}

local function track(c)
	if c then table.insert(S.conns, c) end
	return c
end

local function root()
	local c = LP.Character
	return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
end

local function hum()
	local c = LP.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function notify(title, text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = title, Text = text, Duration = 4 })
	end)
end

local function jitter()
	if not F.humanize then return 0 end
	return (math.random() * 2 - 1) * (F.humanizeJitter or 0.15)
end

local function humanWait(base)
	task.wait(math.max(0.05, (base or 0.3) + jitter()))
end

-- Discord webhook
local function sendWebhook(title, content)
	if not F.panicWebhook or not F.webhookUrl or F.webhookUrl == "" then return end
	pcall(function()
		local body = HttpService:JSONEncode({
			embeds = {{
				title = title,
				description = content,
				color = 16711680,
				footer = { text = "Constipated Hub · Panic" },
			}},
		})
		if request then
			request({ Url = F.webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
		elseif syn and syn.request then
			syn.request({ Url = F.webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
		elseif http_request then
			http_request({ Url = F.webhookUrl, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
		end
	end)
end

-- ===================== NETWORK =====================
local function getNetwork()
	return ReplicatedStorage:FindFirstChild("Network") or ReplicatedStorage
end

local function getRemote(name)
	local net = getNetwork()
	return net:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name, true)
end

local function fireRemote(name, ...)
	local r = getRemote(name)
	if r and r:IsA("RemoteEvent") then
		pcall(function(...) r:FireServer(...) end, ...)
		return true
	end
	return false
end

local function invokeRemote(name, ...)
	local rf = getRemote(name)
	if rf and rf:IsA("RemoteFunction") then
		local res
		local ok = pcall(function(...) res = rf:InvokeServer(...) end, ...)
		if ok then return res end
	end
	return nil
end

local function triggerPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then return false end
	pcall(function()
		if typeof(fireproximityprompt) == "function" then
			fireproximityprompt(prompt, 0)
		else
			prompt:InputHoldBegin()
			task.wait(prompt.HoldDuration or 0.08)
			prompt:InputHoldEnd()
		end
	end)
	return true
end

-- Humanized move: small path steps, no hard snap reset
local function teleportTo(cf, useTween, speed)
	local r = root()
	if not r then return end
	S.savedCF = cf
	if useTween then
		local dist = (r.Position - cf.Position).Magnitude
		local spd = math.max((speed or 90) * (F.humanize and (0.85 + math.random() * 0.3) or 1), 10)
		local t = math.clamp(dist / spd, 0.08, 3.5)
		-- slight curve offset for humanize
		if F.humanize and dist > 20 then
			local mid = r.Position:Lerp(cf.Position, 0.5) + Vector3.new(math.random(-4, 4), 1, math.random(-4, 4))
			local tw1 = TweenService:Create(r, TweenInfo.new(t * 0.5, Enum.EasingStyle.Sine), { CFrame = CFrame.new(mid) })
			tw1:Play()
			tw1.Completed:Wait()
			local tw2 = TweenService:Create(r, TweenInfo.new(t * 0.5, Enum.EasingStyle.Sine), { CFrame = cf })
			tw2:Play()
			tw2.Completed:Wait()
		else
			local tw = TweenService:Create(r, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = cf })
			tw:Play()
			tw.Completed:Wait()
		end
	else
		r.CFrame = cf
	end
end

-- ===================== SCAN =====================
local RARITY_RANK = {
	All = 0, Basic = 1, Common = 1, Uncommon = 2, Rare = 3, Superior = 3,
	Epic = 4, Legendary = 5, Mythic = 6, Cosmic = 7, Eternal = 8,
	Divine = 9, Secret = 10, BrainrotGod = 11,
}

local RARITY_COLOR = {
	BrainrotGod = Color3.fromRGB(255, 0, 128),
	Secret = Color3.fromRGB(0, 255, 255),
	Divine = Color3.fromRGB(255, 215, 0),
	Cosmic = Color3.fromRGB(168, 85, 247),
	Eternal = Color3.fromRGB(255, 75, 75),
	Mythic = Color3.fromRGB(244, 63, 94),
	Legendary = Color3.fromRGB(245, 158, 11),
	Epic = Color3.fromRGB(139, 92, 246),
	Rare = Color3.fromRGB(59, 130, 246),
	Common = Color3.fromRGB(200, 200, 200),
}

local function eggRarity(obj)
	local r = obj:GetAttribute("Rarity") or obj:GetAttribute("Tier") or obj:GetAttribute("EggRarity")
	return typeof(r) == "string" and r or "Common"
end

local function eggIncome(obj)
	local v = obj:GetAttribute("Income") or obj:GetAttribute("Value") or obj:GetAttribute("Price") or obj:GetAttribute("Cash") or obj:GetAttribute("IncomePerSec")
	if typeof(v) == "number" then return v end
	local n = obj:FindFirstChild("Income") or obj:FindFirstChild("Value")
	if n and n:IsA("ValueBase") then return n.Value end
	return 0
end

local function eggMutation(obj)
	local m = obj:GetAttribute("Mutation") or obj:GetAttribute("Mutations") or obj:GetAttribute("Variant")
	return typeof(m) == "string" and m or "None"
end

local function zoneName(obj)
	local z = obj:GetAttribute("Zone") or obj:GetAttribute("Area") or obj:GetAttribute("PlotZone")
	if typeof(z) == "string" then return z end
	local p = obj.Parent
	local depth = 0
	while p and p ~= Workspace and depth < 6 do
		local n = string.lower(p.Name)
		if n:find("zone") or n:find("area") or n:find("forest") or n:find("desert") or n:find("volcano") or n:find("ocean") then
			return p.Name
		end
		p = p.Parent
		depth += 1
	end
	return "Unknown"
end

local function isOwn(obj)
	local path = obj:GetFullName()
	if string.find(path, LP.Name) then return true end
	if obj:GetAttribute("Owner") == LP.Name or obj:GetAttribute("OwnerId") == LP.UserId then return true end
	local p = obj.Parent
	local depth = 0
	while p and p ~= Workspace and depth < 8 do
		if p:GetAttribute("Owner") == LP.Name or p:GetAttribute("OwnerId") == LP.UserId then return true end
		if string.find(tostring(p.Name), LP.Name) then return true end
		p = p.Parent
		depth += 1
	end
	return false
end

local function priorityScore(zone)
	if F.priority1 ~= "None" and zone == F.priority1 then return 400 end
	if F.priority2 ~= "None" and zone == F.priority2 then return 300 end
	if F.priority3 ~= "None" and zone == F.priority3 then return 200 end
	if F.priority4 ~= "None" and zone == F.priority4 then return 100 end
	return 0
end

local function scanEggs()
	local list, seen = {}, {}
	local folders = {
		Workspace:FindFirstChild("Eggs"),
		Workspace:FindFirstChild("AreaEggs"),
		Workspace:FindFirstChild("Plots"),
		Workspace:FindFirstChild("Bases"),
		Workspace,
	}
	local myRoot = root()
	for _, folder in ipairs(folders) do
		if not folder then continue end
		for _, obj in ipairs(folder:GetDescendants()) do
			if seen[obj] then continue end
			local model, part, prompt
			if obj:IsA("ProximityPrompt") then
				local at = string.lower(obj.ActionText or "")
				local ot = string.lower(obj.ObjectText or "")
				if at:find("steal") or ot:find("egg") or obj.Name == "CarryAreaEgg" then
					prompt = obj
					model = obj.Parent
					part = model and (model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart", true))
				end
			elseif obj:IsA("Model") then
				local n = string.lower(obj.Name)
				if n:find("egg") or obj:GetAttribute("IsEgg") or obj:GetAttribute("EggId") or obj:GetAttribute("Uid") then
					model = obj
					part = obj:FindFirstChildWhichIsA("BasePart", true)
					prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
				end
			end
			if model and part and not seen[model] then
				seen[model] = true
				if myRoot and F.espMaxDist > 0 and (part.Position - myRoot.Position).Magnitude > F.espMaxDist then
					continue
				end
				local own = isOwn(model)
				if not F.stealFromOthers and not own then continue end
				local rarity = eggRarity(model)
				if F.minRarity ~= "All" and (RARITY_RANK[rarity] or 0) < (RARITY_RANK[F.minRarity] or 0) then continue end
				local income = eggIncome(model)
				if F.minIncomeOn and income < F.minIncome then continue end
				local mut = eggMutation(model)
				if F.wantedMutation ~= "None" and mut ~= F.wantedMutation and not string.find(string.lower(mut), string.lower(F.wantedMutation)) then
					continue
				end
				local zone = zoneName(model)
				table.insert(list, {
					Model = model,
					Part = part,
					Prompt = prompt,
					Rarity = rarity,
					Income = income,
					Mutation = mut,
					Zone = zone,
					Own = own,
					IsArea = model:GetAttribute("IsAreaEgg") or string.find(string.lower(model.Name), "area") ~= nil,
					Name = model.Name,
					Prio = priorityScore(zone),
				})
			end
		end
	end

	local r = myRoot
	-- Rarest / best with area priority
	table.sort(list, function(a, b)
		if a.Prio ~= b.Prio then return a.Prio > b.Prio end
		if F.stealFirst == "Closest" and r then
			return (a.Part.Position - r.Position).Magnitude < (b.Part.Position - r.Position).Magnitude
		end
		if F.stealFirst == "Highest income" then
			if a.Income ~= b.Income then return a.Income > b.Income end
		end
		-- Rarest first (default)
		local ra, rb = RARITY_RANK[a.Rarity] or 0, RARITY_RANK[b.Rarity] or 0
		if ra ~= rb then return ra > rb end
		return a.Income > b.Income
	end)

	if F.stealFromOthers then
		table.sort(list, function(a, b)
			if a.Own ~= b.Own then return not a.Own end
			return false
		end)
	end
	return list
end

local function depositCF()
	for _, folderName in ipairs({ "Plots", "Bases", "Islands" }) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if string.find(m.Name, LP.Name)
					or m:GetAttribute("Owner") == LP.Name
					or m:GetAttribute("OwnerId") == LP.UserId then
					local p = m:FindFirstChildWhichIsA("BasePart", true)
					if p then return p.CFrame + Vector3.new(0, 3, 0) end
				end
			end
		end
	end
	local r = root()
	return r and r.CFrame
end

local function antiGuardTick()
	if not F.antiGuard then return end
	local r = root()
	if not r then return end
	pcall(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and string.find(string.lower(d.Name), "guard") then
				local p = d:FindFirstChild("HumanoidRootPart") or d:FindFirstChildWhichIsA("BasePart")
				if p and (p.Position - r.Position).Magnitude < 18 then
					r.CFrame = r.CFrame + (r.Position - p.Position).Unit * 8
				end
			end
		end
	end)
end

local function doSteal(target)
	if not target or not target.Part then return false end
	local useTween = (F.goToEgg == "Tween" or F.delivery == "Tween") and not F.instantSteal and F.delivery ~= "Instant"
	local model = target.Model

	teleportTo(target.Part.CFrame + Vector3.new(0, 2.5, 0), useTween, F.tweenSpeed)
	antiGuardTick()
	humanWait(0.08)

	invokeRemote("ActiveAssets: RequestStealTarget", model)
	fireRemote("ActiveAssets: StealTargetEvent", model)
	invokeRemote("ActiveAssets: RequestDnaStealAnimationComplete", model)

	if target.IsArea then
		invokeRemote("Eggs: RequestAreaEggCarry", model)
		humanWait(0.05)
		invokeRemote("Eggs: RequestAreaEggDrop")
		fireRemote("Guards: ForestDeposit")
	end

	if target.Prompt then
		triggerPrompt(target.Prompt)
	else
		local pr = model:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pr then triggerPrompt(pr) end
	end

	for _, name in ipairs({ "Steal", "StealEgg", "TakeEgg", "CollectEgg", "GrabEgg", "PickupEgg" }) do
		local rem = ReplicatedStorage:FindFirstChild(name, true)
		if rem then
			if rem:IsA("RemoteEvent") then pcall(function() rem:FireServer(model) end) end
			if rem:IsA("RemoteFunction") then pcall(function() rem:InvokeServer(model) end) end
		end
	end

	if F.dropSafeZone then
		local dep = depositCF()
		if dep then
			teleportTo(dep, useTween, F.tweenSpeed)
			humanWait(0.08)
			invokeRemote("Eggs: RequestAreaEggDrop")
			fireRemote("Guards: ForestDeposit")
		end
	end
	return true
end

local function stopSteal()
	F.autoSteal = false
	if S.stealThread then
		pcall(function() task.cancel(S.stealThread) end)
		S.stealThread = nil
	end
end

local function startSteal()
	if S.stealThread then pcall(function() task.cancel(S.stealThread) end) end
	S.stealThread = task.spawn(function()
		while F.autoSteal and not S.unloaded do
			local eggs = scanEggs()
			local target
			for _, e in ipairs(eggs) do
				if F.stealFromOthers and not e.Own then
					target = e
					break
				end
			end
			if not target and #eggs > 0 then target = eggs[1] end
			if target then
				doSteal(target)
				humanWait(F.stealDelay)
			else
				humanWait(0.7)
			end
		end
	end)
end

-- ===================== STEAL PANEL =====================
local function ensurePanelGui()
	if S.panelGui and S.panelGui.Parent then return S.panelGui end
	local g = Instance.new("ScreenGui")
	g.Name = "ConstipatedStealPanel"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 50
	pcall(function() g.Parent = (gethui and gethui()) or CoreGui end)
	if not g.Parent then g.Parent = LP:WaitForChild("PlayerGui") end
	S.panelGui = g
	return g
end

local function clearPanelButtons()
	for _, b in pairs(S.panelButtons) do pcall(function() b:Destroy() end) end
	S.panelButtons = {}
end

local function updateStealPanel()
	if S.unloaded or not F.stealPanel then
		clearPanelButtons()
		return
	end
	local gui = ensurePanelGui()
	local eggs = scanEggs()
	local myRoot = root()
	local used = {}
	local count = 0

	for _, e in ipairs(eggs) do
		if count >= F.stealPanelMax then break end
		if e.Own and F.stealFromOthers then continue end
		if myRoot and (e.Part.Position - myRoot.Position).Magnitude > F.stealPanelDist then continue end
		local sp, onScreen = Camera:WorldToViewportPoint(e.Part.Position + Vector3.new(0, 2.2, 0))
		if not onScreen or sp.Z < 0 then continue end
		count += 1
		local key = tostring(e.Model)
		used[key] = true
		local btn = S.panelButtons[key]
		if not btn or not btn.Parent then
			btn = Instance.new("TextButton")
			btn.Size = UDim2.new(0, 56, 0, 56)
			btn.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
			btn.BackgroundTransparency = 0.12
			btn.Text = ""
			btn.ZIndex = 60
			btn.Parent = gui
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2
			stroke.Parent = btn
			local icon = Instance.new("TextLabel")
			icon.Size = UDim2.new(1, 0, 0.5, 0)
			icon.BackgroundTransparency = 1
			icon.Text = "🥚"
			icon.TextSize = 20
			icon.ZIndex = 61
			icon.Parent = btn
			local lab = Instance.new("TextLabel")
			lab.Name = "Lab"
			lab.Size = UDim2.new(1, -4, 0.45, 0)
			lab.Position = UDim2.new(0, 2, 0.5, 0)
			lab.BackgroundTransparency = 1
			lab.TextColor3 = Color3.fromRGB(240, 240, 245)
			lab.TextSize = 8
			lab.Font = Enum.Font.GothamBold
			lab.TextTruncate = Enum.TextTruncate.AtEnd
			lab.ZIndex = 61
			lab.Parent = btn
			btn.MouseButton1Click:Connect(function()
				task.spawn(function()
					doSteal(e)
					notify("Steal Panel", e.Rarity .. " · " .. e.Zone)
				end)
			end)
			S.panelButtons[key] = btn
		end
		btn.Position = UDim2.new(0, sp.X - 28, 0, sp.Y - 28)
		btn.Visible = true
		local lab = btn:FindFirstChild("Lab")
		local dist = myRoot and math.floor((e.Part.Position - myRoot.Position).Magnitude) or 0
		if lab then
			lab.Text = F.espShowDist and (e.Rarity .. "\n" .. dist .. "m") or e.Rarity
		end
		local stroke = btn:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = RARITY_COLOR[e.Rarity] or Color3.fromRGB(255, 200, 50) end
	end
	for key, btn in pairs(S.panelButtons) do
		if not used[key] then
			pcall(function() btn:Destroy() end)
			S.panelButtons[key] = nil
		end
	end
end

track(RunService.RenderStepped:Connect(function()
	if not S.unloaded then updateStealPanel() end
end))

-- ===================== FARM =====================
local function stepHatch()
	invokeRemote("Eggs: RequestHatchEgg")
	invokeRemote("Eggs: RequestCompleteHatchEgg")
	fireRemote("Eggs: Hatch")
	if F.autoPlace or F.fastHatch then
		invokeRemote("Eggs: RequestPlaceEgg")
		fireRemote("Eggs: PlaceEgg")
	end
end

local function stepFuse()
	invokeRemote("Pets: RequestFuse")
	fireRemote("Pets: Fuse")
	invokeRemote("Eggs: RequestFuse")
end

local function stepTreadmill()
	fireRemote("Treadmills: SpeedGain", F.treadmillMult or 1)
	if F.autoUpgradeTreadmill and tick() - S.lastUpgrade > F.upgradeDelay then
		S.lastUpgrade = tick()
		invokeRemote("Treadmills: RequestUpgrade")
	end
	invokeRemote("Treadmills: RequestEquipStatic")
end

local function stepCollect()
	fireRemote("ActiveAssets: MoneyCollected")
	invokeRemote("OfflineAssets: Redeem")
	pcall(function()
		for _, folderName in ipairs({ "Plots", "Bases" }) do
			local folder = Workspace:FindFirstChild(folderName)
			if not folder then continue end
			for _, m in ipairs(folder:GetChildren()) do
				if isOwn(m) then
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("ProximityPrompt") then
							local at = string.lower(d.ActionText or "")
							if at:find("collect") or at:find("claim") then triggerPrompt(d) end
						end
					end
				end
			end
		end
	end)
end

local function stepUpgradeBase()
	if tick() - S.lastUpgrade < F.upgradeDelay then return end
	S.lastUpgrade = tick()
	fireRemote("Plots: RequestBaseUpgrade", "All")
	invokeRemote("Plots: RequestBaseUpgrade", "All")
	invokeRemote("Plots: RequestTableUpgrade")
	fireRemote("Plots: RequestPenUpgrade")
end

local function stepEquipBest()
	invokeRemote("Backpack: EquipBest")
	fireRemote("Pets: EquipBest")
	invokeRemote("Pets: RequestEquipBest")
end

local function stepSell()
	-- Keep best / mutation protection: avoid SellAll when protect on
	if F.protectMutated or F.keepBestEach then
		fireRemote("Pets: SellJunk")
		invokeRemote("Pets: RequestSellJunk")
		fireRemote("Pets: Sell")
		invokeRemote("Pets: RequestSell")
	else
		fireRemote("Pets: SellAll")
		invokeRemote("Pets: RequestSellAll")
	end
	fireRemote("Eggs: Sell")
	invokeRemote("Eggs: RequestSell")
end

local function stepQuest()
	invokeRemote("Quests: ClaimAll")
	fireRemote("Quests: Claim")
	invokeRemote("Events: Claim")
	fireRemote("Events: ClaimReward")
	invokeRemote("GuardTutorial: RequestSyncProgress", 99)
	for _, name in ipairs({
		"Events: DrScramble", "Events: RequestScramble", "Scramble: Start",
		"Scramble: Claim", "Quests: DrScramble",
	}) do
		fireRemote(name)
		invokeRemote(name)
	end
end

local function stepBoss()
	for _, name in ipairs({
		"Boss: RequestJoin", "Boss: Attack", "Boss: Start",
		"Abyss: Start", "Abyss: Attack", "Events: AbyssBoss",
		"Boss: Claim", "Abyss: Claim",
	}) do
		fireRemote(name)
		invokeRemote(name)
	end
end

local function crushTraps()
	if not F.trapCrush then return end
	local r = root()
	if not r then return end
	pcall(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			local n = string.lower(d.Name)
			if (n:find("trap") or n:find("snare") or n:find("cage") or n:find("spike")) then
				if d:IsA("BasePart") and (d.Position - r.Position).Magnitude < 30 then
					pcall(function() d:Destroy() end)
					pcall(function() d.CanCollide = false end)
					pcall(function() d.Transparency = 1 end)
				elseif d:IsA("Model") then
					local p = d:FindFirstChildWhichIsA("BasePart", true)
					if p and (p.Position - r.Position).Magnitude < 30 then
						pcall(function() d:Destroy() end)
					end
				end
			end
		end
	end)
end

local function unstuck()
	local r = root()
	local h = hum()
	if r then
		r.Anchored = false
		r.AssemblyLinearVelocity = Vector3.zero
		r.CFrame = r.CFrame + Vector3.new(0, 15, 0)
	end
	if h then
		h.PlatformStand = false
		h:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
	notify("Unstuck", "Boosted up")
end

task.spawn(function()
	while not S.unloaded do
		if F.autoCollect then pcall(stepCollect) end
		if F.autoHatch then pcall(stepHatch) end
		if F.autoFuse then pcall(stepFuse) end
		if F.autoTreadmill then pcall(stepTreadmill) end
		if F.autoUpgradeBase then pcall(stepUpgradeBase) end
		if F.autoEquipBest then pcall(stepEquipBest) end
		if F.autoSell then pcall(stepSell) end
		if F.autoQuest then pcall(stepQuest) end
		if F.autoBoss then pcall(stepBoss) end
		if F.trapCrush then pcall(crushTraps) end
		task.wait(0.4 + jitter())
	end
end)

-- ===================== STEALTH MOVEMENT (no start-reset) =====================
-- Continuously re-apply speed/jump AFTER game scripts; store last good CF
track(RunService.Heartbeat:Connect(function()
	if S.unloaded then return end
	local h = hum()
	local c = LP.Character
	local r = root()

	if r and r.Position.Y > -50 then
		S.savedCF = r.CFrame
	end

	if h then
		if F.speedOn then
			-- re-apply every frame so game can't soft-reset you
			if math.abs(h.WalkSpeed - F.walkSpeed) > 0.5 then
				h.WalkSpeed = F.walkSpeed
			end
		end
		if F.jumpOn then
			h.UseJumpPower = true
			if math.abs(h.JumpPower - F.jumpPower) > 0.5 then
				h.JumpPower = F.jumpPower
			end
		end
		if F.antiRagdoll then
			pcall(function()
				h.PlatformStand = false
				if c then
					local rag = c:FindFirstChild("Ragdoll")
					if rag then rag:Destroy() end
					for _, v in ipairs(c:GetDescendants()) do
						if v:IsA("BallSocketConstraint") then pcall(function() v:Destroy() end) end
					end
				end
			end)
		end
	end

	-- If teleported to void/spawn unexpectedly while speed/fly on, restore
	if (F.speedOn or F.fly) and r and S.savedCF then
		if r.Position.Y < -100 then
			r.CFrame = S.savedCF + Vector3.new(0, 5, 0)
		end
	end

	if F.antiTrap and r then
		pcall(function()
			if r.Anchored then r.Anchored = false end
			for _, d in ipairs(Workspace:GetDescendants()) do
				local n = string.lower(d.Name)
				if (n:find("trap") or n:find("snare") or n:find("cage")) and d:IsA("BasePart") then
					if (d.Position - r.Position).Magnitude < 8 then
						r.CFrame = r.CFrame + Vector3.new(0, 14, 0)
						break
					end
				end
			end
		end)
	end

	-- Hazard immunity: neutralize nearby kill parts
	if F.hazardImmune and r then
		pcall(function()
			for _, d in ipairs(Workspace:GetDescendants()) do
				local n = string.lower(d.Name)
				if d:IsA("BasePart") and (n:find("kill") or n:find("lava") or n:find("hazard") or n:find("damage") or n:find("abyss")) then
					if (d.Position - r.Position).Magnitude < 40 then
						d.CanTouch = false
						d.CanQuery = false
					end
				end
			end
		end)
	end
end))

track(UserInputService.JumpRequest:Connect(function()
	if S.unloaded or not F.infJump then return end
	local h = hum()
	if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
end))

pcall(function()
	track(LP.Idled:Connect(function()
		if F.antiAfk and not S.unloaded then
			pcall(function()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton2(Vector2.new())
			end)
		end
	end))
end)

local function setNoclip(on)
	if S.noclipConn then
		pcall(function() S.noclipConn:Disconnect() end)
		S.noclipConn = nil
	end
	if not on then return end
	S.noclipConn = track(RunService.Stepped:Connect(function()
		if S.unloaded or not F.noclip then return end
		local c = LP.Character
		if not c then return end
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end))
end

local function setFly(on)
	pcall(function()
		if S.flyBV then S.flyBV:Destroy() S.flyBV = nil end
	end)
	if not on then return end
	local r = root()
	if not r then return end
	local bv = Instance.new("BodyVelocity")
	bv.Name = "CO_Fly"
	bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
	bv.Velocity = Vector3.zero
	bv.Parent = r
	S.flyBV = bv
end

-- Re-parent fly BV if character resets it
track(RunService.RenderStepped:Connect(function()
	if S.unloaded or not F.fly then return end
	local r = root()
	if not r then return end
	if not S.flyBV or not S.flyBV.Parent then
		setFly(true)
	end
	if not S.flyBV then return end
	local cam = Camera.CFrame
	local dir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cam.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cam.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cam.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cam.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.new(0, 1, 0) end
	S.flyBV.Velocity = dir.Magnitude > 0 and dir.Unit * F.flySpeed or Vector3.zero
	S.savedCF = r.CFrame
end))

-- FPS Cap
pcall(function()
	if setfpscap then
		track(RunService.Heartbeat:Connect(function()
			if F.fpsCapOn then setfpscap(F.fpsCap) end
		end))
	end
end)

-- Staff / watchlist panic
local function parseWatchlist()
	local t = {}
	for name in string.gmatch(F.watchlist or "", "[^,]+") do
		name = string.lower((name:gsub("^%s+", ""):gsub("%s+$", "")))
		if name ~= "" then t[name] = true end
	end
	return t
end

local STAFF_KEYS = { "admin", "mod", "moderator", "staff", "dev", "owner", "community manager" }

track(RunService.Heartbeat:Connect(function()
	if S.unloaded then return end
	if tick() - S.lastStaffCheck < 2.5 then return end
	S.lastStaffCheck = tick()
	local watch = parseWatchlist()
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl == LP then continue end
		local n = string.lower(pl.Name)
		local d = string.lower(pl.DisplayName or "")
		local hit = watch[n] or watch[d]
		if not hit and F.staffAutoLeave then
			for _, k in ipairs(STAFF_KEYS) do
				if n:find(k) or d:find(k) then hit = true break end
			end
		end
		if hit then
			local msg = pl.Name .. " joined · panic leave"
			notify("PANIC", msg)
			sendWebhook("Staff / Watchlist", msg .. "\nPlace: " .. tostring(game.PlaceId) .. "\nJob: " .. tostring(game.JobId))
			pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
			return
		end
	end
end))

-- ===================== ESP =====================
local function isCarrier(pl)
	local c = pl.Character
	if not c then return false end
	if c:GetAttribute("Carrying") or c:GetAttribute("HasEgg") then return true end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "egg") then return true end
	end
	return false
end

local function scanPlots()
	local plots = {}
	for _, folderName in ipairs({ "Plots", "Bases", "Islands" }) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			for _, m in ipairs(folder:GetChildren()) do
				if m:IsA("Model") or m:IsA("Folder") then
					table.insert(plots, m)
				end
			end
		end
	end
	return plots
end

track(RunService.RenderStepped:Connect(function()
	if S.unloaded then return end
	local myRoot = root()

	if F.espEggs then
		local seen = {}
		for _, e in ipairs(scanEggs()) do
			if F.espMinRarity ~= "All" and (RARITY_RANK[e.Rarity] or 0) < (RARITY_RANK[F.espMinRarity] or 0) then
				continue
			end
			local m = e.Model
			seen[m] = true
			local hl = S.eggHL[m]
			if not hl or not hl.Parent then
				hl = Instance.new("Highlight")
				hl.FillTransparency = 0.55
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				pcall(function() hl.Parent = (gethui and gethui()) or CoreGui end)
				S.eggHL[m] = hl
			end
			hl.FillColor = (e.Own and F.espOwnBlue) and Color3.fromRGB(80, 180, 255) or (RARITY_COLOR[e.Rarity] or Color3.fromRGB(255, 200, 50))
			hl.Adornee = m:IsA("Model") and m or m
		end
		for m, hl in pairs(S.eggHL) do
			if not seen[m] then pcall(function() hl:Destroy() end) S.eggHL[m] = nil end
		end
	else
		for m, hl in pairs(S.eggHL) do pcall(function() hl:Destroy() end) end
		S.eggHL = {}
	end

	if F.espGuards then
		local seenG = {}
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("Model") and string.find(string.lower(d.Name), "guard") then
				seenG[d] = true
				local hl = S.guardHL[d]
				if not hl or not hl.Parent then
					hl = Instance.new("Highlight")
					hl.FillTransparency = 0.45
					hl.FillColor = Color3.fromRGB(255, 40, 40)
					hl.OutlineTransparency = 0
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.Adornee = d
					pcall(function() hl.Parent = (gethui and gethui()) or CoreGui end)
					S.guardHL[d] = hl
				else
					hl.Adornee = d
				end
			end
		end
		for m, hl in pairs(S.guardHL) do
			if not seenG[m] then pcall(function() hl:Destroy() end) S.guardHL[m] = nil end
		end
	else
		for m, hl in pairs(S.guardHL) do pcall(function() hl:Destroy() end) end
		S.guardHL = {}
	end

	if F.espPlayers or F.espCarriers then
		local seenP = {}
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl == LP or not pl.Character then continue end
			local carrier = isCarrier(pl)
			if F.espCarriers and carrier then
				seenP[pl] = true
			elseif F.espPlayers then
				seenP[pl] = true
			else
				continue
			end
			local hl = S.playerHL[pl]
			if not hl or not hl.Parent then
				hl = Instance.new("Highlight")
				hl.FillTransparency = 0.55
				hl.OutlineTransparency = 0
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				pcall(function() hl.Parent = (gethui and gethui()) or CoreGui end)
				S.playerHL[pl] = hl
			end
			hl.Adornee = pl.Character
			hl.FillColor = carrier and Color3.fromRGB(255, 120, 0) or Color3.fromRGB(100, 200, 255)
		end
		for pl, hl in pairs(S.playerHL) do
			if not seenP[pl] then pcall(function() hl:Destroy() end) S.playerHL[pl] = nil end
		end
	else
		for pl, hl in pairs(S.playerHL) do pcall(function() hl:Destroy() end) end
		S.playerHL = {}
	end

	if F.espPlots or F.espZones then
		local seenPl = {}
		for _, m in ipairs(scanPlots()) do
			seenPl[m] = true
			local hl = S.plotHL[m]
			if not hl or not hl.Parent then
				hl = Instance.new("Highlight")
				hl.FillTransparency = 0.75
				hl.OutlineTransparency = 0.3
				hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				hl.Adornee = m
				pcall(function() hl.Parent = (gethui and gethui()) or CoreGui end)
				S.plotHL[m] = hl
			end
			hl.FillColor = isOwn(m) and Color3.fromRGB(60, 200, 120) or Color3.fromRGB(180, 100, 255)
			hl.Adornee = m
		end
		for m, hl in pairs(S.plotHL) do
			if not seenPl[m] then pcall(function() hl:Destroy() end) S.plotHL[m] = nil end
		end
	else
		for m, hl in pairs(S.plotHL) do pcall(function() hl:Destroy() end) end
		S.plotHL = {}
	end
end))

-- ===================== UI =====================
local Library
do
	local urls = {
		"https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source2.lua",
		"https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/master/source2.lua",
		"https://raw.githubusercontent.com/Stefanuk12/Venyx-UI-Library/main/source.lua",
	}
	for _, u in ipairs(urls) do
		local ok, res = pcall(function() return loadstring(game:HttpGet(u))() end)
		if ok and res then Library = res break end
	end
end
if not Library then warn("[Constipated Hub] Venyx UI failed") return end

local Venyx = Library.new({ title = "Constipated Hub" })
pcall(function()
	Venyx:setTheme({ theme = "Background", color3 = Color3.fromRGB(16, 16, 16) })
	Venyx:setTheme({ theme = "DarkContrast", color3 = Color3.fromRGB(10, 10, 10) })
	Venyx:setTheme({ theme = "LightContrast", color3 = Color3.fromRGB(26, 26, 26) })
	Venyx:setTheme({ theme = "Accent", color3 = Color3.fromRGB(8, 8, 8) })
	Venyx:setTheme({ theme = "TextColor", color3 = Color3.fromRGB(255, 255, 255) })
end)

local PSteal = Venyx:addPage({ title = "Steal", icon = "rbxassetid://5012544372" })
local PFarm = Venyx:addPage({ title = "Farm", icon = "rbxassetid://5012544434" })
local PPlayer = Venyx:addPage({ title = "Player", icon = "rbxassetid://5012541974" })
local PEsp = Venyx:addPage({ title = "ESP", icon = "rbxassetid://5012544124" })
local PSafe = Venyx:addPage({ title = "Safety", icon = "rbxassetid://5012538273" })
local PMisc = Venyx:addPage({ title = "Misc", icon = "rbxassetid://5012538273" })

local SAuto = PSteal:addSection({ title = "Auto Steal" })
SAuto:addToggle({ title = "🥚 Auto Steal", default = false, callback = function(v)
	F.autoSteal = v
	if v then startSteal() else stopSteal() end
end })
SAuto:addDropdown({ title = "🚶 Go to egg", list = { "Tween", "Teleport" }, callback = function(v) F.goToEgg = v end })
SAuto:addDropdown({ title = "📦 Delivery", list = { "Tween", "Teleport", "Instant" }, callback = function(v)
	F.delivery = v
	F.instantSteal = (v == "Instant")
end })
SAuto:addSlider({ title = "⚡ Tween speed", min = 20, max = 250, default = 90, precision = 0, callback = function(v) F.tweenSpeed = v end })
SAuto:addSlider({ title = "⏱ Steal delay", min = 0.1, max = 3, default = 0.4, precision = 2, callback = function(v) F.stealDelay = v end })
SAuto:addToggle({ title = "🧠 Humanized movement", default = true, callback = function(v) F.humanize = v end })
SAuto:addToggle({ title = "⚡ Instant steal", default = false, callback = function(v) F.instantSteal = v end })
SAuto:addToggle({ title = "👥 Steal from others", default = true, callback = function(v) F.stealFromOthers = v end })
SAuto:addToggle({ title = "🛡 Anti guard", default = true, callback = function(v) F.antiGuard = v end })
SAuto:addToggle({ title = "🏠 Drop at safe zone", default = true, callback = function(v) F.dropSafeZone = v end })
SAuto:addButton({ title = "▶ Steal once", callback = function()
	local e = scanEggs()
	if e[1] then doSteal(e[1]) end
end })

local SPanel = PSteal:addSection({ title = "Steal Panel" })
SPanel:addToggle({ title = "🖼 Steal Panel", default = true, callback = function(v)
	F.stealPanel = v
	if not v then clearPanelButtons() end
end })
SPanel:addSlider({ title = "Max icons", min = 4, max = 24, default = 12, precision = 0, callback = function(v) F.stealPanelMax = v end })
SPanel:addSlider({ title = "Panel distance", min = 50, max = 1000, default = 400, precision = 0, callback = function(v) F.stealPanelDist = v end })

local SFilter = PSteal:addSection({ title = "Target filters" })
SFilter:addDropdown({ title = "🎯 Priority mode", list = { "Rarest first", "Closest", "Highest income" }, callback = function(v) F.stealFirst = v end })
SFilter:addDropdown({ title = "💎 Min rarity", list = { "All", "Common", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Secret", "BrainrotGod" }, callback = function(v) F.minRarity = v end })
SFilter:addToggle({ title = "📈 Min income filter", default = false, callback = function(v) F.minIncomeOn = v end })
SFilter:addSlider({ title = "📈 Min income/s", min = 0, max = 5000000, default = 0, precision = 0, callback = function(v) F.minIncome = v end })
SFilter:addDropdown({ title = "✨ Wanted mutation", list = { "None", "Gold", "Diamond", "Rainbow", "Galaxy", "Blood" }, callback = function(v) F.wantedMutation = v end })

local SPrio = PSteal:addSection({ title = "Area priority" })
local zoneOpts = { "None", "Forest", "Desert", "Ocean", "Volcano", "Cyber", "Void", "Snow", "Area1", "Area2", "Area3", "Area4" }
SPrio:addDropdown({ title = "1️⃣ First priority", list = zoneOpts, callback = function(v) F.priority1 = v end })
SPrio:addDropdown({ title = "2️⃣ Second priority", list = zoneOpts, callback = function(v) F.priority2 = v end })
SPrio:addDropdown({ title = "3️⃣ Third priority", list = zoneOpts, callback = function(v) F.priority3 = v end })
SPrio:addDropdown({ title = "4️⃣ Fourth priority", list = zoneOpts, callback = function(v) F.priority4 = v end })

local FTread = PFarm:addSection({ title = "Treadmill & upgrades" })
FTread:addToggle({ title = "🏃 Auto treadmill", default = false, callback = function(v) F.autoTreadmill = v end })
FTread:addToggle({ title = "⬆ Upgrade treadmill", default = false, callback = function(v) F.autoUpgradeTreadmill = v end })
FTread:addToggle({ title = "🏗 Upgrade base / pen", default = false, callback = function(v) F.autoUpgradeBase = v end })
FTread:addSlider({ title = "🏃 Treadmill mult", min = 1, max = 10, default = 1, precision = 0, callback = function(v) F.treadmillMult = v end })
FTread:addSlider({ title = "⏱ Upgrade delay", min = 0.5, max = 10, default = 1.5, precision = 1, callback = function(v) F.upgradeDelay = v end })

local FPet = PFarm:addSection({ title = "Pets · hatch · sell" })
FPet:addToggle({ title = "🐣 Auto hatch", default = false, callback = function(v) F.autoHatch = v end })
FPet:addToggle({ title = "📍 Auto place", default = false, callback = function(v) F.autoPlace = v end })
FPet:addToggle({ title = "⏩ Fast hatch", default = true, callback = function(v) F.fastHatch = v end })
FPet:addToggle({ title = "🔀 Auto fuse", default = false, callback = function(v) F.autoFuse = v end })
FPet:addToggle({ title = "⭐ Equip best", default = false, callback = function(v) F.autoEquipBest = v end })
FPet:addToggle({ title = "💸 Auto sell", default = false, callback = function(v) F.autoSell = v end })
FPet:addToggle({ title = "🛡 Mutation protection", default = true, callback = function(v) F.protectMutated = v end })
FPet:addToggle({ title = "👑 Keep best of each", default = true, callback = function(v) F.keepBestEach = v end })

local FEv = PFarm:addSection({ title = "Collect · quest · boss" })
FEv:addToggle({ title = "💵 Auto collect", default = true, callback = function(v) F.autoCollect = v end })
FEv:addToggle({ title = "📜 Auto quest (Scramble)", default = false, callback = function(v) F.autoQuest = v end })
FEv:addToggle({ title = "👹 Auto boss (Abyss)", default = false, callback = function(v) F.autoBoss = v end })
FEv:addButton({ title = "💵 Collect now", callback = function() stepCollect() end })
FEv:addButton({ title = "📜 Claim quests", callback = function() stepQuest() end })
FEv:addButton({ title = "👹 Boss now", callback = function() stepBoss() end })

local Pl = PPlayer:addSection({ title = "Movement (stealth apply)" })
Pl:addToggle({ title = "🏃 WalkSpeed", default = false, callback = function(v) F.speedOn = v end })
Pl:addSlider({ title = "🏃 Speed", min = 16, max = 120, default = 24, precision = 0, callback = function(v) F.walkSpeed = v end })
Pl:addToggle({ title = "🦘 JumpPower", default = false, callback = function(v) F.jumpOn = v end })
Pl:addSlider({ title = "🦘 Jump", min = 50, max = 200, default = 60, precision = 0, callback = function(v) F.jumpPower = v end })
Pl:addToggle({ title = "♾ Infinite jump", default = false, callback = function(v) F.infJump = v end })
Pl:addToggle({ title = "👻 Noclip", default = false, callback = function(v) F.noclip = v setNoclip(v) end })
Pl:addToggle({ title = "🕊 Fly", default = false, callback = function(v) F.fly = v setFly(v) end })
Pl:addSlider({ title = "🕊 Fly speed", min = 10, max = 150, default = 50, precision = 0, callback = function(v) F.flySpeed = v end })
Pl:addToggle({ title = "🎞 FPS cap", default = false, callback = function(v) F.fpsCapOn = v if v and setfpscap then setfpscap(F.fpsCap) end end })
Pl:addSlider({ title = "🎞 FPS limit", min = 30, max = 240, default = 60, precision = 0, callback = function(v) F.fpsCap = v if F.fpsCapOn and setfpscap then setfpscap(v) end end })

local EEgg = PEsp:addSection({ title = "Egg ESP" })
EEgg:addToggle({ title = "🥚 Eggs", default = true, callback = function(v) F.espEggs = v end })
EEgg:addToggle({ title = "🔵 Own blue", default = true, callback = function(v) F.espOwnBlue = v end })
EEgg:addToggle({ title = "📏 Show distance (panel)", default = true, callback = function(v) F.espShowDist = v end })
EEgg:addDropdown({ title = "💎 Min rarity", list = { "All", "Common", "Rare", "Epic", "Legendary", "Mythic", "Divine", "Secret" }, callback = function(v) F.espMinRarity = v end })
EEgg:addSlider({ title = "📏 Max distance", min = 50, max = 2000, default = 800, precision = 0, callback = function(v) F.espMaxDist = v end })

local EEnt = PEsp:addSection({ title = "Entities" })
EEnt:addToggle({ title = "👮 Guards", default = true, callback = function(v) F.espGuards = v end })
EEnt:addToggle({ title = "👤 Players", default = false, callback = function(v) F.espPlayers = v end })
EEnt:addToggle({ title = "🍊 Carriers", default = true, callback = function(v) F.espCarriers = v end })

local EMap = PEsp:addSection({ title = "Map" })
EMap:addToggle({ title = "🏠 Plot ESP", default = false, callback = function(v) F.espPlots = v end })
EMap:addToggle({ title = "🗺 Zone ESP", default = false, callback = function(v) F.espZones = v end })

local Safe = PSafe:addSection({ title = "Protection" })
Safe:addToggle({ title = "🚫 Anti trap", default = true, callback = function(v) F.antiTrap = v end })
Safe:addToggle({ title = "💥 Trap crusher", default = true, callback = function(v) F.trapCrush = v end })
Safe:addToggle({ title = "🦴 Anti ragdoll", default = true, callback = function(v) F.antiRagdoll = v end })
Safe:addToggle({ title = "🛡 Hazard immunity", default = true, callback = function(v) F.hazardImmune = v end })
Safe:addToggle({ title = "💤 Anti AFK", default = true, callback = function(v) F.antiAfk = v end })
Safe:addButton({ title = "🆘 Get unstuck", callback = function() unstuck() end })

local Panic = PSafe:addSection({ title = "Panic · staff" })
Panic:addToggle({ title = "🚨 Staff auto leave", default = false, callback = function(v) F.staffAutoLeave = v end })
Panic:addToggle({ title = "📡 Webhook on panic", default = true, callback = function(v) F.panicWebhook = v end })
Panic:addButton({ title = "📋 Set webhook (paste in console)", callback = function()
	notify("Webhook", "Set F.webhookUrl via executor or edit script")
	print("[Constipated] Set webhook: getgenv().CO_Webhook = 'YOUR_URL' then reload, or edit F.webhookUrl in source")
end })

-- allow runtime webhook from getgenv
if ENV.CO_Webhook and type(ENV.CO_Webhook) == "string" then
	F.webhookUrl = ENV.CO_Webhook
end
if ENV.CO_Watchlist and type(ENV.CO_Watchlist) == "string" then
	F.watchlist = ENV.CO_Watchlist
end

local Misc = PMisc:addSection({ title = "Menu" })
Misc:addButton({ title = "🔀 Server hop", callback = function()
	pcall(function()
		local placeId = game.PlaceId
		local servers = HttpService:JSONDecode(game:HttpGet(
			"https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100"
		))
		for _, s in ipairs(servers.data or {}) do
			if s.playing < s.maxPlayers and s.id ~= game.JobId then
				TeleportService:TeleportToPlaceInstance(placeId, s.id, LP)
				return
			end
		end
	end)
end })
Misc:addButton({ title = "🔄 Rejoin", callback = function()
	pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
end })
Misc:addButton({ title = "👁 Toggle UI", callback = function() pcall(function() Venyx:toggle() end) end })
Misc:addButton({ title = "❌ Unload", callback = function()
	S.unloaded = true
	stopSteal()
	F.fly = false
	setFly(false)
	setNoclip(false)
	clearPanelButtons()
	if S.panelGui then pcall(function() S.panelGui:Destroy() end) end
	for _, t in ipairs({ S.eggHL, S.guardHL, S.playerHL, S.plotHL }) do
		for _, hl in pairs(t) do pcall(function() hl:Destroy() end) end
	end
	for _, c in ipairs(S.conns) do pcall(function() c:Disconnect() end) end
	pcall(function()
		for _, g in ipairs(CoreGui:GetChildren()) do
			if g.Name == "Constipated Hub" or g.Name == "Venyx" or g.Name == "ConstipatedStealPanel" then
				g:Destroy()
			end
		end
	end)
	ENV.ConstipatedSAEUnload = nil
end })

pcall(function() Venyx:SelectPage({ page = PSteal, toggle = true }) end)
pcall(function()
	Venyx:Notify({ title = "Constipated Hub", text = "Humanized · Panel · Priority · Safety", duration = 5 })
end)

ENV.ConstipatedSAEUnload = function()
	S.unloaded = true
	stopSteal()
end

print("[Constipated Hub] SAE · full undetected-style suite")
