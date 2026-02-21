# core.ps1 - B2P Low-Level Engine
$B2P_CORE_VERSION = "1.2.5" # <--- VERSÃO DO CORE
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
    param ([Object]$Manifest, [String]$Version, [Switch]$Silent, [ScriptBlock]$PreInstall, [ScriptBlock]$PostInstall)

    $AppName = $Manifest.Name.ToLower()
    $AppBaseDir = Join-Path $B2P_APPS $AppName
    $InstallDir = Join-Path $AppBaseDir $Version
    
    if ($PreInstall) { & $PreInstall }

    $randomName = [guid]::NewGuid().ToString()
    $tempFile = Join-Path $env:TEMP "$randomName.tmp"
    
    if (-not $Silent) {
        Write-Host "`n[b2p] Baixando $($Manifest.Name) $Version..." -ForegroundColor Cyan
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $Manifest.Url -Destination $tempFile -Priority Foreground
    } else { Invoke-WebRequest -Uri $Manifest.Url -OutFile $tempFile }

    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
    New-Item $InstallDir -ItemType Directory -Force | Out-Null
    
    Write-Host ">>> Extraindo arquivos..." -ForegroundColor Gray
    Expand-Archive -Path $tempFile -DestinationPath $InstallDir -Force
    Remove-Item $tempFile

    $sub = Get-ChildItem $InstallDir -Directory | Select-Object -First 1
    if ($sub -and $sub.Name -like "*$($Manifest.Name)*") {
        Get-ChildItem $sub.FullName | Move-Item -Destination $InstallDir -Force
        Remove-Item $sub.FullName -Recurse -Force
    }

    
    $meta = @{
        Name = $Manifest.Name
        Version = $Version
        BinPath = Join-Path $InstallDir $Manifest.RelativeBinPath
        CoreVersion = $B2P_CORE_VERSION  # <--- Salva qual core instalou
        InstallDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $meta | ConvertTo-Json | Out-File (Join-Path $InstallDir "b2p-metadata.json")

    # SALVAR DESINSTALADOR LOCAL (Com nome do App fixo para evitar erro de Path Nulo)
    Write-Host ">>> Gerando uninstall.ps1 local..." -ForegroundColor Gray
    $unPath = Join-Path $InstallDir "uninstall.ps1"
    $unContent = @"
param(`$v = '$Version')
`$coreUrl = 'https://raw.githubusercontent.com/b2p-pw/b2p/main/win/core.ps1'
if (Test-Path '$B2P_BIN\core.ps1') { . '$B2P_BIN\core.ps1' } else { . { `$(irm `$coreUrl) } }
Uninstall-B2PApp -Name '$AppName' -Version `$v
"@
    $unContent | Out-File $unPath -Encoding UTF8

    Create-B2PTeleports -Name $Manifest.Name -Version $Version -BinPath $meta.BinPath
    if ($Manifest.Shims) {
        foreach ($s in $Manifest.Shims) {
            Create-B2PShim -BinaryPath (Join-Path $meta.BinPath $s.bin) -Alias $s.alias
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
    $AppName = $Name.ToLower()
    $AppRoot = Join-Path $B2P_APPS $AppName
    Write-Host "[b2p] Removendo $Name ($Version)..." -ForegroundColor Yellow

    # 1. Limpar Teleportes
    Get-ChildItem $B2P_TELEPORTS -Filter "$AppName*" | Remove-Item -Force -ErrorAction SilentlyContinue

    # 2. Limpar Shims (Verifica o conteúdo do .bat)
    if (Test-Path $B2P_SHIMS) {
        Get-ChildItem $B2P_SHIMS -Filter "*.bat" | ForEach-Object {
            $content = Get-Content $_.FullName -ErrorAction SilentlyContinue
            if ($content -like "*\apps\$AppName\*") { Remove-Item $_.FullName -Force }
        }
    }

    # 3. Limpar PATH Real
    $uPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $newPath = $uPath.Split(';') | Where-Object { $_ -notlike "*\.b2p\apps\$AppName\*" }
    [Environment]::SetEnvironmentVariable("Path", ($newPath -join ';'), "User")

    # 4. Deletar arquivos
    if ($Version -eq "all") {
        if (Test-Path $AppRoot) { Remove-Item $AppRoot -Recurse -Force }
    } else {
        $VerPath = Join-Path $AppRoot $Version
        if (Test-Path $VerPath) { Remove-Item $VerPath -Recurse -Force }
    }
    Write-Host "[b2p] Remoção concluída!" -ForegroundColor Green
}