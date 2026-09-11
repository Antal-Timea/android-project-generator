$ErrorActionPreference = 'Stop'

function Get-PowerShellExecutable {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $candidate = Join-Path $PSHOME 'pwsh.exe'
        if (Test-Path $candidate) { return $candidate }
        return 'pwsh'
    }

    $candidate = Join-Path $PSHOME 'powershell.exe'
    if (Test-Path $candidate) { return $candidate }
    return 'powershell.exe'
}

$powerShellExe = Get-PowerShellExecutable
$generator = Join-Path $PSScriptRoot 'new-android-project.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('android-generator-test-' + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $root -Force | Out-Null

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Invoke-GeneratorProcess([string[]]$ArgumentList, [switch]$SuppressOutput) {
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Expected generator failures write to stderr. Windows PowerShell 5.1 can
        # promote native stderr to an ErrorRecord; do not let that abort this harness.
        $ErrorActionPreference = 'Continue'
        if ($SuppressOutput) {
            & $powerShellExe @ArgumentList *> $null
        } else {
            # Send the child process output to the host instead of returning it
            # from this function. Otherwise PowerShell collects stdout together
            # with the exit code and the caller receives Object[] instead of Int32.
            & $powerShellExe @ArgumentList 2>&1 | Out-Host
        }
        $exitCode = $LASTEXITCODE
        return [int]$exitCode
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function ExpectFailure([string]$Project, [string]$Package) {
    $argumentList = @('-NoProfile','-File',$generator,'-ProjectName',$Project,'-PackageName',$Package,'-Destination',$root,'-SkipBuild','-SkipGit','-SkipWrapper')
    $exitCode = Invoke-GeneratorProcess -ArgumentList $argumentList -SuppressOutput
    Assert ($exitCode -ne 0) "Expected failure for Project='$Project' Package='$Package'"
}

try {
    ExpectFailure '' 'com.example.valid'
    ExpectFailure 'Invalid/Name' 'com.example.valid'
    ExpectFailure 'ValidName' 'not a valid package'
    ExpectFailure 'ValidName' '.com.example'

    $occupied = Join-Path $root 'Occupied'
    New-Item -ItemType Directory -Path $occupied -Force | Out-Null
    Set-Content -Path (Join-Path $occupied 'existing.txt') -Value 'x'
    $occupiedArgs = @('-NoProfile','-File',$generator,'-ProjectName','Occupied','-PackageName','com.example.occupied','-Destination',$root,'-SkipBuild','-SkipGit','-SkipWrapper')
    $occupiedExitCode = Invoke-GeneratorProcess -ArgumentList $occupiedArgs -SuppressOutput
    Assert ($occupiedExitCode -ne 0) 'Generator must refuse a non-empty project directory.'

    $generatorSource = Get-Content $generator -Raw
    Assert ($generatorSource.Contains('https://services.gradle.org/distributions/gradle-$Version-bin.zip')) 'Generator must bootstrap Gradle when no global installation exists.'
    Assert ($generatorSource.Contains('gradle/wrapper/gradle-wrapper.jar')) 'Generator must verify wrapper jar creation.'
    Assert ($generatorSource.Contains('function Resolve-AndroidSdk')) 'Generator must resolve the Android SDK automatically.'
    Assert ($generatorSource.Contains("Write-Utf8File (Join-Path $ProjectRoot 'local.properties')")) 'Generator must write local.properties for command-line builds.'
    Assert ($generatorSource.Contains('-AndroidSdkPath')) 'Generator must support an explicit Android SDK override.'
    Assert ($generatorSource.Contains('(?:\.\d+)?$')) 'Generator must accept SDK platform folders with numeric minor API suffixes such as android-37.2.'

    Assert (-not $generatorSource.Contains('[IO.Path]::GetFullPath($Destination,')) 'Generator must not use the two-argument GetFullPath overload unsupported by Windows PowerShell 5.1/.NET Framework.'
    Assert (-not $generatorSource.Contains('[Text.UTF8Encoding]::new')) 'Generator must avoid PowerShell/.NET constructor syntax that may vary across legacy environments.'


    $validArgs = @('-NoProfile','-File',$generator,'-ProjectName','GeneratedApp','-PackageName','com.example.generated','-Destination',$root,'-SkipBuild','-SkipGit','-SkipWrapper')
    $validExitCode = Invoke-GeneratorProcess -ArgumentList $validArgs
    Assert ($validExitCode -eq 0) 'Valid project generation failed.'
    $project = Join-Path $root 'GeneratedApp'

    $required = @(
        'settings.gradle.kts','build.gradle.kts','gradle.properties','gradle/libs.versions.toml','app/build.gradle.kts','app/proguard-rules.pro',
        'app/src/main/AndroidManifest.xml','app/src/main/res/values/strings.xml','app/src/main/res/values/themes.xml',
        'app/src/main/java/com/example/generated/App.kt','app/src/main/java/com/example/generated/MainActivity.kt',
        'app/src/main/java/com/example/generated/presentation/navigation/Destination.kt','app/src/main/java/com/example/generated/presentation/navigation/AppNavHost.kt',
        'app/src/main/java/com/example/generated/presentation/home/HomeUiState.kt','app/src/main/java/com/example/generated/presentation/home/HomeViewModel.kt','app/src/main/java/com/example/generated/presentation/home/HomeScreen.kt',
        'app/src/test/java/com/example/generated/StarterUnitTest.kt'
    )
    foreach ($path in $required) { Assert (Test-Path (Join-Path $project $path)) "Missing $path" }

    $appGradle = Get-Content (Join-Path $project 'app/build.gradle.kts') -Raw
    Assert ($appGradle.Contains('namespace = "com.example.generated"')) 'Wrong namespace.'
    Assert ($appGradle.Contains('applicationId = "com.example.generated"')) 'Wrong applicationId.'
    Assert ($appGradle.Contains('minSdk = 26')) 'Wrong minSdk.'
    Assert ($appGradle.Contains('compileSdk = 37')) 'Wrong compileSdk.'
    Assert ($appGradle.Contains('targetSdk = 37')) 'Wrong targetSdk.'

    $catalog = Get-Content (Join-Path $project 'gradle/libs.versions.toml') -Raw
    Assert (-not ($catalog -match '(?im)^[A-Za-z0-9_-]+\s*=\s*"[^"\r\n]*(alpha|beta|rc|snapshot)[^"\r\n]*"\s*$')) 'Prerelease version pin found.'
    Assert (-not ($catalog -match '(?im)^[A-Za-z0-9_-]+\s*=\s*"[^"\r\n]*\+[^"\r\n]*"\s*$')) 'Floating version pin found.'
    Assert (-not $catalog.Contains('org.jetbrains.kotlin.android')) 'AGP 9 built-in Kotlin should not use kotlin-android.'
    Assert ($catalog.Contains('kotlin = "2.4.20"')) 'Kotlin version must be 2.4.20.'
    Assert ($catalog.Contains('compose-bom = "2026.09.00"')) 'Compose BOM must be 2026.09.00.'
    Assert ($catalog.Contains('navigation = "2.10.1"')) 'Navigation Compose must be 2.10.1.'
    Assert ($catalog.Contains('androidx-hilt = "1.4.0"')) 'AndroidX Hilt must be 1.4.0.'
    Assert ($catalog.Contains('okhttp = "5.5.0"')) 'OkHttp must be 5.5.0.'
    Assert ($catalog.Contains('coil = "3.6.2"')) 'Coil must be 3.6.2.'
    Assert ($catalog.Contains('room = "2.8.5"')) 'Room must be 2.8.5.'
    Assert ($catalog.Contains('material-icons = { module = "androidx.compose.material:material-icons-core", version.ref = "icons"}')) 'Material Icons catalog entry missing.'
    Assert ($catalog.Contains('coil-compose = { module = "io.coil-kt.coil3:coil-compose", version.ref = "coil" }')) 'Coil Compose catalog entry missing.'
    Assert ($catalog.Contains('coil-network-okhttp = { module = "io.coil-kt.coil3:coil-network-okhttp", version.ref = "coil" }')) 'Coil OkHttp catalog entry missing.'

    Assert ($appGradle.Contains('implementation(libs.material.icons)')) 'Material Icons dependency missing from app module.'
    Assert ($appGradle.Contains('implementation(libs.coil.compose)')) 'Coil Compose dependency missing from app module.'
    Assert ($appGradle.Contains('implementation(libs.coil.network.okhttp)')) 'Coil OkHttp dependency missing from app module.'

    $allKotlin = Get-ChildItem (Join-Path $project 'app/src') -Recurse -Filter '*.kt'
    foreach ($file in $allKotlin) {
        $content = Get-Content $file.FullName -Raw
        Assert ($content.TrimStart().StartsWith('package com.example.generated')) "Wrong package in $($file.FullName)"
        Assert (-not $content.Contains('com.example.starter')) "Starter placeholder leaked into $($file.FullName)"
    }

    $manifest = Get-Content (Join-Path $project 'app/src/main/AndroidManifest.xml') -Raw
    Assert ($manifest.Contains('android:name=".App"')) 'Manifest missing App application.'
    Assert ($manifest.Contains('android:exported="true"')) 'Launcher activity must be exported.'

    $stringsPath = Join-Path $project 'app/src/main/res/values/strings.xml'
    $stringsRaw = Get-Content $stringsPath -Raw
    Assert ($stringsRaw.Contains('<string name="app_name">GeneratedApp</string>')) 'strings.xml must contain a valid quoted app_name attribute.'
    try {
        [xml]$stringsDocument = $stringsRaw
    } catch {
        throw "ASSERTION FAILED: strings.xml is not well-formed XML: $($_.Exception.Message)"
    }
    Assert ($stringsDocument.resources.string.name -eq 'app_name') 'strings.xml app_name attribute parsed incorrectly.'

    $dest = Get-Content (Join-Path $project 'app/src/main/java/com/example/generated/presentation/navigation/Destination.kt') -Raw
    $nav = Get-Content (Join-Path $project 'app/src/main/java/com/example/generated/presentation/navigation/AppNavHost.kt') -Raw
    Assert ($dest.Contains('@Serializable')) 'Home destination must be serializable.'
    Assert ($dest.Contains('data object Home')) 'Home destination missing.'
    Assert ($nav.Contains('NavHost(')) 'NavHost missing.'
    Assert ($nav.Contains('composable<Home>')) 'Type-safe Home route missing.'
    Assert (-not $nav.Contains('androidx.navigation3')) 'Navigation 3 must not be used.'

    Assert (-not (Test-Path (Join-Path $project '.git'))) '-SkipGit created a git repository.'
    
$generatorSource = [IO.File]::ReadAllText($generator)
Assert ($generatorSource.Contains('function Resolve-JavaHome')) 'Generator must resolve a Java home for Gradle bootstrap.'
Assert ($generatorSource.Contains("Android\Android Studio\jbr")) 'Generator must fall back to Android Studio bundled JBR.'
Assert ($generatorSource.Contains('Invoke-GradleWithJava')) 'Generator must run Gradle with resolved JAVA_HOME.'
Assert (-not $generatorSource.Contains('& $javaExe -version')) 'Generator must not probe java -version through the PowerShell error stream; Java writes version info to stderr.'
Assert (-not $generatorSource.Contains('Invoke-WithJavaHome')) 'Generator must not call undefined Invoke-WithJavaHome helper.'
Assert ($generatorSource.Contains("$ErrorActionPreference = 'Continue'")) 'Native Gradle invocation must tolerate normal stderr output on Windows PowerShell 5.1.'
Assert ($generatorSource.Contains("Android Project Generator $GeneratorVersion") -or $generatorSource.Contains('Android Project Generator')) 'Generator must print a version banner.'

Write-Host 'All generator smoke tests passed.'
} finally {
    Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue
}
