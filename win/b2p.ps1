# b2p.ps1 - The CLI Manager
param([String]$install, [String]$upgrade, [String]$default, [String]$v="latest", [Switch]$s=$false)

# Importar motor
$coreUrl = "https://raw.githubusercontent.com/b2p-pw/b2p/main/win/core.ps1"
if (Test-Path "$env:USERPROFILE\.b2p\bin\core.ps1") { . "$env:USERPROFILE\.b2p\bin\core.ps1" }
else { iex "& { $(irm '$coreUrl') }" }

function Setup-B2P-Self {
    # Lógica de instalar o b2p.bat como Read-Only na pasta de shims
    $b2pBat = Join-Path $B2P_SHIMS "b2p.bat"
    if (Test-Path $b2pBat) { Set-ItemProperty $b2pBat -Name IsReadOnly -Value $false }
    
    "@echo off`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$B2P_BIN\b2p.ps1`" %*" | Out-File $b2pBat -Encoding ASCII
    Set-ItemProperty $b2pBat -Name IsReadOnly -Value $true
    
    Invoke-WebRequest $coreUrl -OutFile (Join-Path $B2P_BIN "core.ps1")
    # ... PATH setup ...
}

if ($install -eq "b2p") { Setup-B2P-Self; return }
if ($install) { iex "& { $(irm 'https://raw.githubusercontent.com/b2p-pw/w/main/$install/i.s') } -v $v -s:$s"; return }
if ($default) {
    # Lógica para copiar um teleport versionado para o app.bat (imutável)
    $source = Join-Path $B2P_TELEPORTS "$install-$default.bat"
    $target = Join-Path $B2P_TELEPORTS "$install.bat"
    Copy-Item $source $target -Force
    Write-Host "Padrão de $install alterado para $default." -ForegroundColor Green
}