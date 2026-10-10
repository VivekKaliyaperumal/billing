# Creates the Play Store upload keystore and android/key.properties.
# Run once:  powershell -ExecutionPolicy Bypass -File scripts\create_upload_keystore.ps1
#
# Passwords are typed by you and never stored in the repo. Both output files
# are git-ignored. BACK UP the .jks file and passwords (e.g. a password
# manager): losing them means asking Google to reset the upload key.

$ErrorActionPreference = 'Stop'
$keyDir = Join-Path $env:USERPROFILE '.thyantra-keys'
$keystore = Join-Path $keyDir 'thyantra-billing-upload.jks'
$props = Join-Path $PSScriptRoot '..\android\key.properties'

if (Test-Path $keystore) { throw "Keystore already exists at $keystore. Not overwriting it." }

$keytool = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin\keytool.exe' } else { 'keytool' }
if (-not (Get-Command $keytool -ErrorAction SilentlyContinue)) {
    $studioJbr = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
    if (Test-Path $studioJbr) { $keytool = $studioJbr } else { throw 'keytool not found. Install Android Studio or set JAVA_HOME.' }
}

$pw = Read-Host 'Choose a keystore password (min 12 characters)' -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw))
if ($plain.Length -lt 12) { throw 'Password must be at least 12 characters.' }

New-Item -ItemType Directory -Force $keyDir | Out-Null
# Passed via an environment variable so it never appears in the process list.
$env:THYANTRA_KS_PASS = $plain
try {
    & $keytool -genkeypair -v -keystore $keystore -storetype PKCS12 -keyalg RSA -keysize 4096 -validity 10000 `
        -alias upload -storepass:env THYANTRA_KS_PASS -keypass:env THYANTRA_KS_PASS `
        -dname 'CN=Thyantra Technologies, O=Thyantra Technologies, C=IN'
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed.' }
} finally {
    Remove-Item Env:THYANTRA_KS_PASS -ErrorAction SilentlyContinue
}

@"
storeFile=$($keystore -replace '\','/')
storePassword=$plain
keyAlias=upload
keyPassword=$plain
"@ | Set-Content -Encoding ascii $props

# Restrict key.properties to the current user.
icacls $props /inheritance:r /grant:r "$($env:USERNAME):(R,W)" | Out-Null
Write-Host "Created $keystore and android\key.properties. Back up the keystore and password now."
