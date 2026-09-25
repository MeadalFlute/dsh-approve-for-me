# dsh-client-ui-approval host-bundle patch (apply/verify/restore).
#
# WHY: the approve-for-me plugin (this repo) hands AI-denied approvals to the
# human with a `req.reviewContext` rationale. The stock dsh browser plugin
# `@deepseek-ai/dsh-client-ui-approval` renders only the request reason, so we
# patch its bundle to show the AI rationale as a second panel line.
#
# The stock bundle lives under the dsh install:
#   <dsh>/versions/<version>/node_modules/.pnpm/@deepseek-ai+dsh-client-ui-
#     <hash>/node_modules/@deepseek-ai/dsh-client-ui-approval/lib/client.js
# dsh upgrades overwrite it -> re-run this script after every dsh update.
#
# This script performs exact-string replacements (not diff hunks), so it is
# tolerant of unrelated upstream refactors (e.g. the `kind` field move) and of
# CRLF/LF differences. It is idempotent: running it twice is a no-op.
#
# Usage (PowerShell):
#   powershell -ExecutionPolicy Bypass -File apply-ui-approval.ps1 -DshVersion 0.1.6-alpha.2
#   powershell -ExecutionPolicy Bypass -File apply-ui-approval.ps1 -DshVersion 0.1.6-alpha.2 -Revert
#
# An ASCII-only JS payload is embedded below; strings that must stay ASCII
# avoid any PowerShell file-encoding surprises.

param(
  [string]$DshVersion = "0.1.6-alpha.2",
  [switch]$Revert,
  [string]$LauncherRoot = "$env:APPDATA\in.dsh-plug.dsh-launcher"
)

$ErrorActionPreference = "Stop"

# Locate the stock bundle inside the pnpm layout (hash dir varies).
$base = Join-Path $LauncherRoot "versions\$DshVersion\node_modules\.pnpm"
if (-not (Test-Path $base)) {
  Write-Error "dsh versions dir not found: $base"
}
$target = Get-ChildItem -Path $base -Directory -Filter "@deepseek-ai+dsh-client-ui-*" |
  ForEach-Object {
    Join-Path $_.FullName "node_modules\@deepseek-ai\dsh-client-ui-approval\lib\client.js"
  } | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $target) {
  Write-Error "dsh-client-ui-approval bundle not found under $base"
}
Write-Host "target: $target"

$raw = [System.IO.File]::ReadAllText($target, [System.Text.Encoding]::UTF8)
$original = $raw

# --- 1. CSS: headline keeps soft-wrapping; add .mna1RW_review block. ---
$oldCss = '.mna1RW_headline{color:var(--dsw-alias-label-primary);font-size:15px;font-weight:500;line-height:24px}'
$newCssHeadline = '.mna1RW_headline{color:var(--dsw-alias-label-primary);font-size:15px;font-weight:500;line-height:24px;white-space:pre-wrap;word-break:break-word}'
$newCssReview = '.mna1RW_review{color:var(--dsw-alias-state-error-primary);background:var(--dsw-alias-state-error-tertiary);border-radius:8px;margin-top:2px;padding:8px 10px;font-size:13px;line-height:20px;white-space:pre-wrap;word-break:break-word}'
$markerCssReview = '.mna1RW_review{color:var('
$markerHeadline = '.mna1RW_headline{color:var(--dsw-alias-label-primary);font-size:15px;font-weight:500;line-height:24px;white-space:pre-wrap'

# --- 2. css-module key map: add "review": "mna1RW_review". ---
$oldKey = '"headline": "mna1RW_headline",' + "`n" + "`t`t`t`t" + '"reject": "mna1RW_reject",'
$newKey = '"headline": "mna1RW_headline",' + "`n" + "`t`t`t`t" + '"reject": "mna1RW_reject",' + "`n" + "`t`t`t`t" + '"review": "mna1RW_review",'
$markerKey = '"review": "mna1RW_review"'

# --- 3. ApprovalFlow body: render reviewContext under the headline. ---
$oldRender = "children: pending.reason ?? t(""escalation"", { toolName: pending.toolName })`n`t`t`t`t`t`t`t`t`t`t}), detail !== null &&"
$newRender = "children: pending.reason ?? t(""escalation"", { toolName: pending.toolName })`n`t`t`t`t`t`t`t`t`t`t}), pending.reviewContext !== null && pending.reviewContext !== void 0 && (0, react_jsx_runtime.jsx)(""div"", {`n`t`t`t`t`t`t`t`t`t`t`t`tclassName: ApprovalPanel_module_css_default.review,`n`t`t`t`t`t`t`t`t`t`t`t`tchildren: pending.reviewContext`n`t`t`t`t`t`t`t`t`t`t}), detail !== null &&"
$markerRender = 'pending.reviewContext !== null && pending.reviewContext !== void 0'

# --- 4. PendingApproval: carry reviewContext through. ---
$oldField = "this.reason = request.reason;"
$newField = "this.reason = request.reason;`n`t`t`t`t`t`t/** AI reviewer rationale shown as a second line, when present. */`n`t`t`t`t`t`tthis.reviewContext = request.reviewContext ?? null;"
$markerField = 'this.reviewContext = request.reviewContext ?? null'

# --- 5. answerApproval passthrough: forward reviewContext to PendingApproval. ---
$oldPass = "...request.reason === void 0 ? {} : { reason: request.reason },"
$newPass = "...request.reason === void 0 ? {} : { reason: request.reason },`n`t`t`t`t`t`t...request.reviewContext === void 0 ? {} : { reviewContext: request.reviewContext },"
$markerPass = 'reviewContext: request.reviewContext'

$markers = @($markerCssReview, $markerHeadline, $markerKey, $markerRender, $markerField, $markerPass)
$alreadyApplied = $markers | Where-Object { $raw.Contains($_) } | Measure-Object | Select-Object -ExpandProperty Count -ErrorAction SilentlyContinue

if ($Revert) {
  # Restore = inverse of the forward replacements.
  if ($raw.Contains($markerCssReview)) { $raw = $raw.Replace($newCssHeadline + $newCssReview + '.', $oldCss + '.') }
  if ($raw.Contains($markerKey)) { $raw = $raw.Replace($newKey, $oldKey) }
  if ($raw.Contains($markerRender)) {
    $raw = $raw.Replace($newRender.Replace("""", '"').Replace("`n", [Environment]::NewLine), $oldRender.Replace("""", '"').Replace("`n", [Environment]::NewLine))
  }
  if ($raw.Contains($markerField)) { $raw = $raw.Replace($newField, $oldField) }
  if ($raw.Contains($markerPass)) { $raw = $raw.Replace($newPass, $oldPass) }
  [System.IO.File]::WriteAllText($target, $raw, [System.Text.Encoding]::UTF8)
  Write-Host "reverted to stock bundle (markers left: $($markers | Where-Object { $raw.Contains($_) } | Measure-Object | Select-Object -ExpandProperty Count -ErrorAction SilentlyContinue))"
  exit 0
}

if ($alreadyApplied -ge 6) {
  Write-Host "already applied (nothing to do)"
  exit 0
}

$failures = @()
foreach ($s in @(@('headline-css', $oldCss, $newCssHeadline), @('review-css-insert', '.mna1RW_command{color:var(--dsw-alias-label-tertiary)', ($newCssReview + '.mna1RW_command{color:var(--dsw-alias-label-tertiary)')), @('css-key', $oldKey, $newKey), @('render-block', $oldRender, $newRender), @('field', $oldField, $newField), @('pass-through', $oldPass, $newPass))) {
  $name = $s[0]; $o = $s[1]; $n = $s[2]
  # The JSX block strings contain tabs/CRLF that may vary; try several normalized forms.
  $ways = @(
    @($o, $n),
    @($o.Replace("`n", [Environment]::NewLine).Replace("`t", "`t"), $n.Replace("`n", [Environment]::NewLine).Replace("`t", "`t"))
  )
  $done = $false
  foreach ($w in $ways) {
    if ($raw.Contains($w[0])) { $raw = $raw.Replace($w[0], $w[1]); $done = $true; break }
  }
  if (-not $done) { $failures += $name }
}
if ($failures.Count -gt 0) {
  Write-Host ("application incomplete; could not match: " + ($failures -join ', '))
  Write-Error "patch FAILED; leaving file untouched."
}
[System.IO.File]::WriteAllText($target, $raw, [System.Text.Encoding]::UTF8)
Write-Host "applied. verify with: node --check `"$target`""
exit 0