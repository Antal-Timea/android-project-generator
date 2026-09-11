# Android Project Generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a readable PowerShell generator that creates a fresh, buildable, single-module Android Compose project from scratch with current stable dependencies and generic interview-safe scaffolding only.

**Architecture:** A single `new-android-project.ps1` command owns validation, directory creation, and deterministic text generation. A separate `test-generator.ps1` smoke-test exercises the generator in a temporary directory and verifies package substitution and required files. The generated Android project uses a version catalog, Compose + Hilt + Navigation Compose 2.x, and only a minimal Home screen to prove wiring.

**Tech Stack:** PowerShell 7+, Gradle Kotlin DSL, Android Gradle Plugin, Kotlin, Jetpack Compose, Material 3, Navigation Compose 2.x, Hilt, KSP, Coroutines/Flow, Retrofit/OkHttp/kotlinx.serialization, Room, JUnit, MockK, Turbine, AndroidX/Compose testing.

**Spec:** `docs/superpowers/specs/2026-09-08-android-project-generator-design.md`

## Global Constraints

- Windows-first PowerShell workflow.
- Every generated project file is created during the invocation; no starter repository is copied.
- Single `:app` module.
- Use Navigation Compose 2.x, not Navigation 3.
- Use type-safe `@Serializable` routes.
- Use the latest stable release available at implementation time for every dependency and build tool.
- Verify dependency/tool versions from official release documentation; never rely on remembered version numbers.
- No alpha, beta, RC, snapshot, `+`, or floating versions unless explicitly requested.
- Version catalog lives at `gradle/libs.versions.toml`.
- No task-specific models, APIs, repositories, use cases, caching, error mapping, or feature design.
- No `BaseViewModel`, `BaseRepository`, generic result wrapper, or custom MVI framework.
- Build verification must use a real generated project and `assembleDebug` when a usable Gradle environment is available.
- A build failure must leave the generated project intact and return a clear error.

---

## File Map

### Generator repository

- `new-android-project.ps1` — validates CLI arguments, creates the complete project tree, writes every generated file, optionally initializes Git/wrapper, and optionally runs build verification.
- `test-generator.ps1` — black-box smoke test for generation, package replacement, expected file set, and absence of the starter placeholder package.
- `README.md` — usage, parameters, version policy, interview-safety scope, and troubleshooting.
- `docs/superpowers/specs/2026-09-08-android-project-generator-design.md` — approved design.
- `docs/superpowers/plans/2026-09-08-android-project-generator-implementation.md` — this implementation plan.

### Generated Android project

- `settings.gradle.kts` — plugin management, repositories, root name, `:app` include.
- `build.gradle.kts` — root plugin aliases with `apply false`.
- `gradle.properties` — AndroidX/Kotlin/Gradle defaults.
- `gradle/libs.versions.toml` — pinned latest-stable compatible tool/library versions.
- `.gitignore` — standard Android/Gradle/IDE ignores.
- `app/build.gradle.kts` — Android/Kotlin/Compose/KSP/Hilt configuration and dependencies.
- `app/proguard-rules.pro` — intentionally minimal rules file.
- `app/src/main/AndroidManifest.xml` — `App` application and exported launcher activity.
- `app/src/main/res/values/strings.xml` — generated app name.
- `app/src/main/res/values/themes.xml` — minimal platform theme for the activity.
- `App.kt` — `@HiltAndroidApp` application.
- `MainActivity.kt` — edge-to-edge Compose host with `@AndroidEntryPoint`.
- `presentation/navigation/Destination.kt` — type-safe serializable Home route.
- `presentation/navigation/AppNavHost.kt` — Navigation Compose 2.x `NavHost`.
- `presentation/home/HomeUiState.kt` — immutable generic UI state.
- `presentation/home/HomeViewModel.kt` — Hilt ViewModel exposing StateFlow.
- `presentation/home/HomeScreen.kt` — lifecycle-aware state collection and placeholder UI.
- `presentation/theme/Color.kt` — minimal theme colors.
- `presentation/theme/Type.kt` — Material typography.
- `presentation/theme/Theme.kt` — Material 3 light/dark theme.
- empty architecture folders — kept with `.gitkeep` where needed.
- `app/src/test/.../StarterUnitTest.kt` — trivial JVM smoke test.

---

### Task 1: Verify and Pin Current Stable Toolchain and Dependencies

**Files:**
- Modify: `docs/superpowers/specs/2026-09-08-android-project-generator-design.md`
- Create during implementation: version matrix notes in the implementation log or commit message
- Later consumed by: `new-android-project.ps1` when writing `gradle/libs.versions.toml`

**Interfaces:**
- Consumes: official Android Developers/Google Maven/JetBrains/library-maintainer release information.
- Produces: a concrete mutually compatible set of pinned stable versions for AGP, Gradle, Kotlin, KSP, Compose BOM, Navigation Compose 2.x, Lifecycle, Hilt, Coroutines, Retrofit, OkHttp, kotlinx.serialization, Room, MockK, Turbine, and AndroidX testing.

- [ ] **Step 1: Collect official stable versions**

Check only official release sources. Record exact stable versions and exclude any release whose label contains `alpha`, `beta`, `rc`, `snapshot`, `dev`, or `preview`.

- [ ] **Step 2: Check compatibility constraints**

Verify at minimum:

```text
AGP ↔ required Gradle version
AGP ↔ required JDK version
Kotlin ↔ Compose compiler integration
Kotlin ↔ KSP version
Room ↔ KSP
Navigation Compose 2.x ↔ Kotlin serialization
Hilt ↔ Kotlin/KSP/AGP
```

- [ ] **Step 3: Freeze exact versions for this generator revision**

Write the verified versions directly into the generator's version-catalog template. At implementation time the already-confirmed baseline includes AGP 9.4.0, Gradle 9.6.0, Compose BOM 2026.08.00, and Navigation Compose 2.10.0; re-check these immediately before implementation in case a newer stable release appeared. Record every other library with the exact stable version found from its official release source, then build-test the complete set before accepting it.

- [ ] **Step 4: Commit version-policy/spec update**

```bash
git add docs/superpowers/specs/2026-09-08-android-project-generator-design.md
git commit -m "docs: define stable dependency version policy"
```

### Task 2: Implement Generator Input Validation and Filesystem Layout

**Files:**
- Create: `new-android-project.ps1`
- Create: `test-generator.ps1`

**Interfaces:**
- Consumes parameters: `ProjectName: string`, `PackageName: string`, `MinSdk: int = 26`, `CompileSdk: int`, `TargetSdk: int`, `Destination: string = '.'`, `SkipBuild: switch`, `SkipGit: switch`.
- Produces generated project root path and deterministic package path derived by replacing `.` with the platform directory separator.

- [ ] **Step 1: Write failing validation smoke tests**

`test-generator.ps1` must invoke the generator in temporary locations and assert that these fail with non-zero exit status:

```powershell
@(
    @{ Project = ''; Package = 'com.example.valid' },
    @{ Project = 'Invalid/Name'; Package = 'com.example.valid' },
    @{ Project = 'ValidName'; Package = 'not a valid package' },
    @{ Project = 'ValidName'; Package = '.com.example' }
)
```

It must also pre-create a non-empty destination project directory and assert that generation refuses to overwrite it.

- [ ] **Step 2: Run the test and verify failure**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: FAIL because `new-android-project.ps1` does not yet exist.

- [ ] **Step 3: Implement parameter contract and validation**

Use an advanced-script `param` block with mandatory `ProjectName` and `PackageName`. Validate package names against Java/Kotlin identifier segments and reject path separators/reserved filesystem characters in project names.

- [ ] **Step 4: Implement safe destination creation**

Compute:

```powershell
$projectRoot = Join-Path $Destination $ProjectName
$packagePath = $PackageName -replace '\.', [IO.Path]::DirectorySeparatorChar
```

Refuse an existing non-empty `$projectRoot`; create it when absent.

- [ ] **Step 5: Create all required directory paths**

Create Gradle, resources, main/test/androidTest source sets, architecture packages, navigation/home/theme packages, and `di`.

- [ ] **Step 6: Run validation smoke tests**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: validation cases PASS; file-content cases may still fail because files are not generated yet.

- [ ] **Step 7: Commit**

```bash
git add new-android-project.ps1 test-generator.ps1
git commit -m "feat: add generator validation and layout"
```

### Task 3: Generate Gradle Build Configuration and Version Catalog

**Files:**
- Modify: `new-android-project.ps1`
- Modify: `test-generator.ps1`
- Generated: `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`, `app/build.gradle.kts`, `app/proguard-rules.pro`

**Interfaces:**
- Consumes: exact verified versions from Task 1 and validated SDK parameters from Task 2.
- Produces: a Gradle Kotlin DSL project configured for Compose, Kotlin serialization, KSP, Hilt, Room, Retrofit, Coroutines, Navigation Compose 2.x, and tests.

- [ ] **Step 1: Add failing file/content assertions**

Assert that a generated sample project contains all six Gradle files and that:

```text
namespace = "com.example.generated"
applicationId = "com.example.generated"
minSdk = 26
compileSdk = 37
targetSdk = 37
```

Also assert the version catalog contains no `+`, `alpha`, `beta`, `rc`, or `SNAPSHOT` version strings.

- [ ] **Step 2: Run tests and verify failure**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: FAIL on missing Gradle files.

- [ ] **Step 3: Generate `settings.gradle.kts` and root build file**

Include `google()`, `mavenCentral()`, repository mode, project name interpolation, and `include(":app")`. Root plugins are aliases from `libs.versions.toml` with `apply false`.

- [ ] **Step 4: Generate pinned version catalog**

Define plugin aliases for Android application, Kotlin Android, Kotlin Compose if required by the selected Kotlin toolchain, Kotlin serialization, KSP, and Hilt. Define libraries for every stack item in Global Constraints using exact stable versions or BOM-managed coordinates.

- [ ] **Step 5: Generate `app/build.gradle.kts`**

Configure:

```text
namespace/applicationId from PackageName
compileSdk/targetSdk from parameters
minSdk default 26
Java/Kotlin target required by current AGP/Kotlin
buildFeatures.compose = true
Hilt plugin + KSP
Room compiler via KSP
Compose BOM
unit + instrumentation test dependencies
```

- [ ] **Step 6: Generate `gradle.properties` and ProGuard placeholder**

Use conventional AndroidX and Gradle settings only; do not add speculative performance flags.

- [ ] **Step 7: Run smoke tests**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: Gradle/configuration assertions PASS.

- [ ] **Step 8: Commit**

```bash
git add new-android-project.ps1 test-generator.ps1
git commit -m "feat: generate Android Gradle configuration"
```

### Task 4: Generate Manifest, Resources, and Compose/Hilt Application Skeleton

**Files:**
- Modify: `new-android-project.ps1`
- Modify: `test-generator.ps1`
- Generated: manifest/resources and Kotlin files listed in File Map.

**Interfaces:**
- Consumes: validated project/package names.
- Produces: compilable generic app with `App`, `MainActivity`, Material theme, Hilt ViewModel, and Home UI state.

- [ ] **Step 1: Add failing source-content assertions**

Verify all generated Kotlin files begin with the requested package and that no file contains `com.example.starter` unless that exact package was requested.

Verify manifest declares:

```xml
android:name=".App"
android:exported="true"
```

for the application and launcher activity respectively.

- [ ] **Step 2: Run tests and verify failure**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: FAIL on missing Android source files.

- [ ] **Step 3: Generate `App.kt` and `MainActivity.kt`**

`App.kt`:

```kotlin
@HiltAndroidApp
class App : Application()
```

`MainActivity.kt` must use `@AndroidEntryPoint`, `enableEdgeToEdge()`, `setContent`, the generated theme, and `AppNavHost()`.

- [ ] **Step 4: Generate Home state/ViewModel/screen**

Use:

```kotlin
data class HomeUiState(val title: String)
```

and a Hilt ViewModel exposing immutable `StateFlow<HomeUiState>`. `HomeScreen` collects via `collectAsStateWithLifecycle()` and renders only the project title in a simple Material 3 surface/layout.

- [ ] **Step 5: Generate minimal theme**

Generate `Color.kt`, `Type.kt`, and `Theme.kt` without custom brand styling. Support light/dark system theme using Material 3.

- [ ] **Step 6: Generate manifest/resources**

Create `strings.xml`, `themes.xml`, and manifest. The displayed app label must be `ProjectName`.

- [ ] **Step 7: Generate `.gitkeep` only for genuinely empty architecture folders**

Keep placeholders for `data/local`, `data/remote`, `data/repository`, `domain/model`, `domain/repository`, `domain/usecase`, `presentation/components`, and `di`.

- [ ] **Step 8: Run smoke tests**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: source/resource assertions PASS.

- [ ] **Step 9: Commit**

```bash
git add new-android-project.ps1 test-generator.ps1
git commit -m "feat: generate Compose Hilt application skeleton"
```

### Task 5: Generate Type-Safe Navigation Compose 2.x Skeleton

**Files:**
- Modify: `new-android-project.ps1`
- Modify: `test-generator.ps1`
- Generated: `presentation/navigation/Destination.kt`, `presentation/navigation/AppNavHost.kt`

**Interfaces:**
- Consumes: Navigation Compose 2.x and Kotlin serialization dependencies from Task 3; `HomeScreen` from Task 4.
- Produces: `@Serializable data object Home` and `AppNavHost()` using `rememberNavController`, `NavHost`, and `composable<Home>`.

- [ ] **Step 1: Add failing navigation assertions**

Assert generated files contain:

```kotlin
@Serializable
data object Home
```

and:

```kotlin
NavHost(
composable<Home>
```

Assert they do not import `androidx.navigation3`.

- [ ] **Step 2: Run tests and verify failure**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: FAIL on missing navigation files.

- [ ] **Step 3: Generate destination and nav host**

`Destination.kt` defines only the Home route. `AppNavHost.kt` creates/accepts a `NavHostController`, uses Home as `startDestination`, and renders `HomeScreen`.

- [ ] **Step 4: Run smoke tests**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: navigation assertions PASS.

- [ ] **Step 5: Commit**

```bash
git add new-android-project.ps1 test-generator.ps1
git commit -m "feat: add type-safe Navigation Compose skeleton"
```

### Task 6: Add Test Skeleton, Git Initialization, Wrapper Handling, and Build Verification

**Files:**
- Modify: `new-android-project.ps1`
- Modify: `test-generator.ps1`
- Generated: `app/src/test/<package>/StarterUnitTest.kt`

**Interfaces:**
- Consumes: generated project from Tasks 2–5.
- Produces: test source, optional new Git repository, optional Gradle wrapper, and build result.

- [ ] **Step 1: Add failing tests for optional switches**

Verify `-SkipGit` does not create `.git`. Verify `-SkipBuild` does not attempt a build. Verify generated `StarterUnitTest.kt` exists in the requested package.

- [ ] **Step 2: Run tests and verify failure**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: FAIL on missing optional behavior/test source.

- [ ] **Step 3: Generate trivial JVM unit test**

Generate a package-correct JUnit test that proves the test source set is wired, without testing business logic.

- [ ] **Step 4: Implement optional Git initialization**

Unless `-SkipGit` is specified, invoke `git init` only when `git` is available. If Git is unavailable, print a warning rather than fail project generation.

- [ ] **Step 5: Implement Gradle wrapper strategy**

If `gradle` exists globally and no wrapper exists, run:

```powershell
gradle wrapper --gradle-version 9.6.0
```

Do not download or embed `gradle-wrapper.jar` manually.

- [ ] **Step 6: Implement build verification**

Unless `-SkipBuild` is specified:

```powershell
./gradlew.bat assembleDebug
```

when a wrapper was created; otherwise use global `gradle assembleDebug` when available. If neither is available, print explicit Android Studio sync/build instructions and finish generation with a warning.

- [ ] **Step 7: Preserve project on build failure**

On non-zero Gradle exit, print the command and exit code; do not delete generated files.

- [ ] **Step 8: Run smoke tests**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Expected: all black-box generator tests PASS.

- [ ] **Step 9: Commit**

```bash
git add new-android-project.ps1 test-generator.ps1
git commit -m "feat: add generator verification workflow"
```

### Task 7: End-to-End Generate and Compile a Real Sample Project

**Files:**
- No product code changes unless verification exposes an issue.
- Temporary output: a generated sample such as `build-test/NewsReader`.

**Interfaces:**
- Consumes: completed generator.
- Produces: evidence that the generated project configures and compiles using the pinned latest-stable dependency set.

- [ ] **Step 1: Generate a clean sample**

```powershell
pwsh -NoProfile -File ./new-android-project.ps1 `
  -ProjectName NewsReader `
  -PackageName com.example.newsreader `
  -Destination ./build-test `
  -SkipGit
```

- [ ] **Step 2: Verify timestamps are newly created**

Inspect representative generated files and confirm their filesystem creation/write times correspond to this generator invocation rather than copied template files.

- [ ] **Step 3: Run Android build**

From the generated project:

```powershell
./gradlew.bat assembleDebug
```

or the equivalent global Gradle command when no wrapper is available.

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Run JVM tests**

```powershell
./gradlew.bat testDebugUnitTest
```

Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 5: If build fails, fix only the incompatibility exposed and rerun both commands**

Do not weaken the version policy by silently downgrading to older remembered dependencies. Re-check official compatibility/release notes and select the newest stable mutually compatible set.

- [ ] **Step 6: Commit verified compatibility fixes**

```bash
git add new-android-project.ps1 test-generator.ps1 README.md
git commit -m "fix: verify generated Android project build"
```

### Task 8: Write Usage and Maintenance Documentation

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: final generator CLI and behavior.
- Produces: concise instructions sufficient to use and update the generator without reading its implementation.

- [ ] **Step 1: Document primary command**

```powershell
.\new-android-project.ps1 `
    -ProjectName "NewsReader" `
    -PackageName "com.example.newsreader"
```

- [ ] **Step 2: Document all CLI parameters and defaults**

Explain `MinSdk`, `CompileSdk`, `TargetSdk`, `Destination`, `SkipBuild`, and `SkipGit`, including overwrite refusal.

- [ ] **Step 3: Document generated architecture and intentional omissions**

State explicitly that Retrofit/Room are dependencies only and that no API, DAO, database, repository, use case, or business model is generated.

- [ ] **Step 4: Document latest-stable version maintenance policy**

Before an interview or practice session, version updates must be verified from official release pages and followed by a full sample generation + `assembleDebug` + unit-test run.

- [ ] **Step 5: Document interview transparency note**

State that the script is generic personal scaffolding and should be used only when the assignment rules permit pre-existing tooling.

- [ ] **Step 6: Run final verification**

```powershell
pwsh -NoProfile -File ./test-generator.ps1
```

Then regenerate a fresh sample and run `assembleDebug` and `testDebugUnitTest` one final time.

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "docs: document Android project generator"
```

---

## Final Acceptance Checklist

- [ ] One PowerShell command creates a new project from zero files.
- [ ] Every output file has been written during that invocation.
- [ ] Package name and namespace are correct everywhere.
- [ ] Version catalog contains exact pinned latest-stable versions only.
- [ ] Navigation is Navigation Compose 2.x with type-safe serializable routes.
- [ ] Compose/Hilt/ViewModel/Lifecycle wiring compiles.
- [ ] Retrofit/Room/Coroutines dependencies are immediately available but unused until the task needs them.
- [ ] No feature-specific business logic is generated.
- [ ] Generator smoke tests pass.
- [ ] Fresh generated sample passes `assembleDebug`.
- [ ] Fresh generated sample passes `testDebugUnitTest`.
- [ ] README explains update and interview-safe usage.
