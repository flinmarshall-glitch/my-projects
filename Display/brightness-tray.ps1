<#
.SYNOPSIS
  Brightness tray icon (next to the clock) for dimming / restoring all monitors.

.DESCRIPTION
  Left-click          toggle: lowest brightness, or back to the remembered level
  Right-click         menu: Dim to lowest, Restore previous level, 25 / 50 / 75 / 100 %, Exit
  The icon is a thin "-" while the screens are lit (click = dim) and a "+" while dimmed (click = restore).
  The real work is done by dim.ps1 in this folder. Only one copy runs at a time.
  Start it hidden with brightness-tray.vbs.
#>
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Native -Name Tray -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr h);
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern bool SetProcessWorkingSetSize(System.IntPtr h, System.IntPtr min, System.IntPtr max);
'@
if (-not ('FlatMenuColors' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System.Drawing;
using System.Windows.Forms;

public class FlatMenuColors : ProfessionalColorTable
{
    public Color Bg, Hover, Border, Sep;
    public override Color ToolStripDropDownBackground { get { return Bg; } }
    public override Color ImageMarginGradientBegin { get { return Bg; } }
    public override Color ImageMarginGradientMiddle { get { return Bg; } }
    public override Color ImageMarginGradientEnd { get { return Bg; } }
    public override Color MenuBorder { get { return Border; } }
    public override Color MenuItemBorder { get { return Hover; } }
    public override Color MenuItemSelected { get { return Hover; } }
    public override Color MenuItemSelectedGradientBegin { get { return Hover; } }
    public override Color MenuItemSelectedGradientEnd { get { return Hover; } }
    public override Color MenuItemPressedGradientBegin { get { return Hover; } }
    public override Color MenuItemPressedGradientMiddle { get { return Hover; } }
    public override Color MenuItemPressedGradientEnd { get { return Hover; } }
    public override Color SeparatorDark { get { return Sep; } }
    public override Color SeparatorLight { get { return Sep; } }
}
'@
}

$logDir = Join-Path $env:LOCALAPPDATA 'dim'
function Write-Log([string]$text) {
    try {
        New-Item -ItemType Directory -Force $logDir | Out-Null
        Add-Content -Path (Join-Path $logDir 'tray-error.log') -Value ("{0:s}  {1}" -f (Get-Date), $text)
    } catch { }
}

# one copy at a time
$created = $false
$mutex = [System.Threading.Mutex]::new($true, 'Local\DimBrightnessTray', [ref]$created)
if (-not $created) { exit }

try {
    [void][Native.Tray]::SetProcessDPIAware()
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $dimScript = Join-Path $here 'dim.ps1'

    # ---- theme -------------------------------------------------------------------------------------------------
    function Test-LightTaskbar {
        try {
            (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).SystemUsesLightTheme -eq 1
        } catch { $false }
    }
    $script:light = Test-LightTaskbar

    # ---- icons: thin pixel-snapped + / - bars, drawn at the tray's own size ---------------------------------------
    function New-GlyphIcon([string]$glyph) {
        $size = [int][System.Windows.Forms.SystemInformation]::SmallIconSize.Width
        $color = if ($script:light) { [System.Drawing.Color]::FromArgb(255, 27, 27, 27) } else { [System.Drawing.Color]::White }
        $bmp = New-Object System.Drawing.Bitmap -ArgumentList $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'None'
        $g.Clear([System.Drawing.Color]::Transparent)
        $t = [int][math]::Max(1, [math]::Round($size * 0.075))
        $len = [int][math]::Round($size * 0.6)
        if (($size - $len) % 2 -ne 0) { $len++ }
        $a = [int](($size - $len) / 2)
        $b = [int][math]::Floor(($size - $t) / 2)
        $brush = New-Object System.Drawing.SolidBrush -ArgumentList $color
        $g.FillRectangle($brush, $a, $b, $len, $t)
        if ($glyph -eq 'plus') { $g.FillRectangle($brush, $b, $a, $t, $len) }
        $brush.Dispose(); $g.Dispose()
        $h = $bmp.GetHicon()
        $bmp.Dispose()
        [System.Drawing.Icon]::FromHandle($h)
    }
    function Build-Icons {
        $old = $script:icons
        $script:icons = @{ minus = (New-GlyphIcon 'minus'); plus = (New-GlyphIcon 'plus') }
        return $old
    }
    $script:icons = $null
    [void](Build-Icons)

    # ---- state -------------------------------------------------------------------------------------------------
    $script:levels = @()
    $script:proc = $null
    $script:mode = ''
    $script:queued = $null
    $script:ticks = 0

    function ConvertFrom-Status([string]$text) {
        $found = @()
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match '(\d+)/(\d+)\s*$' -and [int]$Matches[2] -gt 0) {
                $found += [int][math]::Round(100 * [int]$Matches[1] / [int]$Matches[2])
            }
        }
        , $found
    }

    function Start-Dim([string]$dimArgs, [string]$mode) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $dimScript + '" ' + $dimArgs
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $script:proc = [System.Diagnostics.Process]::Start($psi)
        $script:mode = $mode
    }

    # one change at a time; a click that arrives while one is running waits its turn (latest click wins)
    function Request-Action([string]$dimArgs) {
        if ($script:proc) { $script:queued = $dimArgs } else { Start-Dim $dimArgs 'action' }
    }

    # ---- menu --------------------------------------------------------------------------------------------------
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Font = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 9.5
    $menu.ShowImageMargin = $false
    $menu.ShowCheckMargin = $false

    $header = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList 'Brightness'
    $header.Enabled = $false
    [void]$menu.Items.Add($header)
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    $onClick = { param($sender, $e) Request-Action $sender.Tag }
    function Add-Item([string]$text, [string]$tag) {
        $item = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList $text
        $item.Tag = $tag
        $item.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 6, 5, 6, 5
        $item.Add_Click($onClick)
        [void]$menu.Items.Add($item)
    }
    Add-Item 'Dim to lowest' 'down'
    Add-Item 'Restore previous level' 'up'
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    Add-Item '25%' '25'
    Add-Item '50%' '50'
    Add-Item '75%' '75'
    Add-Item '100%' '100'
    [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem -ArgumentList 'Exit'
    $exitItem.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 6, 5, 6, 5
    [void]$menu.Items.Add($exitItem)

    function Set-MenuTheme {
        $colors = New-Object FlatMenuColors
        if ($script:light) {
            $colors.Bg = [System.Drawing.Color]::FromArgb(249, 249, 249); $colors.Hover = [System.Drawing.Color]::FromArgb(233, 233, 233)
            $colors.Border = [System.Drawing.Color]::FromArgb(222, 222, 222); $colors.Sep = [System.Drawing.Color]::FromArgb(224, 224, 224)
            $text = [System.Drawing.Color]::FromArgb(27, 27, 27); $dim = [System.Drawing.Color]::FromArgb(120, 120, 120)
        } else {
            $colors.Bg = [System.Drawing.Color]::FromArgb(44, 44, 44); $colors.Hover = [System.Drawing.Color]::FromArgb(62, 62, 62)
            $colors.Border = [System.Drawing.Color]::FromArgb(66, 66, 66); $colors.Sep = [System.Drawing.Color]::FromArgb(66, 66, 66)
            $text = [System.Drawing.Color]::White; $dim = [System.Drawing.Color]::FromArgb(150, 150, 150)
        }
        $renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer -ArgumentList $colors
        $renderer.RoundedEdges = $false
        $menu.Renderer = $renderer
        $menu.BackColor = $colors.Bg
        foreach ($i in $menu.Items) {
            if ($i -is [System.Windows.Forms.ToolStripMenuItem]) { $i.ForeColor = if ($i -eq $header) { $dim } else { $text } }
        }
    }
    # a disabled item ignores ForeColor, so keep the header enabled but inert
    $header.Enabled = $true
    $header.Add_Click({ })
    Set-MenuTheme

    # ---- tray icon ---------------------------------------------------------------------------------------------
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.ContextMenuStrip = $menu
    $notify.Icon = $script:icons.minus
    $notify.Text = 'Brightness'

    function Show-State {
        $lit = @($script:levels | Where-Object { $_ -gt 0 }).Count -gt 0
        if ($script:levels.Count -eq 0) {
            $label = 'Brightness: unknown'
            $hint = ''
        } else {
            $label = 'Brightness: ' + (($script:levels | ForEach-Object { "$_%" }) -join ' / ')
            $hint = if ($lit) { '  -  click to dim' } else { '  -  click to restore' }
        }
        $header.Text = $label
        $tip = $label + $hint
        $notify.Text = $tip.Substring(0, [math]::Min(63, $tip.Length))
        $notify.Icon = if ($lit -or $script:levels.Count -eq 0) { $script:icons.minus } else { $script:icons.plus }
    }

    $notify.Add_MouseClick({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Request-Action 'toggle' }
    })
    $menu.Add_Opening({ if (-not $script:proc) { Start-Dim 'status' 'status' } })

    $ctx = New-Object System.Windows.Forms.ApplicationContext
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $exitItem.Add_Click({ $timer.Stop(); $notify.Visible = $false; $ctx.ExitThread() })

    $timer.Add_Tick({
        try {
            $script:ticks++
            if ($script:ticks -eq 20 -or $script:ticks % 240 -eq 0) {
                # idle app: hand unused memory back to Windows (PowerShell + WinForms otherwise sits near 100 MB)
                [GC]::Collect()
                [void][Native.Tray]::SetProcessWorkingSetSize([System.Diagnostics.Process]::GetCurrentProcess().Handle, [IntPtr](-1), [IntPtr](-1))
            }
            if ($script:ticks % 20 -eq 0) {
                # about every 5 s: follow a Windows light/dark switch
                $l = Test-LightTaskbar
                if ($l -ne $script:light) {
                    $script:light = $l
                    $old = Build-Icons
                    Set-MenuTheme
                    Show-State
                    foreach ($ic in $old.Values) { [void][Native.Tray]::DestroyIcon($ic.Handle) }
                }
            }
            if (-not $script:proc -or -not $script:proc.HasExited) { return }

            $p = $script:proc
            $script:proc = $null
            $out = $p.StandardOutput.ReadToEnd()
            [void]$p.StandardError.ReadToEnd()
            $code = $p.ExitCode
            $p.Dispose()

            if ($script:mode -eq 'status') {
                $script:levels = ConvertFrom-Status $out
                Show-State
            } elseif ($code -ne 0) {
                $notify.ShowBalloonTip(4000, 'Brightness', 'The change failed. Run dim.ps1 status in a terminal to see why.', [System.Windows.Forms.ToolTipIcon]::Error)
            }

            if ($script:queued) {
                $next = $script:queued
                $script:queued = $null
                Start-Dim $next 'action'
            } elseif ($script:mode -eq 'action') {
                Start-Dim 'status' 'status'
            }
        } catch { Write-Log ("tick: " + $_.Exception.Message) }
    })

    $notify.Visible = $true
    $timer.Start()
    Start-Dim 'status' 'status'
    [System.Windows.Forms.Application]::Run($ctx)

    $timer.Stop()
    $notify.Visible = $false
    $notify.Dispose()
    foreach ($ic in $script:icons.Values) { [void][Native.Tray]::DestroyIcon($ic.Handle) }
}
catch { Write-Log ("startup: " + $_.Exception.Message + "`n" + $_.ScriptStackTrace); exit 1 }
finally { try { $mutex.ReleaseMutex() } catch { } }
