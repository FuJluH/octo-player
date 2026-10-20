# Plays the packaged desktop app by itself for a long while and watches its
# memory: the app runs from an app image with a test profile of its own (as
# measure-desktop.ps1 makes it, signed in to the server of the Octo in use),
# the soak plan of desktop/.../system/Soak.kt playing silently with the full
# player open, and every minute this samples the app process from outside:
# private bytes (Task Manager's Commit size), working set, threads, handles,
# the octo-video threads, the graphics card's memory for the process, the
# Java heap (jcmd GC.heap_info) and the JVM's own native memory (jcmd
# VM.native_memory summary, with Native Memory Tracking on). What the JVM
# does not track (private bytes less the JVM's committed total) is Skia, the
# Rust engine, Media Foundation and the graphics driver. At the end it runs
# a full collection (jcmd GC.run) twice and samples again, for how much of
# the growth was only waiting for a collection.
#
#   powershell -File scripts/soak-desktop.ps1 -Label baseline -Minutes 120
#   powershell -File scripts/soak-desktop.ps1 -Label art-off -Art off -Minutes 45
#   powershell -File scripts/soak-desktop.ps1 -Label radio -Source radio -Lyrics off
#   powershell -File scripts/soak-desktop.ps1 -SelfTest
#
# Options:
#   -App <folder>     the app image (default: the one :desktop:createDistributable made)
#   -Label <name>     names the run; results go to desktop\build\soak\<label>
#   -Minutes <n>      how long it plays (default 120)
#   -Art <key>        Animated art: full_screen (default), square or off
#   -Wash <on|off>    the pages' background: immersive (on) or the glow (off)
#   -WashMotion <on|off> the full player's wash moving (on) or held still
#   -Lyrics <on|off>  the lyrics beside the cover in the full player
#   -Full <on|off>    the full player open (on), or Home with the player bar
#   -Source <name>    library (default) or radio
#   -Minimized        minimizes the window once it is up
#   -MinimizeAfter <m> minimizes it that many minutes in
#   -PauseAfter <m>   pauses the music that many minutes in, for good
#   -CacheAfter <m:MB> sets the window's GPU cache limit that many minutes in
#   -Advance <s>      seconds per song (default 45; 0 lets each play out)
#   -Every <s>        seconds between samples (default 60)
#   -Queue <file>     the songs every library run plays (default
#                     desktop\build\soak\queue.txt, written by the first run)
#   -Jvm <options>    more JVM options for this run (space between them)
#   -Jdk <folder>     a full JDK for jcmd (default JAVA_HOME)
#   -Shots <s,s,...>  saves the window as shot-<s>.png that many seconds
#                     after it shows (drawn by the window itself, so other
#                     windows over it do not matter), for comparing builds
#   -Keep             keeps the test profile afterwards
#   -SelfTest         checks the script's reading of jcmd's answers
#
# Writes samples.csv (a row a sample), summary.txt, the soak plan's events,
# and gc.log (the JVM's collections) into the run's folder.
param(
    [string]$App = "",
    [string]$Label = "soak",
    [int]$Minutes = 120,
    [ValidateSet("full_screen", "square", "off")][string]$Art = "full_screen",
    [ValidateSet("on", "off")][string]$Wash = "on",
    [ValidateSet("on", "off")][string]$WashMotion = "on",
    [ValidateSet("on", "off")][string]$Lyrics = "on",
    [ValidateSet("on", "off")][string]$Full = "on",
    [ValidateSet("library", "radio")][string]$Source = "library",
    [switch]$Minimized,
    [int]$MinimizeAfter = 0,
    [int]$PauseAfter = 0,
    [string]$CacheAfter = "",
    [int]$Advance = 45,
    [int]$Every = 60,
    [string]$Queue = "",
    [string]$Jvm = "",
    [string]$Jdk = $env:JAVA_HOME,
    [int]$Width = 1440,
    [int]$Height = 900,
    [string]$Shots = "",
    [switch]$Keep,
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not ("OctoSoak.Win" -as [type])) {
    Add-Type -Namespace OctoSoak -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hWnd);
[DllImport("kernel32.dll", SetLastError = true)] public static extern System.IntPtr OpenThread(int access, bool inherit, int id);
[DllImport("kernel32.dll")] public static extern bool CloseHandle(System.IntPtr handle);
[DllImport("kernel32.dll")] public static extern int GetThreadDescription(System.IntPtr thread, out System.IntPtr description);
[DllImport("kernel32.dll")] public static extern System.IntPtr LocalFree(System.IntPtr memory);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool PrintWindow(System.IntPtr hWnd, System.IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool GetWindowRect(System.IntPtr hWnd, out Rect rect);
public struct Rect { public int Left, Top, Right, Bottom; }
public static string ThreadName(int id) {
    System.IntPtr thread = OpenThread(0x0800, false, id);
    if (thread == System.IntPtr.Zero) return null;
    try {
        System.IntPtr text;
        if (GetThreadDescription(thread, out text) < 0) return null;
        try { return System.Runtime.InteropServices.Marshal.PtrToStringUni(text); } finally { LocalFree(text); }
    } finally { CloseHandle(thread); }
}
'@
}

# The window as it draws itself, as a PNG (PW_RENDERFULLCONTENT, which
# takes a window drawn by the graphics card too).
function Save-WindowShot([IntPtr]$Handle, [string]$Path) {
    Add-Type -AssemblyName System.Drawing
    [void][OctoSoak.Win]::SetProcessDPIAware()
    $rect = New-Object OctoSoak.Win+Rect
    [void][OctoSoak.Win]::GetWindowRect($Handle, [ref]$rect)
    $bitmap = New-Object System.Drawing.Bitmap ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $hdc = $graphics.GetHdc()
        try { [void][OctoSoak.Win]::PrintWindow($Handle, $hdc, 2) } finally { $graphics.ReleaseHdc($hdc) }
        $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

# ---- Reading jcmd's answers ----

# Kilobytes in "123456K" or "123456KB", as megabytes.
function ConvertFrom-Kb([string]$Text) { [math]::Round([double]($Text -replace '[^0-9]', '') / 1024, 1) }

# The Java heap's size and use from GC.heap_info.
function Read-HeapInfo([string]$Text) {
    if ($Text -match 'total (\d+)K, used (\d+)K') { return [pscustomobject]@{ HeapMB = ConvertFrom-Kb $Matches[1]; HeapUsedMB = ConvertFrom-Kb $Matches[2] } }
    [pscustomobject]@{ HeapMB = $null; HeapUsedMB = $null }
}

# The JVM's committed total and its main parts from VM.native_memory summary.
function Read-NativeMemory([string]$Text) {
    $parts = [ordered]@{}
    if ($Text -match 'Total: reserved=(\d+)KB, committed=(\d+)KB') { $parts["NmtMB"] = ConvertFrom-Kb $Matches[2] }
    foreach ($match in [regex]::Matches($Text, '-\s+([A-Za-z ]+?) \(reserved=(\d+)KB, committed=(\d+)KB\)')) {
        $name = ($match.Groups[1].Value -replace ' ', '')
        $parts["Nmt$name"] = ConvertFrom-Kb $match.Groups[3].Value
    }
    $parts
}

function Invoke-Jcmd([int]$ProcessId, [string]$Command) {
    $saved = $env:JAVA_TOOL_OPTIONS
    try {
        # jcmd is a Java program too: the app's options are not its own.
        Remove-Item Env:JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue
        $out = & (Join-Path $Jdk "bin\jcmd.exe") $ProcessId $Command 2>&1 | Out-String
        return $out
    } finally { if ($saved) { $env:JAVA_TOOL_OPTIONS = $saved } }
}

# ---- Samples ----

function Get-GpuMB([int]$ProcessId) {
    try {
        $counters = Get-Counter -Counter "\GPU Process Memory(pid_$($ProcessId)_*)\Dedicated Usage", "\GPU Process Memory(pid_$($ProcessId)_*)\Shared Usage" -ErrorAction Stop
        $dedicated = ($counters.CounterSamples | Where-Object { $_.Path -like '*dedicated usage' } | Measure-Object CookedValue -Sum).Sum
        $shared = ($counters.CounterSamples | Where-Object { $_.Path -like '*shared usage' } | Measure-Object CookedValue -Sum).Sum
        return @([math]::Round($dedicated / 1MB, 1), [math]::Round($shared / 1MB, 1))
    } catch { return @($null, $null) }
}

function Get-Sample([int]$ProcessId, [double]$Minute, [string]$Note = "") {
    $p = Get-Process -Id $ProcessId -ErrorAction Stop
    $video = 0
    foreach ($thread in $p.Threads) {
        $name = [OctoSoak.Win]::ThreadName($thread.Id)
        if ($name -and $name.StartsWith("octo-video")) { $video++ }
    }
    $gpu = Get-GpuMB $ProcessId
    $row = [ordered]@{
        Minute = [math]::Round($Minute, 1)
        Note = $Note
        PrivateMB = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
        WorkingSetMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
        Threads = $p.Threads.Count
        VideoThreads = $video
        Handles = $p.HandleCount
        GpuDedicatedMB = $gpu[0]
        GpuSharedMB = $gpu[1]
        CpuS = [math]::Round($p.TotalProcessorTime.TotalSeconds, 1)
    }
    $heap = Read-HeapInfo (Invoke-Jcmd $ProcessId "GC.heap_info")
    $row["HeapMB"] = $heap.HeapMB
    $row["HeapUsedMB"] = $heap.HeapUsedMB
    $nmt = Read-NativeMemory (Invoke-Jcmd $ProcessId "VM.native_memory summary")
    foreach ($name in "NmtMB", "NmtJavaHeap", "NmtClass", "NmtThread", "NmtCode", "NmtGC", "NmtInternal", "NmtOther", "NmtSymbol", "NmtArenaChunk") { $row[$name] = $nmt[$name] }
    # What the JVM does not know of: Skia, the engine, the system's own.
    $row["OutsideJvmMB"] = if ($nmt["NmtMB"]) { [math]::Round($row.PrivateMB - $nmt["NmtMB"], 1) } else { $null }
    [pscustomobject]$row
}

# Growth in MB an hour over samples from minute 15 on (least squares).
function Get-Slope($Samples, [string]$Field) {
    $points = @($Samples | Where-Object { $_.Minute -ge 15 -and $_.Note -eq "" -and $null -ne $_.$Field })
    if ($points.Count -lt 3) { return $null }
    $mx = ($points | Measure-Object Minute -Average).Average
    $my = ($points | Measure-Object $Field -Average).Average
    $num = 0.0; $den = 0.0
    foreach ($pt in $points) { $num += ($pt.Minute - $mx) * ($pt.$Field - $my); $den += ($pt.Minute - $mx) * ($pt.Minute - $mx) }
    if ($den -eq 0) { return $null }
    [math]::Round($num / $den * 60, 1)
}

# ---- Self-test ----

if ($SelfTest) {
    $failed = 0
    function Check([string]$What, [bool]$Ok) { if ($Ok) { Write-Host "  ok    $What" } else { Write-Host "  FAIL  $What"; $script:failed++ } }
    $heap = Read-HeapInfo " garbage-first heap   total 262144K, used 131072K [0x00000000c0000000, 0x0000000100000000)"
    Check "heap total" ($heap.HeapMB -eq 256)
    Check "heap used" ($heap.HeapUsedMB -eq 128)
    $nmt = Read-NativeMemory "Total: reserved=2097152KB, committed=524288KB`n-                 Java Heap (reserved=1048576KB, committed=262144KB)`n-                     Class (reserved=1048576KB, committed=10240KB)`n-                     Arena Chunk (reserved=2048KB, committed=2048KB)"
    Check "native total" ($nmt["NmtMB"] -eq 512)
    Check "native heap part" ($nmt["NmtJavaHeap"] -eq 256)
    Check "native class part" ($nmt["NmtClass"] -eq 10)
    Check "native part with a space in its name" ($nmt["NmtArenaChunk"] -eq 2)
    $points = 0..10 | ForEach-Object { [pscustomobject]@{ Minute = 15 + $_ * 6; Note = ""; PrivateMB = 1000 + $_ * 10 } }
    Check "growth an hour (10 MB each 6 min is 100 MB/h)" ((Get-Slope $points "PrivateMB") -eq 100)
    $own = Get-Process -Id $PID
    $named = @($own.Threads | ForEach-Object { [OctoSoak.Win]::ThreadName($_.Id) } | Where-Object { $_ -ne $null })
    Check "reading thread names ($($named.Count) of $($own.Threads.Count) here)" ($named.Count -ge 0)
    if (-not (Test-Path (Join-Path $Jdk "bin\jcmd.exe"))) { Check "jcmd at $Jdk" $false }
    if ($failed) { throw "$failed self-test checks failed" }
    Write-Host "All self-test checks passed."
    return
}

# ---- The run ----

if (-not $App) { $App = Join-Path $root "desktop\build\compose\binaries\main\app\Octo" }
$App = (Resolve-Path $App).Path
if (-not (Test-Path (Join-Path $Jdk "bin\jcmd.exe"))) { throw "No jcmd in $Jdk; pass -Jdk <a full JDK 17>" }
$soak = Join-Path $root "desktop\build\soak"
$out = Join-Path $soak $Label
if (Test-Path $out) { Remove-Item -Recurse -Force $out -Confirm:$false }
New-Item -ItemType Directory -Force $out | Out-Null
if (-not $Queue) { $Queue = Join-Path $soak "queue.txt" }
$profileDir = Join-Path ([IO.Path]::GetTempPath()) "octo-soak-$Label"

# The profile: the settings of the Octo in use made safe (measure-desktop.ps1),
# then this run's look, no volume and a fixed window.
& (Join-Path $PSScriptRoot "measure-desktop.ps1") -App $App -ProfileDir $profileDir -WithLibrary -DryRun | Out-Null
foreach ($place in "config\settings.json", "Roaming\Octo\settings.json") {
    $file = Join-Path $profileDir $place
    $settings = Get-Content -Raw -Encoding UTF8 $file | ConvertFrom-Json
    foreach ($group in "appearance", "playback") { if (-not $settings.$group) { $settings | Add-Member -NotePropertyName $group -NotePropertyValue ([pscustomobject]@{}) } }
    $settings.appearance | Add-Member -NotePropertyName animated_art -NotePropertyValue $Art -Force
    $settings.appearance | Add-Member -NotePropertyName ambience -NotePropertyValue $(if ($Wash -eq "on") { "Immersive" } else { "Glow" }) -Force
    $settings.playback | Add-Member -NotePropertyName volume -NotePropertyValue 0 -Force
    if (-not $settings.appearance.wash) { $settings.appearance | Add-Member -NotePropertyName wash -NotePropertyValue ([pscustomobject]@{}) }
    $settings.appearance.wash | Add-Member -NotePropertyName moving -NotePropertyValue ($WashMotion -eq "on") -Force
    $settings | Add-Member -NotePropertyName window -NotePropertyValue ([pscustomobject]@{ x = 60; y = 60; width = $Width; height = $Height; maximized = $false }) -Force
    [IO.File]::WriteAllText($file, ($settings | ConvertTo-Json -Depth 32), (New-Object System.Text.UTF8Encoding($false)))
}
$plan = Join-Path $profileDir "soak.properties"
$planText = "source=$Source`nlyrics=$Lyrics`nfull=$Full`npauseAfter=$PauseAfter`ncacheAfter=$CacheAfter`nadvance=$Advance`nqueue=$($Queue -replace '\\', '/')`n"
[IO.File]::WriteAllText($plan, $planText)

$gcLog = Join-Path $out "gc.log"
$options = "-XX:NativeMemoryTracking=summary -Xlog:gc*:file=$($gcLog -replace '\\', '/'):time,uptime -Docto.soak=$($plan -replace '\\', '/') $Jvm".Trim()
if ($options -match ' "') { throw "Paths with spaces cannot go in JAVA_TOOL_OPTIONS" }

$saved = @{ OCTO_PROFILE_DIR = $env:OCTO_PROFILE_DIR; APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA; JAVA_TOOL_OPTIONS = $env:JAVA_TOOL_OPTIONS }
try {
    $env:OCTO_PROFILE_DIR = $profileDir
    $env:APPDATA = Join-Path $profileDir "Roaming"
    $env:LOCALAPPDATA = Join-Path $profileDir "Local"
    $env:JAVA_TOOL_OPTIONS = $options
    $exe = Join-Path $App "Octo.exe"
    $launcher = Start-Process -FilePath $exe -WorkingDirectory $App -PassThru
} finally {
    foreach ($name in $saved.Keys) { if ($saved[$name]) { Set-Item -Path "Env:$name" -Value $saved[$name] } else { Remove-Item "Env:$name" -ErrorAction SilentlyContinue } }
}

$clock = [Diagnostics.Stopwatch]::StartNew()
$process = $null
try {
    # The launcher starts the app as a child Octo.exe; that is the one to watch.
    while (-not $process -and $clock.Elapsed.TotalSeconds -lt 90) {
        $child = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($launcher.Id) AND Name='Octo.exe'" | Select-Object -First 1
        if ($child) { $process = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue }
        if (-not $process) { $launcher.Refresh(); if ($launcher.HasExited) { throw "Octo ended before starting" }; Start-Sleep -Milliseconds 200 }
    }
    if (-not $process) { throw "Octo did not start" }
    while ($clock.Elapsed.TotalSeconds -lt 120) {
        $process.Refresh()
        if ($process.MainWindowHandle -ne [IntPtr]::Zero -and [OctoSoak.Win]::IsWindowVisible($process.MainWindowHandle)) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($Minimized) { Start-Sleep -Seconds 20; [void][OctoSoak.Win]::ShowWindow($process.MainWindowHandle, 6) }
    Write-Host "Soak $Label`: pid $($process.Id), art $Art, wash $Wash (moving $WashMotion), lyrics $Lyrics, full player $Full, $Source, $(if ($Minimized) { 'minimized' } else { 'shown' }), $Advance s a song, $Minutes min"

    $shown = $clock.Elapsed.TotalSeconds
    $minimizedLate = $false
    $shotsDue = @($Shots -split ',' | Where-Object { $_.Trim() } | ForEach-Object { [int]$_ } | Sort-Object)
    $csv = Join-Path $out "samples.csv"
    $samples = @()
    $end = $Minutes * 60
    $next = 0
    while ($clock.Elapsed.TotalSeconds -lt $end) {
        if ($clock.Elapsed.TotalSeconds -ge $next) {
            $process.Refresh()
            if ($process.HasExited) { throw "Octo ended during the soak (exit $($process.ExitCode))" }
            $sample = Get-Sample $process.Id ($clock.Elapsed.TotalMinutes)
            $samples += $sample
            $sample | Export-Csv -NoTypeInformation -Append -Path $csv
            $next += $Every
        }
        if ($MinimizeAfter -gt 0 -and -not $minimizedLate -and $clock.Elapsed.TotalMinutes -ge $MinimizeAfter) {
            $process.Refresh()
            [void][OctoSoak.Win]::ShowWindow($process.MainWindowHandle, 6)
            $minimizedLate = $true
        }
        while ($shotsDue.Count -gt 0 -and $clock.Elapsed.TotalSeconds - $shown -ge $shotsDue[0]) {
            $process.Refresh()
            Save-WindowShot $process.MainWindowHandle (Join-Path $out "shot-$($shotsDue[0]).png")
            $shotsDue = @($shotsDue | Select-Object -Skip 1)
        }
        Start-Sleep -Seconds 1
    }
    # A full collection, twice (the first lets the cleaners run), then the
    # memory again.
    $before = Get-Sample $process.Id ($clock.Elapsed.TotalMinutes) "before GC"
    [void](Invoke-Jcmd $process.Id "GC.run")
    Start-Sleep -Seconds 20
    [void](Invoke-Jcmd $process.Id "GC.run")
    Start-Sleep -Seconds 20
    $after = Get-Sample $process.Id ($clock.Elapsed.TotalMinutes) "after GC"
    $before, $after | Export-Csv -NoTypeInformation -Append -Path $csv
    $samples += $before, $after

    $regular = @($samples | Where-Object { $_.Note -eq "" })
    $mark = $regular | Where-Object { $_.Minute -ge 15 } | Select-Object -First 1
    $last = $regular[-1]
    $summary = @(
        "Soak $Label ($((Get-Date).ToString('yyyy-MM-dd HH:mm'))): art $Art, wash $Wash (moving $WashMotion), lyrics $Lyrics, full player $Full, $Source, $(if ($Minimized) { 'minimized' } elseif ($MinimizeAfter) { "minimized after $MinimizeAfter min" } else { 'shown' }), $(if ($PauseAfter) { "paused after $PauseAfter min, " })$Advance s a song, $Minutes min, JVM extra '$Jvm'",
        "Private MB: start $($regular[0].PrivateMB), 15 min $($mark.PrivateMB), end $($last.PrivateMB), most $(($regular | Measure-Object PrivateMB -Maximum).Maximum), after GC $($after.PrivateMB) (drop $([math]::Round($before.PrivateMB - $after.PrivateMB, 1)))",
        "Growth MB/h from 15 min: private $(Get-Slope $samples 'PrivateMB'), working set $(Get-Slope $samples 'WorkingSetMB'), outside the JVM $(Get-Slope $samples 'OutsideJvmMB'), JVM total $(Get-Slope $samples 'NmtMB'), heap used $(Get-Slope $samples 'HeapUsedMB'), GPU dedicated $(Get-Slope $samples 'GpuDedicatedMB')",
        "End: working set $($last.WorkingSetMB), threads $($last.Threads), octo-video threads $($last.VideoThreads), handles $($last.Handles), heap $($last.HeapUsedMB)/$($last.HeapMB), JVM total $($last.NmtMB), outside the JVM $($last.OutsideJvmMB), GPU dedicated $($last.GpuDedicatedMB)",
        "After GC: working set $($after.WorkingSetMB), heap $($after.HeapUsedMB)/$($after.HeapMB), JVM total $($after.NmtMB), outside the JVM $($after.OutsideJvmMB)",
        "Within 300 MB of the 15-minute mark at the end: $([math]::Abs($last.PrivateMB - $mark.PrivateMB) -le 300)"
    )
    $summary | Set-Content -Path (Join-Path $out "summary.txt")
    $summary | ForEach-Object { Write-Host $_ }
} finally {
    if ($process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            [void]$process.CloseMainWindow()
            if (-not $process.WaitForExit(15000)) { Stop-Process -Id $process.Id -Force -Confirm:$false }
        }
    }
    if (-not $launcher.WaitForExit(5000)) { Stop-Process -Id $launcher.Id -Force -Confirm:$false -ErrorAction SilentlyContinue }
    if (Test-Path "$plan.events") { Copy-Item "$plan.events" (Join-Path $out "events.log") }
    if (-not $Keep) { Remove-Item -Recurse -Force $profileDir -Confirm:$false -ErrorAction SilentlyContinue }
}
