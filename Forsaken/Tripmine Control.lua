-- Tripmine Control Script (TP‑only version)
-- Removes Client / InvisibleTP modes and their GUI; TP is now the default.

--------------------------------------------------
-- Services
--------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

--------------------------------------------------
-- Player & Camera references
--------------------------------------------------
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

--------------------------------------------------
-- UI
--------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TripmineControlUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0, 180, 0, 50)
toggleButton.Position = UDim2.new(0, 10, 0, 10)
toggleButton.Text = "Control Tripmine"
toggleButton.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
toggleButton.TextColor3 = Color3.new(1, 1, 1)
toggleButton.TextScaled = true
toggleButton.Parent = screenGui

local speed = 20
local speedBox = Instance.new("TextBox")
speedBox.Size   = UDim2.new(0, 180, 0, 40)
speedBox.Position = UDim2.new(0, 10, 0, 70) -- shifted up (no mode button)
speedBox.Text = tostring(speed)
speedBox.PlaceholderText = "Speed"
speedBox.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
speedBox.TextColor3 = Color3.new(1, 1, 1)
speedBox.TextScaled = true
speedBox.ClearTextOnFocus = false
speedBox.Parent = screenGui

speedBox.FocusLost:Connect(function()
	local newSpeed = tonumber(speedBox.Text)
	if newSpeed then
		speed = math.clamp(newSpeed, 1, 500)
		speedBox.Text = tostring(speed)
	else
		speedBox.Text = tostring(speed)
	end
end)

--------------------------------------------------
-- State
--------------------------------------------------
local controlling       = false
local tripmineModel     = nil
local zoomDistance      = 10
local yaw, pitch        = 0, 0
local bodyVelocity      = nil
local originalCFrame    = nil
local teleportLoopRunning = false
local pinchInfo         = {}
local lastTouchPos      = nil

--------------------------------------------------
-- Helpers
--------------------------------------------------
local function cleanUpConstraints()
	local char = player.Character
	if not char then return end
	for _, obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BodyMover") or obj:IsA("BodyVelocity") or obj:IsA("BodyGyro") or (obj:IsA("BasePart") and obj.Name == "TripmineController") then
			pcall(function() obj:Destroy() end)
		end
	end
end

local function getTripmine()
	local map = workspace:FindFirstChild("Map")
	if map then
		local ingame = map:FindFirstChild("Ingame")
		if ingame then
			return ingame:FindFirstChild("SubspaceTripmine")
		end
	end
	return nil
end

local function resetCamera()
	cleanUpConstraints()
	controlling         = false
	toggleButton.Text   = "Control Tripmine"
	camera.CameraType   = Enum.CameraType.Custom

	local character     = player.Character or player.CharacterAdded:Wait()
	local humanoid      = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
	camera.CameraSubject = humanoid

	if bodyVelocity then
		pcall(function() bodyVelocity:Destroy() end)
		bodyVelocity = nil
	end

	if originalCFrame then
		local hrp = character:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = originalCFrame end
		originalCFrame = nil
	end

	teleportLoopRunning = false
	tripmineModel       = nil
end

local function startTeleportLoop()
	teleportLoopRunning = true
	task.spawn(function()
		while teleportLoopRunning and controlling and tripmineModel and tripmineModel.PrimaryPart do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp then
				-- keep player near the mine to avoid anti‑cheat issues
				hrp.CFrame = tripmineModel.PrimaryPart.CFrame + Vector3.new(0, 2, 0)
			end
			task.wait(0.25)
		end
	end)
end

--------------------------------------------------
-- Main toggle
--------------------------------------------------
local function toggleControl()
	local model = getTripmine()
	if not (model and model:IsA("Model") and model.PrimaryPart) then return end

	tripmineModel   = model
	controlling     = not controlling
	toggleButton.Text = controlling and "Stop Controlling" or "Control Tripmine"

	local character = player.Character or player.CharacterAdded:Wait()
	local hrp       = character:WaitForChild("HumanoidRootPart")

	if controlling then
		local forward = model.PrimaryPart.CFrame.LookVector
		yaw   = math.atan2(-forward.X, -forward.Z)
		pitch = 0

		-- switch camera
		camera.CameraType   = Enum.CameraType.Scriptable
		camera.CameraSubject = nil

		-- lock player near mine
		originalCFrame = hrp.CFrame
		hrp.CFrame     = model.PrimaryPart.CFrame + Vector3.new(0, 2, 0)

		-- BodyVelocity for TP movement
		bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
		bodyVelocity.Velocity = Vector3.zero
		bodyVelocity.P        = 1250
		bodyVelocity.Name     = "TripmineController"
		bodyVelocity.Parent   = model.PrimaryPart

		startTeleportLoop()

		model.Destroying:Once(resetCamera)
	else
		resetCamera()
	end
end

toggleButton.MouseButton1Click:Connect(toggleControl)

--------------------------------------------------
-- Mouse / PC input
--------------------------------------------------
UserInputService.InputChanged:Connect(function(input)
	if not controlling then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		yaw   -= input.Delta.X * 0.01
		pitch  = math.clamp(pitch - input.Delta.Y * 0.01, -1.2, 1.2)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		zoomDistance = math.clamp(zoomDistance - input.Position.Z * 1.5, 5, 50)
	end
end)

--------------------------------------------------
-- Touch input (mobile)
--------------------------------------------------
UserInputService.TouchStarted:Connect(function(input)
	if not controlling then return end
	if not pinchInfo.first then
		pinchInfo.first = input
		lastTouchPos    = input.Position
	elseif not pinchInfo.second then
		pinchInfo.second   = input
		pinchInfo.lastDist = (pinchInfo.first.Position - input.Position).Magnitude
	end
end)

UserInputService.TouchMoved:Connect(function(input)
	if not controlling then return end
	if pinchInfo.first and pinchInfo.second and (input == pinchInfo.first or input == pinchInfo.second) then
		local p1      = pinchInfo.first.Position
		local p2      = pinchInfo.second.Position
		local newDist = (p1 - p2).Magnitude
		if pinchInfo.lastDist then
			local zoomDelta  = (newDist - pinchInfo.lastDist) * 0.03
			zoomDistance     = math.clamp(zoomDistance - zoomDelta, 5, 50)
		end
		pinchInfo.lastDist = newDist
	elseif pinchInfo.first and input == pinchInfo.first and not pinchInfo.second then
		local delta   = input.Position - lastTouchPos
		lastTouchPos  = input.Position
		yaw          -= delta.X * 0.005
		pitch         = math.clamp(pitch - delta.Y * 0.005, -1.2, 1.2)
	end
end)

UserInputService.TouchEnded:Connect(function(input)
	if input == pinchInfo.first then
		pinchInfo.first   = pinchInfo.second
		pinchInfo.second  = nil
		pinchInfo.lastDist = nil
	elseif input == pinchInfo.second then
		pinchInfo.second  = nil
		pinchInfo.lastDist = nil
	end
	if not pinchInfo.first then
		lastTouchPos = nil
	end
end)

--------------------------------------------------
-- Camera + Tripmine movement loop
--------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	if controlling and tripmineModel and tripmineModel.PrimaryPart then
		-- camera positioning
		yaw   = yaw % (2 * math.pi)
		pitch = math.clamp(pitch, -1.2, 1.2)

		local rootPos  = tripmineModel.PrimaryPart.Position + Vector3.new(0, 2, 0)
		local rotCF    = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local camOffset = rotCF:VectorToWorldSpace(Vector3.new(0, 0, zoomDistance))
		camera.CFrame  = CFrame.new(rootPos + camOffset, rootPos)

		-- push mine forward
		local forward = rotCF.LookVector
		if bodyVelocity then
			bodyVelocity.Velocity = forward * speed
		end
	end
end)
