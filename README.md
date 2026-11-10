# Exact agent plugin

A Claude Code and Codex plugin with one skill, `exact`. It clones upstream
[expo/exact](https://github.com/expo/exact) at use time, runs its setup, and sends the agent
to its start-here guide. It vendors none of Exact, so it needs no syncing: it always uses the
latest upstream checkout. Not affiliated with Expo.

This repo is the plugin (repo root) and a one-plugin marketplace.

Claude Code:

```sh
claude plugin marketplace add GamerDubz/exact-plugin
claude plugin install exact@exact-agent-marketplace
```

Codex: add `GamerDubz/exact-plugin` as a marketplace and enable `exact@exact-agent-marketplace`.

## Data handling

The plugin has no server and collects nothing. It reads and stores no personal data and
retains nothing. The skill runs on the user's machine and touches the network only to:

- clone or update `github.com/expo/exact` with git;
- run Exact's own `setup`, which downloads the toolchains and dependencies that checkout
  pins (Rust, Bun packages, Binaryen, Hermes bundles, crates);
- open an issue on `github.com/expo/exact`, only when the user asks for it and approves the
  text first.

It is a developer tool, not intended for users under 18.
