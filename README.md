# Exact agent skills marketplace

An agent skills marketplace with one skill, `exact`. It clones upstream
[expo/exact](https://github.com/expo/exact) at use time, runs its setup, and sends the agent
to its start-here guide. It vendors none of Exact, so it always uses the latest upstream
checkout. Not affiliated with Expo.

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

Manual: copy [`skills/exact/SKILL.md`](skills/exact/SKILL.md) into your agent's skills directory.

## Privacy

See [docs/privacy.md](docs/privacy.md). Terms: [LICENSE](LICENSE).
