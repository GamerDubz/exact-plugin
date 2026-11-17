# Privacy

This plugin has no server and collects nothing. It reads and stores no personal
data and retains nothing. The skill runs through the user's agent on their machine, which touches the
network to:

- check for and pull updates to `github.com/expo/exact` with git when the skill
  is used;
- install missing prerequisites (rustup, Bun) by following their official
  instructions, with the user;
- run Exact's own `setup`, which downloads the toolchains and dependencies that
  checkout pins (Rust toolchains, Bun packages, Binaryen, Hermes bundles,
  crates, Playwright Chromium);
- open an issue on `github.com/expo/exact`, only when the user asks for it and
  approves the text first.

The plugin ships no hooks or scripts and runs nothing in the background.
Platform SDKs (Xcode, Android SDK) are never installed by this plugin.

Your agent's model provider sees what your agent sends it, under its own policy.

It is a developer tool, not intended for users under 18.

Questions: [open an issue](https://github.com/GamerDubz/exact-plugin/issues).
