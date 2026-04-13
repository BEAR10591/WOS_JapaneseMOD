#!/bin/bash
# =============================================================================
#  Build TS2Prototype-WindowsNoEditor.pak (macOS) - SODOR
#  repak: brew install bear10591/tap/repak
# =============================================================================
set -euo pipefail
trap 'echo ""; echo "[FAILED] 上記のエラーを修正してから再実行してください。"; exit 1' ERR

# Homebrew PATH (GUI-launched .command support)
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# --- Config -----------------------------------------------------------------
# Repo root = this .command directory
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# repak command (from PATH)
REPAK_CMD="repak"

# 1=skip brew install if repak exists / 0=always try brew
SKIP_REPAK_DL_IF_PRESENT="${SKIP_REPAK_DL_IF_PRESENT:-1}"
# 1=force reinstall (brew reinstall)
FORCE_REPAK_DL="${FORCE_REPAK_DL:-0}"

# staging (currently unused)
STAGING_DIR="${TMPDIR:-/tmp}/wos_font_pak_staging"

# game pak path (Sikarugir Steam.app prefix)
# ${HOME} = current user's home directory
GAME_ORIGINAL_PAK="${HOME}/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Thomas & Friends™ Wonders of Sodor/WindowsNoEditor/TS2Prototype/Content/Paks/TS2Prototype-WindowsNoEditor.pak"

# backup location
BACKUP_DIR="${REPO_ROOT}/Backup"
BACKUP_PAK="${BACKUP_DIR}/TS2Prototype-WindowsNoEditor.pak"

# work root (deleted on success when cleanup enabled)
PACK_WORK_ROOT="${REPO_ROOT}/WOS_pack_work_SODOR"

# repak unpack --output directory
UNPACK_OUTPUT_DIR="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor"

# pack input directory (same as unpack output)
TS2_UNPACKED_DIR="${UNPACK_OUTPUT_DIR}"

# repak pack output pak path (next to unpack dir)
OUTPUT_PAK="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor.pak"

MOD_OVERLAY_DIR="${REPO_ROOT}/WOS_JapaneseMOD_SODOR"

# 1=skip early repak check / 0=require repak before steps
SKIP_REPAK_CHECK="${SKIP_REPAK_CHECK:-1}"

# 1=delete work dirs on success / 0=keep (debug)
CLEANUP_AFTER_BUILD="${CLEANUP_AFTER_BUILD:-1}"

# --- Pre-check --------------------------------------------------------------
if [[ "${SKIP_REPAK_CHECK}" == "0" ]]; then
  if ! command -v "${REPAK_CMD}" >/dev/null 2>&1; then
    echo "[ERROR] repak が見つかりません: ${REPAK_CMD}"
    false
  fi
fi

# --- Steps ------------------------------------------------------------------
step_download_repak() {
  echo ""
  echo "[1/10] repak の取得 (Homebrew: bear10591/tap/repak) ..."
  if [[ "${FORCE_REPAK_DL}" == "0" ]] && [[ "${SKIP_REPAK_DL_IF_PRESENT}" == "1" ]] && command -v "${REPAK_CMD}" >/dev/null 2>&1; then
    echo "       既存の repak を使用: $(command -v "${REPAK_CMD}")"
    return 0
  fi
  if [[ "${FORCE_REPAK_DL}" == "1" ]]; then
    brew reinstall bear10591/tap/repak
  else
    brew install bear10591/tap/repak
  fi
  if ! command -v "${REPAK_CMD}" >/dev/null 2>&1; then
    echo "[ERROR] brew 後も repak が PATH にありません。Homebrew のパスを確認してください。"
    false
  fi
  echo "       配置完了: $(command -v "${REPAK_CMD}")"
}

step_backup_original_pak() {
  echo ""
  echo "[2/10] ゲーム元 pak のバックアップ ..."
  if [[ -f "${BACKUP_PAK}" ]]; then
    echo "       既にバックアップがあります。再コピー・Backup の作り直しはしません。"
    echo "       ${BACKUP_PAK}"
    return 0
  fi
  if [[ ! -f "${GAME_ORIGINAL_PAK}" ]]; then
    echo "[ERROR] 元 pak が見つかりませんでした。"
    echo "       ${GAME_ORIGINAL_PAK}"
    false
  fi
  echo "       検出: ${GAME_ORIGINAL_PAK}"
  mkdir -p "${BACKUP_DIR}"
  cp -f "${GAME_ORIGINAL_PAK}" "${BACKUP_PAK}"
  echo "       保存しました: ${BACKUP_PAK}"
}

step_unpack_backup_pak() {
  echo ""
  echo "[3/10] バックアップ pak の展開 (repak unpack --output) ..."
  if ! command -v "${REPAK_CMD}" >/dev/null 2>&1; then
    echo "[ERROR] repak が見つかりません。先に [1/10] で取得してください。"
    false
  fi
  if [[ ! -f "${BACKUP_PAK}" ]]; then
    echo "[ERROR] バックアップ pak がありません: ${BACKUP_PAK}"
    false
  fi
  mkdir -p "${UNPACK_OUTPUT_DIR}"
  "${REPAK_CMD}" unpack "${BACKUP_PAK}" --output "${UNPACK_OUTPUT_DIR}" --force
  echo "       展開先: ${UNPACK_OUTPUT_DIR}"
}

step_overlay_mod_to_ts2() {
  echo ""
  echo "[4/10] WOS_JapaneseMOD_SODOR を TS2Prototype-WindowsNoEditor に上書きコピー ..."
  if [[ ! -d "${MOD_OVERLAY_DIR}" ]]; then
    echo "[ERROR] 差し替え元フォルダがありません: ${MOD_OVERLAY_DIR}"
    false
  fi
  if [[ ! -d "${TS2_UNPACKED_DIR}" ]]; then
    echo "[ERROR] unpack 済みの TS2Prototype-WindowsNoEditor がありません: ${TS2_UNPACKED_DIR}"
    false
  fi
  rsync -a "${MOD_OVERLAY_DIR}/" "${TS2_UNPACKED_DIR}/"
  echo "       反映先: ${TS2_UNPACKED_DIR}"
}

step_prepare_staging() {
  echo ""
  echo "[5/10] ステージング準備 ..."
  # TODO: prepare/clean staging dir if needed
  :
}

step_copy_or_generate_font_assets() {
  echo ""
  echo "[6/10] フォントアセットの配置 ..."
  # TODO: copy/prepare font assets into staging if needed
  :
}

step_build_response_file() {
  echo ""
  echo "[7/10] pak 用ファイル一覧の準備 ..."
  # TODO: build response file if needed by repak
  :
}

step_run_repak_pack() {
  echo ""
  echo "[8/10] repak pack (--compression Zlib --version V11) ..."
  if ! command -v "${REPAK_CMD}" >/dev/null 2>&1; then
    echo "[ERROR] repak が見つかりません: ${REPAK_CMD}"
    false
  fi
  if [[ ! -d "${TS2_UNPACKED_DIR}" ]]; then
    echo "[ERROR] パック対象がありません: ${TS2_UNPACKED_DIR}"
    false
  fi
  "${REPAK_CMD}" pack --compression Zlib --version V11 "${TS2_UNPACKED_DIR}" "${OUTPUT_PAK}"
  echo "       出力: ${OUTPUT_PAK}"
}

step_verify_output() {
  echo ""
  echo "[9/10] 出力確認 ..."
  if [[ ! -f "${OUTPUT_PAK}" ]]; then
    echo "[ERROR] 出力 pak が生成されていません: ${OUTPUT_PAK}"
    false
  fi
}

step_install_to_game() {
  echo ""
  echo "[10/10] ゲームの TS2Prototype-WindowsNoEditor.pak を差し替え ..."
  if [[ ! -f "${OUTPUT_PAK}" ]]; then
    echo "[ERROR] 配置する pak がありません: ${OUTPUT_PAK}"
    false
  fi
  if [[ ! -f "${GAME_ORIGINAL_PAK}" ]]; then
    echo "[ERROR] ゲーム側の TS2Prototype-WindowsNoEditor.pak が見つかりません（パスを確認してください）。"
    echo "       ${GAME_ORIGINAL_PAK}"
    false
  fi
  cp -f "${OUTPUT_PAK}" "${GAME_ORIGINAL_PAK}"
  echo "       配置先: ${GAME_ORIGINAL_PAK}"
}

step_cleanup_work() {
  echo ""
  echo "[cleanup] WOS_pack_work_Knapford / WOS_pack_work_SODOR をフォルダごと削除（容量削減） ..."
  if [[ "${CLEANUP_AFTER_BUILD}" == "0" ]]; then
    echo "       CLEANUP_AFTER_BUILD=0 のためスキップしました。"
    return 0
  fi
  for d in "${REPO_ROOT}/WOS_pack_work_Knapford" "${REPO_ROOT}/WOS_pack_work_SODOR"; do
    if [[ -d "${d}" ]]; then
      # Retry a few times in case of ENOTEMPTY (e.g. .DS_Store re-created)
      local ok=0
      for _ in 1 2 3 4 5; do
        rm -rf "${d}" && ok=1 && break
        sleep 0.2
      done
      if [[ "${ok}" == "1" ]] && [[ ! -d "${d}" ]]; then
        echo "       削除: ${d}"
      else
        echo "[WARN] 作業フォルダの削除に失敗しました: ${d}"
      fi
    fi
  done
}

step_download_repak
step_backup_original_pak
step_unpack_backup_pak
step_overlay_mod_to_ts2
step_prepare_staging
step_copy_or_generate_font_assets
step_build_response_file
step_run_repak_pack
step_verify_output
step_install_to_game
step_cleanup_work

echo ""
echo "[OK] 完了: ゲームに配置しました。"
exit 0
