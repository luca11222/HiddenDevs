--// Services
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

--// NPC Class
local npcClass = {}
npcClass.__index = npcClass

--// Constructor
function npcClass.new(model)
    local self = setmetatable({}, npcClass)

    self.model = model
    self.root = model:WaitForChild("HumanoidRootPart")
    self.humanoid = model:WaitForChild("Humanoid")

    --// Config
    self.maxDistance = 150
    self.attackRange = 6
    self.viewAngle = 0.5
    self.memoryTime = 4
    self.attackCooldown = 1.2
    self.windupTime = 0.3

    --// State
    self.state = "Idle"
    self.target = nil
    self.lastSeen = 0
    self.lastAttack = 0

    --// Path state
    self.currentPath = nil
    self.waypointIndex = 1
    self.moving = false

    return self
end

--// Validate target
-- Ensures target still exists and is alive
function npcClass:isValidTarget(target)
    if not target then return false end

    local hum = target:FindFirstChild("Humanoid")
    local hrp = target:FindFirstChild("HumanoidRootPart")

    if not hum or hum.Health <= 0 then return false end
    if not hrp then return false end

    return true
end

--// Get closest target
function npcClass:getClosestPlayer()
    local closest, dist = nil, math.huge

    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if not self:isValidTarget(char) then continue end

        local hrp = char.HumanoidRootPart
        local d = (hrp.Position - self.root.Position).Magnitude

        if d < dist then
            dist = d
            closest = char
        end
    end

    return closest, dist
end

--// Vision check (dot product)
function npcClass:canSee(target)
    if not self:isValidTarget(target) then return false end

    local dir = (target.HumanoidRootPart.Position - self.root.Position).Unit
    local dot = self.root.CFrame.LookVector:Dot(dir)

    return dot > self.viewAngle
end

--// Predictive position (leads moving targets)
function npcClass:getPredictedPosition(target)
    local hrp = target.HumanoidRootPart
    local velocity = hrp.Velocity

    return hrp.Position + (velocity * 0.5)
end

--// Compute path (non-blocking)
function npcClass:computePath(target)
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

--// Start moving along path (non-blocking)
function npcClass:followPath(path)
    self.currentPath = path
    self.waypointIndex = 1

    local waypoints = path:GetWaypoints()
    if #waypoints == 0 then return end

    self.moving = true

    task.spawn(function()
        while self.moving and self.currentPath == path do
            local waypoint = waypoints[self.waypointIndex]
            if not waypoint then break end

            self.humanoid:MoveTo(waypoint.Position)

            local reached = self.humanoid.MoveToFinished:Wait()
            if not reached then break end

            self.waypointIndex += 1
        end

        self.moving = false
    end)
end

--// Stop movement safely
function npcClass:stopMoving()
    self.moving = false
    self.currentPath = nil
end

--// Attack with windup + cooldown
function npcClass:attack(target)
    if tick() - self.lastAttack < self.attackCooldown then return end
    if not self:isValidTarget(target) then return end

    self.lastAttack = tick()

    -- Windup (gives combat weight / realism)
    task.delay(self.windupTime, function()
        if not self:isValidTarget(target) then return end

        local dist = (target.HumanoidRootPart.Position - self.root.Position).Magnitude
        if dist > self.attackRange then return end

        target.Humanoid:TakeDamage(20)
    end)
end

--// State: Idle
function npcClass:idle()
    local target, dist = self:getClosestPlayer()
    if not target then return end
    if dist > self.maxDistance then return end

    if self:canSee(target) then
        self.target = target
        self.lastSeen = tick()
        self.state = "Chase"
    end
end

--// State: Chase
function npcClass:chase()
    if not self:isValidTarget(self.target) then
        self.target = nil
        self.state = "Idle"
        self:stopMoving()
        return
    end

    local hrp = self.target.HumanoidRootPart
    local dist = (hrp.Position - self.root.Position).Magnitude

    -- Update memory
    if self:canSee(self.target) then
        self.lastSeen = tick()
    end

    -- Forget target
    if tick() - self.lastSeen > self.memoryTime then
        self.target = nil
        self.state = "Idle"
        self:stopMoving()
        return
    end

    -- Switch to attack
    if dist <= self.attackRange then
        self.state = "Attack"
        self:stopMoving()
        return
    end

    -- Recalculate path periodically
    if not self.moving then
        local path = self:computePath(self.target)
        if path then
            self:followPath(path)
        end
    end
end

--// State: Attack
function npcClass:attackState()
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

--// Main update (Heartbeat-driven)
function npcClass:start()
    RunService.Heartbeat:Connect(function()
        if not self.model.Parent then return end

        if self.state == "Idle" then
            self:idle()
        elseif self.state == "Chase" then
            self:chase()
        elseif self.state == "Attack" then
            self:attackState()
        end
    end)
end

return npcClass
