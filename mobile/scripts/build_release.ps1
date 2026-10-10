# Builds the Play Store app bundle: minified (R8), Dart code obfuscated,
# debug symbols kept separately for reading crash stack traces.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
if (-not (Test-Path 'android\key.properties')) { throw 'Run scripts\create_upload_keystore.ps1 first.' }

flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze reported problems.' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

Write-Host ''
Write-Host 'Upload: build\app\outputs\bundle\release\app-release.aab'
Write-Host 'Keep (do not upload publicly): build\symbols  - needed to read obfuscated stack traces.'
