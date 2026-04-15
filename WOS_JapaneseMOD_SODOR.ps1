$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "=== WOS_JapaneseMOD (Windows / SODOR) ==="

# This script is intentionally almost identical to WOS_JapaneseMOD_Knapford.ps1
# Differences are only the overlay directories and work root.

$RepoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path

$RepakDir = Join-Path $RepoRoot 'repak_cli-x86_64-pc-windows-msvc'
$RepakExe = Join-Path $RepakDir 'repak.exe'

$SkipRepakDlIfPresent = if ($env:SKIP_REPAK_DL_IF_PRESENT) { [int]$env:SKIP_REPAK_DL_IF_PRESENT } else { 1 }
$ForceRepakDl          = if ($env:FORCE_REPAK_DL) { [int]$env:FORCE_REPAK_DL } else { 0 }

$PackWorkRoot = Join-Path $RepoRoot 'WOS_pack_work_SODOR'
$UnpackOutputDir      = Join-Path $PackWorkRoot 'TS2Prototype-WindowsNoEditor'
$UnpackCoreOutputDir  = Join-Path $PackWorkRoot 'TS2Prototype-WindowsNoEditor-Sodor-coredata'
$UnpackJamesOutputDir = Join-Path $PackWorkRoot 'TS2Prototype-WindowsNoEditor-James-coredata'

$OutputPak      = Join-Path $PackWorkRoot 'TS2Prototype-WindowsNoEditor.pak'
$OutputCorePak  = Join-Path $PackWorkRoot 'TS2Prototype-WindowsNoEditor-Sodor-coredata.pak'
$OutputJamesPak = Join-Path $PackWorkRoot 'TS2Prototype-WindowsNoEditor-James-coredata.pak'

$ModOverlayDir      = Join-Path $RepoRoot 'WOS_JapaneseMOD_SODOR\TS2Prototype-WindowsNoEditor'
$ModOverlayCoreDir  = Join-Path $RepoRoot 'WOS_JapaneseMOD_SODOR\TS2Prototype-WindowsNoEditor-Sodor-coredata'
$ModOverlayJamesDir = Join-Path $RepoRoot 'WOS_JapaneseMOD_SODOR\TS2Prototype-WindowsNoEditor-James-coredata'

$OriginalPakDir       = Join-Path $env:LOCALAPPDATA 'WOS_JapaneseMOD\Backup'
$OriginalPak          = Join-Path $OriginalPakDir 'TS2Prototype-WindowsNoEditor.pak'
$OriginalCorePak      = Join-Path $OriginalPakDir 'TS2Prototype-WindowsNoEditor-Sodor-coredata.pak'
$OriginalJamesCorePak = Join-Path $OriginalPakDir 'TS2Prototype-WindowsNoEditor-James-coredata.pak'

$CleanupAfterBuild = if ($env:CLEANUP_AFTER_BUILD) { [int]$env:CLEANUP_AFTER_BUILD } else { 1 }

function Invoke-Repak([string[]]$Args) {
  if (-not (Test-Path -LiteralPath $RepakExe)) {
    throw "repak.exe が見つかりません: $RepakExe"
  }
  & $RepakExe @Args
  $rc = $LASTEXITCODE
  if ($rc -ne 0) {
    throw "repak が失敗しました (exit=$rc): $($Args -join ' ')"
  }
}

function Download-Repak() {
  Write-Host ""
  Write-Host "[1/10] repak 最新版の取得 (GitHub Releases) ..."

  if ($ForceRepakDl -eq 0 -and $SkipRepakDlIfPresent -eq 1 -and (Test-Path -LiteralPath $RepakExe)) {
    Write-Host "       既存の repak を使用: $RepakExe"
    return
  }

  if (Test-Path -LiteralPath $RepakDir) {
    Remove-Item -LiteralPath $RepakDir -Recurse -Force
  }
  New-Item -ItemType Directory -Path $RepakDir -Force | Out-Null

  $api = 'https://api.github.com/repos/trumank/repak/releases/latest'
  $r = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'wonders-of-sodor-mod/WOS_JapaneseMOD' }
  $assetName = 'repak_cli-x86_64-pc-windows-msvc.zip'
  $asset = @($r.assets | Where-Object { $_.name -eq $assetName })[0]
  if (-not $asset) { throw "Release asset not found: $assetName" }

  $tag = ([string]$r.tag_name) -replace '[^a-zA-Z0-9._-]', '_'
  $zip = Join-Path $env:TEMP ("repak_cli_$tag.zip")
  Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip
  Expand-Archive -LiteralPath $zip -DestinationPath $RepakDir -Force

  $top = Get-ChildItem -LiteralPath $RepakDir -Force
  if ($top.Count -eq 1 -and $top[0].PSIsContainer) {
    $nested = $top[0].FullName
    Get-ChildItem -LiteralPath $nested -Force | ForEach-Object {
      Move-Item -LiteralPath $_.FullName -Destination $RepakDir -Force
    }
    Remove-Item -LiteralPath $nested -Recurse -Force
  }

  if (-not (Test-Path -LiteralPath $RepakExe)) {
    throw "repak.exe が配置されていません: $RepakExe"
  }
  Write-Host "       配置完了: $RepakExe"
}

function Find-GamePak() {
  $rel = 'Thomas & Friends™ Wonders of Sodor\WindowsNoEditor\TS2Prototype\Content\Paks\TS2Prototype-WindowsNoEditor.pak'
  $candidates = @(
    Join-Path 'C:\Program Files (x86)\Steam\steamapps\common' $rel,
    Join-Path 'C:\Program Files\Steam\steamapps\common' $rel
  )
  $pak = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $pak) {
    throw "ゲーム側の TS2Prototype-WindowsNoEditor.pak が見つかりません（Steam のインストール先を確認してください）。`n$candidates"
  }
  $dir = Split-Path -Parent $pak
  $core = Join-Path $dir 'TS2Prototype-WindowsNoEditor-Sodor-coredata.pak'
  $james = Join-Path $dir 'TS2Prototype-WindowsNoEditor-James-coredata.pak'
  if (-not (Test-Path -LiteralPath $core)) { throw "ゲーム側の coredata pak が見つかりません: $core" }
  if (-not (Test-Path -LiteralPath $james)) { throw "ゲーム側の James coredata pak が見つかりません: $james" }
  return [pscustomobject]@{
    PakPath = $pak
    PakDir  = $dir
    CorePak = $core
    JamesCorePak = $james
  }
}

function Migrate-V010-Backup() {
  $old = Join-Path $RepoRoot 'Backup'
  if (-not (Test-Path -LiteralPath $old)) { return }

  Write-Host ""
  Write-Host "[migrate] v0.1.0 の Backup を v0.1.1 の保存先へ移行 ..."

  New-Item -ItemType Directory -Path $OriginalPakDir -Force | Out-Null
  foreach ($name in @(
    'TS2Prototype-WindowsNoEditor.pak',
    'TS2Prototype-WindowsNoEditor-Sodor-coredata.pak',
    'TS2Prototype-WindowsNoEditor-James-coredata.pak'
  )) {
    $src = Join-Path $old $name
    $dst = Join-Path $OriginalPakDir $name
    if (Test-Path -LiteralPath $src) {
      if (-not (Test-Path -LiteralPath $dst)) {
        Write-Host "       移動: $src"
        Write-Host "         -> $dst"
        Move-Item -LiteralPath $src -Destination $dst -Force
      } else {
        Write-Host "       既に新しいバックアップがあります。旧を保持します: $dst"
      }
    }
  }
  try { Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue } catch {}
}

function Backup-One([string]$src, [string]$dst) {
  if (Test-Path -LiteralPath $dst) {
    Write-Host "       既にバックアップがあります。再コピー・Backup の作り直しはしません。"
    Write-Host "       $dst"
    return
  }
  if (-not (Test-Path -LiteralPath $src)) {
    throw "元 pak が見つかりませんでした: $src"
  }
  Write-Host "       検出: $src"
  New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst -Force
  Write-Host "       保存しました: $dst"
}

function Backup-OriginalPaks() {
  Write-Host ""
  Write-Host "[2/10] ゲーム元 pak のバックアップ (3種) ..."
  $g = Find-GamePak
  Backup-One $g.PakPath $OriginalPak
  Backup-One $g.CorePak $OriginalCorePak
  Backup-One $g.JamesCorePak $OriginalJamesCorePak
}

function Unpack-One([string]$pak, [string]$outDir) {
  if (-not (Test-Path -LiteralPath $pak)) { throw "バックアップ pak がありません: $pak" }
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
  & $RepakExe 'unpack' $pak '--output' $outDir '--force'
  $rc = $LASTEXITCODE
  if ($rc -ne 0) {
    $ts2 = Join-Path $outDir 'TS2Prototype'
    if (Test-Path -LiteralPath $ts2) {
      Write-Host "       [WARN] repak の終了コードが 0 ではありませんが、展開結果が見つかったため続行します: $rc"
    } else {
      throw "repak unpack に失敗しました (exit=$rc): $pak"
    }
  }
  Write-Host "       展開先: $outDir"
}

function Unpack-Backups() {
  Write-Host ""
  Write-Host "[3/10] バックアップ pak の展開 (3種) (repak unpack --output) ..."
  Unpack-One $OriginalPak $UnpackOutputDir
  Unpack-One $OriginalCorePak $UnpackCoreOutputDir
  Unpack-One $OriginalJamesCorePak $UnpackJamesOutputDir
}

function Remove-JapaneseStoryAssets([string]$root, [string]$label) {
  $re = '.*_S_(?:\d+|StoryName)_ja\.(?:uasset|uexp)$'
  $files = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match $re }
  foreach ($f in $files) { Remove-Item -LiteralPath $f.FullName -Force }
  Write-Host ("       {0}: 削除 {1} ファイル" -f $label, $files.Count)
}

function Overlay-Mod() {
  Write-Host ""
  Write-Host "[4/10] WOS_JapaneseMOD_SODOR を pak 展開先 (3種) に上書きコピー ..."

  foreach ($d in @($ModOverlayDir, $UnpackOutputDir, $UnpackCoreOutputDir, $UnpackJamesOutputDir)) {
    if (-not (Test-Path -LiteralPath $d)) { throw "必要なフォルダがありません: $d" }
  }

  Remove-JapaneseStoryAssets $UnpackCoreOutputDir 'coredata'
  Remove-JapaneseStoryAssets $UnpackJamesOutputDir 'James coredata'

  & robocopy $ModOverlayDir $UnpackOutputDir /E /IS /IT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy に失敗しました (main): $LASTEXITCODE" }

  if (Test-Path -LiteralPath $ModOverlayCoreDir) {
    & robocopy $ModOverlayCoreDir $UnpackCoreOutputDir /E /IS /IT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy に失敗しました (coredata): $LASTEXITCODE" }
  } else {
    Write-Host "[WARN] Sodor coredata 用の差し替え元フォルダがありません。スキップします: $ModOverlayCoreDir"
  }

  if (Test-Path -LiteralPath $ModOverlayJamesDir) {
    & robocopy $ModOverlayJamesDir $UnpackJamesOutputDir /E /IS /IT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy に失敗しました (James coredata): $LASTEXITCODE" }
  } else {
    Write-Host "[WARN] James coredata 用の差し替え元フォルダがありません。スキップします: $ModOverlayJamesDir"
  }

  Write-Host "       反映先: $UnpackOutputDir"
  Write-Host "       反映先: $UnpackCoreOutputDir"
  Write-Host "       反映先: $UnpackJamesOutputDir"
}

function Pack-All() {
  Write-Host ""
  Write-Host "[8/10] repak pack (3種) (--compression Zlib --version V11) ..."
  foreach ($d in @($UnpackOutputDir, $UnpackCoreOutputDir, $UnpackJamesOutputDir)) {
    if (-not (Test-Path -LiteralPath $d)) { throw "パック対象がありません: $d" }
  }
  Invoke-Repak @('pack','--compression','Zlib','--version','V11', $UnpackOutputDir, $OutputPak)
  Write-Host "       出力: $OutputPak"
  Invoke-Repak @('pack','--compression','Zlib','--version','V11', $UnpackCoreOutputDir, $OutputCorePak)
  Write-Host "       出力: $OutputCorePak"
  Invoke-Repak @('pack','--compression','Zlib','--version','V11', $UnpackJamesOutputDir, $OutputJamesPak)
  Write-Host "       出力: $OutputJamesPak"
}

function Verify-Output() {
  Write-Host ""
  Write-Host "[9/10] 出力確認 (3種) ..."
  foreach ($f in @($OutputPak, $OutputCorePak, $OutputJamesPak)) {
    if (-not (Test-Path -LiteralPath $f)) { throw "出力 pak が生成されていません: $f" }
  }
}

function Install-ToGame() {
  Write-Host ""
  Write-Host "[10/10] ゲームの pak を差し替え (3種) ..."
  $g = Find-GamePak
  Copy-Item -LiteralPath $OutputPak -Destination $g.PakPath -Force
  Write-Host "       配置先: $($g.PakPath)"
  Copy-Item -LiteralPath $OutputCorePak -Destination $g.CorePak -Force
  Write-Host "       配置先: $($g.CorePak)"
  Copy-Item -LiteralPath $OutputJamesPak -Destination $g.JamesCorePak -Force
  Write-Host "       配置先: $($g.JamesCorePak)"
}

function Cleanup-Work() {
  Write-Host ""
  Write-Host "[cleanup] WOS_pack_work_Knapford / WOS_pack_work_SODOR をフォルダごと削除（容量削減） ..."
  if ($CleanupAfterBuild -eq 0) {
    Write-Host "       CLEANUP_AFTER_BUILD=0 のためスキップしました。"
    return
  }
  foreach ($d in @(
    (Join-Path $RepoRoot 'WOS_pack_work_Knapford'),
    (Join-Path $RepoRoot 'WOS_pack_work_SODOR')
  )) {
    if (Test-Path -LiteralPath $d) {
      try {
        Remove-Item -LiteralPath $d -Recurse -Force
        Write-Host "       削除: $d"
      } catch {
        Write-Host "[WARN] 作業フォルダの削除に失敗しました: $d"
      }
    }
  }
}

try {
  Download-Repak
  Migrate-V010-Backup
  Backup-OriginalPaks
  Unpack-Backups
  Overlay-Mod

  Write-Host ""
  Write-Host "[5/10] ステージング準備 ..."
  Write-Host ""
  Write-Host "[6/10] フォントアセットの配置 ..."
  Write-Host ""
  Write-Host "[7/10] pak 用ファイル一覧の準備 ..."

  Pack-All
  Verify-Output
  Install-ToGame
  Cleanup-Work

  Write-Host ""
  Write-Host "[OK] 完了: ゲームに配置しました。"
  exit 0
} catch {
  Write-Host ""
  Write-Host "[FAILED] 上記のエラーを修正してから再実行してください。"
  Write-Host "        $($_.Exception.Message)"
  exit 1
}

