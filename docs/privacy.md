# Privacy

This plugin has no server and collects nothing. It reads and stores no personal data and
retains nothing. The skill runs on the user's machine and touches the network only to:

- clone or update `github.com/expo/exact` with git;
- run Exact's own `setup`, which downloads the toolchains and dependencies that checkout
  pins (Rust, Bun packages, Binaryen, Hermes bundles, crates);
- open an issue on `github.com/expo/exact`, only when the user asks for it and approves the
  text first.

Your agent's model provider sees what your agent sends it, under its own policy.

It is a developer tool, not intended for users under 18.

Questions: [open an issue](https://github.com/GamerDubz/exact-plugin/issues).
