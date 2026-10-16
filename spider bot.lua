--[[
	WARNING: Heads up! This script has not been verified by ScriptBlox. Use at your own risk!
]]
-- PROJECT SPIDER V9 — REFERENCE-STYLE ACROBATICS + WEB FX
-- LocalScript: StarterPlayer > StarterPlayerScripts
-- Q: Hold Swing | E: Zip | R: Hold Pull
-- C: Toggle Crawl | F: Charge / Fire Slingshot
-- SPACE: Reel while swinging / Leap while crawling
-- SHIFT: Extend rope / Crawl faster | X: Cancel
-- Mobile buttons are included.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Animation assets carried over from Spider Proto.
local SWING_ANIM_ID = "rbxassetid://507767968"
local CLIMB_ANIM_ID = "rbxassetid://507765644"
local swingStep = 1
local zipStep = 1

-- Keeps procedural leg posing alive briefly after releasing a swing.
local airborneLegPose = nil
local airborneKickUntil = 0
local airborneKickStarted = 0
local boostedWalkSpeed = nil
local boostedWalkSpeedUntil = 0

local CONFIG = {
	SwingForward = 48,
	SwingHeight = 48,
	SwingBoost = 62,
	SwingAcceleration = 132,
	SwingAssist = 24,
	SwingMaxSpeed = 260,
	RopeMinLength = 12,
	RopeMaxLength = 180,
	RopeReelSpeed = 26,

	ZipDistance = 135,
	ZipSpeed = 155,
	ZipDuration = 1.15,

	PullDistance = 100,
	PullSpeed = 110,
	PullDuration = 2.5,

	ClimbReach = 4.8,
	ClimbSpeed = 19,
	ClimbSprintSpeed = 29,
	SurfaceOffset = 1.65,
	SurfaceStickSpeed = 15,
	SurfaceGraceTime = 0.55,

	SlingDistance = 85,
	SlingChargeTime = 1.6,
	SlingMinSpeed = 95,
	SlingMaxSpeed = 180,
	SlingLift = 45,

	Cooldowns = {
		Swing = 0.12,
		Zip = 0.45,
		Pull = 0.6,
		Climb = 0.15,
		Sling = 6,
	},
}

local COLORS = {
	Red = Color3.fromRGB(210, 35, 48),
	Blue = Color3.fromRGB(35, 115, 225),
	Dark = Color3.fromRGB(25, 28, 36),
	Active = Color3.fromRGB(30, 155, 110),
	White = Color3.fromRGB(245, 247, 255),
}

local previous = playerGui:FindFirstChild("SpiderUI")
if previous then
	local oldShutdown = previous:FindFirstChild("Shutdown")
	if oldShutdown and oldShutdown:IsA("BindableEvent") then
		oldShutdown:Fire()
	end
	previous:Destroy()
end

local previousSling = playerGui:FindFirstChild("SpiderSlingshotSolo")
if previousSling then
	previousSling:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpiderUI"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local shutdown = Instance.new("BindableEvent")
shutdown.Name = "Shutdown"
shutdown.Parent = gui

local running = true
local connections = {}
local deathConnection
local characterGeneration = 0

local character
local humanoid
local root

local cooldowns = {}
local keys = {}
local actionHolds = {}
local crawlTouches = {}
local ropeTouches = {}
local buttons = {}

local notice = ""
local noticeUntil = 0

local state = {
	mode = "Idle",
	objects = {},
}

local stopMode
local startSwing
local startZip
local startPull
local toggleClimb
local slingAction
local leapOff

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function alive()
	return running
		and character ~= nil
		and character.Parent ~= nil
		and root ~= nil
		and root.Parent ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
end

local function unitOr(vector, fallback)
	if vector.Magnitude > 0.001 then
		return vector.Unit
	end
	return fallback
end

local function project(vector, normal)
	return vector - normal * vector:Dot(normal)
end

local function own(object)
	table.insert(state.objects, object)
	return object
end

local function tell(text)
	notice = text
	noticeUntil = os.clock() + 2.2
end

local function ready(action)
	return os.clock() >= (cooldowns[action] or 0)
end

local function cooldown(action)
	cooldowns[action] = os.clock() + CONFIG.Cooldowns[action]
end

local function playSound(id, volume, speed)
	if not alive() then return end

	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Volume = volume or 0.8
	sound.PlaybackSpeed = speed or 1
	sound.Parent = root
	sound:Play()
	Debris:AddItem(sound, 4)
end

local function cameraDirection()
	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.LookVector
		or root.CFrame.LookVector
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.Touch
		or input.UserInputType == Enum.UserInputType.MouseButton1
end

local function makeButton(parent, name, text, color, size)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size or UDim2.fromOffset(70, 70)
	button.BackgroundColor3 = color
	button.TextColor3 = COLORS.White
	button.Text = text
	button.TextSize = 14
	button.TextWrapped = true
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 18)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.White
	stroke.Transparency = 0.72
	stroke.Thickness = 1.5
	stroke.Parent = button

	return button
end

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.fromScale(0.5, 0.025)
status.Size = UDim2.new(0.92, 0, 0, 46)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamBold
status.TextSize = 14
status.TextWrapped = true
status.TextColor3 = COLORS.White
status.TextStrokeTransparency = 0.35
status.Text = "PROJECT SPIDER V3"
status.Parent = gui

local actionPanel = Instance.new("Frame")
actionPanel.AnchorPoint = Vector2.new(1, 0.5)
actionPanel.Position = UDim2.new(1, -14, 0.5, 0)
actionPanel.Size = UDim2.fromOffset(76, 388)
actionPanel.BackgroundTransparency = 1
actionPanel.Parent = gui

local actionScale = Instance.new("UIScale")
actionScale.Parent = actionPanel

local actionLayout = Instance.new("UIListLayout")
actionLayout.Padding = UDim.new(0, 8)
actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
actionLayout.Parent = actionPanel

local definitions = {
	{"Swing", "SWING\n[Q]", COLORS.Red},
	{"Zip", "ZIP\n[E]", COLORS.Blue},
	{"Pull", "PULL\n[R]", COLORS.Dark},
	{"Climb", "CRAWL\n[C]", COLORS.Red},
	{"Sling", "SLING\n[F]", COLORS.Blue},
}

for index, definition in ipairs(definitions) do
	local action, text, color = table.unpack(definition)
	local button = makeButton(actionPanel, action, text, color)
	button.LayoutOrder = index

	buttons[action] = {
		button = button,
		text = text,
		color = color,
	}
end

local crawlPanel = Instance.new("Frame")
crawlPanel.AnchorPoint = Vector2.new(0.5, 1)
crawlPanel.Position = UDim2.new(0.5, 0, 1, -20)
crawlPanel.Size = UDim2.fromOffset(204, 136)
crawlPanel.BackgroundTransparency = 1
crawlPanel.Visible = false
crawlPanel.Parent = gui

local crawlScale = Instance.new("UIScale")
crawlScale.Parent = crawlPanel

local function makeDirection(name, text, x, y)
	local button = makeButton(
		crawlPanel,
		name,
		text,
		COLORS.Dark,
		UDim2.fromOffset(62, 62)
	)
	button.Position = UDim2.fromOffset(x, y)
	return button
end

local upButton = makeDirection("Up", "UP", 71, 0)
local downButton = makeDirection("Down", "DOWN", 71, 72)
local leftButton = makeDirection("Left", "LEFT", 0, 72)
local rightButton = makeDirection("Right", "RIGHT", 142, 72)

local leapButton = makeButton(
	gui,
	"LeapOff",
	"LEAP OFF [SPACE]",
	COLORS.Blue,
	UDim2.fromOffset(190, 42)
)
leapButton.AnchorPoint = Vector2.new(0.5, 0)
leapButton.Position = UDim2.new(0.5, 0, 0.025, 50)
leapButton.Visible = false

local ropePanel = Instance.new("Frame")
ropePanel.AnchorPoint = Vector2.new(0.5, 1)
ropePanel.Position = UDim2.new(0.5, 0, 1, -28)
ropePanel.Size = UDim2.fromOffset(224, 54)
ropePanel.BackgroundTransparency = 1
ropePanel.Visible = false
ropePanel.Parent = gui

local ropeScale = Instance.new("UIScale")
ropeScale.Parent = ropePanel

local reelButton = makeButton(
	ropePanel,
	"ReelIn",
	"REEL IN",
	COLORS.Blue,
	UDim2.fromOffset(106, 54)
)

local extendButton = makeButton(
	ropePanel,
	"LetOut",
	"LET OUT",
	COLORS.Dark,
	UDim2.fromOffset(106, 54)
)
extendButton.Position = UDim2.fromOffset(118, 0)

-- Web abilities use invisible, non-colliding points in open air.
local function makeAirAnchor(position)
	local part = own(Instance.new("Part"))
	part.Name = "SpiderAirAnchor"
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Position = position
	part.Parent = Workspace

	local attachment = own(Instance.new("Attachment"))
	attachment.Name = "WebAnchor"
	attachment.Parent = part

	return attachment
end

local function handPart(side)
	return character:FindFirstChild(side .. "Hand")
		or character:FindFirstChild(side .. " Arm")
end

local function makeHandWeb(side, target)
	local hand = handPart(side)
	if not hand then return end

	local attachment = own(Instance.new("Attachment"))
	attachment.Name = "Spider" .. side .. "Web"
	attachment.Position = Vector3.new(0, -hand.Size.Y * 0.45, 0)
	attachment.Parent = hand

	local beam = own(Instance.new("Beam"))
	beam.Name = "SpiderWeb"
	beam.Attachment0 = attachment
	beam.Attachment1 = target
	beam.Width0 = 0.105
	beam.Width1 = 0.045
	beam.FaceCamera = true
	beam.Segments = 18
	beam.LightEmission = 0.65
	beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = 1.4
	beam.TextureSpeed = -2.2
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(225, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.02),
		NumberSequenceKeypoint.new(0.8, 0.12),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	beam.Parent = hand
end

local function startHandPose(activeSides)
	state.pose = {
		targets = {},
		shoulders = {},
		legs = {},
	}

	for _, side in ipairs({"Left", "Right"}) do
		local enabled = activeSides == nil or activeSides[side] == true
		local hand = enabled and handPart(side) or nil
		local upperArm = character:FindFirstChild(side .. "UpperArm")

		if not enabled then
			-- Leave the inactive arm alone so the alternating-arm style is preserved.
		elseif humanoid.RigType == Enum.HumanoidRigType.R15
			and hand and upperArm then

			local target = own(Instance.new("Attachment"))
			target.Name = "Spider" .. side .. "Grip"
			target.Parent = root
			state.pose.targets[side] = target

			local ik = own(Instance.new("IKControl"))
			ik.Name = "Spider" .. side .. "ArmIK"
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = upperArm
			ik.EndEffector = hand
			ik.Target = target
			ik.Weight = 1
			ik.SmoothTime = 0.08
			ik.Priority = 10
			ik.Parent = humanoid
		else
			local torso = character:FindFirstChild("Torso")
			local shoulder = torso
				and torso:FindFirstChild(side .. " Shoulder")

			if shoulder and shoulder:IsA("Motor6D") then
				state.pose.shoulders[side] = {
					motor = shoulder,
					transform = shoulder.Transform,
				}
			end
		end
	end

	-- Procedural acrobatic leg posing. Discover joints by normalized names so
	-- both R6 ("Left Hip") and R15 ("LeftHip", "LeftKnee") rigs are supported.
	local function normalizeJointName(name)
		return string.lower(string.gsub(name, "[%s_%-]", ""))
	end
	for _, joint in ipairs(character:GetDescendants()) do
		if joint:IsA("Motor6D") then
			local n = normalizeJointName(joint.Name)
			local side = string.find(n, "left") and "Left"
				or (string.find(n, "right") and "Right")
			if side and (string.find(n, "hip") or string.find(n, "knee")) then
				local key = side .. (string.find(n, "knee") and "Knee" or "Hip")
				state.pose.legs[key] = {
					motor = joint,
					transform = joint.Transform,
				}
			end
		end
	end
	-- Legacy aliases are kept because the pose updater accepts both naming styles.
	state.pose.legs["Left Hip"] = state.pose.legs["Left Hip"] or state.pose.legs.LeftHip
	state.pose.legs["Right Hip"] = state.pose.legs["Right Hip"] or state.pose.legs.RightHip
	state.pose.legs.LeftKnee = state.pose.legs.LeftKnee
		or state.pose.legs.LeftKnee
	state.pose.legs.RightKnee = state.pose.legs.RightKnee
		or state.pose.legs.RightKnee
end

local function updateHandPose()
	if not state.pose or not state.anchors then return end

	for _, side in ipairs({"Left", "Right"}) do
		local index = side == "Left" and 1 or 2
		local anchor = state.anchors[index] or state.anchors[1]
		local target = state.pose.targets[side]
		local shoulderEntry = state.pose.shoulders[side]
		local sideEnabled = state.activeWebSides == nil
			or state.activeWebSides[side] == true

		if target and anchor and anchor.Parent then
			local shoulderPosition =
				root.Position + root.CFrame.UpVector * 1.25

			local direction = unitOr(
				anchor.WorldPosition - shoulderPosition,
				root.CFrame.UpVector
			)

			local separation = side == "Left" and -0.19 or 0.19
			local grip = shoulderPosition
				+ direction * 2
				+ root.CFrame.RightVector * separation

			target.Position = root.CFrame:PointToObjectSpace(grip)
		elseif shoulderEntry and shoulderEntry.motor.Parent and sideEnabled then
			-- R6 has no IKControl, so pose each active shoulder directly.
			local roll = side == "Left" and math.rad(-12) or math.rad(12)
			shoulderEntry.motor.Transform = shoulderEntry.transform
				* CFrame.Angles(math.rad(-90), 0, roll)
		end
	end
end

local function attachWebs(firstPosition, secondPosition, activeSides)
	local first = makeAirAnchor(firstPosition)
	local second = secondPosition and makeAirAnchor(secondPosition) or first

	state.anchors = {first, second}
	state.activeWebSides = activeSides

	if activeSides == nil or activeSides.Left then makeHandWeb("Left", first) end
	if activeSides == nil or activeSides.Right then makeHandWeb("Right", second) end
	startHandPose(activeSides)
	updateHandPose()
end

local function validAnchors()
	if not state.anchors then return false end

	for _, anchor in ipairs(state.anchors) do
		if not anchor:IsDescendantOf(Workspace) then
			return false
		end
	end

	return true
end

local function makePhysics(useVelocity)
	local attachment = own(Instance.new("Attachment"))
	attachment.Name = "SpiderMotion"
	attachment.Parent = root
	state.motionAttachment = attachment

	local orientation = own(Instance.new("AlignOrientation"))
	orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orientation.Attachment0 = attachment
	orientation.MaxTorque = 1000000
	orientation.MaxAngularVelocity = 14
	orientation.Responsiveness = 22
	orientation.CFrame = root.CFrame.Rotation
	orientation.Parent = root
	state.orientation = orientation

	if useVelocity then
		local velocity = own(Instance.new("LinearVelocity"))
		velocity.Attachment0 = attachment
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VelocityConstraintMode =
			Enum.VelocityConstraintMode.Vector
		velocity.ForceLimitsEnabled = false
		velocity.VectorVelocity = Vector3.zero
		velocity.Parent = root
		state.velocity = velocity
	end
end

stopMode = function()
	local old = state
	if old.mode == "Idle" then return end

	-- Preserve the pendulum's velocity on release, then add a modest
	-- tangent-directed launch so the player carries speed into freefall.
	if old.mode == "Swing" and root and root.Parent and humanoid and humanoid.Health > 0 then
		local velocity = root.AssemblyLinearVelocity
		local tangent = velocity
		if old.anchors and old.anchors[1] and old.anchors[1].Parent then
			local radial = unitOr(old.anchors[1].WorldPosition - root.Position, Vector3.yAxis)
			tangent = project(velocity, radial)
		end
		local cameraForward = unitOr(
			project(cameraDirection(), Vector3.yAxis),
			unitOr(project(root.CFrame.LookVector, Vector3.yAxis), Vector3.new(0, 0, -1))
		)
		local horizontalVelocity = project(velocity, Vector3.yAxis)
		local arcForward = unitOr(project(tangent, Vector3.yAxis), cameraForward)

		-- At the top of an arc, tangent speed can be tiny. Blend toward the
		-- direction the player is looking so release still carries forward.
		local launchDirection = arcForward
		if horizontalVelocity.Magnitude < 18 or arcForward:Dot(cameraForward) < 0.15 then
			launchDirection = unitOr(arcForward * 0.35 + cameraForward * 0.9, cameraForward)
		end
		-- Keep the existing velocity and add a clear forward impulse even at
		-- the top of the arc, where horizontal speed naturally drops.
		local carryBoost = math.clamp(horizontalVelocity.Magnitude * 0.30, 34, 68)
		carryBoost += 28
		local launchVelocity = velocity + launchDirection * carryBoost
		-- Ensure a useful horizontal carry without deleting vertical velocity.
		local horizontalLaunch = Vector3.new(launchVelocity.X, 0, launchVelocity.Z)
		if horizontalLaunch.Magnitude < 52 then
			horizontalLaunch = launchDirection * 52
		end
		root.AssemblyLinearVelocity = Vector3.new(
			horizontalLaunch.X,
			launchVelocity.Y,
			horizontalLaunch.Z
		)

		-- Give the player a temporary sprint after a swing release.
		if humanoid then
			if boostedWalkSpeed == nil then boostedWalkSpeed = humanoid.WalkSpeed end
			humanoid.WalkSpeed = 35
			boostedWalkSpeedUntil = os.clock() + 5
		end
		playSound(1284846268, 0.9, 1.12)

		-- Preserve the original hip/knee joints so the Spider-Man tuck/kick
		-- continues during the first part of the airborne release.
		if old.pose and old.pose.legs then
			airborneLegPose = old.pose.legs
			airborneKickStarted = os.clock()
			airborneKickUntil = airborneKickStarted + 1.65
		end
	end

	if old.animationTrack then
		pcall(function() old.animationTrack:Stop(0.18) end)
		pcall(function() old.animationTrack:Destroy() end)
	end

	state = {
		mode = "Idle",
		objects = {},
	}

	if old.pose then
		for _, entry in pairs(old.pose.shoulders) do
			if entry.motor.Parent then
				entry.motor.Transform = entry.transform
			end
		end
		for _, entry in pairs(old.pose.legs or {}) do
			if entry.motor.Parent then
				entry.motor.Transform = entry.transform
			end
		end
	end

	for index = #old.objects, 1, -1 do
		old.objects[index]:Destroy()
	end

	if old.saved and old.saved.humanoid.Parent then
		local hum = old.saved.humanoid
		hum.AutoRotate = old.saved.autoRotate
		hum.PlatformStand = old.saved.platformStand

		if hum.Health > 0 and not hum.PlatformStand then
			hum:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end

	crawlPanel.Visible = false
	leapButton.Visible = false
	ropePanel.Visible = false

	table.clear(crawlTouches)
	table.clear(ropeTouches)

	if old.mode == "Swing"
		or old.mode == "Pull"
		or old.mode == "Climb"
		or old.mode == "Sling" then
		cooldown(old.mode)
	end
end

local function beginMode(mode, useVelocity)
	if not alive() then return false end

	stopMode()

	state.mode = mode
	state.started = os.clock()
	state.saved = {
		humanoid = humanoid,
		autoRotate = humanoid.AutoRotate,
		platformStand = humanoid.PlatformStand,
	}

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	makePhysics(useVelocity)

	return true
end

local function faceDirection(direction, preferredUp)
	local forward = unitOr(direction, root.CFrame.LookVector)
	local up = preferredUp or Vector3.yAxis

	if math.abs(forward:Dot(up)) > 0.96 then
		up = root.CFrame.RightVector
	end

	if math.abs(forward:Dot(up)) > 0.96 then
		up = Vector3.zAxis
	end

	if math.abs(forward:Dot(up)) > 0.96 then
		up = Vector3.xAxis
	end

	state.orientation.CFrame = CFrame.lookAt(
		Vector3.zero,
		forward,
		up
	)
end

local function freeSwingPosition()
	local look = cameraDirection()
	local fallback = unitOr(
		project(root.CFrame.LookVector, Vector3.yAxis),
		Vector3.new(0, 0, -1)
	)

	local forward = unitOr(
		project(look, Vector3.yAxis),
		fallback
	)

	return root.Position
		+ forward * CONFIG.SwingForward
		+ Vector3.yAxis * (
			CONFIG.SwingHeight + math.max(look.Y, 0) * 28
		)
end

local function freeAimPosition(distance)
	return root.Position
		+ Vector3.yAxis * 1.5
		+ unitOr(cameraDirection(), root.CFrame.LookVector) * distance
end

startSwing = function()
	if not alive() or not ready("Swing") then return end
	if state.mode == "Swing" then return end

	local position = freeSwingPosition()

	if not beginMode("Swing", false) then return end
	local activeSide = swingStep == 1 and "Right" or "Left"
	attachWebs(position, nil, {[activeSide] = true})
	swingStep = swingStep == 1 and 2 or 1

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local swingAnimation = Instance.new("Animation")
	swingAnimation.AnimationId = SWING_ANIM_ID
	local swingTrack = animator:LoadAnimation(swingAnimation)
	swingTrack.Priority = Enum.AnimationPriority.Action4
	swingTrack.Looped = true
	state.animationTrack = swingTrack
	swingTrack:Play(0.08)
	Debris:AddItem(swingAnimation, 2)

	local rope = own(Instance.new("RopeConstraint"))
	rope.Attachment0 = state.motionAttachment
	rope.Attachment1 = state.anchors[1]
	local anchorDistance = (position - root.Position).Magnitude
	-- Slightly tauten the line at launch so ground shots pull the player into motion.
	local launchTension = humanoid.FloorMaterial == Enum.Material.Air and 0 or 4
	rope.Length = math.clamp(
		anchorDistance - launchTension,
		CONFIG.RopeMinLength,
		CONFIG.RopeMaxLength
	)
	rope.Visible = false
	rope.Restitution = 0
	rope.Parent = root
	state.rope = rope

	local force = own(Instance.new("VectorForce"))
	force.Attachment0 = state.motionAttachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.ApplyAtCenterOfMass = true
	force.Force = Vector3.zero
	force.Parent = root
	state.force = force

	local radial = unitOr(position - root.Position, Vector3.yAxis)
	local forward = unitOr(
		project(cameraDirection(), radial),
		unitOr(project(root.CFrame.LookVector, radial), Vector3.zero)
	)

	root.AssemblyLinearVelocity += forward * CONFIG.SwingBoost
	playSound(1284846268, 0.85, 1.05)

	ropePanel.Visible = true
end

startZip = function()
	if not alive() or not ready("Zip") then return end

	local position = freeAimPosition(CONFIG.ZipDistance)

	if not beginMode("Zip", true) then return end

	attachWebs(position, position, {Left = true, Right = true})
	state.deadline = os.clock() + CONFIG.ZipDuration
	playSound(9084017080, 1.0, 1.08)
	cooldown("Zip")
end

startPull = function()
	if not alive() or not ready("Pull") then return end
	if state.mode == "Pull" then return end

	local position = freeAimPosition(CONFIG.PullDistance)

	if not beginMode("Pull", true) then return end

	attachWebs(position)
	state.deadline = os.clock() + CONFIG.PullDuration
	playSound(1284846268, 1, 0.95)
end

slingAction = function()
	if not alive() then return end

	if state.mode == "Sling" then
		if not validAnchors() then
			stopMode()
			return
		end

		local charge = math.clamp(
			(os.clock() - state.started) / CONFIG.SlingChargeTime,
			0,
			1
		)

		local middle = (
			state.anchors[1].WorldPosition
				+ state.anchors[2].WorldPosition
		) * 0.5

		local direction = unitOr(
			middle - root.Position,
			cameraDirection()
		)

		local speed = CONFIG.SlingMinSpeed
			+ (CONFIG.SlingMaxSpeed - CONFIG.SlingMinSpeed) * charge

		stopMode()

		root.AssemblyLinearVelocity =
			direction * speed
			+ Vector3.yAxis * CONFIG.SlingLift

		playSound(9084017080, 1.1, 1.1)
		return
	end

	if not ready("Sling") then
		tell("Slingshot is recharging")
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then return end

	local middle = root.Position
		+ Vector3.yAxis * 13
		+ camera.CFrame.LookVector * CONFIG.SlingDistance

	local first = middle - camera.CFrame.RightVector * 18
	local second = middle + camera.CFrame.RightVector * 18

	if not beginMode("Sling", true) then return end

	attachWebs(first, second)
	state.holdPosition = root.Position
	root.AssemblyLinearVelocity = Vector3.zero
	state.velocity.VectorVelocity = Vector3.zero

	playSound(1284846268, 1, 0.85)
end

-- Only surface crawling uses raycasts.
local function surfaceRay(origin, direction)
	if not character then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	params.IgnoreWater = true
	params.RespectCanCollide = true

	return Workspace:Raycast(origin, direction, params)
end

local function surfaceBasis(normal, preferred)
	-- Prefer world-up on vertical walls so W always climbs and S descends.
	-- Near ceilings/floors, carry the prior up axis projected onto the new
	-- surface so the basis rotates continuously through corners.
	local up
	if math.abs(normal:Dot(Vector3.yAxis)) < 0.72 then
		up = project(Vector3.yAxis, normal)
	else
		up = project(preferred or Vector3.yAxis, normal)
	end
	if up.Magnitude < 0.1 then up = project(Vector3.zAxis, normal) end
	if up.Magnitude < 0.1 then up = project(Vector3.xAxis, normal) end
	up = up.Unit

	-- Avoid sudden 180-degree flips when the surface normal changes.
	if preferred and project(preferred, normal).Magnitude > 0.1
		and up:Dot(project(preferred, normal).Unit) < -0.15 then
		up = -up
	end
	local right = unitOr(up:Cross(normal), Vector3.xAxis)
	return up, right
end

local function initialSurface()
	local directions = {
		cameraDirection(),
		root.CFrame.LookVector,
		root.CFrame.UpVector,
		-root.CFrame.UpVector,
		root.CFrame.RightVector,
		-root.CFrame.RightVector,
		-root.CFrame.LookVector,
	}

	for _, direction in ipairs(directions) do
		local hit = surfaceRay(
			root.Position,
			direction * CONFIG.ClimbReach
		)
		if hit then return hit end
	end

	return nil
end

toggleClimb = function()
	if state.mode == "Climb" then
		stopMode()
		return
	end

	if not alive() or not ready("Climb") then return end

	local hit = initialSurface()
	if not hit then
		tell("Move closer to a wall, floor, or ceiling to crawl")
		return
	end

	if not beginMode("Climb", true) then return end
	-- Keep the Humanoid animator active so the crawl animation can play.
	humanoid.PlatformStand = false

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local climbAnimation = Instance.new("Animation")
	climbAnimation.AnimationId = CLIMB_ANIM_ID
	local climbTrack = animator:LoadAnimation(climbAnimation)
	climbTrack.Priority = Enum.AnimationPriority.Action4
	climbTrack.Looped = true
	state.animationTrack = climbTrack
	climbTrack:Play(0.08)
	Debris:AddItem(climbAnimation, 2)

	state.normal = hit.Normal
	state.surfaceUp = surfaceBasis(hit.Normal, root.CFrame.UpVector)
	state.bodyUp = state.surfaceUp
	state.lastSurface = os.clock()

	crawlPanel.Visible = true
	leapButton.Visible = true
end

local function crawlInput()
	local x, y = 0, 0

	if keys[Enum.KeyCode.A] then x -= 1 end
	if keys[Enum.KeyCode.D] then x += 1 end
	if keys[Enum.KeyCode.W] then y += 1 end
	if keys[Enum.KeyCode.S] then y -= 1 end

	local directions = {}
	for _, direction in pairs(crawlTouches) do
		directions[direction] = true
	end

	if directions.Left then x -= 1 end
	if directions.Right then x += 1 end
	if directions.Up then y += 1 end
	if directions.Down then y -= 1 end

	local input = Vector2.new(x, y)
	return input.Magnitude > 1 and input.Unit or input
end

local function crawlMovementVector(input, normal, fallbackUp)
	-- W/S follows the surface's own up/down axis, so climbing a wall naturally
	-- carries onto the roof without needing to aim the camera at the ceiling.
	local forward, right = surfaceBasis(normal, fallbackUp)
	local movement = right * input.X + forward * input.Y
	return movement.Magnitude > 1 and movement.Unit or movement
end

local function findClimbSurface(movement)
	local normal = state.normal
	local origin = root.Position

	if movement.Magnitude > 0.1 then
		local ahead = surfaceRay(
			origin,
			movement.Unit * (CONFIG.SurfaceOffset + 1)
		)

		if ahead and ahead.Normal:Dot(normal) < 0.92 then
			return ahead
		end
	end

	local current = surfaceRay(origin, -normal * CONFIG.ClimbReach)
	if current then return current end

	local up, right = surfaceBasis(normal, state.surfaceUp or root.CFrame.UpVector)
	local probes = {up, -up, right, -right}
	if movement.Magnitude > 0.1 then
		table.insert(probes, 1, movement.Unit)
	end

	-- Probe forward and around the character. This finds a roof at the top of
	-- a wall and lets the normal rotate smoothly instead of dropping crawl mode.
	for _, direction in ipairs(probes) do
		local aheadOrigin = origin + direction * 1.6 - normal * 0.3
		local hit = surfaceRay(aheadOrigin, -normal * (CONFIG.ClimbReach + 2))
		if hit then return hit end

		local sweep = surfaceRay(
			origin + direction * 1.7,
			-direction * 3.2
		)
		if sweep and sweep.Normal:Dot(normal) < 0.97 then
			return sweep
		end
	end

	-- Extra upward/forward check for wall-to-ceiling transitions.
	local ceiling = surfaceRay(
			origin + up * 1.8,
			up * 4.5 - normal * 1.5
		)
	if ceiling then return ceiling end
	return nil
end

leapOff = function()
	if not alive() then return end

	if state.mode == "Climb" then
		local normal = state.normal
		local travel = state.bodyUp

		stopMode()

		root.AssemblyLinearVelocity =
			normal * 36
			+ travel * 22
			+ Vector3.yAxis * 22
	elseif state.mode ~= "Idle" then
		stopMode()
	end
end

local function updateSwing(dt)
	local target = state.anchors[1].WorldPosition
	local radial = unitOr(target - root.Position, Vector3.yAxis)
	local velocity = root.AssemblyLinearVelocity

	local steering = project(humanoid.MoveDirection, radial)
	local cameraTangent = project(cameraDirection(), radial)
	local travelTangent = project(velocity, radial)
	-- Keyboard steering has priority when a direction is pressed; camera aim
	-- provides a gentle forward bias only when the player isn't steering.
	if steering.Magnitude > 0.05 then
		steering = steering.Unit
	else
		steering = unitOr(cameraTangent, Vector3.zero) * 0.35
	end

	local assistDirection
	if travelTangent.Magnitude > 8 then
		assistDirection = travelTangent.Unit
	else
		assistDirection = unitOr(
			cameraTangent,
			unitOr(project(root.CFrame.LookVector, radial), Vector3.zero)
		)
	end

	local acceleration =
		steering * CONFIG.SwingAcceleration
		+ assistDirection * CONFIG.SwingAssist

	if velocity.Magnitude < 32 then
		-- Stronger startup assist so the rope can build a real pendulum arc.
		local startup = unitOr(cameraTangent, assistDirection)
		acceleration += startup * (32 - velocity.Magnitude) * 0.9
	end

	state.force.Force = acceleration * root.AssemblyMass

	if velocity.Magnitude > CONFIG.SwingMaxSpeed then
		local excess = velocity.Magnitude - CONFIG.SwingMaxSpeed
		state.force.Force -=
			velocity.Unit * excess * root.AssemblyMass * 5
	end

	local reelDirection = 0

	if keys[Enum.KeyCode.Space] then
		reelDirection -= 1
	end
	if keys[Enum.KeyCode.LeftShift]
		or keys[Enum.KeyCode.RightShift] then
		reelDirection += 1
	end

	for _, direction in pairs(ropeTouches) do
		reelDirection += direction
	end

	state.rope.Length = math.clamp(
		state.rope.Length
			+ math.clamp(reelDirection, -1, 1)
			* CONFIG.RopeReelSpeed
			* dt,
		CONFIG.RopeMinLength,
		CONFIG.RopeMaxLength
	)

	-- Let the character turn toward the direction being pressed immediately,
	-- even while the pendulum's velocity is still carrying another way.
	local facing = project(humanoid.MoveDirection, radial)
	if facing.Magnitude < 0.08 then
		facing = cameraTangent
	end
	if facing.Magnitude < 0.08 then
		facing = travelTangent
	end

	faceDirection(facing, radial)
end

local function updateTravel()
	local delta = state.anchors[1].WorldPosition - root.Position
	local distance = delta.Magnitude
	local isZip = state.mode == "Zip"
	local stopDistance = 5

	if distance <= stopDistance or os.clock() >= state.deadline then
		if not isZip or distance <= stopDistance then
			root.AssemblyLinearVelocity *= 0.25
		end
		stopMode()
		return
	end

	local direction = delta / distance
	local maxSpeed = isZip and CONFIG.ZipSpeed or CONFIG.PullSpeed
	local speed = math.min(
		maxSpeed,
		math.max(12, (distance - stopDistance) * 7)
	)

	state.velocity.VectorVelocity = direction * speed
	faceDirection(direction)
end

local function updateClimb(dt)
	local input = crawlInput()
	local movement = crawlMovementVector(input, state.normal, state.surfaceUp)
	local hit = findClimbSurface(movement)

	if not hit then
		state.velocity.VectorVelocity = Vector3.zero

		if os.clock() - state.lastSurface > CONFIG.SurfaceGraceTime then
			stopMode()
		end
		return
	end

	state.lastSurface = os.clock()
	state.normal = hit.Normal
	state.surfaceUp = surfaceBasis(hit.Normal, state.surfaceUp)
	movement = crawlMovementVector(input, hit.Normal, state.surfaceUp)

	local sprinting = keys[Enum.KeyCode.LeftShift]
		or keys[Enum.KeyCode.RightShift]

	local speed = sprinting
		and CONFIG.ClimbSprintSpeed
		or CONFIG.ClimbSpeed

	local gap = (root.Position - hit.Position):Dot(hit.Normal)
	local correction = math.clamp(
		(CONFIG.SurfaceOffset - gap) * 8,
		-CONFIG.SurfaceStickSpeed,
		CONFIG.SurfaceStickSpeed
	)

	local surfaceVelocity = Vector3.zero
	if hit.Instance:IsA("BasePart") then
		surfaceVelocity = hit.Instance:GetVelocityAtPosition(hit.Position)
	end

	state.velocity.VectorVelocity =
		movement * speed
		+ hit.Normal * correction
		+ surfaceVelocity

	-- The head follows travel direction, including head-first descent.
	if movement.Magnitude > 0.05 then
		local desiredUp = movement.Unit
		local currentUp = unitOr(
			project(state.bodyUp, hit.Normal),
			up
		)

		local angle = math.atan2(
			hit.Normal:Dot(currentUp:Cross(desiredUp)),
			math.clamp(currentUp:Dot(desiredUp), -1, 1)
		)

		if math.abs(angle) > math.pi - 0.001 then
			angle = math.pi
		end

		state.bodyUp = CFrame.fromAxisAngle(
			hit.Normal,
			angle * math.min(dt * 10, 1)
		):VectorToWorldSpace(currentUp)
	else
		state.bodyUp = unitOr(
			project(state.bodyUp, hit.Normal),
			up
		)
	end

	faceDirection(-hit.Normal, state.bodyUp)
end

local function updateSling()
	local correction = (state.holdPosition - root.Position) * 12

	if correction.Magnitude > 35 then
		correction = correction.Unit * 35
	end

	state.velocity.VectorVelocity = correction

	local middle = (
		state.anchors[1].WorldPosition
			+ state.anchors[2].WorldPosition
	) * 0.5

	faceDirection(middle - root.Position)
end

local function performAction(action)
	if action == "Swing" then
		startSwing()
	elseif action == "Zip" then
		startZip()
	elseif action == "Pull" then
		startPull()
	elseif action == "Climb" then
		toggleClimb()
	elseif action == "Sling" then
		slingAction()
	end
end

local function actionStillHeld(action)
	for _, held in pairs(actionHolds) do
		if held == action then return true end
	end
	return false
end

local function releaseAction(action)
	if actionStillHeld(action) then return end

	if (action == "Swing" and state.mode == "Swing")
		or (action == "Pull" and state.mode == "Pull") then
		stopMode()
	end
end

for action, entry in pairs(buttons) do
	if action == "Swing" or action == "Pull" then
		connect(entry.button.InputBegan, function(input)
			if not isPointer(input) then return end
			actionHolds[input] = action
			performAction(action)
		end)
	else
		connect(entry.button.Activated, function()
			performAction(action)
		end)
	end
end

local function bindCrawlButton(button, direction)
	connect(button.InputBegan, function(input)
		if isPointer(input) and state.mode == "Climb" then
			crawlTouches[input] = direction
		end
	end)
end

bindCrawlButton(upButton, "Up")
bindCrawlButton(downButton, "Down")
bindCrawlButton(leftButton, "Left")
bindCrawlButton(rightButton, "Right")

local function bindRopeButton(button, direction)
	connect(button.InputBegan, function(input)
		if isPointer(input) and state.mode == "Swing" then
			ropeTouches[input] = direction
		end
	end)
end

bindRopeButton(reelButton, -1)
bindRopeButton(extendButton, 1)
connect(leapButton.Activated, leapOff)

local keyActions = {
	[Enum.KeyCode.Q] = "Swing",
	[Enum.KeyCode.E] = "Zip",
	[Enum.KeyCode.R] = "Pull",
	[Enum.KeyCode.C] = "Climb",
	[Enum.KeyCode.F] = "Sling",
}

connect(UserInputService.InputBegan, function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	keys[input.KeyCode] = true

	local action = keyActions[input.KeyCode]
	if action then
		if action == "Swing" or action == "Pull" then
			actionHolds[input.KeyCode] = action
		end
		performAction(action)
	elseif input.KeyCode == Enum.KeyCode.X then
		stopMode()
	end
end)

connect(UserInputService.InputEnded, function(input)
	keys[input.KeyCode] = nil

	local pointerAction = actionHolds[input]
	actionHolds[input] = nil
	if pointerAction then
		releaseAction(pointerAction)
	end

	local keyboardAction = actionHolds[input.KeyCode]
	actionHolds[input.KeyCode] = nil
	if keyboardAction then
		releaseAction(keyboardAction)
	end

	crawlTouches[input] = nil
	ropeTouches[input] = nil
end)

connect(UserInputService.JumpRequest, function()
	if UserInputService:GetFocusedTextBox() then return end

	-- Swing release is controlled by Q / the Swing button.
	if state.mode ~= "Swing" then
		leapOff()
	end
end)

local function clearInputs()
	table.clear(keys)
	table.clear(actionHolds)
	table.clear(crawlTouches)
	table.clear(ropeTouches)
end

connect(UserInputService.WindowFocusReleased, function()
	clearInputs()
	stopMode()
end)

connect(UserInputService.TextBoxFocused, function()
	clearInputs()
	stopMode()
end)

connect(RunService.PreSimulation, function()
	if not alive() then return end

	local activePose = state.pose
	if activePose then
		-- Apply the R6 arm pose after Animator has written its transforms.
		for side, entry in pairs(activePose.shoulders) do
			if entry.motor.Parent then
				local spread = side == "Left" and -10 or 10
				entry.motor.Transform = entry.transform * CFrame.Angles(
					math.rad(165),
					0,
					math.rad(spread)
				)
			end
		end
	end

	-- During a swing, use the current pose; after release, keep the captured
	-- leg joints and continue a shorter kick/tuck while airborne.
	local legPose = activePose and activePose.legs or nil
	local airborne = false
	if state.mode == "Swing" or state.mode == "Zip" or state.mode == "Pull" or state.mode == "Sling" then
		legPose = activePose and activePose.legs or legPose
	elseif airborneLegPose and os.clock() < airborneKickUntil
		and humanoid.FloorMaterial == Enum.Material.Air then
		legPose = airborneLegPose
		airborne = true
	else
		if airborneLegPose then
			for _, entry in pairs(airborneLegPose) do
				if entry.motor.Parent then entry.motor.Transform = entry.transform end
			end
		end
		airborneLegPose = nil
		airborneKickUntil = 0
	end

	if not legPose then return end
	local t
	if airborne then
		t = os.clock() - airborneKickStarted
	else
		t = os.clock() - (state.started or os.clock())
	end
	local mode = airborne and "Airborne" or state.mode
	local leftHip = legPose["Left Hip"] or legPose.LeftHip
	local rightHip = legPose["Right Hip"] or legPose.RightHip
	local leftKnee = legPose.LeftKnee
	local rightKnee = legPose.RightKnee

	local leftX, rightX, leftKneeX, rightKneeX = 0, 0, 0, 0
	local leftRoll, rightRoll = 0, 0
	if mode == "Swing" then
		-- Alternating forward kick / tuck, like the reference's acrobatic swing.
		local phase = t * 9.2
		leftX = -0.82 + math.sin(phase) * 0.95
		rightX = -0.82 + math.sin(phase + math.pi * 0.72) * 0.95
		leftKneeX = 0.35 + math.max(0, math.sin(phase + 0.4)) * 1.12
		rightKneeX = 0.35 + math.max(0, math.sin(phase + math.pi * 0.72 + 0.4)) * 1.12
		leftRoll = math.sin(phase) * 0.12
		rightRoll = math.sin(phase + math.pi) * 0.12
	elseif mode == "Airborne" then
		-- Hold a visible tucked aerial pose, then smoothly relax before landing.
		local fade = math.clamp((airborneKickUntil - os.clock()) / 1.65, 0, 1)
		local phase = t * 6.5
		leftX = (-0.95 + math.sin(phase) * 0.35) * fade
		rightX = (-0.95 + math.sin(phase + 0.65) * 0.35) * fade
		leftKneeX = (1.05 + math.max(0, math.sin(phase + 0.3)) * 0.55) * fade
		rightKneeX = (1.05 + math.max(0, math.sin(phase + 0.95)) * 0.55) * fade
		leftRoll = math.sin(phase) * 0.10 * fade
		rightRoll = math.sin(phase + 0.65) * 0.10 * fade
	elseif mode == "Zip" or mode == "Pull" or mode == "Sling" then
		local phase = t * (mode == "Sling" and 7 or 12)
		leftX = -0.48 + math.sin(phase) * 0.62
		rightX = -0.48 + math.sin(phase + math.pi) * 0.62
		leftKneeX = 0.55 + math.max(0, math.sin(phase + 0.5)) * 0.90
		rightKneeX = 0.55 + math.max(0, math.sin(phase + math.pi + 0.5)) * 0.90
	end

	local function applyLeg(entry, x, knee, roll)
		if not entry or not entry.motor.Parent then return end
		local jointName = string.lower(entry.motor.Name)
		local isKnee = string.find(jointName, "knee") ~= nil
		local base = entry.transform
		if isKnee then
			entry.motor.Transform = base * CFrame.Angles(knee, 0, 0)
		else
			entry.motor.Transform = base * CFrame.Angles(x, 0, roll or 0)
		end
	end

	applyLeg(leftHip, leftX, leftKneeX, leftRoll)
	applyLeg(rightHip, rightX, rightKneeX, rightRoll)
	applyLeg(leftKnee, leftX, leftKneeX, leftRoll)
	applyLeg(rightKnee, rightX, rightKneeX, rightRoll)
end)

connect(RunService.Heartbeat, function(dt)
	if not alive() then
		stopMode()
		return
	end

	-- The post-swing sprint ends after five seconds or immediately on landing.
	if boostedWalkSpeed ~= nil and humanoid then
		if humanoid.FloorMaterial ~= Enum.Material.Air or os.clock() >= boostedWalkSpeedUntil then
			humanoid.WalkSpeed = boostedWalkSpeed
			boostedWalkSpeed = nil
			boostedWalkSpeedUntil = 0
		end
	end

	if state.mode == "Idle" then return end

	if state.anchors and not validAnchors() then
		stopMode()
		return
	end

	if state.mode == "Swing" then
		updateSwing(dt)
	elseif state.mode == "Zip" or state.mode == "Pull" then
		updateTravel()
	elseif state.mode == "Climb" then
		updateClimb(dt)
	elseif state.mode == "Sling" then
		updateSling()
	end

	updateHandPose()
end)

connect(RunService.RenderStepped, function()
	local now = os.clock()
	local camera = Workspace.CurrentCamera

	if camera then
		local viewport = camera.ViewportSize
		local scale = math.clamp(
			math.min(viewport.Y / 720, viewport.X / 420),
			0.6,
			1
		)

		actionScale.Scale = scale
		crawlScale.Scale = scale
		ropeScale.Scale = scale
	end

	for action, entry in pairs(buttons) do
		local remaining = math.max(
			0,
			(cooldowns[action] or 0) - now
		)

		local active = state.mode == action

		entry.button.BackgroundColor3 = active
			and COLORS.Active
			or remaining > 0 and COLORS.Dark
			or entry.color

		if action == "Sling" and state.mode == "Sling" then
			local charge = math.clamp(
				(now - state.started) / CONFIG.SlingChargeTime,
				0,
				1
			)

			entry.button.Text = string.format(
				"FIRE\n%d%%",
				math.floor(charge * 100)
			)
		elseif remaining > 0 and not active then
			entry.button.Text = string.format(
				"%s\n%.1f",
				action:upper(),
				remaining
			)
		else
			entry.button.Text = entry.text
		end
	end

	if now < noticeUntil then
		status.Text = notice
	elseif state.mode == "Swing" then
		status.Text = "FREE SWING • Release to launch • Adjust rope below"
	elseif state.mode == "Climb" then
		status.Text = "CRAWL • WASD / arrows • SPACE to leap"
	elseif state.mode == "Sling" then
		status.Text = "CHARGING • Tap SLING / F again to launch"
	elseif state.mode == "Pull" then
		status.Text = "AIR WEB PULL • Release to detach"
	elseif state.mode == "Zip" then
		status.Text = "AIR WEB ZIP"
	else
		status.Text = "PROJECT SPIDER V9 • ACROBATIC SWING + WEB FX"
	end
end)

local function bindCharacter(newCharacter)
	characterGeneration += 1
	local generation = characterGeneration

	stopMode()
	clearInputs()
	table.clear(cooldowns)

	if deathConnection then
		deathConnection:Disconnect()
		deathConnection = nil
	end

	character, humanoid, root = nil, nil, nil

	local newHumanoid = newCharacter:WaitForChild("Humanoid", 10)
	local newRoot = newCharacter:WaitForChild("HumanoidRootPart", 10)

	if not running
		or generation ~= characterGeneration
		or player.Character ~= newCharacter
		or not newHumanoid
		or not newRoot then
		return
	end

	character = newCharacter
	humanoid = newHumanoid
	root = newRoot

	deathConnection = humanoid.Died:Connect(function()
		stopMode()
		clearInputs()
	end)
end

connect(player.CharacterAdded, bindCharacter)

connect(player.CharacterRemoving, function(removingCharacter)
	if removingCharacter == character then
		characterGeneration += 1
		stopMode()
		clearInputs()
		character, humanoid, root = nil, nil, nil
	end
end)

local function cleanup()
	if not running then return end

	running = false
	characterGeneration += 1

	stopMode()
	clearInputs()

	if deathConnection then
		deathConnection:Disconnect()
		deathConnection = nil
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

connect(shutdown.Event, function()
	cleanup()
	gui:Destroy()
end)

connect(gui.Destroying, cleanup)
connect(script.Destroying, function()
	cleanup()
	gui:Destroy()
end)

if player.Character then
	task.spawn(bindCharacter, player.Character)
end