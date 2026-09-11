# Android Interview Project Generator

A Windows-first PowerShell bootstrapper that creates a fresh single-module Android project entirely from generated files. It is intentionally limited to reusable infrastructure: build configuration, package structure, Hilt/Compose wiring, type-safe Navigation Compose 2.x, Material Icons, Coil image loading, and a minimal Home screen.

## Usage

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\new-android-project.ps1 `
  -ProjectName NewsReader `
  -PackageName com.example.newsreader
```

Useful options:

```text
-MinSdk 26
-CompileSdk 37
-TargetSdk 37
-Destination .
-SkipBuild
-SkipGit
-SkipWrapper
```

The generator refuses to overwrite a non-empty destination project.

## Dependency policy

Versions are pinned in the generated `gradle/libs.versions.toml`. This revision uses stable releases only and deliberately excludes alpha, beta, RC, snapshot, `+`, and floating versions. Before an interview or take-home exercise, re-check the official release pages and update the pinned matrix if a newer mutually compatible stable release exists.

The current baseline is built around AGP 9.4 with built-in Kotlin support, Gradle 9.6, API 37, Compose BOM 2026.09.00, Kotlin 2.4.20, Navigation Compose 2.10.1, Room 2.8.5, OkHttp 5.5.0, and Coil 3.6.2.

## Scope

Generated scaffolding includes `data`, `domain`, `presentation`, and `di` packages, but no task-specific API, DAO, repository, use case, domain model, cache, error wrapper, or feature implementation. This keeps the bootstrapper transparent and interview-safe: it automates repetitive setup rather than solving the assignment.

Use this script in an interview or take-home exercise only when the assignment rules allow pre-existing personal tooling/scaffolding. If asked, describe it openly as a generic bootstrapper and keep all task-specific implementation inside the exercise itself.

## Verification

Run the black-box smoke test with Windows PowerShell 5.1 or PowerShell 7+:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test-generator.ps1
```

For a full Android verification, generate without `-SkipBuild`. The generator always creates a Gradle 9.6 wrapper by default. If no global `gradle` command exists, it temporarily downloads the official Gradle 9.6 binary distribution, creates `gradlew`, `gradlew.bat`, `gradle-wrapper.jar`, and `gradle-wrapper.properties`, then removes the temporary bootstrap files. Use `-SkipWrapper` only for offline smoke testing or diagnostics.


## Java / JDK

The generator resolves Java in this order: `JAVA_HOME`, `java` on `PATH`, then the Android Studio bundled JBR. Gradle bootstrap and the generated project build run with that resolved Java home.


### PowerShell 5.1 note

The generator does not use `java -version` as a health check because Java writes version information to stderr; Windows PowerShell 5.1 can treat that normal diagnostic stream as an error when strict error handling is enabled. Gradle exit codes are used as the authoritative success/failure signal instead.


## Android SDK discovery

For normal builds the generator resolves the SDK in this order: `-AndroidSdkPath`, `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `%LOCALAPPDATA%\Android\Sdk`, `%USERPROFILE%\AppData\Local\Android\Sdk`. It verifies that the requested `compileSdk` platform is installed and writes a git-ignored `local.properties` automatically.

If your SDK is in a custom location:

```powershell
.\new-android-project.ps1 -ProjectName NewsReader -PackageName com.example.newsreader -AndroidSdkPath 'D:\Android\Sdk'
```
