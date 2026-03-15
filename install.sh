#!/usr/bin/env bash
# Ultimate Code Review — Unix/macOS/Git Bash Installer
#
# Installs the UCR skill and supporting files to the correct locations.
#
# Usage:
#   ./install.sh
#   curl -sSL https://raw.githubusercontent.com/[owner]/ultimate-code-review/main/install.sh | bash
#
# Locations:
#   ~/.claude/skills/ultimate-code-review/   — Skill definition (SKILL.md)
#   ~/.ai-shared/ucr/                        — Reference docs, scripts, templates, etc.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UCR_VERSION="1.0.0"

# ---------------------------------------------------------------------------
# Detect home directory
# ---------------------------------------------------------------------------
detect_home() {
  if [[ -n "${HOME:-}" ]]; then
    echo "$HOME"
  elif [[ -n "${USERPROFILE:-}" ]]; then
    # Git Bash on Windows
    echo "$USERPROFILE"
  elif [[ -d "/c/Users/$(whoami)" ]]; then
    echo "/c/Users/$(whoami)"
  else
    echo "$HOME"
  fi
}

HOME_DIR="$(detect_home)"

# Detect platform
detect_platform() {
  local uname_out
  uname_out="$(uname -s 2>/dev/null || echo "Unknown")"
  case "$uname_out" in
    Linux*)   echo "linux" ;;
    Darwin*)  echo "macos" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows-gitbash" ;;
    *)        echo "unknown" ;;
  esac
}

PLATFORM="$(detect_platform)"

# ---------------------------------------------------------------------------
# Target directories
# ---------------------------------------------------------------------------
SKILL_DIR="${HOME_DIR}/.claude/skills/ultimate-code-review"
UCR_DIR="${HOME_DIR}/.ai-shared/ucr"

# ---------------------------------------------------------------------------
# Colors (if terminal supports them)
# ---------------------------------------------------------------------------
if [[ -t 1 ]] && command -v tput &>/dev/null; then
  GREEN=$(tput setaf 2 2>/dev/null || echo "")
  YELLOW=$(tput setaf 3 2>/dev/null || echo "")
  RED=$(tput setaf 1 2>/dev/null || echo "")
  BOLD=$(tput bold 2>/dev/null || echo "")
  RESET=$(tput sgr0 2>/dev/null || echo "")
else
  GREEN="" YELLOW="" RED="" BOLD="" RESET=""
fi

info()  { echo "${GREEN}[UCR]${RESET} $*"; }
warn()  { echo "${YELLOW}[UCR]${RESET} $*"; }
error() { echo "${RED}[UCR]${RESET} $*" >&2; }
bold()  { echo "${BOLD}$*${RESET}"; }

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ ! -d "$SCRIPT_DIR" ]]; then
  error "Cannot determine script directory. Run from the cloned repo."
  exit 1
fi

# Check that key source files exist
check_source() {
  local file="$1"
  if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
    warn "Source file not found: ${file} — skipping"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
info "Installing Ultimate Code Review v${UCR_VERSION}"
info "Platform: ${PLATFORM}"
info "Home: ${HOME_DIR}"
echo ""

# Create directories
info "Creating directories..."
mkdir -p "${SKILL_DIR}"
mkdir -p "${UCR_DIR}/references"
mkdir -p "${UCR_DIR}/workflows"
mkdir -p "${UCR_DIR}/project-types"
mkdir -p "${UCR_DIR}/templates"
mkdir -p "${UCR_DIR}/scripts"

# Copy SKILL.md to skill directory, replacing path placeholders
if check_source "skill/SKILL.md"; then
  info "Installing SKILL.md..."
  sed "s|{{HOME}}|${HOME_DIR}|g; s|{{UCR_DIR}}|${UCR_DIR}|g; s|\~/.ai-shared/ucr|${UCR_DIR}|g" \
    "${SCRIPT_DIR}/skill/SKILL.md" > "${SKILL_DIR}/SKILL.md"
fi

# Helper: copy files with path placeholder replacement
copy_with_paths() {
  local src_dir="$1"
  local dest_dir="$2"
  local label="$3"
  if [[ -d "${SCRIPT_DIR}/${src_dir}" ]]; then
    info "Copying ${label}..."
    for f in "${SCRIPT_DIR}/${src_dir}/"*; do
      [[ -f "$f" ]] || continue
      local basename
      basename="$(basename "$f")"
      if [[ "$basename" == *.md || "$basename" == *.yml || "$basename" == *.yaml ]]; then
        sed "s|{{HOME}}|${HOME_DIR}|g; s|{{UCR_DIR}}|${UCR_DIR}|g" \
          "$f" > "${dest_dir}/${basename}"
      else
        cp "$f" "${dest_dir}/${basename}"
      fi
    done
  fi
}

copy_with_paths "references" "${UCR_DIR}/references" "reference docs"
copy_with_paths "workflows" "${UCR_DIR}/workflows" "workflows"
copy_with_paths "project-types" "${UCR_DIR}/project-types" "project-type modules"
copy_with_paths "templates" "${UCR_DIR}/templates" "templates"

# Copy scripts
if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
  info "Copying scripts..."
  cp -r "${SCRIPT_DIR}/scripts/"* "${UCR_DIR}/scripts/" 2>/dev/null || true

  # Make scripts executable
  chmod +x "${UCR_DIR}/scripts/"*.sh 2>/dev/null || true
fi

# Copy GitHub Action workflow
if [[ -d "${SCRIPT_DIR}/.github/workflows" ]]; then
  info "Copying GitHub Action workflow..."
  mkdir -p "${UCR_DIR}/.github/workflows"
  cp -r "${SCRIPT_DIR}/.github/workflows/"* "${UCR_DIR}/.github/workflows/" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
echo ""
info "Verifying installation..."

ERRORS=0

if [[ -f "${SKILL_DIR}/SKILL.md" ]]; then
  info "  SKILL.md ............. OK"
else
  warn "  SKILL.md ............. MISSING"
  ERRORS=$((ERRORS + 1))
fi

for subdir in references workflows project-types templates scripts; do
  count=$(find "${UCR_DIR}/${subdir}" -type f 2>/dev/null | wc -l)
  if [[ "$count" -gt 0 ]]; then
    info "  ${subdir} ............ OK (${count} files)"
  else
    warn "  ${subdir} ............ EMPTY (source may not have been populated yet)"
  fi
done

# Check script executability
if [[ -f "${UCR_DIR}/scripts/dep-audit.sh" ]]; then
  if [[ -x "${UCR_DIR}/scripts/dep-audit.sh" ]]; then
    info "  scripts executable ... OK"
  else
    warn "  scripts executable ... FAILED (chmod may not be supported on this filesystem)"
  fi
fi

# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------
echo ""
if [[ "$ERRORS" -eq 0 ]]; then
  bold "Ultimate Code Review v${UCR_VERSION} installed successfully!"
else
  warn "Installation completed with ${ERRORS} warning(s)."
fi

echo ""
echo "Installed to:"
echo "  Skill:      ${SKILL_DIR}/SKILL.md"
echo "  Resources:  ${UCR_DIR}/"
echo ""
echo "Usage:"
echo "  In Claude Code, the skill is automatically available."
echo "  Run a review with:"
echo ""
echo "    /review                    # Review current diff"
echo "    /review --scope repo       # Review entire repo"
echo "    /review --strictness public # Strict public-release review"
echo ""
echo "  To add the GitHub Action to a project:"
echo "    cp ${UCR_DIR}/.github/workflows/ultimate-code-review.yml .github/workflows/"
echo ""
echo "  To run audit scripts directly:"
echo "    ${UCR_DIR}/scripts/dep-audit.sh ."
echo "    ${UCR_DIR}/scripts/license-check.sh ."
echo "    ${UCR_DIR}/scripts/secrets-scan.sh ."
echo ""
