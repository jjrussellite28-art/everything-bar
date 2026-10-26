# One-step update: get the latest code, build it, make the installer and start it.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host '1/4 Getting the latest code...'
git pull

if (-not (Test-Path 'windows')) {
  Write-Host 'Creating Windows project files (first time only)...'
  flutter create --platforms=windows .
  & .\brand_windows.ps1
}

Write-Host '2/4 Building (a few minutes)...'
flutter build windows --release

Write-Host '3/4 Making the installer...'
$candidates = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 was not found. Install it from https://jrsoftware.org/isdl.php and run this again.' }
& $iscc 'installer\HomeShell.iss'

Write-Host '4/4 Starting the installer (it will close the old bar for you)...'
Start-Process 'installer\output\EverythingBar-Setup.exe'
