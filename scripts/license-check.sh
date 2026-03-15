#!/usr/bin/env bash
# UCR License Compliance Checker
# Detects package manager and checks dependency licenses for compliance issues.
#
# Usage:
#   ./license-check.sh [directory]
#
# Outputs standardized JSON to stdout.
# Exit code 0 = success (even if issues found; check JSON for results).
# Exit code 1 = script error.

set -euo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
TARGET_DIR="."
RESULTS=()
SKIPPED=()
FLAGGED=()

# Copyleft / restrictive licenses that are problematic in non-GPL projects
COPYLEFT_LICENSES=(
  "GPL-2.0"
  "GPL-3.0"
  "AGPL-3.0"
  "LGPL-2.1"
  "LGPL-3.0"
  "EUPL-1.1"
  "EUPL-1.2"
  "SSPL-1.0"
  "CPAL-1.0"
  "OSL-3.0"
  "CC-BY-SA"
  "CC-BY-NC"
  "CC-BY-NC-SA"
  "CC-BY-NC-ND"
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      echo "Usage: license-check.sh [directory]"
      echo "  directory   Target directory to check (default: current directory)"
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

is_copyleft() {
  local license="$1"
  local upper_license
  upper_license=$(echo "$license" | tr '[:lower:]' '[:upper:]')
  for cl in "${COPYLEFT_LICENSES[@]}"; do
    local upper_cl
    upper_cl=$(echo "$cl" | tr '[:lower:]' '[:upper:]')
    if [[ "$upper_license" == *"$upper_cl"* ]]; then
      return 0
    fi
  done
  return 1
}

is_unknown_license() {
  local license="$1"
  if [[ -z "$license" || "$license" == "null" || "$license" == "UNKNOWN" || "$license" == "unknown" || "$license" == "UNLICENSED" || "$license" == "N/A" || "$license" == "Custom" ]]; then
    return 0
  fi
  return 1
}

# Detect if the host project itself is GPL-family
detect_project_license() {
  local project_license="unknown"
  if [[ -f "LICENSE" ]]; then
    if grep -qi "GNU GENERAL PUBLIC LICENSE" LICENSE 2>/dev/null; then
      project_license="GPL"
    elif grep -qi "GNU LESSER GENERAL PUBLIC LICENSE" LICENSE 2>/dev/null; then
      project_license="LGPL"
    elif grep -qi "GNU AFFERO GENERAL PUBLIC LICENSE" LICENSE 2>/dev/null; then
      project_license="AGPL"
    elif grep -qi "MIT License" LICENSE 2>/dev/null; then
      project_license="MIT"
    elif grep -qi "Apache License" LICENSE 2>/dev/null; then
      project_license="Apache"
    elif grep -qi "BSD" LICENSE 2>/dev/null; then
      project_license="BSD"
    fi
  elif [[ -f "package.json" ]]; then
    project_license=$(python3 -c "
import json, sys
try:
    with open('package.json') as f:
        d = json.load(f)
    print(d.get('license', 'unknown'))
except: print('unknown')
" 2>/dev/null || echo "unknown")
  elif [[ -f "Cargo.toml" ]]; then
    project_license=$(grep -i '^license' Cargo.toml 2>/dev/null | head -1 | sed 's/.*=\s*"\(.*\)"/\1/' || echo "unknown")
  fi
  echo "$project_license"
}

# ---------------------------------------------------------------------------
# License checkers per package manager
# ---------------------------------------------------------------------------

check_npm() {
  [[ -f "package.json" ]] || return 0

  # Prefer license-checker, fall back to npm ls
  if command_exists npx && command_exists npm; then
    local raw
    raw=$(npx --yes license-checker --json --production 2>/dev/null) || true

    if [[ -n "$raw" && "$raw" != "{}" ]]; then
      # Parse license-checker JSON output
      local deps_json
      deps_json=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    deps = []
    for name, info in d.items():
        lic = info.get('licenses', 'UNKNOWN')
        if isinstance(lic, list):
            lic = ' OR '.join(lic)
        deps.append({'name': name, 'license': lic, 'repository': info.get('repository', '')})
    print(json.dumps(deps))
except Exception as e:
    print('[]')
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"npm\", \"tool\": \"license-checker\", \"dependencies\": $deps_json}")
      return 0
    fi
  fi

  if command_exists npm; then
    local raw
    raw=$(npm ls --all --json 2>/dev/null) || true

    if [[ -n "$raw" ]]; then
      local deps_json
      deps_json=$(echo "$raw" | python3 -c "
import sys, json
def extract(deps, result):
    if not isinstance(deps, dict): return
    for name, info in deps.items():
        if isinstance(info, dict):
            lic = info.get('license', info.get('licenses', 'UNKNOWN'))
            if isinstance(lic, list):
                lic = ' OR '.join([l.get('type','?') if isinstance(l,dict) else str(l) for l in lic])
            elif isinstance(lic, dict):
                lic = lic.get('type', 'UNKNOWN')
            result.append({'name': name, 'license': str(lic)})
            extract(info.get('dependencies', {}), result)
try:
    d = json.load(sys.stdin)
    result = []
    extract(d.get('dependencies', {}), result)
    print(json.dumps(result))
except: print('[]')
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"npm\", \"tool\": \"npm-ls\", \"dependencies\": $deps_json}")
    else
      skip_manager "npm" "npm ls failed to produce output"
    fi
  else
    skip_manager "npm" "npm not found in PATH"
  fi
}

check_yarn() {
  [[ -f "yarn.lock" ]] || return 0

  if ! command_exists yarn; then
    skip_manager "yarn" "yarn not found in PATH"
    return 0
  fi

  local raw
  raw=$(yarn licenses list --json 2>/dev/null) || true

  if [[ -n "$raw" ]]; then
    local deps_json
    deps_json=$(echo "$raw" | python3 -c "
import sys, json
deps = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        if d.get('type') == 'table':
            body = d.get('data', {}).get('body', [])
            for row in body:
                if len(row) >= 3:
                    deps.append({'name': row[0], 'license': row[2]})
    except: pass
print(json.dumps(deps))
" 2>/dev/null || echo "[]")

    RESULTS+=("{\"manager\": \"yarn\", \"tool\": \"yarn-licenses\", \"dependencies\": $deps_json}")
  else
    skip_manager "yarn" "yarn licenses list produced no output"
  fi
}

check_pnpm() {
  [[ -f "pnpm-lock.yaml" ]] || return 0

  if ! command_exists pnpm; then
    skip_manager "pnpm" "pnpm not found in PATH"
    return 0
  fi

  local raw
  raw=$(pnpm licenses list --json 2>/dev/null) || true

  if [[ -n "$raw" ]]; then
    local deps_json
    deps_json=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    deps = []
    for lic_name, pkgs in d.items():
        if isinstance(pkgs, list):
            for pkg in pkgs:
                deps.append({'name': pkg.get('name', '?'), 'license': lic_name})
        elif isinstance(pkgs, dict):
            for pkg_name in pkgs:
                deps.append({'name': pkg_name, 'license': lic_name})
    print(json.dumps(deps))
except: print('[]')
" 2>/dev/null || echo "[]")

    RESULTS+=("{\"manager\": \"pnpm\", \"tool\": \"pnpm-licenses\", \"dependencies\": $deps_json}")
  else
    skip_manager "pnpm" "pnpm licenses list produced no output"
  fi
}

check_pip() {
  [[ -f "requirements.txt" || -f "Pipfile.lock" || -f "pyproject.toml" || -f "setup.py" ]] || return 0

  if command_exists pip-licenses; then
    local raw
    raw=$(pip-licenses --format=json --with-urls 2>/dev/null) || true

    if [[ -n "$raw" ]]; then
      local deps_json
      deps_json=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    deps = [{'name': p.get('Name','?'), 'license': p.get('License','UNKNOWN'), 'url': p.get('URL','')} for p in d]
    print(json.dumps(deps))
except: print('[]')
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"pip\", \"tool\": \"pip-licenses\", \"dependencies\": $deps_json}")
    else
      skip_manager "pip" "pip-licenses produced no output"
    fi
  elif command_exists pip; then
    local raw
    raw=$(pip show $(pip freeze 2>/dev/null | sed 's/==.*//' | head -100) 2>/dev/null) || true

    if [[ -n "$raw" ]]; then
      local deps_json
      deps_json=$(echo "$raw" | python3 -c "
import sys, json
deps = []
current = {}
for line in sys.stdin:
    line = line.rstrip()
    if line.startswith('Name:'):
        if current: deps.append(current)
        current = {'name': line.split(':',1)[1].strip(), 'license': 'UNKNOWN'}
    elif line.startswith('License:'):
        current['license'] = line.split(':',1)[1].strip() or 'UNKNOWN'
if current: deps.append(current)
print(json.dumps(deps))
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"pip\", \"tool\": \"pip-show\", \"dependencies\": $deps_json}")
    else
      skip_manager "pip" "pip show produced no output"
    fi
  else
    skip_manager "pip" "Neither pip-licenses nor pip found; install pip-licenses for best results"
  fi
}

check_cargo() {
  [[ -f "Cargo.toml" ]] || return 0

  if ! command_exists cargo; then
    skip_manager "cargo" "cargo not found in PATH"
    return 0
  fi

  if command_exists cargo-license; then
    local raw
    raw=$(cargo-license --json 2>/dev/null || cargo license --json 2>/dev/null) || true

    if [[ -n "$raw" ]]; then
      local deps_json
      deps_json=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    deps = [{'name': p.get('name','?'), 'license': p.get('license','UNKNOWN')} for p in d]
    print(json.dumps(deps))
except: print('[]')
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"cargo\", \"tool\": \"cargo-license\", \"dependencies\": $deps_json}")
    else
      skip_manager "cargo" "cargo-license produced no output"
    fi
  else
    skip_manager "cargo" "cargo-license not installed; install with: cargo install cargo-license"
  fi
}

check_go() {
  [[ -f "go.mod" ]] || return 0

  if ! command_exists go; then
    skip_manager "go" "go not found in PATH"
    return 0
  fi

  # go-licenses is the standard tool
  if command_exists go-licenses; then
    local raw
    raw=$(go-licenses csv ./... 2>/dev/null) || true

    if [[ -n "$raw" ]]; then
      local deps_json
      deps_json=$(echo "$raw" | python3 -c "
import sys, json, csv, io
deps = []
reader = csv.reader(sys.stdin)
for row in reader:
    if len(row) >= 2:
        deps.append({'name': row[0], 'license': row[1] if len(row) > 1 else 'UNKNOWN', 'url': row[2] if len(row) > 2 else ''})
print(json.dumps(deps))
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"go\", \"tool\": \"go-licenses\", \"dependencies\": $deps_json}")
    else
      skip_manager "go" "go-licenses produced no output"
    fi
  else
    # Fallback: parse go.sum for module names (no license info)
    if [[ -f "go.sum" ]]; then
      local deps_json
      deps_json=$(python3 -c "
import json
deps = set()
with open('go.sum') as f:
    for line in f:
        parts = line.strip().split()
        if parts:
            deps.add(parts[0])
result = [{'name': d, 'license': 'UNKNOWN (install go-licenses for detection)'} for d in sorted(deps)]
print(json.dumps(result))
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"go\", \"tool\": \"go.sum-parse\", \"dependencies\": $deps_json}")
    fi
    skip_manager "go" "go-licenses not found; install with: go install github.com/google/go-licenses@latest"
  fi
}

check_gem() {
  [[ -f "Gemfile" || -f "Gemfile.lock" ]] || return 0

  if ! command_exists bundle; then
    skip_manager "gem" "bundler not found in PATH"
    return 0
  fi

  if command_exists license_finder; then
    local raw
    raw=$(license_finder --format=json 2>/dev/null) || true

    if [[ -n "$raw" ]]; then
      local deps_json
      deps_json=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    deps_list = d.get('dependencies', d) if isinstance(d, dict) else d
    deps = [{'name': p.get('name','?'), 'license': ', '.join(p.get('licenses',['UNKNOWN']))} for p in deps_list]
    print(json.dumps(deps))
except: print('[]')
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"gem\", \"tool\": \"license_finder\", \"dependencies\": $deps_json}")
    else
      skip_manager "gem" "license_finder produced no output"
    fi
  else
    # Fallback: parse Gemfile.lock for gem names
    if [[ -f "Gemfile.lock" ]]; then
      local deps_json
      deps_json=$(python3 -c "
import json, re
deps = []
in_specs = False
with open('Gemfile.lock') as f:
    for line in f:
        line = line.rstrip()
        if line.strip() == 'specs:':
            in_specs = True
            continue
        if in_specs:
            m = re.match(r'^\s{4}(\S+)\s+\((.+)\)', line)
            if m:
                deps.append({'name': m.group(1), 'version': m.group(2), 'license': 'UNKNOWN (install license_finder)'})
            elif not line.startswith(' '):
                in_specs = False
print(json.dumps(deps))
" 2>/dev/null || echo "[]")

      RESULTS+=("{\"manager\": \"gem\", \"tool\": \"gemfile-parse\", \"dependencies\": $deps_json}")
    fi
    skip_manager "gem" "license_finder not found; install with: gem install license_finder"
  fi
}

check_composer() {
  [[ -f "composer.json" ]] || return 0

  if ! command_exists composer; then
    skip_manager "composer" "composer not found in PATH"
    return 0
  fi

  local raw
  raw=$(composer licenses --format=json --no-interaction 2>/dev/null) || true

  if [[ -n "$raw" ]]; then
    local deps_json
    deps_json=$(echo "$raw" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    deps_dict = d.get('dependencies', {})
    deps = []
    for name, info in deps_dict.items():
        lic = info.get('license', ['UNKNOWN'])
        if isinstance(lic, list):
            lic = ' OR '.join(lic)
        deps.append({'name': name, 'version': info.get('version', '?'), 'license': lic})
    print(json.dumps(deps))
except: print('[]')
" 2>/dev/null || echo "[]")

    RESULTS+=("{\"manager\": \"composer\", \"tool\": \"composer-licenses\", \"dependencies\": $deps_json}")
  else
    skip_manager "composer" "composer licenses produced no output"
  fi
}

# ---------------------------------------------------------------------------
# Flag problematic licenses
# ---------------------------------------------------------------------------
flag_issues() {
  local project_license
  project_license=$(detect_project_license)
  local is_project_gpl=false

  if [[ "$project_license" == "GPL" || "$project_license" == "AGPL" || "$project_license" == "LGPL" ]]; then
    is_project_gpl=true
  fi

  # Process all results to find license issues
  local all_results_json="["
  local first=true
  for r in "${RESULTS[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      all_results_json+=", "
    fi
    all_results_json+="$r"
  done
  all_results_json+="]"

  local flags_json
  flags_json=$(echo "$all_results_json" | python3 -c "
import sys, json

copyleft = ['GPL-2.0', 'GPL-3.0', 'AGPL-3.0', 'LGPL-2.1', 'LGPL-3.0', 'EUPL', 'SSPL', 'CPAL', 'OSL-3.0', 'CC-BY-SA', 'CC-BY-NC']
unknown_markers = ['UNKNOWN', 'unknown', 'N/A', 'UNLICENSED', 'Custom', '', 'null', 'None', 'NOASSERTION']
is_gpl = $( [[ "$is_project_gpl" == true ]] && echo "True" || echo "False" )

flags = []
try:
    results = json.load(sys.stdin)
    for r in results:
        deps = r.get('dependencies', [])
        manager = r.get('manager', '?')
        for dep in deps:
            name = dep.get('name', '?')
            lic = dep.get('license', 'UNKNOWN')

            # Flag unknown / missing
            if any(m in lic for m in unknown_markers):
                flags.append({
                    'package': name,
                    'manager': manager,
                    'license': lic,
                    'issue': 'unknown_license',
                    'severity': 'warning',
                    'message': f'License unknown or missing for {name}'
                })
                continue

            # Flag copyleft in non-GPL project
            if not is_gpl:
                for cl in copyleft:
                    if cl.upper() in lic.upper():
                        flags.append({
                            'package': name,
                            'manager': manager,
                            'license': lic,
                            'issue': 'copyleft_in_non_gpl',
                            'severity': 'critical',
                            'message': f'Copyleft license ({lic}) in non-GPL project for {name}'
                        })
                        break
except Exception as e:
    flags.append({'error': str(e)})

print(json.dumps(flags))
" 2>/dev/null || echo "[]")

  echo "$flags_json"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local start_time
  start_time=$(timestamp)

  local project_license
  project_license=$(detect_project_license)

  # Run all checkers
  check_npm
  check_yarn
  check_pnpm
  check_pip
  check_cargo
  check_go
  check_gem
  check_composer

  # Flag issues
  local flags_json
  flags_json=$(flag_issues)

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

  local flag_count
  flag_count=$(echo "$flags_json" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d))
except: print(0)
" 2>/dev/null || echo "0")

  # Output standardized JSON
  cat <<ENDJSON
{
  "tool": "ucr-license-check",
  "version": "1.0.0",
  "timestamp": "$start_time",
  "directory": "$(pwd)",
  "project_license": "$(json_escape "$project_license")",
  "managers_detected": $(( ${#RESULTS[@]} + ${#SKIPPED[@]} )),
  "managers_checked": ${#RESULTS[@]},
  "managers_skipped": ${#SKIPPED[@]},
  "total_flags": $flag_count,
  "results": $results_json,
  "flags": $flags_json,
  "skipped": $skipped_json
}
ENDJSON
}

main
