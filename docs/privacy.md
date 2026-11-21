# Privacy

This plugin has no server and collects nothing. It reads and stores no personal
data and retains nothing. The skill and bootstrap run on the user's machine and
touch the network to:

- clone or update `github.com/expo/exact` with git (including SessionStart
  auto-update pulls when the hook is enabled);
- download and install missing prerequisites with the official installers
  (rustup from rustup.rs, Bun from bun.com) when the bootstrap finds they are
  absent or the Bun pin moved;
- run Exact's own `setup`, which downloads the toolchains and dependencies that
  checkout pins (Rust toolchains, Bun packages, Binaryen, Hermes bundles,
  crates, Playwright Chromium);
- open an issue on `github.com/expo/exact`, only when the user asks for it and
  approves the text first.

Set `EXACT_PLUGIN_NO_AUTOUPDATE=1` to skip the SessionStart probe/update. The hook
still uses a short `git ls-remote` against `github.com/expo/exact` when enabled.
Platform SDKs (Xcode, Android SDK) are never installed by this plugin.

Your agent's model provider sees what your agent sends it, under its own policy.

It is a developer tool, not intended for users under 18.

Questions: [open an issue](https://github.com/GamerDubz/exact-plugin/issues).
