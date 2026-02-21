# core.ps1 - B2P Low-Level Engine
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

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

    $AppBaseDir = Join-Path $B2P_APPS $Manifest.Name.ToLower()
    $InstallDir = Join-Path $AppBaseDir $Version
    
    if ($PreInstall) { & $PreInstall }

    # Download via BITS
    $randomName = [guid]::NewGuid().ToString()
    $tempFile = Join-Path $env:TEMP "$randomName.tmp"
    
    if (-not $Silent) {
        Write-Host "`n[b2p] Baixando $($Manifest.Name) $Version..." -ForegroundColor Cyan
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $Manifest.Url -Destination $tempFile -Priority Foreground
    } else {
        Invoke-WebRequest -Uri $Manifest.Url -OutFile $tempFile
    }

    # Extração
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    New-Item $InstallDir -ItemType Directory -Force | Out-Null
    
    Write-Host ">>> Extraindo arquivos..." -ForegroundColor Gray
    Expand-Archive -Path $tempFile -DestinationPath $InstallDir -Force
    Remove-Item $tempFile

    # Limpeza de subpastas redundantes
    $sub = Get-ChildItem $InstallDir -Directory | Select-Object -First 1
    if ($sub -and $sub.Name -like "*$($Manifest.Name)*") {
        Get-ChildItem $sub.FullName | Move-Item -Destination $InstallDir -Force
        Remove-Item $sub.FullName -Recurse -Force
    }

    # Registro de Metadados
    $meta = @{
        Name = $Manifest.Name
        Version = $Version
        BinPath = Join-Path $InstallDir $Manifest.RelativeBinPath
    }
    $meta | ConvertTo-Json | Out-File (Join-Path $InstallDir "b2p-metadata.json")

    # SALVAR DESINSTALADOR (Renomeado para uninstall.ps1)
    Write-Host ">>> Salvando desinstalador local (uninstall.ps1)..." -ForegroundColor Gray
    $uninstallerUrl = "https://raw.githubusercontent.com/b2p-pw/w/main/$($Manifest.Name)/un.s"
    $unPath = Join-Path $InstallDir "uninstall.ps1"
    try {
        Invoke-WebRequest -Uri $uninstallerUrl -OutFile $unPath -ErrorAction SilentlyContinue
    } catch {
        $genericUn = "param(`$v='latest'); . { `$(irm 'https://raw.githubusercontent.com/b2p-pw/b2p/main/win/core.ps1') }; Uninstall-B2PApp -Name '$($Manifest.Name)' -Version `$v"
        $genericUn | Out-File $unPath -Encoding UTF8
    }

    # Criar Teleportes e Shims
    Create-B2PTeleports -Name $Manifest.Name -Version $Version -BinPath $meta.BinPath
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

    $content = "@echo off`nset B2P_BIN=$BinPath`nif `"%~1`"==`"`" (echo $Name v$Version) else ( `"%B2P_BIN%\%~1`" %~2 %~3 %~4 %~5 %~6 )"
    $content | Out-File $vTele -Encoding ASCII
    $content | Out-File $lTele -Encoding ASCII
    if (-not (Test-Path $dTele)) { $content | Out-File $dTele -Encoding ASCII }
}

function Create-B2PShim {
    param($BinaryPath, $Alias)
    $shimPath = Join-Path $B2P_SHIMS "$Alias.bat"
    "@echo off`n`"$BinaryPath`" %*" | Out-File $shimPath -Encoding ASCII
}

function Uninstall-B2PApp {
    param($Name, $Version)
    
    $AppRoot = Join-Path $B2P_APPS $Name.ToLower()
    Write-Host "[b2p] Iniciando remoção de $Name ($Version)..." -ForegroundColor Yellow

    # 1. Limpar Shims e Teleportes do PATH
    Write-Host ">>> Removendo atalhos e teleportes..." -ForegroundColor Gray
    Get-ChildItem $B2P_TELEPORTS -Filter "$Name*" | Remove-Item -Force -ErrorAction SilentlyContinue
    
    # Busca shims que apontam para este app (lógica robusta)
    Get-ChildItem $B2P_SHIMS -Filter "*.bat" | ForEach-Object {
        if ((Get-Content $_.FullName) -like "*\apps\$Name\*") {
            Remove-Item $_.FullName -Force
        }
    }

    # 2. Remover do PATH Real (se injetado)
    $uPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = $uPath.Split(';') | Where-Object { $_ -notlike "*\.b2p\apps\$Name\*" }
    [Environment]::SetEnvironmentVariable("Path", ($newPath -join ';'), "User")

    # 3. Deletar arquivos físicos
    if ($Version -eq "all") {
        if (Test-Path $AppRoot) { Remove-Item $AppRoot -Recurse -Force }
        Write-Host "[b2p] $Name e todas as versões foram removidas!" -ForegroundColor Green
    } else {
        $VerPath = Join-Path $AppRoot $Version
        if (Test-Path $VerPath) { Remove-Item $VerPath -Recurse -Force }
        Write-Host "[b2p] Versão $Version de $Name removida!" -ForegroundColor Green
    }
}