$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Local Background Remover"

Set-Location $PSScriptRoot

$Port = 5000
$LocalUrl = "http://127.0.0.1:$Port"
$VenvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
$env:PYTHONUTF8 = "1"
$env:PYTHONIOENCODING = "utf-8"

function Write-Step($Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Find-Python {
    $candidates = @(
        @{ Command = "py"; Args = @("-3.11") },
        @{ Command = "py"; Args = @("-3.12") },
        @{ Command = "python"; Args = @() },
        @{ Command = "python3"; Args = @() }
    )

    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate.Command -ErrorAction SilentlyContinue
        if (-not $cmd) {
            continue
        }

        try {
            $command = $candidate.Command
            $args = @($candidate.Args) + @("-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)")
            & $command @args | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return $candidate
            }
        } catch {
            continue
        }
    }

    return $null
}

function Install-PythonWithWinget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $false
    }

    Write-Step "Python was not found. Trying to install Python 3.11 with winget"
    winget install --id Python.Python.3.11 -e --silent --accept-package-agreements --accept-source-agreements
    return $LASTEXITCODE -eq 0
}

function Ensure-Python {
    $python = Find-Python
    if ($python) {
        return $python
    }

    if (Install-PythonWithWinget) {
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        $python = Find-Python
        if ($python) {
            return $python
        }
    }

    throw "Python 3.11+ is required. Install Python 3.11 or 3.12, then run this script again."
}

function Invoke-Python($PythonCommand, $Arguments) {
    $command = $PythonCommand.Command
    $args = @($PythonCommand.Args) + @($Arguments)
    & $command @args
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: $($Arguments -join ' ')"
    }
}

function Ensure-Venv($PythonCommand) {
    if (Test-Path $VenvPython) {
        return
    }

    Write-Step "Creating virtual environment"
    Invoke-Python $PythonCommand @("-m", "venv", ".venv")
}

function Install-Requirements {
    Write-Step "Installing required packages"
    & $VenvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) {
        throw "pip upgrade failed"
    }

    & $VenvPython -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) {
        throw "pip install failed"
    }
}

function Warmup-Model {
    Write-Step "Preparing background removal model. The first run may download model files"
    $script = @'
from rembg import new_session
new_session("u2net")
print("model ready")
'@
    $script | & $VenvPython -
    if ($LASTEXITCODE -ne 0) {
        throw "model warmup failed"
    }
}

function Get-LanUrls {
    $addresses = @()

    try {
        $addresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -notlike "127.*" -and
                $_.IPAddress -notlike "169.254.*" -and
                (
                    $_.IPAddress -like "10.*" -or
                    $_.IPAddress -like "192.168.*" -or
                    $_.IPAddress -match "^172\.(1[6-9]|2[0-9]|3[0-1])\."
                )
            } |
            Select-Object -ExpandProperty IPAddress -Unique
    } catch {
        $addresses = @()
    }

    return @($addresses | ForEach-Object { "http://$($_):$Port" })
}

function Ensure-FirewallRule {
    $isWindows = $env:OS -eq "Windows_NT"
    if (-not $isWindows) {
        return
    }

    $ruleName = "Local Background Remover Port $Port"
    try {
        $existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
        if (-not $existing) {
            Write-Step "Trying to allow LAN access through Windows Firewall"
            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Private | Out-Null
        }
    } catch {
        Write-Host "Could not add firewall rule automatically. If LAN users cannot connect, allow TCP port $Port in Windows Firewall." -ForegroundColor Yellow
    }
}

function Open-BrowserSoon {
    Start-Job -ScriptBlock {
        Start-Sleep -Seconds 10
        Start-Process "http://127.0.0.1:5000"
    } | Out-Null
}

Write-Host "Starting local background remover..." -ForegroundColor Green

$pythonCommand = Ensure-Python
Ensure-Venv $pythonCommand
Install-Requirements
Warmup-Model
Ensure-FirewallRule

$lanUrls = Get-LanUrls

Write-Step "Starting website"
Write-Host "Local URL: $LocalUrl" -ForegroundColor Green
if ($lanUrls.Count -gt 0) {
    Write-Host "LAN URL for other devices on the same network:" -ForegroundColor Green
    foreach ($url in $lanUrls) {
        Write-Host "  $url" -ForegroundColor Green
    }
} else {
    Write-Host "LAN URL was not detected. Run ipconfig and use http://YOUR_IPV4:$Port" -ForegroundColor Yellow
}
Write-Host "Close this window to stop the server." -ForegroundColor Yellow

Open-BrowserSoon
& $VenvPython app.py
