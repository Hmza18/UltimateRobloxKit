--!strict
-- Tycoon settings. Tag instances in Studio (Tag Editor or the Properties > Tags section) with these names.
--
-- Plot             a Model or Part that holds one player's tycoon. Optional child Part "Spawn" and folder "Purchases".
-- PurchaseButton   a Part with attributes ButtonId (string), Cost (number), Unlocks (name of a child of
--                  Purchases) and optional Requires (comma-separated ButtonIds bought first).
-- Dropper          a Part with optional attributes DropValue (number) and Interval (seconds).
-- Collector        a Part that turns drops touching it into coins for the plot owner.

local TycoonConfig = {
	Tags = { Plot = "Plot", Dropper = "Dropper", Collector = "Collector", PurchaseButton = "PurchaseButton" },
	MaxDropsPerPlot = 60, -- drops alive at once per plot, to cap physics cost
	DropLifetime = 20, -- seconds before an uncollected drop is removed
	ButtonDebounce = 1, -- seconds between purchase attempts on one button
	BuildDemoWorld = true, -- build two sample plots when the place has no Plot-tagged instances
}

return table.freeze(TycoonConfig)
