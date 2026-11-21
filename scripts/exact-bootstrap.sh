#!/usr/bin/env bash
# Idempotent Exact checkout + toolchain bootstrap for this plugin.
# Usage: exact-bootstrap.sh [--check] [--auto] [--timeout SECONDS]
# Env: EXACT (checkout path, default ~/exact)
#      EXACT_PLUGIN_NO_AUTOUPDATE=1 (skip --auto)

set -u

CHECK=0
AUTO=0
TIMEOUT_SECS=0
LOG_PREFIX="exact-plugin"
# Short bound for the SessionStart ls-remote probe (seconds).
LS_REMOTE_TIMEOUT_SECS="${EXACT_PLUGIN_LS_REMOTE_TIMEOUT_SECS:-5}"

usage() {
  cat <<'EOF'
Usage: exact-bootstrap.sh [--check] [--auto] [--timeout SECONDS]

  (default)  Ensure checkout, install missing rustup/Bun, run Exact setup when needed
  --check    Report only; non-zero if required tools or checkout paths are missing
  --auto     Quiet SessionStart mode: ls-remote HEAD vs local; update only if upstream
             moved; silent on match/offline/timeout; skip with EXACT_PLUGIN_NO_AUTOUPDATE=1
  --timeout  Kill the whole run after SECONDS (useful with --auto)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=1; shift ;;
    --auto|--quiet) AUTO=1; shift ;;
    --timeout)
      TIMEOUT_SECS="${2:-}"
      if [[ -z "$TIMEOUT_SECS" || ! "$TIMEOUT_SECS" =~ ^[0-9]+$ ]]; then
        echo "$LOG_PREFIX: --timeout needs a number" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "$LOG_PREFIX: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$AUTO" -eq 1 && "${EXACT_PLUGIN_NO_AUTOUPDATE:-}" == "1" ]]; then
  exit 0
fi

# Re-exec under timeout when requested.
if [[ "$TIMEOUT_SECS" -gt 0 && -z "${EXACT_BOOTSTRAP_TIMED:-}" ]]; then
  export EXACT_BOOTSTRAP_TIMED=1
  args=()
  [[ "$CHECK" -eq 1 ]] && args+=(--check)
  [[ "$AUTO" -eq 1 ]] && args+=(--auto)
  if command -v timeout >/dev/null 2>&1; then
    timeout --signal=TERM "$TIMEOUT_SECS" "$0" "${args[@]}"
    status=$?
    # --auto: never fail or chat about the session timeout.
    [[ "$AUTO" -eq 1 ]] && exit 0
    exit "$status"
  fi
  # No timeout(1): run without hard kill; --auto still swallows failures below.
fi

say() {
  if [[ "$AUTO" -eq 1 ]]; then
    echo "$LOG_PREFIX: $*" >&2
  else
    echo "$LOG_PREFIX: $*"
  fi
}

warn() { echo "$LOG_PREFIX: $*" >&2; }

die() {
  warn "$*"
  if [[ "$AUTO" -eq 1 ]]; then
    exit 0
  fi
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

ensure_path() {
  # Official installer locations.
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck source=/dev/null
    . "$HOME/.cargo/env"
  fi
  [[ -d "$HOME/.bun/bin" ]] && export PATH="$HOME/.bun/bin:$PATH"
  [[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
}

ensure_path

EXACT_DIR="${EXACT:-$HOME/exact}"
EXACT_REPO_URL="${EXACT_REPO_URL:-https://github.com/expo/exact.git}"
CHECK_STATUS=0
WILL_INSTALL=()

need_rustup=0
need_bun=0
bun_pin=""

# SessionStart --auto: probe upstream HEAD; exit silently unless it moved.
auto_skip_unless_upstream_moved() {
  [[ "$AUTO" -eq 1 ]] || return 0

  if [[ ! -d "$EXACT_DIR/.git" && ! -f "$EXACT_DIR/.git" ]]; then
    exit 0
  fi

  local local_head remote_out remote_head
  local_head="$(git -C "$EXACT_DIR" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$local_head" ]] || exit 0

  remote_out=""
  if command -v timeout >/dev/null 2>&1; then
    remote_out="$(GIT_TERMINAL_PROMPT=0 timeout --signal=TERM "$LS_REMOTE_TIMEOUT_SECS" \
      git ls-remote "$EXACT_REPO_URL" HEAD 2>/dev/null || true)"
  else
    remote_out="$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime="$LS_REMOTE_TIMEOUT_SECS" \
      ls-remote "$EXACT_REPO_URL" HEAD 2>/dev/null || true)"
  fi
  remote_head="$(printf '%s\n' "$remote_out" | awk 'NF { print $1; exit }')"
  # Offline, timeout, or empty reply: stay silent.
  [[ -n "$remote_head" ]] || exit 0
  # Already current: stay silent.
  [[ "$remote_head" == "$local_head" ]] && exit 0
  return 0
}

auto_skip_unless_upstream_moved

read_bun_pin() {
  local pkg="$1"
  [[ -f "$pkg" ]] || return 1
  # packageManager: "bun@1.4.2"
  bun_pin="$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"bun@\([^"]*\)".*/\1/p' "$pkg" | head -n1)"
  [[ -n "$bun_pin" ]]
}

bun_version() {
  if have bun; then bun --version 2>/dev/null | head -n1; else echo ""; fi
}

plan_prereqs() {
  if ! have rustup; then
    need_rustup=1
    WILL_INSTALL+=("rustup (https://sh.rustup.rs)")
  fi
  if [[ -f "$EXACT_DIR/package.json" ]]; then
    read_bun_pin "$EXACT_DIR/package.json" || bun_pin=""
  fi
  local have_ver
  have_ver="$(bun_version)"
  if [[ -z "$have_ver" ]]; then
    need_bun=1
    WILL_INSTALL+=("Bun ${bun_pin:-latest} (https://bun.com/install)")
  elif [[ -n "$bun_pin" && "$have_ver" != "$bun_pin" ]]; then
    need_bun=1
    WILL_INSTALL+=("Bun $bun_pin (have $have_ver; Exact pins $bun_pin)")
  fi
}

install_rustup() {
  say "installing rustup"
  curl --proto '=https' --tlsv1.2 -fsSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  ensure_path
  have rustup || die "rustup install finished but rustup is not on PATH"
}

install_bun() {
  local tag="bun-v${bun_pin}"
  if [[ -z "$bun_pin" ]]; then
    say "installing Bun (latest; Exact package.json not readable yet)"
    curl -fsSL https://bun.com/install | bash
  else
    say "installing Bun $bun_pin"
    curl -fsSL https://bun.com/install | bash -s "$tag"
  fi
  ensure_path
  have bun || die "Bun install finished but bun is not on PATH"
  if [[ -n "$bun_pin" ]]; then
    local have_ver
    have_ver="$(bun_version)"
    [[ "$have_ver" == "$bun_pin" ]] || warn "Bun is $have_ver; Exact pins $bun_pin"
  fi
}

report_platform_sdks() {
  # Report-only: Exact setup does not install these.
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if have xcodebuild; then
      say "Xcode: $(xcodebuild -version 2>/dev/null | head -n1)"
    else
      say "Xcode: not found (needed for macOS/iOS hosts; install from the App Store)"
      [[ "$CHECK" -eq 1 ]] && CHECK_STATUS=1
    fi
  else
    say "Xcode: n/a on this OS (macOS/iOS hosts need a Mac)"
  fi
  if [[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" || -d "$HOME/Android/Sdk" || -d "$HOME/Library/Android/sdk" ]]; then
    say "Android SDK: present (${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}})"
  else
    say "Android SDK: not found (needed for Android; install the SDK yourself)"
  fi
}

ensure_checkout() {
  if [[ ! -d "$EXACT_DIR/.git" && ! -f "$EXACT_DIR/.git" ]]; then
    if [[ "$CHECK" -eq 1 ]]; then
      say "checkout: missing at $EXACT_DIR"
      CHECK_STATUS=1
      return 1
    fi
    say "cloning $EXACT_REPO_URL -> $EXACT_DIR"
    mkdir -p "$(dirname "$EXACT_DIR")"
    git clone "$EXACT_REPO_URL" "$EXACT_DIR" || die "git clone failed"
  fi
  if [[ ! -f "$EXACT_DIR/scripts/exact.mjs" ]]; then
    say "checkout: $EXACT_DIR lacks scripts/exact.mjs"
    CHECK_STATUS=1
    [[ "$CHECK" -eq 1 ]] && return 1
    die "not an Exact checkout: $EXACT_DIR"
  fi
  return 0
}

update_checkout() {
  local dirty
  dirty="$(git -C "$EXACT_DIR" status --porcelain 2>/dev/null || true)"
  if [[ -n "$dirty" ]]; then
    warn "checkout has local changes; leaving HEAD alone (will not discard)"
    return 0
  fi
  if [[ "$CHECK" -eq 1 ]]; then
    if git -C "$EXACT_DIR" fetch --quiet origin 2>/dev/null; then
      local behind
      behind="$(git -C "$EXACT_DIR" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo "?")"
      say "checkout: fetch ok; commits behind upstream: $behind"
    else
      say "checkout: could not fetch (network or no upstream)"
      CHECK_STATUS=1
    fi
    return 0
  fi
  say "fetching Exact"
  if ! git -C "$EXACT_DIR" fetch --quiet origin; then
    warn "git fetch failed; continuing on current commit"
    return 0
  fi
  if ! git -C "$EXACT_DIR" pull --ff-only --quiet; then
    warn "pull --ff-only failed; continuing on current commit"
  fi
}

stamp_path() {
  local git_dir
  git_dir="$(git -C "$EXACT_DIR" rev-parse --git-dir 2>/dev/null)" || return 1
  # Prefer the checkout's git dir; fall back to user cache.
  if [[ -n "$git_dir" ]]; then
    if [[ "$git_dir" != /* ]]; then
      git_dir="$EXACT_DIR/$git_dir"
    fi
    echo "$git_dir/exact-plugin-setup-stamp"
    return 0
  fi
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/exact-plugin"
  mkdir -p "$cache"
  local key
  key="$(printf '%s' "$EXACT_DIR" | sha256sum 2>/dev/null | awk '{print $1}')"
  [[ -z "$key" ]] && key="$(printf '%s' "$EXACT_DIR" | shasum -a 256 2>/dev/null | awk '{print $1}')"
  echo "$cache/setup-$key"
}

run_setup_if_needed() {
  ensure_path
  have bun || die "bun is required to run Exact setup"
  have rustup || die "rustup is required to run Exact setup"

  local head stamp last
  head="$(git -C "$EXACT_DIR" rev-parse HEAD)"
  stamp="$(stamp_path)" || die "could not resolve stamp path"
  last=""
  [[ -f "$stamp" ]] && last="$(tr -d '[:space:]' <"$stamp")"

  if [[ "$CHECK" -eq 1 ]]; then
    say "running: bun scripts/exact.mjs setup --check"
    if (cd "$EXACT_DIR" && bun scripts/exact.mjs setup --check); then
      say "setup --check: ok"
    else
      say "setup --check: reported missing or differing tools (see above)"
      CHECK_STATUS=1
    fi
    if [[ "$last" == "$head" ]]; then
      say "setup stamp: current ($head)"
    else
      say "setup stamp: stale or missing (last=${last:-none} head=$head)"
    fi
    return 0
  fi

  if [[ "$last" == "$head" ]]; then
    say "setup: skipped (HEAD unchanged since last successful setup)"
    return 0
  fi

  say "running: bun scripts/exact.mjs setup"
  if (cd "$EXACT_DIR" && bun scripts/exact.mjs setup); then
    printf '%s\n' "$head" >"$stamp"
    say "setup: ok; stamped $head"
  else
    die "bun scripts/exact.mjs setup failed"
  fi
}

print_summary() {
  if [[ -d "$EXACT_DIR/.git" || -f "$EXACT_DIR/.git" ]]; then
    local head
    head="$(git -C "$EXACT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    say "checkout: $EXACT_DIR"
    say "HEAD: $head"
  fi
}

# --- main ---
ensure_checkout || true
plan_prereqs

if [[ ${#WILL_INSTALL[@]} -gt 0 ]]; then
  if [[ "$CHECK" -eq 1 ]]; then
    say "would install:"
    for item in "${WILL_INSTALL[@]}"; do say "  - $item"; done
    CHECK_STATUS=1
  else
    say "will install:"
    for item in "${WILL_INSTALL[@]}"; do say "  - $item"; done
    [[ "$need_rustup" -eq 1 ]] && install_rustup
    # Clone may have been missing; pin may appear only after clone.
    if [[ -z "$bun_pin" && -f "$EXACT_DIR/package.json" ]]; then
      read_bun_pin "$EXACT_DIR/package.json" || true
      plan_prereqs
    fi
    [[ "$need_bun" -eq 1 ]] && install_bun
  fi
else
  say "prerequisites: rustup and Bun $(bun_version) present"
fi

if [[ -d "$EXACT_DIR/.git" || -f "$EXACT_DIR/.git" ]]; then
  update_checkout
  # After pull, Bun pin may have moved.
  if [[ -f "$EXACT_DIR/package.json" ]]; then
    read_bun_pin "$EXACT_DIR/package.json" || true
    local_ver="$(bun_version)"
    if [[ "$CHECK" -eq 0 && -n "$bun_pin" && -n "$local_ver" && "$local_ver" != "$bun_pin" ]]; then
      say "Bun pin is now $bun_pin (have $local_ver); upgrading"
      install_bun
    elif [[ "$CHECK" -eq 1 && -n "$bun_pin" && -n "$local_ver" && "$local_ver" != "$bun_pin" ]]; then
      say "Bun pin mismatch: have $local_ver, Exact wants $bun_pin"
      CHECK_STATUS=1
    fi
  fi
  if [[ -f "$EXACT_DIR/scripts/exact.mjs" ]]; then
    run_setup_if_needed
  fi
fi

report_platform_sdks
print_summary

if [[ "$CHECK" -eq 1 ]]; then
  if [[ "$CHECK_STATUS" -ne 0 ]]; then
    say "check: FAILED"
    [[ "$AUTO" -eq 1 ]] && exit 0
    exit 1
  fi
  say "check: OK"
  exit 0
fi

[[ "$AUTO" -eq 1 ]] && exit 0
exit 0
