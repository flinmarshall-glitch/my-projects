<#
.SYNOPSIS
  Dim or restore every monitor over DDC/CI (the same thing the monitor's own brightness menu does).

.EXAMPLE
  dim            # toggle: all monitors to lowest, or back to what they were
  dim down       # lowest brightness (remembers the previous level)
  dim up         # restore the remembered level (50% if none is saved)
  dim 30         # set every monitor to 30%
  dim status     # show current brightness

  Every change fades all monitors together in small steps (default 1 second), so a monitor that
  jumps instantly and one that fades on its own both follow the same path. -Seconds 0 = instant.
  dim down -Seconds 2
#>
param([string]$Action = 'toggle', [double]$Seconds = 1.0)

$ErrorActionPreference = 'Stop'

if (-not ('Ddc' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

public static class Ddc
{
    [StructLayout(LayoutKind.Sequential, Pack = 1, CharSet = CharSet.Unicode)]
    struct PHYSICAL_MONITOR
    {
        public IntPtr hPhysicalMonitor;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szPhysicalMonitorDescription;
    }

    delegate bool EnumProc(IntPtr hMon, IntPtr hdc, IntPtr rect, IntPtr data);

    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, EnumProc cb, IntPtr data);
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr h, out uint n);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr h, uint n, [Out] PHYSICAL_MONITOR[] arr);
    [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(uint n, PHYSICAL_MONITOR[] arr);
    [DllImport("dxva2.dll")] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr h, byte code, IntPtr type, out uint cur, out uint max);
    [DllImport("dxva2.dll")] static extern bool SetVCPFeature(IntPtr h, byte code, uint val);

    const byte BRIGHTNESS = 0x10;

    static List<PHYSICAL_MONITOR> Enumerate()
    {
        var list = new List<PHYSICAL_MONITOR>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, delegate (IntPtr h, IntPtr d, IntPtr r, IntPtr x)
        {
            uint n;
            if (GetNumberOfPhysicalMonitorsFromHMONITOR(h, out n) && n > 0)
            {
                var arr = new PHYSICAL_MONITOR[n];
                if (GetPhysicalMonitorsFromHMONITOR(h, n, arr)) list.AddRange(arr);
            }
            return true;
        }, IntPtr.Zero);
        return list;
    }

    static void Release(List<PHYSICAL_MONITOR> mons)
    {
        if (mons.Count > 0) DestroyPhysicalMonitors((uint)mons.Count, mons.ToArray());
    }

    // One "current|max|description" line per physical monitor; current/max are -1 if DDC/CI did not answer.
    public static string[] Read()
    {
        var mons = Enumerate();
        var res = new List<string>();
        foreach (var m in mons)
        {
            uint cur = 0, max = 0;
            bool ok = false;
            for (int t = 0; t < 5 && !ok; t++)
            {
                ok = GetVCPFeatureAndVCPFeatureReply(m.hPhysicalMonitor, BRIGHTNESS, IntPtr.Zero, out cur, out max);
                if (!ok) Thread.Sleep(120);
            }
            res.Add((ok ? cur.ToString() : "-1") + "|" + (ok ? max.ToString() : "-1") + "|" + m.szPhysicalMonitorDescription);
        }
        Release(mons);
        return res.ToArray();
    }

    // values[i] goes to monitor i (same order as Read). Returns one success flag per value.
    public static bool[] Write(uint[] values)
    {
        var mons = Enumerate();
        var res = new bool[values.Length];
        for (int i = 0; i < values.Length && i < mons.Count; i++)
        {
            for (int t = 0; t < 3 && !res[i]; t++)
            {
                res[i] = SetVCPFeature(mons[i].hPhysicalMonitor, BRIGHTNESS, values[i]);
                if (!res[i]) Thread.Sleep(80);
            }
        }
        Release(mons);
        return res;
    }

    // Walk every monitor from from[i] to to[i] over totalMs, all in lock-step: each pass writes the value for
    // "how far along are we" to every monitor, as fast as the DDC bus allows. The end value is then written and
    // read back, and re-sent if a monitor dropped it (some monitors silently ignore a command that arrives too soon).
    public static bool[] Ramp(uint[] from, uint[] to, int totalMs)
    {
        var mons = Enumerate();
        int n = Math.Min(to.Length, mons.Count);
        var ok = new bool[to.Length];
        var sent = (uint[])from.Clone();

        double span = 0;
        for (int i = 0; i < n; i++) span = Math.Max(span, Math.Abs((double)to[i] - from[i]));

        if (totalMs > 0 && span > 0)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew();
            while (sw.ElapsedMilliseconds < totalMs)
            {
                double f = (double)sw.ElapsedMilliseconds / totalMs;
                for (int i = 0; i < n; i++)
                {
                    uint v = (uint)Math.Round(from[i] + ((double)to[i] - from[i]) * f);
                    if (v != sent[i] && SetVCPFeature(mons[i].hPhysicalMonitor, BRIGHTNESS, v)) sent[i] = v;
                }
            }
        }

        for (int i = 0; i < n; i++)
        {
            for (int t = 0; t < 4 && !ok[i]; t++)
            {
                SetVCPFeature(mons[i].hPhysicalMonitor, BRIGHTNESS, to[i]);
                Thread.Sleep(70);
                uint cur, max;
                ok[i] = GetVCPFeatureAndVCPFeatureReply(mons[i].hPhysicalMonitor, BRIGHTNESS, IntPtr.Zero, out cur, out max) && cur == to[i];
            }
        }
        Release(mons);
        return ok;
    }
}
'@
}

$stateDir  = Join-Path $env:LOCALAPPDATA 'dim'
$stateFile = Join-Path $stateDir 'state.json'
$defaultPct = 50

function Get-Monitors {
    $i = 0
    foreach ($line in [Ddc]::Read()) {
        $p = $line -split '\|', 3
        $max = [int]$p[1]
        # Cap = the top of the scale to use for percentages (100 if the monitor would not tell us)
        [pscustomobject]@{ Index = $i; Current = [int]$p[0]; Max = $max; Cap = $(if ($max -gt 0) { $max } else { 100 }); Name = $p[2] }
        $i++
    }
}

function Read-State {
    $h = @{}
    if (Test-Path $stateFile) {
        (Get-Content $stateFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = [int]$_.Value }
    }
    $h
}

function Set-Levels($monitors, [int[]]$levels) {
    # Every monitor stays in the list (values are matched to monitors by position). One that would not
    # report its level starts the fade at its target, i.e. it just gets the final value.
    $from = New-Object 'System.Collections.Generic.List[uint32]'
    for ($i = 0; $i -lt $monitors.Count; $i++) {
        $start = if ($monitors[$i].Current -ge 0) { $monitors[$i].Current } else { $levels[$i] }
        $from.Add([uint32]$start)
    }
    $flags = [Ddc]::Ramp($from.ToArray(), [uint32[]]$levels, [int]([math]::Max(0, $Seconds) * 1000))
    for ($i = 0; $i -lt $monitors.Count; $i++) {
        $m = $monitors[$i]
        $result = if ($flags[$i]) { "$($m.Current) -> $($levels[$i])" }
                  elseif ($m.Current -lt 0) { "-> $($levels[$i])  (sent, but the monitor would not confirm)" }
                  else { 'FAILED (monitor rejected the command)' }
        '  [{0}] {1,-18} {2}' -f $m.Index, $m.Name, $result
    }
}

$monitors = @(Get-Monitors)
if ($monitors.Count -eq 0) { Write-Error 'No DDC/CI capable monitors found.' }

# DDC/CI reads fail now and then (a monitor busy with its own fade, a flaky cable); ask again before giving up.
for ($try = 0; $try -lt 4 -and @($monitors | Where-Object { $_.Current -lt 0 }).Count -gt 0; $try++) {
    Start-Sleep -Milliseconds 250
    $monitors = @(Get-Monitors)
}

$unreadable = @($monitors | Where-Object { $_.Current -lt 0 })
if ($unreadable.Count -gt 0) {
    Write-Warning ("DDC/CI did not answer on: " + (($unreadable | ForEach-Object { "[$($_.Index)] $($_.Name)" }) -join ', ') + '. Is DDC/CI enabled in the monitor menu?')
}

$mode = $Action.ToLower()
if ($mode -eq 'toggle') {
    $allDim = -not ($monitors | Where-Object { $_.Current -gt 0 })
    $mode = if ($allDim) { 'up' } else { 'down' }
}

switch -Regex ($mode) {
    '^(status|s)$' {
        $readable = @($monitors | Where-Object { $_.Current -ge 0 })
        if ($readable.Count -eq 0) { Write-Error 'No monitor answered.' }
        $readable | ForEach-Object { '  [{0}] {1,-18} {2}/{3}' -f $_.Index, $_.Name, $_.Current, $_.Max }
    }
    '^(down|dim|min|low)$' {
        # Remember levels of monitors that are currently lit; keep older memory for ones already at 0.
        $state = Read-State
        foreach ($m in $monitors) { if ($m.Current -gt 0) { $state["$($m.Index)"] = $m.Current } }
        New-Item -ItemType Directory -Force $stateDir | Out-Null
        ($state | ConvertTo-Json) | Set-Content -Path $stateFile -Encoding ASCII
        'Dimming to lowest:'
        Set-Levels $monitors ([int[]]($monitors | ForEach-Object { 0 }))
    }
    '^(up|restore|normal|on)$' {
        $state = Read-State
        $levels = $monitors | ForEach-Object {
            if ($state.ContainsKey("$($_.Index)")) { [math]::Min($state["$($_.Index)"], $_.Cap) }
            else { [int][math]::Round($_.Cap * $defaultPct / 100) }
        }
        'Restoring:'
        Set-Levels $monitors ([int[]]$levels)
    }
    '^\d+$' {
        $pct = [math]::Min([int]$mode, 100)
        $levels = $monitors | ForEach-Object { [int][math]::Round($_.Cap * $pct / 100) }
        "Setting $pct%:"
        Set-Levels $monitors ([int[]]$levels)
    }
    default {
        Write-Error "Unknown action '$Action'. Use: toggle | down | up | status | <0-100>"
    }
}
