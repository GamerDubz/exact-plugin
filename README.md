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
