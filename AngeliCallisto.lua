local Callisto = (function()
--!strict
--[[
	Callisto — single-file UI library
	Rebuilt from the original instance dump. Visuals are byte-for-byte the same
	properties; everything else is structure, animation and theming.

	Animation rules honoured throughout:
	  - NO element ever changes size for aesthetic purposes. All feedback is
	    transparency, colour, position or rotation.
	  - NO CanvasGroups anywhere: they flatten UIGradients over child text and
	    have too many rendering caveats. Windows and popups fade through the
	    Fader, which cascades transparency tweens over every descendant.
	  - The slider fill DOES resize, instantly and untweened — that is the
	    value display, not an animation.

	local Window = Callisto:CreateWindow({ Title = "Callisto", Size = Vector2.new(591, 480) })
	local Page   = Window:AddPage("General")
	local Left   = Page:AddSection("Left", "Section #1")

	Left:AddToggle({ Title = "Toggle", Default = false, Callback = print })
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

--=============================================================================
-- Shorthands (kept from the original source)
--=============================================================================

local CSK = ColorSequenceKeypoint.new
local NSK = NumberSequenceKeypoint.new
local BSP = Enum.BorderStrokePosition
local ASM = Enum.ApplyStrokeMode
local UFA = Enum.UIFlexAlignment
local TXA = Enum.TextXAlignment
local UIT = Enum.UserInputType
local ETT = Enum.TextTruncate
local UFO = UDim2.fromOffset
local UFS = UDim2.fromScale
local EGS = Enum.GuiState
local EKC = Enum.KeyCode
local TIS = table.insert
local TR = table.remove
local TF = table.find
local MC = math.clamp
local MR = math.round
local MF = math.floor
local ED = Enum.EasingDirection
local FD = Enum.FillDirection
local ES = Enum.EasingStyle
local FW = Enum.FontWeight
local SO = Enum.SortOrder
local FS = Enum.FontStyle
local TI = TweenInfo.new
local V2 = Vector2.new
local UD2 = UDim2.new
local UD = UDim.new
local FN = Font.new
local RGB = Color3.fromRGB
local HSV = Color3.fromHSV
local CS = ColorSequence.new
local NS = NumberSequence.new
local SCL = Enum.ScaleType
local ZIB = Enum.ZIndexBehavior
local AT = Enum.AutomaticSize
local HFA = Enum.HorizontalAlignment
local VFA = Enum.VerticalAlignment
local RSM = Enum.ResamplerMode

local FONT_ID = "rbxassetid://12187365364"

--=============================================================================
-- Library root
--=============================================================================

local Callisto = {}
Callisto.__index = Callisto

Callisto.Version = "1.0.0"
Callisto.Flags = {} :: { [string]: any }
Callisto.Windows = {} :: { any }
Callisto.Connections = {} :: { RBXScriptConnection }

--=============================================================================
-- Theme
--=============================================================================

-- Every colour the original file used, named. Derived accent/foreground shades
-- default to the exact literals from the dump so nothing shifts visually.
local DefaultTheme = {
	Background = RGB(24, 26, 27),
	Foreground = RGB(31, 34, 35),
	ForegroundLight = RGB(38, 41, 42),
	Border = RGB(45, 48, 49),
	Accent = RGB(0, 120, 255),
	AccentLight = RGB(77, 163, 255),
	AccentDark = RGB(0, 86, 178),
	Text = RGB(255, 255, 255),
}

Callisto.Theme = table.clone(DefaultTheme)

-- instance -> { property = themeKey }
local ColorRegistry: { [Instance]: { [string]: string } } = {}
-- gradient -> { {time, themeKey}, ... }
local GradientRegistry: { [UIGradient]: { { any } } } = {}
-- the running theme transition, if any
local ThemeTransition: RBXScriptConnection? = nil

local function Bind(instance: Instance, map: { [string]: string })
	ColorRegistry[instance] = map
	for property, key in next, map do
		pcall(function()
			(instance :: any)[property] = Callisto.Theme[key]
		end)
	end
end

local function BindGradient(gradient: UIGradient, stops: { { any } })
	GradientRegistry[gradient] = stops
	local keypoints = {}
	for _, stop in next, stops do
		TIS(keypoints, CSK(stop[1], Callisto.Theme[stop[2]]))
	end
	gradient.Color = CS(keypoints)
end

-- Paints every registered property/gradient at `alpha` between the previous
-- theme snapshot and the current one. Gradients are rebuilt keypoint-by-
-- keypoint, which is the only way to animate UIGradient.Color at all.
local function PaintTheme(alpha: number, previous: { [string]: Color3 })
	for instance, map in next, ColorRegistry do
		if not instance.Parent then
			ColorRegistry[instance] = nil
			continue
		end
		for property, key in next, map do
			pcall(function()
				(instance :: any)[property] = previous[key]:Lerp(Callisto.Theme[key], alpha)
			end)
		end
	end

	for gradient, stops in next, GradientRegistry do
		if not gradient.Parent then
			GradientRegistry[gradient] = nil
			continue
		end
		local keypoints = {}
		for _, stop in next, stops do
			TIS(keypoints, CSK(stop[1], previous[stop[2]]:Lerp(Callisto.Theme[stop[2]], alpha)))
		end
		gradient.Color = CS(keypoints)
	end
end

--[[
	SetTheme({ Accent = Color3.fromRGB(255, 80, 120) })

	Only pass the keys you care about. AccentLight / AccentDark / ForegroundLight
	are re-derived automatically unless you pass them explicitly — the derivation
	(+/- 30% toward white/black) reproduces the original literals for the default
	accent, so the stock look is preserved exactly.

	The repaint animates over ~0.25s (gradients included); pass `false` as the
	second argument for an instant swap.
]]
function Callisto:SetTheme(theme: { [string]: Color3 }, animate: boolean?)
	local previous = table.clone(self.Theme)

	for key, color in next, theme do
		if self.Theme[key] ~= nil then
			self.Theme[key] = color
		end
	end

	if theme.Accent and not theme.AccentLight then
		self.Theme.AccentLight = theme.Accent:Lerp(RGB(255, 255, 255), 0.3)
	end
	if theme.Accent and not theme.AccentDark then
		self.Theme.AccentDark = theme.Accent:Lerp(RGB(0, 0, 0), 0.3)
	end
	if theme.Foreground and not theme.ForegroundLight then
		self.Theme.ForegroundLight = theme.Foreground:Lerp(RGB(255, 255, 255), 0.03)
	end

	if ThemeTransition then
		ThemeTransition:Disconnect()
		ThemeTransition = nil
	end

	if animate == false then
		PaintTheme(1, previous)
		return
	end

	local elapsed = 0
	ThemeTransition = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local progress = MC(elapsed / 0.25, 0, 1)
		PaintTheme(1 - (1 - progress) ^ 3, previous) -- cubic ease-out
		if progress >= 1 and ThemeTransition then
			ThemeTransition:Disconnect()
			ThemeTransition = nil
		end
	end)
end

function Callisto:ResetTheme(animate: boolean?)
	self:SetTheme(table.clone(DefaultTheme), animate)
end

--=============================================================================
-- Utilities
--=============================================================================

local function Add(class: string, properties: { [string]: any }?): any
	local success, instance = pcall(Instance.new, class)
	if not success then
		return nil
	end

	if properties then
		-- Parent is applied last so a half-configured instance is never rendered.
		local parent = properties.Parent
		for key, value in next, properties do
			if key == "Parent" then
				continue
			end
			local ok, err = pcall(function()
				(instance :: any)[key] = value
			end)
			if not ok then
				warn(err)
			end
		end
		if parent then
			(instance :: any).Parent = parent
		end
	end

	return instance
end

-- Animation constants. One place to retune the whole library's feel.
local Anim = {
	Fast = TI(0.12, ES.Quad, ED.Out),
	Base = TI(0.18, ES.Quad, ED.Out),
	Slow = TI(0.28, ES.Quart, ED.Out),
	Spring = TI(0.35, ES.Back, ED.Out),
}

local function Tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, info, goal)
	tween:Play()
	return tween
end

local function Connect(signal: RBXScriptSignal, callback)
	local connection = signal:Connect(callback)
	TIS(Callisto.Connections, connection)
	return connection
end

-- Fires callback(hovering: boolean).
local function Hover(button: GuiButton, callback: (boolean) -> ())
	Connect(button.MouseEnter, function()
		callback(true)
	end)
	Connect(button.MouseLeave, function()
		callback(false)
	end)
end

-- Standard press feedback: a short transparency dip. Never a size change.
local function Press(button: GuiButton)
	Connect(button.MouseButton1Down, function()
		Tween(button, Anim.Fast, { BackgroundTransparency = 0.15 })
	end)
	local function release()
		Tween(button, Anim.Base, { BackgroundTransparency = 0 })
	end
	Connect(button.MouseButton1Up, release)
	Connect(button.MouseLeave, release)
end

--=============================================================================
-- Fader — whole-tree fades without CanvasGroups
--
-- Fader.Out captures every descendant's rest transparency (only when the tree
-- is at rest, so interrupted animations never pollute the cache) and tweens
-- everything to fully transparent. Fader.In tweens everything back to the
-- captured values.
--=============================================================================

local Fader = {}

Fader.Properties = {
	Frame = { "BackgroundTransparency" },
	TextLabel = { "BackgroundTransparency", "TextTransparency" },
	TextButton = { "BackgroundTransparency", "TextTransparency" },
	TextBox = { "BackgroundTransparency", "TextTransparency" },
	ImageLabel = { "BackgroundTransparency", "ImageTransparency" },
	ImageButton = { "BackgroundTransparency", "ImageTransparency" },
	ScrollingFrame = { "BackgroundTransparency", "ScrollBarImageTransparency" },
	UIStroke = { "Transparency" },
	UIShadow = { "Transparency" },
}

-- root -> { instance -> { property -> restValue } }
Fader.Cache = {} :: { [Instance]: { [Instance]: { [string]: number } } }
-- root -> "shown" | "showing" | "hidden" (absent = shown, never faded)
Fader.State = {} :: { [Instance]: string }
-- root -> generation counter, so stale task.delay callbacks are ignored
Fader.Token = {} :: { [Instance]: number }

function Fader.Out(root: Instance, info: TweenInfo)
	local state = Fader.State[root]

	-- capture fresh rest values only when the tree is fully at rest; if we are
	-- interrupting a fade-in, the existing cache still holds the true values
	if state == nil or state == "shown" then
		local cache = {}
		local targets = root:GetDescendants()
		TIS(targets, root)
		for _, target in next, targets do
			local props = Fader.Properties[target.ClassName]
			if props then
				local values = {}
				for _, property in next, props do
					values[property] = (target :: any)[property]
				end
				cache[target] = values
			end
		end
		Fader.Cache[root] = cache
	end

	Fader.State[root] = "hidden"
	Fader.Token[root] = (Fader.Token[root] or 0) + 1

	-- zero-duration TweenService tweens apply a frame LATE, which breaks the
	-- park-transparent-then-fade-in pattern — instant fades set directly
	local instant = info.Time <= 0

	for target, values in next, Fader.Cache[root] do
		if target.Parent == nil and target ~= root then
			continue
		end
		if instant then
			for property in next, values do
				pcall(function()
					(target :: any)[property] = 1
				end)
			end
		else
			local goal = {}
			for property in next, values do
				goal[property] = 1
			end
			pcall(Tween, target, info, goal)
		end
	end
end

function Fader.In(root: Instance, info: TweenInfo)
	local cache = Fader.Cache[root]
	if not cache then
		return -- never faded out: already fully visible
	end

	local token = (Fader.Token[root] or 0) + 1
	Fader.Token[root] = token

	local instant = info.Time <= 0
	Fader.State[root] = instant and "shown" or "showing"

	for target, values in next, cache do
		if target.Parent == nil and target ~= root then
			continue
		end
		if instant then
			for property, value in next, values do
				pcall(function()
					(target :: any)[property] = value
				end)
			end
		else
			pcall(Tween, target, info, values)
		end
	end

	if not instant then
		task.delay(info.Time, function()
			if Fader.Token[root] == token and Fader.State[root] == "showing" then
				Fader.State[root] = "shown"
			end
		end)
	end
end

-- Drop every cached root that lives under `ancestor` (called before the
-- instances are destroyed, while ancestry is still intact).
function Fader.Forget(ancestor: Instance)
	for root in next, Fader.Cache do
		if root == ancestor or root:IsDescendantOf(ancestor) then
			Fader.Cache[root] = nil
			Fader.State[root] = nil
			Fader.Token[root] = nil
		end
	end
end

function Fader.Clear()
	table.clear(Fader.Cache)
	table.clear(Fader.State)
	table.clear(Fader.Token)
end

local function GetParentGui(): Instance
	-- gethui is an executor-injected global; reach it through the function
	-- environment so plain Luau tooling doesn't flag an unknown global
	local ok, hui = pcall(function()
		return ((getfenv() :: any).gethui)()
	end)
	if ok and hui then
		return hui
	end

	if RunService:IsStudio() then
		return LocalPlayer:WaitForChild("PlayerGui")
	end

	local success, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	return (success and core) or LocalPlayer:WaitForChild("PlayerGui")
end

-- Draggable: smooth, frame-rate independent follow. The lerp loop only runs
-- while dragging (and briefly afterwards, to settle), so it never fights the
-- position tweens the open/close animations play on the same target.
local function MakeDraggable(handle: GuiObject, target: GuiObject)
	local dragging, dragStart, startPosition = false, Vector3.zero, UD2()
	local goal = target.Position
	local settling = false

	Connect(handle.InputBegan, function(input)
		if input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.Touch then
			dragging = true
			settling = true
			dragStart = input.Position
			startPosition = target.Position
			goal = startPosition

			local connection
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					connection:Disconnect()
				end
			end)
		end
	end)

	Connect(UserInputService.InputChanged, function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= UIT.MouseMovement and input.UserInputType ~= UIT.Touch then
			return
		end
		local delta = input.Position - dragStart
		goal = UD2(
			startPosition.X.Scale,
			startPosition.X.Offset + delta.X,
			startPosition.Y.Scale,
			startPosition.Y.Offset + delta.Y
		)
	end)

	Connect(RunService.RenderStepped, function(dt)
		if not settling then
			return
		end

		local position = target.Position
		local settled = not dragging
			and math.abs(goal.X.Offset - position.X.Offset) < 0.5
			and math.abs(goal.Y.Offset - position.Y.Offset) < 0.5
			and math.abs(goal.X.Scale - position.X.Scale) < 0.001
			and math.abs(goal.Y.Scale - position.Y.Scale) < 0.001

		if settled then
			target.Position = goal
			settling = false
			return
		end

		target.Position = position:Lerp(goal, MC(dt * 20, 0, 1))
	end)
end

-- User-driven resizing. This changes Size, but it is direct manipulation of
-- the window by the user — not an animation — so it does not break the rule.
local function MakeResizable(handle: GuiButton, target: GuiObject, minimum: Vector2, onResize: ((UDim2) -> ())?)
	local resizing, startPosition, startSize = false, Vector3.zero, V2()

	Connect(handle.InputBegan, function(input)
		if input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.Touch then
			resizing = true
			startPosition = input.Position
			startSize = target.AbsoluteSize

			local connection
			connection = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
					connection:Disconnect()
				end
			end)
		end
	end)

	Connect(UserInputService.InputChanged, function(input)
		if not resizing then
			return
		end
		if input.UserInputType ~= UIT.MouseMovement and input.UserInputType ~= UIT.Touch then
			return
		end
		local delta = input.Position - startPosition
		 target.Size = UFO(
		 	math.max(minimum.X, MR(startSize.X + delta.X)),
		 	math.max(minimum.Y, MR(startSize.Y + delta.Y))
		 )
		if onResize then
			onResize(target.Size)
		end
	end)
end

--=============================================================================
-- Shared primitives — the exact decorations the dump applied over and over
--=============================================================================

local function Corner(parent: Instance, radius: number?): UICorner
	return Add("UICorner", { Parent = parent, CornerRadius = radius and UD(0, radius) or nil })
end

-- Fully rounded (capsule) corner — UD(1, 0).
local function Pill(parent: Instance): UICorner
	return Add("UICorner", { Parent = parent, CornerRadius = UD(1, 0) })
end

local function Stroke(parent: Instance, key: string?, inner: boolean?): UIStroke
	local stroke = Add("UIStroke", {
		Parent = parent,
		ApplyStrokeMode = ASM.Border,
		BorderStrokePosition = inner and BSP.Inner or nil,
	})
	Bind(stroke, { Color = key or "Border" })
	return stroke
end

-- UIShadow is not available on every client; Add() returns nil there and every
-- caller guards, so the library degrades to shadowless rendering gracefully.
local function Shadow(parent: Instance, transparency: number?, key: string?): any
	local shadow = Add("UIShadow", {
		Parent = parent,
		Transparency = transparency or 0.65,
		BlurRadius = UD(0, 10),
	})
	if shadow and key then
		Bind(shadow, { Color = key })
	end
	return shadow
end

-- IMPORTANT: UIGradient colours MULTIPLY with the element's BackgroundColor3.
-- The dump therefore gives every gradient carrier a plain white background so
-- the gradient's own colours render unmodified. These helpers enforce that —
-- theming flows entirely through the gradient keypoints, never the background.
local WHITE = RGB(255, 255, 255)

-- The "raised control" gradient every button/input/toggle shared.
local function SurfaceGradient(parent: Instance): UIGradient
	(parent :: any).BackgroundColor3 = WHITE
	local gradient = Add("UIGradient", { Parent = parent, Rotation = 90 })
	BindGradient(gradient, { { 0, "Foreground" }, { 1, "ForegroundLight" } })
	return gradient
end

local function AccentGradient(parent: Instance): UIGradient
	(parent :: any).BackgroundColor3 = WHITE
	local gradient = Add("UIGradient", { Parent = parent, Rotation = -90 })
	BindGradient(gradient, { { 0, "Accent" }, { 1, "AccentLight" } })
	return gradient
end

local function Padding(parent: Instance, top: number?, bottom: number?, left: number?, right: number?): UIPadding
	return Add("UIPadding", {
		Parent = parent,
		PaddingTop = UD(0, top or 0),
		PaddingBottom = UD(0, bottom or 0),
		PaddingLeft = UD(0, left or 0),
		PaddingRight = UD(0, right or 0),
	})
end

local function List(parent: Instance, properties: { [string]: any }?): UIListLayout
	local props: { [string]: any } = properties or {}
	props.Parent = parent
	props.SortOrder = props.SortOrder or SO.LayoutOrder
	return Add("UIListLayout", props)
end

local function Text(parent: Instance, properties: { [string]: any }): any
	local props = properties
	props.Parent = parent
	props.FontFace = props.FontFace or FN(FONT_ID, FW.SemiBold, FS.Normal)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextSize = props.TextSize or 14
	props.TextXAlignment = props.TextXAlignment or TXA.Left
	props.BorderSizePixel = 0

	-- ClassName is a pseudo-key for this helper, not a real property
	local class = props.ClassName or "TextLabel"
	props.ClassName = nil

	local color = props.TextColor3
	props.TextColor3 = nil

	local label = Add(class, props)
	if typeof(color) == "Color3" then
		label.TextColor3 = color
	else
		Bind(label, { TextColor3 = color or "Text" })
	end
	return label
end

-- Popup container: a plain Frame (NOT a CanvasGroup — those flatten gradients
-- over child text). Open/close fades run through the Fader.
-- Pass a theme key for a solid background; omit it when the popup carries a
-- colour gradient (the gradient helper will set the white base itself).
local function PopupFrame(parent: Instance, name: string, backgroundKey: string?): any
	local frame = Add("Frame", {
		Parent = parent,
		Name = name,
		Visible = false,
		ClipsDescendants = true,
		BorderSizePixel = 0,
		ZIndex = 40,
	})
	if backgroundKey then
		Bind(frame, { BackgroundColor3 = backgroundKey })
	end
	return frame
end

-- Converts an on-screen point into a Position local to `holder`. Popups are
-- parented to the Externals frame, whose origin is NOT the screen origin on an
-- IgnoreGuiInset ScreenGui — subtracting the holder's own AbsolutePosition
-- makes the maths inset-proof.
local function ToHolderSpace(holder: Instance, x: number, y: number): UDim2
	local origin: Vector2 = (holder :: any).AbsolutePosition
	return UFO(MR(x - origin.X), MR(y - origin.Y))
end

-- Shared open/close animation for popups: Fader cascade + an 8px vertical
-- slide. Position and transparency only; the popup's size is set before
-- opening and never animated.
local function AnimatePopup(popup: GuiObject, open: boolean, basePosition: UDim2)
	if open then
		popup.Position = basePosition + UD2(0, 0, 0, 8)
		popup.Visible = true
		Tween(popup, Anim.Slow, { Position = basePosition })
		Fader.In(popup, Anim.Slow)
	else
		Fader.Out(popup, Anim.Base)
		local tween = Tween(popup, Anim.Base, { Position = basePosition + UD2(0, 0, 0, 8) })
		tween.Completed:Once(function()
			if Fader.State[popup] == "hidden" then
				popup.Visible = false
			end
		end)
	end
end

local function InsideBounds(mouse: Vector2, object: GuiObject): boolean
	local topLeft = object.AbsolutePosition
	local bottomRight = topLeft + object.AbsoluteSize
	return mouse.X >= topLeft.X and mouse.X <= bottomRight.X
		and mouse.Y >= topLeft.Y and mouse.Y <= bottomRight.Y
end

--=============================================================================
-- Sub-elements (things that live in a row's right-hand content)
--=============================================================================

local SubElement = {}

-- Toggle: pill switch. Off = Toggle template, On = ToggleE template.
-- The knob slides (position) and everything else crossfades; nothing resizes.
function SubElement.Toggle(parent: Instance, default: boolean, callback: (boolean) -> ())
	local state = default and true or false

	local button = Add("TextButton", {
		Parent = parent,
		Text = "",
		AutoButtonColor = false,
		Name = "Toggle",
		Size = UFO(26, 16),
		BorderSizePixel = 0,
	})
	Pill(button)
	SurfaceGradient(button)
	local outerStroke = Stroke(button, "Border", true)
	local glow = Shadow(button, 0.65, "Accent")

	-- accent fill, faded in when active
	local fill = Add("Frame", {
		Parent = button,
		Name = "Gradient",
		BackgroundTransparency = 1,
		Size = UFS(1, 1),
		BorderSizePixel = 0,
		ZIndex = 2,
	})
	Pill(fill)
	AccentGradient(fill)
	local fillStroke = Stroke(fill, "AccentLight", true)
	fillStroke.Transparency = 1

	local knob = Add("Frame", {
		Parent = button,
		AnchorPoint = V2(0, 0.5),
		Name = "Indicator",
		BackgroundTransparency = 0.8,
		Position = UD2(0, 2, 0.5, 0),
		Size = UFO(12, 12),
		ZIndex = 3,
		BorderSizePixel = 0,
		BackgroundColor3 = RGB(255, 255, 255),
	})
	Pill(knob)

	local function render(animate: boolean?)
		local info = animate == false and TI(0) or Anim.Base
		Tween(fill, info, { BackgroundTransparency = state and 0 or 1 })
		Tween(fillStroke, info, { Transparency = state and 0 or 1 })
		Tween(outerStroke, info, { Transparency = state and 1 or 0 })
		Tween(knob, state and Anim.Spring or Anim.Base, {
			Position = state and UD2(1, -14, 0.5, 0) or UD2(0, 2, 0.5, 0),
			BackgroundTransparency = state and 0 or 0.8,
		})
		if glow then
			Tween(glow, info, { Transparency = state and 0.65 or 1 })
		end
	end

	render(false)

	Connect(button.MouseButton1Click, function()
		state = not state
		render()
		task.spawn(callback, state)
	end)

	-- hover feedback: knob brightens slightly (transparency only)
	Hover(button, function(hovering)
		if state then
			return -- already fully opaque when on
		end
		Tween(knob, Anim.Fast, { BackgroundTransparency = hovering and 0.6 or 0.8 })
	end)

	return {
		Instance = button,
		Get = function()
			return state
		end,
		Set = function(_, value: boolean)
			state = value and true or false
			render()
			task.spawn(callback, state)
		end,
	}
end

-- Checkbox: square with a tick. Off = Checkbox, On = CheckboxE.
-- The tick fades in while springing from a slight rotation — no size change.
function SubElement.Checkbox(parent: Instance, default: boolean, callback: (boolean) -> ())
	local state = default and true or false

	local button = Add("TextButton", {
		Parent = parent,
		Text = "",
		AutoButtonColor = false,
		Name = "Checkbox",
		Size = UFO(16, 16),
		BorderSizePixel = 0,
	})
	Corner(button, 3)
	SurfaceGradient(button)
	local outerStroke = Stroke(button, "Border", true)
	local glow = Shadow(button, 1, "Accent")

	local fill = Add("Frame", {
		Parent = button,
		Name = "Gradient",
		BackgroundTransparency = 1,
		Size = UFS(1, 1),
		BorderSizePixel = 0,
	})
	Corner(fill, 3)
	AccentGradient(fill)
	local fillStroke = Stroke(fill, "AccentLight", true)
	fillStroke.Transparency = 1

	local icon = Add("ImageLabel", {
		Parent = button,
		ScaleType = SCL.Fit,
		Name = "Icon",
		ResampleMode = RSM.Pixelated,
		AnchorPoint = V2(0.5, 0.5),
		Image = "rbxassetid://114424333378875",
		BackgroundTransparency = 1,
		ImageTransparency = 1,
		Rotation = -60,
		Position = UFS(0.5, 0.5),
		Size = UFO(10, 10),
		ZIndex = 2,
		BorderSizePixel = 0,
	})

	local function render(animate: boolean?)
		local info = animate == false and TI(0) or Anim.Base
		Tween(fill, info, { BackgroundTransparency = state and 0 or 1 })
		Tween(fillStroke, info, { Transparency = state and 0 or 1 })
		Tween(outerStroke, info, { Transparency = state and 1 or 0 })
		Tween(icon, info, { ImageTransparency = state and 0 or 1 })
		Tween(icon, animate == false and TI(0) or (state and Anim.Spring or Anim.Fast), {
			Rotation = state and 0 or -60,
		})
		if glow then
			Tween(glow, info, { Transparency = state and 0.65 or 1 })
		end
	end

	render(false)

	Connect(button.MouseButton1Click, function()
		state = not state
		render()
		task.spawn(callback, state)
	end)

	return {
		Instance = button,
		Get = function()
			return state
		end,
		Set = function(_, value: boolean)
			state = value and true or false
			render()
			task.spawn(callback, state)
		end,
	}
end

--=============================================================================
-- Colorpicker popup (Externals.Colorpicker)
--=============================================================================

local function BuildColorpicker(holder: Instance, swatch: GuiButton, default: Color3, defaultAlpha: number, callback)
	local hue, saturation, value = default:ToHSV()
	local alpha = defaultAlpha or 0

	local panel = PopupFrame(holder, "Colorpicker", "Background")
	panel.Size = UFO(203, 207)
	panel.ZIndex = 50
	Corner(panel, 5)
	Stroke(panel, "Border", true)
	Shadow(panel, 0.65)
	Padding(panel, 10, 10, 10, 10)

	local preview = Add("Frame", {
		Parent = panel,
		Name = "Indicator",
		Size = UFO(16, 16),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Pill(preview)
	Shadow(preview, 0.65)

	local hueBar = Add("TextButton", {
		Parent = panel,
		Text = "",
		AutoButtonColor = false,
		Name = "Hue",
		Position = UFO(26, 0),
		Size = UD2(1, -26, 0, 16),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Pill(hueBar)
	Add("UIGradient", {
		Parent = hueBar,
		Color = CS({
			CSK(0, RGB(255, 0, 0)),
			CSK(0.16, RGB(255, 255, 0)),
			CSK(0.3, RGB(0, 255, 0)),
			CSK(0.5, RGB(0, 255, 255)),
			CSK(0.66, RGB(0, 0, 255)),
			CSK(0.83, RGB(255, 0, 255)),
			CSK(1, RGB(255, 0, 0)),
		}),
	})
	Shadow(hueBar, 0.65)

	-- Selectors must never sink input: once a click parks one under the
	-- cursor, an Active selector would swallow every following press and the
	-- track would stop receiving drags.
	local hueSelector = Add("TextButton", {
		Parent = hueBar,
		Text = "",
		Active = false,
		Selectable = false,
		AnchorPoint = V2(0, 0.5),
		Name = "Selector",
		Position = UD2(0, 1, 0.5, 0),
		Size = UFO(10, 10),
		BackgroundColor3 = RGB(255, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 52,
	})
	Pill(hueSelector)
	Add("UIStroke", {
		Parent = hueSelector,
		Thickness = 2,
		BorderOffset = UD(0, 1),
		Color = RGB(255, 255, 255),
		ApplyStrokeMode = ASM.Border,
	})

	local alphaBar = Add("TextButton", {
		Parent = panel,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = V2(0, 1),
		Name = "Alpha",
		Position = UFS(0, 1),
		Size = UD2(0, 16, 1, -26),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Pill(alphaBar)
	Shadow(alphaBar, 0.65)

	local alphaOverlay = Add("Frame", {
		Parent = alphaBar,
		Name = "_",
		Size = UD2(1, 0, 1, 1),
		BackgroundColor3 = RGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Add("UIGradient", {
		Parent = alphaOverlay,
		Rotation = -90,
		Transparency = NS({ NSK(0, 0), NSK(1, 1) }),
		Color = CS({ CSK(0, RGB(0, 0, 0)), CSK(1, RGB(255, 255, 255)) }),
	})
	Pill(alphaOverlay)

	local alphaSelector = Add("TextButton", {
		Parent = alphaBar,
		Text = "",
		Active = false,
		Selectable = false,
		AnchorPoint = V2(0.5, 0),
		Name = "Selector",
		Position = UD2(0.5, 0, 0, 1),
		Size = UFO(10, 10),
		BorderSizePixel = 0,
		ZIndex = 52,
	})
	Pill(alphaSelector)
	Add("UIStroke", {
		Parent = alphaSelector,
		Thickness = 2,
		BorderOffset = UD(0, 1),
		Color = RGB(255, 255, 255),
		ApplyStrokeMode = ASM.Border,
	})

	local sv = Add("Frame", {
		Parent = panel,
		Name = "SV",
		Position = UFO(26, 26),
		Size = UD2(1, -26, 1, -26),
		BackgroundColor3 = RGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Corner(sv, 5)
	local svGradient = Add("UIGradient", {
		Parent = sv,
		Color = CS({ CSK(0, RGB(255, 255, 255)), CSK(1, RGB(255, 0, 0)) }),
	})
	Shadow(sv, 0.65)

	local svOverlay = Add("Frame", {
		Parent = sv,
		Name = "_",
		Size = UFS(1, 1),
		BackgroundColor3 = RGB(0, 0, 0),
		BorderSizePixel = 0,
		ZIndex = 51,
	})
	Add("UIGradient", {
		Parent = svOverlay,
		Rotation = -90,
		Transparency = NS({ NSK(0, 0), NSK(1, 1) }),
		Color = CS({ CSK(0, RGB(0, 0, 0)), CSK(1, RGB(0, 0, 0)) }),
	})
	Add("UICorner", {
		Parent = svOverlay,
		TopLeftRadius = UD(0, 5),
		TopRightRadius = UD(0, 5),
		BottomRightRadius = UD(0, 4),
		BottomLeftRadius = UD(0, 4),
	})

	local svSelector = Add("TextButton", {
		Parent = sv,
		Text = "",
		Active = false,
		Selectable = false,
		AnchorPoint = V2(1, 0),
		Name = "Selector",
		Position = UD2(1, -1, 0, 1),
		Size = UFO(10, 10),
		BorderSizePixel = 0,
		ZIndex = 52,
	})
	Pill(svSelector)
	Add("UIStroke", {
		Parent = svSelector,
		Thickness = 2,
		BorderOffset = UD(0, 1),
		Color = RGB(255, 255, 255),
		ApplyStrokeMode = ASM.Border,
	})

	local function render(animate: boolean?)
		local color = HSV(hue, saturation, value)
		local info = animate == false and TI(0) or Anim.Fast

		Tween(swatch, info, { BackgroundColor3 = color, BackgroundTransparency = alpha })
		Tween(preview, info, { BackgroundColor3 = color, BackgroundTransparency = alpha })
		Tween(alphaBar, info, { BackgroundColor3 = color })
		Tween(alphaSelector, info, { BackgroundColor3 = color })
		Tween(hueSelector, info, { BackgroundColor3 = HSV(hue, 1, 1) })
		Tween(svSelector, info, { BackgroundColor3 = color })

		svGradient.Color = CS({ CSK(0, RGB(255, 255, 255)), CSK(1, HSV(hue, 1, 1)) })

		-- Selector travel: the 10px knob plus a 1px margin each side must stay
		-- inside the track, so the pixel offset counter-travels 12px across the
		-- full scale range (at scale 0 the offset is +1/+11, at scale 1 it is
		-- -11/-1 depending on the anchor).
		Tween(hueSelector, info, { Position = UD2(hue, 1 - 12 * hue, 0.5, 0) })
		Tween(alphaSelector, info, { Position = UD2(0.5, 0, alpha, 1 - 12 * alpha) })
		Tween(svSelector, info, {
			Position = UD2(saturation, 11 - 12 * saturation, 1 - value, 1 - 12 * (1 - value)),
		})

		task.spawn(callback, color, alpha)
	end

	-- Generic click-and-drag binding for the three tracks.
	local function BindTrack(track: GuiObject, apply: (Vector2) -> ())
		local dragging = false

		local function update(position: Vector3 | Vector2)
			local absolutePosition = track.AbsolutePosition
			local absoluteSize = track.AbsoluteSize
			apply(V2(
				MC((position.X - absolutePosition.X) / absoluteSize.X, 0, 1),
				MC((position.Y - absolutePosition.Y) / absoluteSize.Y, 0, 1)
			))
		end

		Connect(track.InputBegan, function(input)
			if input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.Touch then
				dragging = true
				update(input.Position)
			end
		end)
		Connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.Touch then
				dragging = false
			end
		end)
		Connect(UserInputService.InputChanged, function(input)
			if not dragging then
				return
			end
			if input.UserInputType == UIT.MouseMovement or input.UserInputType == UIT.Touch then
				update(input.Position)
			end
		end)
	end

	BindTrack(hueBar, function(position)
		hue = position.X
		render()
	end)
	BindTrack(alphaBar, function(position)
		alpha = position.Y
		render()
	end)
	BindTrack(sv, function(position)
		saturation = position.X
		value = 1 - position.Y
		render()
	end)

	local open = false
	local function setOpen(shouldOpen: boolean)
		if open == shouldOpen then
			return
		end
		open = shouldOpen

		local absolutePosition = swatch.AbsolutePosition
		local base = ToHolderSpace(holder, absolutePosition.X - 187, absolutePosition.Y + 22)
		AnimatePopup(panel, open, base)
	end

	Connect(swatch.MouseButton1Click, function()
		setOpen(not open)
	end)

	-- Click-away closes the popup.
	Connect(UserInputService.InputBegan, function(input, processed)
		if processed or not open then
			return
		end
		if input.UserInputType ~= UIT.MouseButton1 and input.UserInputType ~= UIT.Touch then
			return
		end
		local mouse = V2(input.Position.X, input.Position.Y)
		if not InsideBounds(mouse, panel) and not InsideBounds(mouse, swatch) then
			setOpen(false)
		end
	end)

	render(false)

	-- prime the fader: capture rest values now that the panel is fully built,
	-- and park everything transparent for the first fade-in
	Fader.Out(panel, TI(0))

	return {
		Panel = panel,
		Close = function()
			setOpen(false)
		end,
		Get = function()
			return HSV(hue, saturation, value), alpha
		end,
		Set = function(_, color: Color3, newAlpha: number?)
			hue, saturation, value = color:ToHSV()
			alpha = newAlpha or alpha
			render()
		end,
	}
end

--=============================================================================
-- Section — holds elements
--=============================================================================

local Section = {}
Section.__index = Section

-- Every labelled control (toggle/checkbox/colorpicker/keybind) shares this row.
function Section:_Row(title: string)
	local row = Add("Frame", {
		Parent = self.Content,
		Name = "Label",
		BackgroundTransparency = 1,
		Size = UFS(1, 0),
		AutomaticSize = AT.Y,
		BorderSizePixel = 0,
		LayoutOrder = self:_Order(),
	})

	local left = Add("Frame", {
		Parent = row,
		AnchorPoint = V2(0, 0.5),
		Name = "LeftContent",
		BackgroundTransparency = 1,
		Position = UFS(0, 0.5),
		Size = UFS(1, 0),
		AutomaticSize = AT.XY,
		BorderSizePixel = 0,
	})
	List(left, { Padding = UD(0, 7), FillDirection = FD.Horizontal })

	local label = Text(left, {
		Name = "Label",
		LayoutOrder = 1,
		Text = title,
		TextTruncate = ETT.SplitWord,
		AutomaticSize = AT.XY,
	})

	local right = Add("Frame", {
		Parent = row,
		AnchorPoint = V2(1, 0),
		BackgroundTransparency = 1,
		Position = UFS(1, 0),
		Name = "RightContent",
		AutomaticSize = AT.XY,
		BorderSizePixel = 0,
	})
	List(right, { VerticalAlignment = VFA.Center, FillDirection = FD.Horizontal, Padding = UD(0, 5) })

	return row, left, right, label
end

function Section:_Order(): number
	self._order = (self._order or 0) + 1
	return self._order
end

--== Button ===================================================================

--[[
	Section:AddButton({ Title = "single button", Callback = function() end })
	Section:AddButton({ Buttons = { {Title="a",Callback=f}, {Title="b",Callback=g} } })
]]
function Section:AddButton(options: { [string]: any })
	local list = options.Buttons or { options }

	local container = Add("Frame", {
		Parent = self.Content,
		Active = true,
		Selectable = true,
		BackgroundTransparency = 1,
		Name = "Button",
		Size = UD2(1, 0, 0, 25),
		BorderSizePixel = 0,
		LayoutOrder = self:_Order(),
	})
	Corner(container, 5)
	List(container, {
		VerticalAlignment = VFA.Center,
		FillDirection = FD.Horizontal,
		HorizontalAlignment = HFA.Center,
		HorizontalFlex = UFA.Fill,
		Padding = UD(0, 5),
	})

	local built = {}
	for index, entry in ipairs(list) do
		local button = Add("TextButton", {
			Parent = container,
			Text = "",
			AutoButtonColor = false,
			Name = "Button",
			TextTruncate = ETT.AtEnd,
			Size = UD2(1, 0, 0, 25),
			LayoutOrder = index,
			BorderSizePixel = 0,
		})
		Corner(button, 5)
		Shadow(button, 0.65)
		local stroke = Stroke(button, "Border", true)
		SurfaceGradient(button)

		-- accent flash layer: blinks in on click, then bleeds back out.
		-- Transparency only — the button never moves or resizes.
		local flash = Add("Frame", {
			Parent = button,
			Name = "Flash",
			BackgroundTransparency = 1,
			Size = UFS(1, 1),
			ZIndex = 2,
			BorderSizePixel = 0,
		})
		Corner(flash, 5)
		AccentGradient(flash)
		local flashStroke = Stroke(flash, "AccentLight", true)
		flashStroke.Transparency = 1

		local label = Text(button, {
			Name = "Label",
			Text = entry.Title or entry.Name or "Button",
			TextTransparency = 0.5,
			Size = UFS(1, 1),
			TextTruncate = ETT.SplitWord,
			ZIndex = 3,
		})
		Padding(label, 0, 1)

		Hover(button, function(hovering)
			Tween(label, Anim.Base, { TextTransparency = hovering and 0 or 0.5 })
			Tween(stroke, Anim.Base, { Color = hovering and Callisto.Theme.Accent or Callisto.Theme.Border })
		end)
		Press(button)

		Connect(button.MouseButton1Click, function()
			flash.BackgroundTransparency = 0.25
			flashStroke.Transparency = 0.25
			Tween(flash, Anim.Slow, { BackgroundTransparency = 1 })
			Tween(flashStroke, Anim.Slow, { Transparency = 1 })
			if entry.Callback then
				task.spawn(entry.Callback)
			end
		end)

		TIS(built, { Instance = button, Label = label })
	end

	return { Instance = container, Buttons = built }
end

--== Label ====================================================================

function Section:AddLabel(options: { [string]: any } | string)
	local opts: { [string]: any } = typeof(options) == "string" and { Title = options } or (options :: any)
	local row, _, _, label = self:_Row(opts.Title or "Label")
	row.AutomaticSize = AT.None
	row.Size = UD2(1, 0, 0, 18)
	label.Size = UD2(1, 0, 0, 18)
	label.TextXAlignment = TXA.Left

	return {
		Instance = row,
		Set = function(_, value: string)
			label.Text = value
		end,
	}
end

--== Toggle ===================================================================

function Section:AddToggle(options: { [string]: any })
	local row, _, right = self:_Row(options.Title or "Toggle")
	local flag = options.Flag

	local function fire(state: boolean)
		if flag then
			Callisto.Flags[flag] = state
		end
		if options.Callback then
			options.Callback(state)
		end
	end

	local control: any
	if options.Style == "Checkbox" then
		control = SubElement.Checkbox(right, options.Default or false, fire)
	else
		control = SubElement.Toggle(right, options.Default or false, fire)
	end

	if flag then
		Callisto.Flags[flag] = options.Default or false
	end

	control.Instance.LayoutOrder = 2
	control.Row = row
	return control
end

function Section:AddCheckbox(options: { [string]: any })
	options.Style = "Checkbox"
	return self:AddToggle(options)
end

--== Colorpicker ==============================================================

function Section:AddColorpicker(options: { [string]: any })
	local row, _, right = self:_Row(options.Title or "Colorpicker")
	local flag = options.Flag

	local swatch = Add("TextButton", {
		Parent = right,
		Text = "",
		AutoButtonColor = false,
		Name = "Colorpicker",
		Size = UFO(16, 16),
		LayoutOrder = 2,
		BorderSizePixel = 0,
	})
	-- deliberately NOT theme-bound: the swatch shows the picked colour, so a
	-- later SetTheme must not overwrite it
	swatch.BackgroundColor3 = options.Default or Callisto.Theme.Accent
	Pill(swatch)
	-- hover ring: accent-themed (the dump's hardcoded purple clashed with any
	-- theme) and driven by GuiState, which unlike MouseEnter/MouseLeave cannot
	-- miss the leave event and leave the ring stuck on
	local swatchStroke = Add("UIStroke", {
		Parent = swatch,
		Transparency = 1,
		BorderOffset = UD(0, 1),
		ApplyStrokeMode = ASM.Border,
	})
	Bind(swatchStroke, { Color = "Accent" })

	Connect(swatch:GetPropertyChangedSignal("GuiState"), function()
		local hovering = swatch.GuiState == EGS.Hover or swatch.GuiState == EGS.Press
		Tween(swatchStroke, Anim.Fast, { Transparency = hovering and 0 or 1 })
	end)

	local picker: any = BuildColorpicker(
		self.Window.Externals,
		swatch,
		options.Default or Callisto.Theme.Accent,
		options.Alpha or 0,
		function(color, alpha)
			if flag then
				Callisto.Flags[flag] = color
			end
			if options.Callback then
				options.Callback(color, alpha)
			end
		end
	)

	picker.Row = row
	return picker
end

--== Keybind ==================================================================

local KeybindBlacklist = {
	[EKC.Unknown] = true,
}

function Section:AddKeybind(options: { [string]: any })
	local _, left = self:_Row(options.Title or "Keybind")
	local current: EnumItem? = options.Default
	local binding = false

	local button = Text(left, {
		ClassName = "TextButton",
		LayoutOrder = 2,
		-- the dump had Active = false (static mockup); it must be true to click
		Active = true,
		Selectable = false,
		TextTruncate = ETT.SplitWord,
		Name = "Keybind",
		Text = current and current.Name:upper() or "NONE",
		TextTransparency = 0.5,
		AutomaticSize = AT.XY,
		AutoButtonColor = false,
	})

	local function render()
		button.Text = binding and "..." or (current and current.Name:upper() or "NONE")
		Tween(button, Anim.Fast, { TextTransparency = binding and 0 or 0.5 })
	end

	Connect(button.MouseButton1Click, function()
		binding = true
		render()
	end)

	Hover(button, function(hovering)
		if not binding then
			Tween(button, Anim.Fast, { TextTransparency = hovering and 0.2 or 0.5 })
		end
	end)

	Connect(UserInputService.InputBegan, function(input, processed)
		if binding then
			if input.UserInputType == UIT.Keyboard and not KeybindBlacklist[input.KeyCode] then
				-- Backspace clears the bind. `x and nil or y` cannot express this
				-- in Lua (nil is falsy), so it has to be a real branch.
				if input.KeyCode == EKC.Backspace then
					current = nil
				else
					current = input.KeyCode
				end
				binding = false
				render()
				if options.Flag then
					Callisto.Flags[options.Flag] = current
				end
				if options.OnChanged then
					options.OnChanged(current)
				end
			end
			return
		end

		if processed or not current then
			return
		end
		if input.UserInputType == UIT.Keyboard and input.KeyCode == current and options.Callback then
			task.spawn(options.Callback, current)
		end
	end)

	render()

	return {
		Instance = button,
		Get = function()
			return current
		end,
		Set = function(_, key: EnumItem?)
			current = key
			render()
		end,
	}
end

--== Slider ===================================================================

function Section:AddSlider(options: { [string]: any })
	local minimum = options.Min or 0
	local maximum = options.Max or 100
	local decimals = options.Decimals or 0
	local suffix = options.Suffix or "%"
	local value = MC(options.Default or minimum, minimum, maximum)

	local container = Add("Frame", {
		Parent = self.Content,
		Name = "Slider",
		BackgroundTransparency = 1,
		Size = UFS(1, 0),
		AutomaticSize = AT.Y,
		BorderSizePixel = 0,
		LayoutOrder = self:_Order(),
	})
	List(container, { Padding = UD(0, 5) })

	local textHolder = Add("Frame", {
		Parent = container,
		AnchorPoint = V2(0, 0.5),
		Name = "TextHolder",
		BackgroundTransparency = 1,
		Position = UFS(0, 0.5),
		Size = UFS(1, 0),
		AutomaticSize = AT.XY,
		BorderSizePixel = 0,
	})
	List(textHolder, {
		FillDirection = FD.Horizontal,
		HorizontalFlex = UFA.SpaceBetween,
		Padding = UD(0, 7),
	})

	local title = Text(textHolder, {
		Name = "Title",
		LayoutOrder = 1,
		Text = options.Title or "slider",
		TextTruncate = ETT.SplitWord,
		AutomaticSize = AT.XY,
	})
	Padding(title, -3, -1)

	local current = Text(textHolder, {
		Name = "Current",
		LayoutOrder = 1,
		Text = "0" .. suffix,
		TextTruncate = ETT.SplitWord,
		AutomaticSize = AT.XY,
	})
	Padding(current, -3, -1)

	local track = Add("TextButton", {
		Parent = container,
		LayoutOrder = 1,
		Text = "",
		AutoButtonColor = false,
		Name = "Button",
		Size = UD2(1, 0, 0, 16),
		BorderSizePixel = 0,
	})
	Corner(track, 5)
	local trackStroke = Stroke(track, "Border", true)
	SurfaceGradient(track)

	local fill = Add("Frame", {
		Parent = track,
		Name = "Fill",
		Size = UD2(0, 0, 1, 0),
		BorderSizePixel = 0,
	})
	Corner(fill, 5)
	AccentGradient(fill)
	Shadow(fill, 0.65, "Accent")

	local function round(number: number): number
		local multiplier = 10 ^ decimals
		return MF(number * multiplier + 0.5) / multiplier
	end

	-- The fill's Size is the value readout — data, not decoration — so it is
	-- set instantly, never tweened. Dragging updates it every frame anyway.
	local function render()
		local progress = (value - minimum) / (maximum - minimum)
		fill.Size = UD2(progress, 0, 1, 0)
		current.Text = tostring(round(value)) .. suffix
	end

	local function set(newValue: number, silent: boolean?)
		value = MC(round(newValue), minimum, maximum)
		render()
		if options.Flag then
			Callisto.Flags[options.Flag] = value
		end
		if options.Callback and not silent then
			task.spawn(options.Callback, value)
		end
	end

	local dragging = false
	local function updateFromInput(position: Vector3 | Vector2)
		local progress = MC((position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		set(minimum + (maximum - minimum) * progress)
	end

	Connect(track.InputBegan, function(input)
		if input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.Touch then
			dragging = true
			updateFromInput(input.Position)
		end
	end)
	Connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == UIT.MouseButton1 or input.UserInputType == UIT.Touch then
			dragging = false
		end
	end)
	Connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == UIT.MouseMovement or input.UserInputType == UIT.Touch) then
			updateFromInput(input.Position)
		end
	end)

	-- hover feedback: stroke tint only
	Hover(track, function(hovering)
		Tween(trackStroke, Anim.Base, {
			Color = hovering and Callisto.Theme.Accent or Callisto.Theme.Border,
		})
	end)

	set(value, true)

	return {
		Instance = container,
		Get = function()
			return value
		end,
		Set = function(_, newValue: number)
			set(newValue)
		end,
	}
end

--== Input ====================================================================

function Section:AddInput(options: { [string]: any })
	local container = Add("Frame", {
		Parent = self.Content,
		Name = "Input",
		BackgroundTransparency = 1,
		Size = UFS(1, 0),
		AutomaticSize = AT.Y,
		BorderSizePixel = 0,
		LayoutOrder = self:_Order(),
	})
	List(container, { VerticalAlignment = VFA.Center, Padding = UD(0, 3) })
	Padding(container, 1)

	local title = Text(container, {
		Name = "Title",
		Text = options.Title or "Input",
		TextTransparency = 0.3,
		Position = UFO(21, 0),
		TextTruncate = ETT.SplitWord,
		AutomaticSize = AT.XY,
	})
	Padding(title, -5, -1)

	local box = Add("Frame", {
		Parent = container,
		LayoutOrder = 1,
		Active = true,
		Selectable = true,
		Name = "Button",
		Size = UD2(1, 0, 0, 25),
		BorderSizePixel = 0,
	})
	Corner(box, 5)
	local stroke = Stroke(box, "Border", true)
	Padding(box, 0, 0, 7, 7)
	Shadow(box, 0.65)
	SurfaceGradient(box)

	local input = Text(box, {
		ClassName = "TextBox",
		Name = "TextLabel",
		Text = options.Default or "",
		Size = UFS(1, 1),
		Selectable = false,
		TextXAlignment = TXA.Left,
		TextTruncate = ETT.SplitWord,
		Active = false,
		PlaceholderText = options.Placeholder or "something here....",
		ClearTextOnFocus = options.ClearOnFocus ~= false,
	})

	Connect(input.Focused, function()
		Tween(stroke, Anim.Base, { Color = Callisto.Theme.Accent })
	end)
	Connect(input.FocusLost, function(enter)
		Tween(stroke, Anim.Base, { Color = Callisto.Theme.Border })
		if options.Flag then
			Callisto.Flags[options.Flag] = input.Text
		end
		if options.Callback and (enter or not options.OnEnter) then
			task.spawn(options.Callback, input.Text, enter)
		end
	end)

	return {
		Instance = container,
		Get = function()
			return input.Text
		end,
		Set = function(_, value: string)
			input.Text = value
		end,
	}
end

--== Dropdown =================================================================

function Section:AddDropdown(options: { [string]: any })
	local values = options.Values or options.Options or {}
	local multi = options.Multi or options.MultiSelect or false
	local selected: { string } = {}

	if options.Default then
		if typeof(options.Default) == "table" then
			for _, item in next, options.Default do
				TIS(selected, item)
			end
		else
			TIS(selected, options.Default)
		end
	end

	local container = Add("Frame", {
		Parent = self.Content,
		Name = "Dropdown",
		BackgroundTransparency = 1,
		Size = UFS(1, 0),
		AutomaticSize = AT.Y,
		BorderSizePixel = 0,
		LayoutOrder = self:_Order(),
	})
	List(container, { VerticalAlignment = VFA.Center, Padding = UD(0, 3) })
	Padding(container, 1)

	local title = Text(container, {
		Name = "Title",
		Text = options.Title or "Dropdown",
		TextTransparency = 0.3,
		Position = UFO(21, 0),
		TextTruncate = ETT.SplitWord,
		AutomaticSize = AT.XY,
	})
	Padding(title, -5, -1)

	local button = Add("TextButton", {
		Parent = container,
		LayoutOrder = 1,
		Text = "",
		AutoButtonColor = false,
		Size = UD2(1, 0, 0, 25),
		Name = "Button",
		TextXAlignment = TXA.Left,
		TextTruncate = ETT.SplitWord,
		BorderSizePixel = 0,
	})
	Corner(button, 5)
	local stroke = Stroke(button, "Border", true)
	Padding(button, 0, 0, 7, 7)
	Shadow(button, 0.65)
	SurfaceGradient(button)
	List(button, {
		VerticalAlignment = VFA.Center,
		HorizontalFlex = UFA.Fill,
		FillDirection = FD.Horizontal,
	})

	local display = Text(button, {
		Text = "",
		Size = UFS(0, 1),
		TextXAlignment = TXA.Left,
		TextTruncate = ETT.SplitWord,
		AutomaticSize = AT.X,
	})

	local icon = Add("ImageLabel", {
		Parent = button,
		ScaleType = SCL.Fit,
		Name = "Icon",
		ResampleMode = RSM.Pixelated,
		AnchorPoint = V2(0.5, 0.5),
		Image = "rbxassetid://77930667227229",
		BackgroundTransparency = 1,
		Position = UFS(0.5, 0.5),
		Size = UFO(10, 10),
		ZIndex = 2,
		BorderSizePixel = 0,
	})
	Add("UISizeConstraint", { Parent = icon, MinSize = V2(10, 10), MaxSize = V2(10, 10) })

	--== popup list (plain Frame; the surface gradient only tints the frame's
	--== own background, so the option text stays untouched)
	local externals = self.Window.Externals
	local popup = PopupFrame(externals, "Dropdown")
	Corner(popup, 5)
	Stroke(popup, "Border", true)
	Padding(popup, 6, 5, 6, 7)
	Shadow(popup, 0.65)
	SurfaceGradient(popup)

	local inner = Add("ScrollingFrame", {
		Parent = popup,
		BackgroundTransparency = 1,
		Size = UFS(1, 1),
		CanvasSize = UFS(0, 0),
		AutomaticCanvasSize = AT.Y,
		ScrollBarThickness = 0,
		BorderSizePixel = 0,
		ZIndex = 41,
	})

	local ENTRY_HEIGHT = 14
	local ENTRY_GAP = 3
	List(inner, { Padding = UD(0, ENTRY_GAP) })

	local entries: { any } = {}

	local function displayText(): string
		if #selected == 0 then
			return options.Placeholder or "..."
		end
		return table.concat(selected, ", ")
	end

	local function render()
		display.Text = displayText()
		for _, entry in next, entries do
			local isSelected = TF(selected, entry.Value) ~= nil
			Tween(entry.Button, Anim.Fast, {
				TextTransparency = isSelected and 0 or 0.5,
				TextColor3 = isSelected and Callisto.Theme.Accent or Callisto.Theme.Text,
			})
		end
		if options.Flag then
			Callisto.Flags[options.Flag] = multi and table.clone(selected) or selected[1]
		end
	end

	local open = false
	local function setOpen(shouldOpen: boolean)
		if open == shouldOpen then
			return
		end
		open = shouldOpen

		-- Size is decided before the popup appears and never animated. It is
		-- computed from fixed entry metrics — TextBounds (and therefore
		-- AbsoluteContentSize) are NOT computed for elements that have never
		-- rendered, so measuring the hidden list would collapse the popup.
		local count = #entries
		local contentHeight = count * ENTRY_HEIGHT + math.max(count - 1, 0) * ENTRY_GAP
		local height = math.min(contentHeight + 11, options.MaxHeight or 160)
		popup.Size = UFO(MR(button.AbsoluteSize.X), height)

		local absolutePosition = button.AbsolutePosition
		local base = ToHolderSpace(externals, absolutePosition.X, absolutePosition.Y + 28)
		AnimatePopup(popup, open, base)
		Tween(icon, Anim.Slow, { Rotation = open and 180 or 0 })
	end

	local function AddOption(value: string)
		-- fixed height + full width instead of AutomaticSize: automatic sizing
		-- needs TextBounds, which stay 0 until the element first renders
		local entry = Text(inner, {
			ClassName = "TextButton",
			LayoutOrder = 1,
			Text = value,
			TextTransparency = 0.5,
			Size = UD2(1, 0, 0, ENTRY_HEIGHT),
			TextXAlignment = TXA.Left,
			TextTruncate = ETT.AtEnd,
			AutoButtonColor = false,
			ZIndex = 41,
		})

		Connect(entry.MouseButton1Click, function()
			local index = TF(selected, value)
			if multi then
				if index then
					TR(selected, index)
				else
					TIS(selected, value)
				end
			else
				selected = { value }
				setOpen(false)
			end
			render()
			if options.Callback then
				task.spawn(options.Callback, multi and table.clone(selected) or selected[1])
			end
		end)

		Hover(entry, function(hovering)
			if TF(selected, value) then
				return
			end
			Tween(entry, Anim.Fast, { TextTransparency = hovering and 0.2 or 0.5 })
		end)

		TIS(entries, { Button = entry, Value = value })
	end

	for _, value in ipairs(values) do
		AddOption(tostring(value))
	end

	-- prime the fader with the fully-built option list (see colorpicker note)
	Fader.Out(popup, TI(0))

	Connect(button.MouseButton1Click, function()
		setOpen(not open)
	end)

	Hover(button, function(hovering)
		Tween(stroke, Anim.Base, { Color = hovering and Callisto.Theme.Accent or Callisto.Theme.Border })
	end)

	Connect(UserInputService.InputBegan, function(input, processed)
		if processed or not open then
			return
		end
		if input.UserInputType ~= UIT.MouseButton1 and input.UserInputType ~= UIT.Touch then
			return
		end
		local mouse = V2(input.Position.X, input.Position.Y)
		if not InsideBounds(mouse, popup) and not InsideBounds(mouse, button) then
			setOpen(false)
		end
	end)

	render()

	return {
		Instance = container,
		Get = function()
			return multi and table.clone(selected) or selected[1]
		end,
		Set = function(_, value)
			selected = typeof(value) == "table" and table.clone(value) or { value }
			render()
		end,
		Refresh = function(_, newValues: { string })
			-- restore the shell to rest before rebuilding, so the re-prime
			-- below captures true rest values rather than mid-fade ones
			local hidden = Fader.State[popup] == "hidden"
			if hidden then
				Fader.In(popup, TI(0))
			end

			for _, entry in next, entries do
				entry.Button:Destroy()
			end
			table.clear(entries)
			selected = {}
			for _, value in ipairs(newValues) do
				AddOption(tostring(value))
			end
			render()

			if hidden then
				Fader.State[popup] = "shown"
				Fader.Out(popup, TI(0))
			end
		end,
		Close = function()
			setOpen(false)
		end,
	}
end

--== Switch (segmented button) ================================================

--[[
	Section:AddSwitch({
		Values = { "varation 1", "Disabled" },
		Default = 1,
		Compact = true,             -- SwitchButton2 (2px inset) vs SwitchButton (1px)
		Callback = function(value, index) end,
	})
]]
function Section:AddSwitch(options: { [string]: any })
	local values = options.Values or {}
	local index = options.Default or 1
	local inset = options.Compact and 2 or 1

	local container = Add("Frame", {
		Parent = self.Content,
		Size = UD2(1, 0, 0, 25),
		Name = "SwitchButton",
		Active = true,
		Selectable = true,
		BorderSizePixel = 0,
		LayoutOrder = self:_Order(),
	})
	Bind(container, { BackgroundColor3 = "Background" })
	Corner(container, 5)
	List(container, {
		VerticalAlignment = VFA.Center,
		FillDirection = FD.Horizontal,
		HorizontalAlignment = HFA.Center,
		HorizontalFlex = UFA.Fill,
	})
	Padding(container, inset, inset, inset, inset)
	Stroke(container, "Border", true)
	Shadow(container, 0.65)

	local buttons: { any } = {}

	-- Active segment = accent background (the button itself) + accent stroke.
	-- Inactive = the accent layer fades out, revealing the raised surface
	-- behind. Pure crossfade — no segment ever moves or resizes.
	local function render(animate: boolean?)
		local info = animate == false and TI(0) or Anim.Base
		for position, entry in next, buttons do
			local active = position == index
			Tween(entry.Button, info, { BackgroundTransparency = active and 0 or 1 })
			Tween(entry.Stroke, info, { Transparency = active and 0 or 1 })
			Tween(entry.Label, info, {
				TextTransparency = entry.Disabled and 0.9 or (active and 0 or 0.5),
			})
		end
	end

	-- ipairs, not next: LayoutOrder depends on a deterministic sequence
	for position, value in ipairs(values) do
		local disabled = typeof(value) == "table" and value.Disabled or false
		local title = typeof(value) == "table" and value.Title or tostring(value)

		local button = Add("TextButton", {
			Parent = container,
			Text = "",
			AutoButtonColor = false,
			Name = "Button",
			BackgroundTransparency = 1,
			TextTruncate = ETT.AtEnd,
			Size = UFS(1, 1),
			LayoutOrder = position,
			BorderSizePixel = 0,
		})
		Corner(button, 4)
		AccentGradient(button)
		local buttonStroke = Stroke(button, "AccentLight", true)
		buttonStroke.Transparency = 1

		local label = Text(button, {
			Name = "Label",
			Text = title,
			Size = UFS(1, 1),
			TextTruncate = ETT.SplitWord,
			Position = UFO(0, -1),
			TextTransparency = disabled and 0.9 or 0.5,
		})

		-- inactive segments keep the raised surface gradient
		local surface = Add("Frame", {
			Parent = button,
			BackgroundTransparency = 1,
			Size = UFS(1, 1),
			ZIndex = 0,
			BorderSizePixel = 0,
		})
		Corner(surface, 4)
		SurfaceGradient(surface)

		TIS(buttons, {
			Button = button,
			Label = label,
			Stroke = buttonStroke,
			Disabled = disabled,
		})

		if not disabled then
			Connect(button.MouseButton1Click, function()
				if index == position then
					return
				end
				index = position
				render()
				if options.Callback then
					task.spawn(options.Callback, title, position)
				end
			end)

			Hover(button, function(hovering)
				if index == position then
					return
				end
				Tween(label, Anim.Fast, { TextTransparency = hovering and 0.2 or 0.5 })
			end)
		end
	end

	render(false)

	return {
		Instance = container,
		Get = function()
			local value = values[index]
			return typeof(value) == "table" and value.Title or value, index
		end,
		Set = function(_, position: number)
			index = position
			render()
		end,
	}
end

--=============================================================================
-- Page
--=============================================================================

local Page = {}
Page.__index = Page

--[[
	Page:AddSection("Left", "Section #1")
	Page:AddSection("Section #1")          -- side omitted, defaults to Left
]]
function Page:AddSection(side: string, title: string?)
	local normalized = side and side:lower() or "left"

	-- Allow the side argument to be skipped entirely.
	if normalized ~= "left" and normalized ~= "right" then
		title = side
		normalized = "left"
	end

	local parent = (normalized == "right") and self.Right or self.Left

	local section = Add("Frame", {
		Parent = parent,
		Size = UFS(1, 0),
		Name = "Section",
		AutomaticSize = AT.Y,
		BorderSizePixel = 0,
	})
	Bind(section, { BackgroundColor3 = "Background" })
	Stroke(section, "Border", true)
	Corner(section, 5)
	Shadow(section, 0.6)

	local header = Add("Frame", {
		Parent = section,
		Name = "Header",
		Size = UD2(1, 0, 0, 25),
		BorderSizePixel = 0,
	})
	Bind(header, { BackgroundColor3 = "Foreground" })
	Add("UICorner", {
		Parent = header,
		TopLeftRadius = UD(0, 5),
		TopRightRadius = UD(0, 5),
		BottomRightRadius = UD(0, 0),
		BottomLeftRadius = UD(0, 0),
	})
	Stroke(header, "Border", true)

	Text(header, {
		Name = "Title",
		Text = title or "Section",
		Size = UFS(0, 1),
		Position = UFO(5, 0),
		TextTruncate = ETT.SplitWord,
		AutomaticSize = AT.X,
	})

	local content = Add("Frame", {
		Parent = section,
		ClipsDescendants = true,
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UFO(0, 25),
		Size = UFS(1, 0),
		AutomaticSize = AT.Y,
		BorderSizePixel = 0,
	})
	Padding(content, 10, 11, 11, 11)
	List(content, { Padding = UD(0, 7) })

	return setmetatable({
		Instance = section,
		Content = content,
		Window = self.Window,
		Page = self,
		_order = 0,
	}, Section)
end

--=============================================================================
-- Window
--=============================================================================

local Window = {}
Window.__index = Window

function Window:AddPage(name: string)
	local mobile = self.Mobile
	local frame = Add("ScrollingFrame", {
		Parent = self.Pages,
		BackgroundTransparency = 1,
		Name = "PageFrame",
		Size = UFS(1, 1),
		Visible = false,
		CanvasSize = UFS(0, 0),
		AutomaticCanvasSize = AT.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollingEnabled = mobile,
		ScrollBarThickness = mobile and 4 or 0,
		BorderSizePixel = 0,
	})

	local left = Add("ScrollingFrame", {
		Parent = frame,
		MidImage = "rbxassetid://83323744952055",
		TopImage = "rbxassetid://86255327167604",
		BottomImage = "rbxassetid://79069740978089",
		ClipsDescendants = false,
		AutomaticCanvasSize = AT.Y,
		ScrollBarThickness = 0,
		Name = "Left",
		Size = mobile and UFS(1, 0) or UFS(0.5, 1),
		AutomaticSize = mobile and AT.Y or AT.None,
		ScrollingEnabled = not mobile,
		Selectable = false,
		BackgroundTransparency = 1,
		CanvasSize = UFS(0, 0),
		BorderSizePixel = 0,
	})
	Bind(left, { ScrollBarImageColor3 = "Accent" })
	Padding(left, 0, 0, 0, 5)
	List(left, { Padding = UD(0, 10) })

	local right = Add("ScrollingFrame", {
		Parent = frame,
		Selectable = false,
		AnchorPoint = V2(1, 0),
		CanvasSize = UFS(0, 0),
		MidImage = "rbxassetid://83323744952055",
		TopImage = "rbxassetid://86255327167604",
		BottomImage = "rbxassetid://79069740978089",
		ClipsDescendants = false,
		ScrollBarThickness = 0,
		Name = "Right",
		Size = mobile and UFS(1, 0) or UFS(0.5, 1),
		AutomaticSize = mobile and AT.Y or AT.None,
		ScrollingEnabled = not mobile,
		BackgroundTransparency = 1,
		Position = UFS(1, 0),
		AutomaticCanvasSize = AT.Y,
		BorderSizePixel = 0,
	})
	Bind(right, { ScrollBarImageColor3 = "Accent" })
	Padding(right, 0, 0, 5, 0)
	List(right, { Padding = UD(0, 10) })
	if mobile then
		local function stackColumns()
			right.Position = UFO(0, math.floor(left.AbsoluteSize.Y) + 10)
		end
		Connect(left:GetPropertyChangedSignal("AbsoluteSize"), stackColumns)
		task.defer(stackColumns)
	end

	--== tab button (PageButtonD inactive <-> PageButtonE active) ==============
	local button = Add("TextButton", {
		Parent = self.ButtonHolder,
		FontFace = FN(FONT_ID, FW.Medium, FS.Normal),
		-- the dump had Active = false (static mockup); tabs must be clickable
		Active = true,
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Size = UFS(0, 1),
		Name = "PageButton",
		BackgroundTransparency = 1,
		AutomaticSize = AT.X,
		BorderSizePixel = 0,
		LayoutOrder = #self.PageList + 1,
	})
	-- gradient carrier: white background, colours live in the gradient
	button.BackgroundColor3 = WHITE
	Corner(button, 5)
	Padding(button, 0, 0, 5, 5)
	local buttonShadow = Shadow(button, 1, "Accent")
	local buttonStroke = Stroke(button, "AccentLight", true)
	buttonStroke.Transparency = 1
	local buttonGradient = Add("UIGradient", { Parent = button, Rotation = 90 })
	BindGradient(buttonGradient, { { 0, "Accent" }, { 1, "AccentDark" } })

	local label = Text(button, {
		FontFace = FN(FONT_ID, FW.Medium, FS.Normal),
		Text = name,
		TextTransparency = 0.5,
		BackgroundTransparency = 1,
		Size = UFS(1, 1),
		AutomaticSize = AT.XY,
		TextSize = 15,
	})

	local page: any = setmetatable({
		Name = name,
		Instance = frame,
		Left = left,
		Right = right,
		Button = button,
		Window = self,
	}, Page)

	local function setActive(active: boolean, animate: boolean?)
		local info = animate == false and TI(0) or Anim.Base
		Tween(button, info, { BackgroundTransparency = active and 0 or 1 })
		Tween(buttonStroke, info, { Transparency = active and 0 or 1 })
		Tween(label, info, { TextTransparency = active and 0 or 0.5 })
		if buttonShadow then
			Tween(buttonShadow, info, { Transparency = active and 0.65 or 1 })
		end
	end

	page.SetActive = setActive

	Connect(button.MouseButton1Click, function()
		self:SelectPage(page)
	end)

	Hover(button, function(hovering)
		if self.CurrentPage == page then
			return
		end
		Tween(label, Anim.Fast, { TextTransparency = hovering and 0.2 or 0.5 })
	end)

	setActive(false, false)
	TIS(self.PageList, page)

	if not self.CurrentPage then
		self:SelectPage(page)
	end

	return page
end

function Window:SelectPage(page: any)
	if self.CurrentPage == page then
		return
	end

	local previous: any = self.CurrentPage
	self.CurrentPage = page

	for _, other in next, self.PageList do
		other.SetActive(other == page)
	end

	-- The outgoing page is captured and hidden instantly (no overlap frames);
	-- the incoming page fades back to its captured rest values while settling
	-- down from +8px. The first visit to a page has no capture yet, so it
	-- simply appears and slides — every later visit gets the full fade.
	if previous then
		local frame = previous.Instance
		Fader.Out(frame, TI(0))
		frame.Visible = false
		frame.Position = UFO(0, 0)
	end

	page.Instance.Position = UFO(0, 8)
	page.Instance.Visible = true
	Fader.In(page.Instance, Anim.Slow)
	Tween(page.Instance, Anim.Slow, { Position = UFO(0, 0) })
end

function Window:SetTitle(title: string)
	self.Title.Text = title
end

-- Open/close: Fader cascade + a 12px slide. The window's size is NEVER
-- animated.
function Window:Toggle(state: boolean?)
	local open = state
	if open == nil then
		open = not self.Visible
	end
	if open == self.Visible then
		return
	end
	self.Visible = open

	local canvas: any = self.Canvas

	if open then
		local home: UDim2 = self.HomePosition or canvas.Position
		self.HomePosition = home
		self.ScreenGui.Enabled = true
		canvas.Visible = true
		if self.Minimized then
			self:Minimize(false)
		else
			self.Pages.Visible = true
			self.Footer.Visible = true
		end
		Fader.In(canvas, TI(0))
		for _, page in next, self.PageList do
			Fader.In(page.Instance, TI(0))
			page.Instance.Visible = page == self.CurrentPage
		end
		canvas.Position = home
	else
		self.HomePosition = canvas.Position
		self.ScreenGui.Enabled = false
	end
end

function Window:Minimize(state: boolean?)
	local minimized = state
	if minimized == nil then
		minimized = not self.Minimized
	end
	if minimized == self.Minimized then
		return
	end

	local canvas: any = self.Canvas
	self.NormalSize = self.NormalSize or canvas.Size
	self.Minimized = minimized

	if minimized then
		Fader.Out(self.Pages, Anim.Base)
		Fader.Out(self.Footer, Anim.Base)
		Tween(canvas, Anim.Slow, {
			Size = UD2(self.NormalSize.X.Scale, self.NormalSize.X.Offset, 0, 35),
		})
		if self.MinimizeButton then
			local vertical = self.MinimizeButton:FindFirstChild("MinimizeIconVertical")
			if vertical then
				vertical.Visible = true
			end
		end
		task.delay(0.3, function()
			if self.Minimized then
				self.Pages.Visible = false
				self.Footer.Visible = false
			end
		end)
		return
	end

	self.Pages.Visible = true
	self.Footer.Visible = true
	canvas.Size = UD2(self.NormalSize.X.Scale, self.NormalSize.X.Offset, 0, 35)
	Fader.In(self.Pages, Anim.Slow)
	Fader.In(self.Footer, Anim.Slow)
	Tween(canvas, Anim.Slow, { Size = self.NormalSize })
	if self.MinimizeButton then
		local vertical = self.MinimizeButton:FindFirstChild("MinimizeIconVertical")
		if vertical then
			vertical.Visible = false
		end
	end
end

-- Removes this window only. Connections are library-wide, so they are left
-- alone here; use Callisto:Unload() to tear everything down.
function Window:Destroy()
	local index = TF(Callisto.Windows, self)
	if index then
		TR(Callisto.Windows, index)
	end
	Fader.Forget(self.Root) -- before Destroy, while ancestry is intact
	self.Root:Destroy()
end

--=============================================================================
-- CreateWindow
--=============================================================================

function Callisto:CreateWindow(options: { [string]: any }?)
	local opts: { [string]: any } = options or {}
	local size = opts.Size or V2(591, 480)
	local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local camera = workspace.CurrentCamera
	local canvas
	local function fitMobile()
		if not mobile then
			return
		end
		local viewport = camera and camera.ViewportSize or V2(800, 600)
		canvas.Size = UFO(math.max(300, viewport.X - 14), math.max(360, viewport.Y - 14))
	end
	if mobile and camera then
		size = V2(math.max(300, camera.ViewportSize.X - 14), math.max(360, camera.ViewportSize.Y - 14))
	end

	local root = Add("Folder", { Parent = GetParentGui(), Name = "Callisto" })

	local screenGui = Add("ScreenGui", {
		Parent = root,
		Enabled = true,
		Name = "Window",
		ZIndexBehavior = ZIB.Sibling,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
	})

	canvas = Add("Frame", {
		Parent = screenGui,
		Name = "Canvas",
		AnchorPoint = V2(0.5, 0.5),
		Position = UFS(0.5, 0.5),
		Size = UFO(size.X, size.Y),
		BorderSizePixel = 0,
	})
	Bind(canvas, { BackgroundColor3 = "Background" })
	Stroke(canvas, "Border")
	Shadow(canvas, 0.65)
	Corner(canvas)

	--== header ===============================================================
	local header = Add("Frame", {
		Parent = canvas,
		Name = "Header",
		Size = UD2(1, 0, 0, 35),
		ClipsDescendants = true,
		BorderSizePixel = 0,
	})
	Bind(header, { BackgroundColor3 = "Foreground" })
	Add("UICorner", { Parent = header, BottomRightRadius = UD(0, 0), BottomLeftRadius = UD(0, 0) })
	Stroke(header, "Border")
	List(header, {
		VerticalAlignment = VFA.Center,
		HorizontalFlex = UFA.SpaceBetween,
		FillDirection = FD.Horizontal,
	})
	Padding(header, 7, 7, 10, 10)
	local headerGradient = Add("UIGradient", { Parent = header, Enabled = false, Rotation = 90 })
	BindGradient(headerGradient, { { 0, "Background" }, { 1, "Foreground" } })

	local textHolder = Add("Frame", {
		Parent = header,
		Name = "TextHolder",
		BackgroundTransparency = 1,
		Size = UFS(0, 1),
		AutomaticSize = AT.X,
		BorderSizePixel = 0,
	})
	List(textHolder, { VerticalAlignment = VFA.Center, FillDirection = FD.Horizontal, Padding = UD(0, 5) })

	local title = Text(textHolder, {
		Name = "Title",
		Text = opts.Title or "Callisto",
		Size = UFS(0, 1),
		Position = UFO(10, 0),
		AutomaticSize = AT.X,
		TextSize = 17,
	})

	local buttonHolder = Add("ScrollingFrame", {
		Parent = header,
		Name = "ButtonHolder",
		BackgroundTransparency = 1,
		Size = UD2(1, -150, 0, 28),
		AutomaticSize = AT.None,
		AutomaticCanvasSize = AT.X,
		CanvasSize = UFS(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollingEnabled = true,
		ScrollBarThickness = 0,
		BorderSizePixel = 0,
	})
	buttonHolder.ClipsDescendants = true
	List(buttonHolder, {
		VerticalAlignment = VFA.Center,
		FillDirection = FD.Horizontal,
		HorizontalAlignment = HFA.Left,
		Padding = UD(0, 5),
	})

	--== body =================================================================
	local pages = Add("Frame", {
		Parent = canvas,
		Name = "Pages",
		BackgroundTransparency = 1,
		Position = UFO(10, 45),
		Size = UD2(1, -20, 1, -80),
		ClipsDescendants = true,
		BorderSizePixel = 0,
	})
	Padding(pages, 1, 1)

	--== footer ===============================================================
	local footer = Add("Frame", {
		Parent = canvas,
		AnchorPoint = V2(0, 1),
		Name = "Footer",
		Position = UFS(0, 1),
		Size = UD2(1, 0, 0, 25),
		BorderSizePixel = 0,
	})
	Bind(footer, { BackgroundColor3 = "Foreground" })
	Add("UICorner", { Parent = footer, TopRightRadius = UD(0, 0), TopLeftRadius = UD(0, 0) })
	Stroke(footer, "Border")
	local footerGradient = Add("UIGradient", { Parent = footer, Enabled = false, Rotation = -90 })
	BindGradient(footerGradient, { { 0, "Background" }, { 1, "Foreground" } })

	local footerLabel = Text(footer, {
		Text = opts.Footer or "https://discord.gg/robloxuis",
		TextTransparency = 0.5,
		Name = "Label",
		Size = UFS(0, 1),
		RichText = true,
		AutomaticSize = AT.X,
	})
	Corner(footerLabel, 5)
	Padding(footerLabel, 0, 1, 10, 10)

	local resize = Add("ImageButton", {
		Parent = footer,
		ScaleType = SCL.Fit,
		ImageTransparency = 0.5,
		Name = "Resize",
		AnchorPoint = V2(1, 0),
		Image = "rbxassetid://89501307163630",
		BackgroundTransparency = 1,
		Position = UD2(1, -3, 0, 11),
		Size = UFO(10, 10),
		ResampleMode = RSM.Pixelated,
		BorderSizePixel = 0,
	})
	Hover(resize, function(hovering)
		Tween(resize, Anim.Fast, { ImageTransparency = hovering and 0 or 0.5 })
	end)
	resize.Visible = not mobile

	--== externals (popups live above everything, outside the canvas group so
	--== they are not clipped or faded with the window) ========================
	local externals = Add("Frame", {
		Parent = screenGui,
		Name = "Externals",
		BackgroundTransparency = 1,
		Size = UFS(1, 1),
		ZIndex = 100,
		BorderSizePixel = 0,
	})

	local window: any = setmetatable({
		Root = root,
		ScreenGui = screenGui,
		Canvas = canvas,
		Header = header,
		Title = title,
		ButtonHolder = buttonHolder,
		Pages = pages,
		Footer = footer,
		Externals = externals,
		PageList = {},
		CurrentPage = nil,
		Visible = true,
		Minimized = false,
		NormalSize = canvas.Size,
		HomePosition = nil,
		Mobile = mobile,
	}, Window)

	local controls = Add("Frame", {
		Parent = canvas,
		Name = "WindowControls",
		AnchorPoint = V2(1, 0),
		Position = UD2(1, -7, 0, 6),
		Size = UFO(28, 24),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 100,
	})

	local minimizeButton = Text(controls, {
		ClassName = "TextButton",
		Name = "Minimize",
		Text = "",
		TextSize = 19,
		TextXAlignment = TXA.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextTransparency = 0.25,
		BackgroundTransparency = 0.1,
		Size = UFO(24, 22),
		Position = UFS(0, 0),
		Active = true,
		Selectable = false,
		AutoButtonColor = false,
		ZIndex = 101,
	})
	Bind(minimizeButton, { TextColor3 = "Text" })
	Bind(minimizeButton, { BackgroundColor3 = "Foreground" })
	SurfaceGradient(minimizeButton)
	Corner(minimizeButton, 4)
	local minimizeLine = Add("Frame", {
		Parent = minimizeButton,
		Name = "MinimizeIconLine",
		AnchorPoint = V2(0.5, 0.5),
		Position = UFS(0.5, 0, 0.5, 0),
		Size = UFO(12, 2),
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		BorderSizePixel = 0,
		ZIndex = 102,
	})
	Bind(minimizeLine, { BackgroundColor3 = "Text" })
	local minimizeVertical = Add("Frame", {
		Parent = minimizeButton,
		Name = "MinimizeIconVertical",
		AnchorPoint = V2(0.5, 0.5),
		Position = UFS(0.5, 0, 0.5, 0),
		Size = UFO(2, 12),
		BackgroundColor3 = Color3.fromRGB(245, 245, 245),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 102,
	})
	Bind(minimizeVertical, { BackgroundColor3 = "Text" })
	local minimizeStroke = Stroke(minimizeButton, "Border", true)
	Hover(minimizeButton, function(hovering)
		Tween(minimizeStroke, Anim.Fast, { Color = hovering and Callisto.Theme.Accent or Callisto.Theme.Border })
		Tween(minimizeButton, Anim.Fast, { TextTransparency = hovering and 0 or 0.25 })
	end)
	Connect(minimizeButton.MouseButton1Click, function()
		window:Minimize()
	end)
	window.MinimizeButton = minimizeButton

	MakeDraggable(header, canvas)
	MakeResizable(resize, canvas, opts.MinSize or (mobile and V2(300, 360) or V2(420, 320)), function(newSize)
		if not window.Minimized then
			window.NormalSize = newSize
		end
	end)
	if mobile then
		Connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
			fitMobile()
			if not window.Minimized then
				window.NormalSize = canvas.Size
			end
		end)
	end

	-- open/close keybind
	local toggleKey = opts.Keybind or EKC.RightShift
	Connect(UserInputService.InputBegan, function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == UIT.Keyboard and input.KeyCode == toggleKey then
			window:Toggle()
		end
	end)

	-- entrance: capture the freshly-built shell, park it transparent, then
	-- fade + slide up into place; the size never animates
	local home = canvas.Position
	Fader.Out(canvas, TI(0))
	canvas.Position = home + UD2(0, 0, 0, 12)
	Tween(canvas, Anim.Slow, { Position = home })
	Fader.In(canvas, Anim.Slow)

	TIS(Callisto.Windows, window)
	return window
end

-- Full teardown: every window, every connection, every theme registration.
function Callisto:Unload()
	if ThemeTransition then
		ThemeTransition:Disconnect()
		ThemeTransition = nil
	end

	for _, connection in next, self.Connections do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(self.Connections)

	for index = #self.Windows, 1, -1 do
		self.Windows[index].Root:Destroy()
		self.Windows[index] = nil
	end

	table.clear(ColorRegistry)
	table.clear(GradientRegistry)
	table.clear(self.Flags)
	Fader.Clear()
end

return Callisto

end)()

--=============================================================================
-- punishuilib API adapter over Callisto
-- Lets the angeli feature code run unchanged on the Callisto UI.
--=============================================================================

local Library = {}
Library.__index = Library
local TweenService = game:GetService("TweenService")

local function GetParentGui()
	local ok, hui = pcall(function()
		return (getfenv().gethui)()
	end)
	if ok and hui then
		return hui
	end
	local success, core = pcall(function()
		return game:GetService("CoreGui")
	end)
	return (success and core) or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local ToastGui

local function Notify(opts)
	opts = opts or {}
	local duration = opts.Duration or 3
	local title = opts.Title or "angeli"
	local content = opts.Content or ""

	if not ToastGui then
		ToastGui = Instance.new("ScreenGui")
		ToastGui.Name = "AngeliToasts"
		ToastGui.ResetOnSpawn = false
		ToastGui.IgnoreGuiInset = true
		ToastGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		ToastGui.DisplayOrder = 1000
		ToastGui.Parent = GetParentGui()
	end

	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(24, 26, 27)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(1, 0)
	frame.Position = UDim2.new(1, -10, 0, 10)
	frame.Size = UDim2.new(0, 220, 0, 70)
	frame.Parent = ToastGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(45, 48, 49)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.BorderSizePixel = 0
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = title
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 14
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Size = UDim2.new(1, -14, 0, 18)
	titleLabel.Position = UDim2.new(0, 7, 0, 6)
	titleLabel.Parent = frame

	local body = Instance.new("TextLabel")
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.Font = Enum.Font.Gotham
	body.Text = content
	body.TextColor3 = Color3.fromRGB(205, 205, 205)
	body.TextSize = 13
	body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.Size = UDim2.new(1, -14, 0, 40)
	body.Position = UDim2.new(0, 7, 0, 24)
	body.Parent = frame

	local ts = game:GetService("TweenService")
	ts:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0.05 }):Play()

	task.spawn(function()
		task.wait(duration)
		ts:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		task.wait(0.3)
		if frame.Parent then
			frame:Destroy()
		end
	end)
end

function Library:Notify(opts)
	Notify(opts)
end

--=============================================================================
-- Window adapter
--=============================================================================

local WindowAdapter = {}
WindowAdapter.__index = WindowAdapter

local TabAdapter = {}
TabAdapter.__index = TabAdapter

local DropdownAdapter = {}
DropdownAdapter.__index = DropdownAdapter

local function MakeInfoSectionCollapsible(section, title)
	local normalized = string.lower(title or "")
	local collapsible = normalized == "credits"
		or normalized == "changelog"
		or normalized == "important"
		or string.find(normalized, "info", 1, true) ~= nil
		or normalized == "note"

	if not collapsible then
		return
	end

	local open = true
	local transitioning = false
	local header = section.Instance:FindFirstChild("Header")
	if not header then
		return
	end

	header.Active = true

	local hitbox = Instance.new("TextButton")
	hitbox.Name = "CollapseButton"
	hitbox.BackgroundTransparency = 1
	hitbox.BorderSizePixel = 0
	hitbox.Text = ""
	hitbox.AutoButtonColor = false
	hitbox.Size = UDim2.new(1, 0, 0, 25)
	hitbox.ZIndex = 10
	hitbox.Parent = section.Instance

	local arrow = Instance.new("TextLabel")
	arrow.Name = "CollapseIndicator"
	arrow.BackgroundTransparency = 1
	arrow.BorderSizePixel = 0
	arrow.Font = Enum.Font.GothamBold
	arrow.Text = "-"
	arrow.TextColor3 = Color3.fromRGB(180, 180, 180)
	arrow.TextSize = 16
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.Size = UDim2.new(0, 24, 0, 25)
	arrow.Position = UDim2.new(1, -28, 0, 0)
	arrow.ZIndex = 11
	arrow.Parent = hitbox

	local transparencyProperties = {
		Frame = { "BackgroundTransparency" },
		TextLabel = { "TextTransparency" },
		TextButton = { "TextTransparency" },
		TextBox = { "TextTransparency" },
		ImageLabel = { "ImageTransparency" },
		ImageButton = { "ImageTransparency" },
		UIStroke = { "Transparency" },
	}
	local rest
	local function captureRest()
		if rest then
			return
		end
		rest = {}
		for _, object in ipairs(section.Content:GetDescendants()) do
			local properties = transparencyProperties[object.ClassName]
			if properties then
				for _, property in ipairs(properties) do
					local value = object[property]
					if type(value) == "number" then
						table.insert(rest, { Object = object, Property = property, Value = value })
					end
				end
			end
		end
	end

	local function animateContent(show)
		if transitioning then
			return
		end
		transitioning = true
		captureRest()

		if show then
			section.Content.Visible = true
			for _, entry in ipairs(rest) do
				if entry.Object.Parent then
					entry.Object[entry.Property] = 1
					TweenService:Create(entry.Object, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						[entry.Property] = entry.Value,
					}):Play()
				end
			end
			task.delay(0.22, function()
				transitioning = false
			end)
			return
		end

		for _, entry in ipairs(rest) do
			if entry.Object.Parent then
				TweenService:Create(entry.Object, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					[entry.Property] = 1,
				}):Play()
			end
		end
		task.delay(0.22, function()
			if not open then
				section.Content.Visible = false
			end
			transitioning = false
		end)
	end

	hitbox.MouseButton1Click:Connect(function()
		open = not open
		arrow.Text = open and "-" or "+"
		animateContent(open)
	end)
end

function Library:CreateWindow(title)
	local window = Callisto:CreateWindow({
		Title = title,
		Size = Vector2.new(900, 650),
		MinSize = Vector2.new(700, 480),
		Keybind = Enum.KeyCode.None,
		Footer = "discord.gg/q2ZvgAxsre",
	})

	local adapter = setmetatable({
		Window = window,
		Tabs = {},
		ToggleKey = Enum.KeyCode.LeftControl,
	}, WindowAdapter)

	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == adapter.ToggleKey then
			window:Toggle()
		end
	end)

	return adapter
end

function WindowAdapter:CreateTab(name)
	local page = self.Window:AddPage(name)
	local adapter = setmetatable({
		Page = page,
		CurrentSection = nil,
		Window = self,
		SectionCount = 0,
	}, TabAdapter)
	table.insert(self.Tabs, adapter)
	return adapter
end

function WindowAdapter:Toggle()
	self.Window:Toggle()
end

function WindowAdapter:SetKeybind(key)
	if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
		self.ToggleKey = key
	elseif type(key) == "string" then
		local resolved = Enum.KeyCode[key]
		if resolved then
			self.ToggleKey = resolved
		end
	end
end

--=============================================================================
-- Tab adapter
--=============================================================================

function TabAdapter:CreateSection(name)
	self.SectionCount += 1
	local side = self.SectionCount % 2 == 0 and "Right" or "Left"
	local section = self.Page:AddSection(side, name)
	self.CurrentSection = section
	MakeInfoSectionCollapsible(section, name)
	return section
end

function TabAdapter:CreateToggle(title, desc, default, callback)
	return self.CurrentSection:AddToggle({
		Title = title,
		Default = default or false,
		Callback = callback or function() end,
	})
end

function TabAdapter:CreateButton(title, desc, image, callback)
	return self.CurrentSection:AddButton({
		Title = title,
		Callback = callback or function() end,
	})
end

function TabAdapter:CreateLabel(text)
	return self.CurrentSection:AddLabel(text or "")
end

function TabAdapter:CreateParagraph(title, content)
	self.CurrentSection:AddLabel(title or "")
	local last
	for line in ((content or "") .. "\n"):gmatch("(.-)\n") do
		last = self.CurrentSection:AddLabel(line)
	end
	return last
end

function TabAdapter:CreateImageParagraph(title, content, image)
	return self:CreateParagraph(title, content)
end

function TabAdapter:CreateSlider(name, minimum, maximum, default, callback)
	return self.CurrentSection:AddSlider({
		Title = name,
		Min = minimum,
		Max = maximum,
		Default = default or minimum,
		Suffix = "",
		Callback = callback or function() end,
	})
end

function TabAdapter:CreateInput(name, desc, placeholder, hidden, max, callback)
	return self.CurrentSection:AddInput({
		Title = name,
		Placeholder = placeholder or "enter value",
		Callback = callback or function() end,
	})
end

function TabAdapter:CreateKeybind(name, desc, default, callback)
	local key = default
	if type(default) == "string" then
		key = Enum.KeyCode[default]
	end
	return self.CurrentSection:AddKeybind({
		Title = name,
		Default = key,
		Callback = function() end,
		OnChanged = callback or function() end,
	})
end

function TabAdapter:CreateDivider()
	local section = self.CurrentSection
	if not section then
		return
	end
	local line = Instance.new("Frame")
	line.BackgroundColor3 = Color3.fromRGB(45, 48, 49)
	line.BorderSizePixel = 0
	line.Size = UDim2.new(1, 0, 0, 1)
	line.LayoutOrder = 9999
	line.Parent = section.Content
	return line
end

function TabAdapter:CreateDropdown(name)
	local options = {}
	local control = self.CurrentSection:AddDropdown({
		Title = name,
		Values = {},
		Callback = function(value)
			for _, option in ipairs(options) do
				if option.Title == value then
					option.Callback()
				end
			end
		end,
	})
	local adapter = setmetatable({
		Options = options,
		Control = control,
	}, DropdownAdapter)
	return adapter
end

--=============================================================================
-- Dropdown adapter
--=============================================================================

function DropdownAdapter:CreateButton(title, desc, image, callback)
	table.insert(self.Options, {
		Title = title,
		Callback = callback or function() end,
	})
	local values = {}
	for _, option in ipairs(self.Options) do
		table.insert(values, option.Title)
	end
	self.Control:Refresh(values)
	return self
end


--=============================================================================
-- punishuilib-backed adapter
-- Keep the existing feature-facing API, but let punishuilib own the visuals.
--=============================================================================

local PunishUILib = (function()
local punishgoatby97mzu = {
	Instances = {},
	ThemeChangedHooks = {},
	CurrentTheme = "punishgoat",
	Themes = {
		punishgoat = {
    MainBg = Color3.fromRGB(15, 15, 15),
    Stroke = Color3.fromRGB(70, 70, 70),
    Accent = Color3.fromRGB(40, 40, 40),
    Accentpunish = Color3.fromRGB(230, 230, 230),
    Text = Color3.fromRGB(220, 220, 220),
    TextInactive = Color3.fromRGB(255, 255, 255),
    ToggleBgOff = Color3.fromRGB(50, 50, 50),
    ToggleBtnBg = Color3.fromRGB(35, 35, 35), 
    ToggleDot = Color3.fromRGB(200, 200, 200),
    SectionTitle = Color3.fromRGB(160, 160, 160),
},
	},
}
 
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
 
function punishgoatby97mzu:ApplyThemeObj(Inst, Prop, ThemeType)
	table.insert(self.Instances, { Inst = Inst, Prop = Prop, Type = ThemeType })
	local palette = self.Themes[self.CurrentTheme]
	Inst[Prop] = palette[ThemeType]
	return Inst
end
 
function punishgoatby97mzu:ChangeTheme(ThemeName)
	self.CurrentTheme = ThemeName
	local palette = self.Themes[ThemeName]
	for _, obj in pairs(self.Instances) do
		if obj.Inst and obj.Inst.Parent then
			TweenService:Create(obj.Inst, TweenInfo.new(0.3), { [obj.Prop] = palette[obj.Type] }):Play()
		end
	end
 
	for _, hook in pairs(self.ThemeChangedHooks) do
		if hook.Inst and hook.Inst.Parent then
			hook.Func(ThemeName)
		end
	end
end
 
local NotifUI = Instance.new("ScreenGui")
NotifUI.Name = "punishgoatNotifUI"
NotifUI.ResetOnSpawn = false
NotifUI.IgnoreGuiInset = true
-- Set the highest DisplayOrder so notification cards never get covered by the game's HUD
NotifUI.DisplayOrder = 99999
NotifUI.Parent = LocalPlayer:WaitForChild("PlayerGui")
 
local NotifContainer = Instance.new("Frame", NotifUI)
NotifContainer.Name = "NotifContainer"
NotifContainer.Size = UDim2.new(0, 260, 1, -20)
NotifContainer.Position = UDim2.new(1, -20, 0, 10)
NotifContainer.AnchorPoint = Vector2.new(1, 0)
NotifContainer.BackgroundTransparency = 1
NotifContainer.ZIndex = 1000
 
local NotifLayout = Instance.new("UIListLayout", NotifContainer)
NotifLayout.SortOrder = Enum.SortOrder.LayoutOrder
NotifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
NotifLayout.Padding = UDim.new(0, 10)
 
function punishgoatby97mzu:Notify(Data)
	local TitleStr = Data.Title or "Notification"
	local ContentStr = Data.Content or "Description here"
	local Duration = Data.Duration or 3
 
	local NCard = Instance.new("Frame", NotifContainer)
	NCard.Size = UDim2.new(1, 0, 0, 60)
	NCard.Position = UDim2.new(1, 300, 0, 0)
	NCard.BackgroundTransparency = 0.15
	NCard.ClipsDescendants = true
	NCard.ZIndex = 1001
	Instance.new("UICorner", NCard).CornerRadius = UDim.new(0, 8)
	punishgoatby97mzu:ApplyThemeObj(NCard, "BackgroundColor3", "ToggleBtnBg")
 
	local NStroke = Instance.new("UIStroke", NCard)
	NStroke.Thickness = 1
	NStroke.Transparency = 0.5
	punishgoatby97mzu:ApplyThemeObj(NStroke, "Color", "Stroke")
 
	local NIcon = Instance.new("ImageLabel", NCard)
	NIcon.Size = UDim2.new(0, 24, 0, 24)
	NIcon.Position = UDim2.new(0, 15, 0.5, -12)
	NIcon.BackgroundTransparency = 1
	NIcon.Image = "rbxassetid://10709771426"
	NIcon.ZIndex = 1002
	punishgoatby97mzu:ApplyThemeObj(NIcon, "ImageColor3", "Accent")
 
	local NTitle = Instance.new("TextLabel", NCard)
	NTitle.Size = UDim2.new(1, -55, 0, 18)
	NTitle.Position = UDim2.new(0, 50, 0, 10)
	NTitle.BackgroundTransparency = 1
	NTitle.Text = TitleStr
	NTitle.Font = Enum.Font.GothamBold
	NTitle.TextSize = 13
	NTitle.TextXAlignment = Enum.TextXAlignment.Left
	NTitle.ZIndex = 1002
	punishgoatby97mzu:ApplyThemeObj(NTitle, "TextColor3", "Text")
 
	local NDesc = Instance.new("TextLabel", NCard)
	NDesc.Size = UDim2.new(1, -55, 1, -30)
	NDesc.Position = UDim2.new(0, 50, 0, 28)
	NDesc.BackgroundTransparency = 1
	NDesc.Text = ContentStr
	NDesc.Font = Enum.Font.Gotham
	NDesc.TextSize = 11
	NDesc.TextWrapped = true
	NDesc.TextYAlignment = Enum.TextYAlignment.Top
	NDesc.TextXAlignment = Enum.TextXAlignment.Left
	NDesc.ZIndex = 1002
	punishgoatby97mzu:ApplyThemeObj(NDesc, "TextColor3", "TextInactive")
 
	local NBarBg = Instance.new("Frame", NCard)
	NBarBg.Size = UDim2.new(1, 0, 0, 3)
	NBarBg.Position = UDim2.new(0, 0, 1, -3)
	NBarBg.BorderSizePixel = 0
	NBarBg.ZIndex = 1002
	punishgoatby97mzu:ApplyThemeObj(NBarBg, "BackgroundColor3", "MainBg")
 
	local NBarFill = Instance.new("Frame", NBarBg)
	NBarFill.Size = UDim2.new(1, 0, 1, 0)
	NBarFill.BorderSizePixel = 0
	NBarFill.ZIndex = 1002
	punishgoatby97mzu:ApplyThemeObj(NBarFill, "BackgroundColor3", "Accent")
 
	TweenService:Create(
		NCard,
		TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 0, 0, 0) }
	):Play()
	TweenService:Create(NBarFill, TweenInfo.new(Duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 1, 0) })
		:Play()
 
	task.delay(Duration, function()
		local OutAnim = TweenService:Create(
			NCard,
			TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
			{ Position = UDim2.new(1, 300, 0, 0) }
		)
		OutAnim:Play()
		OutAnim.Completed:Wait()
		NCard:Destroy()
	end)
end
 
-- This is the "brain" that stores UI state for as long as the script is running
local UI_Session = {
    Pos = UDim2.new(0.5, 0, 0.5, 0), -- Default ke tengah
    Size = UDim2.new(0, 600, 0, 400), -- Default ukuran
}
 function punishgoatby97mzu:CreateWindow(TitleText)
    local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

    -- Se já existir uma instância antiga, destrói
    local oldUI = PlayerGui:FindFirstChild("punishgoatUI")
    if oldUI then
        oldUI:Destroy()
    end

    local Window = { Tabs = {}, SelectCloseFuncs = {}, DropdownCloseFuncs = {}, CurrentTab = nil, Visible = true }
 
    local punishgoatUI = Instance.new("ScreenGui")
    punishgoatUI.Name = "punishgoatUI"
    punishgoatUI.ResetOnSpawn = false
    punishgoatUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    punishgoatUI.IgnoreGuiInset = true
    punishgoatUI.DisplayOrder = 99999 
    punishgoatUI.Parent = PlayerGui
 
    local Main = Instance.new("Frame")
    local currentSize = UDim2.new(0, 600, 0, 400)

    Window.ScreenGui = punishgoatUI
    Window.Main = Main

    function Window:Toggle(state)
        if state ~= nil then
            self.Visible = state
        else
            self.Visible = not self.Visible
        end
        if punishgoatUI then
            punishgoatUI.Enabled = self.Visible
        end
        if Main then
            Main.Visible = self.Visible
        end
    end
 
    local Camera = workspace.CurrentCamera
    local Viewport = Camera and Camera.ViewportSize or Vector2.new(1000, 1000)
    local scaleX = Viewport.X / 640
    local scaleY = Viewport.Y / 440
    local initialScale = math.clamp(math.min(scaleX, scaleY, 1), 0.38, 1)
    local initialYOffset = (Viewport.Y / 2) - (400 * initialScale / 2)
    local currentPos = UDim2.new(0.5, 0, 0, initialYOffset)
 
    Main.Name = "Main"
    Main.Size = UDim2.new(0, 600, 0, 400)
    Main.AnchorPoint = Vector2.new(0.5, 0) 
    Main.Position = currentPos
    Main.BackgroundTransparency = 0.02
    Main.BorderSizePixel = 0
    Main.ClipsDescendants = true
    Main.ZIndex = 10
    Main.Parent = punishgoatUI
    punishgoatby97mzu:ApplyThemeObj(Main, "BackgroundColor3", "MainBg")
 
	local MainScale = Instance.new("UIScale")
	MainScale.Name = "punishgoatAutoScaler"
	MainScale.Parent = Main
 
	local function ScaleUI()
            local Camera = workspace.CurrentCamera
            if not Camera then
                return
            end
            local Viewport = Camera.ViewportSize
 
local maxWidth = 600 + 40
local maxHeight = 400 + 40
 
            local scaleX = Viewport.X / maxWidth
            local scaleY = Viewport.Y / maxHeight
 
            local finalScale = math.min(scaleX, scaleY, 1)
 
            -- Clamp the minimum scale to 0.38 so it still fits on short phone screens
            MainScale.Scale = math.clamp(finalScale, 0.38, 1)
        end
 
	ScaleUI()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ScaleUI)
 
 
	local MainCorner = Instance.new("UICorner", Main)
	MainCorner.CornerRadius = UDim.new(0, 8)
 
	local MainStroke = Instance.new("UIStroke", Main)
	MainStroke.Thickness = 1
	MainStroke.Transparency = 0.5
	MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	punishgoatby97mzu:ApplyThemeObj(MainStroke, "Color", "Stroke")
 
	local TopBar = Instance.new("Frame", Main)
	TopBar.Name = "TopBar"
	TopBar.Size = UDim2.new(1, 0, 0, 30)
	TopBar.BackgroundTransparency = 1
	TopBar.ZIndex = 50
 
	local TopBarPadding = Instance.new("UIPadding", TopBar)
	TopBarPadding.PaddingLeft = UDim.new(0, 15)
	TopBarPadding.PaddingRight = UDim.new(0, 15)
 
	local Title = Instance.new("TextLabel", TopBar)
	Title.Name = "Title"
	Title.Size = UDim2.new(0.5, 0, 1, 0)
	Title.BackgroundTransparency = 1
	Title.Text = TitleText or "punishgoat Hub | V6 God Tier"
	Title.Font = Enum.Font.GothamBold
	Title.TextSize = 15
	Title.TextXAlignment = Enum.TextXAlignment.Left
	Title.ZIndex = 51
	punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
	local dragging, dragInput, dragStart, startPos
	TopBar.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			dragStart = input.Position
			startPos = Main.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	TopBar.InputChanged:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragInput = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			Main.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			currentPos = Main.Position -- 🔥 TIMPA: Simpan posisi terbaru setiap kali UI digeser
		end
	end)
 
	local ControlContainer = Instance.new("Frame", TopBar)
	ControlContainer.Name = "ControlContainer"
	ControlContainer.Size = UDim2.new(0.5, 0, 1, 0)
	ControlContainer.AnchorPoint = Vector2.new(1, 0)
	ControlContainer.Position = UDim2.new(1, 0, 0, 0)
	ControlContainer.BackgroundTransparency = 1
	ControlContainer.ZIndex = 51
 
	local ControlLayout = Instance.new("UIListLayout", ControlContainer)
	ControlLayout.FillDirection = Enum.FillDirection.Horizontal
	ControlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	ControlLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	ControlLayout.Padding = UDim.new(0, 10)
	ControlLayout.SortOrder = Enum.SortOrder.LayoutOrder
 
	local MinimizeBtn = Instance.new("ImageButton", ControlContainer)
	MinimizeBtn.Size = UDim2.new(0, 18, 0, 18)
	MinimizeBtn.BackgroundTransparency = 1
	MinimizeBtn.LayoutOrder = 2
	MinimizeBtn.Image = "rbxassetid://10734896206"
	MinimizeBtn.ZIndex = 51
	punishgoatby97mzu:ApplyThemeObj(MinimizeBtn, "ImageColor3", "Text")

 
	local CloseBtn = Instance.new("ImageButton", ControlContainer)
	CloseBtn.Size = UDim2.new(0, 18, 0, 18)
	CloseBtn.BackgroundTransparency = 1
	CloseBtn.LayoutOrder = 4
	CloseBtn.Image = "rbxassetid://10747384394"
	CloseBtn.ZIndex = 51
	punishgoatby97mzu:ApplyThemeObj(CloseBtn, "ImageColor3", "Text")
 
	local function ApplyHover(btn, hoverColor)
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.2), { ImageColor3 = hoverColor }):Play()
		end)
		btn.MouseLeave:Connect(function()
			local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
			TweenService:Create(btn, TweenInfo.new(0.2), { ImageColor3 = palette.Text }):Play()
		end)
	end
	ApplyHover(MinimizeBtn, Color3.fromRGB(250, 154, 50))
	ApplyHover(CloseBtn, Color3.fromRGB(255, 54, 54))
 
	local ProfileCard
 
	local isMinimized = false
	local preMinSize = Main.Size
	local preMinPos = Main.Position
	local isMinTweening = false
 
MinimizeBtn.MouseButton1Click:Connect(function()
    if isMinTweening then return end
    isMinTweening = true
    isMinimized = not isMinimized
 
    if isMinimized then
        if Sidebar then Sidebar.Visible = false end
        if ContentContainer then ContentContainer.Visible = false end
        if SidebarDivider then SidebarDivider.Visible = false end
        if ResizeGrip then ResizeGrip.Visible = false end
        if ThemePanel then ThemePanel.Visible = false end
        if ProfileCard then ProfileCard.Visible = false end
    else
        if Sidebar then Sidebar.Visible = true end
        if ContentContainer then ContentContainer.Visible = true end
        if SidebarDivider then SidebarDivider.Visible = true end
        if ResizeGrip then ResizeGrip.Visible = true end
        if ProfileCard then ProfileCard.Visible = true end
    end
 
    -- Use currentSize as the target height when un-minimizing
    local targetHeight = isMinimized and 30 or currentSize.Y.Offset
    
    TweenService:Create(Main, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset, 0, targetHeight)
    }):Play()
 
    task.delay(0.4, function() isMinTweening = false end)
end)

 
	local ModalOverlay = Instance.new("Frame", Main)
	ModalOverlay.Size = UDim2.new(1, 0, 1, 0)
	ModalOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	ModalOverlay.BackgroundTransparency = 1
	ModalOverlay.Visible = false
	ModalOverlay.ZIndex = 998
 
	local ModalBox = Instance.new("Frame", ModalOverlay)
	ModalBox.Size = UDim2.new(0, 300, 0, 150)
	ModalBox.AnchorPoint = Vector2.new(0.5, 0.5)
	ModalBox.Position = UDim2.new(0.5, 0, 0.5, 20)
	ModalBox.BackgroundTransparency = 1
	ModalBox.ZIndex = 999
	Instance.new("UICorner", ModalBox).CornerRadius = UDim.new(0, 10)
	punishgoatby97mzu:ApplyThemeObj(ModalBox, "BackgroundColor3", "MainBg")
 
	local ModalStroke = Instance.new("UIStroke", ModalBox)
	ModalStroke.Thickness = 1
	ModalStroke.Transparency = 1
	punishgoatby97mzu:ApplyThemeObj(ModalStroke, "Color", "Stroke")
 
	local ModalTitle = Instance.new("TextLabel", ModalBox)
	ModalTitle.Size = UDim2.new(1, 0, 0, 40)
	ModalTitle.BackgroundTransparency = 1
	ModalTitle.Text = "Exit punishgoat Hub?"
	ModalTitle.Font = Enum.Font.GothamBold
	ModalTitle.TextSize = 16
	ModalTitle.TextTransparency = 1
	ModalTitle.ZIndex = 999
	punishgoatby97mzu:ApplyThemeObj(ModalTitle, "TextColor3", "Text")
 
	local ModalDesc = Instance.new("TextLabel", ModalBox)
	ModalDesc.Size = UDim2.new(1, -40, 0, 40)
	ModalDesc.Position = UDim2.new(0, 20, 0, 40)
	ModalDesc.BackgroundTransparency = 1
	ModalDesc.Text = "Are you sure you want to exit? You will need to re-execute the script."
	ModalDesc.TextWrapped = true
	ModalDesc.Font = Enum.Font.Gotham
	ModalDesc.TextSize = 12
	ModalDesc.TextTransparency = 1
	ModalDesc.ZIndex = 999
	punishgoatby97mzu:ApplyThemeObj(ModalDesc, "TextColor3", "TextInactive")
 
	local CancelBtn = Instance.new("TextButton", ModalBox)
	CancelBtn.Size = UDim2.new(0, 110, 0, 36)
	CancelBtn.Position = UDim2.new(0, 30, 1, -50)
	CancelBtn.Text = "Cancel"
	CancelBtn.Font = Enum.Font.GothamMedium
	CancelBtn.TextSize = 13
	CancelBtn.AutoButtonColor = false
	CancelBtn.BackgroundTransparency = 1
	CancelBtn.TextTransparency = 1
	CancelBtn.ZIndex = 999
	Instance.new("UICorner", CancelBtn).CornerRadius = UDim.new(0, 6)
	punishgoatby97mzu:ApplyThemeObj(CancelBtn, "BackgroundColor3", "ToggleBgOff")
	punishgoatby97mzu:ApplyThemeObj(CancelBtn, "TextColor3", "Text")
 
	local ConfirmBtn = Instance.new("TextButton", ModalBox)
	ConfirmBtn.Size = UDim2.new(0, 110, 0, 36)
	ConfirmBtn.Position = UDim2.new(1, -140, 1, -50)
	ConfirmBtn.Text = "Yes, Exit"
	ConfirmBtn.Font = Enum.Font.GothamMedium
	ConfirmBtn.TextSize = 13
	ConfirmBtn.AutoButtonColor = false
	ConfirmBtn.BackgroundTransparency = 1
	ConfirmBtn.TextTransparency = 1
	ConfirmBtn.ZIndex = 999
	Instance.new("UICorner", ConfirmBtn).CornerRadius = UDim.new(0, 6)
	punishgoatby97mzu:ApplyThemeObj(ConfirmBtn, "BackgroundColor3", "Accent")
	ConfirmBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
 
	CloseBtn.MouseButton1Click:Connect(function()
		ModalOverlay.Visible = true
		TweenService:Create(ModalOverlay, TweenInfo.new(0.3), { BackgroundTransparency = 0.5 }):Play()
		TweenService:Create(
			ModalBox,
			TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundTransparency = 0 }
		):Play()
		TweenService:Create(ModalStroke, TweenInfo.new(0.3), { Transparency = 0.5 }):Play()
		TweenService:Create(ModalTitle, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		TweenService:Create(ModalDesc, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		TweenService:Create(CancelBtn, TweenInfo.new(0.3), { BackgroundTransparency = 0, TextTransparency = 0 }):Play()
		TweenService:Create(ConfirmBtn, TweenInfo.new(0.3), { BackgroundTransparency = 0.2, TextTransparency = 0 })
			:Play()
	end)
 
	CancelBtn.MouseButton1Click:Connect(function()
		TweenService:Create(ModalOverlay, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(
			ModalBox,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, 0.5, 20), BackgroundTransparency = 1 }
		):Play()
		TweenService:Create(ModalStroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		TweenService:Create(ModalTitle, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(ModalDesc, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		TweenService:Create(CancelBtn, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		TweenService:Create(ConfirmBtn, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		task.wait(0.3)
		ModalOverlay.Visible = false
	end)
 
	ConfirmBtn.MouseButton1Click:Connect(function()
		TweenService:Create(
			Main,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In),
			{ Size = UDim2.new(0, 0, 0, 0) }
		):Play()
		TweenService:Create(FloatingBtn, TweenInfo.new(0.3), { Size = UDim2.new(0, 0, 0, 0) }):Play()
		task.wait(0.3)
		punishgoatUI:Destroy()
	end)
 
local ResizeGrip = Instance.new("ImageButton", Main)
ResizeGrip.Size = UDim2.new(0, 20, 0, 20)
ResizeGrip.Position = UDim2.new(1, 0, 1, 0)
ResizeGrip.AnchorPoint = Vector2.new(1, 1)
ResizeGrip.BackgroundTransparency = 1
ResizeGrip.Image = "rbxassetid://83865456239149"
ResizeGrip.ZIndex = 100
	local resizing, rDragStart, startSize
	ResizeGrip.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if isMinimized or isMaximized then
				return
			end
			resizing = true
			rDragStart = input.Position
			startSize = Main.Size
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					resizing = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			resizing
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local delta = input.Position - rDragStart
local newX = math.clamp(startSize.X.Offset + delta.X, 400, 1000)
local newY = math.clamp(startSize.Y.Offset + delta.Y, 300, 800)
			Main.Size = UDim2.new(0, newX, 0, newY)
			currentSize = Main.Size
		end
	end)
 
	local Sidebar = Instance.new("ScrollingFrame", Main)
	Sidebar.Name = "Sidebar"
	Sidebar.Size = UDim2.new(0, 180, 1, -95)
	Sidebar.Position = UDim2.new(0, 0, 0, 30)
	Sidebar.BackgroundTransparency = 1
	Sidebar.BorderSizePixel = 0
	Sidebar.ScrollBarThickness = 0
	Sidebar.CanvasSize = UDim2.new(0, 0, 0, 0)
	Sidebar.AutomaticCanvasSize = Enum.AutomaticSize.Y
	Sidebar.ClipsDescendants = true
 
	local SidebarPadding = Instance.new("UIPadding", Sidebar)
	SidebarPadding.PaddingTop = UDim.new(0, 10)
	SidebarPadding.PaddingBottom = UDim.new(0, 10)
	SidebarPadding.PaddingLeft = UDim.new(0, 10)
	SidebarPadding.PaddingRight = UDim.new(0, 10)
 
	local SidebarLayout = Instance.new("UIListLayout", Sidebar)
	SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
	SidebarLayout.Padding = UDim.new(0, 5)
 
	local SidebarDivider = Instance.new("Frame", Main)
	SidebarDivider.Name = "SidebarDivider"
	SidebarDivider.Size = UDim2.new(0, 1, 1, -80)
	SidebarDivider.AnchorPoint = Vector2.new(0, 0.5)
	SidebarDivider.Position = UDim2.new(0, 180, 0.5, 15)
	SidebarDivider.BackgroundTransparency = 0.7
	SidebarDivider.BorderSizePixel = 0
	punishgoatby97mzu:ApplyThemeObj(SidebarDivider, "BackgroundColor3", "Stroke")
 
	ProfileCard = Instance.new("Frame", Main)
	ProfileCard.Size = UDim2.new(0, 160, 0, 50)
	ProfileCard.Position = UDim2.new(0, 10, 1, -60)
	ProfileCard.BackgroundTransparency = 0.55
	Instance.new("UICorner", ProfileCard).CornerRadius = UDim.new(0, 8)
	punishgoatby97mzu:ApplyThemeObj(ProfileCard, "BackgroundColor3", "ToggleBtnBg")
 
	local ProfStroke = Instance.new("UIStroke", ProfileCard)
	ProfStroke.Transparency = 0.85
	punishgoatby97mzu:ApplyThemeObj(ProfStroke, "Color", "Stroke")
 
	local AvatarImg = Instance.new("ImageLabel", ProfileCard)
	AvatarImg.Size = UDim2.new(0, 36, 0, 36)
	AvatarImg.Position = UDim2.new(0, 7, 0.5, -18)
	AvatarImg.BackgroundTransparency = 1
	AvatarImg.Image = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=150&h=150"
	Instance.new("UICorner", AvatarImg).CornerRadius = UDim.new(1, 0)
 
	local PlayerName = Instance.new("TextLabel", ProfileCard)
	PlayerName.Size = UDim2.new(1, -105, 0, 16)
	PlayerName.Position = UDim2.new(0, 50, 0, 8)
	PlayerName.BackgroundTransparency = 1
	PlayerName.Text = LocalPlayer.Name
	PlayerName.Font = Enum.Font.GothamBold
	PlayerName.TextSize = 12
	PlayerName.TextXAlignment = Enum.TextXAlignment.Left
	PlayerName.TextTruncate = Enum.TextTruncate.AtEnd
	punishgoatby97mzu:ApplyThemeObj(PlayerName, "TextColor3", "Text")
 
	local f = Instance.new("TextLabel", ProfileCard)
	f.Size = UDim2.new(1, -105, 0, 14)
	f.Position = UDim2.new(0, 45, 0, 26)
	f.BackgroundTransparency = 1
	f.Text = "Punishment User"
	f.Font = Enum.Font.GothamMedium
	f.TextSize = 10
	f.TextXAlignment = Enum.TextXAlignment.Left
	punishgoatby97mzu:ApplyThemeObj(f, "TextColor3", "Accentpunish")
 
	local ThemePanel = Instance.new("Frame", Main)
	ThemePanel.Name = "ThemePanel"
	ThemePanel.AnchorPoint = Vector2.new(0, 1)
	ThemePanel.Position = UDim2.new(0, 10, 1, -65)
	ThemePanel.Size = UDim2.new(0, 160, 0, 0)
	ThemePanel.BackgroundTransparency = 0.55
	ThemePanel.ClipsDescendants = true
	ThemePanel.ZIndex = 50
	Instance.new("UICorner", ThemePanel).CornerRadius = UDim.new(0, 8)
	punishgoatby97mzu:ApplyThemeObj(ThemePanel, "BackgroundColor3", "ToggleBtnBg")
 
	local TPStroke = Instance.new("UIStroke", ThemePanel)
	TPStroke.Transparency = 0.85
	punishgoatby97mzu:ApplyThemeObj(TPStroke, "Color", "Stroke")
 
	local TPPadding = Instance.new("UIPadding", ThemePanel)
	TPPadding.PaddingTop = UDim.new(0, 8)
	TPPadding.PaddingBottom = UDim.new(0, 8)
	TPPadding.PaddingLeft = UDim.new(0, 8)
	TPPadding.PaddingRight = UDim.new(0, 8)
 
	local TPLayout = Instance.new("UIListLayout", ThemePanel)
	TPLayout.SortOrder = Enum.SortOrder.LayoutOrder
	TPLayout.Padding = UDim.new(0, 4)
 
	local ThemeOrder =
		{ "Dark", "Light", "Ocean", "Cyberpunk", "Matcha", "Silver", "White", "Platinum", "Crimson", "Gold" }
	for i, tName in ipairs(ThemeOrder) do
		local tBtn = Instance.new("TextButton", ThemePanel)
		tBtn.Size = UDim2.new(1, 0, 0, 26)
		tBtn.BackgroundTransparency = 1
		tBtn.Text = tName
		tBtn.Font = Enum.Font.GothamMedium
		tBtn.TextSize = 11
		tBtn.AutoButtonColor = false
		tBtn.LayoutOrder = i
		Instance.new("UICorner", tBtn).CornerRadius = UDim.new(0, 4)
		punishgoatby97mzu:ApplyThemeObj(tBtn, "BackgroundColor3", "ToggleBgOff")
		punishgoatby97mzu:ApplyThemeObj(tBtn, "TextColor3", "TextInactive")
 
		tBtn.MouseEnter:Connect(function()
			TweenService:Create(tBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0.8 }):Play()
		end)
		tBtn.MouseLeave:Connect(function()
			TweenService:Create(tBtn, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		end)
 
		tBtn.MouseButton1Click:Connect(function()
			punishgoatby97mzu:ChangeTheme(tName)
			for _, tabData in pairs(Window.Tabs) do
				if tabData.Page.Visible then
					local palette = punishgoatby97mzu.Themes[tName]
					TweenService:Create(tabData.Icon, TweenInfo.new(0.3), { ImageColor3 = palette.Accent }):Play()
					TweenService:Create(tabData.TitleLabel, TweenInfo.new(0.3), { TextColor3 = palette.Text }):Play()
				end
			end
		end)
	end
 
	local t = Instance.new("ImageLabel", ProfileCard)
	t.Size = UDim2.new(0, 20, 0, 20)
	t.AnchorPoint = Vector2.new(1, 0.5)
	t.Position = UDim2.new(1, -10, 0.6, 0)
	t.BackgroundTransparency = 1
	t.Image = "rbxassetid://81899856845503"
	punishgoatby97mzu:ApplyThemeObj(t, "ImageColor3", "TextInactive")
 
	local ContentContainer = Instance.new("Frame", Main)
	ContentContainer.Name = "ContentContainer"
	ContentContainer.Size = UDim2.new(1, -181, 1, -30)
	ContentContainer.Position = UDim2.new(0, 181, 0, 30)
	ContentContainer.BackgroundTransparency = 1
	ContentContainer.BorderSizePixel = 0
	ContentContainer.ClipsDescendants = true
 
	function Window:CreateTab(TabName, IconID)
		local TabBtn = Instance.new("TextButton", Sidebar)
		TabBtn.Name = "TabBtn_" .. TabName
		TabBtn.Size = UDim2.new(1, 0, 0, 32)
		TabBtn.BackgroundTransparency = 0.98
		TabBtn.Text = ""
		TabBtn.AutoButtonColor = false
		Instance.new("UICorner", TabBtn).CornerRadius = UDim.new(0, 6)
		punishgoatby97mzu:ApplyThemeObj(TabBtn, "BackgroundColor3", "Text")
 
		local Indicator = Instance.new("Frame", TabBtn)
		Indicator.Name = "Indicator"
		Indicator.Size = UDim2.new(0, 3, 0, 16)
		Indicator.AnchorPoint = Vector2.new(0, 0.5)
		Indicator.Position = UDim2.new(0, 4, 0.5, 0)
		Indicator.BackgroundTransparency = 1
		Indicator.BorderSizePixel = 0
		Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)
		punishgoatby97mzu:ApplyThemeObj(Indicator, "BackgroundColor3", "Accent")
 
		local Icon = Instance.new("ImageLabel", TabBtn)
		Icon.Name = "Icon"
		Icon.Size = UDim2.new(0, 16, 0, 16)
		Icon.AnchorPoint = Vector2.new(0, 0.5)
		Icon.Position = UDim2.new(0, 14, 0.5, 0)
		Icon.BackgroundTransparency = 1
		Icon.Image = IconID or ""
		punishgoatby97mzu:ApplyThemeObj(Icon, "ImageColor3", "TextInactive")
 
		local TitleLabel = Instance.new("TextLabel", TabBtn)
		TitleLabel.Name = "TitleLabel"
		TitleLabel.Size = UDim2.new(1, -40, 1, 0)
		TitleLabel.Position = UDim2.new(0, 40, 0, 0)
		TitleLabel.BackgroundTransparency = 1
		TitleLabel.Text = TabName
		TitleLabel.Font = Enum.Font.GothamMedium
		TitleLabel.TextSize = 13
		TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
		TitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
		punishgoatby97mzu:ApplyThemeObj(TitleLabel, "TextColor3", "TextInactive")
 
		local Page = Instance.new("ScrollingFrame", ContentContainer)
		Page.Name = "Page_" .. TabName
		Page.Size = UDim2.new(1, 0, 1, 0)
		Page.Position = UDim2.new(0, 0, 1, 0)
		Page.BackgroundTransparency = 1
		Page.BorderSizePixel = 0
		Page.ScrollBarThickness = 2
		Page.CanvasSize = UDim2.new(0, 0, 0, 0)
		-- Use Roblox's built-in AutomaticCanvasSize so scroll height adapts to dropdown content automatically
		Page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		punishgoatby97mzu:ApplyThemeObj(Page, "ScrollBarImageColor3", "Stroke")
 
		local PagePadding = Instance.new("UIPadding", Page)
		PagePadding.PaddingTop = UDim.new(0, 15)
		PagePadding.PaddingBottom = UDim.new(0, 15)
		PagePadding.PaddingLeft = UDim.new(0, 15)
		PagePadding.PaddingRight = UDim.new(0, 15)
 
		local PageLayout = Instance.new("UIListLayout", Page)
		PageLayout.SortOrder = Enum.SortOrder.LayoutOrder
		PageLayout.Padding = UDim.new(0, 8)
 
		local TabData = {
			Button = TabBtn,
			Indicator = Indicator,
			Icon = Icon,
			TitleLabel = TitleLabel,
			Page = Page,
		}
		table.insert(Window.Tabs, TabData)
 
		TabBtn.MouseButton1Click:Connect(function()
			if Window.CurrentTab == TabData then
				return
			end
			local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
 
			for _, v in pairs(Window.Tabs) do
				TweenService:Create(v.Button, TweenInfo.new(0.2), { BackgroundTransparency = 0.98 }):Play()
				TweenService:Create(v.Indicator, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
				TweenService:Create(v.Icon, TweenInfo.new(0.2), { ImageColor3 = palette.TextInactive }):Play()
				TweenService:Create(v.TitleLabel, TweenInfo.new(0.2), { TextColor3 = palette.TextInactive }):Play()
 
				if v.Page.Visible then
					v.Page.Visible = false
				end
			end
 
			Window.CurrentTab = TabData
			Page.Visible = true
			Page.Position = UDim2.new(0, 0, 0, 0)
			Page.CanvasPosition = Vector2.new(0, 0)
 
			TweenService:Create(TabBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0.9 }):Play()
			TweenService:Create(Indicator, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
			TweenService:Create(Icon, TweenInfo.new(0.2), { ImageColor3 = palette.Accent }):Play()
			TweenService:Create(TitleLabel, TweenInfo.new(0.2), { TextColor3 = palette.Text }):Play()
 
			for _, closeFunc in pairs(Window.SelectCloseFuncs) do
				closeFunc()
			end
		end)
 
		if #Window.Tabs == 1 then
			Window.CurrentTab = TabData
			Page.Visible = true
			Page.Position = UDim2.new(0, 0, 0, 0)
			TabBtn.BackgroundTransparency = 0.9
			Indicator.BackgroundTransparency = 0
			local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
			Icon.ImageColor3 = palette.Accent
			TitleLabel.TextColor3 = palette.Text
		end
 
		local Tab = {}
		function Tab:CreateSection(SectionName)
			local SectionLabel = Instance.new("Frame", Page)
			SectionLabel.Size = UDim2.new(1, 0, 0, 30)
			SectionLabel.BackgroundTransparency = 1
 
			local Title = Instance.new("TextLabel", SectionLabel)
			Title.Size = UDim2.new(1, -10, 1, 0)
			Title.Position = UDim2.new(0, 5, 0, 0)
			Title.BackgroundTransparency = 1
			Title.Text = SectionName
			Title.Font = Enum.Font.GothamBold
			Title.TextSize = 14
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "SectionTitle")
 
			Instance.new("UIPadding", SectionLabel).PaddingTop = UDim.new(0, 15)
		end
 
		-- Thin horizontal separator to break up long lists of components.
		function Tab:CreateDivider()
			local DividerHolder = Instance.new("Frame", Page)
			DividerHolder.Size = UDim2.new(1, 0, 0, 9)
			DividerHolder.BackgroundTransparency = 1
 
			local Line = Instance.new("Frame", DividerHolder)
			Line.Size = UDim2.new(1, 0, 0, 1)
			Line.Position = UDim2.new(0, 0, 0.5, 0)
			Line.AnchorPoint = Vector2.new(0, 0.5)
			Line.BorderSizePixel = 0
			Line.BackgroundTransparency = 0.7
			punishgoatby97mzu:ApplyThemeObj(Line, "BackgroundColor3", "Stroke")
		end
 
		-- Same idea as CreateDivider, but accepts an optional centered label
		-- (e.g. AddLine("Advanced"), or just AddLine() for a plain line).
		function Tab:AddLine(Text)
			local LineHolder = Instance.new("Frame", Page)
			LineHolder.Size = UDim2.new(1, 0, 0, 9)
			LineHolder.BackgroundTransparency = 1
 
			if Text and Text ~= "" then
				local LeftLine = Instance.new("Frame", LineHolder)
				LeftLine.AnchorPoint = Vector2.new(0, 0.5)
				LeftLine.Position = UDim2.new(0, 0, 0.5, 0)
				LeftLine.Size = UDim2.new(0.4, 0, 0, 1)
				LeftLine.BorderSizePixel = 0
				LeftLine.BackgroundTransparency = 0.7
				punishgoatby97mzu:ApplyThemeObj(LeftLine, "BackgroundColor3", "Stroke")
 
				local Label = Instance.new("TextLabel", LineHolder)
				Label.AnchorPoint = Vector2.new(0.5, 0.5)
				Label.Position = UDim2.new(0.5, 0, 0.5, 0)
				Label.Size = UDim2.new(0, 0, 0, 14)
				Label.AutomaticSize = Enum.AutomaticSize.X
				Label.BackgroundTransparency = 1
				Label.Text = Text
				Label.Font = Enum.Font.GothamMedium
				Label.TextSize = 11
				punishgoatby97mzu:ApplyThemeObj(Label, "TextColor3", "TextInactive")
 
				local RightLine = Instance.new("Frame", LineHolder)
				RightLine.AnchorPoint = Vector2.new(1, 0.5)
				RightLine.Position = UDim2.new(1, 0, 0.5, 0)
				RightLine.Size = UDim2.new(0.4, 0, 0, 1)
				RightLine.BorderSizePixel = 0
				RightLine.BackgroundTransparency = 0.7
				punishgoatby97mzu:ApplyThemeObj(RightLine, "BackgroundColor3", "Stroke")
			else
				local Line = Instance.new("Frame", LineHolder)
				Line.Size = UDim2.new(1, 0, 0, 1)
				Line.Position = UDim2.new(0, 0, 0.5, 0)
				Line.AnchorPoint = Vector2.new(0, 0.5)
				Line.BorderSizePixel = 0
				Line.BackgroundTransparency = 0.7
				punishgoatby97mzu:ApplyThemeObj(Line, "BackgroundColor3", "Stroke")
			end
		end
 
		-- Live search box. Calls Callback(query) on every keystroke; the caller decides
		-- what to filter (component list, dropdown options, etc). Returns a handle with
		-- :Set(text) so the search text can be cleared/updated from outside too.
		function Tab:CreateSearchBar(Placeholder, Callback)
			local CallbackFunc = Callback or function() end
 
			local SearchContainer = Instance.new("Frame", Page)
			SearchContainer.Size = UDim2.new(1, 0, 0, 36)
			SearchContainer.BackgroundTransparency = 0.55
			Instance.new("UICorner", SearchContainer).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(SearchContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local SearchStroke = Instance.new("UIStroke", SearchContainer)
			SearchStroke.Thickness = 1
			SearchStroke.Transparency = 0.85
			SearchStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			punishgoatby97mzu:ApplyThemeObj(SearchStroke, "Color", "Stroke")
 
			local Icon = Instance.new("ImageLabel", SearchContainer)
			Icon.Size = UDim2.new(0, 16, 0, 16)
			Icon.AnchorPoint = Vector2.new(0, 0.5)
			Icon.Position = UDim2.new(0, 12, 0.5, 0)
			Icon.BackgroundTransparency = 1
			Icon.Image = "rbxassetid://10709791245" -- magnifying glass icon
			punishgoatby97mzu:ApplyThemeObj(Icon, "ImageColor3", "TextInactive")
 
			local Input = Instance.new("TextBox", SearchContainer)
			Input.Size = UDim2.new(1, -70, 1, 0)
			Input.Position = UDim2.new(0, 36, 0, 0)
			Input.BackgroundTransparency = 1
			Input.PlaceholderText = Placeholder or "Search..."
			Input.Text = ""
			Input.ClearTextOnFocus = false
			Input.Font = Enum.Font.Gotham
			Input.TextSize = 13
			Input.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Input, "TextColor3", "Text")
			punishgoatby97mzu:ApplyThemeObj(Input, "PlaceholderColor3", "TextInactive")
 
			local ClearBtn = Instance.new("TextButton", SearchContainer)
			ClearBtn.Size = UDim2.new(0, 24, 0, 24)
			ClearBtn.AnchorPoint = Vector2.new(1, 0.5)
			ClearBtn.Position = UDim2.new(1, -8, 0.5, 0)
			ClearBtn.BackgroundTransparency = 1
			ClearBtn.Text = "X"
			ClearBtn.Font = Enum.Font.GothamBold
			ClearBtn.TextSize = 12
			ClearBtn.AutoButtonColor = false
			ClearBtn.Visible = false
			punishgoatby97mzu:ApplyThemeObj(ClearBtn, "TextColor3", "TextInactive")
 
			Input.Focused:Connect(function()
				TweenService:Create(SearchStroke, TweenInfo.new(0.2), {
					Color = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme].Accent,
					Transparency = 0.5,
				}):Play()
			end)
			Input.FocusLost:Connect(function()
				TweenService:Create(SearchStroke, TweenInfo.new(0.2), {
					Color = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme].Stroke,
					Transparency = 0.85,
				}):Play()
			end)
 
			-- [FIX] React on every keystroke (GetPropertyChangedSignal), not just FocusLost,
			-- so filtering feels instant instead of only firing once the box loses focus.
			Input:GetPropertyChangedSignal("Text"):Connect(function()
				ClearBtn.Visible = Input.Text ~= ""
				CallbackFunc(Input.Text)
			end)
 
			ClearBtn.MouseButton1Click:Connect(function()
				Input.Text = ""
				Input:CaptureFocus()
			end)
 
			local SearchBar = {}
			function SearchBar:Set(text)
				Input.Text = text or ""
			end
			function SearchBar:Get()
				return Input.Text
			end
			return SearchBar
		end
 
		function Tab:CreateThemeDropdown(DropdownName)
			local Expanded = false
 
			local DropdownContainer = Instance.new("Frame", Page)
			DropdownContainer.Size = UDim2.new(1, 0, 0, 36)
			DropdownContainer.BackgroundTransparency = 0.55
			DropdownContainer.ClipsDescendants = true
			Instance.new("UICorner", DropdownContainer).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(DropdownContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local ContainerStroke = Instance.new("UIStroke", DropdownContainer)
			ContainerStroke.Thickness = 1
			ContainerStroke.Transparency = 0.85
			ContainerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			punishgoatby97mzu:ApplyThemeObj(ContainerStroke, "Color", "Stroke")
 
			local Header = Instance.new("TextButton", DropdownContainer)
			Header.Size = UDim2.new(1, 0, 0, 36)
			Header.BackgroundTransparency = 1
			Header.AutoButtonColor = false
			Header.Text = ""
 
			local Title = Instance.new("TextLabel", Header)
			Title.Size = UDim2.new(1, -60, 1, 0)
			Title.Position = UDim2.new(0, 15, 0, 0)
			Title.BackgroundTransparency = 1
			Title.Text = DropdownName or "Select Theme"
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			local Arrow = Instance.new("ImageLabel", Header)
			Arrow.Size = UDim2.new(0, 16, 0, 16)
			Arrow.AnchorPoint = Vector2.new(1, 0.5)
			Arrow.Position = UDim2.new(1, -15, 0.5, 0)
			Arrow.BackgroundTransparency = 1
			Arrow.Image = "rbxassetid://10709790948"
			punishgoatby97mzu:ApplyThemeObj(Arrow, "ImageColor3", "TextInactive")
 
			local ContentArea = Instance.new("Frame", DropdownContainer)
			ContentArea.Size = UDim2.new(1, 0, 0, 0)
			ContentArea.Position = UDim2.new(0, 0, 0, 36)
			ContentArea.BackgroundTransparency = 1
 
			local ContentPadding = Instance.new("UIPadding", ContentArea)
			ContentPadding.PaddingTop = UDim.new(0, 8)
			ContentPadding.PaddingBottom = UDim.new(0, 12)
			ContentPadding.PaddingLeft = UDim.new(0, 12)
			ContentPadding.PaddingRight = UDim.new(0, 12)
 
			local ContentLayout = Instance.new("UIListLayout", ContentArea)
			ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
			ContentLayout.Padding = UDim.new(0, 4)
 
			local function ToggleDropdown()
				Expanded = not Expanded
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
 
				if Expanded then
					local TargetHeight = 36 + 20 + ContentLayout.AbsoluteContentSize.Y
					TweenService:Create(
						DropdownContainer,
						TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{ Size = UDim2.new(1, 0, 0, TargetHeight) }
					):Play()
					TweenService
						:Create(ContainerStroke, TweenInfo.new(0.3), { Color = palette.Accent, Transparency = 0.5 })
						:Play()
					TweenService:Create(Arrow, TweenInfo.new(0.3), { ImageColor3 = palette.Accent, Rotation = 180 })
						:Play()
					TweenService:Create(Title, TweenInfo.new(0.3), { TextColor3 = palette.Accent }):Play()
				else
					TweenService:Create(
						DropdownContainer,
						TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{ Size = UDim2.new(1, 0, 0, 36) }
					):Play()
					TweenService
						:Create(ContainerStroke, TweenInfo.new(0.3), { Color = palette.Stroke, Transparency = 0.85 })
						:Play()
					TweenService:Create(Arrow, TweenInfo.new(0.3), { ImageColor3 = palette.TextInactive, Rotation = 0 })
						:Play()
					TweenService:Create(Title, TweenInfo.new(0.3), { TextColor3 = palette.Text }):Play()
				end
			end
 
			Header.MouseButton1Click:Connect(ToggleDropdown)
 
			local ThemeOrder =
				{ "Dark", "Light", "Ocean", "Cyberpunk", "Matcha", "Silver", "White", "Platinum", "Crimson", "Gold" }
			for _, tName in ipairs(ThemeOrder) do
				local tBtn = Instance.new("TextButton", ContentArea)
				tBtn.Size = UDim2.new(1, 0, 0, 30)
				tBtn.BackgroundTransparency = 1
				tBtn.Text = tName
				tBtn.Font = Enum.Font.GothamMedium
				tBtn.TextSize = 12
				tBtn.AutoButtonColor = false
				Instance.new("UICorner", tBtn).CornerRadius = UDim.new(0, 4)
				punishgoatby97mzu:ApplyThemeObj(tBtn, "BackgroundColor3", "ToggleBgOff")
				punishgoatby97mzu:ApplyThemeObj(tBtn, "TextColor3", "TextInactive")
 
				tBtn.MouseEnter:Connect(function()
					TweenService:Create(tBtn, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
				end)
				tBtn.MouseLeave:Connect(function()
					TweenService:Create(tBtn, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
				end)
 
				tBtn.MouseButton1Click:Connect(function()
					punishgoatby97mzu:ChangeTheme(tName)
 
					for _, tabData in pairs(Window.Tabs) do
						if tabData.Page.Visible then
							local palette = punishgoatby97mzu.Themes[tName]
							TweenService:Create(tabData.Icon, TweenInfo.new(0.3), { ImageColor3 = palette.Accent })
								:Play()
							TweenService:Create(tabData.TitleLabel, TweenInfo.new(0.3), { TextColor3 = palette.Text })
								:Play()
						end
					end
 
					ToggleDropdown()
				end)
			end
		end
 
		function Tab:CreateChangelog(TitleText, ContentText)
			local Expanded = false
 
			local LogContainer = Instance.new("TextButton", Page)
			LogContainer.Size = UDim2.new(1, 0, 0, 36)
			LogContainer.BackgroundTransparency = 0.55
			LogContainer.AutoButtonColor = false
			LogContainer.Text = ""
			LogContainer.ClipsDescendants = true
			Instance.new("UICorner", LogContainer).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(LogContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local LogStroke = Instance.new("UIStroke", LogContainer)
			LogStroke.Thickness = 1
			LogStroke.Transparency = 0.85
			LogStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			punishgoatby97mzu:ApplyThemeObj(LogStroke, "Color", "Stroke")
 
			local Header = Instance.new("Frame", LogContainer)
			Header.Size = UDim2.new(1, 0, 0, 36)
			Header.BackgroundTransparency = 1
 
			local Title = Instance.new("TextLabel", Header)
			Title.Size = UDim2.new(1, -40, 1, 0)
			Title.Position = UDim2.new(0, 15, 0, 0)
			Title.BackgroundTransparency = 1
			Title.Text = TitleText
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			local Arrow = Instance.new("ImageLabel", Header)
			Arrow.Size = UDim2.new(0, 16, 0, 16)
			Arrow.AnchorPoint = Vector2.new(1, 0.5)
			Arrow.Position = UDim2.new(1, -15, 0.5, 0)
			Arrow.BackgroundTransparency = 1
			Arrow.Image = "rbxassetid://10709790948"
			punishgoatby97mzu:ApplyThemeObj(Arrow, "ImageColor3", "TextInactive")
 
			local ContentArea = Instance.new("Frame", LogContainer)
			ContentArea.Size = UDim2.new(1, 0, 0, 0)
			ContentArea.Position = UDim2.new(0, 0, 0, 36)
			ContentArea.BackgroundTransparency = 1
 
			local ContentPadding = Instance.new("UIPadding", ContentArea)
			ContentPadding.PaddingTop = UDim.new(0, 5)
			ContentPadding.PaddingBottom = UDim.new(0, 10)
			ContentPadding.PaddingLeft = UDim.new(0, 15)
			ContentPadding.PaddingRight = UDim.new(0, 15)
 
			local ContentLayout = Instance.new("UIListLayout", ContentArea)
			ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
			ContentLayout.Padding = UDim.new(0, 6)
 
			local lines = {}
			for s in string.gmatch(ContentText, "[^\r\n]+") do
				table.insert(lines, s)
			end
 
			for _, lineText in ipairs(lines) do
				local LogCard = Instance.new("Frame", ContentArea)
				LogCard.Size = UDim2.new(1, 0, 0, 26)
				LogCard.BackgroundTransparency = 0.5
				Instance.new("UICorner", LogCard).CornerRadius = UDim.new(0, 4)
				punishgoatby97mzu:ApplyThemeObj(LogCard, "BackgroundColor3", "ToggleBgOff")
 
				local CardStroke = Instance.new("UIStroke", LogCard)
				CardStroke.Thickness = 1
				CardStroke.Transparency = 0.8
				punishgoatby97mzu:ApplyThemeObj(CardStroke, "Color", "Stroke")
 
				local LogLineText = Instance.new("TextLabel", LogCard)
				LogLineText.Size = UDim2.new(1, -20, 1, 0)
				LogLineText.Position = UDim2.new(0, 10, 0, 0)
				LogLineText.BackgroundTransparency = 1
				LogLineText.Text = lineText
				LogLineText.Font = Enum.Font.GothamMedium
				LogLineText.TextSize = 11
				LogLineText.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(LogLineText, "TextColor3", "TextInactive")
			end
 
			local function ToggleLog()
				Expanded = not Expanded
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
 
				if Expanded then
					local TargetHeight = 36 + 15 + ContentLayout.AbsoluteContentSize.Y
					TweenService:Create(
						LogContainer,
						TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{ Size = UDim2.new(1, 0, 0, TargetHeight) }
					):Play()
					TweenService:Create(Arrow, TweenInfo.new(0.3), { Rotation = 180, ImageColor3 = palette.Accent })
						:Play()
					TweenService:Create(LogStroke, TweenInfo.new(0.3), { Color = palette.Accent, Transparency = 0.5 })
						:Play()
				else
					TweenService:Create(
						LogContainer,
						TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{ Size = UDim2.new(1, 0, 0, 36) }
					):Play()
					TweenService:Create(Arrow, TweenInfo.new(0.3), { Rotation = 0, ImageColor3 = palette.TextInactive })
						:Play()
					TweenService:Create(LogStroke, TweenInfo.new(0.3), { Color = palette.Stroke, Transparency = 0.85 })
						:Play()
				end
			end
 
			LogContainer.MouseButton1Click:Connect(ToggleLog)
			ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if Expanded then
					local TargetHeight = 36 + 15 + ContentLayout.AbsoluteContentSize.Y
					TweenService:Create(
						LogContainer,
						TweenInfo.new(0.2, Enum.EasingStyle.Sine),
						{ Size = UDim2.new(1, 0, 0, TargetHeight) }
					):Play()
				end
			end)
		end
 
		function Tab:CreateToggle(ToggleName, Description, Default, Callback)
			local State = Default or false
			local CallbackFunc = Callback or function() end
			local HasDesc = type(Description) == "string" and Description ~= ""
 
			local ToggleBtn = Instance.new("TextButton", Page)
			ToggleBtn.Active = false
			ToggleBtn.Size = UDim2.new(1, 0, 0, HasDesc and 52 or 36)
			ToggleBtn.AutoButtonColor = false
			ToggleBtn.Text = ""
			ToggleBtn.BackgroundTransparency = 0.2
			Instance.new("UICorner", ToggleBtn).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(ToggleBtn, "BackgroundColor3", "ToggleBtnBg")
 
			local ToggleStroke = Instance.new("UIStroke", ToggleBtn)
			ToggleStroke.Thickness = 1
			ToggleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
 
			ToggleStroke.Color = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme].Stroke
			ToggleStroke.Transparency = 0.85
 
			local function UpdateStrokeVisual(isActive, themeName)
				local palette = punishgoatby97mzu.Themes[themeName or punishgoatby97mzu.CurrentTheme]
				if isActive then
					TweenService:Create(
						ToggleStroke,
						TweenInfo.new(0.3, Enum.EasingStyle.Quint),
						{ Color = palette.Accent, Transparency = 0.85 }
					):Play()
				else
					TweenService:Create(
						ToggleStroke,
						TweenInfo.new(0.3, Enum.EasingStyle.Quint),
						{ Color = palette.Stroke, Transparency = 0.88 }
					):Play()
				end
			end
 
			UpdateStrokeVisual(State, punishgoatby97mzu.CurrentTheme)
			table.insert(punishgoatby97mzu.ThemeChangedHooks, {
				Inst = ToggleBtn,
				Func = function(tName)
					UpdateStrokeVisual(State, tName)
				end,
			})
 
			local Title = Instance.new("TextLabel", ToggleBtn)
			Title.Size = UDim2.new(1, -60, 0, 16)
			Title.Position = UDim2.new(0, 15, 0, HasDesc and 10 or 10)
			if not HasDesc then
				Title.Size = UDim2.new(1, -60, 1, 0)
				Title.Position = UDim2.new(0, 15, 0, 0)
			end
			Title.BackgroundTransparency = 1
			Title.Text = ToggleName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			if HasDesc then
				local DescLabel = Instance.new("TextLabel", ToggleBtn)
				DescLabel.Size = UDim2.new(1, -60, 0, 14)
				DescLabel.Position = UDim2.new(0, 15, 0, 26)
				DescLabel.BackgroundTransparency = 1
				DescLabel.Text = Description
				DescLabel.Font = Enum.Font.Gotham
				DescLabel.TextSize = 11
				DescLabel.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(DescLabel, "TextColor3", "TextInactive")
			end
 
			local SwitchBg = Instance.new("Frame", ToggleBtn)
			SwitchBg.Size = UDim2.new(0, 36, 0, 18)
			SwitchBg.AnchorPoint = Vector2.new(1, 0.5)
			SwitchBg.Position = UDim2.new(1, -15, 0.5, 0)
			Instance.new("UICorner", SwitchBg).CornerRadius = UDim.new(1, 0)
			punishgoatby97mzu:ApplyThemeObj(SwitchBg, "BackgroundColor3", State and "Accent" or "ToggleBgOff")
 
			local Dot = Instance.new("Frame", SwitchBg)
			Dot.Size = UDim2.new(0, 14, 0, 14)
			Dot.AnchorPoint = Vector2.new(0, 0.5)
			Dot.Position = UDim2.new(0, State and 20 or 2, 0.5, 0)
			Dot.ZIndex = 2
			Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)
			punishgoatby97mzu:ApplyThemeObj(Dot, "BackgroundColor3", "ToggleDot")
 
			ToggleBtn.MouseButton1Click:Connect(function()
				State = not State
				CallbackFunc(State)
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
 
				UpdateStrokeVisual(State)
 
				if State then
					TweenService
						:Create(
							Dot,
							TweenInfo.new(0.3, Enum.EasingStyle.Quint),
							{ Position = UDim2.new(0, 20, 0.5, 0) }
						)
						:Play()
					TweenService
						:Create(
							SwitchBg,
							TweenInfo.new(0.3, Enum.EasingStyle.Quint),
							{ BackgroundColor3 = palette.Accent }
						)
						:Play()
				else
					TweenService
						:Create(Dot, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.new(0, 2, 0.5, 0) })
						:Play()
					TweenService:Create(
						SwitchBg,
						TweenInfo.new(0.3, Enum.EasingStyle.Quint),
						{ BackgroundColor3 = palette.ToggleBgOff }
					):Play()
				end
 
				for _, obj in pairs(punishgoatby97mzu.Instances) do
					if obj.Inst == SwitchBg then
						obj.Type = State and "Accent" or "ToggleBgOff"
					end
				end
			end)
		end
 
		function Tab:CreateButton(ButtonName, Description, IconID, Callback)
			local CallbackFunc = Callback or function() end
			local HasDesc = type(Description) == "string" and Description ~= ""
 
			local ButtonContainer = Instance.new("TextButton", Page)
			ButtonContainer.Active = false -- 🔥 TAMBAHKAN BARIS INI
			ButtonContainer.Size = UDim2.new(1, 0, 0, HasDesc and 52 or 36)
			ButtonContainer.BackgroundTransparency = 0.55
			ButtonContainer.AutoButtonColor = false
			ButtonContainer.Text = ""
			Instance.new("UICorner", ButtonContainer).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(ButtonContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local BtnStroke = Instance.new("UIStroke", ButtonContainer)
			BtnStroke.Thickness = 1
			BtnStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			BtnStroke.Color = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme].Stroke
			BtnStroke.Transparency = 0.85
 
			local function UpdateBtnStrokeVisual(isActive, themeName)
				local palette = punishgoatby97mzu.Themes[themeName or punishgoatby97mzu.CurrentTheme]
				if isActive then
					TweenService:Create(
						BtnStroke,
						TweenInfo.new(0.3, Enum.EasingStyle.Quint),
						{ Color = palette.Accent, Transparency = 0.5 }
					):Play()
				else
					TweenService:Create(
						BtnStroke,
						TweenInfo.new(0.5, Enum.EasingStyle.Sine),
						{ Color = palette.Stroke, Transparency = 0.85 }
					):Play()
				end
			end
 
			UpdateBtnStrokeVisual(false, punishgoatby97mzu.CurrentTheme)
			table.insert(punishgoatby97mzu.ThemeChangedHooks, {
				Inst = ButtonContainer,
				Func = function(tName)
					UpdateBtnStrokeVisual(false, tName)
				end,
			})
 
			local Title = Instance.new("TextLabel", ButtonContainer)
			Title.Size = UDim2.new(1, -60, 0, 16)
			Title.Position = UDim2.new(0, 15, 0, HasDesc and 10 or 10)
			if not HasDesc then
				Title.Size = UDim2.new(1, -60, 1, 0)
				Title.Position = UDim2.new(0, 15, 0, 0)
			end
			Title.BackgroundTransparency = 1
			Title.Text = ButtonName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			if HasDesc then
				local DescLabel = Instance.new("TextLabel", ButtonContainer)
				DescLabel.Size = UDim2.new(1, -60, 0, 14)
				DescLabel.Position = UDim2.new(0, 15, 0, 26)
				DescLabel.BackgroundTransparency = 1
				DescLabel.Text = Description
				DescLabel.Font = Enum.Font.Gotham
				DescLabel.TextSize = 11
				DescLabel.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(DescLabel, "TextColor3", "TextInactive")
			end
 
			local ActionKey = Instance.new("Frame", ButtonContainer)
			ActionKey.Size = UDim2.new(0, 30, 0, 30)
			ActionKey.AnchorPoint = Vector2.new(1, 0.5)
			ActionKey.Position = UDim2.new(1, -3, 0.5, 0)
			Instance.new("UICorner", ActionKey).CornerRadius = UDim.new(0, 6)
			punishgoatby97mzu:ApplyThemeObj(ActionKey, "BackgroundColor3", "ToggleBgOff")
 
			local KeyStroke = Instance.new("UIStroke", ActionKey)
			KeyStroke.Thickness = 1
			KeyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			KeyStroke.Color = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme].Stroke
			KeyStroke.Transparency = 0.7
 
			local Icon = Instance.new("ImageLabel", ActionKey)
			Icon.Size = UDim2.new(0, 18, 0, 18)
			Icon.AnchorPoint = Vector2.new(0.5, 0.5)
			Icon.Position = UDim2.new(0.5, 0, 0.5, 0)
			Icon.BackgroundTransparency = 1
			Icon.Image = IconID or "rbxassetid://10734933056"
			punishgoatby97mzu:ApplyThemeObj(Icon, "ImageColor3", "TextInactive")
 
			ButtonContainer.MouseEnter:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(ActionKey, TweenInfo.new(0.2), {
					BackgroundColor3 = Color3.fromRGB(
						math.clamp(palette.ToggleBgOff.R * 255 + 12, 0, 255),
						math.clamp(palette.ToggleBgOff.G * 255 + 12, 0, 255),
						math.clamp(palette.ToggleBgOff.B * 255 + 12, 0, 255)
					),
				}):Play()
				TweenService:Create(KeyStroke, TweenInfo.new(0.2), { Color = palette.Accent, Transparency = 0.4 })
					:Play()
				TweenService:Create(Icon, TweenInfo.new(0.2), { ImageColor3 = palette.Text }):Play()
			end)
 
			ButtonContainer.MouseLeave:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(ActionKey, TweenInfo.new(0.2), { BackgroundColor3 = palette.ToggleBgOff }):Play()
				TweenService:Create(KeyStroke, TweenInfo.new(0.2), { Color = palette.Stroke, Transparency = 0.7 })
					:Play()
				TweenService:Create(Icon, TweenInfo.new(0.2), { ImageColor3 = palette.TextInactive }):Play()
			end)
 
			ButtonContainer.MouseButton1Click:Connect(function()
				CallbackFunc()
			end)
 
			ButtonContainer.MouseButton1Down:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService
					:Create(ActionKey, TweenInfo.new(0.05, Enum.EasingStyle.Sine), { Size = UDim2.new(0, 26, 0, 26) })
					:Play()
				TweenService:Create(
					Icon,
					TweenInfo.new(0.05, Enum.EasingStyle.Sine),
					{ Size = UDim2.new(0, 14, 0, 14), ImageColor3 = palette.Accent }
				):Play()
				TweenService:Create(
					KeyStroke,
					TweenInfo.new(0.05, Enum.EasingStyle.Sine),
					{ Color = palette.Accent, Transparency = 0.2 }
				):Play()
				UpdateBtnStrokeVisual(true)
			end)
 
			local function ResetButtonAnim()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(
					ActionKey,
					TweenInfo.new(0.3, Enum.EasingStyle.Bounce),
					{ Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = palette.ToggleBgOff }
				):Play()
				TweenService:Create(
					Icon,
					TweenInfo.new(0.3, Enum.EasingStyle.Bounce),
					{ Size = UDim2.new(0, 18, 0, 18), ImageColor3 = palette.TextInactive }
				):Play()
				TweenService:Create(
					KeyStroke,
					TweenInfo.new(0.3, Enum.EasingStyle.Sine),
					{ Color = palette.Stroke, Transparency = 0.7 }
				):Play()
				UpdateBtnStrokeVisual(false)
			end
 
			ButtonContainer.MouseButton1Up:Connect(ResetButtonAnim)
		end
 
		function Tab:CreateSlider(SliderName, Min, Max, Default, Callback)
			local CallbackFunc = Callback or function() end
			local Value = math.clamp(Default or Min, Min, Max)
 
			local SliderContainer = Instance.new("TextButton", Page)
			SliderContainer.Active = false
			SliderContainer.Size = UDim2.new(1, 0, 0, 42)
			SliderContainer.BackgroundTransparency = 0.55
			SliderContainer.AutoButtonColor = false
			SliderContainer.Text = ""
			Instance.new("UICorner", SliderContainer).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(SliderContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local SliderStroke = Instance.new("UIStroke", SliderContainer)
			SliderStroke.Thickness = 1
			SliderStroke.Transparency = 0.85
			SliderStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			punishgoatby97mzu:ApplyThemeObj(SliderStroke, "Color", "Stroke")
 
			local Title = Instance.new("TextLabel", SliderContainer)
			Title.Size = UDim2.new(1, -100, 0, 20)
			Title.Position = UDim2.new(0, 15, 0, 5)
			Title.BackgroundTransparency = 1
			Title.Text = SliderName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			local ValueCard = Instance.new("Frame", SliderContainer)
			ValueCard.Size = UDim2.new(0, 35, 0, 20)
			ValueCard.AnchorPoint = Vector2.new(1, 0)
			ValueCard.Position = UDim2.new(1, -15, 0, 5)
			ValueCard.BackgroundTransparency = 0.5
			ValueCard.BorderSizePixel = 0
			Instance.new("UICorner", ValueCard).CornerRadius = UDim.new(0, 4)
			punishgoatby97mzu:ApplyThemeObj(ValueCard, "BackgroundColor3", "ToggleBgOff")
 
			local CardStroke = Instance.new("UIStroke", ValueCard)
			CardStroke.Thickness = 1
			CardStroke.Transparency = 0.8
			punishgoatby97mzu:ApplyThemeObj(CardStroke, "Color", "Stroke")
 
			local ValueInput = Instance.new("TextBox", ValueCard)
			ValueInput.Size = UDim2.new(1, 0, 1, 0)
			ValueInput.BackgroundTransparency = 1
			ValueInput.Text = tostring(Value)
			ValueInput.Font = Enum.Font.GothamMedium
			ValueInput.TextSize = 12
			ValueInput.ClearTextOnFocus = false
			punishgoatby97mzu:ApplyThemeObj(ValueInput, "TextColor3", "Text")
 
			local SliderBg = Instance.new("Frame", SliderContainer)
			SliderBg.Size = UDim2.new(1, -30, 0, 4)
			SliderBg.AnchorPoint = Vector2.new(0.5, 1)
			SliderBg.Position = UDim2.new(0.5, 0, 1, -8)
			SliderBg.BorderSizePixel = 0
			Instance.new("UICorner", SliderBg).CornerRadius = UDim.new(1, 0)
			punishgoatby97mzu:ApplyThemeObj(SliderBg, "BackgroundColor3", "ToggleBgOff")
 
			local SliderFill = Instance.new("Frame", SliderBg)
			local SizeScale = (Value - Min) / (Max - Min)
			SliderFill.Size = UDim2.new(SizeScale, 0, 1, 0)
			SliderFill.BorderSizePixel = 0
			Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(1, 0)
			punishgoatby97mzu:ApplyThemeObj(SliderFill, "BackgroundColor3", "Accent")
 
			local Dot = Instance.new("Frame", SliderFill)
			Dot.Size = UDim2.new(0, 12, 0, 12)
			Dot.AnchorPoint = Vector2.new(1, 0.5)
			Dot.Position = UDim2.new(1, 6, 0.5, 0)
			Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)
			punishgoatby97mzu:ApplyThemeObj(Dot, "BackgroundColor3", "ToggleDot")
 
			local DotStroke = Instance.new("UIStroke", Dot)
			DotStroke.Thickness = 1
			punishgoatby97mzu:ApplyThemeObj(DotStroke, "Color", "Stroke")
 
			local Dragging = false
			local function UpdateSlider(Input)
				local Percent =
					math.clamp((Input.Position.X - SliderBg.AbsolutePosition.X) / SliderBg.AbsoluteSize.X, 0, 1)
				Value = math.floor(Min + ((Max - Min) * Percent))
				ValueInput.Text = tostring(Value)
				TweenService
					:Create(
						SliderFill,
						TweenInfo.new(0.05, Enum.EasingStyle.Sine),
						{ Size = UDim2.new(Percent, 0, 1, 0) }
					)
					:Play()
				CallbackFunc(Value)
			end
 
			SliderContainer.InputBegan:Connect(function(Input)
				if
					Input.UserInputType == Enum.UserInputType.MouseButton1
					or Input.UserInputType == Enum.UserInputType.Touch
				then
					Dragging = true
					UpdateSlider(Input)
					TweenService
						:Create(Dot, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 16, 0, 16) })
						:Play()
				end
			end)
 
			UserInputService.InputChanged:Connect(function(Input)
				if
					Dragging
					and (
						Input.UserInputType == Enum.UserInputType.MouseMovement
						or Input.UserInputType == Enum.UserInputType.Touch
					)
				then
					UpdateSlider(Input)
				end
			end)
 
			UserInputService.InputEnded:Connect(function(Input)
				if
					Input.UserInputType == Enum.UserInputType.MouseButton1
					or Input.UserInputType == Enum.UserInputType.Touch
				then
					if Dragging then
						Dragging = false
						TweenService
							:Create(Dot, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 12, 0, 12) })
							:Play()
					end
				end
			end)
 
			SliderContainer.MouseEnter:Connect(function()
				if not Dragging then
					TweenService
						:Create(Dot, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 16, 0, 16) })
						:Play()
				end
			end)
			SliderContainer.MouseLeave:Connect(function()
				if not Dragging then
					TweenService
						:Create(Dot, TweenInfo.new(0.2, Enum.EasingStyle.Quint), { Size = UDim2.new(0, 12, 0, 12) })
						:Play()
				end
			end)
 
			ValueInput.FocusLost:Connect(function()
				local Num = tonumber(ValueInput.Text)
				if Num then
					Value = math.clamp(math.floor(Num), Min, Max)
					local NewScale = (Value - Min) / (Max - Min)
					TweenService:Create(
						SliderFill,
						TweenInfo.new(0.3, Enum.EasingStyle.Quint),
						{ Size = UDim2.new(NewScale, 0, 1, 0) }
					):Play()
					CallbackFunc(Value)
				end
				ValueInput.Text = tostring(Value)
			end)
		end
 
function Tab:CreateImageParagraph(Title, Desc, Image)
    local Container = Instance.new("Frame", Page)
    Container.Size = UDim2.new(1, 0, 0, 0)
    Container.AutomaticSize = Enum.AutomaticSize.Y
    Container.BackgroundTransparency = 0.55
    Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 8)
    punishgoatby97mzu:ApplyThemeObj(Container, "BackgroundColor3", "ToggleBtnBg")

    local Stroke = Instance.new("UIStroke", Container)
    Stroke.Thickness = 1
    Stroke.Transparency = 0.85
    punishgoatby97mzu:ApplyThemeObj(Stroke, "Color", "Stroke")

    local Padding = Instance.new("UIPadding", Container)
    Padding.PaddingTop = UDim.new(0, 10)
    Padding.PaddingBottom = UDim.new(0, 10)
    Padding.PaddingLeft = UDim.new(0, 12)
    Padding.PaddingRight = UDim.new(0, 12)

    local Top = Instance.new("Frame", Container)
    Top.Size = UDim2.new(1, 0, 0, 40)
    Top.BackgroundTransparency = 1

    local ImageLabel = Instance.new("ImageLabel", Top)
    ImageLabel.Size = UDim2.new(0, 36, 0, 36)
    ImageLabel.Position = UDim2.new(0, 0, 0.5, -16)
    ImageLabel.BackgroundTransparency = 1
    ImageLabel.Image = Image or ""

    local Corner = Instance.new("UICorner", ImageLabel)
    Corner.CornerRadius = UDim.new(0, 5)

    local TitleLbl = Instance.new("TextLabel", Top)
    TitleLbl.Position = UDim2.new(0, 42, 0, 5)
    TitleLbl.Size = UDim2.new(1, -42, 0, 16)
    TitleLbl.BackgroundTransparency = 1
    TitleLbl.Text = Title or ""
    TitleLbl.Font = Enum.Font.GothamBold
    TitleLbl.TextSize = 14
    TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
    TitleLbl.RichText = true
    punishgoatby97mzu:ApplyThemeObj(TitleLbl, "TextColor3", "Text")

    local DescLbl = Instance.new("TextLabel", Top)
    DescLbl.Position = UDim2.new(0, 42, 0, 19)
    DescLbl.Size = UDim2.new(1, -42, 0, 14)
    DescLbl.BackgroundTransparency = 1
    DescLbl.Text = Desc or ""
    DescLbl.Font = Enum.Font.Gotham
    DescLbl.TextSize = 13.4
    DescLbl.TextXAlignment = Enum.TextXAlignment.Left
    DescLbl.RichText = true
    punishgoatby97mzu:ApplyThemeObj(DescLbl, "TextColor3", "TextInactive")

    local Obj = {}

    function Obj:SetTitle(NewTitle)
        TitleLbl.Text = NewTitle
    end

    function Obj:SetDescription(NewDesc)
        DescLbl.Text = NewDesc
    end

    function Obj:SetImage(NewImage)
        ImageLabel.Image = NewImage
    end

    return Obj
end

		function Tab:CreateInput(InputName, Description, Placeholder, ExtraIcon, ExtraCallback, TextCallback)
			if type(ExtraIcon) == "function" then
				TextCallback = ExtraIcon
				ExtraIcon = nil
				ExtraCallback = nil
			end
 
			local CallbackFunc = TextCallback or function() end
			local HasDesc = type(Description) == "string" and Description ~= ""
 
			local InputContainer = Instance.new("TextButton", Page)
			InputContainer.Active = false
			InputContainer.Size = UDim2.new(1, 0, 0, HasDesc and 52 or 36)
			InputContainer.BackgroundTransparency = 0.55
			InputContainer.AutoButtonColor = false
			InputContainer.Text = ""
			Instance.new("UICorner", InputContainer).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(InputContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local InputStroke = Instance.new("UIStroke", InputContainer)
			InputStroke.Thickness = 1
			InputStroke.Transparency = 0.85
			InputStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			punishgoatby97mzu:ApplyThemeObj(InputStroke, "Color", "Stroke")
 
			local Title = Instance.new("TextLabel", InputContainer)
			Title.Size = UDim2.new(1, ExtraIcon and -200 or -170, 0, 16)
			Title.Position = UDim2.new(0, 15, 0, HasDesc and 10 or 10)
			if not HasDesc then
				Title.Size = UDim2.new(1, ExtraIcon and -200 or -170, 1, 0)
				Title.Position = UDim2.new(0, 15, 0, 0)
			end
			Title.BackgroundTransparency = 1
			Title.Text = InputName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			if HasDesc then
				local DescLabel = Instance.new("TextLabel", InputContainer)
				DescLabel.Size = UDim2.new(1, ExtraIcon and -200 or -170, 0, 14)
				DescLabel.Position = UDim2.new(0, 15, 0, 26)
				DescLabel.BackgroundTransparency = 1
				DescLabel.Text = Description
				DescLabel.Font = Enum.Font.Gotham
				DescLabel.TextSize = 11
				DescLabel.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(DescLabel, "TextColor3", "TextInactive")
			end
 
			local TextBoxCard = Instance.new("Frame", InputContainer)
			TextBoxCard.Size = UDim2.new(0, ExtraIcon and 180 or 150, 0, 26)
			TextBoxCard.AnchorPoint = Vector2.new(1, 0.5)
			TextBoxCard.Position = UDim2.new(1, -10, 0.5, 0)
			TextBoxCard.BackgroundTransparency = 0.5
			Instance.new("UICorner", TextBoxCard).CornerRadius = UDim.new(0, 6)
			punishgoatby97mzu:ApplyThemeObj(TextBoxCard, "BackgroundColor3", "ToggleBgOff")
 
			local CardStroke = Instance.new("UIStroke", TextBoxCard)
			CardStroke.Thickness = 1
			CardStroke.Transparency = 0.7
			punishgoatby97mzu:ApplyThemeObj(CardStroke, "Color", "Stroke")
 
			local TextBox = Instance.new("TextBox", TextBoxCard)
			TextBox.Size = UDim2.new(1, ExtraIcon and -36 or -16, 1, 0)
			TextBox.Position = UDim2.new(0, 8, 0, 0)
			TextBox.BackgroundTransparency = 1
			TextBox.Text = ""
			TextBox.PlaceholderText = Placeholder or "Type here..."
			TextBox.Font = Enum.Font.GothamMedium
			TextBox.TextSize = 11
			TextBox.TextXAlignment = Enum.TextXAlignment.Left
			TextBox.ClearTextOnFocus = false
			TextBox.ClipsDescendants = true
			punishgoatby97mzu:ApplyThemeObj(TextBox, "TextColor3", "Text")
			punishgoatby97mzu:ApplyThemeObj(TextBox, "PlaceholderColor3", "TextInactive")
 
			TextBox.Focused:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(CardStroke, TweenInfo.new(0.3), { Color = palette.Accent, Transparency = 0.3 })
					:Play()
			end)
 
			TextBox.FocusLost:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(CardStroke, TweenInfo.new(0.3), { Color = palette.Stroke, Transparency = 0.7 })
					:Play()
				CallbackFunc(TextBox.Text)
			end)
			-- [FIX FOCUSLOST BUG] Save instantly so the value registers even before pressing Enter!
			TextBox:GetPropertyChangedSignal("Text"):Connect(function()
				CallbackFunc(TextBox.Text)
			end)
			-- Detect text changes instantly (real-time) on paste, without needing to press Enter
			TextBox:GetPropertyChangedSignal("Text"):Connect(function()
				CallbackFunc(TextBox.Text)
			end)
 
			if ExtraIcon then
				local ExtraBtn = Instance.new("ImageButton", TextBoxCard)
				ExtraBtn.Size = UDim2.new(0, 20, 0, 20)
				ExtraBtn.Position = UDim2.new(1, -4, 0.5, 0)
				ExtraBtn.AnchorPoint = Vector2.new(1, 0.5)
				ExtraBtn.BackgroundTransparency = 1
				ExtraBtn.Image = ExtraIcon
				punishgoatby97mzu:ApplyThemeObj(ExtraBtn, "ImageColor3", "Accent")
 
				ExtraBtn.MouseButton1Click:Connect(function()
					TweenService:Create(ExtraBtn, TweenInfo.new(0.1), { Size = UDim2.new(0, 16, 0, 16) }):Play()
					task.wait(0.1)
					TweenService:Create(ExtraBtn, TweenInfo.new(0.1), { Size = UDim2.new(0, 20, 0, 20) }):Play()
					if ExtraCallback then
						ExtraCallback(TextBox.Text)
					end
				end)
			end
		end
 
		function Tab:CreateDropdown(DropdownName)
			local Expanded = false
 
			local DropdownContainer = Instance.new("Frame", Page)
			DropdownContainer.Name = "Dropdown_" .. DropdownName
			DropdownContainer.Size = UDim2.new(1, 0, 0, 36)
			DropdownContainer.BackgroundTransparency = 0.55
			DropdownContainer.ClipsDescendants = true
			Instance.new("UICorner", DropdownContainer).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(DropdownContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local ContainerStroke = Instance.new("UIStroke", DropdownContainer)
			ContainerStroke.Thickness = 1
			ContainerStroke.Transparency = 0.85
			ContainerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			punishgoatby97mzu:ApplyThemeObj(ContainerStroke, "Color", "Stroke")
 
			local Header = Instance.new("TextButton", DropdownContainer)
			Header.Active = false
			Header.Size = UDim2.new(1, 0, 0, 36)
			Header.BackgroundTransparency = 1
			Header.AutoButtonColor = false
			Header.Text = ""
 
			local Title = Instance.new("TextLabel", Header)
			Title.Size = UDim2.new(1, -60, 1, 0)
			Title.Position = UDim2.new(0, 15, 0, 0)
			Title.BackgroundTransparency = 1
			Title.Text = DropdownName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			local Arrow = Instance.new("ImageLabel", Header)
			Arrow.Size = UDim2.new(0, 16, 0, 16)
			Arrow.AnchorPoint = Vector2.new(1, 0.5)
			Arrow.Position = UDim2.new(1, -15, 0.5, 0)
			Arrow.BackgroundTransparency = 1
			Arrow.Image = "rbxassetid://10709791523"
			punishgoatby97mzu:ApplyThemeObj(Arrow, "ImageColor3", "TextInactive")
 
			local ContentArea = Instance.new("Frame", DropdownContainer)
			ContentArea.Size = UDim2.new(1, 0, 0, 0)
			ContentArea.Position = UDim2.new(0, 0, 0, 36)
			ContentArea.BackgroundTransparency = 1
 
			local ContentPadding = Instance.new("UIPadding", ContentArea)
			ContentPadding.PaddingTop = UDim.new(0, 8)
			ContentPadding.PaddingBottom = UDim.new(0, 2)
			ContentPadding.PaddingLeft = UDim.new(0, 12)
			ContentPadding.PaddingRight = UDim.new(0, 12)
 
			local ContentLayout = Instance.new("UIListLayout", ContentArea)
			ContentLayout.SortOrder = Enum.SortOrder.LayoutOrder
			ContentLayout.Padding = UDim.new(0, 6)
 
			local function ToggleDropdown()
				Expanded = not Expanded
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
 
				if Expanded then
					local TargetHeight = 36 + 16 + ContentLayout.AbsoluteContentSize.Y
					TweenService:Create(
						DropdownContainer,
						TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{ Size = UDim2.new(1, 0, 0, TargetHeight) }
					):Play()
					TweenService
						:Create(ContainerStroke, TweenInfo.new(0.3), { Color = palette.Accent, Transparency = 0.5 })
						:Play()
					TweenService:Create(Arrow, TweenInfo.new(0.3), { ImageColor3 = palette.Accent, Rotation = 180 })
						:Play()
					TweenService:Create(Title, TweenInfo.new(0.3), { TextColor3 = palette.Accent }):Play()
				else
					TweenService:Create(
						DropdownContainer,
						TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{ Size = UDim2.new(1, 0, 0, 36) }
					):Play()
					TweenService
						:Create(ContainerStroke, TweenInfo.new(0.3), { Color = palette.Stroke, Transparency = 0.85 })
						:Play()
					TweenService:Create(Arrow, TweenInfo.new(0.3), { ImageColor3 = palette.TextInactive, Rotation = 0 })
						:Play()
					TweenService:Create(Title, TweenInfo.new(0.3), { TextColor3 = palette.Text }):Play()
				end
			end
 
			Header.MouseButton1Click:Connect(ToggleDropdown)
 
			local function ForceCloseDropdown()
				if Expanded then
					Expanded = false
					local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
					TweenService:Create(DropdownContainer, TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 36) }):Play()
					TweenService
						:Create(ContainerStroke, TweenInfo.new(0.2), { Color = palette.Stroke, Transparency = 0.85 })
						:Play()
					TweenService:Create(Arrow, TweenInfo.new(0.2), { ImageColor3 = palette.TextInactive, Rotation = 0 })
						:Play()
					TweenService:Create(Title, TweenInfo.new(0.2), { TextColor3 = palette.Text }):Play()
				end
			end
			table.insert(Window.DropdownCloseFuncs, ForceCloseDropdown)
 
			ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				if Expanded then
					local TargetHeight = 36 + 16 + ContentLayout.AbsoluteContentSize.Y
					TweenService:Create(
						DropdownContainer,
						TweenInfo.new(0.2, Enum.EasingStyle.Sine),
						{ Size = UDim2.new(1, 0, 0, TargetHeight) }
					):Play()
				end
			end)
 
			local DropdownObj = {}
			function DropdownObj:CreateToggle(...)
				local oldPage = Page
				Page = ContentArea
				Tab.CreateToggle(Tab, ...)
				Page = oldPage
			end
			function DropdownObj:CreateButton(...)
				local oldPage = Page
				Page = ContentArea
				Tab.CreateButton(Tab, ...)
				Page = oldPage
			end
			function DropdownObj:CreateSlider(...)
				local oldPage = Page
				Page = ContentArea
				Tab.CreateSlider(Tab, ...)
				Page = oldPage
			end
			function DropdownObj:CreateInput(...)
				local oldPage = Page
				Page = ContentArea
				Tab.CreateInput(Tab, ...)
				Page = oldPage
			end
			function DropdownObj:CreateSelect(...)
				local oldPage = Page
				Page = ContentArea
				Tab.CreateSelect(Tab, ...)
				Page = oldPage
			end
			return DropdownObj
		end
 
		function Tab:CreateSelect(SelectName, Description, Options, Default, Callback)
			local CallbackFunc = Callback or function() end
			local OptionsList = Options or {}
			local Expanded = false
			local HasDesc = type(Description) == "string" and Description ~= ""
 
			local SelectedItems = {}
			if type(Default) == "table" then
				for _, v in pairs(Default) do
					table.insert(SelectedItems, v)
				end
			elseif type(Default) == "string" and Default ~= "None" and Default ~= "" then
				table.insert(SelectedItems, Default)
			end
 
			local TriggerBtn = Instance.new("TextButton", Page)
			TriggerBtn.Active = false
			TriggerBtn.Size = UDim2.new(1, 0, 0, HasDesc and 52 or 36)
			TriggerBtn.BackgroundTransparency = 0.55
			TriggerBtn.AutoButtonColor = false
			TriggerBtn.Text = ""
			Instance.new("UICorner", TriggerBtn).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(TriggerBtn, "BackgroundColor3", "ToggleBtnBg")
 
			local TriggerStroke = Instance.new("UIStroke", TriggerBtn)
			TriggerStroke.Thickness = 1
			TriggerStroke.Transparency = 0.85
			TriggerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			punishgoatby97mzu:ApplyThemeObj(TriggerStroke, "Color", "Stroke")
 
			local Title = Instance.new("TextLabel", TriggerBtn)
			Title.Size = UDim2.new(0.5, -15, 0, 16)
			Title.Position = UDim2.new(0, 15, 0, HasDesc and 10 or 10)
			if not HasDesc then
				Title.Size = UDim2.new(0.5, -15, 1, 0)
				Title.Position = UDim2.new(0, 15, 0, 0)
			end
			Title.BackgroundTransparency = 1
			Title.Text = SelectName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			if HasDesc then
				local DescLabel = Instance.new("TextLabel", TriggerBtn)
				DescLabel.Size = UDim2.new(0.5, -15, 0, 14)
				DescLabel.Position = UDim2.new(0, 15, 0, 26)
				DescLabel.BackgroundTransparency = 1
				DescLabel.Text = Description
				DescLabel.Font = Enum.Font.Gotham
				DescLabel.TextSize = 11
				DescLabel.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(DescLabel, "TextColor3", "TextInactive")
			end
 
			local SelectedText = Instance.new("TextLabel", TriggerBtn)
			SelectedText.Size = UDim2.new(0.5, -35, 1, 0)
			SelectedText.Position = UDim2.new(0.5, 0, 0, 0)
			SelectedText.BackgroundTransparency = 1
			SelectedText.Font = Enum.Font.GothamMedium
			SelectedText.TextSize = 12
			SelectedText.TextXAlignment = Enum.TextXAlignment.Right
			punishgoatby97mzu:ApplyThemeObj(SelectedText, "TextColor3", "TextInactive")
 
			local Arrow = Instance.new("ImageLabel", TriggerBtn)
			Arrow.Size = UDim2.new(0, 16, 0, 16)
			Arrow.AnchorPoint = Vector2.new(1, 0.5)
			Arrow.Position = UDim2.new(1, -15, 0.5, 0)
			Arrow.BackgroundTransparency = 1
			Arrow.Image = "rbxassetid://10709790948"
			punishgoatby97mzu:ApplyThemeObj(Arrow, "ImageColor3", "TextInactive")
 
			local function UpdateTriggerText()
				-- If empty OR only "Any" / "All" is selected, automatically display "--"
				if #SelectedItems == 0 or (#SelectedItems == 1 and (SelectedItems[1] == "Any" or SelectedItems[1] == "All")) then
					SelectedText.Text = "--"
				elseif #SelectedItems == 1 then
					SelectedText.Text = SelectedItems[1]
				else
					SelectedText.Text = tostring(#SelectedItems) .. " Selected"
				end
			end
			UpdateTriggerText()
 
			local ContainerParent = ContentContainer
 
			local CloseArea = Instance.new("TextButton", ContainerParent)
			CloseArea.Size = UDim2.new(1, 0, 1, 0)
			CloseArea.BackgroundTransparency = 1
			CloseArea.Text = ""
			CloseArea.ZIndex = 9
			CloseArea.Visible = false
 
			local SidePanel = Instance.new("Frame", ContainerParent)
			SidePanel.Name = "SidePanel_" .. SelectName
			SidePanel.Size = UDim2.new(0.55, -10, 1, -10)
			SidePanel.Position = UDim2.new(1, 10, 0, 5)
			SidePanel.BackgroundTransparency = 0.05
			SidePanel.ZIndex = 10
			Instance.new("UICorner", SidePanel).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(SidePanel, "BackgroundColor3", "ToggleBgOff")
 
			local PanelStroke = Instance.new("UIStroke", SidePanel)
			PanelStroke.Thickness = 1
			PanelStroke.Transparency = 0.85
			punishgoatby97mzu:ApplyThemeObj(PanelStroke, "Color", "Stroke")
 
			local SearchContainer = Instance.new("Frame", SidePanel)
			SearchContainer.Size = UDim2.new(1, -20, 0, 30)
			SearchContainer.Position = UDim2.new(0, 10, 0, 10)
			SearchContainer.BackgroundTransparency = 0.5
			SearchContainer.ZIndex = 11
			Instance.new("UICorner", SearchContainer).CornerRadius = UDim.new(0, 6)
			punishgoatby97mzu:ApplyThemeObj(SearchContainer, "BackgroundColor3", "ToggleBtnBg")
 
			local SearchStroke = Instance.new("UIStroke", SearchContainer)
			SearchStroke.Thickness = 1
			SearchStroke.Transparency = 0.8
			punishgoatby97mzu:ApplyThemeObj(SearchStroke, "Color", "Stroke")
 
			local SearchIcon = Instance.new("ImageLabel", SearchContainer)
			SearchIcon.Size = UDim2.new(0, 14, 0, 14)
			SearchIcon.AnchorPoint = Vector2.new(0, 0.5)
			SearchIcon.Position = UDim2.new(0, 10, 0.5, 0)
			SearchIcon.BackgroundTransparency = 1
			SearchIcon.Image = "rbxassetid://10709761217"
			SearchIcon.ZIndex = 11
			punishgoatby97mzu:ApplyThemeObj(SearchIcon, "ImageColor3", "TextInactive")
 
			local SearchInput = Instance.new("TextBox", SearchContainer)
			SearchInput.Size = UDim2.new(1, -34, 1, 0)
			SearchInput.Position = UDim2.new(0, 30, 0, 0)
			SearchInput.BackgroundTransparency = 1
			SearchInput.Text = ""
			SearchInput.PlaceholderText = "Search..."
			SearchInput.Font = Enum.Font.GothamMedium
			SearchInput.TextSize = 12
			SearchInput.TextXAlignment = Enum.TextXAlignment.Left
			SearchInput.ZIndex = 11
			SearchInput.ClearTextOnFocus = false
			punishgoatby97mzu:ApplyThemeObj(SearchInput, "TextColor3", "Text")
			punishgoatby97mzu:ApplyThemeObj(SearchInput, "PlaceholderColor3", "TextInactive")
 
			SearchInput.Focused:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(SearchStroke, TweenInfo.new(0.3), { Color = palette.Accent, Transparency = 0.3 })
					:Play()
			end)
 
			SearchInput.FocusLost:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(SearchStroke, TweenInfo.new(0.3), { Color = palette.Stroke, Transparency = 0.8 })
					:Play()
			end)
 
		local ItemList = Instance.new("ScrollingFrame", SidePanel)
		ItemList.Size = UDim2.new(1, 0, 1, -55)
		ItemList.Position = UDim2.new(0, 10, 0, 50)
		ItemList.BackgroundTransparency = 1
		ItemList.BorderSizePixel = 0
		ItemList.ScrollBarThickness = 2
		ItemList.ZIndex = 11
 
		-- Use Roblox's built-in AutomaticCanvasSize so the search list doesn't lag while scrolling
		ItemList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		ItemList.CanvasSize = UDim2.new(0, 0, 0, 0)
		punishgoatby97mzu:ApplyThemeObj(ItemList, "ScrollBarImageColor3", "Stroke")
 
		local ListPadding = Instance.new("UIPadding", ItemList)
		ListPadding.PaddingLeft = UDim.new(0, 1)
		ListPadding.PaddingRight = UDim.new(0, 20)
		ListPadding.PaddingTop = UDim.new(0, 5)
 
		ListPadding.PaddingBottom = UDim.new(0, 5)
 
		local ListLayout = Instance.new("UIListLayout", ItemList)
		ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		ListLayout.Padding = UDim.new(0, 6)
 
			local OptionButtons = {}
 
			local function ClosePanel()
				Expanded = false
				CloseArea.Visible = false
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(
					SidePanel,
					TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
					{ Position = UDim2.new(1, 10, 0, 5) }
				):Play()
				TweenService:Create(Arrow, TweenInfo.new(0.3), { Rotation = 0, ImageColor3 = palette.TextInactive })
					:Play()
				TweenService:Create(TriggerStroke, TweenInfo.new(0.3), { Transparency = 0.85, Color = palette.Stroke })
					:Play()
			end
 
			table.insert(Window.SelectCloseFuncs, ClosePanel)
			CloseArea.MouseButton1Click:Connect(ClosePanel)
 
			local function RefreshOptions()
				for _, btn in pairs(OptionButtons) do
					btn:Destroy()
				end
				table.clear(OptionButtons)
 
				local FilterText = string.lower(SearchInput.Text)
 
				for _, opt in ipairs(OptionsList) do
					if FilterText == "" or string.find(string.lower(opt), FilterText) then
						local OptBtn = Instance.new("TextButton", ItemList)
						OptBtn.Active = false
						OptBtn.Size = UDim2.new(1, 0, 0, 32)
						OptBtn.BackgroundTransparency = 0.95
						OptBtn.AutoButtonColor = false
						OptBtn.Text = ""
						OptBtn.ZIndex = 12
						Instance.new("UICorner", OptBtn).CornerRadius = UDim.new(0, 6)
						punishgoatby97mzu:ApplyThemeObj(OptBtn, "BackgroundColor3", "ToggleBtnBg")
 
						local OptStroke = Instance.new("UIStroke", OptBtn)
						OptStroke.Thickness = 1
						OptStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
 
						local Indicator = Instance.new("Frame", OptBtn)
						local isSelected = table.find(SelectedItems, opt) ~= nil
						Indicator.Size = UDim2.new(0, 3, 0, isSelected and 16 or 0)
						Indicator.AnchorPoint = Vector2.new(0, 0.5)
						Indicator.Position = UDim2.new(0, 4, 0.5, 0)
						Indicator.BorderSizePixel = 0
						Indicator.ZIndex = 12
						Indicator.BackgroundTransparency = 0
						Instance.new("UICorner", Indicator).CornerRadius = UDim.new(1, 0)
						punishgoatby97mzu:ApplyThemeObj(Indicator, "BackgroundColor3", "Accent")
 
						local ItemTitle = Instance.new("TextLabel", OptBtn)
						ItemTitle.Size = UDim2.new(1, -30, 1, 0)
						ItemTitle.Position = UDim2.new(0, 15, 0, 0)
						ItemTitle.BackgroundTransparency = 1
						ItemTitle.Text = opt
						ItemTitle.Font = Enum.Font.GothamMedium
						ItemTitle.TextSize = 12
						ItemTitle.TextXAlignment = Enum.TextXAlignment.Left
						ItemTitle.ZIndex = 12
 
						if isSelected then
							OptStroke.Transparency = 0.95
							punishgoatby97mzu:ApplyThemeObj(OptStroke, "Color", "Accent")
							punishgoatby97mzu:ApplyThemeObj(ItemTitle, "TextColor3", "Accent")
							OptBtn.BackgroundTransparency = 0.55
						else
							OptStroke.Transparency = 0.85
							punishgoatby97mzu:ApplyThemeObj(OptStroke, "Color", "Stroke")
							punishgoatby97mzu:ApplyThemeObj(ItemTitle, "TextColor3", "Text")
							OptBtn.BackgroundTransparency = 0.95
						end
 
						OptBtn.MouseButton1Click:Connect(function()
							local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
							local idx = table.find(SelectedItems, opt)
 
							if idx then
								table.remove(SelectedItems, idx)
								TweenService:Create(
									Indicator,
									TweenInfo.new(0.3, Enum.EasingStyle.Quint),
									{ Size = UDim2.new(0, 3, 0, 0) }
								):Play()
								TweenService
									:Create(
										OptStroke,
										TweenInfo.new(0.3),
										{ Transparency = 0.85, Color = palette.Stroke }
									)
									:Play()
								TweenService:Create(ItemTitle, TweenInfo.new(0.3), { TextColor3 = palette.Text }):Play()
								TweenService:Create(OptBtn, TweenInfo.new(0.3), { BackgroundTransparency = 0.95 })
									:Play()
							else
								table.insert(SelectedItems, opt)
								TweenService:Create(
									Indicator,
									TweenInfo.new(0.3, Enum.EasingStyle.Quint),
									{ Size = UDim2.new(0, 3, 0, 16) }
								):Play()
								TweenService
									:Create(
										OptStroke,
										TweenInfo.new(0.3),
										{ Transparency = 0.95, Color = palette.Accent }
									)
									:Play()
								TweenService:Create(ItemTitle, TweenInfo.new(0.3), { TextColor3 = palette.Accent })
									:Play()
								TweenService:Create(OptBtn, TweenInfo.new(0.3), { BackgroundTransparency = 0.55 })
									:Play()
							end
 
							UpdateTriggerText()
							CallbackFunc(SelectedItems)
						end)
 
						table.insert(OptionButtons, OptBtn)
					end
				end
			end
 
			RefreshOptions()
 
			SearchInput:GetPropertyChangedSignal("Text"):Connect(RefreshOptions)
 
			TriggerBtn.MouseButton1Click:Connect(function()
				Expanded = not Expanded
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
 
				if Expanded then
					CloseArea.Visible = true
					TweenService:Create(
						SidePanel,
						TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
						{ Position = UDim2.new(0.45, 5, 0, 5) }
					):Play()
					TweenService:Create(Arrow, TweenInfo.new(0.3), { Rotation = 90, ImageColor3 = palette.Accent })
						:Play()
					TweenService
						:Create(TriggerStroke, TweenInfo.new(0.3), { Transparency = 0.5, Color = palette.Accent })
						:Play()
				else
					ClosePanel()
				end
			end)
 
			local SelectObj = {}
			
			-- New internal function to force a selection change from outside the library
			local function SetSelection(newSelection)
				SelectedItems = {}
				if type(newSelection) == "table" then
					for _, v in pairs(newSelection) do
						table.insert(SelectedItems, v)
					end
				elseif type(newSelection) == "string" and newSelection ~= "None" and newSelection ~= "" then
					table.insert(SelectedItems, newSelection)
				end
				UpdateTriggerText()
				RefreshOptions()
				pcall(function() CallbackFunc(SelectedItems) end)
			end
 
			-- Expose the Set function so it can be called from the main script
			function SelectObj:Set(newSelection)
				SetSelection(newSelection)
			end
 
			function SelectObj:SetValue(newSelection)
				SetSelection(newSelection)
			end
 
			-- Update the Refresh function to support auto-cleaning stale data
			function SelectObj:Refresh(NewOptions, KeepSelection)
                OptionsList = NewOptions or {}
                
                if KeepSelection == false then
                    SelectedItems = {}
                else
                    -- [SMART AUTO-CLEAN & UPGRADE SYNC]
                    local validSet = {}
                    for _, opt in ipairs(OptionsList) do
                        validSet[opt] = true
                    end
                    
                    for i = #SelectedItems, 1, -1 do
                        local item = SelectedItems[i]
                        if item ~= "Any" and item ~= "All" and not validSet[item] then
                            -- MAIN FIX: check whether this is just a level-up/mutation change, NOT actually removed
                            local baseItem = item:match("^(.-)%s*%[Lvl") or item:match("^(.-)%s*%[Lv") or item:match("^(.-)%s*%(") or item
                            
                            local foundEvolution = false
                            for _, opt in ipairs(OptionsList) do
                                local baseOpt = opt:match("^(.-)%s*%[Lvl") or opt:match("^(.-)%s*%[Lv") or opt:match("^(.-)%s*%(") or opt
                                
                                -- If the base name matches (e.g. Passionfruit) but the level differs
                                if baseItem:lower() == baseOpt:lower() then
                                    -- Automatically move the selection to the new level name!
                                    SelectedItems[i] = opt
                                    foundEvolution = true
                                    break
                                end
                            end
                            
                            -- Only deselect once the base name is truly gone (actually removed from the field)
                            if not foundEvolution then
                                table.remove(SelectedItems, i)
                            end
                        end
                    end
                end
                
                UpdateTriggerText()
                RefreshOptions()
            end
			
			return SelectObj
		end
 
		function Tab:CreateKeybind(KeybindName, Description, DefaultKey, Callback)
			local CallbackFunc = Callback or function() end
			local CurrentKey = DefaultKey or Enum.KeyCode.Unknown
			local HasDesc = type(Description) == "string" and Description ~= ""
			local Listening = false
 
			local KeybindBtn = Instance.new("Frame", Page)
			KeybindBtn.Size = UDim2.new(1, 0, 0, HasDesc and 52 or 36)
			KeybindBtn.BackgroundTransparency = 0.2
			Instance.new("UICorner", KeybindBtn).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(KeybindBtn, "BackgroundColor3", "ToggleBtnBg")
 
			local KeybindStroke = Instance.new("UIStroke", KeybindBtn)
			KeybindStroke.Thickness = 1
			KeybindStroke.Transparency = 0.85
			punishgoatby97mzu:ApplyThemeObj(KeybindStroke, "Color", "Stroke")
 
			local Title = Instance.new("TextLabel", KeybindBtn)
			Title.Size = UDim2.new(1, -110, 0, 16)
			Title.Position = UDim2.new(0, 15, 0, HasDesc and 10 or 10)
			if not HasDesc then
				Title.Size = UDim2.new(1, -110, 1, 0)
				Title.Position = UDim2.new(0, 15, 0, 0)
			end
			Title.BackgroundTransparency = 1
			Title.Text = KeybindName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			if HasDesc then
				local DescLabel = Instance.new("TextLabel", KeybindBtn)
				DescLabel.Size = UDim2.new(1, -110, 0, 14)
				DescLabel.Position = UDim2.new(0, 15, 0, 26)
				DescLabel.BackgroundTransparency = 1
				DescLabel.Text = Description
				DescLabel.Font = Enum.Font.Gotham
				DescLabel.TextSize = 11
				DescLabel.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(DescLabel, "TextColor3", "TextInactive")
			end
 
			local KeyBtn = Instance.new("TextButton", KeybindBtn)
			KeyBtn.Size = UDim2.new(0, 80, 0, 26)
			KeyBtn.AnchorPoint = Vector2.new(1, 0.5)
			KeyBtn.Position = UDim2.new(1, -12, 0.5, 0)
			KeyBtn.AutoButtonColor = false
			KeyBtn.Font = Enum.Font.GothamBold
			KeyBtn.TextSize = 12
			Instance.new("UICorner", KeyBtn).CornerRadius = UDim.new(0, 6)
			punishgoatby97mzu:ApplyThemeObj(KeyBtn, "BackgroundColor3", "ToggleBgOff")
			punishgoatby97mzu:ApplyThemeObj(KeyBtn, "TextColor3", "Text")
 
			local function KeyName()
				return (CurrentKey and CurrentKey ~= Enum.KeyCode.Unknown) and CurrentKey.Name or "None"
			end
			KeyBtn.Text = KeyName()
 
			local captureConn
			KeyBtn.MouseButton1Click:Connect(function()
				if Listening then
					return
				end
				Listening = true
				KeyBtn.Text = "..."
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				TweenService:Create(KeybindStroke, TweenInfo.new(0.2), { Color = palette.Accent, Transparency = 0.5 })
					:Play()
 
				-- One-shot listener: grabs the very next key press, then disconnects itself.
				captureConn = UserInputService.InputBegan:Connect(function(input, gpe)
					if gpe then
						return
					end
					if input.UserInputType == Enum.UserInputType.Keyboard then
						if input.KeyCode ~= Enum.KeyCode.Escape then
							CurrentKey = input.KeyCode
						end
						Listening = false
						KeyBtn.Text = KeyName()
						TweenService:Create(
							KeybindStroke,
							TweenInfo.new(0.2),
							{ Color = palette.Stroke, Transparency = 0.85 }
						):Play()
						if captureConn then
							captureConn:Disconnect()
							captureConn = nil
						end
					end
				end)
			end)
 
			-- Fires the callback whenever the bound key is pressed (ignored while rebinding).
			UserInputService.InputBegan:Connect(function(input, gpe)
				if gpe or Listening then
					return
				end
				if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == CurrentKey then
					CallbackFunc(CurrentKey)
				end
			end)
 
			local KeybindObj = {}
			function KeybindObj:Set(keyCode)
				CurrentKey = keyCode
				KeyBtn.Text = KeyName()
			end
			function KeybindObj:Get()
				return CurrentKey
			end
			return KeybindObj
		end
 
		-- Static one-liner, e.g. hints, warnings, small info text. Returns a handle
		-- with :Set(text) so it can be updated later (e.g. live status text).
		function Tab:CreateLabel(Text)
			local LabelHolder = Instance.new("Frame", Page)
			LabelHolder.Size = UDim2.new(1, 0, 0, 0)
			LabelHolder.AutomaticSize = Enum.AutomaticSize.Y
			LabelHolder.BackgroundTransparency = 1
 
			local TextLbl = Instance.new("TextLabel", LabelHolder)
			TextLbl.Size = UDim2.new(1, 0, 0, 0)
			TextLbl.AutomaticSize = Enum.AutomaticSize.Y
			TextLbl.BackgroundTransparency = 1
			TextLbl.Text = Text or ""
			TextLbl.Font = Enum.Font.Gotham
			TextLbl.TextSize = 12
			TextLbl.TextWrapped = true
			TextLbl.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(TextLbl, "TextColor3", "TextInactive")
 
			local LabelObj = {}
			function LabelObj:Set(newText)
				TextLbl.Text = newText
			end
			return LabelObj
		end
 
		-- Boxed title + body text, for longer explanations/warnings that a one-line
		-- Label wouldn't fit nicely.
		function Tab:CreateParagraph(Title, Content)
			local Container = Instance.new("Frame", Page)
			Container.Size = UDim2.new(1, 0, 0, 0)
			Container.AutomaticSize = Enum.AutomaticSize.Y
			Container.BackgroundTransparency = 0.55
			Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(Container, "BackgroundColor3", "ToggleBtnBg")
 
			local Stroke = Instance.new("UIStroke", Container)
			Stroke.Thickness = 1
			Stroke.Transparency = 0.85
			punishgoatby97mzu:ApplyThemeObj(Stroke, "Color", "Stroke")
 
			local Padding = Instance.new("UIPadding", Container)
			Padding.PaddingTop = UDim.new(0, 10)
			Padding.PaddingBottom = UDim.new(0, 10)
			Padding.PaddingLeft = UDim.new(0, 12)
			Padding.PaddingRight = UDim.new(0, 12)
 
			local Layout = Instance.new("UIListLayout", Container)
			Layout.SortOrder = Enum.SortOrder.LayoutOrder
			Layout.Padding = UDim.new(0, 4)
 
			local TitleLbl = Instance.new("TextLabel", Container)
			TitleLbl.Size = UDim2.new(1, 0, 0, 16)
			TitleLbl.BackgroundTransparency = 1
			TitleLbl.Text = Title or ""
			TitleLbl.Font = Enum.Font.GothamBold
			TitleLbl.TextSize = 13
			TitleLbl.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(TitleLbl, "TextColor3", "Text")
 
			local ContentLbl = Instance.new("TextLabel", Container)
			ContentLbl.Size = UDim2.new(1, 0, 0, 0)
			ContentLbl.AutomaticSize = Enum.AutomaticSize.Y
			ContentLbl.BackgroundTransparency = 1
			ContentLbl.Text = Content or ""
			ContentLbl.Font = Enum.Font.Gotham
			ContentLbl.TextSize = 12
			ContentLbl.TextWrapped = true
			ContentLbl.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(ContentLbl, "TextColor3", "TextInactive")
 
			local ParagraphObj = {}
			function ParagraphObj:Set(newContent)
				ContentLbl.Text = newContent
			end
			return ParagraphObj
		end
 
		-- Progress/stat bar with a :Set(value, max?) handle — good for things like
		-- Cash/Sec, farm progress, or a session counter shown right inside a tab.
		function Tab:CreateProgressBar(BarName, Max, Default)
			local MaxValue = Max or 100
			local Value = math.clamp(Default or 0, 0, MaxValue)
 
			local Container = Instance.new("Frame", Page)
			Container.Size = UDim2.new(1, 0, 0, 46)
			Container.BackgroundTransparency = 0.55
			Instance.new("UICorner", Container).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(Container, "BackgroundColor3", "ToggleBtnBg")
 
			local Stroke = Instance.new("UIStroke", Container)
			Stroke.Thickness = 1
			Stroke.Transparency = 0.85
			punishgoatby97mzu:ApplyThemeObj(Stroke, "Color", "Stroke")
 
			local Title = Instance.new("TextLabel", Container)
			Title.Size = UDim2.new(1, -80, 0, 18)
			Title.Position = UDim2.new(0, 15, 0, 6)
			Title.BackgroundTransparency = 1
			Title.Text = BarName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			local ValueLabel = Instance.new("TextLabel", Container)
			ValueLabel.Size = UDim2.new(0, 65, 0, 18)
			ValueLabel.AnchorPoint = Vector2.new(1, 0)
			ValueLabel.Position = UDim2.new(1, -15, 0, 6)
			ValueLabel.BackgroundTransparency = 1
			ValueLabel.Text = tostring(Value) .. "/" .. tostring(MaxValue)
			ValueLabel.Font = Enum.Font.GothamMedium
			ValueLabel.TextSize = 12
			ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
			punishgoatby97mzu:ApplyThemeObj(ValueLabel, "TextColor3", "TextInactive")
 
			local BarBg = Instance.new("Frame", Container)
			BarBg.Size = UDim2.new(1, -30, 0, 6)
			BarBg.Position = UDim2.new(0, 15, 1, -14)
			BarBg.BorderSizePixel = 0
			Instance.new("UICorner", BarBg).CornerRadius = UDim.new(1, 0)
			punishgoatby97mzu:ApplyThemeObj(BarBg, "BackgroundColor3", "ToggleBgOff")
 
			local BarFill = Instance.new("Frame", BarBg)
			BarFill.Size = UDim2.new(MaxValue > 0 and (Value / MaxValue) or 0, 0, 1, 0)
			BarFill.BorderSizePixel = 0
			Instance.new("UICorner", BarFill).CornerRadius = UDim.new(1, 0)
			punishgoatby97mzu:ApplyThemeObj(BarFill, "BackgroundColor3", "Accent")
 
			local BarObj = {}
			function BarObj:Set(value, max)
				if max then
					MaxValue = max
				end
				Value = math.clamp(value, 0, MaxValue)
				ValueLabel.Text = tostring(Value) .. "/" .. tostring(MaxValue)
				TweenService:Create(BarFill, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {
					Size = UDim2.new(MaxValue > 0 and (Value / MaxValue) or 0, 0, 1, 0),
				}):Play()
			end
			function BarObj:Get()
				return Value, MaxValue
			end
			return BarObj
		end
 
		-- Scrollable-friendly history/list block (e.g. "last brainrots found"). Caps
		-- itself at MaxRows so it can't grow forever like an unbounded log would.
		function Tab:CreateTable(TableName, MaxRows)
			MaxRows = MaxRows or 20
 
			if TableName and TableName ~= "" then
				local TitleLabel = Instance.new("TextLabel", Page)
				TitleLabel.Size = UDim2.new(1, 0, 0, 20)
				TitleLabel.BackgroundTransparency = 1
				TitleLabel.Text = TableName
				TitleLabel.Font = Enum.Font.GothamBold
				TitleLabel.TextSize = 13
				TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(TitleLabel, "TextColor3", "SectionTitle")
			end
 
			local ListFrame = Instance.new("Frame", Page)
			ListFrame.Size = UDim2.new(1, 0, 0, 0)
			ListFrame.AutomaticSize = Enum.AutomaticSize.Y
			ListFrame.BackgroundTransparency = 1
 
			local ListLayout = Instance.new("UIListLayout", ListFrame)
			ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
			ListLayout.Padding = UDim.new(0, 4)
 
			local Rows = {}
			local OrderCounter = 0
 
			local TableObj = {}
			function TableObj:AddRow(text)
				local Row = Instance.new("Frame", ListFrame)
				Row.Size = UDim2.new(1, 0, 0, 26)
				Row.BackgroundTransparency = 0.5
				OrderCounter = OrderCounter - 1
				Row.LayoutOrder = OrderCounter -- newest row always sorts first
				Instance.new("UICorner", Row).CornerRadius = UDim.new(0, 4)
				punishgoatby97mzu:ApplyThemeObj(Row, "BackgroundColor3", "ToggleBgOff")
 
				local RowStroke = Instance.new("UIStroke", Row)
				RowStroke.Thickness = 1
				RowStroke.Transparency = 0.8
				punishgoatby97mzu:ApplyThemeObj(RowStroke, "Color", "Stroke")
 
				local RowText = Instance.new("TextLabel", Row)
				RowText.Size = UDim2.new(1, -20, 1, 0)
				RowText.Position = UDim2.new(0, 10, 0, 0)
				RowText.BackgroundTransparency = 1
				RowText.Text = text
				RowText.Font = Enum.Font.GothamMedium
				RowText.TextSize = 11
				RowText.TextXAlignment = Enum.TextXAlignment.Left
				RowText.TextTruncate = Enum.TextTruncate.AtEnd
				punishgoatby97mzu:ApplyThemeObj(RowText, "TextColor3", "TextInactive")
 
				table.insert(Rows, 1, Row)
 
				-- [Cap] never let the history grow forever — trim the oldest row past MaxRows.
				if #Rows > MaxRows then
					local oldest = table.remove(Rows)
					oldest:Destroy()
				end
			end
 
			function TableObj:Clear()
				for _, row in ipairs(Rows) do
					row:Destroy()
				end
				Rows = {}
			end
 
			return TableObj
		end
 
		-- Two-step "arm then confirm" button for dangerous actions (e.g. reset config).
		-- First click arms it (turns red, shows ConfirmText for 3s); a second click
		-- within that window fires the callback. Avoids building a full modal/overlay.
		function Tab:CreateConfirmButton(ButtonName, Description, ConfirmText, Callback)
			local CallbackFunc = Callback or function() end
			local HasDesc = type(Description) == "string" and Description ~= ""
			local Armed = false
			local resetTask
 
			local Btn = Instance.new("TextButton", Page)
			Btn.Size = UDim2.new(1, 0, 0, HasDesc and 52 or 36)
			Btn.AutoButtonColor = false
			Btn.Text = ""
			Btn.BackgroundTransparency = 0.2
			Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 8)
			punishgoatby97mzu:ApplyThemeObj(Btn, "BackgroundColor3", "ToggleBtnBg")
 
			local BtnStroke = Instance.new("UIStroke", Btn)
			BtnStroke.Thickness = 1
			BtnStroke.Transparency = 0.85
			punishgoatby97mzu:ApplyThemeObj(BtnStroke, "Color", "Stroke")
 
			local Title = Instance.new("TextLabel", Btn)
			Title.Size = UDim2.new(1, -20, 0, 16)
			Title.Position = UDim2.new(0, 15, 0, HasDesc and 10 or 10)
			if not HasDesc then
				Title.Size = UDim2.new(1, -20, 1, 0)
				Title.Position = UDim2.new(0, 15, 0, 0)
			end
			Title.BackgroundTransparency = 1
			Title.Text = ButtonName
			Title.Font = Enum.Font.GothamMedium
			Title.TextSize = 13
			Title.TextXAlignment = Enum.TextXAlignment.Left
			punishgoatby97mzu:ApplyThemeObj(Title, "TextColor3", "Text")
 
			if HasDesc then
				local DescLabel = Instance.new("TextLabel", Btn)
				DescLabel.Size = UDim2.new(1, -20, 0, 14)
				DescLabel.Position = UDim2.new(0, 15, 0, 26)
				DescLabel.BackgroundTransparency = 1
				DescLabel.Text = Description
				DescLabel.Font = Enum.Font.Gotham
				DescLabel.TextSize = 11
				DescLabel.TextXAlignment = Enum.TextXAlignment.Left
				punishgoatby97mzu:ApplyThemeObj(DescLabel, "TextColor3", "TextInactive")
			end
 
			Btn.MouseButton1Click:Connect(function()
				local palette = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme]
				if not Armed then
					Armed = true
					Title.Text = ConfirmText or "Click again to confirm"
					TweenService:Create(
						BtnStroke,
						TweenInfo.new(0.2),
						{ Color = Color3.fromRGB(255, 75, 75), Transparency = 0.4 }
					):Play()
 
					if resetTask then
						task.cancel(resetTask)
					end
					resetTask = task.delay(3, function()
						Armed = false
						Title.Text = ButtonName
						TweenService:Create(
							BtnStroke,
							TweenInfo.new(0.2),
							{ Color = punishgoatby97mzu.Themes[punishgoatby97mzu.CurrentTheme].Stroke, Transparency = 0.85 }
						):Play()
					end)
				else
					Armed = false
					if resetTask then
						task.cancel(resetTask)
					end
					Title.Text = ButtonName
					TweenService:Create(BtnStroke, TweenInfo.new(0.2), { Color = palette.Stroke, Transparency = 0.85 })
						:Play()
					CallbackFunc()
				end
			end)
		end
 
		return Tab
	end
 
	return Window
end
 
-- ==========================================
-- [🔮] IN-GAME DYNAMIC PREDICTION HUD (DRAGGABLE, RESIZABLE & AUTO-WRAPPING)
-- ==========================================
 
local PredictHUD_UI = nil
local PredictHUD = nil
 
function punishgoatby97mzu:UpdatePredictHUD(brainrot, rarity, mutation, cps)
	-- If the toggle is off, pass nil/false as the first argument to hide the HUD
	if not brainrot then
		if PredictHUD then
			PredictHUD.Visible = false
		end
		return
	end
	
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
	
	-- Create a dedicated ScreenGui with max DisplayOrder (2147483647) so it's always above gamepass/inventory UI
	if not PredictHUD_UI then
		PredictHUD_UI = Instance.new("ScreenGui")
		PredictHUD_UI.Name = "punishgoatPredictHUD_UI"
		PredictHUD_UI.ResetOnSpawn = false
		PredictHUD_UI.IgnoreGuiInset = true
		PredictHUD_UI.DisplayOrder = 2147483647 -- Limit maksimum 32-bit integer Roblox
		PredictHUD_UI.Parent = PlayerGui
	end
	
	-- Create the HUD Frame if it doesn't exist yet
	if not PredictHUD then
		PredictHUD = Instance.new("Frame")
		PredictHUD.Name = "PredictHUD"
		-- Slightly taller (125) to fit the new Cash/Sec row
		PredictHUD.Size = UDim2.new(0, 210, 0, 125) 
		PredictHUD.Position = UDim2.new(0.02, 0, 0.22, 0) -- Pas di bawah floating button kiri
		PredictHUD.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		PredictHUD.BackgroundTransparency = 0.15
		PredictHUD.BorderSizePixel = 0
		PredictHUD.ZIndex = 400
		PredictHUD.Active = true
		PredictHUD.ClipsDescendants = true -- Agar resize memotong elemen dengan rapi
		PredictHUD.Parent = PredictHUD_UI
		
		local Corner = Instance.new("UICorner", PredictHUD)
		Corner.CornerRadius = UDim.new(0, 8)
		
		local Stroke = Instance.new("UIStroke", PredictHUD)
		Stroke.Thickness = 1
		Stroke.Color = Color3.fromRGB(121, 121, 121)
		Stroke.Transparency = 0.5
		
		local Title = Instance.new("TextLabel", PredictHUD)
		Title.Name = "HUD_Title"
		Title.Size = UDim2.new(1, 0, 0, 20)
		Title.BackgroundTransparency = 1
		Title.Text = "🔮 PREDICTION HUD"
		Title.Font = Enum.Font.GothamBold
		Title.TextSize = 11
		Title.TextColor3 = Color3.fromRGB(172, 0, 0) -- punishgoat Red Accent
		Title.ZIndex = 401
		
		local Layout = Instance.new("UIListLayout", PredictHUD)
		Layout.SortOrder = Enum.SortOrder.LayoutOrder
		Layout.Padding = UDim.new(0, 4)
		
		local Padding = Instance.new("UIPadding", PredictHUD)
		Padding.PaddingLeft = UDim.new(0, 12)
		Padding.PaddingRight = UDim.new(0, 12)
		Padding.PaddingTop = UDim.new(0, 8)
		Padding.PaddingBottom = UDim.new(0, 8)
		
		local L_Brainrot = Instance.new("TextLabel", PredictHUD)
		L_Brainrot.Name = "L_Brainrot"
		L_Brainrot.Size = UDim2.new(1, -12, 0, 18) -- Sisakan sedikit padding kanan agar tidak menabrak grip
		L_Brainrot.BackgroundTransparency = 1
		L_Brainrot.Font = Enum.Font.GothamMedium
		L_Brainrot.TextSize = 11
		L_Brainrot.TextColor3 = Color3.fromRGB(210, 210, 210)
		L_Brainrot.TextXAlignment = Enum.TextXAlignment.Left
		L_Brainrot.RichText = true
		L_Brainrot.TextWrapped = true -- AKTIFKAN TEXT WRAP AGAR TULISAN PANJANG TURUN KE BAWAH
		L_Brainrot.AutomaticSize = Enum.AutomaticSize.Y -- TINGGI OTOMATIS MENYESUAIKAN JIKA WRAP
		L_Brainrot.ZIndex = 401
		
		local L_Rarity = Instance.new("TextLabel", PredictHUD)
		L_Rarity.Name = "L_Rarity"
		L_Rarity.Size = UDim2.new(1, -12, 0, 18)
		L_Rarity.BackgroundTransparency = 1
		L_Rarity.Font = Enum.Font.GothamMedium
		L_Rarity.TextSize = 11
		L_Rarity.TextColor3 = Color3.fromRGB(210, 210, 210)
		L_Rarity.TextXAlignment = Enum.TextXAlignment.Left
		L_Rarity.RichText = true
		L_Rarity.TextWrapped = true
		L_Rarity.AutomaticSize = Enum.AutomaticSize.Y
		L_Rarity.ZIndex = 401
		
		local L_Mutation = Instance.new("TextLabel", PredictHUD)
		L_Mutation.Name = "L_Mutation"
		L_Mutation.Size = UDim2.new(1, -12, 0, 18)
		L_Mutation.BackgroundTransparency = 1
		L_Mutation.Font = Enum.Font.GothamMedium
		L_Mutation.TextSize = 11
		L_Mutation.TextColor3 = Color3.fromRGB(210, 210, 210)
		L_Mutation.TextXAlignment = Enum.TextXAlignment.Left
		L_Mutation.RichText = true
		L_Mutation.TextWrapped = true
		L_Mutation.AutomaticSize = Enum.AutomaticSize.Y
		L_Mutation.ZIndex = 401
 
		-- Add a new Label for Cash Per Second (CPS)
		local L_CPS = Instance.new("TextLabel", PredictHUD)
		L_CPS.Name = "L_CPS"
		L_CPS.Size = UDim2.new(1, -12, 0, 18)
		L_CPS.BackgroundTransparency = 1
		L_CPS.Font = Enum.Font.GothamMedium
		L_CPS.TextSize = 11
		L_CPS.TextColor3 = Color3.fromRGB(210, 210, 210)
		L_CPS.TextXAlignment = Enum.TextXAlignment.Left
		L_CPS.RichText = true
		L_CPS.TextWrapped = true
		L_CPS.AutomaticSize = Enum.AutomaticSize.Y
		L_CPS.ZIndex = 401
 
		-- Smooth drag-and-drop feature
		local draggingHUD, dragInputHUD, dragStartHUD, startPosHUD
		PredictHUD.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				draggingHUD = true
				dragStartHUD = input.Position
				startPosHUD = PredictHUD.Position
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						draggingHUD = false
					end
				end)
			end
		end)
		PredictHUD.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				dragInputHUD = input
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if input == dragInputHUD and draggingHUD then
				local delta = input.Position - dragStartHUD
				PredictHUD.Position = UDim2.new(
					startPosHUD.X.Scale,
					startPosHUD.X.Offset + delta.X,
					startPosHUD.Y.Scale,
					startPosHUD.Y.Offset + delta.Y
				)
			end
		end)
 
		-- RESIZE GRIP: bottom-right resize handle
		local ResizeGrip = Instance.new("TextButton", PredictHUD)
		ResizeGrip.Name = "ResizeGrip"
		ResizeGrip.Size = UDim2.new(0, 15, 0, 15)
		ResizeGrip.Position = UDim2.new(1, 0, 1, 0)
		ResizeGrip.AnchorPoint = Vector2.new(1, 1)
		ResizeGrip.BackgroundTransparency = 1
		ResizeGrip.Text = "◢"
		ResizeGrip.Font = Enum.Font.GothamBold
		ResizeGrip.TextSize = 10
		ResizeGrip.TextColor3 = Color3.fromRGB(121, 121, 121)
		ResizeGrip.ZIndex = 402
 
		local resizingHUD, rDragStartHUD, startSizeHUD
		ResizeGrip.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				resizingHUD = true
				rDragStartHUD = input.Position
				startSizeHUD = PredictHUD.Size
				input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						resizingHUD = false
					end
				end)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if resizingHUD and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - rDragStartHUD
				local newX = math.clamp(startSizeHUD.X.Offset + delta.X, 180, 500)
				local newY = math.clamp(startSizeHUD.Y.Offset + delta.Y, 95, 300)
				PredictHUD.Size = UDim2.new(0, newX, 0, newY)
			end
		end)
	end
	
	-- Update text
	PredictHUD.Visible = true
	PredictHUD.L_Brainrot.Text = "<b>BRAINROT:</b> " .. tostring(brainrot):upper()
	PredictHUD.L_Rarity.Text = "<b>RARITY:</b> " .. tostring(rarity):upper()
	PredictHUD.L_Mutation.Text = "<b>MUTATION:</b> " .. tostring(mutation):upper()
	-- Display the latest estimated Cash Per Second
	PredictHUD.L_CPS.Text = "<b>CASH/SEC:</b> " .. tostring(cps or "N/A"):upper()
end
 
-- ==========================================
-- [⚡] DYNAMIC VISUAL ENGINE (EXTREME POTATO MODE) - LOW-END & ANTI-CRASH
-- ==========================================
function punishgoatby97mzu:SetPotatoMode(state)
    task.spawn(function()
        local Lighting = game:GetService("Lighting")
        local Workspace = game:GetService("Workspace")
        local Terrain = Workspace:FindFirstChildOfClass("Terrain")
 
        if state then
            if self.VisualConnections.Potato then self.VisualConnections.Potato:Disconnect() end
 
            -- [BUG FIX] Build a "protected" check (characters + camera) so Potato Mode only
            -- strips the map/props, not the player's own avatar or viewmodel.
            -- With StreamingEnabled, DescendantAdded fires for every part that streams in,
            -- including character parts respawning — without this guard those get flattened too.
            local function IsProtected(obj)
                local camera = Workspace.CurrentCamera
                if camera and obj:IsDescendantOf(camera) then
                    return true
                end
                for _, player in ipairs(Players:GetPlayers()) do
                    if player.Character and obj:IsDescendantOf(player.Character) then
                        return true
                    end
                end
                return false
            end
 
            -- 1. Aggressively disable global lighting
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            Lighting.GlobalShadows = false
            Lighting.EnvironmentDiffuseScale = 0
            Lighting.EnvironmentSpecularScale = 0
            Lighting.Brightness = 2 -- Slightly raised so the map isn't pitch black once it's stripped down
            Lighting.FogEnd = 9e9
 
            -- [FIX CRASH]: every Terrain property change must be wrapped in its own pcall!
            if Terrain then
                pcall(function() Terrain.WaterWaveSize = 0 end)
                pcall(function() Terrain.WaterWaveSpeed = 0 end)
                pcall(function() Terrain.WaterReflectance = 0 end)
                pcall(function() Terrain.WaterTransparency = 0 end)
                pcall(function() Terrain.Decoration = false end)
            end
 
            -- 2. Core function that strips down every visual (extreme low-end mode)
            local function AnnihilateVisuals(obj)
                if IsProtected(obj) then return end
                pcall(function()
                    if obj:IsA("BasePart") and not obj:IsA("Terrain") then
                        -- Flatten the material (remove reflections)
                        obj.Material = Enum.Material.SmoothPlastic
                        obj.Reflectance = 0
                        obj.CastShadow = false
                        
                        -- [TARGET: BRAINROT & MAP TEXTURES]: strip the original 3D model appearance
                        if obj:IsA("MeshPart") then
                            obj.TextureID = "" 
                        end
                    elseif obj:IsA("SpecialMesh") then
                        obj.TextureId = "" 
                    elseif obj:IsA("SurfaceAppearance") then
                        -- Destroy Roblox's built-in HD/PBR texture system
                        obj:Destroy() 
                    elseif obj:IsA("Decal") or obj:IsA("Texture") then
                        obj.Transparency = 1 
                    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") or obj:IsA("Highlight") then
                        -- Disable ALL VFX including Highlight/Outline
                        obj.Enabled = false 
                    elseif obj:IsA("PostEffect") or obj:IsA("Atmosphere") or obj:IsA("Sky") then
                        obj.Enabled = false 
                    elseif obj:IsA("Light") then
                        -- Disable PointLight/SpotLight so the GPU skips lighting calculations
                        obj.Enabled = false 
                    end
                end)
            end
 
            -- 3. Run an O(N) chunked pass across the whole map (freeze-free)
            local allObjects = Workspace:GetDescendants()
            for i, obj in ipairs(allObjects) do
                AnnihilateVisuals(obj)
                -- Yield every 500 objects so the frame rate doesn't drop during the forced re-render
                if i % 500 == 0 then task.wait() end 
            end
 
            for _, obj in ipairs(Lighting:GetChildren()) do
                AnnihilateVisuals(obj)
            end
 
            -- 4. Real-time O(1) guard (auto-strips new Brainrot/VFX the moment they spawn)
            self.VisualConnections.Potato = Workspace.DescendantAdded:Connect(function(obj)
                AnnihilateVisuals(obj)
            end)
 
        else
            -- DISABLE POTATO MODE
            if self.VisualConnections.Potato then 
                self.VisualConnections.Potato:Disconnect() 
                self.VisualConnections.Potato = nil 
            end
            Lighting.GlobalShadows = true
            settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
        end
    end)
end
 
function punishgoatby97mzu:SetRTXMode(state)
    -- [FIX]: wrapped in task.spawn
    task.spawn(function()
        local Lighting = game:GetService("Lighting")
        local Workspace = game:GetService("Workspace")
        local Terrain = Workspace:FindFirstChildOfClass("Terrain")
 
        if state then
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level21
            Lighting.GlobalShadows = true
            Lighting.ShadowSoftness = 0.2
            Lighting.Brightness = 3
            Lighting.EnvironmentDiffuseScale = 1.2
            Lighting.EnvironmentSpecularScale = 1.5 
            
            Lighting.Ambient = Color3.fromRGB(130, 145, 165) 
            Lighting.OutdoorAmbient = Color3.fromRGB(180, 190, 210) 
            Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)
            Lighting.ColorShift_Top = Color3.fromRGB(255, 240, 245)
 
            if Terrain then
                Terrain.WaterWaveSize = 0.8
                Terrain.WaterWaveSpeed = 10
                Terrain.WaterReflectance = 1
                Terrain.WaterTransparency = 0.6
                Terrain.Decoration = true
            end
 
            for _, effect in ipairs(Lighting:GetChildren()) do
                if (effect:IsA("PostEffect") or effect:IsA("Atmosphere")) and effect.Name:match("punishgoat") then
                    effect:Destroy()
                end
            end
 
            local cc = Instance.new("ColorCorrectionEffect")
            cc.Name = "punishgoatColor"
            cc.Brightness = 0.05
            cc.Contrast = 0.15 
            cc.Saturation = 0.65 
            cc.TintColor = Color3.fromRGB(255, 245, 255) 
            cc.Parent = Lighting
 
            local bloom = Instance.new("BloomEffect")
            bloom.Name = "punishgoatBloom"
            bloom.Intensity = 0.5
            bloom.Size = 40
            bloom.Threshold = 2
            bloom.Parent = Lighting
 
            local sun = Instance.new("SunRaysEffect")
            sun.Name = "punishgoatSunRays"
            sun.Intensity = 0.25
            sun.Spread = 0.75
            sun.Parent = Lighting
 
            local atmos = Instance.new("Atmosphere")
            atmos.Name = "punishgoatAtmosphere"
            atmos.Density = 0.25
            atmos.Offset = 0.25
            atmos.Color = Color3.fromRGB(150, 180, 220)
            atmos.Decay = Color3.fromRGB(255, 180, 200)
            atmos.Glare = 0.2
            atmos.Haze = 0.4
            atmos.Parent = Lighting
            
            local dof = Instance.new("DepthOfFieldEffect")
            dof.Name = "punishgoatDOF"
            dof.FarIntensity = 0.25
            dof.FocusDistance = 25
            dof.InFocusRadius = 40
            dof.NearIntensity = 0
            dof.Parent = Lighting
        else
            for _, effect in ipairs(Lighting:GetChildren()) do
                if (effect:IsA("PostEffect") or effect:IsA("Atmosphere")) and effect.Name:match("punishgoat") then
                    effect:Destroy()
                end
            end
        end
    end)
end
return punishgoatby97mzu

end)()

local function FindPunishScreenGui()
	local parents = {
		game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui"),
		GetParentGui(),
	}
	for _, parent in ipairs(parents) do
		if parent then
			for _, child in ipairs(parent:GetChildren()) do
				if child:IsA("ScreenGui") and (child.Name == "punishgoatUI" or child.Name:lower():find("punish", 1, true)) then
					return child
				end
			end
		end
	end
end

function Library:Notify(opts)
	return PunishUILib:Notify(opts)
end

function Library:CreateWindow(title)
	local window = PunishUILib:CreateWindow(title)
	local adapter = setmetatable({
		Window = window,
		Tabs = {},
		ToggleKey = Enum.KeyCode.Backquote,
		Visible = true,
		ScreenGui = window.ScreenGui or FindPunishScreenGui(),
	}, WindowAdapter)
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local bound_key = adapter.ToggleBinding and adapter.ToggleBinding:Get() or adapter.ToggleKey
		if type(bound_key) == "string" then
			bound_key = Enum.KeyCode[bound_key]
		end
		if input.UserInputType == Enum.UserInputType.Keyboard
			and (input.KeyCode == Enum.KeyCode.Backquote or input.KeyCode == bound_key)
		then
			adapter:Toggle()
		end
	end)
	return adapter
end

function WindowAdapter:CreateTab(name)
	local adapter = setmetatable({
		Tab = self.Window:CreateTab(name),
		Window = self,
	}, TabAdapter)
	table.insert(self.Tabs, adapter)
	return adapter
end

function WindowAdapter:Toggle()
	if self.Window and type(self.Window.Toggle) == "function" then
		local ok = pcall(function()
			self.Window:Toggle()
		end)
		if ok then
			return
		end
	end
	self.ScreenGui = self.ScreenGui or FindPunishScreenGui()
	if self.ScreenGui then
		self.Visible = not self.ScreenGui.Enabled
		self.ScreenGui.Enabled = self.Visible
		local main = self.ScreenGui:FindFirstChild("Main")
		if main then
			main.Visible = self.Visible
		end
	end
end

function WindowAdapter:SetKeybind(key)
	if typeof(key) == "EnumItem" then
		self.ToggleKey = key
	elseif type(key) == "string" then
		self.ToggleKey = Enum.KeyCode[key]
	end
	if self.Window and self.Window.SetKeybind then
		pcall(function()
			self.Window:SetKeybind(self.ToggleKey)
		end)
	end
end

function TabAdapter:CreateSection(name)
	self.CurrentSection = self.Tab:CreateSection(name)
	return self.CurrentSection
end

function TabAdapter:CreateToggle(title, desc, default, callback)
	return self.Tab:CreateToggle(title, desc, default, callback)
end

function TabAdapter:CreateButton(title, desc, image, callback)
	return self.Tab:CreateButton(title, desc, image, callback)
end

function TabAdapter:CreateLabel(text)
	return self.Tab:CreateLabel(text or "")
end

function TabAdapter:CreateParagraph(title, content)
	return self.Tab:CreateParagraph(title, content)
end

function TabAdapter:CreateImageParagraph(title, content, image)
	return self.Tab:CreateImageParagraph(title, content, image)
end

function TabAdapter:CreateSlider(name, minimum, maximum, default, callback)
	return self.Tab:CreateSlider(name, minimum, maximum, default, callback)
end

function TabAdapter:CreateInput(name, desc, placeholder, hidden, max, callback)
	return self.Tab:CreateInput(name, desc, placeholder, hidden, max, callback)
end

function TabAdapter:CreateKeybind(name, desc, default, callback)
	local key = default
	if type(key) == "string" then
		key = Enum.KeyCode[key]
	end
	local binding = self.Tab:CreateKeybind(name, desc, key, callback)
	if name == "Toggle Keybind" then
		self.Window.ToggleBinding = binding
	end
	return binding
end

function TabAdapter:CreateDivider()
	return self.Tab:CreateDivider()
end

function TabAdapter:CreateDropdown(name)
	return self.Tab:CreateDropdown(name)
end




local t1 = {}
local t2 = {}
local v3 = unpack or table.unpack
local Players = game:GetService("Players")
t2[1] = game:GetService("RunService")
t2[2] = game:GetService("UserInputService")
t2[3] = game:GetService("TweenService")
t2[4] = game:GetService("HttpService")
t2[5] = Players.LocalPlayer
t2[6] = workspace.CurrentCamera
t2[7] = firetouchinterest or function()
end
t2[8] = math.abs
t2[9] = math.clamp
t2[10] = math.sqrt
t2[11] = os.clock
t2[12] = Vector3.new
t2[13] = Vector3.zero
local ok, result = pcall(function()
    return game:GetService("CoreGui")
end)
t1[1] = ok
t1[2] = result
local v7 = t1[1] and (t1[2] and t1[2])
if not v7 then
    v7 = t2[5]:WaitForChild("PlayerGui")
end
t2[14] = "unknown"
pcall(function()
    if identifyexecutor then
        t2[14] = identifyexecutor():lower()

        return
    end

    if getexecutorname then
        t2[14] = getexecutorname():lower()
    end
end)
local v8 = t2[14]:find("xeno")
if not v8 then
    v8 = t2[14]:find("solara")
end
if not v8 then
    t1[3] = typeof(XENO) ~= "nil"
    v8 = t1[3]

    if not t1[3] then
        t1[5] = typeof(SYN) ~= "nil"
        t1[7] = t1[5]

        if t1[5] then
            t1[9] = typeof(SYN.request) ~= "nil"
            t1[5] = t1[9]

            if t1[9] then
                t1[5] = t2[14]:find("solara")
            end

            t1[7] = t1[5]
        end

        v8 = t1[7] or false
    end
end
local v9 = v8 == true

t2[15] = Library

local t3 = {
	[1] = t2[15]:CreateWindow("angeli tps hub")
}

	t1[4] = t3[1]:CreateTab("Home", nil)
	t1[5] = t3[1]:CreateTab("Reach", nil)
	t1[15] = t3[1]:CreateTab("Kicks", nil)
	t1[6] = t3[1]:CreateTab("Xeno Reach", nil)
t1[9] = t3[1]:CreateTab("Moss", nil)
t1[8] = t3[1]:CreateTab("React", nil)
t1[7] = t3[1]
t3[2] = nil
t1[10] = t1[7]:CreateTab("Xeno Moss", nil)
t1[11] = t3[1]:CreateTab("Flags", nil)
t1[12] = t3[1]:CreateTab("Extras", nil)
t1[13] = t3[1]:CreateTab("Settings", nil)
t1[4]:CreateSection("Credits")
t1[4]:CreateParagraph("Made by", "south")
t1[4]:CreateParagraph("Discord", "discord.gg/q2ZvgAxsre")
t1[4]:CreateImageParagraph("angeli tps hub", "Welcome to angeli tps hub", "rbxassetid://129100470726516")
t1[7] = t1[4].CreateDivider
t3[3] = nil
t1[7](t1[4])
t1[4]:CreateSection("Changelog")
t1[4]:CreateParagraph("Updates", "• extras tab added\n• everything togglable i hope\n• everything improved\n• error checks added")
t3[4] = nil
t1[4]:CreateParagraph("Note", "blatant features in Extras.\nuse them when losing badly only.")
t3[5] = nil
t3[6] = nil
t3[7] = nil
t1[16] = function(p3)
    if not p3 then
        return
    end

    t3[5] = p3
    t3[6] = p3:WaitForChild("HumanoidRootPart", 3)
    t3[7] = p3:WaitForChild("Humanoid", 3)
end
t3[8] = 0.05
t3[9] = 0
t3[10] = t1[16]
t3[10](t2[5].Character)
t2[5].CharacterAdded:Connect(function(character)
    task.wait()
    t3[10](character)
end)
t3[11] = false
t3[12] = 12
t3[13] = nil
t3[14] = false
t3[15] = 12
t3[16] = nil
t3[17] = 0.05
t3[18] = 0
t1[18] = function()
    if t3[16] then
        t3[16]:Disconnect()
    end

    t3[16] = t2[1].PreSimulation:Connect(function()
        local v255 = t3[5]

        if v255 then
            v255 = t3[6] and t3[7]
        end

        if not v255 then
            return
        end

        local TPSSystem = workspace:FindFirstChild("TPSSystem")
        local v257 = TPSSystem and TPSSystem:FindFirstChild("TPS")

        if not v257 then
            return
        end

        if t2[11]() - t3[18] >= 2 then
            pcall(function()
                t3[17] = t2[9](t2[5]:GetNetworkPing(), 0.016, 0.2)
            end)
        end

        local v258 = t3[17] + 0.016666666666667
        local Position = v257.Position
        local AssemblyLinearVelocity = v257.AssemblyLinearVelocity
        local Position2 = t3[6].Position
        local AssemblyLinearVelocityY = t3[6].AssemblyLinearVelocity.Y

        if (Position + AssemblyLinearVelocity * v258 - Position2).Magnitude > t3[15] then
            return
        end

        local v263 = t3[7].FloorMaterial == Enum.Material.Air
        local v264 = AssemblyLinearVelocityY > 2
        local v265 = Position.Y > Position2.Y + 0.5
        local v266 = AssemblyLinearVelocity.Y < -3

        if not v264 then
            v264 = t3[3] and (v265 and v266)

            if not v264 then
                v264 = t3[3] and (not not v263 and v265) or t3[2]
            end
        end

        if not v264 then
            return
        end

        local Name = game.Lighting:FindFirstChild(t2[5].Name)

        if Name then
            Name = Name:FindFirstChild("PreferredFoot")
        end

        local v268

        if t3[7].RigType == Enum.HumanoidRigType.R6 then
            if Name then
                Name = Name.Value ~= 1 and "Left Leg" or "Right Leg"
            end

            v268 = Name or "Right Leg"
        else
            if Name then
                Name = Name.Value ~= 1 and "LeftLowerLeg" or "RightLowerLeg"
            end

            v268 = Name or "RightLowerLeg"
        end

        local v269 = t3[5]:FindFirstChild(v268)

        pcall(function()
            if v269 then
                t2[7](v269, v257, 0)
                t2[7](v269, v257, 1)
            end

            t2[7](t3[6], v257, 0)
            t2[7](t3[6], v257, 1)
        end)
    end)
end
t3[3] = true
t3[2] = false
t3[19] = t1[18]
t3[20] = t2[12](5, 5, 5)
t3[21] = false
t3[22] = nil
t3[23] = nil
t3[24] = false
t3[25] = Instance.new("Part")
t1[20] = t3[25]
t1[20].Anchored = true
t1[20] = t3[25]
t1[20].CanCollide = false
t1[20] = t3[25]
t1[20].Transparency = 0.7
t1[20] = t3[25]
t1[22] = Color3.fromRGB(0, 85, 255)
t1[20].Color = t1[22]
t1[20] = t3[25]
t1[20].Name = "SouthReachPart"
t1[20] = t3[25]
t1[21] = workspace
t1[20].Parent = t1[21]
t3[26] = nil
t3[27] = nil
t3[28] = nil
t3[29] = nil
t3[30] = nil
t3[31] = nil
t3[32] = function(p4)
    if not p4 then
        return
    end

    t3[26] = p4:FindFirstChild("HumanoidRootPart")
    t3[27] = p4:FindFirstChild("Humanoid")

    local RightLowerLeg = p4:FindFirstChild("RightLowerLeg")

    if not RightLowerLeg then
        RightLowerLeg = p4:FindFirstChild("Right Leg")
    end

    t3[28] = RightLowerLeg

    local LeftLowerLeg = p4:FindFirstChild("LeftLowerLeg")

    if not LeftLowerLeg then
        LeftLowerLeg = p4:FindFirstChild("Left Leg")
    end

    t3[29] = LeftLowerLeg
    t3[30] = t3[28] ~= nil
    t3[31] = t3[29] ~= nil
end
t3[32](t2[5].Character)
local CharacterAdded = t2[5].CharacterAdded
t1[17] = function(p5)
    task.wait()
    t3[32](p5)
end
CharacterAdded:Connect(t1[17])
task.spawn(function()
	while true do
		local Character = t2[5].Character

		if Character then
			local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
			local Humanoid = Character:FindFirstChild("Humanoid")
			local ref5, ref6, ref7 = t3[5], t3[6], t3[7]
			local stale = (not ref5) or (not ref6) or (not ref7) or ref5.Parent == nil or ref6.Parent == nil or ref7.Parent == nil

			if stale and HumanoidRootPart and Humanoid then
				t3[5], t3[6], t3[7] = Character, HumanoidRootPart, Humanoid
			end

			stale = (not t3[26]) or (not t3[27]) or t3[26].Parent == nil or t3[27].Parent == nil

			if stale and HumanoidRootPart and Humanoid then
				t3[26], t3[27] = HumanoidRootPart, Humanoid
			end
		end

		task.wait(0.5)
	end
end)
t3[33] = nil
t1[17] = function()
    local v49 = t3[33]

    if v49 then
        v49 = t3[33].Parent
    end

    if v49 then
        return t3[33]
    end

    local TPSSystem = workspace:FindFirstChild("TPSSystem")

    if TPSSystem then
        TPSSystem = TPSSystem:FindFirstChild("TPS")
    end

    if not TPSSystem then
        TPSSystem = workspace:FindFirstChild("Ball")
    end

    t3[33] = TPSSystem

    return t3[33]
end
t3[33] = nil
t3[34] = t1[17]
t3[35] = function(p6)
    pcall(function()
        local Character = t2[5].Character

        if not Character then
            return
        end

        local kickParts = {
            Character:FindFirstChild("HumanoidRootPart"),
            Character:FindFirstChild("RightLowerLeg") or Character:FindFirstChild("Right Leg"),
            Character:FindFirstChild("RightUpperLeg") or Character:FindFirstChild("Right Leg"),
            Character:FindFirstChild("RightFoot") or Character:FindFirstChild("Right Leg"),
            Character:FindFirstChild("LeftLowerLeg") or Character:FindFirstChild("Left Leg"),
            Character:FindFirstChild("LeftUpperLeg") or Character:FindFirstChild("Left Leg"),
            Character:FindFirstChild("LeftFoot") or Character:FindFirstChild("Left Leg")
        }

        for _, part in pairs(kickParts) do
            if part then
                t2[7](part, p6, 0)
                t2[7](part, p6, 1)
            end
        end
    end)
end
t3[36] = 8
t3[37] = {}
for i = 1, t3[36] do
    local v21 = t3[37]
    local v22 = t2[13]
    local v23 = t2[13]

    v21[i] = {
		t = 0,
		pos = v22,
		vel = v23
	}
end
t3[38] = 0
t3[39] = nil
t3[40] = nil
t3[40] = 0
t3[41] = function(p7)
    t3[38] = t3[38] % t3[36] + 1

    local v52 = t3[37][t3[38]]

    v52.t = t2[11]()
    v52.pos = p7.Position
    v52.vel = p7.AssemblyLinearVelocity

    if t3[40] < t3[36] then
        t3[40] = t3[40] + 1
    end
end
t3[42] = nil
t3[43] = nil
t3[42] = function(p8)
    return t3[37][(t3[38] - p8 - 1) % t3[36] + 1]
end
t3[44] = function(p9, p10)
    if t3[40] < 2 then
        if not p9 then
            return t2[13], t2[13]
        end

        return p9.Position + p9.AssemblyLinearVelocity * p10, p9.AssemblyLinearVelocity
    end

    local v56 = t3[42](0)
    local v57 = t3[42](1)
    local v58 = v56.t - v57.t

    if v58 <= 0 then
        v58 = 0.016
    end

    local v59 = (v56.pos.X - v57.pos.X) / v58
    local v60 = (v56.pos.Y - v57.pos.Y) / v58
    local v61 = (v56.pos.Z - v57.pos.Z) / v58
    local velX = v56.vel.X
    local velY = v56.vel.Y
    local velZ = v56.vel.Z
    local v65 = velX - v59
    local v66 = velY - v60
    local v67 = velZ - v61
    local v68 = t2[9]((v65 * v65 + v66 * v66 + v67 * v67) / 1225, 0, 1)
    local v69 = v59 * (1 - v68) + velX * v68
    local v70 = v60 * (1 - v68) + velY * v68
    local n2 = 0
    local v72 = v61 * (1 - v68) + velZ * v68
    local n3 = 0
    local n4 = 0

    if t3[40] >= 3 then
        local v75 = t3[42](2)
        local v76 = v57.t - v75.t

        if v76 > 0 then
            local v77 = (v57.pos.X - v75.pos.X) / v76
            local v78 = (v57.pos.Y - v75.pos.Y) / v76
            local v79 = (v57.pos.Z - v75.pos.Z) / v76

            n3 = t2[9]((v59 - v77) / v58, -120, 120)
            n4 = t2[9]((v60 - v78) / v58, -120, 120)
            n2 = t2[9]((v61 - v79) / v58, -120, 120)
        end
    end

    local v80 = -9.8 * p10 * p10 * (1 - v68)
    local v81 = t2[9](p10, 0.016, 0.25)
    local v82 = 0.5 * v81 * v81

    return t2[12](v56.pos.X + v69 * v81 + n3 * v82, v56.pos.Y + v70 * v81 + n4 * v82 + v80, v56.pos.Z + v72 * v81 + n2 * v82), t2[12](v69, v70, v72)
end
t3[45] = 0.05
t3[46] = 0
t3[47] = 0.1
t3[39] = -0.0013611111111111
t3[43] = 12
t3[115] = 0
local M2_TOUCH_INTERVAL = 0.05
	local function tryM2Touch(ball, unthrottled)
		if unthrottled then
			t3[35](ball)
			return
		end
		local now = t2[11]()
	if now - t3[115] < M2_TOUCH_INTERVAL then
		return
	end
	t3[115] = now
	t3[35](ball)
end
t3[48] = nil
t3[48] = function(unthrottled, custom_size, custom_part, custom_hide)
    if not t3[26] or not t3[27] then
        return
    end

    local v83 = t3[34]()

    if not v83 then
        return
    end

    if t2[11]() - t3[46] >= 2 then
        pcall(function()
            t3[45] = t2[9](t2[5]:GetNetworkPing(), 0.016, 0.25)
        end)
    end

    local Position = v83.Position
    local Position3 = t3[26].Position
    local v86 = Position.X - Position3.X
    local v87 = Position.Z - Position3.Z

    if t2[8](v86) > 32 or t2[8](v87) > 32 then
        return
    end

    t3[41](v83)

    local v88 = Position.Y - Position3.Y
    local v89 = v88 * v88
    local v90 = v86 * v86 + v89
    local v91 = t2[10](v90 + v87 * v87)
    local v92 = t3[45] + 0.016666666666667
    local v93

    if t3[45] >= t3[47] or v91 >= 7 then
        Position, v93 = t3[44](v83, v92)
    else
        v93 = v83.AssemblyLinearVelocity
    end

    local X = v93.X
    local Y = v93.Y
    local Z = v93.Z
    local v97 = t2[12](Position.X + X * 0.016666666666667, Position.Y + Y * 0.016666666666667 + t3[39], Position.Z + Z * 0.016666666666667)
	local active_size = custom_size
	local active_part = custom_part
	local active_hide = custom_hide
	active_size = active_size or t3[20]
	active_part = active_part or t3[25]
	active_hide = active_hide == nil and t3[24] or active_hide
	local v98 = active_size.X / 2
	local v99 = active_size.Y / 2
	local v100 = active_size.Z / 2
    local v101 = Position.X - Position3.X
    local v102 = Position.Y - Position3.Y
    local v103 = Position.Z - Position3.Z
    local v104 = v97.X - Position3.X
    local v105 = v97.Y - Position3.Y
    local v106 = v97.Z - Position3.Z

    if v91 < t3[43] then
			tryM2Touch(v83, unthrottled)
    end

    local v107 = v98 >= t2[8](v101)

    if v107 then
        v107 = v99 >= t2[8](v102) and v100 >= t2[8](v103)
    end

    if not v107 then
        v107 = v98 >= t2[8](v104)

        if v107 then
            v107 = v99 >= t2[8](v105) and v100 >= t2[8](v106)
        end
    end

    if v107 then
			tryM2Touch(v83, unthrottled)
    end

	if not active_hide and t3[26] then
		pcall(function()
			active_part.CFrame = t3[26].CFrame
		end)
    end
end
t3[49] = function()
    if t3[22] then
        t3[22]:Disconnect()
    end

    if t3[23] then
        t3[23]:Disconnect()
    end

    t3[25].Size = t3[20]
    t3[22] = t2[1].PreSimulation:Connect(t3[48])
end
local function v24()
    if t3[22] then
        t3[22]:Disconnect()
    end

    if t3[23] then
        t3[23]:Disconnect()
    end

    pcall(function()
        t3[25].CFrame = CFrame.new(0, -9999, 0)
    end)
end
t1[5]:CreateSection("Method 1  (not Xeno/Solara)")
if v9 then
    t1[5]:CreateLabel("WARNING: ur on Xeno/Solara — use Xeno Reach tab instead")
end
t1[5]:CreateLabel("hi.")
t1[5]:CreateToggle("Enable Reach M1", "fires leg touch on ball entry", false, function(p11)
    t3[11] = p11

		if not p11 and t3[13] then
			t3[13]:Disconnect()
			t3[13] = nil

        return
    end

    if t3[13] then
        t3[13]:Disconnect()
    end

    t3[13] = t2[1].PreSimulation:Connect(function()
        local v270 = t3[5]

        if v270 then
            v270 = t3[6] and t3[7]
        end

        if not v270 then
            return
        end

        local TPSSystem = workspace:FindFirstChild("TPSSystem")

        if TPSSystem then
            TPSSystem = TPSSystem:FindFirstChild("TPS")
        end

        local v272 = TPSSystem

        if not v272 then
            return
        end

        if t2[11]() - t3[9] >= 2 then
            pcall(function()
                t3[8] = t2[9](t2[5]:GetNetworkPing(), 0.016, 0.2)
            end)
        end

        local v273 = t3[8] + 0.016666666666667
        local v274 = v272.Position + v272.AssemblyLinearVelocity * v273

        if (t3[6].Position - v274).Magnitude > t3[12] then
            return
        end

        local Name = game.Lighting:FindFirstChild(t2[5].Name)
        local v276 = Name and Name:FindFirstChild("PreferredFoot")

        if not v276 then
            return
        end

        t3[35](v272)
    end)
end)
t1[25] = function(p12)
    local num = tonumber(p12)

    if num then
        if num > 12 then
            t2[15]:Notify({
				Title = "Reach",
				Content = "Max reach is 12.",
				Duration = 3
			})
            num = 12
        end

        t3[12] = num
    end

    if t3[11] then
        if t3[13] then
            t3[13]:Disconnect()
        end

        t3[13] = t2[1].PreSimulation:Connect(function()
            local v279 = t3[5]

            if v279 then
                v279 = t3[6] and t3[7]
            end

            if not v279 then
                return
            end

            local TPSSystem = workspace:FindFirstChild("TPSSystem")

            if TPSSystem then
                TPSSystem = TPSSystem:FindFirstChild("TPS")
            end

            local v281 = TPSSystem

            if not v281 then
                return
            end

            if t2[11]() - t3[9] >= 2 then
                pcall(function()
                    t3[8] = t2[9](t2[5]:GetNetworkPing(), 0.016, 0.2)
                end)
            end

            local v282 = t3[8] + 0.016666666666667
            local v283 = v281.Position + v281.AssemblyLinearVelocity * v282

            if (t3[6].Position - v283).Magnitude > t3[12] then
                return
            end

            local Name = game.Lighting:FindFirstChild(t2[5].Name)
            local v285 = Name and Name:FindFirstChild("PreferredFoot")

            if not v285 then
                return
            end

            t3[35](v281)
        end)
    end
end
t1[5]:CreateInput("Reach Size", "enter number", "Default: 12", nil, nil, t1[25])
t1[5]:CreateDivider()
t1[5]:CreateSection("Volley Reach  (not Xeno/Solara)")
t1[5]:CreateLabel("weird but rlly fast downward volley")
t1[5]:CreateToggle("Enable Volley Reach", "ping-aware aerial volley reach", false, function(p13)
    t3[14] = p13

		if not p13 and t3[16] then
			t3[16]:Disconnect()
			t3[16] = nil

        return
    end

    t3[19]()
end)
t1[5]:CreateSlider("Reach Radius", 3, 12, 12, function(p14)
    t3[15] = p14

    if t3[14] then
        t3[19]()
    end
end)
	t1[5]:CreateToggle("Downward Volley", "fire when ball descends above you", false, function(p15)
    t3[3] = p15
end)
t1[5]:CreateToggle("Ground Mode", "can reach on the ground too", false, function(p16)
    t3[2] = p16
end)
t1[5]:CreateDivider()
t1[5]:CreateSection("Method 2  (not Xeno/Solara)")
t1[5]:CreateLabel("Box reach | smartPredict + gravity + dual-frame check.")
local v25 = t1[5]:CreateDropdown("Shape")
v25:CreateButton("Box", "Block hitbox", nil, function()
    t3[25].Shape = Enum.PartType.Block

    if t3[21] then
        t3[49]()
    end
end)
v25:CreateButton("Sphere", "Ball hitbox", nil, function()
    t3[25].Shape = Enum.PartType.Ball

    if t3[21] then
        t3[49]()
    end
end)
v25:CreateButton("Cylinder", "Cylinder hitbox", nil, function()
    t3[25].Shape = Enum.PartType.Cylinder

    if t3[21] then
        t3[49]()
    end
end)
t1[5]:CreateToggle("Enable Reach M2", "hitbox box reach with prediction", false, function(p17)
    t3[21] = p17

    if p17 then
        t3[49]()

        return
    end

    v24()
end)
t1[5]:CreateSlider("Reach X", 1, 12, 5, function(p18)
    t3[20] = t2[12](p18, t3[20].Y, t3[20].Z)
    t3[25].Size = t3[20]

    if t3[21] then
        t3[49]()
    end
end)
t1[5]:CreateSlider("Reach Y", 1, 12, 5, function(p19)
    t3[20] = t2[12](t3[20].X, p19, t3[20].Z)
    t3[25].Size = t3[20]

    if t3[21] then
        t3[49]()
    end
end)
t1[5]:CreateSlider("Reach Z", 1, 12, 5, function(p20)
    t3[20] = t2[12](t3[20].X, t3[20].Y, p20)
    t3[25].Size = t3[20]

    if t3[21] then
        t3[49]()
    end
end)
t1[5]:CreateInput("Sync X Y Z", "set all axes at once", "Enter number", nil, nil, function(p21)
    local num = tonumber(p21)

    if num then
        if num > 12 then
            t2[15]:Notify({
				Title = "Reach",
				Content = "Max reach is 12.",
				Duration = 3
			})
            num = 12
        end

        t3[20] = t2[12](num, num, num)
        t3[25].Size = t3[20]

        if t3[21] then
            t3[49]()
        end
    end
end)
t1[5]:CreateToggle("Hide Box", "make the reach box invisible", false, function(p22)
    t3[24] = p22

    if p22 then
        pcall(function()
            t3[25].CFrame = CFrame.new(0, -9999, 0)
        end)
        t3[25].Transparency = 1

        return
    end

    t3[25].Transparency = t3[4]
end)
	local legacy_m2_pre
	local legacy_m2_stepped
	local original_m2_size = Vector3.new(5, 5, 5)
	local original_m2_hide = false
	local original_m2_part = Instance.new("Part")
	original_m2_part.Name = "OriginalM2ReachPart"
	original_m2_part.Anchored = true
	original_m2_part.CanCollide = false
	original_m2_part.Transparency = 0.7
	original_m2_part.Color = Color3.fromRGB(255, 120, 0)
	original_m2_part.Size = original_m2_size
	original_m2_part.CFrame = CFrame.new(0, -9999, 0)
	original_m2_part.Parent = workspace
	local function stop_legacy_m2()
		if legacy_m2_pre then legacy_m2_pre:Disconnect() end
		if legacy_m2_stepped then legacy_m2_stepped:Disconnect() end
		legacy_m2_pre = nil
		legacy_m2_stepped = nil
		original_m2_part.CFrame = CFrame.new(0, -9999, 0)
	end
	local function start_legacy_m2()
		stop_legacy_m2()
		legacy_m2_pre = t2[1].PreSimulation:Connect(function()
			t3[48](true, original_m2_size, original_m2_part, original_m2_hide)
		end)
		legacy_m2_stepped = t2[1].Stepped:Connect(function()
			t3[48](true, original_m2_size, original_m2_part, original_m2_hide)
		end)
	end
	t1[5]:CreateSection("Reach M2 Method")
	t1[5]:CreateLabel("Original Method 2 from Angeli.lua with independent controls.")
	local original_shape = t1[5]:CreateDropdown("Original Shape")
	original_shape:CreateButton("Box", "Block hitbox", nil, function()
		original_m2_part.Shape = Enum.PartType.Block
	end)
	original_shape:CreateButton("Sphere", "Ball hitbox", nil, function()
		original_m2_part.Shape = Enum.PartType.Ball
	end)
	original_shape:CreateButton("Cylinder", "Cylinder hitbox", nil, function()
		original_m2_part.Shape = Enum.PartType.Cylinder
	end)
	t1[5]:CreateToggle("Enable Reach M2 Original", "use the original Reach M2 method", false, function(enabled)
		if enabled then
			start_legacy_m2()
		else
			stop_legacy_m2()
		end
	end)
	t1[5]:CreateSlider("Original Reach X", 1, 12, 5, function(value)
		original_m2_size = Vector3.new(value, original_m2_size.Y, original_m2_size.Z)
		original_m2_part.Size = original_m2_size
	end)
	t1[5]:CreateSlider("Original Reach Y", 1, 12, 5, function(value)
		original_m2_size = Vector3.new(original_m2_size.X, value, original_m2_size.Z)
		original_m2_part.Size = original_m2_size
	end)
	t1[5]:CreateSlider("Original Reach Z", 1, 12, 5, function(value)
		original_m2_size = Vector3.new(original_m2_size.X, original_m2_size.Y, value)
		original_m2_part.Size = original_m2_size
	end)
	t1[5]:CreateInput("Original Sync X Y Z", "set original axes at once", "Enter number", nil, nil, function(value)
		local number = tonumber(value)
		if number then
			original_m2_size = Vector3.new(math.clamp(number, 1, 12), math.clamp(number, 1, 12), math.clamp(number, 1, 12))
			original_m2_part.Size = original_m2_size
		end
	end)
	t1[5]:CreateToggle("Hide Original Box", "hide the original M2 hitbox", false, function(hidden)
		original_m2_hide = hidden
		original_m2_part.Transparency = hidden and 1 or 0.7
		if hidden then
			original_m2_part.CFrame = CFrame.new(0, -9999, 0)
		end
	end)
	local kick_stage_enabled = { true, true, true, true }
	local kick_stage_names = { "Kick 1", "Kick 2", "Kick 3", "Kick 4" }
	local kick_policy_installed

	local function get_kick_stage(speed)
		if speed <= 30 then
			return 1
		elseif speed < 45 then
			return 2
		elseif speed < 60 then
			return 3
		end
		return 4
	end

	local function get_current_kick_stage()
		local player_gui = t2[5]:FindFirstChildOfClass("PlayerGui")
		local start = player_gui and player_gui:FindFirstChild("Start")
		local power_bar = start and start:FindFirstChild("PowerBar")
		local fill = power_bar and power_bar:FindFirstChild("PB")
		if fill then
			local progress = fill.Size.X.Offset
			if progress <= 30 then
				return 1
			elseif progress <= 75 then
				return 2
			elseif progress <= 105 then
				return 3
			end
			return 4
		end
		local backpack = t2[5]:FindFirstChild("Backpack")
		local speed = backpack and backpack:FindFirstChild("Speed")
		return get_kick_stage(speed and speed.Value or 0)
	end

	local function get_kick_parts(character)
		local parts = {}
		local names = {
			"HumanoidRootPart",
			"RightLowerLeg", "RightUpperLeg", "RightFoot", "Right Leg",
			"LeftLowerLeg", "LeftUpperLeg", "LeftFoot", "Left Leg",
		}
		local seen = {}
		for _, name in ipairs(names) do
			local part = character:FindFirstChild(name)
			if part and not seen[part] then
				seen[part] = true
				table.insert(parts, part)
			end
		end
		return parts
	end

	local function install_kick_policy()
		if kick_policy_installed then
			return
		end
		local backpack = t2[5]:FindFirstChild("Backpack")
		local module = backpack and backpack:FindFirstChild("Module")
		if not module or not module:IsA("ModuleScript") then
			return
		end
		local actions
		if not pcall(function()
			actions = require(module)
		end) or type(actions) ~= "table" or type(actions.Kick2) ~= "function" then
			return
		end
		if actions.__AngeliKickPolicy then
			kick_policy_installed = true
			return
		end
		local original_kick2 = actions.Kick2
		actions.Kick2 = function(...)
			local speed_value = backpack:FindFirstChild("Speed")
			local stage = get_current_kick_stage()
			if not kick_stage_enabled[1] and not kick_stage_enabled[2]
				and not kick_stage_enabled[3] and not kick_stage_enabled[4] then
				return original_kick2(...)
			end
			if kick_stage_enabled[stage] then
				return original_kick2(...)
			end

			local character = t2[5].Character
			if not character then
				return original_kick2(...)
			end
			local parts = get_kick_parts(character)
			local previous_touch = {}
			for _, part in ipairs(parts) do
				pcall(function()
					previous_touch[part] = part.CanTouch
					part.CanTouch = false
				end)
			end
			local result = original_kick2(...)
			task.delay(0.8, function()
				for part, can_touch in pairs(previous_touch) do
					pcall(function()
						part.CanTouch = can_touch
					end)
				end
			end)
			return result
		end
		actions.__AngeliKickPolicy = true
		kick_policy_installed = true
	end

	local kick_speed_override_enabled = false
	local kick_stage_speed = { 30, 45, 60, 70 }
	local function update_kick_policy()
		install_kick_policy()
		local backpack = t2[5]:FindFirstChild("Backpack")
		local speed_value = backpack and backpack:FindFirstChild("Speed")
		local stage = get_current_kick_stage()
		if kick_speed_override_enabled and speed_value then
			speed_value.Value = kick_stage_speed[stage]
		end
	end

	t1[15]:CreateSection("Automatic Kick Power")
	t1[15]:CreateLabel("Stages are selected automatically from the game's power bar.")
	for stage = 1, 4 do
		local current_stage = stage
		t1[15]:CreateToggle(kick_stage_names[stage], "allow this automatic kick stage to count", false, function(enabled)
			kick_stage_enabled[current_stage] = enabled
		end)
	end
	t1[15]:CreateToggle("Enable Kick Speed Override", "change the kick speed used by the power bar", false, function(enabled)
		kick_speed_override_enabled = enabled
	end)
	for stage = 1, 4 do
		local current_stage = stage
		t1[15]:CreateSlider(string.format("Kick %d Speed", stage), 0, 70, kick_stage_speed[stage], function(value)
			kick_stage_speed[current_stage] = value
		end)
	end
	t1[15]:CreateLabel("Disabled stages keep the kick animation but block ball contact.")
	t2[1].Heartbeat:Connect(update_kick_policy)
t3[50] = false
t3[51] = "Right Leg"
t3[52] = t2[12](10, 10, 10)
t3[53] = nil
t3[54] = 0
t3[55] = 0.05
t3[56] = Instance.new("Part")
t1[24] = t3[56]
t1[24].Anchored = true
t1[24] = t3[56]
t1[24].CanCollide = false
t1[24] = t3[56]
t1[24].Transparency = 0.5
t1[24] = t3[56]
t1[26] = Enum.Material.Neon
t1[24].Material = t1[26]
t1[24] = t3[56]
t1[27] = Color3.fromRGB(255, 0, 0)
t1[24].Color = t1[27]
t1[24] = t3[56]
t1[24].Size = t3[52]
t1[24] = t3[56]
t1[27] = CFrame.new(0, -9999, 0)
t1[24].CFrame = t1[27]
t1[24] = t3[56]
t1[26] = workspace
t1[24].Parent = t1[26]
t1[28] = function()
    local Name = game:GetService("Lighting"):FindFirstChild(t2[5].Name)

    if Name then
        local PreferredFoot = Name:FindFirstChild("PreferredFoot")
        local v124 = PreferredFoot

        if PreferredFoot then
            v124 = PreferredFoot:IsA("IntValue")
        end

        if v124 then
            t3[51] = PreferredFoot.Value ~= 1 and "Left Leg" or "Right Leg"
        end
    end
end
t1[26] = function(p23)

    for v128, v129 in p23:GetDescendants() do

        local v130 = v129
        local v131 = v130:IsA("Motor6D")

        if v131 then
            v131 = v130.Name:find("Fake")
        end

        if v131 then
            pcall(function()
                v130:Destroy()
            end)
        end
    end
    local Torso = p23:FindFirstChild("Torso")
    if not Torso then
        return
    end
    local v133 = p23:FindFirstChild("Right Leg")
    local v134 = p23:FindFirstChild("Left Leg")
    if v133 then
        v133.Transparency = 1
        v133.Massless = true
    end
    if v134 then
        v134.Transparency = 1
        v134.Massless = true
    end
    local Part = Instance.new("Part")
    Part.Name = "Left Leg"
    Part.Size = t2[12](1, 2, 1)
    local v136 = v134 and v134.Color
    if not v136 then
        v136 = Color3.fromRGB(200, 200, 200)
    end
    Part.Color = v136
    Part.CanCollide = false
    Part.Locked = true
    Part.Parent = p23
    local Motor6D = Instance.new("Motor6D")
    Motor6D.Name = "Fake Left Hip"
    Motor6D.Part0 = Torso
    Motor6D.Part1 = Part
    Motor6D.C0 = CFrame.new(-1, -1, 0) * CFrame.Angles(0, -1.5707963267948966, 0)
    Motor6D.C1 = CFrame.new(-0.5, 1, 0) * CFrame.Angles(0, -1.5707963267948966, 0)
    Motor6D.Parent = Torso
    local Part2 = Instance.new("Part")
    Part2.Name = "Right Leg"
    Part2.Size = t2[12](1, 2, 1)
    local v139 = v133 and v133.Color
    if not v139 then
        v139 = Color3.fromRGB(200, 200, 200)
    end
    Part2.Color = v139
    Part2.CanCollide = false
    Part2.Locked = true
    Part2.Parent = p23
    local Motor6D2 = Instance.new("Motor6D")
    Motor6D2.Name = "Fake Right Hip"
    Motor6D2.Part0 = Torso
    Motor6D2.Part1 = Part2
    Motor6D2.C0 = CFrame.new(1, -1, 0) * CFrame.Angles(0, 1.5707963267948966, 0)
    Motor6D2.C1 = CFrame.new(0.5, 1, 0) * CFrame.Angles(0, 1.5707963267948966, 0)
    Motor6D2.Parent = Torso
end
t3[57] = t1[28]
t3[58] = t1[26]
t1[6]:CreateSection("Xeno & Solara Reach")
t1[6]:CreateLabel("Moves your leg to the ball when it enters the hitbox.")
t1[6]:CreateToggle("Enable Xeno Reach", "leg teleports to ball on contact", false, function(p24)
    t3[50] = p24

    if t3[53] then
        t3[53]:Disconnect()
    end

    if not p24 then
        pcall(function()
            t3[56].CFrame = CFrame.new(0, -9999, 0)
        end)

        return
    end

    t3[57]()

    local Character = t2[5].Character

    if not Character then
        Character = t2[5].CharacterAdded:Wait()
    end

    local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart", 3)
    local v144 = t3[51] ~= "Right Leg" and "Left" or "Right"
    local v145 = Character:FindFirstChild(v144 .. " Hip", true)

    if not v145 then
        v145 = Character:FindFirstChild(v144 .. "Hip", true)
    end

    local v146 = v145
    local v147 = v146

    if v147 then
        v147 = v146:IsA("Motor6D")
    end

    if v147 then
        pcall(function()
            v146:Destroy()
        end)
    end

    t3[58](Character)

    local v148 = Character:FindFirstChild(t3[51])

    if not v148 then
        v148 = Character:FindFirstChild("RightLowerLeg")

        if not v148 then
            v148 = Character:FindFirstChild("LeftLowerLeg")
        end
    end

    local v149 = v148

    t3[54] = 0
	 t3[53] = t2[1].RenderStepped:Connect(function()
        if tick() - t3[54] < t3[55] then
            return
        end
        local v288 = t3[50]
        if v288 then
            v288 = HumanoidRootPart and v149
        end
        if not v288 then
            return
        end
        t3[56].Size = t3[52]
        pcall(function()
            t3[56].CFrame = HumanoidRootPart.CFrame
        end)
        local TPS
        local TPSSystem = workspace:FindFirstChild("TPSSystem")
        if TPSSystem then
            TPS = TPSSystem:FindFirstChild("TPS")
        end
        if not TPS then
            local Balls = workspace:FindFirstChild("Balls")

            if Balls then
                TPS = Balls:FindFirstChildWhichIsA("BasePart")
            end
        end
        if not TPS then
            return
        end
        local v292 = TPS.Position + TPS.Velocity * 0.001
        local v293 = v292 - HumanoidRootPart.Position
        local v294 = t3[52].X * 0.5
        local v295 = t3[52].Y * 0.5
        local v296 = t3[52].Z * 0.5
        local v297 = v294 >= t2[8](v293.X)
        if v297 then
            v297 = v295 >= t2[8](v293.Y)

            if v297 then
                v297 = v296 >= t2[8](v293.Z)
            end
        end
        if v297 then
            pcall(function()
                v149.CFrame = CFrame.new(v292) * CFrame.new(0, -0.6, 0)
            end)
        end
    end)
end)
t1[26] = t1[6]:CreateDropdown("Leg")
t1[26]:CreateButton("Right Leg", "use right leg", nil, function()
end)
t1[26]:CreateButton("Left Leg", "use left leg", nil, function()
end)
t1[6]:CreateSlider("Box Size X", 0, 30, 10, function(p25)
    t3[52] = t2[12](p25, t3[52].Y, t3[52].Z)
    t3[56].Size = t3[52]
end)
t1[29] = function(p26)
    t3[52] = t2[12](t3[52].X, p26, t3[52].Z)
    t3[56].Size = t3[52]
end
t1[6]:CreateSlider("Box Size Y", 0, 30, 10, t1[29])
t1[6]:CreateSlider("Box Size Z", 0, 30, 10, function(p27)
    t3[52] = t2[12](t3[52].X, t3[52].Y, p27)
    t3[56].Size = t3[52]
end)
t1[6]:CreateDivider()
t1[6]:CreateSection("Visual & Cosmetics")
t1[6]:CreateInput("Box Transparency", "0 = solid, 1 = invisible", "0.5", nil, nil, function(p28)
    t3[56].Transparency = tonumber(p28) or 0.5
end)
t1[6]:CreateToggle("Appear Normal Legs", "re-create fake legs to look normal", false, function(p29)
    if not p29 then
        return
    end

    local Character = t2[5].Character

    if not Character then
        Character = t2[5].CharacterAdded:Wait()
    end

    local Humanoid = Character:WaitForChild("Humanoid", 3)

    if not Humanoid then
        return
    end

    if Humanoid.RigType == Enum.HumanoidRigType.R6 then
        t3[58](Character)

        return
    end

    if Humanoid.RigType == Enum.HumanoidRigType.R15 then
        if Character:FindFirstChild("RightLowerLeg") then
            Character.RightLowerLeg.Transparency = 1
        end

        if Character:FindFirstChild("LeftLowerLeg") then
            Character.LeftLowerLeg.Transparency = 1
        end
    end
end)
t3[59] = false
t3[60] = nil
local function v26(p30, p31, p32, p33, p34, p35)
    if t3[60] then
        t3[60]:Disconnect()
        t3[60] = nil
    end
    local Head
    local u164
    local u165 = false
    local n5 = 0.05
    local function v167(p36)
        return p36:gsub("^DFInt", ""):gsub("^DFFlag", ""):gsub("FString", ""):gsub("FLog", ""):gsub("^FFlag", ""):gsub("^DFint", ""):gsub("^FInt", "")
    end
    local function v168(p37)
        if not setfflag then
            return
        end

        pcall(function()
            local v383 = v167("DFIntTargetTimeDelayFacctorTenths")

            if getfflag(v383) ~= nil then
                setfflag(v383, p37)

                return
            end

            if getfflag("DFIntTargetTimeDelayFacctorTenths") ~= nil then
                setfflag("DFIntTargetTimeDelayFacctorTenths", p37)
            end
        end)
    end
    task.spawn(function()
        while true do
            v168(p30)

            local v301 = p32

            if setfflag then
                pcall(function()
                    local v385 = v167("FIntInterpolationMaxDelayMSec")

                    if getfflag(v385) ~= nil then
                        setfflag(v385, v301)

                        return
                    end

                    if getfflag("FIntInterpolationMaxDelayMSec") ~= nil then
                        setfflag("FIntInterpolationMaxDelayMSec", v301)
                    end
                end)
            end

            task.wait(20)
        end
    end)
    local Character = t2[5].Character
    if Character then
        Head = Character:FindFirstChild("Head")
    end
    t2[5].CharacterAdded:Connect(function(character)
        task.wait()

        if not character then
            return
        end

        Head = character:FindFirstChild("Head")
    end)
    local function v170()
        local v304 = u164

        if v304 then
            v304 = u164.Parent
        end

        if v304 then
            return u164
        end

        local TPSSystem = workspace:FindFirstChild("TPSSystem")

        if TPSSystem then
            TPSSystem = TPSSystem:FindFirstChild("TPS")
        end

        if not TPSSystem then
            TPSSystem = workspace:FindFirstChild("Ball")
        end

        u164 = TPSSystem

        return u164
    end
    t3[60] = t2[1].PreSimulation:Connect(function()
        if not t3[59] then
            return
        end

        if not Head then
            return
        end

        local v306 = v170()

        if not v306 then
            return
        end

        local Position = v306.Position
        local HeadPosition = Head.Position

        if t2[11]() - 0 >= 2 then
            pcall(function()
                n5 = t2[9](t2[5]:GetNetworkPing(), 0.016, 0.15)
            end)
        end

        local v309 = n5 + 0.016666666666667
        local AssemblyLinearVelocity = v306.AssemblyLinearVelocity
        local v311 = Position.X + AssemblyLinearVelocity.X * v309
        local v312 = Position.Y + AssemblyLinearVelocity.Y * v309
        local v313 = Position.Z + AssemblyLinearVelocity.Z * v309
        local v314 = v311 - HeadPosition.X
        local v315 = v312 - HeadPosition.Y
        local v316 = v313 - HeadPosition.Z
        local v317 = v314 >= -p33

        if v317 then
            v317 = v314 <= p33

            if v317 then
                v317 = v316 >= -p34

                if v317 then
                    v317 = v316 <= p34

                    if v317 then
                        v317 = v315 >= 1 and v315 <= p35
                    end
                end
            end
        end

        if v317 then
            pcall(function()
                t2[7](v306, Head, 0)
                t2[7](v306, Head, 1)
            end)

            if not u165 then
                u165 = true
                v168(p31)

                return
            end
        elseif u165 then
            v168(p30)
        end
    end)
end
t1[9]:CreateSection("Head Reach & Moss")
if v9 then
    t1[9]:CreateLabel("WARNING: ur on Xeno/Solara — use Xeno Moss tab instead")
end
t1[9]:CreateLabel("Enable first, then select intensity. Ping-aware prediction.")
t1[9]:CreateToggle("Enable Moss", "activates head reach / moss", false, function(p38)
    t3[59] = p38

    if not p38 and t3[60] then
        t3[60]:Disconnect()
    end
end)
t1[30] = function()
    v26("13", "9", "90", 2.5, 1.5, 3)
end
t1[9]:CreateButton("Moss 15%  — kinda obv", "safest, highest delay", nil, t1[30])
t1[9]:CreateButton("Moss 25%  — unmossable", "hard to moss back", nil, function()
    v26("12", "8", "85", 2.7, 1.7, 3.4)
end)
t1[30] = function()
    v26("10", "6", "75", 3.1, 2.3, 4.2)
end
t1[9]:CreateButton("Moss 50%  — barely mossable", "balanced", nil, t1[30])
t1[9]:CreateButton("Moss 75%  — not mossable", "aggressive", nil, function()
    v26("8", "3", "67", 3.6, 2.9, 5.1)
end)
t1[9]:CreateButton("Moss 100% — blatant", "most aggressive, noticeable", nil, function()
    v26("6", "0", "60", 4, 3.5, 6)
end)
t1[9]:CreateDivider()
t1[9]:CreateSection("Info")
t1[9]:CreateParagraph("How Moss Works", "made by south.\nrlly good if used with smart config")
t1[9]:CreateParagraph("15% — 100%", "15% = safest (highest delay)\n100% = most aggressive (rlly broken)")
t3[61] = false
t3[62] = nil
t3[63] = "13"
t3[64] = "90"
local function v27(p39, p40)
    local function v174(p41)
        return p41:gsub("^DFInt", ""):gsub("^DFFlag", ""):gsub("FString", ""):gsub("FLog", ""):gsub("^FFlag", ""):gsub("^DFint", ""):gsub("^FInt", "")
    end

    t3[63] = p39
    t3[64] = p40

    if t3[62] then
        task.cancel(t3[62])
        t3[62] = nil
    end

    if not t3[61] then
        return
    end

    local t4 = {
		DFIntTargetTimeDelayFacctorTenths = p39,
		FIntInterpolationMaxDelayMSec = p40
	}

    t3[62] = task.spawn(function()
        while true do
            (function()
                if not setfflag then
                    return
                end

                for k, v in pairs(t4) do
                    local v388 = v
                    local v389 = v174(k)

                    pcall(function()
                        if getfflag(v389) ~= nil then
                            setfflag(v389, v388)

                            return
                        end

                        if getfflag(k) ~= nil then
                            setfflag(k, v388)
                        end
                    end)
                end
            end)()
            task.wait(20)
        end
    end)
end
t1[8]:CreateSection("React")
t1[8]:CreateLabel("Enable first, then pick level.")
t1[8]:CreateToggle("Enable React", "activates flag-based react", false, function(p42)
    t3[61] = p42

    if not p42 then
        if t3[62] then
            task.cancel(t3[62])

            return
        end
    else
        v27(t3[63], t3[64])
    end
end)
t1[34] = function()
    v27("13", "90")
end
t1[8]:CreateButton("React 15%  — not obv at all", "safest react level", nil, t1[34])
t1[8]:CreateButton("React 25%  — not obv", "light react", nil, function()
    v27("12", "85")
end)
t1[8]:CreateButton("React 50%  — balanced", "mid react", nil, function()
    v27("10", "75")
end)
t1[8]:CreateButton("React 75%  — Aggressive", "high react", nil, function()
    v27("8", "67")
end)
t1[34] = function()
    v27("6", "70")
end
t1[8]:CreateButton("React 100% — Maximum", "max react, noticeable", nil, t1[34])
t1[8]:CreateSection("Input Reaction")
t1[8]:CreateLabel("Applies the maximum react timing when G or X is pressed.")
	local fast_g_react = false
	local fast_x_react = false
	t1[8]:CreateToggle("Fast G React", "faster reaction timing for G", false, function(enabled)
	fast_g_react = enabled
end)
	t1[8]:CreateToggle("Fast X Tackle", "faster reaction timing for X tackle", false, function(enabled)
	fast_x_react = enabled
end)
t2[2].InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if (input.KeyCode == Enum.KeyCode.G and fast_g_react)
		or (input.KeyCode == Enum.KeyCode.X and fast_x_react) then
		if not t3[61] then
			t3[61] = true
		end
		v27("6", "70")
	end
end)
t1[8]:CreateDivider()
t1[8]:CreateSection("Note")
t1[8]:CreateParagraph("React vs Moss", "made by south.\nreact is basically for heading faster.")
t3[65] = nil
t3[66] = false
t1[33] = function(p43, p44, p45)
    if t3[65] then
        t3[65]:Disconnect()
        t3[65] = nil
    end
    if not t3[66] then
        return
    end
    local function v180(p46, p47, p48, p49)
        local v323 = p46.Position - p47 / 2
        local v324 = p46.Position + p47 / 2
        local v325 = p48.Position - p49 / 2
        local v326 = p48.Position + p49 / 2
        local v327 = v323.X <= v326.X

        if v327 then
            v327 = v324.X >= v325.X
        end

        if v327 then
            v327 = v323.Y <= v326.Y

            if v327 then
                v327 = v324.Y >= v325.Y
            end

            if v327 then
                v327 = v323.Z <= v326.Z

                if v327 then
                    v327 = v324.Z >= v325.Z
                end
            end
        end

        return v327
    end
    local Animation = Instance.new("Animation")
    Animation.AnimationId = "rbxassetid://301501585"
    local track
    local function v183()
        local Character = t2[5].Character

        if not Character then
            return
        end

        local Humanoid = Character:FindFirstChildOfClass("Humanoid")

        if Humanoid then
            local Animator = Humanoid:FindFirstChildOfClass("Animator")

            if not Animator then
                Animator = Instance.new("Animator", Humanoid)
            end

            Humanoid = Animator
        end

        local v331 = Humanoid

        if not v331 then
            return
        end

        local v332 = track

        if v332 then
            v332 = track.IsPlaying
        end

        if v332 then
            return
        end

        pcall(function()
            track = v331:LoadAnimation(Animation)
            track:Play()
        end)
    end
    local function v184()
        local TPSSystem = workspace:FindFirstChild("TPSSystem")

        if TPSSystem then
            TPSSystem = TPSSystem:FindFirstChild("TPS")
        end

        local v334 = TPSSystem

        if not v334 then
            return
        end

        local FE = workspace:FindFirstChild("FE")

        if FE then
            local System = FE:FindFirstChild("System")

            if System then
                System = FE.System:FindFirstChild("Header")
            end

            FE = System
        end

        local v337 = FE

        if not v337 then
            return
        end

        pcall(function()
            v337:FireServer(t2[5].UserId, v334, "Rock'n'roll Star", "NeverFearTruth", "power=95/100")
        end)
    end
    t3[65] = t2[1].Heartbeat:Connect(function()
        if not t3[66] then
            return
        end
        local Character = t2[5].Character
        if not Character then
            return
        end
        local Head = Character:FindFirstChild("Head")
        if not Head then
            return
        end
        local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")
        if not HumanoidRootPart then
            return
        end
        local v341 = Head.CFrame * CFrame.new(0, 1.5, 0)
        local v342 = t2[12](p43, p44, p45)
        local t5 = {}
        local Balls = workspace:FindFirstChild("Balls")
        local g354
        if Balls then
            for _, child in Balls:GetChildren() do
                if child:IsA("BasePart") then
                    table.insert(t5, child)
                end
            end
        end
        local TPSSystem = workspace:FindFirstChild("TPSSystem")
        if TPSSystem then
            for _, child in TPSSystem:GetChildren() do
                local v350 = child:IsA("BasePart")

                if not v350 then
                    v350 = child.Name == "TPS"
                end

                if v350 then
                    table.insert(t5, child)
                end
            end
        end
        local v351
        local v352 = false
        repeat
            local v353

            v351, v353 = t5(nil, v351)

            if not v351 then
                g354 = true
            end

            if g354 then
                break
            end

            local v355 = v353.Position + v353.Velocity * 0.001
            local v356 = CFrame.new(v355) * v353.CFrame.Rotation
        until v353.Position.Y >= HumanoidRootPart.Position.Y + 1 and v180(v341, v342, v356, v353.Size)
        if not g354 then
            v352 = true
        end
        g354 = false
        if v352 then
            v352 = true
        end
        if v352 then
            v183()
            v184()
            task.delay(0.3, function()
            end)
        end
    end)
end
t3[65] = nil
t3[67] = t1[33]
t1[10]:CreateSection("Xeno Moss (Xeno & Solara)")
t1[10]:CreateLabel("Enable first, then pick hitbox size.")
t1[10]:CreateToggle("Enable Xeno Moss", "activates Xeno/Solara heading moss", false, function(p50)
    t3[66] = p50

    if not p50 and t3[65] then
        t3[65]:Disconnect()
    end
end)
t1[31] = function()
    t3[67](2, 2.8, 3)
end
t1[10]:CreateButton("Xeno Moss 15%  — Small hitbox", "safest hitbox size", nil, t1[31])
t1[31] = function()
    t3[67](2.5, 3.2, 3.3)
end
t1[10]:CreateButton("Xeno Moss 25%  — Slight", "small-ish hitbox", nil, t1[31])
t1[31] = function()
    t3[67](3, 3.8, 3.6)
end
t1[10]:CreateButton("Xeno Moss 50%  — Balanced", "mid hitbox", nil, t1[31])
t1[10]:CreateButton("Xeno Moss 75%  — Aggressive", "large hitbox", nil, function()
    t3[67](3.5, 4.5, 4.1)
end)
t1[31] = function()
    t3[67](4, 5, 4.5)
end
t1[10]:CreateButton("Xeno Moss 100% — Max hitbox", "max hitbox, blatant", nil, t1[31])
t1[10]:CreateDivider()
t1[10]:CreateSection("Info")
t1[10]:CreateParagraph("How Xeno Moss Works", "Fires Header remote + heading animation on entry.\nWorks on Xeno & Solara executors.")
t3[68] = {
	tt = "4",
	interp = "60",
	s2 = "38720"
}
t1[32] = function(p51)
    return p51:gsub("^DFInt", ""):gsub("^DFFlag", ""):gsub("FString", ""):gsub("FLog", ""):gsub("^FFlag", ""):gsub("^DFint", ""):gsub("^FInt", "")
end
t3[69] = nil
t3[70] = nil
t1[31] = function()
    if not setfflag then
        return
    end

    local _pairs = pairs
    local tt = t3[68].tt
    local interp = t3[68].interp
    local s2 = t3[68].s2

    for v191, v192 in _pairs({
		DFIntTargetTimeDelayFacctorTenths = tt,
		FIntInterpolationMaxDelayMSec = interp,
		DFIntS2PhysicsSenderRate = s2
	}) do
        local v193 = v192
        local v194 = t3[70](v191)
        local u195 = v194
        pcall(function()
            if getfflag(u195) ~= nil then
                setfflag(u195, v193)

                return
            end

            if getfflag(v191) ~= nil then
                setfflag(v191, v193)
            end
        end)
    end
end
t3[70] = t1[32]
t3[71] = t1[31]
t1[11]:CreateSection("Flag Override")
t1[11]:CreateLabel("Manually set the three main flags.")
t1[11]:CreateInput("TargetTimeDelay", "DFIntTargetTimeDelayFacctorTenths", "Default: 4", nil, nil, function(p52)
    if p52 ~= "" then
        t3[68].tt = p52
    end
end)
t1[11]:CreateInput("Interpolation", "FIntInterpolationMaxDelayMSec", "Default: 60", nil, nil, function(p53)
    if p53 ~= "" then
        t3[68].interp = p53
    end
end)
t1[11]:CreateInput("PhysicsSenderRate", "DFIntS2PhysicsSenderRate", "Default: 38720", nil, nil, function(p54)
    if p54 ~= "" then
        t3[68].s2 = p54
    end
end)
t1[37] = function()
    if t3[69] then
        task.cancel(t3[69])
    end

    t3[69] = task.spawn(function()
        while true do
            t3[71]()
            task.wait(20)
        end
    end)
    t2[15]:Notify({
		Title = "Flags",
		Content = "Flag loop started.",
		Duration = 3
	})
end
t1[11]:CreateButton("Start Flag Loop", "start looped flag apply", nil, t1[37])
t1[37] = function()
    if t3[69] then
        task.cancel(t3[69])
    end

    t2[15]:Notify({
		Title = "Flags",
		Content = "Flag loop stopped.",
		Duration = 3
	})
end
t1[11]:CreateButton("Unlock / Stop Loop", "stop the flag loop", nil, t1[37])
t1[11]:CreateDivider()
t1[11]:CreateSection("Flag Inject (JSON)")
t1[11]:CreateLabel("Paste raw JSON. Format: {\"FlagName\":\"value\"}")
t3[72] = nil
t3[73] = {}
t1[11]:CreateInput("Flag JSON", "{\"DFIntTargetTimeDelayFacctorTenths\":\"7\"}", "Paste JSON here", nil, nil, function(p55)
    local v200 = not p55

    if not v200 then
        v200 = p55 == ""
    end

    if v200 then
        return
    end

    local ok3, result3 = pcall(function()
        return t2[4]:JSONDecode(p55)
    end)

    if ok3 then
        ok3 = type(result3) == "table"
    end

    if ok3 then
        t3[73] = result3
        t2[15]:Notify({
			Title = "Inject",
			Content = "Flags parsed.",
			Duration = 3
		})

        return
    end

    t2[15]:Notify({
		Title = "Inject Error",
		Content = "Invalid JSON.",
		Duration = 4
	})
end)
t1[11]:CreateButton("Start Inject", "start injecting parsed flags", nil, function()
    if t3[72] then
        task.cancel(t3[72])
    end

    t3[72] = task.spawn(function()
        while true do
            if setfflag then
                for k, v in pairs(t3[73]) do
                    local v359 = v
                    local v360 = t3[70](k)

                    pcall(function()
                        if getfflag(v360) ~= nil then
                            setfflag(v360, (tostring(v359)))

                            return
                        end

                        if getfflag(k) ~= nil then
                            setfflag(k, (tostring(v359)))
                        end
                    end)
                end
            end

            task.wait(20)
        end
    end)
    t2[15]:Notify({
		Title = "Inject",
		Content = "Injecting flags...",
		Duration = 3
	})
end)
t1[11]:CreateButton("Stop Inject", "stop the inject loop", nil, function()
    if t3[72] then
        task.cancel(t3[72])
    end

    t2[15]:Notify({
		Title = "Inject",
		Content = "Inject loop stopped.",
		Duration = 3
	})
end)
t1[12]:CreateSection("200kickspersecond")
t1[12]:CreateLabel("yo use only when losing badly")
t3[77] = nil
t1[42] = workspace:FindFirstChild("TPSSystem")
t1[38] = t1[42]
if t1[42] then
    t1[38] = workspace.TPSSystem:FindFirstChild("TPS")
end
t1[37] = t1[38]
if not t1[38] then
    t1[37] = workspace:FindFirstChild("Ball")
end
t3[78] = t1[37]
t1[39] = workspace:FindFirstChild("FE")
t1[37] = t1[39]
if t1[39] then
    t1[44] = workspace.FE:FindFirstChild("System")
    t1[45] = t1[44]

    if t1[44] then
        t1[45] = workspace.FE.System:FindFirstChild("Kick")
    end

    t1[37] = t1[45]
end
t3[79] = t1[37]
t1[39] = function()
    return {
		t2[5].UserId,
		t3[78],
		70,
		t2[12](400000, 350, 400000),
		false,
		true,
		0,
		"Rock'n'roll Star",
		"NeverFearTruth",
		"power=95/100"
	}
end
t3[80] = 0
t3[81] = t1[39]
t1[12]:CreateToggle("200kickspersec", "auto-fires kick remote rapidly", false, function(p61)
    if t3[77] then
        t3[77]:Disconnect()
		t3[77] = nil
    end

    if not p61 then
        return
    end

    if not t3[78] or not t3[79] then
        return
    end

    t3[77] = t2[1].PreSimulation:Connect(function()
        local Character = t2[5].Character

        if not Character then
            return
        end

        local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart")

        if not HumanoidRootPart then
            return
        end

        local v363 = t2[11]()
        local v364 = false

        if (HumanoidRootPart.Position - t3[78].Position).Magnitude <= 10 then
            v364 = v363 - t3[80] >= 0
        end

        if v364 then
            pcall(function()
                local v390 = t3[79]
                local _unpack = unpack
                local t6 = { t3[81]() }

                v390:FireServer(_unpack(v3(t6)))
            end)
        end
    end)
end)
t1[12]:CreateDivider()
t1[40] = function()
    local TPSSystem = workspace:FindFirstChild("TPSSystem")

    if TPSSystem then
        TPSSystem = TPSSystem:FindFirstChild("TPS")
    end

    if not TPSSystem then
        TPSSystem = workspace:FindFirstChild("Ball")
    end

    return TPSSystem
end
t3[82] = nil
t1[12]:CreateSection("Loop TP to Ball 4ever")
t3[83] = nil
t1[43] = function()
    t3[83] = false

    if t3[82] then
        t3[82]:Disconnect()
        t3[82] = nil
    end

    local Character = t2[5].Character
    local v212 = Character

    if Character then
        v212 = Character:FindFirstChild("HumanoidRootPart")
    end

    if v212 then
        pcall(function()
            Character.HumanoidRootPart.Anchored = false
        end)
    end
end
t3[83] = false
t3[82] = nil
t3[84] = nil
t1[41] = function()
    if t3[82] then
        t3[82]:Disconnect()
    end

    t3[83] = true
    t3[82] = t2[1].Heartbeat:Connect(function()
        local Character = t2[5].Character

        if Character then
            Character = Character:FindFirstChild("HumanoidRootPart")
        end

        local v366 = Character
        local v367 = t3[84]()

        if not v366 or not v367 then
            return
        end

        pcall(function()
            v366.AssemblyLinearVelocity = t2[13]
        end)

        local LookVector = t2[6].CFrame.LookVector

        pcall(function()
            v366.CFrame = CFrame.new(v367.Position + t2[12](0, 3.1, 0), v367.Position + t2[12](LookVector.X, 3.1, LookVector.Z))
        end)
    end)
end
t3[84] = t1[40]
t3[85] = t1[41]
t3[86] = t1[43]
t1[12]:CreateToggle("Enable Ball Stick", "teleport-locks you to the ball", false, function(p62)
    if p62 then
        t3[85]()
    else
        t3[86]()
    end
end)
t1[12]:CreateDivider()
t1[12]:CreateSection("ZZZ Helper")
t1[12]:CreateLabel("zzz helper.")
t3[87] = false
t3[88] = 9
t3[89] = nil
t3[90] = nil
t3[91] = function()
    if t3[90] then
        t3[90]:Disconnect()
    end

    if t3[89] then
        pcall(function()
            t3[89]:Destroy()
        end)
        t3[89] = nil
    end

    if not t3[87] then
        return
    end

    local Part = Instance.new("Part")

    Part.Name = "ZZZHelperPart"
    Part.Size = Vector3.new(t3[88], 0.001, t3[88])
    Part.Anchored = true
    Part.Transparency = 1
    Part.BrickColor = BrickColor.new("Bright red")
    Part.Parent = workspace
    t3[89] = Part

    local TPSSystem = workspace:FindFirstChild("TPSSystem")
    local v216 = TPSSystem

    if v216 then
        v216 = TPSSystem:FindFirstChild("TPS")
    end

    local u217 = v216

	 t3[90] = t2[1].RenderStepped:Connect(function()
        local v369 = not u217

        if not v369 then
            v369 = not u217.Parent
        end

        if v369 then
            TPSSystem = workspace:FindFirstChild("TPSSystem")

            local v370 = TPSSystem

            if v370 then
                v370 = TPSSystem:FindFirstChild("TPS")
            end

            u217 = v370
        end

        if u217 and t3[89] then
            pcall(function()
                t3[89].Position = u217.Position - Vector3.new(0, 1, 0)
            end)
        end
    end)
end
t1[53] = function(p63)
    t3[87] = p63
    t3[91]()
end
t1[12]:CreateToggle("Enable ZZZHELPER", "flat invisible part under ball", false, t1[53])
t1[52] = function(p64)
    t3[88] = p64

    if t3[87] and t3[89] then
        pcall(function()
            t3[89].Size = Vector3.new(t3[88], 0.001, t3[88])
        end)
    end
end
t1[12]:CreateSlider("Helper Size", 0, 100, 9, t1[52])
t1[12]:CreateDivider()
t1[12]:CreateSection("Target Speed")
t1[12]:CreateLabel("Locks your Speed value every frame. Toggle on/off.")
t3[92] = false
t3[93] = nil
t3[94] = 70
t1[55] = function(p65)
    t3[92] = p65

    if p65 then
        if t3[93] then
            task.cancel(t3[93])
            t3[93] = nil
        end

        t3[93] = task.spawn(function()
            while t3[92] do
                local Backpack = t2[5]:FindFirstChild("Backpack")
                local Character = t2[5].Character

                pcall(function()
                    if Backpack then
                        local Speed = Backpack:FindFirstChild("Speed")

                        if Speed then
                            Speed.Value = t3[94]
                        end
                    end

                    if Character then
                        local Speed = Character:FindFirstChild("Speed")

                        if Speed then
                            Speed.Value = t3[94]
                        end
                    end
                end)
                task.wait(0)
            end
        end)

        return
    end

    if t3[93] then
        task.cancel(t3[93])
		t3[93] = nil
    end
end
t1[12]:CreateToggle("Enable Target Speed", "freezes your speed value", false, t1[55])
t1[48] = function(p66)
    t3[94] = p66
end
t1[12]:CreateSlider("Speed Value", 1, 70, 70, t1[48])
t1[12]:CreateDivider()
t1[12]:CreateSection("Movement")
t3[95] = nil
t3[96] = false
t3[97] = nil
	t1[48] = function()
    if t3[95] then
        t3[95]:Disconnect()
        t3[95] = nil
    end
end
t3[95] = nil
	t1[55] = function()
		if t3[95] then
			t3[95]:Disconnect()
			t3[95] = nil
		end

		t3[95] = t2[1].Heartbeat:Connect(function()
        if not t3[96] then
            return
        end

        if os.clock() - 0 < 0.03 then
            return
        end

        local Character = t2[5].Character

        if Character then
            Character = Character:FindFirstChild("HumanoidRootPart")
        end

        local v376 = Character

        if not v376 then
            return
        end

        local CFrame2 = t2[6].CFrame
        local zero = Vector3.zero

        if t2[2]:IsKeyDown(Enum.KeyCode.W) then
            zero += CFrame2.LookVector
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.S) then
            zero -= CFrame2.LookVector
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.A) then
            zero -= CFrame2.RightVector
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.D) then
            zero += CFrame2.RightVector
        end

        if zero.Magnitude > 0 then
            zero = Vector3.new(zero.X, 0, zero.Z).Unit
            pcall(function()
                v376.CFrame = v376.CFrame + zero * t3[97]
            end)
        end
    end)
end
t3[97] = 1.2
t3[98] = t1[55]
t3[99] = t1[48]
t1[12]:CreateToggle("TP Walk", "teleport-based WASD movement", false, function(p67)
    t3[96] = p67

    if p67 then
        t3[98]()

        return
    end

    t3[99]()
end)
t1[12]:CreateSlider("TP Speed", 0, 4, 1, function(p68)
    t3[97] = p68
end)
t3[100] = false
t3[101] = 4
t3[102] = nil
t3[103] = nil
t3[104] = nil
t1[49] = function()
    local Character = t2[5].Character
    local v225 = Character and Character:FindFirstChild("HumanoidRootPart")

    if not v225 then
        return
    end

    if t3[103] then
        pcall(function()
            t3[103]:Destroy()
        end)
    end

    if t3[104] then
        pcall(function()
            t3[104]:Destroy()
        end)
    end

    if t3[102] then
        t3[102]:Disconnect()
    end

    t3[103] = Instance.new("BodyVelocity")
    t3[103].MaxForce = Vector3.new(9000000000, 9000000000, 9000000000)
    t3[103].P = 90000
    t3[103].Velocity = Vector3.zero
    t3[103].Parent = v225
    t3[104] = Instance.new("BodyGyro")
    t3[104].MaxTorque = Vector3.new(9000000000, 9000000000, 9000000000)
    t3[104].P = 90000
    t3[104].CFrame = v225.CFrame
    t3[104].Parent = v225
    t3[102] = t2[1].Heartbeat:Connect(function()
        local v379 = v225

        if v379 then
            v379 = v225.Parent and t3[100]
        end

        if not v379 then
            return
        end

        local CFrame3 = t2[6].CFrame
        local zero = Vector3.zero

        if t2[2]:IsKeyDown(Enum.KeyCode.W) then
            zero += CFrame3.LookVector
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.S) then
            zero -= CFrame3.LookVector
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.A) then
            zero -= CFrame3.RightVector
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.D) then
            zero += CFrame3.RightVector
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.Space) then
            zero += Vector3.new(0, 1, 0)
        end

        if t2[2]:IsKeyDown(Enum.KeyCode.LeftShift) then
            zero -= Vector3.new(0, 1, 0)
        end

        local v382 = t3[101] * 18

        pcall(function()
            if zero.Magnitude > 0 then
                t3[103].Velocity = zero.Unit * v382
            else
                t3[103].Velocity = Vector3.zero
            end

            t3[104].CFrame = CFrame3
        end)
    end)
end
t1[51] = function()
    t3[100] = false

    if t3[102] then
        t3[102]:Disconnect()
    end

    if t3[103] then
        pcall(function()
            t3[103]:Destroy()
        end)
        t3[103] = nil
    end

    if t3[104] then
        pcall(function()
            t3[104]:Destroy()
        end)
        t3[104] = nil
    end
end
t3[104] = nil
t3[105] = t1[49]
t3[106] = t1[51]
t1[12]:CreateToggle("Fly", "WASD + Space + Shift to fly", false, function(p69)
    t3[100] = p69

    if p69 then
        t3[105]()

        return
    end

    t3[106]()
end)
t1[57] = function(p70)
    t3[101] = p70
end
t1[12]:CreateSlider("Fly Power", 1, 8, 4, t1[57])
t1[12]:CreateDivider()
t1[12]:CreateSection("Sigma Xray")
t3[107] = function(p71)
    if not p71 then
        return
    end

    local GetDescendants = p71.GetDescendants

    for _, v in pairs(GetDescendants(p71)) do
        local v232 = v

        if v232:IsA("BasePart") then
            pcall(function()
                v232.Material = Enum.Material.ForceField
            end)
        end
    end
end
t1[12]:CreateToggle("Sigma Xray", "ForceField material on your character", false, function(p72)
    if p72 then
        if t2[5].Character then
            t3[107](t2[5].Character)

            return
        end
    elseif t2[5].Character then
        for _, descendant in pairs(t2[5].Character:GetDescendants()) do
            local v236 = descendant

            if v236:IsA("BasePart") then
                pcall(function()
                    v236.Material = Enum.Material.SmoothPlastic
                end)
            end
        end
    end
end)
t1[50] = function()
    local Character = t2[5].Character

    if Character then
        Character = t2[5].Character:FindFirstChildOfClass("Humanoid")
    end

    if Character then
        Character = Character.RigType == Enum.HumanoidRigType.R15
    end

    return Character
end
t3[108] = nil
t3[109] = nil
t3[110] = nil
t3[111] = 3
t3[112] = t1[50]
t3[113] = nil
t1[54] = function()
    if t3[110] then
        t3[110]:Disconnect()
    end

    if t3[109] then
        pcall(function()
            t3[109]:Stop()
        end)
    end

    if t3[108] then
        pcall(function()
            t3[108]:Destroy()
        end)
    end

    t3[109] = nil
    t3[108] = nil
    t3[110] = nil
end
t1[58] = function(p73)
    if t3[110] then
        t3[110]:Disconnect()
    end

    if t3[109] then
        pcall(function()
            t3[109]:Stop()
        end)
    end

    if t3[108] then
        pcall(function()
            t3[108]:Destroy()
        end)
    end

    local Character = t2[5].Character

    if not Character then
        return
    end

    local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")

    if not Humanoid then
        return
    end

    local Animator = Humanoid:FindFirstChildOfClass("Animator")

    if not Animator then
        Animator = Instance.new("Animator", Humanoid)
    end

    local v242 = Animator

    t3[108] = Instance.new("Animation")
    t3[108].AnimationId = not t3[112]() and "rbxassetid://148840371" or "rbxassetid://5918726674"
    pcall(function()
        t3[109] = v242:LoadAnimation(t3[108])
        t3[109].Priority = Enum.AnimationPriority.Action4
        t3[109].Looped = true
        t3[109]:Play(0.1, 1, 1)
        t3[109]:AdjustSpeed(p73 or 3)
    end)
    Humanoid.Died:Connect(function()
        t3[113]()
    end)
end
t3[113] = t1[54]
t3[114] = t1[58]
t1[12]:CreateDivider()
t1[12]:CreateSection("Air Bang")
t1[12]:CreateToggle("Air Bang", "looped jump animation", false, function(p74)
    if p74 then
        t3[114](t3[111])

        return
    end

    t3[113]()
end)
t1[59] = function(p75)
    if t3[109] then
        pcall(function()
            t3[109]:AdjustSpeed(p75)
        end)
    end
end
t1[12]:CreateSlider("Bang Speed", 1, 10, 3, t1[59])
t1[12]:CreateDivider()
t1[12]:CreateSection("IMPORTANT")
t1[12]:CreateParagraph("Warning", "Only use aggressive features when losing badly.\n\nFly = WASD+Space+Shift.\nZZZ Helper = flat invisible part under ball.\nTarget Speed = locks ur Speed value.")
t1[13]:CreateSection("Hub Settings")
	local fake_kick_key = Enum.KeyCode.F
	local fake_kick_track
	local function fake_kick()
		local backpack = t2[5]:FindFirstChild("Backpack")
		local character = t2[5].Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animations = t2[5].PlayerGui:FindFirstChild("Animations")
		if not backpack or not character or not humanoid or not animations or humanoid.Health <= 0 then
			return
		end

		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			return
		end

		local switch = backpack:FindFirstChild("Switch")
		local left = switch and switch.Value == 0
		local name
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			name = left and "MKickL" or "MKick"
		else
			name = left and "OldMKickL" or "OldMKick"
		end

		local animation = animations:FindFirstChild(name)
		if not animation then
			return
		end

		if fake_kick_track then
			pcall(function()
				fake_kick_track:Stop(0.05)
			end)
		end
		fake_kick_track = animator:LoadAnimation(animation)
		fake_kick_track.Priority = Enum.AnimationPriority.Action4
		fake_kick_track:Play(0.05, 1, 1)
	end
	t2[2].InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == fake_kick_key then
			fake_kick()
		end
	end)
	t1[13]:CreateKeybind("Fake Max Kick (No Count)", "maximum kick animation, never counts the ball", "F", function(key)
		fake_kick_key = key
	end)
	t1[13]:CreateKeybind("Toggle Keybind", "key to open/close the hub", "Backquote", function(p76)
    pcall(function()
        t3[1]:SetKeybind(p76)
    end)
end)
t1[13]:CreateDivider()
t1[13]:CreateSection("About")
t1[13]:CreateParagraph("angeli tps hub", "angeli")
t1[13]:CreateParagraph("Discord", "discord.gg/q2ZvgAxsre")
t2[15]:Notify({
	Title = "angeli tps hub Loaded",
	Content = "Backquote to toggle.  discord.gg/q2ZvgAxsre",
	Duration = 8
})
if v9 then
    task.wait(1)
    t2[15]:Notify({
		Title = "Xeno / Solara detected",
		Content = "yo ur on Xeno or Solara — please use the Xeno Reach and Xeno Moss tabs",
		Duration = 10
	})
end

local ball_chams_enabled = false
local ball_chams_connection
local ball_chams = {}

local function clear_ball_chams()
    for ball, highlight in pairs(ball_chams) do
        pcall(function()
            highlight:Destroy()
        end)
        ball_chams[ball] = nil
    end
end

local function collect_ball_parts()
    local result = {}
    local seen = {}

    local function add_ball(instance)
        if instance and instance:IsA("BasePart") and not seen[instance] then
            if instance.Name == "TPS" or instance.Name == "PSoccerBall" or instance.Name == "Bomb" or instance.Name == "Ball" then
                seen[instance] = true
                table.insert(result, instance)
            end
        end
    end

    local tps_system = workspace:FindFirstChild("TPSSystem")
    add_ball(tps_system and tps_system:FindFirstChild("TPS"))
    add_ball(workspace:FindFirstChild("Ball"))

    local balls = workspace:FindFirstChild("Balls")
    if balls then
        for _, child in ipairs(balls:GetChildren()) do
            add_ball(child)
        end
    end

    return result
end

local function update_ball_chams()
    if not ball_chams_enabled then
        return
    end

    local active = {}
    for _, ball in ipairs(collect_ball_parts()) do
        active[ball] = true
        if not ball_chams[ball] then
            local highlight = Instance.new("Highlight")
            highlight.Name = "AngeliBallChams"
            highlight.Adornee = ball
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.FillColor = Callisto.Theme.Accent
            highlight.FillTransparency = 0.35
            highlight.OutlineColor = Callisto.Theme.AccentLight
            highlight.OutlineTransparency = 0
            highlight.Parent = ball
            ball_chams[ball] = highlight
        end
    end

    for ball, highlight in pairs(ball_chams) do
        if not active[ball] or not ball.Parent then
            pcall(function()
                highlight:Destroy()
            end)
            ball_chams[ball] = nil
        end
    end
end

local function set_ball_chams(enabled)
    ball_chams_enabled = enabled

    if ball_chams_connection then
        ball_chams_connection:Disconnect()
        ball_chams_connection = nil
    end

    clear_ball_chams()

    if enabled then
        update_ball_chams()
        ball_chams_connection = t2[1].Heartbeat:Connect(update_ball_chams)
    end
end

t1[12]:CreateSection("Ball Visuals")
t1[12]:CreateToggle("Ball Chams", "highlight the active ball through the map", false, set_ball_chams)
