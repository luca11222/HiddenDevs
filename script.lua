--Services
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

-- Class
local NPC = {}
NPC.__index = NPC

-- Constructor
function NPC.new(model)
    local self = setmetatable({}, NPC)

    self.model = model
    self.root = model:WaitForChild("HumanoidRootPart")
    self.humanoid = model:WaitForChild("Humanoid")

    -- Config
    self.maxDistance = 150
    self.attackRange = 6
    self.viewAngle = 0.5
    self.memoryTime = 4
    self.attackCooldown = 1.2
    self.windupTime = 0.25

    -- State
    self.state = "Idle"
    self.target = nil
    self.lastSeen = 0
    self.lastAttack = 0

    -- Movement
    self.currentPath = nil
    self.waypoints = {}
    self.waypointIndex = 1
    self.moving = false

    return self
end


--VALIDATION


-- Ensures a target is alive and usable
function NPC:isValidTarget(target)
    if not target then return false end

    local hum = target:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end

    local hrp = target:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    return true
end


TARGETING


-- Finds closest player efficiently
function NPC:getClosestPlayer()
    local closest = nil
    local shortest = math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if not self:isValidTarget(char) then continue end

        local hrp = char.HumanoidRootPart
        local dist = (hrp.Position - self.root.Position).Magnitude

        if dist < shortest then
            shortest = dist
            closest = char
        end
    end

    return closest, shortest
end

-- Checks if target is within field of view using dot product
function NPC:canSee(target)
    if not self:isValidTarget(target) then return false end

    local dir = (target.HumanoidRootPart.Position - self.root.Position).Unit
    local dot = self.root.CFrame.LookVector:Dot(dir)

    return dot > self.viewAngle
end

-- Predicts future position based on velocity
function NPC:getPredictedPosition(target)
    local hrp = target.HumanoidRootPart
    return hrp.Position + (hrp.Velocity * 0.4)
end


MOVEMENT


-- Computes a path to predicted position
function NPC:computePath(target)
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true
    })

    local predicted = self:getPredictedPosition(target)

    path:ComputeAsync(self.root.Position, predicted)

    if path.Status ~= Enum.PathStatus.Success then return nil end

    return path
end

-- Starts following a path without blocking main thread
function NPC:followPath(path)
    self.currentPath = path
    self.waypoints = path:GetWaypoints()
    self.waypointIndex = 1
    self.moving = true

    task.spawn(function()
        while self.moving do
            local waypoint = self.waypoints[self.waypointIndex]
            if not waypoint then break end

            self.humanoid:MoveTo(waypoint.Position)

            local reached = self.humanoid.MoveToFinished:Wait()
            if not reached then break end

            self.waypointIndex += 1
        end

        self.moving = false
    end)
end

-- Stops movement safely
function NPC:stopMoving()
    self.moving = false
    self.currentPath = nil
    self.waypoints = {}
end


--COMBAT


-- Handles attacking with cooldown and windup
function NPC:attack(target)
    if tick() - self.lastAttack < self.attackCooldown then return end
    if not self:isValidTarget(target) then return end

    self.lastAttack = tick()

    task.delay(self.windupTime, function()
        if not self:isValidTarget(target) then return end

        local dist = (target.HumanoidRootPart.Position - self.root.Position).Magnitude
        if dist > self.attackRange then return end

        target.Humanoid:TakeDamage(20)
    end)
end

-- STATE LOGIC


function NPC:idle()
    local target, dist = self:getClosestPlayer()

    if not target then return end
    if dist > self.maxDistance then return end

    if self:canSee(target) then
        self.target = target
        self.lastSeen = tick()
        self.state = "Chase"
    end
end

function NPC:chase()
    if not self:isValidTarget(self.target) then
        self.target = nil
        self.state = "Idle"
        self:stopMoving()
        return
    end

    local hrp = self.target.HumanoidRootPart
    local dist = (hrp.Position - self.root.Position).Magnitude

    if self:canSee(self.target) then
        self.lastSeen = tick()
    end

    if tick() - self.lastSeen > self.memoryTime then
        self.target = nil
        self.state = "Idle"
        self:stopMoving()
        return
    end

    if dist <= self.attackRange then
        self.state = "Attack"
        self:stopMoving()
        return
    end

    if not self.moving then
        local path = self:computePath(self.target)
        if path then
            self:followPath(path)
        end
    end
end

function NPC:attackState()
    if not self:isValidTarget(self.target) then
        self.state = "Idle"
        return
    end

    local dist = (self.target.HumanoidRootPart.Position - self.root.Position).Magnitude

    if dist > self.attackRange then
        self.state = "Chase"
        return
    end

    self:attack(self.target)
end


--UPDATE LOOP


function NPC:update()
    if self.state == "Idle" then
        self:idle()
        return
    end

    if self.state == "Chase" then
        self:chase()
        return
    end

    if self.state == "Attack" then
        self:attackState()
        return
    end
end

-- Start system using Heartbeat
function NPC:start()
    RunService.Heartbeat:Connect(function()
        if not self.model.Parent then return end
        self:update()
    end)
end

return NPC
