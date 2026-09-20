#Requires -Version 7.0
param(
    [switch]$CheckOnly,
    [switch]$Launch,
    [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
$skillRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $skillRoot

$script:fail = 0
$script:backupDir = $null
$script:clientConfigChanged = $false

function Write-Ok([string]$Message) { Write-Host "OK    $Message" }
function Write-Warn([string]$Message) { Write-Host "WARN  $Message" }
function Write-Fail([string]$Message) { Write-Host "FAIL  $Message"; $script:fail++ }

function Get-BackupDir {
    if (-not $script:backupDir) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $script:backupDir = Join-Path $skillRoot "tmp\config-backups\$stamp"
        New-Item -ItemType Directory -Force -Path $script:backupDir | Out-Null
    }
    return $script:backupDir
}

function Save-BackupText([string]$Name, [string]$Content) {
    Set-Content -LiteralPath (Join-Path (Get-BackupDir) $Name) -Value $Content -Encoding utf8
}

function Find-Blender([string]$ConfiguredPath) {
    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($ConfiguredPath) { [void]$candidates.Add($ConfiguredPath) }

    $command = Get-Command blender -ErrorAction SilentlyContinue
    if ($command) { [void]$candidates.Add($command.Source) }

    foreach ($registryPath in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\blender.exe',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\blender.exe'
    )) {
        $entry = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($entry -and $entry.'(default)') { [void]$candidates.Add([string]$entry.'(default)') }
    }

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $installs = Get-ItemProperty $uninstallRoots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'Blender*' -and $_.InstallLocation }
    foreach ($install in $installs) {
        [void]$candidates.Add((Join-Path ([string]$install.InstallLocation) 'blender.exe'))
    }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        [void]$candidates.Add((Join-Path $root 'Blender Foundation\Blender\blender.exe'))
        [void]$candidates.Add((Join-Path $root 'Steam\steamapps\common\Blender\blender.exe'))
        [void]$candidates.Add((Join-Path $root 'Programs\Blender Foundation\Blender\blender.exe'))
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-BlenderVersionKey([string]$BlenderExe) {
    $output = & $BlenderExe --version 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Blender --version failed with $LASTEXITCODE" }
    $firstLine = [string]($output | Select-Object -First 1)
    if ($firstLine -notmatch '^Blender\s+(\d+\.\d+)') {
        throw "Could not parse Blender version from '$firstLine'"
    }
    return $Matches[1]
}

function Find-Uvx {
    $command = Get-Command uvx -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path $env:USERPROFILE '.local\bin\uvx.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    return $null
}

function Invoke-WithNetwork([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')"
    }
}

function Install-Uv {
    $installer = Join-Path ([System.IO.Path]::GetTempPath()) "open-blender-kit-uv-install-$PID.ps1"
    try {
        Invoke-WithNetwork 'curl.exe' @(
            '--location', '--fail', '--silent', '--show-error',
            'https://astral.sh/uv/install.ps1', '--output', $installer
        )
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
            throw 'uv installer was not downloaded'
        }
        & pwsh -NoProfile -File $installer
        if ($LASTEXITCODE -ne 0) { throw "uv installer exited $LASTEXITCODE" }
    } finally {
        if (Test-Path -LiteralPath $installer -PathType Leaf) {
            Remove-Item -LiteralPath $installer -Force
        }
    }
}

function Get-PortListener([int]$Port) {
    return Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1
}

function Get-PortProcessName([int]$Port) {
    $listener = Get-PortListener $Port
    if (-not $listener) { return $null }
    $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    return $(if ($process) { $process.ProcessName } else { "pid-$($listener.OwningProcess)" })
}

function Find-FreePort([int]$StartPort) {
    for ($candidate = $StartPort; $candidate -le 9899; $candidate++) {
        if (-not (Get-PortListener $candidate)) { return $candidate }
    }
    throw "No free Blender MCP port in range $StartPort-9899"
}

function Test-CodexConfig([string]$Uvx, [string]$HostName, [int]$Port) {
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $codex) { return $null }
    $raw = & $codex.Source mcp get blender --json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return $false }
    try { $config = $raw | ConvertFrom-Json } catch { return $false }
    $transport = $config.transport
    $argsOk = (@($transport.args) -join "`0") -eq (@('--python', '3.11', 'blender-mcp') -join "`0")
    return (
        $transport.type -eq 'stdio' -and
        [string]$transport.command -eq $Uvx -and
        $argsOk -and
        [string]$transport.env.DISABLE_TELEMETRY -eq 'true' -and
        [string]$transport.env.BLENDER_HOST -eq $HostName -and
        [string]$transport.env.BLENDER_PORT -eq [string]$Port
    )
}

function Set-CodexConfig([string]$Uvx, [string]$HostName, [int]$Port) {
    $codex = Get-Command codex -ErrorAction SilentlyContinue
    if (-not $codex) { Write-Warn 'codex command not found; skipped Codex MCP config'; return }
    $existing = & $codex.Source mcp get blender --json 2>$null
    if ($LASTEXITCODE -eq 0 -and $existing) {
        Save-BackupText 'codex-blender.json' ($existing | Out-String)
        & $codex.Source mcp remove blender | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "codex mcp remove exited $LASTEXITCODE" }
    }
    & $codex.Source mcp add blender `
        --env 'DISABLE_TELEMETRY=true' `
        --env 'UV_PYTHON_PREFERENCE=only-managed' `
        --env "BLENDER_HOST=$HostName" `
        --env "BLENDER_PORT=$Port" `
        -- $Uvx --python 3.11 blender-mcp | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "codex mcp add exited $LASTEXITCODE" }
}

function Test-ClaudeConfig([string]$Uvx, [string]$HostName, [int]$Port) {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) { return $null }
    $raw = & $claude.Source mcp get blender 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }
    return (
        $raw.Contains($Uvx) -and
        $raw.Contains('blender-mcp') -and
        $raw.Contains('DISABLE_TELEMETRY') -and
        $raw.Contains($HostName) -and
        $raw.Contains([string]$Port)
    )
}

function Set-ClaudeConfig([string]$Uvx, [string]$HostName, [int]$Port) {
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if (-not $claude) { Write-Warn 'claude command not found; skipped Claude MCP config'; return }
    $existing = & $claude.Source mcp get blender 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Save-BackupText 'claude-blender.txt' $existing
        & $claude.Source mcp remove --scope user blender | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "claude mcp remove exited $LASTEXITCODE" }
    }
    $definition = [ordered]@{
        type = 'stdio'
        command = $Uvx
        args = @('--python', '3.11', 'blender-mcp')
        env = [ordered]@{
            DISABLE_TELEMETRY = 'true'
            UV_PYTHON_PREFERENCE = 'only-managed'
            BLENDER_HOST = $HostName
            BLENDER_PORT = [string]$Port
        }
    } | ConvertTo-Json -Depth 8 -Compress
    & $claude.Source mcp add-json --scope user blender $definition | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "claude mcp add-json exited $LASTEXITCODE" }
}

function Test-CursorConfig([string]$Uvx, [string]$HostName, [int]$Port) {
    $cursor = Get-Command cursor -ErrorAction SilentlyContinue
    $path = Join-Path $env:USERPROFILE '.cursor\mcp.json'
    if (-not $cursor -and -not (Test-Path -LiteralPath $path)) { return $null }
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try { $config = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json } catch { return $false }
    $server = $config.mcpServers.blender
    if (-not $server) { return $false }
    $argsOk = (@($server.args) -join "`0") -eq (@('--python', '3.11', 'blender-mcp') -join "`0")
    return (
        [string]$server.command -eq $Uvx -and
        $argsOk -and
        [string]$server.env.DISABLE_TELEMETRY -eq 'true' -and
        [string]$server.env.BLENDER_HOST -eq $HostName -and
        [string]$server.env.BLENDER_PORT -eq [string]$Port
    )
}

function Set-CursorConfig([string]$Uvx, [string]$HostName, [int]$Port) {
    $cursor = Get-Command cursor -ErrorAction SilentlyContinue
    $path = Join-Path $env:USERPROFILE '.cursor\mcp.json'
    if (-not $cursor -and -not (Test-Path -LiteralPath $path)) {
        Write-Warn 'cursor command and config not found; skipped Cursor MCP config'
        return
    }
    $directory = Split-Path -Parent $path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    if (Test-Path -LiteralPath $path) {
        $raw = Get-Content -Raw -LiteralPath $path
        Save-BackupText 'cursor-mcp.json' $raw
        try { $config = $raw | ConvertFrom-Json } catch { throw "Cursor MCP config is invalid JSON: $path" }
    } else {
        $config = [pscustomobject]@{}
    }
    if (-not $config.PSObject.Properties['mcpServers']) {
        $config | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{})
    }
    $definition = [pscustomobject][ordered]@{
        command = $Uvx
        args = @('--python', '3.11', 'blender-mcp')
        env = [pscustomobject][ordered]@{
            DISABLE_TELEMETRY = 'true'
            UV_PYTHON_PREFERENCE = 'only-managed'
            BLENDER_HOST = $HostName
            BLENDER_PORT = [string]$Port
        }
    }
    $config.mcpServers | Add-Member -NotePropertyName blender -NotePropertyValue $definition -Force
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
}

function Test-Addon([string]$BlenderExe) {
    $expression = 'import addon_utils; print("BLENDER_MCP_CHECK=" + repr([(m.__name__, addon_utils.check(m.__name__)) for m in addon_utils.modules(refresh=True) if m.bl_info.get("name") == "Blender MCP"]))'
    $output = & $BlenderExe --background --python-expr $expression 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0 -and $output -match 'BLENDER_MCP_CHECK=.*\(True, True\)')
}

function Test-AddonTelemetryOff([string]$BlenderExe) {
    $expression = 'import addon_utils; modules=[m.__name__ for m in addon_utils.modules(refresh=True) if m.bl_info.get("name") == "Blender MCP"]; name="blender_mcp" if "blender_mcp" in modules else (modules[-1] if modules else ""); addon_utils.enable(name) if name else None; prefs=bpy.context.preferences.addons[name].preferences if name else None; print("BLENDER_MCP_TELEMETRY_OFF=" + repr(bool(prefs is not None and not getattr(prefs, "telemetry_consent", False))))'
    $output = & $BlenderExe --background --python-expr "import bpy; $expression" 2>&1 | Out-String
    return ($LASTEXITCODE -eq 0 -and $output -match 'BLENDER_MCP_TELEMETRY_OFF=True')
}

function Test-UvPython([string]$Uv) {
    if (-not $Uv) { return $false }
    & $Uv python find 3.11 *> $null
    return ($LASTEXITCODE -eq 0)
}

function Start-HiddenBlender([string]$BlenderExe, [int]$Port, [string]$LogPath) {
    $bootstrap = Join-Path $PSScriptRoot 'start_blender_mcp.py'
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $BlenderExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $false
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    [void]$startInfo.ArgumentList.Add('--python')
    [void]$startInfo.ArgumentList.Add($bootstrap)
    $startInfo.Environment['BLENDER_MCP_PORT'] = [string]$Port
    $startInfo.Environment['BLENDER_MCP_LOG'] = $LogPath
    $process = [System.Diagnostics.Process]::Start($startInfo)
    if (-not $process) { throw 'Blender process did not start' }

    $deadline = [DateTime]::UtcNow.AddSeconds(40)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) {
            $log = $(if (Test-Path -LiteralPath $LogPath) { Get-Content -Raw -LiteralPath $LogPath } else { '' })
            throw "Blender exited before MCP was ready. $log"
        }
        if (Get-PortListener $Port) {
            Write-Ok "hidden Blender pid=$($process.Id) port=$Port"
            return $process
        }
        Start-Sleep -Milliseconds 500
    }
    throw "Blender MCP addon did not listen on port $Port within 40 seconds"
}

$mode = if ($CheckOnly) { 'check' } elseif ($SmokeTest) { 'smoke' } elseif ($Launch) { 'launch' } else { 'configure' }
Write-Host "skillRoot=$skillRoot  mode=$mode"

$localPath = Join-Path $skillRoot 'local\blender.local.json'
$examplePath = Join-Path $skillRoot 'local\blender.local.json.example'
$config = $null
if (Test-Path -LiteralPath $localPath) {
    try { $config = Get-Content -Raw -LiteralPath $localPath | ConvertFrom-Json } catch { Write-Fail "invalid $localPath" }
} elseif ($CheckOnly) {
    Write-Fail 'missing local/blender.local.json (run ensure.ps1)'
    if (Test-Path -LiteralPath $examplePath) { $config = Get-Content -Raw -LiteralPath $examplePath | ConvertFrom-Json }
} elseif (Test-Path -LiteralPath $examplePath) {
    Copy-Item -LiteralPath $examplePath -Destination $localPath
    $config = Get-Content -Raw -LiteralPath $localPath | ConvertFrom-Json
    Write-Ok 'created local/blender.local.json'
} else {
    Write-Fail 'missing local/blender.local.json.example'
}

$configuredExe = $(if ($config) { [string]$config.executable } else { '' })
$blenderExe = Find-Blender $configuredExe
$versionKey = $null
if (-not $blenderExe) {
    Write-Fail 'Blender executable not found; install Blender or set local/blender.local.json'
} else {
    try {
        $versionKey = Get-BlenderVersionKey $blenderExe
        Write-Ok "Blender $versionKey at $blenderExe"
    } catch {
        Write-Fail $_.Exception.Message
    }
}

$hostName = $(if ($config -and $config.host) { [string]$config.host } else { '127.0.0.1' })
$port = $(if ($config -and $config.port) { [int]$config.port } else { 9876 })
$occupant = Get-PortProcessName $port
if ($occupant -and $occupant -notmatch '^blender') {
    if ($CheckOnly) {
        Write-Fail "port $port is occupied by $occupant"
    } else {
        $oldPort = $port
        $port = Find-FreePort ([Math]::Max(9877, $port + 1))
        Write-Warn "port $oldPort is occupied by $occupant; selected $port"
    }
}

if ($config -and -not $CheckOnly -and $blenderExe) {
    $config.executable = $blenderExe
    $config.host = $hostName
    $config.port = $port
    $config.launchMode = 'hidden'
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $localPath -Encoding utf8
}

$uvx = Find-Uvx
if (-not $uvx -and -not $CheckOnly) {
    Write-Warn 'uvx not found; installing uv from the official installer'
    try { Install-Uv; $uvx = Find-Uvx } catch { Write-Fail $_.Exception.Message }
}
if ($uvx) { Write-Ok "uvx=$uvx" } else { Write-Fail 'uvx not found' }
$uv = $(if ($uvx) { Join-Path (Split-Path -Parent $uvx) 'uv.exe' } else { $null })
if ($uv -and -not (Test-Path -LiteralPath $uv -PathType Leaf)) { $uv = $null }

if (-not $CheckOnly -and $uvx -and $blenderExe -and $script:fail -eq 0) {
    try {
        if (Test-UvPython $uv) {
            Write-Ok 'uv-managed Python 3.11 already installed'
        } else {
            Invoke-WithNetwork $uv @('python', 'install', '3.11')
            Write-Ok 'installed uv-managed Python 3.11'
        }

        if (Test-Addon $blenderExe) {
            Write-Ok 'Blender MCP addon already installed and enabled'
            if (Test-AddonTelemetryOff $blenderExe) {
                Write-Ok 'Blender MCP telemetry already disabled'
            } else {
                & $blenderExe --background --python (Join-Path $PSScriptRoot 'configure_addon.py') | Out-Host
                if ($LASTEXITCODE -ne 0) { throw "Blender telemetry configuration exited $LASTEXITCODE" }
                Write-Ok 'Blender MCP telemetry disabled'
            }
        } else {
            $addonsDir = Join-Path $env:APPDATA "Blender Foundation\Blender\$versionKey\scripts\addons"
            New-Item -ItemType Directory -Force -Path $addonsDir | Out-Null
            $previousAddonsDir = $env:BLENDERMCP_ADDONS_DIR
            $env:BLENDERMCP_ADDONS_DIR = $addonsDir
            try {
                Invoke-WithNetwork $uvx @('--python', '3.11', 'blender-mcp', 'install-addon')
            } catch {
                Write-Warn 'first addon install failed; refreshing blender-mcp cache once'
                & $uv cache clean blender-mcp | Out-Host
                Invoke-WithNetwork $uvx @('--refresh', '--python', '3.11', 'blender-mcp', 'install-addon')
            } finally {
                if ($null -eq $previousAddonsDir) { Remove-Item Env:BLENDERMCP_ADDONS_DIR -ErrorAction SilentlyContinue }
                else { $env:BLENDERMCP_ADDONS_DIR = $previousAddonsDir }
            }
            & $blenderExe --background --python (Join-Path $PSScriptRoot 'configure_addon.py') | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "Blender addon configuration exited $LASTEXITCODE" }
            Write-Ok 'Blender MCP addon installed and enabled'
        }
    } catch {
        Write-Fail $_.Exception.Message
    }
} elseif ($CheckOnly -and $blenderExe) {
    if (Test-Addon $blenderExe) { Write-Ok 'Blender MCP addon enabled' }
    else { Write-Fail 'Blender MCP addon missing or disabled' }
    if (Test-AddonTelemetryOff $blenderExe) { Write-Ok 'Blender MCP telemetry disabled' }
    else { Write-Fail 'Blender MCP telemetry is enabled' }
}

if ($uvx) {
    $codexOk = Test-CodexConfig $uvx $hostName $port
    $claudeOk = Test-ClaudeConfig $uvx $hostName $port
    $cursorOk = Test-CursorConfig $uvx $hostName $port
    if ($CheckOnly) {
        if ($null -eq $codexOk) { Write-Warn 'Codex not installed' } elseif ($codexOk) { Write-Ok 'Codex blender MCP config' } else { Write-Fail 'Codex blender MCP config missing or stale' }
        if ($null -eq $claudeOk) { Write-Warn 'Claude not installed' } elseif ($claudeOk) { Write-Ok 'Claude blender MCP config' } else { Write-Fail 'Claude blender MCP config missing or stale' }
        if ($null -eq $cursorOk) { Write-Warn 'Cursor not installed' } elseif ($cursorOk) { Write-Ok 'Cursor blender MCP config' } else { Write-Fail 'Cursor blender MCP config missing or stale' }
    } elseif ($script:fail -eq 0) {
        try {
            if (-not $codexOk) { Set-CodexConfig $uvx $hostName $port; $script:clientConfigChanged = $true }
            if (-not $claudeOk) { Set-ClaudeConfig $uvx $hostName $port; $script:clientConfigChanged = $true }
            if (-not $cursorOk) { Set-CursorConfig $uvx $hostName $port; $script:clientConfigChanged = $true }
            Write-Ok 'Codex/Claude/Cursor blender MCP configs ready'
        } catch {
            Write-Fail $_.Exception.Message
        }
    }
}

$startedProcess = $null
$listenerBeforeLaunch = Get-PortListener $port
if (($Launch -or $SmokeTest) -and $script:fail -eq 0) {
    try {
        if ($listenerBeforeLaunch) {
            Write-Ok "Blender MCP port $port already listening"
        } else {
            $logPath = Join-Path $skillRoot 'tmp\blender-startup.log'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $logPath) | Out-Null
            $startedProcess = Start-HiddenBlender $blenderExe $port $logPath
        }
    } catch {
        Write-Fail $_.Exception.Message
    }
}

if ($SmokeTest -and $script:fail -eq 0) {
    try {
        $smoke = Join-Path $PSScriptRoot 'mcp_smoke_test.py'
        $case = Join-Path $PSScriptRoot 'build_suzanne.py'
        $output = Join-Path $skillRoot 'tmp\cases'
        $arguments = @(
            'run', '--python', '3.11', '--with', 'mcp', '--no-project', 'python', $smoke,
            '--uvx', $uvx, '--host', $hostName, '--port', [string]$port,
            '--output-dir', $output, '--case-script', $case
        )
        if ($listenerBeforeLaunch) { $arguments += '--health-only' }
        Invoke-WithNetwork $uv $arguments
        Write-Ok 'real Blender MCP smoke test passed'
    } catch {
        Write-Fail $_.Exception.Message
    } finally {
        if ($startedProcess -and -not $startedProcess.HasExited) {
            Stop-Process -Id $startedProcess.Id
            Write-Ok "stopped isolated Blender pid=$($startedProcess.Id)"
        }
    }
}

if ($script:backupDir) { Write-Host "backup=$script:backupDir" }
if (-not $CheckOnly -and $script:fail -eq 0 -and $script:clientConfigChanged) {
    Write-Warn 'Restart Codex, Claude, and Cursor to reload a newly added MCP server.'
}
if ($script:fail -gt 0) {
    Write-Host "DONE  $script:fail FAIL"
    exit 1
}
Write-Host 'DONE  Blender MCP ready'
exit 0
