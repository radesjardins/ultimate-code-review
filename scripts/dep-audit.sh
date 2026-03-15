#!/usr/bin/env bash
# UCR Dependency Audit Wrapper
# Detects package manager and runs vulnerability audit
#
# Usage:
#   ./dep-audit.sh [--local-only] [directory]
#
# Outputs standardized JSON to stdout.
# Exit code 0 = success (even if vulnerabilities found; check JSON for results).
# Exit code 1 = script error.

set -euo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
LOCAL_ONLY=false
TARGET_DIR="."
RESULTS=()
SKIPPED=()

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --local-only)
      LOCAL_ONLY=true
      shift
      ;;
    -h|--help)
      echo "Usage: dep-audit.sh [--local-only] [directory]"
      echo "  --local-only   Skip network-dependent checks (offline cache only)"
      echo "  directory      Target directory to audit (default: current directory)"
      exit 0
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "{\"error\": \"Directory not found: $TARGET_DIR\"}" >&2
  exit 1
fi

cd "$TARGET_DIR"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S"
}

command_exists() {
  command -v "$1" &>/dev/null
}

json_escape() {
  # Minimal JSON string escaping for inline values
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

skip_manager() {
  local manager="$1"
  local reason="$2"
  SKIPPED+=("{\"manager\": \"$manager\", \"reason\": \"$(json_escape "$reason")\"}")
}

# ---------------------------------------------------------------------------
# Auditors — each function appends to RESULTS or SKIPPED
# ---------------------------------------------------------------------------

audit_npm() {
  [[ -f "package-lock.json" || -f "package.json" ]] || return 0

  if ! command_exists npm; then
    skip_manager "npm" "npm not found in PATH"
    return 0
  fi

  local args=("audit" "--json")
  if [[ "$LOCAL_ONLY" == true ]]; then
    # npm audit requires network; skip in local-only mode
    skip_manager "npm" "Skipped in --local-only mode (npm audit requires network)"
    return 0
  fi

  local raw
  raw=$(npm "${args[@]}" 2>/dev/null) || true

  # npm audit --json returns structured data; extract summary
  local vuln_total vuln_critical vuln_high vuln_moderate vuln_low
  vuln_total=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    meta = d.get('metadata', d.get('auditReportVersion', {}))
    vulns = meta.get('vulnerabilities', {})
    print(sum(vulns.values()) if isinstance(vulns, dict) else 0)
except: print(0)
" 2>/dev/null || echo "0")

  local summary
  summary=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    meta = d.get('metadata', {})
    vulns = meta.get('vulnerabilities', {})
    if isinstance(vulns, dict):
        print(json.dumps(vulns))
    else:
        print('{}')
except: print('{}')
" 2>/dev/null || echo "{}")

  RESULTS+=("{\"manager\": \"npm\", \"lockfile\": true, \"total_vulnerabilities\": $vuln_total, \"severity_counts\": $summary, \"raw_available\": true}")
}

audit_yarn() {
  [[ -f "yarn.lock" ]] || return 0

  if ! command_exists yarn; then
    skip_manager "yarn" "yarn not found in PATH"
    return 0
  fi

  if [[ "$LOCAL_ONLY" == true ]]; then
    skip_manager "yarn" "Skipped in --local-only mode (yarn audit requires network)"
    return 0
  fi

  local raw
  raw=$(yarn audit --json 2>/dev/null) || true

  local vuln_count
  vuln_count=$(echo "$raw" | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        if d.get('type') == 'auditAdvisory':
            count += 1
    except: pass
print(count)
" 2>/dev/null || echo "0")

  RESULTS+=("{\"manager\": \"yarn\", \"lockfile\": true, \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")
}

audit_pnpm() {
  [[ -f "pnpm-lock.yaml" ]] || return 0

  if ! command_exists pnpm; then
    skip_manager "pnpm" "pnpm not found in PATH"
    return 0
  fi

  if [[ "$LOCAL_ONLY" == true ]]; then
    skip_manager "pnpm" "Skipped in --local-only mode (pnpm audit requires network)"
    return 0
  fi

  local raw
  raw=$(pnpm audit --json 2>/dev/null) || true

  local vuln_count
  vuln_count=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    meta = d.get('metadata', {})
    vulns = meta.get('vulnerabilities', {})
    print(sum(vulns.values()) if isinstance(vulns, dict) else 0)
except: print(0)
" 2>/dev/null || echo "0")

  RESULTS+=("{\"manager\": \"pnpm\", \"lockfile\": true, \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")
}

audit_pip() {
  [[ -f "requirements.txt" || -f "Pipfile.lock" || -f "pyproject.toml" || -f "setup.py" ]] || return 0

  # Try pip-audit first, then safety, then skip
  if command_exists pip-audit; then
    if [[ "$LOCAL_ONLY" == true ]]; then
      skip_manager "pip" "Skipped in --local-only mode (pip-audit requires network)"
      return 0
    fi

    local raw
    raw=$(pip-audit --format=json 2>/dev/null) || true

    local vuln_count
    vuln_count=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # pip-audit returns a list of vulnerability objects
    vulns = d if isinstance(d, list) else d.get('vulnerabilities', [])
    print(len(vulns))
except: print(0)
" 2>/dev/null || echo "0")

    RESULTS+=("{\"manager\": \"pip\", \"tool\": \"pip-audit\", \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")

  elif command_exists safety; then
    if [[ "$LOCAL_ONLY" == true ]]; then
      skip_manager "pip" "Skipped in --local-only mode (safety requires network)"
      return 0
    fi

    local raw
    raw=$(safety check --json 2>/dev/null) || true

    local vuln_count
    vuln_count=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d) if isinstance(d, list) else 0)
except: print(0)
" 2>/dev/null || echo "0")

    RESULTS+=("{\"manager\": \"pip\", \"tool\": \"safety\", \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")

  else
    skip_manager "pip" "Neither pip-audit nor safety found in PATH; install with: pip install pip-audit"
  fi
}

audit_cargo() {
  [[ -f "Cargo.lock" || -f "Cargo.toml" ]] || return 0

  if ! command_exists cargo; then
    skip_manager "cargo" "cargo not found in PATH"
    return 0
  fi

  # cargo-audit is a subcommand plugin
  if ! cargo audit --version &>/dev/null; then
    skip_manager "cargo" "cargo-audit not installed; install with: cargo install cargo-audit"
    return 0
  fi

  if [[ "$LOCAL_ONLY" == true ]]; then
    # cargo-audit can use a local advisory DB if already fetched
    local raw
    raw=$(cargo audit --json 2>/dev/null) || true
  else
    local raw
    raw=$(cargo audit --json 2>/dev/null) || true
  fi

  local vuln_count
  vuln_count=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    vulns = d.get('vulnerabilities', {}).get('list', [])
    print(len(vulns))
except: print(0)
" 2>/dev/null || echo "0")

  RESULTS+=("{\"manager\": \"cargo\", \"tool\": \"cargo-audit\", \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")
}

audit_go() {
  [[ -f "go.sum" || -f "go.mod" ]] || return 0

  if ! command_exists go; then
    skip_manager "go" "go not found in PATH"
    return 0
  fi

  # govulncheck is the official Go vulnerability checker
  if command_exists govulncheck; then
    if [[ "$LOCAL_ONLY" == true ]]; then
      skip_manager "go" "Skipped in --local-only mode (govulncheck requires network)"
      return 0
    fi

    local raw
    raw=$(govulncheck -json ./... 2>/dev/null) || true

    local vuln_count
    vuln_count=$(echo "$raw" | python3 -c "
import sys, json
count = 0
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        if 'osv' in d:
            count += 1
    except: pass
print(count)
" 2>/dev/null || echo "0")

    RESULTS+=("{\"manager\": \"go\", \"tool\": \"govulncheck\", \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")
  else
    skip_manager "go" "govulncheck not found; install with: go install golang.org/x/vuln/cmd/govulncheck@latest"
  fi
}

audit_gem() {
  [[ -f "Gemfile.lock" || -f "Gemfile" ]] || return 0

  if ! command_exists bundle; then
    skip_manager "gem" "bundler not found in PATH"
    return 0
  fi

  if command_exists bundle-audit || bundle audit --version &>/dev/null 2>&1; then
    if [[ "$LOCAL_ONLY" == true ]]; then
      # bundle-audit can use local DB if previously updated
      local raw
      raw=$(bundle-audit check --format=json 2>/dev/null || bundle audit --format=json 2>/dev/null) || true
    else
      # Update advisory DB first
      bundle-audit update 2>/dev/null || bundle audit update 2>/dev/null || true
      local raw
      raw=$(bundle-audit check --format=json 2>/dev/null || bundle audit --format=json 2>/dev/null) || true
    fi

    local vuln_count
    vuln_count=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    results = d.get('results', [])
    print(len(results))
except: print(0)
" 2>/dev/null || echo "0")

    RESULTS+=("{\"manager\": \"gem\", \"tool\": \"bundle-audit\", \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")
  else
    skip_manager "gem" "bundle-audit not found; install with: gem install bundler-audit"
  fi
}

audit_composer() {
  [[ -f "composer.lock" || -f "composer.json" ]] || return 0

  if ! command_exists composer; then
    skip_manager "composer" "composer not found in PATH"
    return 0
  fi

  if [[ "$LOCAL_ONLY" == true ]]; then
    # composer audit uses local data from composer.lock
    local raw
    raw=$(composer audit --format=json --no-interaction 2>/dev/null) || true
  else
    local raw
    raw=$(composer audit --format=json --no-interaction 2>/dev/null) || true
  fi

  local vuln_count
  vuln_count=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    advisories = d.get('advisories', {})
    count = sum(len(v) for v in advisories.values()) if isinstance(advisories, dict) else 0
    print(count)
except: print(0)
" 2>/dev/null || echo "0")

  RESULTS+=("{\"manager\": \"composer\", \"total_vulnerabilities\": $vuln_count, \"raw_available\": true}")
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local start_time
  start_time=$(timestamp)

  # Run all auditors
  audit_npm
  audit_yarn
  audit_pnpm
  audit_pip
  audit_cargo
  audit_go
  audit_gem
  audit_composer

  local end_time
  end_time=$(timestamp)

  # Build JSON arrays
  local results_json="["
  local first=true
  for r in "${RESULTS[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      results_json+=", "
    fi
    results_json+="$r"
  done
  results_json+="]"

  local skipped_json="["
  first=true
  for s in "${SKIPPED[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      skipped_json+=", "
    fi
    skipped_json+="$s"
  done
  skipped_json+="]"

  # Determine detected managers
  local detected_count=$(( ${#RESULTS[@]} + ${#SKIPPED[@]} ))

  # Output standardized JSON
  cat <<ENDJSON
{
  "tool": "ucr-dep-audit",
  "version": "1.0.0",
  "timestamp": "$start_time",
  "directory": "$(pwd)",
  "local_only": $LOCAL_ONLY,
  "managers_detected": $detected_count,
  "managers_audited": ${#RESULTS[@]},
  "managers_skipped": ${#SKIPPED[@]},
  "results": $results_json,
  "skipped": $skipped_json
}
ENDJSON
}

main
