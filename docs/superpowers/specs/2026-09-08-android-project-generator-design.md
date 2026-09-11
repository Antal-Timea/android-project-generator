# Android Project Generator — Design

## Goal

Create a reusable PowerShell bootstrap script that generates a fresh, buildable Android project from scratch for interview exercises and practice projects.

The generated project must contain only generic infrastructure and boilerplate. It must not include task-specific business logic, API models, repositories, use cases, or feature implementations.

## Primary Use Case

From a terminal on Windows:

```powershell
.\new-android-project.ps1 `
    -ProjectName "NewsReader" `
    -PackageName "com.example.newsreader"
```

The script creates a new directory named after the project and generates every project file during that invocation.

## Constraints

- Windows-first workflow using PowerShell.
- Generated project must open directly in Android Studio.
- Generated project must be buildable immediately after Gradle sync.
- Use a single `:app` module.
- Prefer simple, conventional Android architecture over framework-heavy abstractions.
- Avoid application-specific implementation.
- Avoid `BaseViewModel`, `BaseRepository`, generic result wrappers, custom MVI frameworks, and unnecessary abstraction layers.
- Package and project names must be configurable.
- All generated source files must use the requested package name.
- Script should be readable enough to explain during an interview.

## Generated Architecture

```text
<ProjectName>/
├── app/
│   ├── build.gradle.kts
│   ├── proguard-rules.pro
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml
│       │   ├── java/<package path>/
│       │   │   ├── App.kt
│       │   │   ├── MainActivity.kt
│       │   │   ├── data/
│       │   │   │   ├── local/
│       │   │   │   ├── remote/
│       │   │   │   └── repository/
│       │   │   ├── domain/
│       │   │   │   ├── model/
│       │   │   │   ├── repository/
│       │   │   │   └── usecase/
│       │   │   ├── presentation/
│       │   │   │   ├── navigation/
│       │   │   │   │   ├── AppNavHost.kt
│       │   │   │   │   └── Destination.kt
│       │   │   │   ├── home/
│       │   │   │   │   ├── HomeScreen.kt
│       │   │   │   │   ├── HomeUiState.kt
│       │   │   │   │   └── HomeViewModel.kt
│       │   │   │   ├── components/
│       │   │   │   └── theme/
│       │   │   │       ├── Color.kt
│       │   │   │       ├── Theme.kt
│       │   │   │       └── Type.kt
│       │   │   └── di/
│       │   └── res/
│       │       ├── values/
│       │       │   ├── strings.xml
│       │       │   └── themes.xml
│       │       └── xml/
│       ├── test/
│       └── androidTest/
├── gradle/
│   └── libs.versions.toml
├── build.gradle.kts
├── settings.gradle.kts
├── gradle.properties
├── .gitignore
└── README.md
```

Empty package directories may need `.gitkeep` files because empty folders are not retained by Git. The generated project itself does not depend on them at runtime.

## Technology Stack

The script will configure current mutually compatible versions of:

- Kotlin
- Android Gradle Plugin
- Jetpack Compose
- Compose BOM
- Material 3
- Navigation Compose
- Lifecycle Runtime Compose
- ViewModel Compose
- Hilt
- Hilt Navigation Compose
- KSP
- Kotlin Coroutines
- Retrofit
- OkHttp
- kotlinx.serialization
- Retrofit kotlinx.serialization converter
- Room
- JUnit
- MockK
- Turbine
- AndroidX test libraries
- Compose UI test libraries

Dependencies will be centralized in `gradle/libs.versions.toml`.

Version policy:

- Use the latest **stable** release available at generation-tool implementation time for every dependency and build tool.
- Verify versions against official Android Developers, Google Maven, JetBrains, or the library maintainer's official release documentation rather than relying on model memory.
- Do not use alpha, beta, RC, snapshot, dynamic (`+`), or floating versions unless explicitly requested.
- Use Navigation Compose 2.x (latest stable 2.x) as the default navigation stack, with type-safe `@Serializable` routes.
- Keep the selected versions mutually compatible and validate them with a real `assembleDebug` build before considering the generator complete.

## Generated Application Skeleton

### Application

`App.kt` contains only the Hilt application setup:

```kotlin
@HiltAndroidApp
class App : Application()
```

### MainActivity

`MainActivity`:

- uses `@AndroidEntryPoint`
- extends `ComponentActivity`
- enables edge-to-edge rendering
- calls `setContent`
- applies the generated Compose theme
- hosts `AppNavHost`

### Navigation

The initial navigation setup contains a single generic `Home` destination.

The navigation layer exists to prove that Navigation Compose is wired correctly, but does not contain task-specific flows.

The structure is designed so a `Detail` or other route can be added immediately during an exercise.

### Home Feature

The home feature is intentionally minimal:

- `HomeUiState` — simple immutable state model
- `HomeViewModel` — `@HiltViewModel` with a `StateFlow`
- `HomeScreen` — collects state using `collectAsStateWithLifecycle`

The UI displays only a basic placeholder such as the generated project name.

This validates Hilt + ViewModel + Compose + lifecycle integration without implementing business logic.

## Dependency Injection

No concrete network/database modules are generated initially because there are no concrete APIs, DAOs, or repositories yet.

The `di/` package is created as a placeholder for future modules.

This avoids creating unused or artificial abstractions while keeping the intended package structure visible.

## Retrofit and Room

Retrofit, OkHttp, serialization, and Room dependencies are included but no API service or database is generated.

Rationale:

- creating a fake `ApiService` adds noise
- creating an empty Room database provides no value
- the dependencies are immediately available when the interview task requires them
- task-specific persistence/network code should be written during the exercise

## Script Responsibilities

`new-android-project.ps1` will:

1. Validate `ProjectName`.
2. Validate `PackageName` as a Java/Kotlin-style package name.
3. Refuse to overwrite an existing non-empty destination by default.
4. Convert the package to a folder path.
5. Create all directories.
6. Generate Gradle settings and build files.
7. Generate the version catalog.
8. Generate Android resources and manifest.
9. Generate the Kotlin application skeleton.
10. Generate test directories and basic smoke/unit tests where useful.
11. Create a project-local README.
12. Optionally initialize Git.
13. Optionally generate or copy a Gradle wrapper.
14. Optionally run `assembleDebug` as verification.
15. Print a concise completion summary and next commands.

## Script Parameters

Minimum required parameters:

```powershell
-ProjectName
-PackageName
```

Useful optional parameters:

```powershell
-MinSdk 26
-TargetSdk <current stable>
-CompileSdk <current stable>
-Destination .
-SkipBuild
-SkipGit
```

Defaults should favor the interview/practice workflow and minimize required typing.

## Gradle Wrapper Strategy

A completely standalone generator cannot reliably create `gradle-wrapper.jar` from plain text.

Preferred behavior:

1. If `gradle` is installed globally, run `gradle wrapper` in the generated project.
2. Otherwise generate all project files and clearly instruct the user to open the project in Android Studio, which can sync using its configured Gradle environment.
3. The script must not silently download arbitrary binaries.

A later optional enhancement may allow supplying a known local Gradle wrapper template path.

## Error Handling

The script should fail early with clear messages for:

- invalid package names
- invalid project names
- destination already exists
- unsupported PowerShell environment
- file write failures
- Gradle verification failure

Build failure must not delete the generated project. The script should leave it in place and print the failing command and exit code.

## Testing Strategy

### Generator Tests

Where practical, a lightweight PowerShell smoke-test script will:

- generate a project in a temporary directory
- verify important files exist
- verify package declarations were substituted correctly
- verify namespace/applicationId values
- verify no starter placeholder package remains

### Android Project Verification

When Gradle is available:

```text
assembleDebug
```

is the minimum acceptance check.

The starter should also include one trivial JVM unit test to prove the test configuration works.

## Interview Safety / Transparency

The generator provides only generic setup and infrastructure. It deliberately does not generate:

- domain models
- API contracts
- real repositories
- feature-specific use cases
- actual screen designs
- task-specific navigation
- caching strategy
- error mapping
- business rules

This keeps the distinction clear between a reusable development tool and the solution to an interview assignment.

The user should still follow the interviewer's rules regarding external tools and pre-existing scaffolding.

## Success Criteria

The design is successful when:

1. One PowerShell command creates a fresh Android project.
2. Every generated project file is created during that run.
3. The requested package name appears consistently everywhere.
4. Android Studio can import and sync the project.
5. Hilt, Compose, Navigation, Room, Retrofit, Coroutines, and test dependencies are already configured.
6. The app starts on a minimal Home screen.
7. Hilt-injected `HomeViewModel` works.
8. No feature-specific solution is preimplemented.
9. The generated project is simple enough to understand and modify quickly during a senior Android interview.
