[CmdletBinding()]
param(
    [switch]$NoCommit
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RunnerPath = Join-Path $PSScriptRoot "verify_android_native.ps1"
$ReportRoot = Join-Path $ProjectRoot "build\reports\unattended"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$StdOutPath = Join-Path $ReportRoot "$Timestamp-runner.stdout.log"
$StdErrPath = Join-Path $ReportRoot "$Timestamp-runner.stderr.log"
$PidPath = Join-Path $ReportRoot "runner.pid"

New-Item -ItemType Directory -Force -Path $ReportRoot | Out-Null

$PowerShellPath = (Get-Process -Id $PID).Path
$RunnerArguments = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $RunnerPath
)
if (-not $NoCommit) {
    $RunnerArguments += "-Commit"
}

$Process = Start-Process `
    -FilePath $PowerShellPath `
    -ArgumentList $RunnerArguments `
    -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput $StdOutPath `
    -RedirectStandardError $StdErrPath `
    -PassThru

$Process.Id | Set-Content -Encoding ascii $PidPath

[ordered]@{
    process_id = $Process.Id
    status_file = Join-Path $ReportRoot "status.json"
    progress_log = Join-Path $ReportRoot "progress.log"
    stdout_log = $StdOutPath
    stderr_log = $StdErrPath
} | ConvertTo-Json
