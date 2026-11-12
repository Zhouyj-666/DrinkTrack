# push-to-github.ps1
#
# One-shot helper: initialize a git repo at E:\DrinkTrack and push it to GitHub.
# Run this ONCE after you have created an EMPTY repository on github.com
# (do NOT tick "Add a README file" when creating it).
#
# Usage:
#   & "E:\DrinkTrack\_build-tools\push-to-github.ps1" -GitHubUser yourname -RepoName DrinkTrack
#
# Note: this script is written in English on purpose. Windows PowerShell 5.1 parses
# .ps1 files using the system ANSI codepage unless they carry a UTF-8 BOM, and Chinese
# characters in a BOM-less script corrupt the parser (we hit exactly this bug earlier
# with gen-pbxproj.ps1).

param(
    [Parameter(Mandatory = $true)][string]$GitHubUser,
    [string]$RepoName = "DrinkTrack",
    [string]$RepoPath = "E:\DrinkTrack",
    [string]$UserEmail = "",
    [string]$UserName  = ""
)

$ErrorActionPreference = "Stop"

# git is installed under Program Files but a freshly spawned shell may not have it on PATH yet.
$gitExe = "git"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    $candidate = "C:\Program Files\Git\cmd\git.exe"
    if (Test-Path $candidate) {
        $gitExe = $candidate
        Write-Host "git not on PATH, using $candidate"
    } else {
        throw "git not found. Install it first, then open a NEW terminal."
    }
}

Set-Location $RepoPath

if (-not (Test-Path (Join-Path $RepoPath ".git"))) {
    & $gitExe init
    & $gitExe branch -M main
} else {
    Write-Host "Repo already initialized, skipping git init"
}

# Identity is required before the first commit. Set it locally (this repo only)
# so we do not touch any global config you may already have.
if ($UserEmail) { & $gitExe config user.email $UserEmail }
if ($UserName)  { & $gitExe config user.name  $UserName }

$hasEmail = (& $gitExe config user.email)
if (-not $hasEmail) {
    throw "git user.email is not set. Re-run with -UserEmail you@example.com -UserName 'Your Name'"
}

& $gitExe add -A

Write-Host ""
Write-Host "=== Files staged for the first commit ==="
& $gitExe status --short
Write-Host "========================================"
Write-Host ""

& $gitExe commit -m "DrinkTrack round 1: P0 subset + GitHub Actions build"

$remoteUrl = "https://github.com/$GitHubUser/$RepoName.git"
$existing = & $gitExe remote
if ($existing -contains "origin") {
    & $gitExe remote set-url origin $remoteUrl
} else {
    & $gitExe remote add origin $remoteUrl
}

Write-Host "Pushing to $remoteUrl ..."
Write-Host "A browser/credential window may pop up asking you to sign in to GitHub."
& $gitExe push -u origin main

Write-Host ""
Write-Host "Done. Now open https://github.com/$GitHubUser/$RepoName/actions to watch the build."
