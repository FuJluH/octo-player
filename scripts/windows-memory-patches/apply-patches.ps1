# Накладывает эти патчи на новую версию Octo.
#
#   powershell -File apply-patches.ps1 -Base desktop-v1.11.0
#   powershell -File apply-patches.ps1 -Base origin/main
#   powershell -File apply-patches.ps1 -Base ab79bfe -Branch fix/windows-native-memory
#
# Делает в репозитории новую ветку от указанной версии и применяет патчи по
# одному через git am -3 (three-way merge), сохраняя тексты коммитов.
param(
    [Parameter(Mandatory = $true)][string]$Base,
    [string]$Repo = "C:\Projects\octo\octo-player",
    [string]$PatchDir = "",
    [string]$Branch = ""
)
$ErrorActionPreference = "Stop"
if ($PatchDir -eq "") {
    # $PSScriptRoot пуст, когда скрипт вызывают через powershell -File.
    $PatchDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "patches"
}

function Invoke-Git {
    param([string[]]$GitArgs, [switch]$AllowFail)
    $out = & git -C $Repo @GitArgs 2>&1
    $code = $LASTEXITCODE
    ($out | Out-String).Trim() | Write-Host
    if ($code -ne 0 -and -not $AllowFail) { throw "git $($GitArgs -join ' ') — код $code" }
    return $code
}

# 1. Свежие теги и ветки из оригинального репозитория (когда есть сеть).
Invoke-Git -GitArgs @("fetch", "origin", "--tags", "--prune") -AllowFail | Out-Null

# 2. Версия, на которую накатываем: тег, ветка, origin/ветка или хеш.
$baseRef = ""
foreach ($try in @($Base, "refs/tags/$Base", "origin/$Base")) {
    if ((Invoke-Git -GitArgs @("rev-parse", "--verify", "--quiet", $try) -AllowFail) -eq 0) { $baseRef = $try; break }
}
if ($baseRef -eq "") { throw "Не нашёл версию '$Base' в $Repo" }
Write-Host "База: $baseRef -> $(git -C $Repo rev-parse --short $baseRef)"

# 3. Новая ветка поверх неё.
if ($Branch -eq "") {
    $short = (git -C $Repo rev-parse --short $baseRef).Trim()
    $Branch = "fix/windows-native-memory-$short"
}
if ((Invoke-Git -GitArgs @("rev-parse", "--verify", "--quiet", "refs/heads/$Branch") -AllowFail) -eq 0) {
    throw "Ветка '$Branch' уже есть. Удали её (git branch -D $Branch) или задай -Branch другое имя."
}
Invoke-Git -GitArgs @("checkout", "-q", "-b", $Branch, $baseRef) | Out-Null

# 4. Патчи по одному, с сохранением коммитов.
$patches = Get-ChildItem -LiteralPath $PatchDir -Filter "*.patch" | Sort-Object Name
if ($patches.Count -eq 0) { throw "В $PatchDir нет .patch-файлов" }
foreach ($p in $patches) {
    Write-Host "`n=== $($p.Name) ==="
    $code = Invoke-Git -GitArgs @("am", "-3", "--keep-cr", $p.FullName) -AllowFail
    if ($code -ne 0) {
        $conflicts = (git -C $Repo diff --name-only --diff-filter=U) | Out-String
        Write-Host @"
Патч $($p.Name) лёг с конфликтом.
Файлы с метками <<<<<<< :
$conflicts
Разрежь их, сделай git add <файл> и продолжи:  git -C $Repo am --continue
Пропустить этот патч:                        git -C $Repo am --skip
Отменить всё наложенное:                    git -C $Repo am --abort
"@
        exit 2
    }
}

Write-Host "`nГотово: ветка $Branch, коммиты:"
Invoke-Git -GitArgs @("log", "--oneline", "$baseRef..$Branch")
