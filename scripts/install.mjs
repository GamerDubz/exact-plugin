#!/usr/bin/env node
// Installs the Exact agent skill into whichever of Claude Code and Codex is on this
// machine. A client whose plugin commands work gets the marketplace plugin; a client
// that is present but has no plugin commands gets the bundled skill file instead. A
// client that is absent is left alone. Nothing is written until the plan is approved.

import { spawn } from 'node:child_process';
import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath } from 'node:url';

export const MARKETPLACE_SOURCE = 'GamerDubz/exact-plugin';
export const PLUGIN_ID = 'exact@exact-agent-marketplace';
const PLUGIN_NAME_PREFIX = 'exact@';
const SKILL_NAME = 'exact';
const PROBE_TIMEOUT_MS = 30_000;
const INSTALL_TIMEOUT_MS = 180_000;
const OUTPUT_LIMIT_BYTES = 64 * 1024;
const UNSUPPORTED_PATTERN =
  /ENOENT|not recognized|unknown (?:command|subcommand)|unrecognized subcommand|unexpected argument/iu;

export const EXIT_OK = 0;
export const EXIT_FAILED = 1;
export const EXIT_NOT_APPROVED = 2;

/**
 * @typedef {'claude' | 'codex'} Client
 * @typedef {{ exitCode: number | null, stdout: string, stderr: string, spawnError?: string, timedOut?: boolean }} RunResult
 * @typedef {(command: string, args: readonly string[], timeoutMs: number) => Promise<RunResult>} Run
 * @typedef {'plugin' | 'skill' | 'none'} Route
 * @typedef {{ client: Client, route: Route, summary: string, commands: string[][], skillPath?: string, problem?: string }} PlanEntry
 * @typedef {{ run: Run, home: string, skillText: string, readText: (path: string) => Promise<string | undefined>, writeText: (path: string, text: string) => Promise<void>, log: (line: string) => void }} Environment
 */

/** @type {readonly Client[]} */
export const CLIENTS = ['claude', 'codex'];

/**
 * Where each client reads a user-level skill from when plugins are unavailable.
 * Codex documents `$HOME/.agents/skills`; Claude Code reads `~/.claude/skills`.
 * @param {Client} client
 * @param {string} home
 */
export function skillPathFor(client, home) {
  return client === 'claude'
    ? join(home, '.claude', 'skills', SKILL_NAME, 'SKILL.md')
    : join(home, '.agents', 'skills', SKILL_NAME, 'SKILL.md');
}

/**
 * The commands that install the plugin; only the final step differs between clients.
 * @param {Client} client
 * @param {boolean} isInstalled
 * @returns {string[][]}
 */
export function pluginCommands(client, isInstalled) {
  const scope = client === 'claude' ? ['--scope', 'user'] : [];
  if (isInstalled) return [['plugin', 'enable', PLUGIN_ID, ...scope]];
  return [
    ['plugin', 'marketplace', 'add', MARKETPLACE_SOURCE],
    ['plugin', client === 'codex' ? 'add' : 'install', PLUGIN_ID, ...scope],
  ];
}

/**
 * @param {Client} client
 * @param {unknown} value parsed `plugin list --json` output
 * @returns {{ id: string, enabled: boolean }[]}
 */
function readInventory(client, value) {
  const entries =
    client === 'codex'
      ? /** @type {{ installed?: { pluginId: string, enabled: boolean }[] }} */ (value).installed?.map(
          ({ pluginId, enabled }) => ({ id: pluginId, enabled }),
        )
      : /** @type {{ id: string, enabled: boolean }[]} */ (value);
  if (!Array.isArray(entries)) throw new TypeError('plugin inventory is not a list');
  for (const entry of entries) {
    if (typeof entry?.id !== 'string' || typeof entry?.enabled !== 'boolean')
      throw new TypeError('plugin inventory entry has no id or enabled flag');
  }
  return entries;
}

/**
 * Asks the client what it has. Never writes.
 * @param {Client} client
 * @param {Run} run
 * @returns {Promise<{ status: 'absent' } | { status: 'unsupported' | 'invalid', detail: string } | { status: 'available', isInstalled: boolean, isEnabled: boolean }>}
 */
export async function inspectClient(client, run) {
  const version = await run(client, ['--version'], PROBE_TIMEOUT_MS);
  if (version.exitCode !== 0) return { status: 'absent' };

  const list = await run(client, ['plugin', 'list', '--json'], PROBE_TIMEOUT_MS);
  if (list.timedOut) return { status: 'invalid', detail: `${client} plugin list timed out` };
  if (list.exitCode !== 0) {
    const text = `${list.spawnError ?? ''} ${list.stderr}`;
    return UNSUPPORTED_PATTERN.test(text)
      ? { status: 'unsupported', detail: text.trim() }
      : { status: 'invalid', detail: `${client} plugin list failed: ${text.trim() || `exit ${list.exitCode}`}` };
  }
  try {
    const entries = readInventory(client, JSON.parse(list.stdout));
    const ours = entries.filter(({ id }) => id.startsWith(PLUGIN_NAME_PREFIX));
    if (ours.length > 1 || ours.some(({ id }) => id !== PLUGIN_ID))
      return {
        status: 'invalid',
        detail: `another ${client} plugin source already provides "exact"; pick one in the client's plugin manager first`,
      };
    return { status: 'available', isInstalled: ours.length === 1, isEnabled: ours[0]?.enabled === true };
  } catch (error) {
    return { status: 'invalid', detail: `${client} returned an unreadable plugin list (${error instanceof Error ? error.message : 'parse error'})` };
  }
}

/**
 * Decides what to do for one client without changing anything.
 * @param {Client} client
 * @param {'auto' | 'plugin' | 'skill'} mode
 * @param {Environment} environment
 * @returns {Promise<PlanEntry>}
 */
export async function planClient(client, mode, environment) {
  const inspection = await inspectClient(client, environment.run);
  if (inspection.status === 'absent')
    return { client, route: 'none', summary: `${client}: not installed, skipped`, commands: [] };

  const skillPath = skillPathFor(client, environment.home);
  const planSkill = async (/** @type {string} */ reason) => {
    const existing = await environment.readText(skillPath);
    if (existing === environment.skillText)
      return { client, route: /** @type {Route} */ ('none'), summary: `${client}: skill already installed at ${skillPath}`, commands: [] };
    if (existing !== undefined)
      return {
        client,
        route: /** @type {Route} */ ('none'),
        summary: `${client}: ${skillPath} exists with different content`,
        commands: [],
        problem: `Left ${skillPath} unchanged because it is not this version's file. Delete it and rerun to replace it.`,
      };
    return { client, route: /** @type {Route} */ ('skill'), summary: `${client}: copy the skill to ${skillPath} (${reason})`, commands: [], skillPath };
  };

  if (mode === 'skill') return planSkill('chosen with --mode skill');
  if (inspection.status === 'unsupported') {
    return mode === 'plugin'
      ? { client, route: 'none', summary: `${client}: plugin commands are unavailable`, commands: [], problem: `${client} has no plugin commands (${inspection.detail}). Update it, or rerun with --mode skill.` }
      : planSkill('its plugin commands are unavailable');
  }
  if (inspection.status === 'invalid')
    return { client, route: 'none', summary: `${client}: plugin state could not be read`, commands: [], problem: inspection.detail };
  if (inspection.isInstalled && inspection.isEnabled)
    return { client, route: 'none', summary: `${client}: plugin ${PLUGIN_ID} already installed and enabled`, commands: [] };

  const commands = pluginCommands(client, inspection.isInstalled);
  return {
    client,
    route: 'plugin',
    summary: `${client}: ${inspection.isInstalled ? 'enable' : 'install'} plugin ${PLUGIN_ID} from ${MARKETPLACE_SOURCE}`,
    commands,
  };
}

/**
 * Applies one planned entry. A plugin entry is re-inspected first, so a change made
 * between the preview and the approval is respected instead of overwritten.
 * @param {PlanEntry} entry
 * @param {Environment} environment
 * @returns {Promise<string | undefined>} a problem to report, or undefined on success
 */
export async function applyEntry(entry, environment) {
  if (entry.route === 'skill' && entry.skillPath !== undefined) {
    if ((await environment.readText(entry.skillPath)) !== undefined)
      return `${entry.skillPath} appeared after the preview; left unchanged.`;
    await environment.writeText(entry.skillPath, environment.skillText);
    return undefined;
  }
  if (entry.route !== 'plugin') return undefined;

  const fresh = await inspectClient(entry.client, environment.run);
  if (fresh.status !== 'available') return `${entry.client} changed since the preview; rerun to plan again.`;
  if (fresh.isInstalled && fresh.isEnabled) return undefined;
  for (const args of pluginCommands(entry.client, fresh.isInstalled)) {
    const result = await environment.run(entry.client, args, INSTALL_TIMEOUT_MS);
    if (result.exitCode !== 0 || result.timedOut)
      return `${entry.client} ${args.join(' ')} did not complete (${result.timedOut ? 'timed out' : `exit ${result.exitCode}`}): ${result.stderr.trim() || result.spawnError || 'no output'}. A marketplace that was added stays added; rerun after fixing this.`;
  }
  const verified = await inspectClient(entry.client, environment.run);
  return verified.status === 'available' && verified.isInstalled && verified.isEnabled
    ? undefined
    : `${entry.client} did not confirm an enabled ${PLUGIN_ID}. Check "${entry.client} plugin list".`;
}

/**
 * @param {{ mode: 'auto' | 'plugin' | 'skill', clients: readonly Client[], yes: boolean, confirm: (question: string) => Promise<boolean> }} options
 * @param {Environment} environment
 * @returns {Promise<number>} the process exit code
 */
export async function install(options, environment) {
  const plan = [];
  for (const client of options.clients) plan.push(await planClient(client, options.mode, environment));

  environment.log('Plan:');
  for (const entry of plan) {
    environment.log(`  ${entry.summary}`);
    for (const args of entry.commands) environment.log(`    $ ${entry.client} ${args.join(' ')}`);
    if (entry.problem !== undefined) environment.log(`    ! ${entry.problem}`);
  }

  const actions = plan.filter(({ route }) => route !== 'none');
  const problems = plan.filter(({ problem }) => problem !== undefined);
  if (actions.length === 0) {
    environment.log(problems.length > 0 ? 'Nothing was changed.' : 'Nothing to do.');
    return problems.length > 0 ? EXIT_FAILED : EXIT_OK;
  }
  if (!options.yes && !(await options.confirm('Apply this plan? [y/N] '))) {
    environment.log('Not approved; nothing was changed. Rerun with --yes to skip this question.');
    return EXIT_NOT_APPROVED;
  }

  let failed = problems.length > 0;
  for (const entry of actions) {
    const problem = await applyEntry(entry, environment);
    environment.log(problem === undefined ? `  done: ${entry.summary}` : `  failed: ${problem}`);
    failed ||= problem !== undefined;
  }
  if (!failed) environment.log('Restart the client so it loads the skill.');
  return failed ? EXIT_FAILED : EXIT_OK;
}

/**
 * Runs a client command with a deadline and bounded output. Windows resolves `.cmd`
 * shims through cmd.exe, which is spawned explicitly instead of using the shell
 * option; every argument is a constant from this file.
 * @type {Run}
 */
export function runCommand(command, args, timeoutMs) {
  return new Promise(resolve => {
    const chunks = { stdout: '', stderr: '' };
    let timedOut = false;
    const child =
      process.platform === 'win32'
        ? spawn(process.env.ComSpec ?? 'cmd.exe', ['/d', '/s', '/c', command, ...args], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] })
        : spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill();
    }, timeoutMs);
    const collect = (/** @type {'stdout' | 'stderr'} */ key) => (/** @type {Buffer} */ data) => {
      if (chunks[key].length < OUTPUT_LIMIT_BYTES) chunks[key] += data.toString('utf8');
    };
    child.stdout.on('data', collect('stdout'));
    child.stderr.on('data', collect('stderr'));
    child.on('error', error => {
      clearTimeout(timer);
      resolve({ exitCode: null, ...chunks, spawnError: error.message, timedOut });
    });
    child.on('close', exitCode => {
      clearTimeout(timer);
      resolve({ exitCode, ...chunks, timedOut });
    });
  });
}

/** @param {string[]} argv */
export function parseArguments(argv) {
  const options = { mode: /** @type {'auto' | 'plugin' | 'skill'} */ ('auto'), clients: [...CLIENTS], yes: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[index + 1];
    if (argument === '--yes' || argument === '-y') options.yes = true;
    else if (argument === '--help' || argument === '-h') options.help = true;
    else if (argument === '--mode' && (value === 'auto' || value === 'plugin' || value === 'skill')) {
      options.mode = value;
      index += 1;
    } else if (argument === '--client' && (value === 'claude' || value === 'codex')) {
      options.clients = [value];
      index += 1;
    } else throw new Error(`Unknown or incomplete option: ${argument}. Run with --help.`);
  }
  return options;
}

const USAGE = `Usage: install-exact-skill [--client claude|codex] [--mode auto|plugin|skill] [--yes]

Installs the Exact skill into the coding agents on this machine.
  auto    (default) use the marketplace plugin where the client supports plugins,
          the bundled skill file where it does not, and skip absent clients
  plugin  require the marketplace plugin; never fall back to a skill file
  skill   copy the skill file instead of installing the plugin
A plan is shown first; nothing is written until you approve it or pass --yes.`;

async function main() {
  let options;
  try {
    options = parseArguments(process.argv.slice(2));
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    return EXIT_FAILED;
  }
  if (options.help) {
    console.log(USAGE);
    return EXIT_OK;
  }
  const skillFile = join(dirname(fileURLToPath(import.meta.url)), '..', 'skills', SKILL_NAME, 'SKILL.md');
  /** @type {Environment} */
  const environment = {
    run: runCommand,
    home: homedir(),
    skillText: await readFile(skillFile, 'utf8'),
    readText: async path => {
      try {
        await access(path);
        return await readFile(path, 'utf8');
      } catch (error) {
        if (/** @type {NodeJS.ErrnoException} */ (error).code === 'ENOENT') return undefined;
        throw error;
      }
    },
    writeText: async (path, text) => {
      await mkdir(dirname(path), { recursive: true });
      await writeFile(path, text, { encoding: 'utf8', flag: 'wx' });
    },
    log: line => console.log(line),
  };
  const confirm = async (/** @type {string} */ question) => {
    if (!process.stdin.isTTY) return false;
    const reader = createInterface({ input: process.stdin, output: process.stdout });
    try {
      return /^y(es)?$/iu.test((await reader.question(question)).trim());
    } finally {
      reader.close();
    }
  };
  return install({ ...options, confirm }, environment);
}

if (process.argv[1] !== undefined && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = await main();
}
