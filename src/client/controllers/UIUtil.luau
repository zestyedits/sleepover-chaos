--!strict
-- UIUtil — tiny helpers for building the greybox UI in code (no .rbxmx assets needed).
-- The client is presentation-only; these keep the controllers terse.

local UIUtil = {}

-- Cozy-leaning placeholder palette (GDD §16 warm, colorful-but-tasteful).
UIUtil.palette = {
	bg = Color3.fromRGB(38, 34, 52),
	panel = Color3.fromRGB(52, 46, 74),
	accent = Color3.fromRGB(240, 140, 190),
	accent2 = Color3.fromRGB(140, 200, 240),
	text = Color3.fromRGB(245, 240, 250),
	subtext = Color3.fromRGB(190, 185, 205),
	good = Color3.fromRGB(150, 220, 150),
	warn = Color3.fromRGB(250, 200, 120),
	chaos = Color3.fromRGB(250, 130, 130),
}

function UIUtil.make(className: string, props: { [string]: any }, children: { Instance }?): Instance
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function UIUtil.corner(radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	return corner
end

function UIUtil.padding(px: number): UIPadding
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, px)
	pad.PaddingRight = UDim.new(0, px)
	pad.PaddingTop = UDim.new(0, px)
	pad.PaddingBottom = UDim.new(0, px)
	return pad
end

-- Colour for an announce style (matches server-side style strings).
function UIUtil.styleColor(style: string): Color3
	if style == "chaos" then
		return UIUtil.palette.chaos
	elseif style == "result" then
		return UIUtil.palette.good
	elseif style == "event" then
		return UIUtil.palette.accent
	elseif style == "warn" then
		return UIUtil.palette.warn
	end
	return UIUtil.palette.text
end

return UIUtil
