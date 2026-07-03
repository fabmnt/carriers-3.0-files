$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$ComposeUrl = 'https://github.com/fabmnt/carriers-3.0-files/releases/download/compose-1.0/docker-compose.yml'
$ComposeFile = Join-Path ([System.IO.Path]::GetTempPath()) ("docker-compose-{0}.yml" -f [Guid]::NewGuid().ToString('N'))

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-PathForDocker {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $dockerCliPath = Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'

    $env:Path = "$machinePath;$userPath;$env:Path"
    if ((Test-Path $dockerCliPath) -and ($env:Path -notlike "*$dockerCliPath*")) {
        $env:Path = "$dockerCliPath;$env:Path"
    }
}

function Install-Docker {
    if (Test-Command docker) {
        return
    }

    if (-not (Test-Command winget)) {
        throw 'Docker is not installed and winget was not found. Install Docker Desktop, then run this script again.'
    }

    Write-Host 'Docker was not found. Installing Docker Desktop with winget...'
    winget install --id Docker.DockerDesktop --exact --source winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop installation failed with exit code $LASTEXITCODE."
    }

    Update-PathForDocker

    if (-not (Test-Command docker)) {
        throw 'Docker Desktop was installed, but the docker command is not available yet. Restart this PowerShell session and run the script again.'
    }
}

function Test-DockerReady {
    try {
        docker info *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Start-DockerDesktop {
    $dockerDesktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $dockerDesktop) {
        Start-Process -FilePath $dockerDesktop -WindowStyle Hidden | Out-Null
    }
}

function Wait-DockerReady {
    param([int]$TimeoutSeconds = 300)

    if (Test-DockerReady) {
        return
    }

    Start-DockerDesktop
    Write-Host 'Waiting for Docker to start...'

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        if (Test-DockerReady) {
            return
        }
    }

    throw "Docker is installed, but the Docker engine did not become ready within $TimeoutSeconds seconds. Start Docker Desktop and run this script again."
}

try {
    Install-Docker
    Wait-DockerReady

    Write-Host "Downloading compose file to $ComposeFile..."
    Invoke-WebRequest -Uri $ComposeUrl -OutFile $ComposeFile -UseBasicParsing

    Write-Host 'Pulling Docker images...'
    docker compose -f $ComposeFile pull
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose pull failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Starting services in detached mode...'
    docker compose -f $ComposeFile up -d
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Services started successfully.'
}
finally {
    if (Test-Path $ComposeFile) {
        Remove-Item -LiteralPath $ComposeFile -Force
    }
}
