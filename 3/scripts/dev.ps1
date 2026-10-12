<#
.SYNOPSIS
    Run the hello-rest service on a local minikube cluster (Windows PowerShell 5.1+ / PowerShell 7+).

.DESCRIPTION
    PowerShell twin of scripts/dev.sh - same commands, same config.env.

.EXAMPLE
    .\scripts\dev.ps1 all      # check + up + deploy + test + open
.EXAMPLE
    .\scripts\dev.ps1 help     # list all commands
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('all', 'check', 'up', 'build', 'deploy', 'test', 'open', 'status', 'logs', 'undeploy', 'down', 'destroy', 'help')]
    [string]$Command = 'help'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RootDir = Split-Path -Parent $PSScriptRoot

$Cfg = @{}
foreach ($line in Get-Content (Join-Path $RootDir 'config.env')) {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith('#') -or -not $line.Contains('=')) { continue }
    $key, $value = $line.Split('=', 2)
    $envValue = [Environment]::GetEnvironmentVariable($key.Trim())
    $Cfg[$key.Trim()] = if ($envValue) { $envValue } else { $value.Trim() }
}

$Profile_ = $Cfg.MINIKUBE_PROFILE
$Ns       = $Cfg.APP_NAMESPACE
$App      = $Cfg.APP_NAME
$Image    = "localhost:$($Cfg.REGISTRY_PORT)/$($App):$($Cfg.APP_VERSION)"
$Url      = "http://localhost:$($Cfg.LOCAL_PORT)/hello-world"
$K8sDir   = Join-Path $RootDir 'k8s'

function Step([string]$m) { Write-Host '==> ' -ForegroundColor Blue -NoNewline; Write-Host $m }
function Ok([string]$m)   { Write-Host '  [ok] ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn([string]$m) { Write-Host '  [warn] ' -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Fail([string]$m) { Write-Host '  [fail] ' -ForegroundColor Red -NoNewline; Write-Host $m }
function Die([string]$m)  { Fail $m; exit 1 }

# Ensure common installation directories are present in the current process PATH
$progFiles = if ($env:ProgramFiles) { $env:ProgramFiles } else { 'C:\Program Files' }
$progData  = if ($env:ProgramData)  { $env:ProgramData }  else { 'C:\ProgramData' }
$candidatePaths = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\minikube'),
    (Join-Path $progFiles 'Kubernetes\Minikube'),
    (Join-Path $progData 'chocolatey\bin')
)
foreach ($p in $candidatePaths) {
    if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
        $env:Path = "$p;$env:Path"
    }
}

function Have([string]$cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Invoke-Native {
    $exe = $args[0]
    [string[]]$rest = @()
    if ($args.Count -gt 1) {
        foreach ($item in $args[1..($args.Count - 1)]) {
            if ($item -is [System.Collections.IEnumerable] -and $item -isnot [string]) {
                foreach ($sub in $item) { $rest += "$sub" }
            } else {
                $rest += "$item"
            }
        }
    }
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { Die "'$exe $($rest -join ' ')' failed with exit code $LASTEXITCODE" }
}

function Mk { Invoke-Native minikube -p $Profile_ @args }

# kubectl, falling back to the version bundled with minikube.
function Kc {
    if (Have kubectl) { Invoke-Native kubectl --context $Profile_ @args }
    else              { Invoke-Native minikube -p $Profile_ kubectl -- @args }
}

function Test-ClusterRunning {
    $ErrorActionPreference = 'Continue'   # PS 5.1: redirected stderr must not throw
    $s = & minikube -p $Profile_ status --format '{{.Host}}/{{.APIServer}}' 2>$null
    return ($LASTEXITCODE -eq 0 -and "$s".Trim() -eq 'Running/Running')
}

function Assert-Cluster {
    if (-not (Test-ClusterRunning)) { Die "Minikube profile '$Profile_' is not running. Run: .\scripts\dev.ps1 up" }
}

function Invoke-Check {
    Step 'Checking required tooling'
    $ErrorActionPreference = 'Continue'   # PS 5.1: redirected stderr must not throw
    $errors = 0

    if (Have docker) {
        Ok ("docker CLI    " + (& docker version --format '{{.Client.Version}}' 2>$null))
        if ($Cfg.MINIKUBE_DRIVER -eq 'docker') {
            & docker info *> $null
            if ($LASTEXITCODE -eq 0) { Ok 'docker daemon running' }
            else { Fail 'docker daemon is not running (start Docker Desktop)'; $errors++ }
        }
    } else {
        Fail 'docker not found   -> https://docs.docker.com/get-docker/'; $errors++
    }

    if (Have minikube) {
        Ok ("minikube      " + (& minikube version --short 2>$null))
    } else {
        Fail 'minikube not found -> winget install Kubernetes.minikube  (https://minikube.sigs.k8s.io/docs/start/)'; $errors++
    }

    if (Have kubectl) {
        $v = (& kubectl version --client -o json 2>$null | ConvertFrom-Json).clientVersion.gitVersion
        Ok "kubectl       $v"
    } else {
        Warn "kubectl not found - falling back to 'minikube kubectl --' (winget install Kubernetes.kubectl)"
    }

    if ($errors -gt 0) { Die "$errors required tool(s) missing or not running." }
    Ok 'All required tooling present'
}

function Invoke-Up {
    Invoke-Check
    Step "Starting minikube profile '$Profile_'"
    if (Test-ClusterRunning) {
        Ok 'Already running'
    } else {
        Mk start "--driver=$($Cfg.MINIKUBE_DRIVER)" '--container-runtime=docker' `
            "--cpus=$($Cfg.MINIKUBE_CPUS)" "--memory=$($Cfg.MINIKUBE_MEMORY)" `
            "--kubernetes-version=$($Cfg.KUBERNETES_VERSION)"
    }

    Step 'Enabling local image registry addon'
    Mk addons enable registry | Out-Null
    Kc -n kube-system wait --for=condition=Ready pod -l kubernetes.io/minikube-addons=registry --timeout=180s | Out-Null
    Ok "Registry ready at localhost:$($Cfg.REGISTRY_PORT) (inside the cluster)"
}

function Invoke-Build {
    Assert-Cluster
    Step "Building and pushing $Image to the in-cluster registry"
    # Use minikube's own Docker daemon: the build runs inside the node, and from
    # there localhost:5000 is the registry addon (the same path the kubelet uses
    # to pull). No remote registry, no port-forward, no insecure-registry config.
    $vars = 'DOCKER_TLS_VERIFY', 'DOCKER_HOST', 'DOCKER_CERT_PATH', 'MINIKUBE_ACTIVE_DOCKERD'
    $saved = @{}
    foreach ($v in $vars) { $saved[$v] = [Environment]::GetEnvironmentVariable($v) }
    try {
        (& minikube -p $Profile_ docker-env --shell powershell) -join "`n" | Invoke-Expression
        Invoke-Native docker build `
            --build-arg "APP_VERSION=$($Cfg.APP_VERSION)" `
            --build-arg "APP_ZIP_URL=$($Cfg.APP_ZIP_URL)" `
            --build-arg "APP_ZIP_SHA256=$($Cfg.APP_ZIP_SHA256)" `
            -t $Image $RootDir
        Invoke-Native docker push $Image
    } finally {
        # Restore the caller's Docker environment (this script runs in-process).
        foreach ($v in $vars) { [Environment]::SetEnvironmentVariable($v, $saved[$v]) }
    }
    Ok "Pushed $Image"
}

function Invoke-Deploy {
    Invoke-Build
    Step 'Applying Kubernetes manifests (k8s/)'
    Kc apply -k $K8sDir
    # Keep the image in sync with APP_VERSION and force a fresh pull of the tag.
    Kc -n $Ns set image "deployment/$App" "$App=$Image" | Out-Null
    Kc -n $Ns rollout restart "deployment/$App" | Out-Null
    Kc -n $Ns rollout status "deployment/$App" --timeout=180s
    Ok 'Deployed'
}

function Start-PortForward([int]$LocalPort) {
    $exe, $pre = if (Have kubectl) { 'kubectl', @('--context', $Profile_) }
                 else { 'minikube', @('-p', $Profile_, 'kubectl', '--') }
    $argList = $pre + @('-n', $Ns, 'port-forward', "svc/$App", "$($LocalPort):80")
    $log = [IO.Path]::GetTempFileName()
    Start-Process -FilePath $exe -ArgumentList $argList -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err"
}

function Invoke-Test {
    Assert-Cluster
    Step 'Smoke-testing the service'
    $port = 18080
    $pf = Start-PortForward $port
    try {
        $resp = $null
        for ($i = 0; $i -lt 20 -and -not $resp; $i++) {
            try { $resp = Invoke-RestMethod -Uri "http://localhost:$port/hello-world" -TimeoutSec 2 }
            catch { Start-Sleep -Milliseconds 500 }
        }
        if (-not $resp) { Die 'No response from the service' }
        Write-Host "  response: $($resp | ConvertTo-Json -Compress)"
        if ("$($resp.message)" -match '^Hello World') { Ok 'Service returns the expected JSON' }
        else { Die 'Unexpected response' }
    } finally {
        Stop-Process -Id $pf.Id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Open {
    Assert-Cluster
    Step "Forwarding $Url  ->  svc/$App"
    Write-Host "  Try:  curl.exe $Url   (or Invoke-RestMethod $Url)"
    Write-Host '  Press Ctrl+C to stop.'
    Kc -n $Ns port-forward "svc/$App" "$($Cfg.LOCAL_PORT):80"
}

function Invoke-Status {
    Assert-Cluster
    Step 'Cluster'
    & minikube -p $Profile_ status
    Step "Resources in namespace $Ns"
    Kc -n $Ns get 'deploy,rs,pods,svc' -o wide
    Step 'Recent events'
    Kc -n $Ns get events --sort-by=.lastTimestamp
}

function Invoke-Logs     { Assert-Cluster; Kc -n $Ns logs -f "deployment/$App" --all-containers }
function Invoke-Undeploy { Assert-Cluster; Step 'Removing the application'; Kc delete -k $K8sDir --ignore-not-found }
function Invoke-Down     { Step "Stopping minikube profile '$Profile_' (state is kept)"; Mk stop }
function Invoke-Destroy  { Step "Deleting minikube profile '$Profile_'"; Mk delete }

function Invoke-All {
    Invoke-Up
    Invoke-Deploy
    Invoke-Test
    Invoke-Open
}

function Invoke-Help {
    @"
Usage: .\scripts\dev.ps1 <command>

  all        check + up + deploy + test + open   (start here)
  check      verify required tooling is installed / running
  up         start minikube (profile '$Profile_') and the local registry
  build      build the image and push it to the in-cluster registry
  deploy     build + push + kubectl apply -k k8s/ + wait for rollout
  test       call /hello-world through a temporary port-forward
  open       expose $Url (blocks, Ctrl+C to stop)
  status     show cluster and application state
  logs       follow application logs
  undeploy   remove the application, keep the cluster
  down       stop the cluster (fast restart with 'up')
  destroy    delete the cluster completely

Settings live in config.env and can be overridden by environment variables,
e.g.  `$env:LOCAL_PORT=9090; .\scripts\dev.ps1 open
"@ | Write-Host
}

switch ($Command) {
    'all'      { Invoke-All }
    'check'    { Invoke-Check }
    'up'       { Invoke-Up }
    'build'    { Invoke-Build }
    'deploy'   { Invoke-Deploy }
    'test'     { Invoke-Test }
    'open'     { Invoke-Open }
    'status'   { Invoke-Status }
    'logs'     { Invoke-Logs }
    'undeploy' { Invoke-Undeploy }
    'down'     { Invoke-Down }
    'destroy'  { Invoke-Destroy }
    default    { Invoke-Help }
}
