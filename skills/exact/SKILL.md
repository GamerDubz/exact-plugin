---
name: exact
description: Build, run and test an app with Exact (github.com/expo/exact), the cross-platform runtime where the UI is written in Contract and data logic in TypeScript or Rust. Use when the user asks to make an Exact app, write an app.contract, or run Exact's agent driver (scripts/agent.mjs), or mentions Contract, exact.mjs or expo/exact.
---

# Exact

Exact has no releases, tags or npm package. An app uses a git checkout of
`expo/exact` by path, so this skill gets a current checkout and defers to the docs
inside it. It is pre-1.0 and changes daily; the checkout's docs are the source of
truth, not this file and not your memory of Exact.

## 1. Get a current checkout

Look for an existing one first: `$EXACT_HOME`, `~/exact`, or a parent of the current
directory containing `scripts/exact.mjs`. If none exists:

```sh
git clone https://github.com/expo/exact.git ~/exact
```

If one exists, update it with `git -C <checkout> pull --ff-only`. Stop and tell the user
if that fails because of local changes; do not discard them. Call the checkout `<exact2>`
below.

## 2. Check the tools

Needed: Rust through rustup, Bun at the version `package.json` pins, and Google Chrome
(or `CHROME` set to another Chromium). The macOS and iOS hosts also need Xcode. Report
anything missing and let the user install it; do not install toolchains silently.

Run once per checkout, from `<exact2>`:

```sh
bun scripts/exact.mjs setup
```

After the checkout moves, `bun exact.mjs update` reports lock drift and
`bun exact.mjs lock` refreshes it.

## 3. Read the one required guide

- A website (pages served to a browser): `<exact2>/docs/start-here-site.md`
- Any other app: `<exact2>/docs/start-here.md`

Read only that guide before starting. Everything else in the checkout is lookup. Do not
read `AGENTS.md`; it is for work on Exact itself.

## 4. Make and verify the app

```sh
bun <exact2>/scripts/exact.mjs new <path>
cd <path>
bun exact.mjs pattern        # list the starter patterns
bun exact.mjs verify         # build, run app.test.contract, check screens
```

Start from the nearest pattern, replace the placeholder screen and tests, and put
the view in Contract with data logic in `app.ts`. `verify` is the gate; a clean run on the
app's platform is done. Drive an app by hand with `bun exact.mjs agent web ...`.

First native builds (macOS, iOS) take roughly 10 to 15 minutes. Run them in the
background and watch the output.

## 5. Feedback

Exact does not take pull requests. Bugs, confusing docs and missing capabilities go in
issues at `github.com/expo/exact`, ideally with the smallest `app.contract` that shows
the problem. Ask the user before filing one.
