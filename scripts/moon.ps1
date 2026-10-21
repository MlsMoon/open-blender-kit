#Requires -Version 7.0
# 保持参数数组，不拼接 shell 命令；工具路径只在运行时发现。
$ErrorActionPreference = 'Stop'
$folder = $env:MOON_ARTS_TOOL_DIR
if (-not $folder) {
    foreach ($start in @($PWD.Path, $PSScriptRoot)) {
        $cursor = [IO.DirectoryInfo]::new($start)
        while ($null -ne $cursor) {
            $candidate = Join-Path $cursor.FullName 'Tools/MoonArtsTool'
            if (Test-Path -LiteralPath (Join-Path $candidate 'manifest.json')) {
                $folder = $candidate
                break
            }
            $cursor = $cursor.Parent
        }
        if ($folder) { break }
    }
}
if (-not $folder) {
    throw 'Moon Arts CLI not found. Provide Tools/MoonArtsTool or set MOON_ARTS_TOOL_DIR for this process.'
}
$exe = Join-Path $folder 'MoonArtsToolCLI.exe'
$manifestPath = Join-Path $folder 'manifest.json'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or
    -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw 'Moon Arts CLI and manifest.json must be supplied together.'
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.file -ne 'MoonArtsToolCLI.exe' -or $manifest.protocol -ne 1) {
    throw 'Unsupported tool manifest.'
}
$actual = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $manifest.sha256) {
    throw 'CLI SHA256 mismatch. Restore a matching EXE and manifest.'
}
& $exe @args
exit $LASTEXITCODE
