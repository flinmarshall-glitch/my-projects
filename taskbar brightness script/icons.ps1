<#
.SYNOPSIS
  Regenerates the minimal + / - icons used by the pinned brightness taskbar buttons.

.DESCRIPTION
  Taskbar\brightness-down.ico  (-)   and   Taskbar\brightness-up.ico  (+)
      drawn for the current Windows theme (white on a dark taskbar, near-black on a light one).
  (The tray icon draws its own + / - at runtime, so it follows the theme and display scaling by itself.)

  Re-run after switching Windows between light and dark mode. If a pinned icon looks stale, restart Explorer.

.EXAMPLE
  .\Make-Icons.ps1            # theme detected automatically
  .\Make-Icons.ps1 -Theme light
#>
param([ValidateSet('auto', 'dark', 'light')][string]$Theme = 'auto')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$taskbarDir = Join-Path $here 'Taskbar'
New-Item -ItemType Directory -Force $taskbarDir | Out-Null

if ($Theme -eq 'auto') {
    $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $light = (Get-ItemProperty $k -ErrorAction SilentlyContinue).SystemUsesLightTheme
    $Theme = if ($light -eq 1) { 'light' } else { 'dark' }
}

$white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$ink = [System.Drawing.Color]::FromArgb(255, 27, 27, 27)

function New-Frame([int]$size, [string]$glyph, [System.Drawing.Color]$color) {
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'None'
    $g.Clear([System.Drawing.Color]::Transparent)

    # Pixel-snapped bars (no anti-aliasing) so the glyph is razor sharp at every size.
    $t = [int][math]::Max(1, [math]::Round($size * 0.075))
    $len = [int][math]::Round($size * 0.6)
    if (($size - $len) % 2 -ne 0) { $len++ }
    $a = [int](($size - $len) / 2)
    $b = [int][math]::Floor(($size - $t) / 2)
    $brush = New-Object System.Drawing.SolidBrush -ArgumentList $color
    $g.FillRectangle($brush, $a, $b, $len, $t)
    if ($glyph -eq 'plus') { $g.FillRectangle($brush, $b, $a, $t, $len) }
    $brush.Dispose()
    $g.Dispose()
    $bmp
}

function Save-Ico([string]$glyph, [System.Drawing.Color]$color, [string]$file) {
    $sizes = 16, 20, 24, 32, 40, 48, 64, 256
    $pngs = @()
    foreach ($sz in $sizes) {
        $bmp = New-Frame $sz $glyph $color
        $ms = New-Object IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $pngs += , $ms.ToArray()
    }
    $fs = [IO.File]::Create($file)
    $bw = New-Object IO.BinaryWriter -ArgumentList $fs
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        $b = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $bw.Write([byte]$b); $bw.Write([byte]$b); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $bw.Write([byte[]]$p) }
    $bw.Close()
    $fs.Close()
}

$pinColor = if ($Theme -eq 'light') { $ink } else { $white }
Save-Ico 'minus' $pinColor (Join-Path $taskbarDir 'brightness-down.ico')
Save-Ico 'plus' $pinColor (Join-Path $taskbarDir 'brightness-up.ico')

"Icons written for the $Theme theme."
