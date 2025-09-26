param(
    [string]$Triplet   = "x64-windows",
    [string]$BuildDir  = "$PSScriptRoot\build-windows",
    [string]$VcpkgDir  = "$PSScriptRoot\vcpkg"
)

function Write-Log {
    param([string]$msg)
    Write-Host "> $msg"
}

# Check if java is on path
if (-not (Get-Command "java" -ErrorAction SilentlyContinue)) {
    Write-Host "==> Java is not installed or not on the PATH. Please install Java and add it to the PATH." -ForegroundColor Red
    exit 1
}

# Clone vcpkg if it doesn't exist
if (-not (Test-Path $VcpkgDir)) {
    Write-Log "Cloning vcpkg into '$VcpkgDir'..."
    git clone https://github.com/microsoft/vcpkg.git $VcpkgDir
    Push-Location $VcpkgDir
    Write-Log "Bootstrapping vcpkg..."
    .\bootstrap-vcpkg.bat
    Pop-Location
}

$VcpkgExe = Join-Path $VcpkgDir 'vcpkg.exe'

# Ensure vcpkg.exe is available
if (-not (Test-Path $VcpkgExe)) {
    Push-Location $VcpkgDir
    Write-Log "Bootstrapping vcpkg..."
    .\bootstrap-vcpkg.bat
    Pop-Location
}

# Install required ports
# Include Google Test in dependencies
Write-Log "Installing Boost.System, Boost.Beast, C++/WinRT, and GTest via vcpkg ($Triplet)..."
& $VcpkgExe install "boost-system:$Triplet" "boost-beast:$Triplet" "cppwinrt:$Triplet" "gtest:$Triplet" "pthreads:$Triplet"

# Create build directory if needed
if (-not (Test-Path $BuildDir)) {
    Write-Log "Creating build directory '$BuildDir'..."
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

Push-Location $BuildDir

# find java home directory (path of dir containing bin folder)
$JavaHome = Get-Command java | Select-Object -ExpandProperty Source | Split-Path -Parent | Split-Path -Parent
$JavaHome = $JavaHome -replace '\\','/'
Write-Log "Java home directory: $JavaHome"

# Configure CMake with vcpkg toolchain
$ToolchainFile = Join-Path $VcpkgDir "scripts\buildsystems\vcpkg.cmake"
Write-Log "Configuring project with CMake (Toolchain: $ToolchainFile)..."
cmake .. `
    -G "Visual Studio 17 2022" `
    -A x64 `
    -DCMAKE_BUILD_TYPE=Release `
    -DCMAKE_TOOLCHAIN_FILE="$ToolchainFile" `
    -DVCPKG_TARGET_TRIPLET="$Triplet" `
    -Dcppwinrt_DIR="$VcpkgDir\installed\$Triplet\share\cppwinrt" `
    -DBoost_DIR="$VcpkgDir\installed\$Triplet\share\boost" `
    -DJAVA_HOME="$JavaHome"

if ($LASTEXITCODE -ne 0) {
    Write-Host "[build-windows] ERROR: CMake configuration failed!" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Build the solution
Write-Log "Building project..."
cmake --build . --config Release

if ($LASTEXITCODE -ne 0) {
    Write-Host "[build-windows] ERROR: Build failed!" -ForegroundColor Red
    Pop-Location
    exit 1
}

Pop-Location
Write-Host "==> Windows build finished successfully!" -ForegroundColor Green
