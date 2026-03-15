#!/usr/bin/env bash
# UCR Secrets Detection Wrapper
# Uses gitleaks if available, otherwise falls back to pattern-based scanning.
#
# SECURITY: This script NEVER outputs actual secret values.
#
# Usage:
#   ./secrets-scan.sh [--local-only] [directory]
#
# Outputs standardized JSON to stdout.
# Exit code 0 = success (even if secrets found; check JSON for results).
# Exit code 1 = script error.

set -euo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
LOCAL_ONLY=false
TARGET_DIR="."

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
      echo "Usage: secrets-scan.sh [--local-only] [directory]"
      echo "  --local-only   Skip network-dependent checks"
      echo "  directory      Target directory to scan (default: current directory)"
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

# Redact a string to show only type/length, NEVER the value
redact() {
  local val="$1"
  local len=${#val}
  if [[ $len -le 4 ]]; then
    echo "[REDACTED ${len} chars]"
  else
    echo "[REDACTED ${len} chars]"
  fi
}

# ---------------------------------------------------------------------------
# File filtering — skip binary, vendored, and generated files
# ---------------------------------------------------------------------------
SKIP_DIRS=(
  ".git"
  "node_modules"
  "vendor"
  ".vendor"
  "dist"
  "build"
  "__pycache__"
  ".tox"
  ".mypy_cache"
  "target"
  ".next"
  ".nuxt"
  "coverage"
  ".nyc_output"
  ".cache"
  "venv"
  ".venv"
  "env"
)

SKIP_EXTENSIONS=(
  "png" "jpg" "jpeg" "gif" "ico" "svg" "bmp" "webp"
  "woff" "woff2" "ttf" "eot" "otf"
  "zip" "tar" "gz" "bz2" "xz" "7z" "rar"
  "pdf" "doc" "docx" "xls" "xlsx"
  "exe" "dll" "so" "dylib" "o" "a"
  "pyc" "pyo" "class" "jar" "war"
  "lock"
  "min.js" "min.css"
  "map"
)

build_find_excludes() {
  local excludes=""
  for d in "${SKIP_DIRS[@]}"; do
    excludes+=" -not -path '*/${d}/*'"
  done
  echo "$excludes"
}

should_skip_file() {
  local file="$1"
  local basename
  basename=$(basename "$file")
  local ext="${basename##*.}"
  ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')

  for se in "${SKIP_EXTENSIONS[@]}"; do
    if [[ "$ext" == "$se" ]]; then
      return 0
    fi
  done

  # Skip files larger than 1MB (likely binary/generated)
  local size
  size=$(wc -c < "$file" 2>/dev/null || echo 0)
  if [[ "$size" -gt 1048576 ]]; then
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Pattern definitions for fallback scanning
# ---------------------------------------------------------------------------
# Each pattern: NAME|REGEX|DESCRIPTION
# Patterns are designed to match the key/assignment, not just any string.
PATTERNS=(
  # AWS
  "aws_access_key|AKIA[0-9A-Z]{16}|AWS Access Key ID"
  "aws_secret_key|(aws_secret_access_key|AWS_SECRET_ACCESS_KEY)\s*[=:]\s*[A-Za-z0-9/+=]{40}|AWS Secret Access Key"

  # Generic API keys (in assignments/configs)
  "api_key_assignment|(api[_-]?key|apikey|api[_-]?secret|api[_-]?token)\s*[=:]\s*['\"]?[A-Za-z0-9_\-]{20,}|API Key assignment"
  "bearer_token|[Bb]earer\s+[A-Za-z0-9_\-\.]{20,}|Bearer token"

  # JWT / session secrets
  "jwt_secret|(jwt[_-]?secret|JWT_SECRET|session[_-]?secret|SESSION_SECRET)\s*[=:]\s*['\"]?[^\s'\"]{8,}|JWT or session secret"

  # Private keys
  "private_key|-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----|Private key header"
  "private_key_assignment|(private[_-]?key|PRIVATE_KEY)\s*[=:]\s*['\"]?[^\s'\"]{10,}|Private key assignment"

  # Database URLs with credentials
  "database_url|(mysql|postgres|postgresql|mongodb|redis|amqp|mssql):\/\/[^:]+:[^@]+@|Database URL with password"

  # Common service tokens
  "github_token|(ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|ghu_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9]{36}|ghr_[A-Za-z0-9]{36})|GitHub token"
  "gitlab_token|glpat-[A-Za-z0-9\-]{20,}|GitLab personal access token"
  "slack_token|xox[bpors]-[A-Za-z0-9\-]{10,}|Slack token"
  "slack_webhook|hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+|Slack webhook URL"
  "stripe_key|(sk_live|pk_live|sk_test|pk_test)_[A-Za-z0-9]{20,}|Stripe API key"
  "twilio_key|SK[0-9a-fA-F]{32}|Twilio API key"
  "sendgrid_key|SG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43}|SendGrid API key"
  "mailgun_key|key-[A-Za-z0-9]{32}|Mailgun API key"
  "heroku_key|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|Heroku-style API key (UUID)"

  # Google
  "google_api_key|AIza[A-Za-z0-9_\-]{35}|Google API key"
  "google_oauth|(client_secret|client_id)\s*[=:]\s*['\"]?[A-Za-z0-9_\-\.]{20,}|Google OAuth credential"

  # Generic high-entropy (password/secret assignments only)
  "password_assignment|(password|passwd|pwd|secret|token|credential)\s*[=:]\s*['\"]?[^\s'\"]{8,}|Password or secret assignment"

  # .env file patterns
  "env_secret|^[A-Z_]+_(KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|AUTH)\s*=\s*[^\s]{8,}|Environment variable secret"
)

# ---------------------------------------------------------------------------
# Gitleaks-based scanning
# ---------------------------------------------------------------------------
scan_gitleaks() {
  local raw
  # --no-git flag scans files without requiring a git repo
  raw=$(gitleaks detect --source="." --no-git --report-format=json --report-path=/dev/stdout 2>/dev/null) || true

  if [[ -z "$raw" ]]; then
    echo "[]"
    return 0
  fi

  # Parse gitleaks JSON and redact secret values
  echo "$raw" | python3 -c "
import sys, json

try:
    findings = json.load(sys.stdin)
    if not isinstance(findings, list):
        findings = []
except:
    findings = []

sanitized = []
for f in findings:
    sanitized.append({
        'file': f.get('File', f.get('file', '?')),
        'line': f.get('StartLine', f.get('line', 0)),
        'type': f.get('RuleID', f.get('rule', 'unknown')),
        'description': f.get('Description', f.get('description', '')),
        'match_length': len(f.get('Secret', f.get('match', ''))),
        'commit': f.get('Commit', ''),
        'entropy': f.get('Entropy', 0),
        # NEVER include the actual secret value
    })

print(json.dumps(sanitized))
" 2>/dev/null || echo "[]"
}

# ---------------------------------------------------------------------------
# Pattern-based fallback scanning
# ---------------------------------------------------------------------------
scan_patterns() {
  local findings="[]"

  # Build file list (respecting exclusions)
  local filelist
  filelist=$(mktemp)
  trap "rm -f '$filelist'" EXIT

  # Use find with exclusions
  local find_cmd="find . -type f"
  for d in "${SKIP_DIRS[@]}"; do
    find_cmd+=" -not -path './${d}/*'"
  done

  eval "$find_cmd" 2>/dev/null | while read -r file; do
    # Normalize path
    file="${file#./}"
    echo "$file"
  done > "$filelist"

  # Scan with each pattern using python for reliable regex + JSON output
  python3 -c "
import re, json, os, sys, math

patterns = []
pattern_defs = '''$(printf '%s\n' "${PATTERNS[@]}")'''

for line in pattern_defs.strip().split('\n'):
    line = line.strip()
    if not line:
        continue
    parts = line.split('|', 2)
    if len(parts) == 3:
        patterns.append({'name': parts[0], 'regex': parts[1], 'description': parts[2]})

# Read file list
with open('$filelist') as f:
    files = [line.strip() for line in f if line.strip()]

findings = []
seen = set()  # Deduplicate by (file, line, type)

for filepath in files:
    # Skip binary-looking extensions
    ext = os.path.splitext(filepath)[1].lower()
    skip_exts = {'.png','.jpg','.jpeg','.gif','.ico','.svg','.bmp','.webp',
                 '.woff','.woff2','.ttf','.eot','.otf','.zip','.tar','.gz',
                 '.bz2','.xz','.7z','.rar','.pdf','.doc','.docx','.xls',
                 '.xlsx','.exe','.dll','.so','.dylib','.o','.a','.pyc',
                 '.pyo','.class','.jar','.war','.lock','.map'}
    if ext in skip_exts:
        continue

    # Skip known false-positive filenames
    basename = os.path.basename(filepath)
    if basename in {'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'Cargo.lock',
                    'go.sum', 'Gemfile.lock', 'composer.lock', 'poetry.lock'}:
        continue

    # Skip files > 1MB
    try:
        if os.path.getsize(filepath) > 1048576:
            continue
    except:
        continue

    try:
        with open(filepath, 'r', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                for pat in patterns:
                    try:
                        match = re.search(pat['regex'], line)
                        if match:
                            key = (filepath, line_num, pat['name'])
                            if key in seen:
                                continue
                            seen.add(key)

                            matched_text = match.group(0)

                            # Compute Shannon entropy of the matched text
                            entropy = 0.0
                            if len(matched_text) > 0:
                                freq = {}
                                for c in matched_text:
                                    freq[c] = freq.get(c, 0) + 1
                                for count in freq.values():
                                    p = count / len(matched_text)
                                    if p > 0:
                                        entropy -= p * math.log2(p)

                            findings.append({
                                'file': filepath,
                                'line': line_num,
                                'type': pat['name'],
                                'description': pat['description'],
                                'match_length': len(matched_text),
                                'entropy': round(entropy, 2),
                                # NEVER include the actual matched value
                            })
                    except re.error:
                        pass
    except (IOError, OSError):
        pass

print(json.dumps(findings))
" 2>/dev/null || echo "[]"
}

# ---------------------------------------------------------------------------
# High-entropy string detection (standalone, generic)
# ---------------------------------------------------------------------------
scan_high_entropy() {
  python3 -c "
import os, json, math, re, sys

# Only scan specific file types likely to contain secrets
target_exts = {'.env', '.yml', '.yaml', '.json', '.toml', '.ini', '.cfg',
               '.conf', '.config', '.properties', '.sh', '.bash', '.zsh',
               '.ps1', '.py', '.js', '.ts', '.rb', '.go', '.rs', '.java',
               '.cs', '.php', '.tf', '.hcl'}

skip_dirs = {'.git', 'node_modules', 'vendor', 'dist', 'build', '__pycache__',
             'target', '.next', '.nuxt', 'coverage', 'venv', '.venv', 'env',
             '.tox', '.mypy_cache', '.cache', '.nyc_output'}

# Patterns for lines that look like assignments
assignment_re = re.compile(r'[A-Z_]{2,}\s*[=:]\s*[\"'\'']*([A-Za-z0-9+/=_\-]{20,})[\"'\'']*')

def shannon_entropy(s):
    if not s: return 0
    freq = {}
    for c in s:
        freq[c] = freq.get(c, 0) + 1
    ent = 0.0
    for count in freq.values():
        p = count / len(s)
        if p > 0:
            ent -= p * math.log2(p)
    return ent

findings = []
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in skip_dirs]
    for fname in files:
        ext = os.path.splitext(fname)[1].lower()
        # Also check dotfiles like .env
        if ext not in target_exts and not fname.startswith('.env'):
            continue

        fpath = os.path.join(root, fname)
        if fpath.startswith('./'):
            fpath = fpath[2:]

        try:
            if os.path.getsize(fpath) > 1048576:
                continue
        except:
            continue

        try:
            with open(fpath, 'r', errors='ignore') as f:
                for line_num, line in enumerate(f, 1):
                    m = assignment_re.search(line)
                    if m:
                        val = m.group(1)
                        ent = shannon_entropy(val)
                        # High entropy threshold: 4.5 bits for strings >= 20 chars
                        if ent >= 4.5 and len(val) >= 20:
                            findings.append({
                                'file': fpath,
                                'line': line_num,
                                'type': 'high_entropy_string',
                                'description': 'High-entropy string in assignment (possible secret)',
                                'match_length': len(val),
                                'entropy': round(ent, 2),
                            })
        except (IOError, OSError):
            pass

print(json.dumps(findings))
" 2>/dev/null || echo "[]"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  local start_time
  start_time=$(timestamp)

  local tool_used=""
  local findings="[]"
  local entropy_findings="[]"

  if command_exists gitleaks; then
    tool_used="gitleaks"
    findings=$(scan_gitleaks)
  else
    tool_used="pattern-scan"
    findings=$(scan_patterns)
  fi

  # Always run high-entropy scan as a supplement
  entropy_findings=$(scan_high_entropy)

  local end_time
  end_time=$(timestamp)

  # Count findings
  local finding_count
  finding_count=$(echo "$findings" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d) if isinstance(d, list) else 0)
except: print(0)
" 2>/dev/null || echo "0")

  local entropy_count
  entropy_count=$(echo "$entropy_findings" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d) if isinstance(d, list) else 0)
except: print(0)
" 2>/dev/null || echo "0")

  local total_count=$(( finding_count + entropy_count ))

  local gitleaks_available=false
  command_exists gitleaks && gitleaks_available=true

  # Output standardized JSON
  cat <<ENDJSON
{
  "tool": "ucr-secrets-scan",
  "version": "1.0.0",
  "timestamp": "$start_time",
  "directory": "$(pwd)",
  "local_only": $LOCAL_ONLY,
  "scanner": "$tool_used",
  "gitleaks_available": $gitleaks_available,
  "total_findings": $total_count,
  "pattern_findings": $finding_count,
  "entropy_findings": $entropy_count,
  "findings": $findings,
  "high_entropy_findings": $entropy_findings,
  "note": "Secret values are NEVER included in output. Only file, line, type, and length are reported."
}
ENDJSON
}

main
