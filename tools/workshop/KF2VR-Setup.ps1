# KF2-VR Workshop setup: puts the "Play in VR / Play normally" choice on
# Killing Floor 2's Play button. Run it again to take it off.
#
# Players run one line (Windows+R, paste, Enter):
#   powershell -ep bypass -c "irm https://raw.githubusercontent.com/optimumbox/Killing-Floor-2-VR/vr-dlss-fixes/tools/workshop/KF2VR-Setup.ps1|iex"
#
# It finds Killing Floor 2 in any Steam library, checks the Workshop item has
# downloaded (opening its page to subscribe if not), closes Steam briefly,
# writes the game's Launch Options for every Steam account on this PC (after a
# backup) and starts Steam again. No parameters, so it also runs through iex.
# Testing: set $env:KF2VR_TEST_CONFIG to a copy of localconfig.vdf and
# $env:KF2VR_TEST_PLAY to a Play.cmd path; Steam is then left alone.

$ErrorActionPreference = 'Stop'
$ItemId = '3817663661'
$AppId = '232090'
$Title = 'KF2-VR setup'
$Test = [bool]$env:KF2VR_TEST_CONFIG

Add-Type -AssemblyName System.Windows.Forms
function Say([string]$Text, [string]$Buttons = 'OK') {
    if ($Test) { Write-Output "[dialog] $Text"; return 'OK' }
    return [string][System.Windows.Forms.MessageBox]::Show($Text, $Title, $Buttons, 'Information')
}

# --- Steam's text config (VDF): find a child block by key within a range ----
function Find-Block([string]$T, [int]$From, [int]$To, [string]$Key) {
    $depth = 0; $i = $From
    while ($i -lt $To) {
        $c = $T[$i]
        if ($c -eq '"') {
            $j = $i + 1
            while ($j -lt $To -and $T[$j] -ne '"') { if ($T[$j] -eq '\') { $j++ }; $j++ }
            $token = $T.Substring($i + 1, $j - $i - 1)
            $k = $j + 1
            while ($k -lt $To -and [char]::IsWhiteSpace($T[$k])) { $k++ }
            if ($depth -eq 0 -and $k -lt $To -and $T[$k] -eq '{' -and $token -ieq $Key) {
                $d = 0; $m = $k
                while ($m -lt $To) {
                    if ($T[$m] -eq '"') { $m++; while ($m -lt $To -and $T[$m] -ne '"') { if ($T[$m] -eq '\') { $m++ }; $m++ } }
                    elseif ($T[$m] -eq '{') { $d++ }
                    elseif ($T[$m] -eq '}') { $d--; if ($d -eq 0) { return @($i, $k, $m) } }
                    $m++
                }
                return $null
            }
            $i = $j + 1; continue
        }
        if ($c -eq '{') { $depth++ } elseif ($c -eq '}') { $depth-- }
        $i++
    }
    return $null
}

# The tabs in front of the closing brace at $At: the block's own indent.
function Line-Indent([string]$T, [int]$At) {
    $start = $T.LastIndexOf("`n", [Math]::Max($At - 1, 0)) + 1
    return $T.Substring($start, $At - $start)
}

function Vdf-Escape([string]$S) { return $S.Replace('\', '\\').Replace('"', '\"') }

# Returns the new text, or $null when the file's layout is not understood.
function Set-LaunchOptions([string]$T, [string]$Value) {
    $b = Find-Block $T 0 $T.Length 'UserLocalConfigStore'
    if (-not $b) { return $null }
    foreach ($key in 'Software', 'Valve', 'Steam', 'apps') {
        $b = Find-Block $T ($b[1] + 1) $b[2] $key
        if (-not $b) { return $null }
    }
    $apps = $b
    $game = Find-Block $T ($apps[1] + 1) $apps[2] $AppId
    $line = "`"LaunchOptions`"`t`t`"" + (Vdf-Escape $Value) + "`""
    if (-not $game) {
        if ($Value -eq '') { return $T }
        $pad = Line-Indent $T $apps[2]
        $insert = "`t$pad`"$AppId`"`n`t$pad{`n`t`t$pad$line`n`t$pad}`n$pad"
        return $T.Substring(0, $apps[2]).TrimEnd("`t") + $insert + $T.Substring($apps[2])
    }
    $pad = Line-Indent $T $game[2]
    $body = $T.Substring($game[1] + 1, $game[2] - $game[1] - 1)
    $pattern = '(?m)^([ \t]*)"LaunchOptions"[ \t]+"(?:[^"\\]|\\.)*"[ \t]*\r?\n?'
    if ([regex]::IsMatch($body, $pattern)) {
        $evaluator = { param($m) if ($Value -eq '') { '' } else { $m.Groups[1].Value + $line + "`n" } }
        $body = [regex]::Replace($body, $pattern, $evaluator, 1)
    } elseif ($Value -ne '') {
        $body = $body.TrimEnd("`t") + "`t$pad$line`n$pad"
    }
    return $T.Substring(0, $game[1] + 1) + $body + $T.Substring($game[2])
}

function Get-LaunchOptions([string]$T) {
    $b = Find-Block $T 0 $T.Length 'UserLocalConfigStore'
    foreach ($key in 'Software', 'Valve', 'Steam', 'apps', $AppId) {
        if (-not $b) { return '' }
        $b = Find-Block $T ($b[1] + 1) $b[2] $key
    }
    if (-not $b) { return '' }
    $m = [regex]::Match($T.Substring($b[1], $b[2] - $b[1]), '"LaunchOptions"[ \t]+"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return '' }
    return $m.Groups[1].Value.Replace('\"', '"').Replace('\\', '\')
}

# --- Find Steam, Killing Floor 2 and the Workshop item ----------------------
$steam = $null
try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam').SteamPath } catch {}
if ($Test) { $steam = 'TEST' }
if (-not $steam) { Say "Steam isn't installed on this PC. Install Steam and Killing Floor 2 first."; return }
$steam = $steam.Replace('/', '\')

if ($Test) { $play = $env:KF2VR_TEST_PLAY; $configs = @(Get-Item $env:KF2VR_TEST_CONFIG) }
else {
    $libraries = @($steam)
    $folders = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $folders) {
        foreach ($m in [regex]::Matches((Get-Content $folders -Raw), '"path"\s+"((?:[^"\\]|\\.)*)"')) {
            $libraries += $m.Groups[1].Value.Replace('\\', '\')
        }
    }
    $library = $libraries | Where-Object { Test-Path (Join-Path $_ "steamapps\appmanifest_$AppId.acf") } | Select-Object -First 1
    if (-not $library) { Say "Killing Floor 2 isn't installed. Install it in Steam, then run this setup again."; return }
    $item = Join-Path $library "steamapps\workshop\content\$AppId\$ItemId"
    # The item's top-level Play.cmd is the stable entry point.
    $play = Join-Path $item 'Play.cmd'
    if ((Test-Path $item) -and -not (Test-Path $play)) {
        Start-Process 'steam://open/downloads'
        Say ("Steam hasn't finished downloading KF2VR yet.`n`n" +
             "Steam often waits for the game to start before it downloads Workshop items:`n" +
             "1. Press Play on Killing Floor 2.`n2. Wait for the main menu, then quit the game.`n" +
             "3. Run this setup again.`n`n" +
             "Still not working? On the KF2VR Workshop page click Unsubscribe, then Subscribe, and repeat.")
        return
    }
    if (-not (Test-Path $play)) {
        Start-Process "steam://url/CommunityFilePage/$ItemId"
        Say ("Almost there.`n`n1. Steam is opening the KF2VR Workshop page: click Subscribe.`n" +
             "2. Press Play on Killing Floor 2 once, wait for the main menu, then quit`n" +
             "   (Steam downloads KF2VR when the game starts).`n3. Run this setup again.")
        return
    }
    $configs = @(Get-ChildItem (Join-Path $steam 'userdata\*\config\localconfig.vdf') -ErrorAction SilentlyContinue)
    if ($configs.Count -eq 0) { Say "Start Steam and log in once, then run this setup again."; return }
}

$option = "`"$play`" %command%"
# Already pointing here: offer to take it off. Pointing at an older copy of
# the item (a renamed folder): just repoint it.
$current = @($configs | ForEach-Object { Get-LaunchOptions ([IO.File]::ReadAllText($_.FullName)) })
$installed = @($current | Where-Object { $_ -eq $option }).Count -gt 0
if ($installed) {
    $answer = Say ("KF2-VR is already set up on Killing Floor 2's Play button.`n`n" +
                   "Remove it, so Play starts plain Killing Floor 2 again?") 'YesNo'
    if ($answer -ne 'Yes' -and -not $Test) { return }
    $option = ''
}

# --- Steam rewrites its config on exit: close it, edit, start it again -------
$running = (-not $Test) -and [bool](Get-Process steam -ErrorAction SilentlyContinue)
if ($running) {
    if ((Say "Steam will close for a few seconds while this is set up, then open again. OK?" 'OKCancel') -ne 'OK') { return }
    Start-Process (Join-Path $steam 'steam.exe') '-shutdown'
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Process steam -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    if (Get-Process steam -ErrorAction SilentlyContinue) { Say "Steam didn't close. Close Steam yourself (Steam > Exit), then run this setup again."; return }
    Start-Sleep -Seconds 1
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$changed = 0
foreach ($file in $configs) {
    $text = [IO.File]::ReadAllText($file.FullName)
    $new = Set-LaunchOptions $text $option
    if ($null -eq $new) { continue }
    if ($new -ne $text) {
        Copy-Item $file.FullName ($file.FullName + '.kf2vr-backup') -Force
        [IO.File]::WriteAllText($file.FullName, $new, $utf8)
    }
    $changed++
}
if (-not $Test) { Start-Process (Join-Path $steam 'steam.exe') }

if ($changed -eq 0) {
    Set-Clipboard -Value $option
    Say ("Couldn't change the setting automatically. It's copied to your clipboard instead:`n`n" +
         "In Steam, right-click Killing Floor 2 > Properties > Launch Options, then press Ctrl+V.")
} elseif ($option -eq '') {
    Say "Done. Pressing Play on Killing Floor 2 starts the normal game again."
} else {
    Say ("Done!`n`nIn Steam, press Play on Killing Floor 2. A window asks:`n" +
         "  Play in VR  or  Play normally`n`nTo undo this later, run the same setup again.")
}
