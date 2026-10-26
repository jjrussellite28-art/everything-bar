# Run once from this folder after `flutter create --platforms=windows .`
# Makes Windows show "Everything Bar" (Task Manager, file properties, window title).
$ErrorActionPreference = 'Stop'
$rc = 'windows\runner\Runner.rc'
(Get-Content $rc) `
  -replace '("FileDescription",\s*)"[^"]*"', '$1"Everything Bar"' `
  -replace '("ProductName",\s*)"[^"]*"', '$1"Everything Bar"' `
  -replace '("InternalName",\s*)"[^"]*"', '$1"Everything Bar"' |
  Set-Content $rc
$cpp = 'windows\runner\main.cpp'
(Get-Content $cpp) -replace 'L"home_shell"', 'L"Everything Bar"' | Set-Content $cpp
Write-Host 'Done. Now run: flutter build windows --release'
