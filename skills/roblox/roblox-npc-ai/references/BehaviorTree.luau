--!strict
-- Tiny behavior tree for NPCs. Nodes are functions that return a status each tick.
-- Tick the tree from a single scheduler (see SKILL.md), not one loop per NPC.

export type Status = "Success" | "Failure" | "Running"
export type Node<B> = (blackboard: B, dt: number) -> Status

local BT = {}

-- Runs children in order until one fails or is running.
function BT.sequence<B>(children: { Node<B> }): Node<B>
	return function(bb: B, dt: number): Status
		for _, child in children do
			local s = child(bb, dt)
			if s ~= "Success" then
				return s
			end
		end
		return "Success"
	end
end

-- Runs children in order until one succeeds or is running.
function BT.selector<B>(children: { Node<B> }): Node<B>
	return function(bb: B, dt: number): Status
		for _, child in children do
			local s = child(bb, dt)
			if s ~= "Failure" then
				return s
			end
		end
		return "Failure"
	end
end

function BT.condition<B>(test: (B) -> boolean): Node<B>
	return function(bb: B, _dt: number): Status
		return if test(bb) then "Success" else "Failure"
	end
end

function BT.action<B>(run: (B, number) -> Status): Node<B>
	return run
end

-- Inverts Success and Failure.
function BT.invert<B>(child: Node<B>): Node<B>
	return function(bb: B, dt: number): Status
		local s = child(bb, dt)
		if s == "Success" then
			return "Failure"
		elseif s == "Failure" then
			return "Success"
		end
		return s
	end
end

-- Example tree:
--
-- type Blackboard = { npc: Model, target: Model?, home: Vector3, mover: any }
-- local root = BT.selector({
--     BT.sequence({
--         BT.condition(function(bb) return bb.target ~= nil end),
--         BT.action(function(bb, _dt) bb.mover:follow(bb.target); return "Running" end),
--     }),
--     BT.action(function(bb, _dt)
--         bb.mover:moveTo(bb.home)
--         return "Running"
--     end),
-- })

return BT
