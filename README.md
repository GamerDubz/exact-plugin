# Exact agent skills marketplace

An agent skills marketplace with one skill, `exact`. Each time it is used, the
skill has the agent clone or fast-forward a live
[expo/exact](https://github.com/expo/exact) checkout, check prerequisites, run
Exact's own `setup` when the checkout moved, and follow the checkout's
start-here guide. It vendors none of Exact and ships no scripts or hooks. Not
affiliated with Expo.

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
skills directory.

## Setup and updates

The skill keeps Exact current without any background process. Whenever it is
used, the agent compares `git ls-remote https://github.com/expo/exact.git HEAD`
with the local checkout and only pulls and reruns `setup` when upstream moved,
so an unchanged checkout costs one tiny request. Missing prerequisites (rustup,
Bun) are installed by following their official instructions. Ask your agent to
"set up Exact" or "update Exact" at any time to run it on demand.

## Privacy

See [docs/privacy.md](docs/privacy.md). Terms: [LICENSE](LICENSE).
