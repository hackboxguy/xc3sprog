@echo off
REM Quick rebuild script with fixed XDC constraints
REM This will clean the previous build and rebuild with LED pin assignments

echo ============================================================
echo Rebuilding BSCAN SPI Bitstream for XC7A75T-FGG484
echo (with fixed LED pin constraints)
echo ============================================================
echo.

REM Set Vivado path
set VIVADO_PATH=C:\Xilinx\2025.1\Vivado

REM Check if Vivado exists
if not exist "%VIVADO_PATH%\bin\vivado.bat" (
    echo ERROR: Vivado not found at %VIVADO_PATH%
    echo Please edit this script and set the correct VIVADO_PATH
    pause
    exit /b 1
)

echo Found Vivado at: %VIVADO_PATH%
echo.

REM Clean previous build
echo Cleaning previous build directory...
if exist "build_xc7a75t" (
    rmdir /s /q build_xc7a75t
    echo Previous build directory removed.
)
echo.

REM Add Vivado to PATH
set PATH=%VIVADO_PATH%\bin;%PATH%

REM Run Vivado build
echo Starting Vivado build (this will take 6-10 minutes)...
echo.
vivado.bat -mode batch -source build_xc7a75t_fgg484.tcl

echo.
echo ============================================================
echo Build Complete!
echo ============================================================
echo.

REM Check if bitstream was created
if exist "xc7a75t-2fgg484.bit" (
    echo SUCCESS: Bitstream created!
    echo File: xc7a75t-2fgg484.bit
    echo Size:
    dir xc7a75t-2fgg484.bit | find "xc7a75t-2fgg484.bit"
    echo.
    echo Next steps:
    echo 1. Transfer to Pi4: scp xc7a75t-2fgg484.bit pi@pi4-flasher-008:~/micropanel/fpga/share/xc3sprog/bscan_spi/
    echo 2. Update wrapper script on Pi4 to use this bitstream
    echo 3. Test with: ./bin/fpga-jtag-flasher.sh --info
) else (
    echo ERROR: Bitstream was not created!
    echo Check vivado.log for errors.
    echo.
    echo Common issues:
    echo - Pin constraints incorrect
    echo - Missing device support
    echo - License issues
)

echo.
pause
