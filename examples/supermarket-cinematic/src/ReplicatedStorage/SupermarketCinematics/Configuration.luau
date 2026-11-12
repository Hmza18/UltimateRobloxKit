-- SupermarketCinematics configuration. Everything a designer is expected to tune lives here.
-- The cinematic is local to each client: it builds its own film set, cast and props, never moves
-- gameplay objects, never awards currency and never edits inventory, prices or product data.

local Configuration = {}

-- Playback ---------------------------------------------------------------------------------------
Configuration.AutoPlayOnJoin = true -- server asks each joining player's client to play once per session
Configuration.AutoPlayDelay = 1.5 -- seconds after the character spawns
Configuration.AllowSkip = true
Configuration.SkipKeys = { Enum.KeyCode.Return, Enum.KeyCode.ButtonB }
Configuration.ShowTestPanel = "studio" -- true | false | "studio" (Replay / Pause / Skip panel)
Configuration.ReplayCooldown = 2 -- seconds between replays requested from the test panel
Configuration.MaxStep = 1 / 15 -- clamp per-frame delta so a hitch never jumps over a cue
Configuration.HideOtherGuis = true -- disable the game's ScreenGuis while playing, restore after

-- Where the film set is built (client-only parts, far from the playable map) ------------------------
Configuration.SetOrigin = CFrame.new(0, 600, 3000)

-- Optional: an existing store to film instead of the procedural set's building shell. Leave nil to
-- always use the procedural set. (Characters, shelves and props still come from the cinematic.)
Configuration.ExistingStorefrontPath = nil -- e.g. "Workspace.Supermarket.Exterior"

-- Products ------------------------------------------------------------------------------------------
-- Real product models are looked up by name under these containers (read-only: the cinematic clones
-- them, strips scripts from the clone and never touches the original or its configuration).
Configuration.ProductContainers = {
	"ReplicatedStorage.Products",
	"ReplicatedStorage.Assets.Products",
	"ReplicatedStorage.Items",
	"Workspace.Products",
}
-- Display scale for the stand-in boxes (1.0 = the approved reference sizes, which fit the set shelves).
Configuration.ProductScale = 1.0
-- Real product clones are scaled (visually only) so their tallest side matches this height.
Configuration.ProductDisplayHeight = 1.2

-- Audio: fill in sounds your experience is allowed to use. Empty = silent hook (reported once). ----
-- No asset IDs are invented here. The footstep is Roblox's built-in character footstep file.
Configuration.Audio = {
	StoreOpen = "",
	Footstep = "rbxasset://sounds/action_footsteps_plastic.mp3",
	BoxHandle = "",
	ProductPlace = "",
	BasketDrop = "",
	ScannerBeep = "",
	CheckoutSuccess = "",
	FinalReveal = "",
	Music = "",
}
Configuration.AudioVolume = {
	Footstep = 0.25,
	Music = 0.4,
	default = 0.6,
}

-- Animations: paste uploaded animation asset IDs ("rbxassetid://...") to play them as real Roblox
-- AnimationTracks. Empty = the built-in pose player drives the same keyframes (works unpublished).
Configuration.AnimationIds = {
	SM_Idle = "",
	SM_Walk = "",
	SM_CarryWalk = "",
	SM_BasketWalk = "",
	SM_BasketIdle = "",
	SM_Wave = "",
	SM_BoxLift = "",
	SM_Stock = "",
	SM_Browse = "",
	SM_ReachPick = "",
	SM_Scan = "",
	SM_CashierIdle = "",
	SM_Cheer = "",
}
-- Ground speed the walk clips are authored for (studs/s): actors travel at exactly this speed so the
-- planted foot does not skate (anim_src/_sm.py Gait: 0.06 studs/frame at 60 fps).
Configuration.WalkSpeed = 3.6

-- Look and feel ---------------------------------------------------------------------------------
Configuration.StoreName = "SUPER MART"
Configuration.Title = "YOUR SUPERMARKET JOURNEY STARTS NOW"
Configuration.Subtitle = "BUILD • STOCK • SELL • EXPAND"
Configuration.EarningsText = { "+$25", "+$18" } -- illustrative cinematic UI only, not game pricing
Configuration.Font = Enum.Font.FredokaOne
Configuration.Letterbox = 0.085 -- bar height as a share of the screen

-- Performance -----------------------------------------------------------------------------------
Configuration.ParticleBudget = 1.0 -- multiplier on every burst; lowered automatically on low quality
Configuration.LowQualityLevel = 4 -- at or below this graphics level: half particles, no extra NPCs

return Configuration
