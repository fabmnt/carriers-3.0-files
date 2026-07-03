$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$ComposeUrl = 'https://github.com/fabmnt/carriers-3.0-files/releases/download/compose-1.0/docker-compose.yml'
$ComposeProjectName = 'carriers'
$ComposeFile = Join-Path ([System.IO.Path]::GetTempPath()) ("docker-compose-{0}.yml" -f [Guid]::NewGuid().ToString('N'))
$DockerInstallerUrl = 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'
$DockerInstallerFile = Join-Path ([System.IO.Path]::GetTempPath()) ("docker-desktop-installer-{0}.exe" -f [Guid]::NewGuid().ToString('N'))

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-PathForDocker {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $dockerCliPaths = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Docker\Docker\resources\bin'),
        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin')
    )

    $env:Path = "$machinePath;$userPath;$env:Path"
    foreach ($dockerCliPath in $dockerCliPaths) {
        if ((Test-Path $dockerCliPath) -and ($env:Path -notlike "*$dockerCliPath*")) {
            $env:Path = "$dockerCliPath;$env:Path"
        }
    }
}

function Test-WslReady {
    if (-not (Test-Command wsl)) {
        return $false
    }

    try {
        wsl --version *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Assert-WslReady {
    if (Test-WslReady) {
        Write-Host 'WSL is already installed.'
        wsl --set-default-version 2 *> $null
        return
    }

    if (-not (Test-IsAdministrator)) {
        throw 'WSL 2 is not ready. Run this script from an elevated PowerShell session so Windows can enable or update WSL.'
    }

    Write-Host 'Installing WSL without a Linux distribution...'
    wsl --install --no-distribution
    $wslInstallExitCode = $LASTEXITCODE
    if ($wslInstallExitCode -eq 3010) {
        throw 'WSL was installed, but Windows requires a restart before Docker can be installed. Restart Windows, then run this script again.'
    }
    if ($wslInstallExitCode -ne 0) {
        throw "WSL installation failed with exit code $wslInstallExitCode."
    }

    Write-Host 'Updating WSL...'
    wsl --update
    if ($LASTEXITCODE -ne 0) {
        throw "WSL update failed with exit code $LASTEXITCODE."
    }

    wsl --set-default-version 2 *> $null

    if (-not (Test-WslReady)) {
        throw 'WSL was installed or updated, but it is not ready yet. Restart Windows, then run this script again.'
    }
}

function Install-Docker {
    if (Test-Command docker) {
        return
    }

    Write-Host "Downloading Docker Desktop installer to $DockerInstallerFile..."
    Invoke-WebRequest -Uri $DockerInstallerUrl -OutFile $DockerInstallerFile -UseBasicParsing

    Write-Host 'Installing Docker Desktop with WSL 2 backend...'
    $installArgs = @('install', '--quiet', '--accept-license', '--backend=wsl-2', '--user')
    $process = Start-Process -FilePath $DockerInstallerFile -ArgumentList $installArgs -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Docker Desktop installation failed with exit code $($process.ExitCode)."
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
    $dockerDesktopPaths = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Docker\Docker\Docker Desktop.exe')
    )

    foreach ($dockerDesktop in $dockerDesktopPaths) {
        if (Test-Path $dockerDesktop) {
            Start-Process -FilePath $dockerDesktop -WindowStyle Hidden | Out-Null
            return
        }
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
    if (-not (Test-Command docker)) {
        Assert-WslReady
    }

    Install-Docker
    Wait-DockerReady

    Write-Host "Downloading compose file to $ComposeFile..."
    Invoke-WebRequest -Uri $ComposeUrl -OutFile $ComposeFile -UseBasicParsing

    Write-Host 'Pulling Docker images...'
    docker compose -p $ComposeProjectName -f $ComposeFile pull
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose pull failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Starting services in detached mode...'
    docker compose -p $ComposeProjectName -f $ComposeFile up -d
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose up failed with exit code $LASTEXITCODE."
    }

    Write-Host 'Services started successfully.'
}
finally {
    if (Test-Path $ComposeFile) {
        Remove-Item -LiteralPath $ComposeFile -Force
    }
    if (Test-Path $DockerInstallerFile) {
        Remove-Item -LiteralPath $DockerInstallerFile -Force
    }
}
