# GitHub Actions deploy pattern

Secrets (repository or environment secrets, never committed):

- `ROBLOX_API_KEY_STAGING`, `ROBLOX_API_KEY_PROD`: Open Cloud keys, each scoped to one universe with place publishing write only.

Variables (not secret): `STAGING_UNIVERSE_ID`, `STAGING_PLACE_ID`, `PROD_UNIVERSE_ID`, `PROD_PLACE_ID`.

Create a `production` environment in GitHub with required reviewers so a tag deploy waits for a human approval.

```yaml
# .github/workflows/deploy.yml
name: build-test-deploy
on:
  push:
    branches: [main]
    tags: ["v*.*.*"]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install toolchain from rokit.toml
        uses: CompeyDev/setup-rokit@v0.1.2 # verify the current action name/version, or install rokit with its install script
      - run: selene src
      - run: lune run tests/run
      - name: Stamp version
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          if [[ "$GITHUB_REF_TYPE" != "tag" ]]; then VERSION="0.0.0-${GITHUB_SHA::7}"; fi
          printf 'return "%s"\n' "$VERSION" > src/shared/Version.luau
      - run: rojo build default.project.json -o build.rbxl
      - uses: actions/upload-artifact@v4
        with:
          name: place
          path: build.rbxl

  deploy-staging:
    needs: test
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with: { name: place }
      - name: Publish to staging
        env:
          ROBLOX_API_KEY: ${{ secrets.ROBLOX_API_KEY_STAGING }}
        run: |
          curl --fail -sS -X POST \
            "https://apis.roblox.com/universes/v1/${{ vars.STAGING_UNIVERSE_ID }}/places/${{ vars.STAGING_PLACE_ID }}/versions?versionType=Published" \
            -H "x-api-key: $ROBLOX_API_KEY" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @build.rbxl

  deploy-production:
    needs: test
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment: production # required reviewers gate this job
    steps:
      - uses: actions/download-artifact@v4
        with: { name: place }
      - name: Publish to production
        env:
          ROBLOX_API_KEY: ${{ secrets.ROBLOX_API_KEY_PROD }}
        run: |
          curl --fail -sS -X POST \
            "https://apis.roblox.com/universes/v1/${{ vars.PROD_UNIVERSE_ID }}/places/${{ vars.PROD_PLACE_ID }}/versions?versionType=Published" \
            -H "x-api-key: $ROBLOX_API_KEY" \
            -H "Content-Type: application/octet-stream" \
            --data-binary @build.rbxl
```

Notes:

- Pull requests run `test` only; secrets are not exposed to workflows from forks.
- Pin third-party actions to a full commit SHA in production repositories.
- The workflow does not restart servers. Do that deliberately from Creator Hub (or the Open Cloud restart operation once verified) after checking staging.
- Multi-place experiences: one build and one publish step per place, all from the same commit.
- Record each release: tag, place version number returned by the API, time, and the rollback target version.
