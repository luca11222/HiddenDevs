```lua id="npc200"
local npcClass = {}
npcClass.__index = npcClass

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

function npcClass.new(model)
	local self = setmetatable({}, npcClass)

	self.model = model
	self.humanoid = model:WaitForChild("Humanoid")
	self.root = model:WaitForChild("HumanoidRootPart")

	self.id = model.Name
	self.target = nil

	self.state = "idle"
	self.range = 80
	self.attackRange = 6

	self.memory = nil
	self.memoryTime = 0

	self.cooldowns = {}
	self.states = {}

	self.moving = false
	self.lastPos = nil

	self.debugEnabled = true

	self:initStates()

	return self
end

-- debug used to track behaviour during runtime
function npcClass:debug(msg)
	if not self.debugEnabled then return end
	print("NPC", self.id, msg)
end

-- cooldown prevents spam actions like attack
function npcClass:setCooldown(name, time)
	self.cooldowns[name] = tick() + time
end

-- checks if cooldown still active
function npcClass:hasCooldown(name)
	return self.cooldowns[name] and self.cooldowns[name] > tick()
end

-- find closest player to reduce search cost later
function npcClass:getClosestPlayer()
	local closest
	local dist = math.huge

	for _, player in pairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end

		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end

		local d = (hrp.Position - self.root.Position).Magnitude

		if d < dist then
			dist = d
			closest = char
		end
	end

	return closest, dist
end

-- dot check avoids full raycast every frame
function npcClass:canSee(target)
	if not target then return end

	local hrp = target:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local dir = (hrp.Position - self.root.Position).Unit
	local look = self.root.CFrame.LookVector

	local dot = look:Dot(dir)

	if dot > 0.4 then
		return true
	end
end

-- follow uses humanoid for built in path solving
function npcClass:follow(target)
	if not target then return end

	local hrp = target:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	self.humanoid:MoveTo(hrp.Position)
	self.moving = true
end

-- attack uses cooldown to control damage rate
function npcClass:attack(target)
	if self:hasCooldown("attack") then return end

	local hum = target:FindFirstChild("Humanoid")
	if not hum then return end

	self:setCooldown("attack", 1.5)

	hum:TakeDamage(10)
	self:debug("attack fired")
end

-- memory stores last known target position
function npcClass:updateMemory(pos)
	self.memory = pos
	self.memoryTime = tick()
end

-- memory decay avoids infinite chasing
function npcClass:hasMemory()
	return self.memory and (tick() - self.memoryTime < 5)
end

function npcClass:initStates()
	self.states = {

		idle = {
			enter = function(self)
				self:debug("idle enter")
			end,

			update = function(self)
				local target, dist = self:getClosestPlayer()

				if target and dist < self.range then
					if self:canSee(target) then
						self.target = target
						self:updateMemory(target.HumanoidRootPart.Position)
						self:setState("chasing")
					end
				end
			end
		},

		chasing = {
			enter = function(self)
				self:debug("chasing enter")
			end,

			update = function(self)
				if not self.target then
					self:setState("searching")
					return
				end

				local hrp = self.target:FindFirstChild("HumanoidRootPart")
				if not hrp then
					self.target = nil
					self:setState("searching")
					return
				end

				local dist = (hrp.Position - self.root.Position).Magnitude

				if dist > self.range then
					self.target = nil
					self:setState("searching")
					return
				end

				self:updateMemory(hrp.Position)

				if dist <= self.attackRange then
					self:setState("attacking")
					return
				end

				self:follow(self.target)
			end
		},

		searching = {
			enter = function(self)
				self:debug("searching enter")
			end,

			update = function(self)
				if self:hasMemory() then
					self.humanoid:MoveTo(self.memory)

					if (self.root.Position - self.memory).Magnitude < 3 then
						self.memory = nil
					end
				else
					self:setState("idle")
				end
			end
		},

		attacking = {
			enter = function(self)
				self:debug("attacking enter")
			end,

			update = function(self)
				if not self.target then
					self:setState("idle")
					return
				end

				local hrp = self.target:FindFirstChild("HumanoidRootPart")
				if not hrp then
					self.target = nil
					self:setState("idle")
					return
				end

				local dist = (hrp.Position - self.root.Position).Magnitude

				if dist > self.attackRange then
					self:setState("chasing")
					return
				end

				self:attack(self.target)
			end
		}
	}
end

-- state change ensures clean transitions
function npcClass:setState(state)
	if self.state == state then return end

	if self.states[self.state] and self.states[self.state].exit then
		self.states[self.state].exit(self)
	end

	self.state = state

	if self.states[self.state] and self.states[self.state].enter then
		self.states[self.state].enter(self)
	end
end

-- movement check prevents stuck npc
function npcClass:move()
	if not self.moving then return end

	if self.lastPos then
		if (self.root.Position - self.lastPos).Magnitude < 0.5 then
			self.moving = false
			self:debug("movement stopped")
		end
	end

	self.lastPos = self.root.Position
end

-- update delegates logic to state
function npcClass:update()
	if self.states[self.state] and self.states[self.state].update then
		self.states[self.state].update(self)
	end
end

-- heartbeat loop keeps npc responsive
function npcClass:start()
	self.connection = RunService.Heartbeat:Connect(function()
		self:update()
		self:move()
	end)
end

-- cleanup avoids memory leaks
function npcClass:Destroy()
	if self.connection then
		self.connection:Disconnect()
	end

	self.model:Destroy()
end

return npcClass
```

