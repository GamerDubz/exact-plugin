# Exact agent plugin

A Claude Code and Codex plugin with one skill, `exact`. It clones upstream
[expo/exact](https://github.com/expo/exact) at use time, runs its setup, and sends the agent
to its start-here guide. It vendors none of Exact, so it needs no syncing: it always uses the
latest upstream checkout. Not affiliated with Expo.

This repo is the plugin (repo root) and a one-plugin marketplace.

Automatic (detects which client is installed):

```sh
npx github:GamerDubz/exact-plugin
```

It looks for Claude Code and Codex on this machine and shows a plan before writing anything.
A client with plugin commands gets the marketplace plugin; a client that has no plugin
commands gets the skill file instead (`~/.claude/skills/exact` for Claude Code,
`~/.agents/skills/exact` for Codex); a client that is not installed is skipped. It never
overwrites a skill file that differs from this version's. Options: `--yes` skips the
approval question, `--client claude|codex`, and `--mode plugin|skill` to force a route.

Or by hand. Claude Code:

```sh
claude plugin marketplace add GamerDubz/exact-plugin
claude plugin install exact@exact-agent-marketplace
```

Codex: add `GamerDubz/exact-plugin` as a marketplace and enable `exact@exact-agent-marketplace`.

## Data handling

The plugin has no server and collects nothing. It reads and stores no personal data and
retains nothing. The skill runs on the user's machine and touches the network only to:

- (installer only) let `claude` or `codex` fetch this repo as a marketplace from
  `github.com/GamerDubz/exact-plugin`, or write the skill file into the user's home folder,
  after showing the plan and getting approval;
- clone or update `github.com/expo/exact` with git;
- run Exact's own `setup`, which downloads the toolchains and dependencies that checkout
  pins (Rust, Bun packages, Binaryen, Hermes bundles, crates);
- open an issue on `github.com/expo/exact`, only when the user asks for it and approves the
  text first.

It is a developer tool, not intended for users under 18.
