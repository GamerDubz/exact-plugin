---
name: exact
description: Build, run and test an app with Exact (github.com/expo/exact), the all-platform runtime where the UI is written in Contract and data logic in TypeScript or Rust. Use when the user asks to make an Exact app or website, write an app.contract, run Exact's agent driver, or mentions Contract, exact.mjs, scripts/agent.mjs, or expo/exact.
---

# Exact

Exact has no releases, tags or npm package. An app uses a git checkout of
`expo/exact` by path. This skill bootstraps that checkout, then defers to the
docs inside it. Exact is pre-1.0 and changes daily; the checkout's docs are the
source of truth. Not affiliated with Expo.

## 1. Bootstrap (setup or update)

Run the plugin's bootstrap first. It clones or fast-forwards `$EXACT` (else
`~/exact`), installs missing rustup and the Bun version Exact pins, and runs
`bun scripts/exact.mjs setup` only when the checkout HEAD moved since the last
successful setup. It never discards local changes.

From the installed plugin root (Claude: `$CLAUDE_PLUGIN_ROOT`; Codex:
`$PLUGIN_ROOT` / `$CLAUDE_PLUGIN_ROOT`):

```sh
bash "${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}/scripts/exact-bootstrap.sh"
# Windows: pwsh "${env:PLUGIN_ROOT}/scripts/exact-bootstrap.ps1"
```

`SessionStart` hooks run the same script with `--auto` (ls-remote HEAD check;
skipped when `EXACT_PLUGIN_NO_AUTOUPDATE=1`). Use `--check` to report only.

### Fallback (no plugin script)

```sh
git clone https://github.com/expo/exact.git ~/exact   # or: git -C "$EXACT" pull --ff-only
# install rustup from https://rustup.rs and Bun at package.json's packageManager pin
cd "${EXACT:-$HOME/exact}" && bun scripts/exact.mjs setup
```

`bun scripts/exact.mjs setup --check` reports prerequisites without changing the
machine. Platform SDKs (Xcode, Android SDK) are report-only.

Call the checkout `<exact>` below.

## 2. Read the one required guide

- Website: `<exact>/docs/start-here-site.md`
- Any other app: `<exact>/docs/start-here.md`

Read only that guide before starting. Do not read `AGENTS.md` (Exact's own work).

## 3. Make and verify the app

```sh
bun <exact>/scripts/exact.mjs new <path>
cd <path>
bun exact.mjs pattern        # list starters; `pattern site` for a website
bun exact.mjs verify         # build, run app.test.contract, check screens
```

After the Exact checkout moves, in an existing app: `bun exact.mjs update`
rewrites generated Exact paths/patches; if it reports lock drift, run
`bun exact.mjs lock`.

Start from the nearest pattern, put the view in Contract and data logic in
`app.ts`. `verify` is the gate. Drive by hand with `bun exact.mjs agent web ...`.

## 4. Feedback

Exact does not take pull requests. Bugs and missing capabilities go to
`github.com/expo/exact` issues — ask the user before filing.
