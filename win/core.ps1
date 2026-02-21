# core.ps1 - B2P Low-Level Engine
$B2P_HOME = Join-Path $env:USERPROFILE ".b2p"
$B2P_APPS = Join-Path $B2P_HOME "apps"
$B2P_TELEPORTS = Join-Path $B2P_HOME "teleports"
$B2P_SHIMS = Join-Path $B2P_HOME "shims"
$B2P_BIN = Join-Path $B2P_HOME "bin"

# Garantir infraestrutura
@($B2P_APPS, $B2P_TELEPORTS, $B2P_SHIMS, $B2P_BIN) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item $_ -ItemType Directory -Force | Out-Null }
}

function Install-B2PApp {
    param (
        [Object]$Manifest,
        [String]$Version,
        [Switch]$Silent,
        [ScriptBlock]$PreInstall,
        [ScriptBlock]$PostInstall
    )

    $AppBaseDir = Join-Path $B2P_APPS $Manifest.Name
    $InstallDir = Join-Path $AppBaseDir $Version
    
    if ($PreInstall) { & $PreInstall }

    # Download via BITS (Barra de progresso real)
    $tempFile = Join-Path $env:TEMP "$(New-Guid).tmp"
    if (-not $Silent) {
        Write-Host "`n>>> Downloading $($Manifest.Name) $Version..." -ForegroundColor Cyan
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $Manifest.Url -Destination $tempFile -Priority Foreground
    } else {
        Invoke-WebRequest -Uri $Manifest.Url -OutFile $tempFile
    }

    # Extração
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    New-Item $InstallDir -ItemType Directory -Force | Out-Null
    
    Write-Host ">>> Extracting files..." -ForegroundColor Gray
    Expand-Archive -Path $tempFile -DestinationPath $InstallDir -Force
    Remove-Item $tempFile

    # Limpeza de subpastas redundantes (comum no LLVM)
    $sub = Get-ChildItem $InstallDir -Directory | Select-Object -First 1
    if ($sub -and $sub.Name -like "$($Manifest.Name)*") {
        Get-ChildItem $sub.FullName | Move-Item -Destination $InstallDir -Force
        Remove-Item $sub.FullName -Recurse -Force
    }

    # Registro de Metadados
    $meta = @{
        Name = $Manifest.Name
        Version = $Version
        BinPath = Join-Path $InstallDir $Manifest.RelativeBinPath
        RealPathActive = $Manifest.RealPath
    }
    $meta | ConvertTo-Json | Out-File (Join-Path $InstallDir "b2p-metadata.json")

    # Criar Teleportes
    Create-B2PTeleports -Name $Manifest.Name -Version $Version -BinPath $meta.BinPath

    # Criar Shims do Manifesto
    if ($Manifest.Shims) {
        foreach ($s in $Manifest.Shims) {
            $binaryFull = Join-Path $meta.BinPath $s.bin
            Create-B2PShim -BinaryPath $binaryFull -Alias $s.alias
        }
    }

    if ($PostInstall) { & $PostInstall }
    Write-Host "[b2p] Instalado com sucesso!" -ForegroundColor Green
}

function Create-B2PTeleports {
    param($Name, $Version, $BinPath)
    
    $vTele = Join-Path $B2P_TELEPORTS "$Name-v$Version.bat"
    $lTele = Join-Path $B2P_TELEPORTS "$Name-latest.bat"
    $dTele = Join-Path $B2P_TELEPORTS "$Name.bat"

    $content = "@echo off`nset B2P_BIN=$BinPath`nif `"%~1`"==`"`" (echo App: $Name $Version) else ( `"%B2P_BIN%\%~1`" %~2 %~3 %~4 %~5 %~6 )"
    
    $content | Out-File $vTele -Encoding ASCII
    $content | Out-File $lTele -Encoding ASCII
    
    # Teleporte padrão (Só cria se não existir - Imutável)
    if (-not (Test-Path $dTele)) {
        $content | Out-File $dTele -Encoding ASCII
    }
}

function Create-B2PShim {
    param($BinaryPath, $Alias)
    $shimPath = Join-Path $B2P_SHIMS "$Alias.bat"
    "@echo off`n`"$BinaryPath`" %*" | Out-File $shimPath -Encoding ASCII
}

function Uninstall-B2PApp {
    param($Name, $Version)
    # Lógica de remoção baseada no metadata.json
    Write-Host "Removendo $Name $Version..." -ForegroundColor Yellow
    $dir = Join-Path $B2P_APPS "$Name\$Version"
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
}