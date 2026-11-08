# Release checklist

Copy to `docs/releases/<version>.md` for every publish. Publishing needs a person with access and explicit permission.

- Version:
- Release date and time (when the team can watch servers for 2+ hours):
- Release owner:

## Before publish

- [ ] Changelog written (player-facing and internal)
- [ ] No open P0 bugs; P1s fixed or deferred with a note
- [ ] Tests pass (unit tests, `--!strict` type check, lint)
- [ ] Played in Studio with 2+ clients (Clients and Servers test)
- [ ] Tested on a low-end phone, a PC and a gamepad
- [ ] Data: save/load tested with an old profile from the previous version; migrations run once and are idempotent
- [ ] Purchases: each developer product and game pass tested in Studio; ProcessReceipt idempotent
- [ ] Security: new remotes validate types, ranges, ownership and rate
- [ ] Performance: memory and frame time within budget on the low-end phone
- [ ] Analytics events for new features in place
- [ ] Store page, thumbnails and update notes updated and truthful
- [ ] Rollback plan: previous version identified and the restore steps known

## Publish

- [ ] Published to a test place or private build first and smoke tested
- [ ] Published to production by the owner
- [ ] Old servers handled (migrate or let them close; verify current shutdown/migrate options)

## After publish (first 2 hours, then 24 hours)

- [ ] Error reports and server logs checked
- [ ] Concurrent players and session length normal for the time of day
- [ ] Purchases arriving; no duplicate-grant reports
- [ ] Community channels watched for reports
- [ ] Decision: keep / hotfix / roll back, written down

## Sign-off

| Role | Name | Date |
|---|---|---|
| Release owner | | |
| QA | | |
