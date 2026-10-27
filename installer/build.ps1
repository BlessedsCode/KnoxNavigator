param([string]$Repository = '__REPOSITORY__')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $output -Force | Out-Null
if ($Repository -ne '__REPOSITORY__' -and $Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Expected owner/repository.' }
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'KnoxNavigatorSetup.cs')).Replace('__REPOSITORY__', $Repository)
$generated = Join-Path $output 'KnoxNavigatorSetup.generated.cs'
[IO.File]::WriteAllText($generated, $source, [Text.UTF8Encoding]::new($true))
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$executable = Join-Path $output 'KnoxNavigatorSetup.exe'
& $compiler /nologo /target:winexe /platform:anycpu "/out:$executable" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll $generated
if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
Write-Output "Installer built: $executable"
