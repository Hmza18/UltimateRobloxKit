--!strict
-- Shared type definitions. Player data types live with the save format in Logic/DataSchema.

-- A server service or a client controller, loaded by Loader.
export type Module = {
	Name: string?, -- defaults to the ModuleScript's name
	Priority: number?, -- lower runs first; defaults to 100
	Init: ((self: any) -> ())?, -- set up state, signals and remotes; must not yield
	Start: ((self: any) -> ())?, -- runs in its own thread after every Init has finished
}

-- Arguments a client sent with a RemoteEvent, after the player argument.
export type RemoteHandler = (player: Player, ...any) -> ()

return {}
