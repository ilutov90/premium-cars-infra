<#
.SYNOPSIS
  Runs the backend (profile "worker") and the frontend on this laptop against the PRODUCTION database, so the
  automatic import reads guazi and autowini from this laptop's address. See docs/local-worker.md.

.DESCRIPTION
  1. checks the tools and that the backend and frontend are on origin/main (what production runs);
  2. asks the server (scripts/local-worker-info.sh) for the PostgreSQL and Vault addresses, the backend's AppRole
     login and settings, and refuses to go on while production still runs the automatic import itself;
  3. opens an SSH tunnel to PostgreSQL and Vault (nothing is published on the server);
  4. starts the backend (mvn spring-boot:run, profile worker: no Liquibase, no scheduled posts or other background
     jobs, only the automatic import) and the frontend (npm run dev) in two windows;
  5. stops all of it when you press Enter (or Ctrl+C) in this window.
  Secrets stay in these processes' environment only: nothing is written to disk.

.EXAMPLE
  .\scripts\local-worker.ps1
  .\scripts\local-worker.ps1 -Server deploy@62.83.40.12
#>
param(
    [string]$Server = 'deploy@62.83.40.12',
    [string]$InfraOnServer = '/opt/premium-cars/premium-cars-infra',
    [string]$Backend = (Join-Path $PSScriptRoot '..\..\premium-cars-backend'),
    [string]$Frontend = (Join-Path $PSScriptRoot '..\..\premium-cars-frontend'),
    [int]$DbPort = 15432,
    [int]$VaultPort = 18200
)

$ErrorActionPreference = 'Stop'

function Stop-Here([string]$Message) {
    Write-Host ''
    Write-Host "STOPPED: $Message" -ForegroundColor Red
    exit 1
}

function Wait-Port([int]$Port, [int]$Seconds) {
    for ($i = 0; $i -lt $Seconds; $i++) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $Port)
            $client.Close()
            return $true
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    return $false
}

function Stop-Tree($Process) {
    if ($Process -and -not $Process.HasExited) {
        & taskkill.exe /T /F /PID $Process.Id 2>$null | Out-Null
    }
}

# --- 1. tools and code ---------------------------------------------------------------------------------------------
foreach ($tool in 'ssh', 'git', 'java', 'mvn', 'npm') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Stop-Here "$tool was not found (PATH)" }
}
$Backend = (Resolve-Path $Backend).Path
$Frontend = (Resolve-Path $Frontend).Path
foreach ($port in $DbPort, $VaultPort, 8080, 3000) {
    if (Wait-Port $port 1) { Stop-Here "port $port is in use on this laptop: stop what uses it (a local backend, frontend or database?)" }
}
foreach ($repo in $Backend, $Frontend) {
    & git -C $repo fetch -q origin
    $head = (& git -C $repo rev-parse HEAD).Trim()
    $main = (& git -C $repo rev-parse origin/main).Trim()
    $dirty = (& git -C $repo status --porcelain)
    if ($head -ne $main -or $dirty) {
        Write-Host "$repo is not exactly origin/main (production runs origin/main)." -ForegroundColor Yellow
        Write-Host "  Run there: git checkout main; git pull   (and keep no local changes)" -ForegroundColor Yellow
        if ((Read-Host 'Type yes to go on anyway') -ne 'yes') { exit 1 }
    }
}

# --- 2. what the server says -------------------------------------------------------------------------------------
Write-Host "Asking $Server ..."
$raw = & ssh -o BatchMode=no $Server "$InfraOnServer/scripts/local-worker-info.sh"
if ($LASTEXITCODE -ne 0) { Stop-Here "the server did not answer: $raw" }
$info = @{}
foreach ($line in $raw) {
    $i = $line.IndexOf('=')
    if ($i -gt 0) { $info[$line.Substring(0, $i)] = $line.Substring($i + 1) }
}
if ($info.ERROR) { Stop-Here $info.ERROR }
if ($info.PROD_AUTO_IMPORT -ne 'false') {
    Stop-Here ("production still runs the automatic import itself. On the server: set AUTO_IMPORT_ENABLED=false in " +
        "$InfraOnServer/.env.prod, then ./scripts/prod.sh up -d (docs/local-worker.md, step 2).")
}
foreach ($key in 'PG_IP', 'VAULT_IP', 'ROLE_ID', 'SECRET_ID') {
    if (-not $info[$key]) { Stop-Here "the server did not give $key" }
}

$tunnel = $null
$backendWindow = $null
$frontendWindow = $null
try {
    # --- 3. SSH tunnel ----------------------------------------------------------------------------------------------
    Write-Host "Opening the tunnel: localhost:$DbPort -> PostgreSQL, localhost:$VaultPort -> Vault ..."
    $tunnel = Start-Process -FilePath 'ssh' -NoNewWindow -PassThru -ArgumentList @(
        '-N', '-o', 'ExitOnForwardFailure=yes', '-o', 'ServerAliveInterval=30',
        '-L', "127.0.0.1:${DbPort}:$($info.PG_IP):5432",
        '-L', "127.0.0.1:${VaultPort}:$($info.VAULT_IP):8200",
        $Server)
    if (-not (Wait-Port $DbPort 30) -or -not (Wait-Port $VaultPort 5)) { Stop-Here 'the SSH tunnel did not open' }

    # --- 4. backend and frontend (they inherit these variables; nothing is written to disk) -------------------------
    $env:SPRING_PROFILES_ACTIVE = 'worker'
    $env:VAULT_ADDR = "http://127.0.0.1:$VaultPort"
    $env:SPRING_CLOUD_VAULT_APPROLE_ROLEID = $info.ROLE_ID
    $env:SPRING_CLOUD_VAULT_APPROLE_SECRETID = $info.SECRET_ID
    $env:DB_URL = "jdbc:postgresql://127.0.0.1:$DbPort/premiumcars"
    $env:R2_ENDPOINT = $info.R2_ENDPOINT
    $env:R2_BUCKET = $info.R2_BUCKET
    $env:R2_PUBLIC_URL = $info.R2_PUBLIC_URL
    $env:APP_SITE_URL = $info.APP_SITE_URL
    $env:APP_NOTIFY_TO = $info.APP_NOTIFY_TO
    $env:APP_NOTIFY_FROM = $info.APP_NOTIFY_FROM
    $env:APP_SECURE_COOKIES = 'false'
    $env:APP_API_DOCS = 'false'
    $env:JAVA_TOOL_OPTIONS = '-Duser.timezone=Europe/Sofia'
    $env:API_URL = 'http://localhost:8080'
    $env:SITE_URL = 'http://localhost:3000'

    Write-Host 'Starting the backend (window "backend") ...'
    $backendWindow = Start-Process -FilePath 'powershell' -PassThru -ArgumentList @(
        '-NoExit', '-Command',
        "`$host.UI.RawUI.WindowTitle = 'backend (worker, PRODUCTION database)'; Set-Location '$Backend'; mvn spring-boot:run")

    Write-Host 'Starting the frontend (window "frontend") ...'
    $frontendWindow = Start-Process -FilePath 'powershell' -PassThru -ArgumentList @(
        '-NoExit', '-Command',
        ("`$host.UI.RawUI.WindowTitle = 'frontend'; Set-Location '$Frontend'; " +
            "if (-not (Test-Path node_modules)) { npm ci }; npm run dev"))

    Write-Host 'Waiting for the backend (the first start downloads dependencies, a few minutes) ...'
    $up = $false
    for ($i = 0; $i -lt 600 -and -not $up; $i += 5) {
        Start-Sleep -Seconds 5
        if ($backendWindow.HasExited) { Stop-Here 'the backend window closed' }
        try {
            $health = Invoke-RestMethod -Uri 'http://localhost:8080/actuator/health' -TimeoutSec 3
            $up = $health.status -eq 'UP'
        } catch { }
    }
    if (-not $up) { Stop-Here 'the backend did not start in 10 minutes: see its window' }

    Write-Host ''
    Write-Host 'READY' -ForegroundColor Green
    Write-Host '  Admin panel:  http://localhost:3000/admin/auto-import   (your usual login)'
    Write-Host '  The import runs from this laptop; keep it on and awake.'
    Write-Host '  Everything you change here changes PRODUCTION (same database).'
    Write-Host ''
    Read-Host 'Press Enter here to stop the backend, the frontend and the tunnel' | Out-Null
} finally {
    Write-Host 'Stopping ...'
    Stop-Tree $frontendWindow
    Stop-Tree $backendWindow
    Stop-Tree $tunnel
    Write-Host 'Stopped.'
}
