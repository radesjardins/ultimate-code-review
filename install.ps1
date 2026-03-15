# Ultimate Code Review — Windows PowerShell Installer
#
# Installs the UCR skill and supporting files to the correct locations.
#
# Usage:
#   .\install.ps1
#   irm https://raw.githubusercontent.com/[owner]/ultimate-code-review/main/install.ps1 | iex
#
# Locations:
#   ~\.claude\skills\ultimate-code-review\   — Skill definition (SKILL.md)
#   ~\.ai-shared\ucr\                        — Reference docs, scripts, templates, etc.

#Requires -Version 5.1

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$UCR_VERSION = "1.0.0"
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
}

# ---------------------------------------------------------------------------
# Detect home directory
# ---------------------------------------------------------------------------
$HomeDir = $env:USERPROFILE
if (-not $HomeDir) {
    $HomeDir = [System.Environment]::GetFolderPath("UserProfile")
}
if (-not $HomeDir) {
    Write-Error "Could not determine home directory."
    exit 1
}

# ---------------------------------------------------------------------------
# Target directories
# ---------------------------------------------------------------------------
$SkillDir = Join-Path $HomeDir ".claude\skills\ultimate-code-review"
$UcrDir   = Join-Path $HomeDir ".ai-shared\ucr"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-UCR {
    param([string]$Message, [string]$Color = "Green")
    Write-Host "[UCR] " -ForegroundColor $Color -NoNewline
    Write-Host $Message
}

function Write-UCRWarn {
    param([string]$Message)
    Write-UCR $Message -Color Yellow
}

function Write-UCRError {
    param([string]$Message)
    Write-UCR $Message -Color Red
}

function Test-SourceFile {
    param([string]$RelativePath)
    $fullPath = Join-Path $ScriptDir $RelativePath
    if (Test-Path $fullPath) {
        return $true
    }
    Write-UCRWarn "Source file not found: $RelativePath — skipping"
    return $false
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )
    if (Test-Path $Source) {
        $items = Get-ChildItem -Path $Source -Recurse
        foreach ($item in $items) {
            $relativePath = $item.FullName.Substring($Source.Length).TrimStart('\', '/')
            $destPath = Join-Path $Destination $relativePath

            if ($item.PSIsContainer) {
                if (-not (Test-Path $destPath)) {
                    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
                }
            } else {
                $destDir = Split-Path -Parent $destPath
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                # Replace path placeholders in .md and .yml files
                if ($item.Extension -in @('.md', '.yml', '.yaml')) {
                    $content = Get-Content -Path $item.FullName -Raw
                    $content = $content -replace '\{\{HOME\}\}', $HomeDir
                    $content = $content -replace '\{\{UCR_DIR\}\}', $UcrDir
                    $content = $content -replace '~/.ai-shared/ucr', $UcrDir
                    Set-Content -Path $destPath -Value $content -Encoding UTF8
                } else {
                    Copy-Item -Path $item.FullName -Destination $destPath -Force
                }
            }
        }
        return $true
    }
    return $false
}

# ---------------------------------------------------------------------------
# Validate source directory
# ---------------------------------------------------------------------------
if (-not (Test-Path $ScriptDir)) {
    Write-UCRError "Cannot determine script directory. Run from the cloned repo."
    exit 1
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
Write-Host ""
Write-UCR "Installing Ultimate Code Review v$UCR_VERSION"
Write-UCR "Platform: Windows"
Write-UCR "Home: $HomeDir"
Write-Host ""

# Create directories
Write-UCR "Creating directories..."
$dirs = @(
    $SkillDir,
    (Join-Path $UcrDir "references"),
    (Join-Path $UcrDir "workflows"),
    (Join-Path $UcrDir "project-types"),
    (Join-Path $UcrDir "templates"),
    (Join-Path $UcrDir "scripts"),
    (Join-Path $UcrDir ".github\workflows")
)
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Copy SKILL.md with path placeholder replacement
$skillSource = Join-Path $ScriptDir "skill\SKILL.md"
if (Test-Path $skillSource) {
    Write-UCR "Installing SKILL.md..."
    $content = Get-Content -Path $skillSource -Raw
    # Replace path placeholders with actual paths (Windows format)
    $content = $content -replace '\{\{HOME\}\}', $HomeDir
    $content = $content -replace '\{\{UCR_DIR\}\}', $UcrDir
    $content = $content -replace '~/.ai-shared/ucr', $UcrDir
    # Also handle Unix-style home references
    $unixHome = $HomeDir -replace '\\', '/'
    $content = $content -replace '\{\{UNIX_HOME\}\}', $unixHome
    Set-Content -Path (Join-Path $SkillDir "SKILL.md") -Value $content -Encoding UTF8
} else {
    Write-UCRWarn "skill/SKILL.md not found — skipping"
}

# Copy reference docs
$refSource = Join-Path $ScriptDir "references"
if (Copy-DirectoryContents -Source $refSource -Destination (Join-Path $UcrDir "references")) {
    Write-UCR "Copied reference docs."
} else {
    Write-UCRWarn "No references directory found."
}

# Copy workflows
$wfSource = Join-Path $ScriptDir "workflows"
if (Copy-DirectoryContents -Source $wfSource -Destination (Join-Path $UcrDir "workflows")) {
    Write-UCR "Copied workflows."
} else {
    Write-UCRWarn "No workflows directory found."
}

# Copy project-types
$ptSource = Join-Path $ScriptDir "project-types"
if (Copy-DirectoryContents -Source $ptSource -Destination (Join-Path $UcrDir "project-types")) {
    Write-UCR "Copied project-type modules."
} else {
    Write-UCRWarn "No project-types directory found."
}

# Copy templates
$tmplSource = Join-Path $ScriptDir "templates"
if (Copy-DirectoryContents -Source $tmplSource -Destination (Join-Path $UcrDir "templates")) {
    Write-UCR "Copied templates."
} else {
    Write-UCRWarn "No templates directory found."
}

# Copy scripts
$scriptsSource = Join-Path $ScriptDir "scripts"
if (Copy-DirectoryContents -Source $scriptsSource -Destination (Join-Path $UcrDir "scripts")) {
    Write-UCR "Copied scripts."
} else {
    Write-UCRWarn "No scripts directory found."
}

# Copy GitHub Action workflow
$ghSource = Join-Path $ScriptDir ".github\workflows"
if (Copy-DirectoryContents -Source $ghSource -Destination (Join-Path $UcrDir ".github\workflows")) {
    Write-UCR "Copied GitHub Action workflow."
} else {
    Write-UCRWarn "No .github/workflows directory found."
}

# ---------------------------------------------------------------------------
# Verify installation
# ---------------------------------------------------------------------------
Write-Host ""
Write-UCR "Verifying installation..."

$errors = 0

$skillMd = Join-Path $SkillDir "SKILL.md"
if (Test-Path $skillMd) {
    Write-UCR "  SKILL.md ............. OK"
} else {
    Write-UCRWarn "  SKILL.md ............. MISSING"
    $errors++
}

$subdirs = @("references", "workflows", "project-types", "templates", "scripts")
foreach ($subdir in $subdirs) {
    $subPath = Join-Path $UcrDir $subdir
    if (Test-Path $subPath) {
        $count = (Get-ChildItem -Path $subPath -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        if ($count -gt 0) {
            $padding = "." * [Math]::Max(1, 20 - $subdir.Length)
            Write-UCR "  $subdir $padding OK ($count files)"
        } else {
            $padding = "." * [Math]::Max(1, 20 - $subdir.Length)
            Write-UCRWarn "  $subdir $padding EMPTY (source may not have been populated yet)"
        }
    }
}

# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------
Write-Host ""
if ($errors -eq 0) {
    Write-Host "Ultimate Code Review v$UCR_VERSION installed successfully!" -ForegroundColor Green -NoNewline
    Write-Host ""
} else {
    Write-UCRWarn "Installation completed with $errors warning(s)."
}

Write-Host ""
Write-Host "Installed to:"
Write-Host "  Skill:      $SkillDir\SKILL.md"
Write-Host "  Resources:  $UcrDir\"
Write-Host ""
Write-Host "Usage:"
Write-Host "  In Claude Code, the skill is automatically available."
Write-Host "  Run a review with:"
Write-Host ""
Write-Host "    /review                     # Review current diff"
Write-Host "    /review --scope repo        # Review entire repo"
Write-Host "    /review --strictness public # Strict public-release review"
Write-Host ""
Write-Host "  To add the GitHub Action to a project:"
Write-Host "    Copy-Item `"$UcrDir\.github\workflows\ultimate-code-review.yml`" .github\workflows\"
Write-Host ""
Write-Host "  To run audit scripts (Git Bash / WSL):"
Write-Host "    bash $UcrDir/scripts/dep-audit.sh ."
Write-Host "    bash $UcrDir/scripts/license-check.sh ."
Write-Host "    bash $UcrDir/scripts/secrets-scan.sh ."
Write-Host ""
