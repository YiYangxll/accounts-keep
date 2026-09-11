# Start the Android emulator for this project and move its window fully on screen.
#
# Why this script exists
# ----------------------
# The primary display work area on this machine is only 2293x912. The emulator derives
# a window about 951px tall from the "Pixel 6 + 420dpi" profile, which is taller than the
# screen, so it positions the window with a negative Y (measured: y = -480). The title bar
# and the upper half of the window then sit outside the visible desktop.
#
# The emulator recomputes that placement on every launch: it ignores the Qt-saved
# geometry and it also ignores -scale / -fixed-scale. So the only reliable fix is to
# launch it and then move the window once.
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads .ps1 files using the ANSI
# code page unless a BOM is present, so non-ASCII comments can corrupt the parser.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\tools\start-emulator.ps1
#   powershell -ExecutionPolicy Bypass -File .\tools\start-emulator.ps1 -Avd other_avd
#   powershell -ExecutionPolicy Bypass -File .\tools\start-emulator.ps1 -NoFix

[CmdletBinding()]
param(
    [string]$Avd = 'accounts_keep_api36',
    [int]$X = 60,
    [int]$Y = 20,
    [int]$Width = 430,
    [int]$Height = 880,
    [switch]$NoFix
)

$ErrorActionPreference = 'Stop'

$sdk = 'E:\SDK\Android'
$emulator = Join-Path $sdk 'emulator\emulator.exe'
$adb = Join-Path $sdk 'platform-tools\adb.exe'

if (-not (Test-Path $emulator)) {
    throw "Emulator not found: $emulator"
}

$env:ANDROID_SDK_ROOT = $sdk
$env:ANDROID_HOME = $sdk
$env:ANDROID_AVD_HOME = Join-Path $env:USERPROFILE '.android\avd'

# Win32 helpers used to move the emulator window.
$win32 = @'
using System;
using System.Runtime.InteropServices;

public class EmuWindow
{
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);

    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }
}
'@

function Get-EmulatorWindowHandle {
    foreach ($candidate in (Get-Process -Name 'qemu-system-x86_64' -ErrorAction SilentlyContinue)) {
        if ($candidate.MainWindowHandle -ne 0) {
            return $candidate.MainWindowHandle
        }
    }
    return [IntPtr]::Zero
}

Write-Host "Starting AVD: $Avd" -ForegroundColor Cyan

# No -Wait here on purpose: the script must keep running to reposition the window.
$emuArgs = @('-avd', $Avd, '-gpu', 'auto', '-no-boot-anim')
$proc = Start-Process -FilePath $emulator -ArgumentList $emuArgs -PassThru

if (-not $NoFix) {
    Add-Type -TypeDefinition $win32

    # The emulator needs a moment before its own placement settles; moving too early
    # would simply be overridden.
    $hwnd = [IntPtr]::Zero
    for ($i = 0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 1
        $hwnd = Get-EmulatorWindowHandle
        if ($hwnd -ne [IntPtr]::Zero) {
            break
        }
    }

    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Warning 'Emulator window handle not found; skipped repositioning.'
    }
    else {
        Start-Sleep -Seconds 4
        [void][EmuWindow]::MoveWindow($hwnd, $X, $Y, $Width, $Height, $true)
        Start-Sleep -Seconds 1

        $rect = New-Object EmuWindow+RECT
        [void][EmuWindow]::GetWindowRect($hwnd, [ref]$rect)
        $actualWidth = $rect.Right - $rect.Left
        $actualHeight = $rect.Bottom - $rect.Top
        if ($rect.Top -lt 0) {
            Write-Warning "Window top is still off screen (y=$($rect.Top)). Run this script again or drag it manually."
        }
        else {
            Write-Host "Window repositioned to ($($rect.Left),$($rect.Top)) ${actualWidth}x${actualHeight}" -ForegroundColor Green
        }
    }
}

if (Test-Path $adb) {
    Write-Host 'Waiting for Android to finish booting...' -ForegroundColor Cyan
    # While the device is still coming up, adb prints "device offline" on stderr and exits
    # non-zero. That is expected here, so relax the error preference for the polling loop.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        for ($i = 0; $i -lt 80; $i++) {
            $state = & $adb -s 'emulator-5554' shell getprop sys.boot_completed 2>$null
            if ($state -match '1') {
                break
            }
            Start-Sleep -Seconds 3
        }
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    Write-Host 'Emulator is ready.' -ForegroundColor Green
}

Write-Host "Emulator PID: $($proc.Id) (close the emulator window to quit)" -ForegroundColor DarkGray
$proc.WaitForExit()
