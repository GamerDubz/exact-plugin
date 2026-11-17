---
name: exact
description: Build, run and test an app with Exact (github.com/expo/exact), the all-platform runtime where the UI is written in Contract and data logic in TypeScript or Rust. Use when the user asks to make an Exact app or website, write an app.contract, run Exact's agent driver, or mentions Contract, exact.mjs, scripts/agent.mjs, expo/exact, or Exact templates.
---

# Exact

Exact has no releases, tags or npm package. An app uses a git checkout of
`expo/exact` by path. This skill sets up and updates that checkout, then defers to the
docs inside it. Exact is pre-1.0 and changes daily; the checkout's docs are the
source of truth. Not affiliated with Expo.

## 1. Set up or update (every time this skill is used)

Do this before any Exact work. It is quick when nothing changed.

1. Find the checkout: `$EXACT`, else `~/exact`, else a parent of the current
   directory containing `scripts/exact.mjs`. If none exists, clone it:
   `git clone https://github.com/expo/exact.git ~/exact`.
2. Check for upstream changes: compare
   `git ls-remote https://github.com/expo/exact.git HEAD` with
   `git -C <exact> rev-parse HEAD`. If they match, skip to step 4. If the network
   is unavailable, carry on with the current checkout and say so.
3. If upstream moved, run `git -C <exact> pull --ff-only`. If that fails because
   of local changes, never discard them: tell the user and continue on the
   current commit.
4. Check prerequisites with `bun scripts/exact.mjs setup --check` from `<exact>`.
   Exact needs Rust through rustup and Bun at the version in `package.json`'s
   `packageManager` field. If either is missing, point the user to the official
   instructions ([rustup.rs](https://rustup.rs),
   [Bun installation](https://bun.com/docs/installation)) and help them follow
   those. Platform SDKs (Xcode, Android SDK) are report-only.
5. Run `bun scripts/exact.mjs setup` from `<exact>` on a fresh clone, after a
   pull that moved HEAD, or when `--check` reports something setup fixes.
   Otherwise skip it.

If the user asks to set up or update Exact, do all of the above even outside an
Exact app.

Call the checkout `<exact>` below.

## 2. Read the one required guide

- Website: `<exact>/docs/start-here-site.md`
- Any other app: `<exact>/docs/start-here.md`

Read only that guide before starting. Do not read `AGENTS.md` (Exact's own work).

## 3. Make and verify the app

### Start from a template (new apps only, once)

Only when making a new app, check once whether a whole-app template from
[expo/exact-templates](https://github.com/expo/exact-templates) fits. Skip this
for existing apps and for any other Exact work; never re-check templates on
later uses.

1. Use `~/.exact/templates` if it exists, as it is. Otherwise clone it once:
   `git clone --depth 1 https://github.com/expo/exact-templates.git ~/.exact/templates`.
   Pull it only if the user asks to update the templates.
2. Read its `INDEX.md` (or grep the `Keywords:` lines) and pick the template
   whose kind of app matches the request. If none fits, skip to the plain
   `exact new` below.
3. Make the app from it with Bun:
   ```sh
   bun ~/.exact/templates/new.mjs <template> <path> --name <name> --bundle-id <id>
   cd <path> && bun exact.mjs test web
   ```
   The template pins its own Exact commit in `<template>/exact.json`, and
   `new.mjs` gives the app a checkout of that commit under
   `~/.exact/exact2/`. Pass `--exact2 <exact>` only if the user wants it on
   their own checkout. Never copy a template's `app/` by hand.
4. Read the template's `TEMPLATE.md` (adapt, limits) and the new app's
   `AGENTS.md`, then adapt it. The template is a one-off starting point: the
   app does not track the template afterwards.

### Or start from a pattern

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
