param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FlutterArgs
)

$ErrorActionPreference = 'Stop'

$drive = 'X:'
$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')
$spaceParent = Resolve-Path -LiteralPath (Join-Path $repoRoot '..\..')
$mappedRepo = "$drive\stormSync\storm_sync"
$mappedFlutter = "$drive\flutter\bin\flutter.bat"

$existingMapping = (subst) | Where-Object { $_ -like "$drive*=>" }
if ($existingMapping) {
    throw "$drive is already mapped. Choose a free drive letter in this script."
}

try {
    subst $drive $spaceParent.Path
    Push-Location $mappedRepo
    & $mappedFlutter @FlutterArgs
    exit $LASTEXITCODE
}
finally {
    if ((Get-Location).Path -like "$drive*") {
        Pop-Location
    }
    subst $drive /D 2>$null
}
