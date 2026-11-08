---
name: roblox-publishing-liveops
description: Shipping and operating a Roblox experience - Studio publish and version history rollback, Rojo build to the Open Cloud Place Publishing API with a scoped API key kept in a secret, Open Cloud Assets API, a GitHub Actions deploy pattern, experience settings checklist (maturity questionnaire, devices, private servers, thumbnails), live updates with server restarts, soft shutdown and data migrations, semver tags, and monitoring via Creator Analytics and error reports. Use when publishing, deploying from CI, rolling back, restarting servers for an update or preparing a launch.
license: MIT
metadata:
  category: roblox
  version: 1.0.0
  triggers: [publish, deploy, open cloud, place publishing, rollback, version history, soft shutdown, restart servers, release, liveops, github actions]
  depends: [roblox-toolchain-doctor, roblox-data-persistence, roblox-testing-debugging]
---

# Roblox publishing and live ops

## When to use

- First publish, regular releases, CI deploys from a Rojo project.
- Rolling back a bad release, restarting servers, migrating saved data.
- Launch prep and post-launch monitoring.

When not to use: toolchain setup (`roblox-toolchain-doctor`); save schema design (`roblox-data-persistence`); test strategy (`roblox-testing-debugging`); pricing and events design (`monetization-economy-design`).

## Safety rules

- Publishing to a live place changes what every player gets. Only publish when the user explicitly asks, and say which place id. Deploy to a **staging** experience first.
- API keys are secrets: store them in the CI secret store or a local env var, never in the repo, never in Luau, never in chat. Scope each key to the minimum (one universe, place publishing only) and set an expiry and IP restrictions where available.
- Only the user signs in to Roblox and creates API keys in Creator Hub.

## Inputs

- Universe id and place ids (staging and production), visible in Creator Hub.
- An Open Cloud API key with place publishing permission (`universe-places` write, verify the current scope name in creator docs) for those universes.
- A Rojo project that builds: `rojo build default.project.json -o build.rbxl`.

## Workflow

1. **Manual publish (Studio)**: File > Publish to Roblox (Alt+P). Each publish creates a place version. Rollback: Creator Hub > your experience > Places > place > Version History > restore an older version (it publishes that version as new), then restart servers.
2. **Build**: `rojo build default.project.json -o build.rbxl`. Run Lune tests and a lint (`selene`) first; fail the pipeline on any error.
3. **Publish via Open Cloud** (Place Publishing API):

   ```bash
   curl --fail -sS -X POST \
     "https://apis.roblox.com/universes/v1/$UNIVERSE_ID/places/$PLACE_ID/versions?versionType=Published" \
     -H "x-api-key: $ROBLOX_API_KEY" \
     -H "Content-Type: application/octet-stream" \
     --data-binary @build.rbxl
   ```

   The response contains `versionNumber`. Use `versionType=Saved` to upload without publishing. `.rbxlx` uses `Content-Type: application/xml`.
4. **Assets** (images, meshes, audio, models) go through the Open Cloud Assets API (`https://apis.roblox.com/assets/v1/assets`, multipart, `asset:read`/`asset:write` scopes; verify fields in creator docs). Uploads are moderated; poll the returned operation until done.
5. **CI**: GitHub Actions workflow in [references/deploy-workflow.md](references/deploy-workflow.md): tests on every push, staging deploy on `main`, production deploy only on a `v*` semver tag with a manual approval environment.
6. **Versioning**: tag releases `vMAJOR.MINOR.PATCH`. Bake the version into the build (a generated `Version.luau` or a `StringValue`) and show it in a corner of the UI and in error reports so a player's report maps to a commit.
7. **Live update**: after publishing, existing servers keep the old version. In Creator Hub use the server restart option for the place or experience (wording and behavior, including whether players are migrated gracefully, change; verify in creator docs). Open Cloud also exposes a restart-servers operation (verify endpoint and scope in creator docs). For a custom soft shutdown, see the code below.
8. **Data migrations**: every save has `schemaVersion`. On load, run migrations in order up to the current version; never delete old fields in the same release that stops writing them. Old servers still running can overwrite new data during a rollout, so make migrations backward-tolerant or restart all servers immediately.
9. **Experience settings checklist** (Creator Hub, before launch): maturity and compliance questionnaire completed, supported devices (computer, phone, tablet, console, VR), genre, description, icon and thumbnails, server size, private servers (on/off, price), allowed copied (usually off), API services/HTTP access as needed, third-party teleports only if used, social links, localization, and age guidelines.
10. **Monitor**: Creator Hub Analytics (retention, sessions, monetization, performance), the Error Report in analytics (script errors aggregated by message), Developer Console in a live server, and your own logged events. Watch the first hour after every release; roll back on an error spike.

### Version check, migrations and soft shutdown

```lua
--!strict
-- ServerScriptService/LiveOps/LiveOps.luau (ModuleScript; call LiveOps.start() once from a server Script)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local BUILD_VERSION = "1.4.0" -- generated by CI from the git tag

-- Migrations: each takes a save at version N and returns version N+1.
type Save = { [string]: any }
local MIGRATIONS: { [number]: (Save) -> Save } = {
	[1] = function(save)
		save.coins = save.money or 0 -- renamed field; keep `money` until the next major release
		return save
	end,
	[2] = function(save)
		save.settings = save.settings or { music = true }
		return save
	end,
}
local CURRENT_SCHEMA = 3

local LiveOps = {}

function LiveOps.migrate(save: Save): Save
	local version = (save.schemaVersion :: number?) or 1
	while version < CURRENT_SCHEMA do
		local step = MIGRATIONS[version]
		assert(step, "missing migration from " .. version)
		save = step(save)
		version += 1
		save.schemaVersion = version
	end
	return save
end

function LiveOps.start()
	workspace:SetAttribute("BuildVersion", BUILD_VERSION) -- UI and bug reports read this

	-- Soft shutdown: move players to a temporary reserved server, which sends them
	-- back to a fresh public server (now on the new version) a few seconds later.
	game:BindToClose(function()
		if RunService:IsStudio() or #Players:GetPlayers() == 0 then
			return
		end
		local ok, code = pcall(TeleportService.ReserveServer, TeleportService, game.PlaceId)
		if ok then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			options:SetTeleportData({ softShutdown = true })
			pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, Players:GetPlayers(), options)
		end
		task.wait(10) -- give teleports time; BindToClose allows about 30 s in total
	end)

	-- In the holding reserved server: send everyone back to public servers.
	Players.PlayerAdded:Connect(function(player)
		local data = player:GetJoinData().TeleportData
		if game.PrivateServerId ~= "" and typeof(data) == "table" and data.softShutdown then
			task.wait(5)
			pcall(TeleportService.TeleportAsync, TeleportService, game.PlaceId, { player })
		end
	end)
end

return LiveOps
```

The soft-shutdown trick relies on reserved servers starting from the newest published version. If the built-in restart flow already migrates players for you, prefer it and drop this block. The `softShutdown` flag is teleport data, so a client can fake it; the worst case is that player being sent to a public server, which is harmless.

## Outputs

- Build and deploy commands, a CI workflow, a version module, migrations, a release checklist and a rollback note per release.

## Validation

1. `rojo build` succeeds; tests pass; the Open Cloud call returns a `versionNumber` (check with `curl --fail`, non-zero exit on HTTP errors).
2. Creator Hub Version History lists the new version with the expected time.
3. Join the **staging** experience and check the in-game `BuildVersion` matches the tag.
4. Migration tests: Lune test each migration with saved fixtures from every old schema.
5. After restart, a new server's `BuildVersion` is the new one; Error Report shows no new top errors in the first hour.

## Pitfalls

- **API key committed to git**: revoke it in Creator Hub immediately, rotate, and purge from history. Add secret scanning.
- **Publishing the place file but forgetting packages/assets**: assets referenced by id must be uploaded and approved first.
- **Rojo build missing Studio-only content** (terrain, hand-built maps not in the repo): use a base place file with `rojo build` against a project that includes it, or publish map changes from Studio separately and pull them into the repo.
- **Old servers overwrite migrated data**: restart servers promptly after a schema change, and keep migrations additive.
- **Shipping on Friday night** without someone watching analytics.
- **Teleport soft shutdown in Studio**: teleports fail there; the code skips Studio.

## Limitations

- This skill cannot sign in, create API keys or press publish; the user does that or supplies a key through a secret.
- Open Cloud endpoints, scopes and Creator Hub labels evolve; check creator docs before automating, especially for server restarts and the Assets API.
- Analytics dashboards are read in Creator Hub; there is no fully documented Open Cloud API for every analytics view (verify current availability).
