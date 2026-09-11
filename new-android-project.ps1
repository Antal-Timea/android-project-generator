[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [string]$PackageName,

    [int]$MinSdk = 26,
    [int]$CompileSdk = 37,
    [int]$TargetSdk = 37,
    [string]$Destination = '.',
    [string]$AndroidSdkPath,
    [switch]$SkipBuild,
    [switch]$SkipGit,
    [switch]$SkipWrapper
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$GeneratorVersion = '2026.09.10.1'
Write-Host "Android Project Generator $GeneratorVersion"

function Fail([string]$Message) {
    Write-Error $Message
    exit 1
}

function Write-Utf8File([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if ([string]::IsNullOrWhiteSpace($ProjectName)) { Fail 'ProjectName must not be empty.' }
if ($ProjectName -match '[\\/:*?"<>|]') { Fail 'ProjectName contains invalid filesystem characters.' }
if ($ProjectName -in @('.', '..')) { Fail 'ProjectName is invalid.' }

$segment = '[A-Za-z_][A-Za-z0-9_]*'
if ($PackageName -notmatch "^$segment(\.$segment)+$") {
    Fail 'PackageName must contain at least two valid Java/Kotlin identifier segments (for example com.example.app).'
}
if ($MinSdk -lt 24 -or $MinSdk -gt $TargetSdk) { Fail 'MinSdk must be at least 24 and not exceed TargetSdk.' }
if ($TargetSdk -gt $CompileSdk) { Fail 'TargetSdk must not exceed CompileSdk.' }

if ([IO.Path]::IsPathRooted($Destination)) {
    $destinationFull = [IO.Path]::GetFullPath($Destination)
} else {
    $destinationFull = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $Destination))
}
$projectRoot = Join-Path $destinationFull $ProjectName
if (Test-Path $projectRoot) {
    $existing = @(Get-ChildItem -Force -Path $projectRoot)
    if ($existing.Count -gt 0) { Fail "Refusing to overwrite non-empty directory: $projectRoot" }
} else {
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
}

$packagePath = $PackageName.Replace('.', [IO.Path]::DirectorySeparatorChar)
$mainKotlin = Join-Path $projectRoot "app/src/main/java/$packagePath"
$testKotlin = Join-Path $projectRoot "app/src/test/java/$packagePath"
$androidTestKotlin = Join-Path $projectRoot "app/src/androidTest/java/$packagePath"

$dirs = @(
    'gradle', 'app/src/main/res/values', 'app/src/main/res/xml',
    "app/src/main/java/$packagePath/data/local", "app/src/main/java/$packagePath/data/remote", "app/src/main/java/$packagePath/data/repository",
    "app/src/main/java/$packagePath/domain/model", "app/src/main/java/$packagePath/domain/repository", "app/src/main/java/$packagePath/domain/usecase",
    "app/src/main/java/$packagePath/presentation/navigation", "app/src/main/java/$packagePath/presentation/home", "app/src/main/java/$packagePath/presentation/components", "app/src/main/java/$packagePath/presentation/theme",
    "app/src/main/java/$packagePath/di", "app/src/test/java/$packagePath", "app/src/androidTest/java/$packagePath"
)
foreach ($dir in $dirs) { New-Item -ItemType Directory -Path (Join-Path $projectRoot $dir) -Force | Out-Null }

$versions = @'
[versions]
agp = "9.4.0"
kotlin = "2.4.20"
ksp = "2.3.11"
compose-bom = "2026.09.00"
activity = "1.13.0"
lifecycle = "2.11.0"
navigation = "2.10.1"
androidx-hilt = "1.4.0"
dagger-hilt = "2.60.1"
coroutines = "1.11.0"
retrofit = "3.0.0"
okhttp = "5.5.0"
serialization-json = "1.11.0"
coil = "3.6.2"
room = "2.8.5"
junit = "4.13.2"
mockk = "1.14.11"
turbine = "1.2.1"
androidx-test-ext = "1.3.0"
androidx-test-runner = "1.7.0"
espresso = "3.7.0"
icons = "1.7.8"

[libraries]
compose-bom = { module = "androidx.compose:compose-bom", version.ref = "compose-bom" }
compose-ui = { module = "androidx.compose.ui:ui" }
compose-ui-tooling = { module = "androidx.compose.ui:ui-tooling" }
compose-ui-tooling-preview = { module = "androidx.compose.ui:ui-tooling-preview" }
compose-ui-test-junit4 = { module = "androidx.compose.ui:ui-test-junit4" }
compose-ui-test-manifest = { module = "androidx.compose.ui:ui-test-manifest" }
compose-material3 = { module = "androidx.compose.material3:material3" }
activity-compose = { module = "androidx.activity:activity-compose", version.ref = "activity" }
lifecycle-runtime-compose = { module = "androidx.lifecycle:lifecycle-runtime-compose", version.ref = "lifecycle" }
lifecycle-viewmodel-compose = { module = "androidx.lifecycle:lifecycle-viewmodel-compose", version.ref = "lifecycle" }
navigation-compose = { module = "androidx.navigation:navigation-compose", version.ref = "navigation" }
androidx-hilt-viewmodel-compose = { module = "androidx.hilt:hilt-lifecycle-viewmodel-compose", version.ref = "androidx-hilt" }
dagger-hilt-android = { module = "com.google.dagger:hilt-android", version.ref = "dagger-hilt" }
dagger-hilt-compiler = { module = "com.google.dagger:hilt-compiler", version.ref = "dagger-hilt" }
coroutines-android = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-android", version.ref = "coroutines" }
retrofit = { module = "com.squareup.retrofit2:retrofit", version.ref = "retrofit" }
retrofit-kotlinx-serialization = { module = "com.squareup.retrofit2:converter-kotlinx-serialization", version.ref = "retrofit" }
okhttp-bom = { module = "com.squareup.okhttp3:okhttp-bom", version.ref = "okhttp" }
okhttp = { module = "com.squareup.okhttp3:okhttp" }
okhttp-logging = { module = "com.squareup.okhttp3:logging-interceptor" }
serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "serialization-json" }
coil-compose = { module = "io.coil-kt.coil3:coil-compose", version.ref = "coil" }
coil-network-okhttp = { module = "io.coil-kt.coil3:coil-network-okhttp", version.ref = "coil" }
room-runtime = { module = "androidx.room:room-runtime", version.ref = "room" }
room-ktx = { module = "androidx.room:room-ktx", version.ref = "room" }
room-compiler = { module = "androidx.room:room-compiler", version.ref = "room" }
junit = { module = "junit:junit", version.ref = "junit" }
mockk = { module = "io.mockk:mockk", version.ref = "mockk" }
turbine = { module = "app.cash.turbine:turbine", version.ref = "turbine" }
androidx-test-ext-junit = { module = "androidx.test.ext:junit", version.ref = "androidx-test-ext" }
androidx-test-runner = { module = "androidx.test:runner", version.ref = "androidx-test-runner" }
espresso-core = { module = "androidx.test.espresso:espresso-core", version.ref = "espresso" }
material-icons = { module = "androidx.compose.material:material-icons-core", version.ref = "icons"}

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
ksp = { id = "com.google.devtools.ksp", version.ref = "ksp" }
hilt = { id = "com.google.dagger.hilt.android", version.ref = "dagger-hilt" }
'@
Write-Utf8File (Join-Path $projectRoot 'gradle/libs.versions.toml') $versions

$settings = @'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "__PROJECT__"
include(":app")
'@.Replace('__PROJECT__', $ProjectName)
Write-Utf8File (Join-Path $projectRoot 'settings.gradle.kts') $settings

$rootBuild = @'
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.hilt) apply false
}
'@
Write-Utf8File (Join-Path $projectRoot 'build.gradle.kts') $rootBuild

$gradleProps = @'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
'@
Write-Utf8File (Join-Path $projectRoot 'gradle.properties') $gradleProps

$appBuild = @'
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
}

android {
    namespace = "__PACKAGE__"
    compileSdk = __COMPILE_SDK__

    defaultConfig {
        applicationId = "__PACKAGE__"
        minSdk = __MIN_SDK__
        targetSdk = __TARGET_SDK__
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    androidTestImplementation(platform(libs.compose.bom))

    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.material.icons)
    implementation(libs.navigation.compose)
    implementation(libs.androidx.hilt.viewmodel.compose)

    implementation(libs.dagger.hilt.android)
    ksp(libs.dagger.hilt.compiler)

    implementation(libs.coroutines.android)
    implementation(libs.retrofit)
    implementation(libs.retrofit.kotlinx.serialization)
    implementation(platform(libs.okhttp.bom))
    implementation(libs.okhttp)
    implementation(libs.okhttp.logging)
    implementation(libs.serialization.json)

    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.turbine)

    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.espresso.core)
    androidTestImplementation(libs.compose.ui.test.junit4)

    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
}
'@
$appBuild = $appBuild.Replace('__PACKAGE__', $PackageName).Replace('__COMPILE_SDK__', "$CompileSdk").Replace('__MIN_SDK__', "$MinSdk").Replace('__TARGET_SDK__', "$TargetSdk")
Write-Utf8File (Join-Path $projectRoot 'app/build.gradle.kts') $appBuild
Write-Utf8File (Join-Path $projectRoot 'app/proguard-rules.pro') "# Add project-specific R8/ProGuard rules here when needed.`n"

$manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />

    <application
        android:name=".App"
        android:allowBackup="true"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.__THEME__">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:theme="@style/Theme.__THEME__">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
'@.Replace('__THEME__', ($ProjectName -replace '[^A-Za-z0-9_]', ''))
Write-Utf8File (Join-Path $projectRoot 'app/src/main/AndroidManifest.xml') $manifest

$escapedAppName = [Security.SecurityElement]::Escape($ProjectName)
$stringsXml = @"
<resources>
    <string name="app_name">$escapedAppName</string>
</resources>
"@
Write-Utf8File (Join-Path $projectRoot 'app/src/main/res/values/strings.xml') $stringsXml
$themeName = ($ProjectName -replace '[^A-Za-z0-9_]', '')
$themesXml = @'
<resources>
    <style name="Theme.__THEME__" parent="android:style/Theme.Material.Light.NoActionBar">
        <item name="android:windowLightStatusBar">true</item>
    </style>
</resources>
'@.Replace('__THEME__', $themeName)
Write-Utf8File (Join-Path $projectRoot 'app/src/main/res/values/themes.xml') $themesXml

function KotlinFile([string]$RelativePath, [string]$Content) {
    Write-Utf8File (Join-Path $mainKotlin $RelativePath) $Content.Replace('__PACKAGE__', $PackageName).Replace('__PROJECT__', $ProjectName)
}

KotlinFile 'App.kt' @'
package __PACKAGE__

import android.app.Application
import dagger.hilt.android.HiltAndroidApp

@HiltAndroidApp
class App : Application()
'@

KotlinFile 'MainActivity.kt' @'
package __PACKAGE__

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import dagger.hilt.android.AndroidEntryPoint
import __PACKAGE__.presentation.navigation.AppNavHost
import __PACKAGE__.presentation.theme.AppTheme

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AppTheme {
                AppNavHost()
            }
        }
    }
}
'@

KotlinFile 'presentation/navigation/Destination.kt' @'
package __PACKAGE__.presentation.navigation

import kotlinx.serialization.Serializable

@Serializable
data object Home
'@

KotlinFile 'presentation/navigation/AppNavHost.kt' @'
package __PACKAGE__.presentation.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import __PACKAGE__.presentation.home.HomeScreen

@Composable
fun AppNavHost(
    navController: NavHostController = rememberNavController(),
) {
    NavHost(
        navController = navController,
        startDestination = Home,
    ) {
        composable<Home> {
            HomeScreen()
        }
    }
}
'@

KotlinFile 'presentation/home/HomeUiState.kt' @'
package __PACKAGE__.presentation.home

data class HomeUiState(
    val title: String = "__PROJECT__",
)
'@

KotlinFile 'presentation/home/HomeViewModel.kt' @'
package __PACKAGE__.presentation.home

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@HiltViewModel
class HomeViewModel @Inject constructor() : ViewModel() {
    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()
}
'@

KotlinFile 'presentation/home/HomeScreen.kt' @'
package __PACKAGE__.presentation.home

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable
fun HomeScreen(
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    HomeContent(uiState)
}

@Composable
private fun HomeContent(uiState: HomeUiState) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = uiState.title,
            style = MaterialTheme.typography.headlineMedium,
        )
    }
}
'@

KotlinFile 'presentation/theme/Color.kt' @'
package __PACKAGE__.presentation.theme

import androidx.compose.ui.graphics.Color

internal val LightPrimary = Color(0xFF3F51B5)
internal val DarkPrimary = Color(0xFFBAC3FF)
'@

KotlinFile 'presentation/theme/Type.kt' @'
package __PACKAGE__.presentation.theme

import androidx.compose.material3.Typography

val AppTypography = Typography()
'@

KotlinFile 'presentation/theme/Theme.kt' @'
package __PACKAGE__.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(primary = LightPrimary)
private val DarkColors = darkColorScheme(primary = DarkPrimary)

@Composable
fun AppTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = AppTypography,
        content = content,
    )
}
'@

$unitTest = @'
package __PACKAGE__

import org.junit.Assert.assertTrue
import org.junit.Test

class StarterUnitTest {
    @Test
    fun testSourceSetIsWired() {
        assertTrue(true)
    }
}
'@.Replace('__PACKAGE__', $PackageName)
Write-Utf8File (Join-Path $testKotlin 'StarterUnitTest.kt') $unitTest

foreach ($empty in @('data/local','data/remote','data/repository','domain/model','domain/repository','domain/usecase','presentation/components','di')) {
    Write-Utf8File (Join-Path $mainKotlin "$empty/.gitkeep") ''
}

$gitignore = @'
*.iml
.gradle/
/local.properties
/.idea/
.DS_Store
/build/
/captures/
.externalNativeBuild/
.cxx/
app/build/
'@
Write-Utf8File (Join-Path $projectRoot '.gitignore') $gitignore

if (-not $SkipGit) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        & git -C $projectRoot init | Out-Null
    } else {
        Write-Warning 'Git was not found. Project generated without git init.'
    }
}

$gradleVersion = '9.6.0'
$gradleCommand = $null
$gradleArgs = @()
$wrapperBat = Join-Path $projectRoot 'gradlew.bat'


function Resolve-JavaHome {
    $candidates = @()

    if ($env:JAVA_HOME) {
        $candidates += $env:JAVA_HOME
    }

    $javaCommand = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCommand) {
        $javaExe = if ($javaCommand.Source) { $javaCommand.Source } else { $javaCommand.Path }
        if ($javaExe) {
            $candidates += (Split-Path -Parent (Split-Path -Parent $javaExe))
        }
    }

    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr')
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Android\Android Studio\jbr')
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\jbr')
    }

    $studioCommand = Get-Command studio64.exe -ErrorAction SilentlyContinue
    if ($studioCommand) {
        $studioExe = if ($studioCommand.Source) { $studioCommand.Source } else { $studioCommand.Path }
        if ($studioExe) {
            $studioHome = Split-Path -Parent $studioExe
            $candidates += (Join-Path $studioHome 'jbr')
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        $javaExe = Join-Path $candidate 'bin\java.exe'
        if (Test-Path $javaExe) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }

    throw 'Java 17+ was not found. Android Studio normally provides it under C:\Program Files\Android\Android Studio\jbr. Set JAVA_HOME explicitly if Android Studio is installed elsewhere.'
}


function Resolve-AndroidSdk([string]$ExplicitPath, [int]$RequiredCompileSdk) {
    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $candidates += $ExplicitPath
    }
    if ($env:ANDROID_HOME) {
        $candidates += $env:ANDROID_HOME
    }
    if ($env:ANDROID_SDK_ROOT) {
        $candidates += $env:ANDROID_SDK_ROOT
    }
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    }
    if ($env:USERPROFILE) {
        $candidates += (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk')
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        try {
            $fullPath = [IO.Path]::GetFullPath($candidate)
        } catch {
            continue
        }

        $platformsRoot = Join-Path $fullPath 'platforms'
        if (-not (Test-Path $platformsRoot)) { continue }

        # Recent Android SDK packages may store a major API level with a minor
        # suffix (for example android-37.0, android-37.1, android-37.2) even
        # though Gradle is configured with compileSdk = 37. Accept the exact
        # major folder and any numeric minor revision for that API level.
        $platformPattern = '^android-' + [regex]::Escape([string]$RequiredCompileSdk) + '(?:\.\d+)?$'
        $matchingPlatforms = Get-ChildItem -Path $platformsRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match $platformPattern -and (Test-Path (Join-Path $_.FullName 'android.jar')) } |
            Sort-Object Name -Descending

        if ($matchingPlatforms) {
            Write-Host "Found Android platform: $($matchingPlatforms[0].Name)"
            return $fullPath
        }
    }

    $searched = ($candidates | Select-Object -Unique) -join '; '
    if ([string]::IsNullOrWhiteSpace($searched)) {
        $searched = '<no SDK candidates discovered>'
    }
    throw "Android SDK with a compatible platform for API $RequiredCompileSdk was not found. Install Android SDK Platform $RequiredCompileSdk in Android Studio SDK Manager, set ANDROID_HOME/ANDROID_SDK_ROOT, or pass -AndroidSdkPath explicitly. Searched: $searched"
}

function Write-LocalProperties([string]$ProjectRoot, [string]$SdkPath) {
    # local.properties accepts forward slashes on Windows and this avoids
    # Java-properties backslash escaping issues (for example C:\\Users\\...).
    $normalizedSdkPath = $SdkPath.Replace('\', '/')
    Write-Utf8File (Join-Path $ProjectRoot 'local.properties') "sdk.dir=$normalizedSdkPath`n"
    Write-Host "Using Android SDK from: $SdkPath"
}

function Invoke-GradleWithJava([string]$GradleBat, [string[]]$Arguments, [string]$JavaHome) {
    $previousJavaHome = $env:JAVA_HOME
    $previousPath = $env:PATH
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $env:JAVA_HOME = $JavaHome
        $javaBin = Join-Path $JavaHome 'bin'
        $env:PATH = $javaBin + ';' + $previousPath

        $javaExe = Join-Path $JavaHome 'bin\java.exe'
        if (-not (Test-Path $javaExe)) {
            throw "Resolved Java runtime is missing java.exe: $javaExe"
        }

        Write-Host "Using Java from: $JavaHome"

        # Native tools commonly write normal diagnostic output to stderr.
        # Windows PowerShell 5.1 can promote that stream to ErrorRecord when
        # ErrorActionPreference is Stop, so keep native output visible without
        # allowing stderr alone to abort the wrapper/build process.
        $ErrorActionPreference = 'Continue'
        & $GradleBat @Arguments 2>&1 | Out-Host
        $exitCode = $LASTEXITCODE
        return [int]$exitCode
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        $env:JAVA_HOME = $previousJavaHome
        $env:PATH = $previousPath
    }
}

function New-GradleWrapper([string]$ProjectRoot, [string]$Version) {
    if (Test-Path (Join-Path $ProjectRoot 'gradlew.bat')) { return }

    $javaHome = Resolve-JavaHome
    $globalGradle = Get-Command gradle -ErrorAction SilentlyContinue

    if ($globalGradle) {
        $globalGradleBat = if ($globalGradle.Source) { $globalGradle.Source } else { $globalGradle.Path }
        Push-Location $ProjectRoot
        try {
            $exitCode = Invoke-GradleWithJava -GradleBat $globalGradleBat -Arguments @('wrapper','--gradle-version',$Version,'--distribution-type','bin') -JavaHome $javaHome
            if ($exitCode -ne 0) { throw "Gradle wrapper creation failed with exit code $exitCode." }
        } finally { Pop-Location }
    } else {
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('android-project-generator-gradle-' + [Guid]::NewGuid().ToString())
        $zipPath = Join-Path $tempRoot "gradle-$Version-bin.zip"
        $distributionUrl = "https://services.gradle.org/distributions/gradle-$Version-bin.zip"

        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        try {
            Write-Host "Global Gradle not found. Bootstrapping Gradle $Version to create the wrapper..."

            if ($PSVersionTable.PSEdition -eq 'Desktop') {
                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            }

            Invoke-WebRequest -Uri $distributionUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $tempRoot -Force

            $bootstrapGradle = Join-Path $tempRoot "gradle-$Version\bin\gradle.bat"
            if (-not (Test-Path $bootstrapGradle)) {
                throw "Downloaded Gradle archive did not contain expected executable: $bootstrapGradle"
            }

            Push-Location $ProjectRoot
            try {
                $exitCode = Invoke-GradleWithJava -GradleBat $bootstrapGradle -Arguments @('wrapper','--gradle-version',$Version,'--distribution-type','bin') -JavaHome $javaHome
                if ($exitCode -ne 0) { throw "Gradle wrapper creation failed with exit code $exitCode." }
            } finally { Pop-Location }
        } finally {
            Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
        }
    }

    $requiredWrapperFiles = @(
        'gradlew',
        'gradlew.bat',
        'gradle/wrapper/gradle-wrapper.jar',
        'gradle/wrapper/gradle-wrapper.properties'
    )
    foreach ($relativePath in $requiredWrapperFiles) {
        if (-not (Test-Path (Join-Path $ProjectRoot $relativePath))) {
            throw "Gradle wrapper creation did not produce required file: $relativePath"
        }
    }
}

if (-not $SkipWrapper) {
    try {
        New-GradleWrapper -ProjectRoot $projectRoot -Version $gradleVersion
    } catch {
        Write-Error "Unable to create Gradle wrapper: $($_.Exception.Message) Project kept at $projectRoot"
        exit 1
    }
}

if (-not $SkipBuild) {
    try {
        $androidSdk = Resolve-AndroidSdk -ExplicitPath $AndroidSdkPath -RequiredCompileSdk $CompileSdk
        Write-LocalProperties -ProjectRoot $projectRoot -SdkPath $androidSdk
    } catch {
        Write-Error "$($_.Exception.Message) Project kept at $projectRoot"
        exit 1
    }

    if (Test-Path $wrapperBat) {
        $gradleCommand = $wrapperBat
        $gradleArgs = @('assembleDebug')
    } elseif (Get-Command gradle -ErrorAction SilentlyContinue) {
        $gradleCommand = 'gradle'
        $gradleArgs = @('assembleDebug')
    }

    if ($gradleCommand) {
        Push-Location $projectRoot
        try {
            $javaHome = Resolve-JavaHome
            $exitCode = Invoke-GradleWithJava -GradleBat $gradleCommand -Arguments $gradleArgs -JavaHome $javaHome
            if ($exitCode -ne 0) {
                throw "Build failed: $gradleCommand $($gradleArgs -join ' ') (exit $exitCode)."
            }
        } catch {
            Write-Error "$($_.Exception.Message) Project kept at $projectRoot"
            exit 1
        } finally { Pop-Location }
    } else {
        Write-Warning 'No Gradle wrapper or global Gradle found. This is expected only when -SkipWrapper is used.'
    }
}

Write-Host "Generated Android project: $projectRoot"
