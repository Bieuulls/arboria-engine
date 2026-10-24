# ARBORIA VALIDATION LAB — Environment Diagnostic Tool
param (
    [string]$GodotPath = "",
    [string]$ProjectPath = ""
)

$ErrorActionPreference = "Continue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path "$ScriptDir\..\.."
if (-not $ProjectPath) {
    $ProjectPath = "$RepoRoot\project"
}
$LabRoot = Split-Path -Parent $ScriptDir
$ResultsDir = "$LabRoot\results"
if (-not (Test-Path $ResultsDir)) {
    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
}
$ResultsFile = "$ResultsDir\environment.json"

Write-Host "===================================================================="
Write-Host "  ARBORIA VALIDATION LAB - DIAGNOSTICO DO AMBIENTE GRAFICO"
Write-Host "===================================================================="

# 1. Informações de Sistema Operacional e Hardware
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$ramGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)

$gpuInfo = @{
    Name = "Desconhecida"
    Driver = "Desconhecido"
    VramMB = 0
}

try {
    $smi = nvidia-smi --query-gpu=gpu_name,driver_version,memory.total --format=csv,noheader,nounits 2>$null
    if ($smi) {
        $parts = $smi.Split(",")
        $gpuInfo.Name = $parts[0].Trim()
        $gpuInfo.Driver = $parts[1].Trim()
        $gpuInfo.VramMB = [int]$parts[2].Trim()
    }
} catch {}

Write-Host ""
Write-Host "[1] HARDWARE E SISTEMA OPERACIONAL:"
Write-Host ("  OS     : {0} ({1}) Build {2}" -f $os.Caption, $os.OSArchitecture, $os.BuildNumber)
Write-Host ("  CPU    : {0} ({1} Cores / {2} Threads)" -f $cpu.Name, $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
Write-Host ("  RAM    : {0} GB" -f $ramGb)
Write-Host ("  GPU    : {0} ({1} MB VRAM)" -f $gpuInfo.Name, $gpuInfo.VramMB)
Write-Host ("  Driver : {0}" -f $gpuInfo.Driver)

# 2. Localização do Godot
if (-not $GodotPath -or -not (Test-Path $GodotPath)) {
    $candidates = @(
        $env:GODOT_BIN,
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe",
        "$RepoRoot\bin\godot_console.exe",
        "$RepoRoot\bin\godot.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $GodotPath = $c
            break
        }
    }
}

$godotVersion = "Nao detectado"
if ($GodotPath -and (Test-Path $GodotPath)) {
    try {
        $gv = & $GodotPath --version 2>$null
        if ($gv) { $godotVersion = $gv.Trim() }
    } catch {}
}

Write-Host ""
Write-Host "[2] MOTOR GODOT ENGINE:"
if ($GodotPath -and (Test-Path $GodotPath)) {
    Write-Host ("  [OK] Executavel: {0}" -f $GodotPath)
    Write-Host ("  [OK] Versao    : {0}" -f $godotVersion)
} else {
    Write-Host "  [FALTA] Godot 4.7.2 nao localizado automaticamente."
}

# 3. Ferramentas Gráficas Profissionais de Validação
Write-Host ""
Write-Host "[3] FERRAMENTAS PROFISSIONAIS DE VALIDACAO GRAFICA:"

$tools = [ordered]@{}

# Vulkan SDK
$vulkanSdkPath = $env:VULKAN_SDK
$vulkanLayers = Test-Path "$vulkanSdkPath\Bin\VkLayer_khronos_validation.json"
$tools["VulkanSDK"] = @{
    Required = $true
    Installed = [bool]($vulkanSdkPath -and (Test-Path $vulkanSdkPath))
    Path = $vulkanSdkPath
    Details = if ($vulkanLayers) { "Validation Layers OK" } else { "Validation Layers nao encontradas (Baixar LunarG Vulkan SDK)" }
}

# RenderDoc
$renderdocPath = "C:\Program Files\RenderDoc\qrenderdoc.exe"
$renderdocInstalled = Test-Path $renderdocPath
$tools["RenderDoc"] = @{
    Required = $true
    Installed = $renderdocInstalled
    Path = if ($renderdocInstalled) { $renderdocPath } else { "" }
    Details = if ($renderdocInstalled) { "Pronto para captura de frames" } else { "Necessario baixar: https://renderdoc.org" }
}

# Nsight Graphics
$nsightGraphics = Get-Item "C:\Program Files\NVIDIA Corporation\Nsight Graphics*\host\windows-desktop-nomad-x64\ngfx-ui.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
$tools["NsightGraphics"] = @{
    Required = $true
    Installed = [bool]$nsightGraphics
    Path = if ($nsightGraphics) { $nsightGraphics.FullName } else { "" }
    Details = if ($nsightGraphics) { "GPU Profiler Ativo" } else { "Necessario baixar da NVIDIA Developer" }
}

# Nsight Systems
$nsightSystems = Get-Item "C:\Program Files\NVIDIA Corporation\Nsight Systems*\host-windows-x64\nsys-ui.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
$tools["NsightSystems"] = @{
    Required = $true
    Installed = [bool]$nsightSystems
    Path = if ($nsightSystems) { $nsightSystems.FullName } else { "" }
    Details = if ($nsightSystems) { "Timeline CPU/GPU Ativo" } else { "Necessario baixar da NVIDIA Developer" }
}

# Visual Studio / MSVC C++
$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = ""
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -property installationPath 2>$null
}
$cmakeCmd = Get-Command cmake -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
$tools["VisualStudioCpp"] = @{
    Required = $true
    Installed = [bool]($vsPath -or $cmakeCmd)
    Path = if ($vsPath) { $vsPath } else { $cmakeCmd }
    Details = if ($vsPath) { "MSVC Visual Studio Detectado" } elseif ($cmakeCmd) { "CMake + MinGW C++ Detectado" } else { "Instalar ferramentas C++" }
}

# Python
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
$tools["Python"] = @{
    Required = $true
    Installed = [bool]$pythonCmd
    Path = $pythonCmd
    Details = if ($pythonCmd) { (& python --version 2>&1) } else { "Necessario Python 3.10+" }
}

# Git
$gitCmd = Get-Command git -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
$tools["Git"] = @{
    Required = $false
    Installed = [bool]$gitCmd
    Path = $gitCmd
    Details = if ($gitCmd) { "Git Ativo" } else { "Git nao encontrado" }
}

foreach ($k in $tools.Keys) {
    $item = $tools[$k]
    $tag = if ($item.Installed) { "[OK]" } else { if ($item.Required) { "[FALTA]" } else { "[AVISO]" } }
    Write-Host ("  {0,-8} {1,-18}: {2}" -f $tag, $k, $item.Details)
}

# 4. Salva o resultado consolidado em JSON
$report = [ordered]@{
    Timestamp = (Get-Date).ToString("s")
    Environment = @{
        OS = ("{0} ({1})" -f $os.Caption, $os.OSArchitecture)
        CPU = $cpu.Name
        RAM_GB = $ramGb
        GPU = $gpuInfo.Name
        Driver = $gpuInfo.Driver
        VRAM_MB = $gpuInfo.VramMB
    }
    Godot = @{
        Path = $GodotPath
        Version = $godotVersion
    }
    Tools = $tools
    Project = @{
        Path = $ProjectPath
        Valid = (Test-Path "$ProjectPath\project.godot")
    }
}

$report | ConvertTo-Json -Depth 5 | Out-File -FilePath $ResultsFile -Encoding utf8
Write-Host ""
Write-Host "===================================================================="
Write-Host ("Diagnostico gravado em: {0}" -f $ResultsFile)
Write-Host "===================================================================="
