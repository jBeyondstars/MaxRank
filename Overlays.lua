-- Overlays: glow on outdated action buttons, padlock on ignored ranks, and the ignore mode.
--
-- Everything here is our own frames parented to Blizzard's action buttons. Nothing is written into
-- Blizzard tables and nothing is hooked (hooksecurefunc misbehaves while taintLog is on in this build).

local ADDON, ns = ...

local BUTTON_NAMES = ActionButtonUtil and ActionButtonUtil.ActionBarButtonNames or {
	"ActionButton",
	"MultiBarBottomLeftButton",
	"MultiBarBottomRightButton",
	"MultiBarLeftButton",
	"MultiBarRightButton",
	"MultiBar5Button",
	"MultiBar6Button",
	"MultiBar7Button",
}
local BUTTONS_PER_BAR = NUM_ACTIONBAR_BUTTONS or 12
local MAX_ACTION_SLOT = 180
local OVERLAY_LEVEL = 3		-- above the icon and cooldown, below the hotkey and count text
local CATCHER_LEVEL = 20	-- above every part of the button

-- Outdated glow: Blizzard's proc art (ActionButtonSpellAlerts.xml), drawn additively for extra light.
local LOOP_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"
local BURST_ATLAS = "UI-HUD-ActionBar-Proc-Start-Flipbook"
local BLOOM_ATLAS = "UI-HUD-RotationHelper-ProcAltGlow"
local ICON_MASK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mask"
local BORDER_FILE = "Interface\\Buttons\\UI-ActionButton-Border"
local REF_SIZE = 45			-- button size Blizzard's proc art is drawn for
local GLOW_SCALE = 1.4		-- the proc alert frame is 1.4x the button
local BURST_SIZE = 150		-- proc burst size on a REF_SIZE button
local BORDER_SCALE = 1.9	-- UI-ActionButton-Border has wide transparent margins
local FLIPBOOK_ROWS, FLIPBOOK_COLUMNS, FLIPBOOK_FRAMES = 6, 5, 30
local LOOP_TIME, BURST_TIME = 1, 0.7
local BREATH_TIME = 0.9			-- bloom and icon shine pulse, each way
local BLOOM_LOW = 0.45			-- bloom alpha at the bottom of a breath
local SHINE_HIGH, SHINE_LOW = 0.55, 0.15	-- icon brightening, additive
local GLOW_COLOR = { 1, 0.85, 0.2 }		-- only for the fallback border

-- Ignored mark, styled like Blizzard's Level Link lock: greyed icon, padlock in the middle
-- (the top right corner belongs to the hotkey text).
local IGNORED_COLOR = { 0.35, 0.65, 1 }
local VEIL_SHADE = 0.5			-- brightness of the greyed copy of the icon
local LOCK_ATLAS = "QuestSharing-Padlock"
local LOCK_FILE = "Interface\\PetBattles\\PetBattle-LockIcon"
local LOCK_SCALE = 1.25			-- relative to Blizzard's padlock on a REF_SIZE button
local LOCK_SIZE = 20			-- padlock size when the atlas is missing

local buttons			-- Blizzard action buttons, collected on first use
local overlays = {}		-- [button] = overlay frame
local catchers = {}		-- [button] = click catcher used in ignore mode
local highlightOn, pickMode = false, false

local function GetButtons()
	if not buttons then
		buttons = {}
		for _, prefix in ipairs(BUTTON_NAMES) do
			for i = 1, BUTTONS_PER_BAR do
				local b = _G[prefix .. i]
				if b then buttons[#buttons + 1] = b end
			end
		end
	end
	return buttons
end

local function ButtonSlot(button)
	local slot = ns.Val(button.action)
	if type(slot) == "number" and slot > 0 and slot <= MAX_ACTION_SLOT then return slot end
	return nil
end

local function AtlasInfo(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
end

local function SetAtlasOr(tex, atlas, file)
	if AtlasInfo(atlas) then
		tex:SetAtlas(atlas)
		return true
	end
	tex:SetTexture(file)
	return false
end

-- Clip a texture to the rounded shape of action button icons.
local function MaskToIcon(frame, tex)
	if not AtlasInfo(ICON_MASK_ATLAS) then return end
	local mask = frame:CreateMaskTexture()
	mask:SetAtlas(ICON_MASK_ATLAS)
	mask:SetAllPoints(tex)
	tex:AddMaskTexture(mask)
end

--------------------------------------------------------------------------------
-- Outdated glow
--------------------------------------------------------------------------------

-- Alpha animations set the region's alpha outright, so high and low are absolute.
local function Breathe(region, high, low)
	local group = region:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local fade = group:CreateAnimation("Alpha")
	fade:SetFromAlpha(high)
	fade:SetToAlpha(low)
	fade:SetDuration(BREATH_TIME)
	fade:SetSmoothing("IN_OUT")
	return group
end

-- One step of Blizzard's proc animation: show the sprite sheet, then play its 30 frames.
local function AddFlipBook(group, texture, duration, order)
	local show = group:CreateAnimation("Alpha")
	show:SetTarget(texture)
	show:SetFromAlpha(1)
	show:SetToAlpha(1)
	show:SetDuration(0.001)
	show:SetOrder(order)
	local flip = group:CreateAnimation("FlipBook")
	flip:SetTarget(texture)
	flip:SetFlipBookRows(FLIPBOOK_ROWS)
	flip:SetFlipBookColumns(FLIPBOOK_COLUMNS)
	flip:SetFlipBookFrames(FLIPBOOK_FRAMES)
	flip:SetFlipBookFrameWidth(0)
	flip:SetFlipBookFrameHeight(0)
	flip:SetDuration(duration)
	flip:SetOrder(order + 1)
end

-- A burst, then marching ants around the button, over a breathing bloom, with the icon itself
-- brightened. Our own copy of the proc art: Blizzard's alert manager would hide its own alert.
local function CreateGlow(parent)
	local g = CreateFrame("Frame", nil, parent)
	g:SetPoint("CENTER")
	g:Hide()

	g.bloom = g:CreateTexture(nil, "BACKGROUND")
	g.bloom:SetPoint("CENTER")
	g.bloom:SetBlendMode("ADD")
	g.bloomAtlas = SetAtlasOr(g.bloom, BLOOM_ATLAS, BORDER_FILE)
	if not g.bloomAtlas then
		g.bloom:SetVertexColor(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3])
	end
	g.bloomPulse = Breathe(g.bloom, 1, BLOOM_LOW)

	g.shine = g:CreateTexture(nil, "BORDER")
	g.shine:SetPoint("TOPLEFT", parent)
	g.shine:SetPoint("BOTTOMRIGHT", parent)
	g.shine:SetBlendMode("ADD")
	g.shine:SetAlpha(SHINE_HIGH)
	MaskToIcon(g, g.shine)
	g.shinePulse = Breathe(g.shine, SHINE_HIGH, SHINE_LOW)

	g.procArt = AtlasInfo(LOOP_ATLAS) ~= nil and AtlasInfo(BURST_ATLAS) ~= nil
	if g.procArt then
		g.loop = g:CreateTexture(nil, "ARTWORK")
		g.loop:SetAtlas(LOOP_ATLAS)
		g.loop:SetAllPoints()
		g.loop:SetBlendMode("ADD")
		g.loop:SetAlpha(0)
		g.loopAnim = g:CreateAnimationGroup()
		g.loopAnim:SetLooping("REPEAT")
		AddFlipBook(g.loopAnim, g.loop, LOOP_TIME, 1)

		g.burst = g:CreateTexture(nil, "OVERLAY")
		g.burst:SetAtlas(BURST_ATLAS)
		g.burst:SetPoint("CENTER")
		g.burst:SetBlendMode("ADD")
		g.burst:SetAlpha(0)
		g.burstAnim = g:CreateAnimationGroup()
		g.burstAnim:SetToFinalAlpha(true)
		AddFlipBook(g.burstAnim, g.burst, BURST_TIME, 1)
		local fadeOut = g.burstAnim:CreateAnimation("Alpha")
		fadeOut:SetTarget(g.burst)
		fadeOut:SetFromAlpha(1)
		fadeOut:SetToAlpha(0)
		fadeOut:SetDuration(0.001)
		fadeOut:SetOrder(3)
		g.burstAnim:SetScript("OnFinished", function() g.loopAnim:Play() end)
	end

	-- Animations stop while the bar is hidden (Edit Mode, vehicles...): resume on show.
	g:SetScript("OnShow", function(self)
		if not self.active then return end
		if not self.bloomPulse:IsPlaying() then self.bloomPulse:Play() end
		if not self.shinePulse:IsPlaying() then self.shinePulse:Play() end
		if self.procArt and not self.loopAnim:IsPlaying() and not self.burstAnim:IsPlaying() then
			self.loopAnim:Play()
		end
	end)
	return g
end

local function SizeGlow(g, w, h)
	g:SetSize(w * GLOW_SCALE, h * GLOW_SCALE)
	local info = g.bloomAtlas and AtlasInfo(BLOOM_ATLAS)
	if info and info.width and info.height then
		g.bloom:SetSize(info.width * w / REF_SIZE, info.height * h / REF_SIZE)
	else
		g.bloom:SetSize(w * BORDER_SCALE, h * BORDER_SCALE)
	end
	if g.procArt then
		g.burst:SetSize(w * BURST_SIZE / REF_SIZE, h * BURST_SIZE / REF_SIZE)
	end
end

local function SizeOverlay(o, w, h)
	SizeGlow(o.glow, w, h)
	local lw, lh = LOCK_SIZE, LOCK_SIZE
	local info = o.mark.lockAtlas and AtlasInfo(LOCK_ATLAS)
	if info and info.width and info.height then lw, lh = info.width, info.height end
	o.mark.lock:SetSize(lw * LOCK_SCALE * w / REF_SIZE, lh * LOCK_SCALE * h / REF_SIZE)
end

local function StartGlow(g, icon)
	g.shine:SetTexture(icon)
	if g.active then return end
	g:Show()
	g.active = true
	g.bloomPulse:Play()
	g.shinePulse:Play()
	if g.procArt then
		g.loopAnim:Stop()
		g.burstAnim:Play()	-- its OnFinished starts the loop
	end
end

local function StopGlow(g)
	if not g.active then return end
	g.active = false
	g.bloomPulse:Stop()
	g.shinePulse:Stop()
	if g.procArt then
		g.burstAnim:Stop()
		g.loopAnim:Stop()
	end
	g:Hide()
end

--------------------------------------------------------------------------------
-- Overlay per button: the glow, and the ignored mark
--------------------------------------------------------------------------------

local function GetOverlay(button)
	local o = overlays[button]
	if o then return o end
	o = CreateFrame("Frame", nil, button)
	o:SetAllPoints(button)
	o:SetFrameLevel(button:GetFrameLevel() + OVERLAY_LEVEL)
	o:EnableMouse(false)

	o.glow = CreateGlow(o)

	local mark = CreateFrame("Frame", nil, o)
	mark:SetAllPoints()
	o.mark = mark
	-- A greyed, darker copy of the icon on top of the real one: works on bright icons too.
	mark.veil = mark:CreateTexture(nil, "ARTWORK")
	mark.veil:SetAllPoints()
	mark.veil:SetDesaturated(true)
	mark.veil:SetVertexColor(VEIL_SHADE, VEIL_SHADE, VEIL_SHADE)
	MaskToIcon(mark, mark.veil)
	-- Normal blending: an additive blue border vanishes on light icons.
	local border = mark:CreateTexture(nil, "OVERLAY")
	SetAtlasOr(border, "UI-HUD-ActionBar-IconFrame-Mouseover", "Interface\\Buttons\\ButtonHilight-Square")
	border:SetAllPoints()
	border:SetVertexColor(IGNORED_COLOR[1], IGNORED_COLOR[2], IGNORED_COLOR[3])
	mark.lock = mark:CreateTexture(nil, "OVERLAY", nil, 2)
	mark.lockAtlas = SetAtlasOr(mark.lock, LOCK_ATLAS, LOCK_FILE)
	mark.lock:SetPoint("CENTER")

	o:SetScript("OnSizeChanged", function(self, w, h) SizeOverlay(self, w, h) end)
	SizeOverlay(o, button:GetWidth(), button:GetHeight())

	o:Hide()
	overlays[button] = o
	return o
end

--------------------------------------------------------------------------------
-- Ignore mode: transparent buttons over the action buttons take the clicks,
-- so the secure action button underneath never casts.
--------------------------------------------------------------------------------

local function CatcherOnEnter(self)
	local slot = ButtonSlot(self.owner)
	local info = slot and ns.GetSlotInfo(slot)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if info then
		GameTooltip:SetAction(slot)
		if info.ignored then
			GameTooltip:AddLine("Left-click: stop ignoring this rank", 0.25, 1, 0.25)
		else
			GameTooltip:AddLine("Left-click: ignore this rank on all action bars", 0.25, 1, 0.25)
		end
	else
		GameTooltip:SetText("Only spells can be ignored.", 0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine("Right-click or Esc: done", 0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function CatcherOnClick(self, mouseButton)
	if mouseButton == "RightButton" then
		ns.StopPick()
		return
	end
	ns.ToggleIgnoreSlot(ButtonSlot(self.owner))
	if GameTooltip:IsOwned(self) then CatcherOnEnter(self) end
end

local function GetCatcher(button)
	local c = catchers[button]
	if c then return c end
	c = CreateFrame("Button", nil, button)
	c.owner = button
	c:SetAllPoints(button)
	c:SetFrameLevel(button:GetFrameLevel() + CATCHER_LEVEL)
	c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	c:SetScript("OnClick", CatcherOnClick)
	c:SetScript("OnEnter", CatcherOnEnter)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	local hover = c:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.2)
	c:Hide()
	catchers[button] = c
	return c
end

-- On-screen hint. Listed in UISpecialFrames so Esc hides it, which ends ignore mode
-- (Esc also closes the spellbook in the same pass).
local hint = CreateFrame("Frame", "MaxRankPickHint", UIParent)
hint:SetFrameStrata("DIALOG")
hint:SetSize(700, 50)
hint:SetPoint("TOP", 0, -140)
hint:Hide()
local hintText = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
hintText:SetPoint("TOP")
hintText:SetText("MaxRank ignore mode: left-click spells on your action bars to ignore or un-ignore that exact rank.")
local hintSub = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
hintSub:SetPoint("TOP", hintText, "BOTTOM", 0, -4)
hintSub:SetText("Right-click or press Esc when done. Key bindings still cast normally.")
hint:SetScript("OnHide", function() ns.StopPick() end)
tinsert(UISpecialFrames, "MaxRankPickHint")

function ns.StartPick()
	if pickMode then return end
	if InCombatLockdown() then
		ns.Print("Ignore mode isn't available in combat.")
		return
	end
	pickMode = true
	for _, button in ipairs(GetButtons()) do
		GetCatcher(button)
	end
	hint:Show()
	ns.RefreshOverlays()
	ns.RequestRefresh()
end

function ns.StopPick()
	if not pickMode then return end
	pickMode = false
	for _, c in pairs(catchers) do
		c:Hide()
	end
	hint:Hide()
	ns.RequestRefresh()
end

function ns.TogglePickMode()
	if pickMode then ns.StopPick() else ns.StartPick() end
end

function ns.IsPickMode()
	return pickMode
end

--------------------------------------------------------------------------------
-- Highlight
--------------------------------------------------------------------------------

function ns.ToggleHighlight()
	highlightOn = not highlightOn
	if highlightOn then
		local outdated = ns.ScanBars()
		if #outdated == 0 then
			ns.Print("Highlight on: every action bar spell is at its highest known rank.")
		else
			ns.Print(("Highlight on: %d action slot%s to update."):format(#outdated, ns.Plural(#outdated)))
		end
	end
	ns.RequestRefresh()
end

function ns.IsHighlight()
	return highlightOn
end

-- The spellbook closed: its buttons are gone, so the modes they toggle end too.
function ns.EndModes()
	ns.StopPick()
	if highlightOn then
		highlightOn = false
		ns.RequestRefresh()
	end
end

function ns.RefreshOverlays()
	local show = highlightOn or pickMode
	local combat = InCombatLockdown()
	for _, button in ipairs(GetButtons()) do
		local slot = ButtonSlot(button)
		local info = show and slot and ns.GetSlotInfo(slot) or nil
		local glow = info ~= nil and info.outdated and not info.ignored
		local locked = info ~= nil and info.ignored
		local o = overlays[button]
		if (glow or locked) and (o or not combat) then
			o = o or GetOverlay(button)
			o:Show()
			local icon = ns.Val(GetActionTexture(slot))
			if glow then
				StartGlow(o.glow, icon)
			else
				StopGlow(o.glow)
			end
			if locked then
				o.mark.veil:SetTexture(icon)
			end
			o.mark:SetShown(locked)
		elseif o then
			StopGlow(o.glow)
			o:Hide()
		end
		local c = catchers[button]
		if c then
			c:SetShown(pickMode and slot ~= nil and ns.Val(HasAction(slot)) and true or false)
		end
	end
end
