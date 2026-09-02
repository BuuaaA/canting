[CmdletBinding()]
param(
    [switch]$Commit,
    [string]$CommitMessage = "feat: add Android share OCR and widgets"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ReportRoot = Join-Path $ProjectRoot "build\reports\unattended"
$StatusPath = Join-Path $ReportRoot "status.json"
$ProgressPath = Join-Path $ReportRoot "progress.log"
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"

New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

if (-not $env:JAVA_HOME) {
    $AndroidStudioJdk = "C:\Program Files\Android\Android Studio\jbr"
    if (Test-Path $AndroidStudioJdk) {
        $env:JAVA_HOME = $AndroidStudioJdk
    }
}

function Write-WorkflowStatus {
    param(
        [string]$Stage,
        [string]$State,
        [string]$Message
    )

    $Timestamp = (Get-Date).ToString("o")
    [ordered]@{
        run_id = $RunId
        timestamp = $Timestamp
        stage = $Stage
        state = $State
        message = $Message
        project_root = $ProjectRoot
    } | ConvertTo-Json | Set-Content -Encoding utf8 $StatusPath

    "$Timestamp`t$State`t$Stage`t$Message" |
        Add-Content -Encoding utf8 $ProgressPath
}

function Invoke-WorkflowStage {
    param(
        [string]$Name,
        [string]$Command,
        [string[]]$Arguments,
        [string]$WorkingDirectory = $ProjectRoot,
        [int]$Attempts = 1
    )

    $StageLog = Join-Path $ReportRoot "$RunId-$Name.log"
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        Write-WorkflowStatus $Name "running" "Attempt $Attempt of $Attempts"
        Push-Location $WorkingDirectory
        $PreviousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            & $Command @Arguments *>> $StageLog
            $ExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $PreviousErrorActionPreference
            Pop-Location
        }

        if ($ExitCode -eq 0) {
            Write-WorkflowStatus $Name "passed" "Completed successfully"
            return
        }

        if ($Attempt -lt $Attempts) {
            Write-WorkflowStatus $Name "retrying" "Exit code $ExitCode"
            Start-Sleep -Seconds ([Math]::Min(30, 5 * $Attempt))
        }
    }

    throw "Stage '$Name' failed after $Attempts attempt(s). See $StageLog"
}

try {
    Write-WorkflowStatus "startup" "running" "Starting Android native verification"
    Invoke-WorkflowStage "flutter-pub-get" "flutter" @("pub", "get") -Attempts 3
    Invoke-WorkflowStage "dart-format-check" "dart" @(
        "format",
        "--output=none",
        "--set-exit-if-changed",
        "lib",
        "test"
    )
    Invoke-WorkflowStage "flutter-analyze" "flutter" @("analyze")
    Invoke-WorkflowStage "flutter-test" "flutter" @("test")
    Invoke-WorkflowStage "android-unit-test" ".\gradlew.bat" @(
        ":app:testDebugUnitTest"
    ) -WorkingDirectory (Join-Path $ProjectRoot "android")
    Invoke-WorkflowStage "debug-apk" "flutter" @(
        "build",
        "apk",
        "--debug"
    ) -Attempts 2

    if ($Commit) {
        $GitUserName = & git -C $ProjectRoot config --get user.name
        if (-not $GitUserName) {
            Invoke-WorkflowStage "git-user-name" "git" @(
                "config",
                "--local",
                "user.name",
                "Canting Automation"
            )
        }
        $GitUserEmail = & git -C $ProjectRoot config --get user.email
        if (-not $GitUserEmail) {
            Invoke-WorkflowStage "git-user-email" "git" @(
                "config",
                "--local",
                "user.email",
                "canting@local.invalid"
            )
        }
        Invoke-WorkflowStage "git-add" "git" @("add", "--all")
        $PendingChanges = & git -C $ProjectRoot diff --cached --name-only
        if ($LASTEXITCODE -ne 0) {
            throw "Could not inspect staged Git changes"
        }
        if ($PendingChanges) {
            Invoke-WorkflowStage "git-commit" "git" @(
                "commit",
                "-m",
                $CommitMessage
            )
        }
        else {
            Write-WorkflowStatus "git-commit" "passed" "No changes to commit"
        }
    }

    Write-WorkflowStatus "complete" "passed" "All verification stages passed"
    exit 0
}
catch {
    Write-WorkflowStatus "failed" "failed" $_.Exception.Message
    Write-Error $_
    exit 1
}
