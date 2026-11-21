# Exact agent skills marketplace

An agent skills marketplace with one skill, `exact`. After install it bootstraps
a live [expo/exact](https://github.com/expo/exact) checkout (clone or
fast-forward), installs missing rustup and Exact's pinned Bun, runs Exact's own
`setup` when HEAD moves, and points the agent at the checkout's start-here
guide. It vendors none of Exact. Not affiliated with Expo.

Primary entry: [`.agents/plugins/marketplace.json`](.agents/plugins/marketplace.json).
Claude Code and Codex manifests are included for those agents.

## Install

Agents marketplace (any agent that reads `.agents/plugins/marketplace.json`):

```sh
# clone or point at GamerDubz/exact-plugin, add the marketplace, then install
# exact@exact-agent-marketplace
```

Codex:

```sh
codex plugin marketplace add GamerDubz/exact-plugin
codex plugin add exact@exact-agent-marketplace
```

Claude Code:

```sh
claude plugin marketplace add GamerDubz/exact-plugin
claude plugin install exact@exact-agent-marketplace
```

Manual: copy [`skills/exact/SKILL.md`](skills/exact/SKILL.md) into your agent's
skills directory, or run [`scripts/exact-bootstrap.sh`](scripts/exact-bootstrap.sh)
(Windows: [`scripts/exact-bootstrap.ps1`](scripts/exact-bootstrap.ps1)) yourself.

## Auto-setup and auto-update

- **Bootstrap:** `scripts/exact-bootstrap.sh` (or `.ps1`) ensures `$EXACT` or
  `~/exact`, pulls with `--ff-only` (warns and keeps local commits if dirty),
  installs missing toolchains with the official installers, and runs
  `bun scripts/exact.mjs setup` only when the checkout HEAD changed since the
  last successful setup.
- **SessionStart:** Claude Code and Codex load `hooks/hooks.json`, which runs
  the bootstrap in `--auto` mode. It probes
  `git ls-remote https://github.com/expo/exact.git HEAD` with a short timeout and
  compares that to the local checkout. Matching or unreachable HEADs exit
  immediately and silently; only when upstream has moved does it fetch,
  fast-forward, and rerun setup. The hook is time-boxed and never fails the
  session.

To turn off the SessionStart update:

```sh
export EXACT_PLUGIN_NO_AUTOUPDATE=1
```

## Privacy

See [docs/privacy.md](docs/privacy.md). Terms: [LICENSE](LICENSE).
