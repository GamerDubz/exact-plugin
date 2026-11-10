import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  EXIT_FAILED,
  EXIT_NOT_APPROVED,
  EXIT_OK,
  MARKETPLACE_SOURCE,
  PLUGIN_ID,
  install,
  parseArguments,
  skillPathFor,
} from './install.mjs';

const HOME = '/home/tester';
const SKILL_TEXT = '---\nname: exact\n---\nbundled skill\n';

/**
 * A client that only answers the exact command tuples the installer is allowed to
 * use. Any other tuple throws, so a typo or an unmodeled command fails the test
 * instead of silently succeeding.
 * @param {'claude' | 'codex'} client
 * @param {{ present?: boolean, plugins?: 'full' | 'none' | 'broken', installed?: { id: string, enabled: boolean }[], failOn?: string }} [options]
 */
function fakeClient(client, { present = true, plugins = 'full', installed = [], failOn } = {}) {
  const state = { marketplaceAdded: false, installed: [...installed] };
  const scope = client === 'claude' ? ' --scope user' : '';
  const installVerb = client === 'codex' ? 'add' : 'install';
  const respond = (/** @type {number | null} */ exitCode, stdout = '', stderr = '') => ({ exitCode, stdout, stderr });
  const run = (/** @type {readonly string[]} */ args) => {
    const key = args.join(' ');
    if (!present) return { exitCode: null, stdout: '', stderr: '', spawnError: 'ENOENT' };
    if (key === failOn) return respond(1, '', 'boom');
    if (key === '--version') return respond(0, '1.0.0');
    if (key === 'plugin list --json') {
      if (plugins === 'none') return respond(2, '', "error: unrecognized subcommand 'plugin'");
      if (plugins === 'broken') return respond(0, 'not json');
      return respond(
        0,
        JSON.stringify(
          client === 'codex'
            ? { installed: state.installed.map(({ id, enabled }) => ({ pluginId: id, name: id.split('@')[0], enabled })) }
            : state.installed.map(({ id, enabled }) => ({ id, scope: 'user', enabled })),
        ),
      );
    }
    if (key === `plugin marketplace add ${MARKETPLACE_SOURCE}`) {
      state.marketplaceAdded = true;
      return respond(0);
    }
    if (key === `plugin ${installVerb} ${PLUGIN_ID}${scope}`) {
      if (!state.marketplaceAdded) return respond(1, '', 'marketplace not added');
      state.installed.push({ id: PLUGIN_ID, enabled: true });
      return respond(0);
    }
    if (key === `plugin enable ${PLUGIN_ID}${scope}`) {
      for (const entry of state.installed) entry.enabled = true;
      return respond(0);
    }
    throw new Error(`unmodeled ${client} command: ${key}`);
  };
  return { run, state };
}

/** @param {{ claude?: ReturnType<typeof fakeClient>, codex?: ReturnType<typeof fakeClient>, files?: Map<string, string> }} world */
function makeEnvironment({ claude = fakeClient('claude', { present: false }), codex = fakeClient('codex', { present: false }), files = new Map() }) {
  /** @type {string[]} */
  const lines = [];
  const commands = /** @type {string[]} */ ([]);
  return {
    files,
    lines,
    commands,
    environment: {
      home: HOME,
      skillText: SKILL_TEXT,
      run: async (/** @type {string} */ command, /** @type {readonly string[]} */ args) => {
        commands.push(`${command} ${args.join(' ')}`);
        return (command === 'claude' ? claude : codex).run(args);
      },
      readText: async (/** @type {string} */ path) => files.get(path),
      writeText: async (/** @type {string} */ path, /** @type {string} */ text) => void files.set(path, text),
      log: (/** @type {string} */ line) => void lines.push(line),
    },
  };
}

const approve = { mode: /** @type {const} */ ('auto'), clients: /** @type {const} */ (['claude', 'codex']), yes: true, confirm: async () => true };
const writes = (/** @type {string[]} */ commands) => commands.filter(command => /plugin (marketplace add|install|add|enable)/u.test(command));

test('neither client installed: nothing runs beyond the version probe and nothing is written', async () => {
  const world = makeEnvironment({});
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.deepEqual(world.commands, ['claude --version', 'codex --version']);
  assert.equal(world.files.size, 0);
});

test('codex with plugin commands gets the marketplace plugin, not the skill file', async () => {
  const codex = fakeClient('codex');
  const world = makeEnvironment({ codex });
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.deepEqual(writes(world.commands), [`codex plugin marketplace add ${MARKETPLACE_SOURCE}`, `codex plugin add ${PLUGIN_ID}`]);
  assert.deepEqual(codex.state.installed, [{ id: PLUGIN_ID, enabled: true }]);
  assert.equal(world.files.size, 0);
});

test('claude installs at user scope', async () => {
  const claude = fakeClient('claude');
  const world = makeEnvironment({ claude });
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.deepEqual(writes(world.commands), [`claude plugin marketplace add ${MARKETPLACE_SOURCE}`, `claude plugin install ${PLUGIN_ID} --scope user`]);
});

test('both present: each client takes its own route in one run', async () => {
  const world = makeEnvironment({ claude: fakeClient('claude'), codex: fakeClient('codex', { plugins: 'none' }) });
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.ok(world.commands.includes(`claude plugin install ${PLUGIN_ID} --scope user`));
  assert.equal(world.files.get(skillPathFor('codex', HOME)), SKILL_TEXT);
});

test('already installed and enabled: no write commands', async () => {
  const world = makeEnvironment({ codex: fakeClient('codex', { installed: [{ id: PLUGIN_ID, enabled: true }] }) });
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.deepEqual(writes(world.commands), []);
});

test('installed but disabled: enables without re-adding the marketplace', async () => {
  const claude = fakeClient('claude', { installed: [{ id: PLUGIN_ID, enabled: false }] });
  const world = makeEnvironment({ claude });
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.deepEqual(writes(world.commands), [`claude plugin enable ${PLUGIN_ID} --scope user`]);
});

test('a client without plugin commands falls back to the skill file at its documented path', async () => {
  const world = makeEnvironment({ claude: fakeClient('claude', { plugins: 'none' }), codex: fakeClient('codex', { plugins: 'none' }) });
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.equal(world.files.get(skillPathFor('claude', HOME)), SKILL_TEXT);
  assert.equal(world.files.get(skillPathFor('codex', HOME)), SKILL_TEXT);
  assert.deepEqual(writes(world.commands), []);
});

test('rerunning the skill fallback changes nothing', async () => {
  const files = new Map([[skillPathFor('codex', HOME), SKILL_TEXT]]);
  const world = makeEnvironment({ codex: fakeClient('codex', { plugins: 'none' }), files });
  assert.equal(await install(approve, world.environment), EXIT_OK);
  assert.match(world.lines.join('\n'), /already installed/u);
});

test('a different existing skill file is preserved and reported, never overwritten', async () => {
  const files = new Map([[skillPathFor('codex', HOME), 'my own edited skill']]);
  const world = makeEnvironment({ codex: fakeClient('codex', { plugins: 'none' }), files });
  assert.equal(await install(approve, world.environment), EXIT_FAILED);
  assert.equal(files.get(skillPathFor('codex', HOME)), 'my own edited skill');
});

test('a conflicting exact plugin from another source blocks writes for that client', async () => {
  const codex = fakeClient('codex', { installed: [{ id: 'exact@someone-else', enabled: true }] });
  const world = makeEnvironment({ codex });
  assert.equal(await install(approve, world.environment), EXIT_FAILED);
  assert.deepEqual(writes(world.commands), []);
  assert.equal(world.files.size, 0);
});

test('an unreadable plugin list writes nothing and does not fall back to a skill', async () => {
  const world = makeEnvironment({ claude: fakeClient('claude', { plugins: 'broken' }) });
  assert.equal(await install(approve, world.environment), EXIT_FAILED);
  assert.deepEqual(writes(world.commands), []);
  assert.equal(world.files.size, 0);
});

test('without approval nothing is written and the exit code says so', async () => {
  const world = makeEnvironment({ codex: fakeClient('codex') });
  assert.equal(await install({ ...approve, yes: false, confirm: async () => false }, world.environment), EXIT_NOT_APPROVED);
  assert.deepEqual(writes(world.commands), []);
});

test('--mode skill copies the file even when plugin commands work', async () => {
  const world = makeEnvironment({ codex: fakeClient('codex') });
  assert.equal(await install({ ...approve, mode: 'skill' }, world.environment), EXIT_OK);
  assert.deepEqual(writes(world.commands), []);
  assert.equal(world.files.get(skillPathFor('codex', HOME)), SKILL_TEXT);
});

test('--mode plugin refuses to fall back when plugin commands are missing', async () => {
  const world = makeEnvironment({ codex: fakeClient('codex', { plugins: 'none' }) });
  assert.equal(await install({ ...approve, mode: 'plugin' }, world.environment), EXIT_FAILED);
  assert.equal(world.files.size, 0);
});

test('a failing install step is reported with its fix and does not fall back to a skill', async () => {
  const world = makeEnvironment({ claude: fakeClient('claude', { failOn: `plugin install ${PLUGIN_ID} --scope user` }) });
  assert.equal(await install(approve, world.environment), EXIT_FAILED);
  assert.match(world.lines.join('\n'), /did not complete/u);
  assert.equal(world.files.size, 0);
});

test('an unmodeled command fails the fake instead of passing silently', async () => {
  const claude = fakeClient('claude');
  assert.throws(() => claude.run(['plugin', 'uninstall', PLUGIN_ID]), /unmodeled/u);
});

test('argument parsing rejects unknown options and bad values', () => {
  assert.deepEqual(parseArguments(['--client', 'codex', '--mode', 'skill', '--yes']), { mode: 'skill', clients: ['codex'], yes: true, help: false });
  assert.throws(() => parseArguments(['--mode', 'everything']), /Unknown or incomplete/u);
  assert.throws(() => parseArguments(['--client']), /Unknown or incomplete/u);
});
