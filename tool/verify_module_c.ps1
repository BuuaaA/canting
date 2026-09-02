param(
  [switch]$SkipTests,
  [switch]$SkipIOSBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$logDirectory = Join-Path $projectRoot "build/module_c_verification"
$logPath = Join-Path $logDirectory "latest.log"

New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
Set-Content -Encoding UTF8 -Path $logPath -Value (
  "Module C verification started: $(Get-Date -Format o)"
)
Push-Location $projectRoot

function Write-ProgressLine {
  param([string]$Message)

  $line = "[$(Get-Date -Format HH:mm:ss)] $Message"
  Write-Host $line
  Add-Content -Encoding UTF8 -Path $logPath -Value $line
}

function Invoke-ExternalStep {
  param(
    [string]$Name,
    [scriptblock]$Command
  )

  Write-ProgressLine "START $Name"
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    & $Command 2>&1 | ForEach-Object {
      $line = if ($_ -is [System.Management.Automation.ErrorRecord]) {
        $_.Exception.Message
      } else {
        $_.ToString()
      }
      Write-Host $line
      Add-Content -Encoding UTF8 -Path $logPath -Value $line
    }
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  if ($exitCode -ne 0) {
    throw "$Name failed with exit code $exitCode"
  }
  Write-ProgressLine "PASS  $Name"
}

function Assert-Condition {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

try {
  Write-ProgressLine "START native configuration checks"

  $requiredFiles = @(
    "ios/Runner/CantingNativeBridge.swift",
    "ios/Runner/Runner.entitlements",
    "ios/CantingShareExtension/ShareViewController.swift",
    "ios/CantingShareExtension/OCRService.swift",
    "ios/CantingShareExtension/CantingShareExtension.entitlements",
    "ios/CantingWidget/CantingWidget.swift",
    "ios/CantingWidget/PetWidgetEntryView.swift",
    "ios/CantingWidget/CantingWidget.entitlements",
    "ios/Runner.xcodeproj/project.pbxproj"
  )
  foreach ($path in $requiredFiles) {
    Assert-Condition (Test-Path $path) "Missing required file: $path"
  }

  $appGroup = "group.com.canting.shared"
  $entitlements = @(
    "ios/Runner/Runner.entitlements",
    "ios/CantingShareExtension/CantingShareExtension.entitlements",
    "ios/CantingWidget/CantingWidget.entitlements"
  )
  foreach ($path in $entitlements) {
    [xml]$xml = Get-Content -Raw -Encoding UTF8 $path
    Assert-Condition ($xml.OuterXml.Contains($appGroup)) (
      "App Group $appGroup is missing from $path"
    )
  }

  $plistPaths = @(
    "ios/Runner/Info.plist",
    "ios/CantingShareExtension/Info.plist",
    "ios/CantingWidget/Info.plist"
  )
  foreach ($path in $plistPaths) {
    [xml](Get-Content -Raw -Encoding UTF8 $path) | Out-Null
  }

  $project = Get-Content -Raw -Encoding UTF8 (
    "ios/Runner.xcodeproj/project.pbxproj"
  )
  foreach ($marker in @(
    "CantingShareExtension.appex in Embed App Extensions",
    "CantingWidget.appex in Embed App Extensions",
    "CantingNativeBridge.swift in Sources",
    "dishes.json in Resources",
    "Assets.xcassets in Resources"
  )) {
    Assert-Condition ($project.Contains($marker)) (
      "Xcode project marker is missing: $marker"
    )
  }

  Get-Content -Raw -Encoding UTF8 "assets/data/dishes.json" |
    ConvertFrom-Json | Out-Null
  Get-Content -Raw -Encoding UTF8 (
    "ios/CantingWidget/Assets.xcassets/pet_placeholder.imageset/Contents.json"
  ) | ConvertFrom-Json | Out-Null
  Write-ProgressLine "PASS  native configuration checks"

  Invoke-ExternalStep "flutter pub get" { flutter pub get }
  Invoke-ExternalStep "dart format check" {
    dart format --output=none --set-exit-if-changed lib test
  }
  Invoke-ExternalStep "flutter analyze" { flutter analyze }

  if (-not $SkipTests) {
    Invoke-ExternalStep "flutter test" { flutter test --reporter compact }
  } else {
    Write-ProgressLine "SKIP  flutter test"
  }

  $isMacOSHost = $PSVersionTable.PSEdition -eq "Core" -and $IsMacOS
  if ($isMacOSHost -and -not $SkipIOSBuild) {
    Invoke-ExternalStep "iOS simulator build" {
      flutter build ios --simulator --debug
    }
  } else {
    Write-ProgressLine "SKIP  iOS build (requires macOS and Xcode)"
  }

  Write-ProgressLine "SUCCESS Module C verification completed"
} catch {
  Write-ProgressLine "FAILED $($_.Exception.Message)"
  throw
} finally {
  Pop-Location
}
