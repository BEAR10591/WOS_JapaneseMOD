#!/bin/bash
# =============================================================================
#  Build TS2Prototype-WindowsNoEditor.pak (macOS)
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
GAME_ORIGINAL_CORE_PAK="${HOME}/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Thomas & Friends™ Wonders of Sodor/WindowsNoEditor/TS2Prototype/Content/Paks/TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
GAME_ORIGINAL_JAMES_CORE_PAK="${HOME}/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Thomas & Friends™ Wonders of Sodor/WindowsNoEditor/TS2Prototype/Content/Paks/TS2Prototype-WindowsNoEditor-James-coredata.pak"

# original pak storage location (fixed per-user backup dir)
ORIGINAL_PAK_DIR="${HOME}/Library/Application Support/WOS_JapaneseMOD/Backup"
ORIGINAL_PAK="${ORIGINAL_PAK_DIR}/TS2Prototype-WindowsNoEditor.pak"
ORIGINAL_SODOR_CORE_PAK="${ORIGINAL_PAK_DIR}/TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
ORIGINAL_JAMES_CORE_PAK="${ORIGINAL_PAK_DIR}/TS2Prototype-WindowsNoEditor-James-coredata.pak"

# work root (deleted on success when cleanup enabled)
PACK_WORK_ROOT="${REPO_ROOT}/WOS_pack_work_Knapford"

# repak unpack --output directory
UNPACK_OUTPUT_DIR="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor"
UNPACK_CORE_OUTPUT_DIR="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor-Sodor-coredata"
UNPACK_JAMES_CORE_OUTPUT_DIR="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor-James-coredata"

# pack input directory (same as unpack output)
TS2_UNPACKED_DIR="${UNPACK_OUTPUT_DIR}"
TS2_CORE_UNPACKED_DIR="${UNPACK_CORE_OUTPUT_DIR}"
TS2_JAMES_CORE_UNPACKED_DIR="${UNPACK_JAMES_CORE_OUTPUT_DIR}"

# repak pack output pak path (next to unpack dir)
OUTPUT_PAK="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor.pak"
OUTPUT_CORE_PAK="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"
OUTPUT_JAMES_CORE_PAK="${PACK_WORK_ROOT}/TS2Prototype-WindowsNoEditor-James-coredata.pak"

MOD_OVERLAY_DIR="${REPO_ROOT}/WOS_JapaneseMOD_Knapford/TS2Prototype-WindowsNoEditor"
MOD_OVERLAY_SODOR_CORE_DIR="${REPO_ROOT}/WOS_JapaneseMOD_Knapford/TS2Prototype-WindowsNoEditor-Sodor-coredata"
MOD_OVERLAY_JAMES_CORE_DIR="${REPO_ROOT}/WOS_JapaneseMOD_Knapford/TS2Prototype-WindowsNoEditor-James-coredata"

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

step_migrate_v010_backup() {
  local old_dir="${REPO_ROOT}/Backup"
  local new_dir="${ORIGINAL_PAK_DIR}"
  if [[ ! -d "${old_dir}" ]]; then
    return 0
  fi
  echo ""
  echo "[migrate] v0.1.0 の Backup を v0.1.1 の保存先へ移行 ..."
  mkdir -p "${new_dir}"

  local moved=0
  for name in \
    "TS2Prototype-WindowsNoEditor.pak" \
    "TS2Prototype-WindowsNoEditor-Sodor-coredata.pak" \
    "TS2Prototype-WindowsNoEditor-James-coredata.pak"
  do
    local src="${old_dir}/${name}"
    local dst="${new_dir}/${name}"
    if [[ -f "${src}" ]]; then
      if [[ ! -f "${dst}" ]]; then
        echo "       移動: ${src}"
        echo "         -> ${dst}"
        mv -f "${src}" "${dst}"
        moved=$((moved + 1))
      else
        echo "       既に新しいバックアップがあります。旧を保持します: ${dst}"
      fi
    fi
  done

  rmdir "${old_dir}" >/dev/null 2>&1 || true
  if [[ "${moved}" -gt 0 ]]; then
    echo "       移行しました: ${moved} ファイル"
  fi
}

backup_one() {
  # args: src dst
  local src="$1"
  local dst="$2"
  if [[ -f "${dst}" ]]; then
    echo "       既にバックアップがあります。再コピー・Backup の作り直しはしません。"
    echo "       ${dst}"
    return 0
  fi
  if [[ ! -f "${src}" ]]; then
    echo "[ERROR] 元 pak が見つかりませんでした。"
    echo "       ${src}"
    false
  fi
  echo "       検出: ${src}"
  mkdir -p "$(dirname "${dst}")"
  cp -f "${src}" "${dst}"
  echo "       保存しました: ${dst}"
}

unpack_one() {
  # args: pak output_dir
  local pak="$1"
  local out="$2"
  if ! command -v "${REPAK_CMD}" >/dev/null 2>&1; then
    echo "[ERROR] repak が見つかりません。先に [1/10] で取得してください。"
    false
  fi
  if [[ ! -f "${pak}" ]]; then
    echo "[ERROR] バックアップ pak がありません: ${pak}"
    false
  fi
  mkdir -p "${out}"
  "${REPAK_CMD}" unpack "${pak}" --output "${out}" --force
  echo "       展開先: ${out}"
}

install_one() {
  # args: src dst label
  local src="$1"
  local dst="$2"
  local label="$3"
  if [[ ! -f "${src}" ]]; then
    echo "[ERROR] 配置する ${label} pak がありません: ${src}"
    false
  fi
  if [[ ! -f "${dst}" ]]; then
    echo "[ERROR] ゲーム側の ${label} pak が見つかりません（パスを確認してください）。"
    echo "       ${dst}"
    false
  fi
  cp -f "${src}" "${dst}"
  echo "       配置先: ${dst}"
}

step_backup_original_pak() {
  echo ""
  echo "[2/10] ゲーム元 pak のバックアップ (3種) ..."
  backup_one "${GAME_ORIGINAL_PAK}" "${ORIGINAL_PAK}"
  backup_one "${GAME_ORIGINAL_CORE_PAK}" "${ORIGINAL_SODOR_CORE_PAK}"
  backup_one "${GAME_ORIGINAL_JAMES_CORE_PAK}" "${ORIGINAL_JAMES_CORE_PAK}"
}

step_unpack_backup_pak() {
  echo ""
  echo "[3/10] バックアップ pak の展開 (3種) (repak unpack --output) ..."
  unpack_one "${ORIGINAL_PAK}" "${UNPACK_OUTPUT_DIR}"
  unpack_one "${ORIGINAL_SODOR_CORE_PAK}" "${UNPACK_CORE_OUTPUT_DIR}"
  unpack_one "${ORIGINAL_JAMES_CORE_PAK}" "${UNPACK_JAMES_CORE_OUTPUT_DIR}"
}

step_overlay_mod_to_ts2() {
  echo ""
  echo "[4/10] WOS_JapaneseMOD_Knapford を pak 展開先 (3種) に上書きコピー ..."
  if [[ ! -d "${MOD_OVERLAY_DIR}" ]]; then
    echo "[ERROR] 差し替え元フォルダがありません: ${MOD_OVERLAY_DIR}"
    false
  fi
  if [[ ! -d "${TS2_UNPACKED_DIR}" ]]; then
    echo "[ERROR] unpack 済みの TS2Prototype-WindowsNoEditor がありません: ${TS2_UNPACKED_DIR}"
    false
  fi
  if [[ ! -d "${TS2_CORE_UNPACKED_DIR}" ]]; then
    echo "[ERROR] unpack 済みの TS2Prototype-WindowsNoEditor-Sodor-coredata がありません: ${TS2_CORE_UNPACKED_DIR}"
    false
  fi
  if [[ ! -d "${TS2_JAMES_CORE_UNPACKED_DIR}" ]]; then
    echo "[ERROR] unpack 済みの TS2Prototype-WindowsNoEditor-James-coredata がありません: ${TS2_JAMES_CORE_UNPACKED_DIR}"
    false
  fi
  # coredata only: delete existing Japanese story assets (cleanup before MOD overlay)
  local deleted=0
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    rm -f "${f}"
    deleted=$((deleted + 1))
  done < <(
    find "${TS2_CORE_UNPACKED_DIR}" -type f \( -name "*_S_*_ja.uasset" -o -name "*_S_*_ja.uexp" \) 2>/dev/null \
      | grep -E '/[^/]*_S_([0-9]+|StoryName)_ja\.(uasset|uexp)$' || true
  )
  echo "       coredata: 削除 ${deleted} ファイル"
  local deleted_james=0
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    rm -f "${f}"
    deleted_james=$((deleted_james + 1))
  done < <(
    find "${TS2_JAMES_CORE_UNPACKED_DIR}" -type f \( -name "*_S_*_ja.uasset" -o -name "*_S_*_ja.uexp" \) 2>/dev/null \
      | grep -E '/[^/]*_S_([0-9]+|StoryName)_ja\.(uasset|uexp)$' || true
  )
  echo "       James coredata: 削除 ${deleted_james} ファイル"
  rsync -a "${MOD_OVERLAY_DIR}/" "${TS2_UNPACKED_DIR}/"
  if [[ -d "${MOD_OVERLAY_SODOR_CORE_DIR}" ]]; then
    rsync -a "${MOD_OVERLAY_SODOR_CORE_DIR}/" "${TS2_CORE_UNPACKED_DIR}/"
  else
    echo "[WARN] Sodor coredata 用の差し替え元フォルダがありません。スキップします: ${MOD_OVERLAY_SODOR_CORE_DIR}"
  fi
  if [[ -d "${MOD_OVERLAY_JAMES_CORE_DIR}" ]]; then
    rsync -a "${MOD_OVERLAY_JAMES_CORE_DIR}/" "${TS2_JAMES_CORE_UNPACKED_DIR}/"
  else
    echo "[WARN] James coredata 用の差し替え元フォルダがありません。スキップします: ${MOD_OVERLAY_JAMES_CORE_DIR}"
  fi
  echo "       反映先: ${TS2_UNPACKED_DIR}"
  echo "       反映先: ${TS2_CORE_UNPACKED_DIR}"
  echo "       反映先: ${TS2_JAMES_CORE_UNPACKED_DIR}"
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
  echo "[8/10] repak pack (3種) (--compression Zlib --version V11) ..."
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

  if [[ ! -d "${TS2_CORE_UNPACKED_DIR}" ]]; then
    echo "[ERROR] パック対象 (coredata) がありません: ${TS2_CORE_UNPACKED_DIR}"
    false
  fi
  "${REPAK_CMD}" pack --compression Zlib --version V11 "${TS2_CORE_UNPACKED_DIR}" "${OUTPUT_CORE_PAK}"
  echo "       出力: ${OUTPUT_CORE_PAK}"

  if [[ ! -d "${TS2_JAMES_CORE_UNPACKED_DIR}" ]]; then
    echo "[ERROR] パック対象 (James coredata) がありません: ${TS2_JAMES_CORE_UNPACKED_DIR}"
    false
  fi
  "${REPAK_CMD}" pack --compression Zlib --version V11 "${TS2_JAMES_CORE_UNPACKED_DIR}" "${OUTPUT_JAMES_CORE_PAK}"
  echo "       出力: ${OUTPUT_JAMES_CORE_PAK}"
}

step_verify_output() {
  echo ""
  echo "[9/10] 出力確認 (3種) ..."
  if [[ ! -f "${OUTPUT_PAK}" ]]; then
    echo "[ERROR] 出力 pak が生成されていません: ${OUTPUT_PAK}"
    false
  fi
  if [[ ! -f "${OUTPUT_CORE_PAK}" ]]; then
    echo "[ERROR] 出力 coredata pak が生成されていません: ${OUTPUT_CORE_PAK}"
    false
  fi
  if [[ ! -f "${OUTPUT_JAMES_CORE_PAK}" ]]; then
    echo "[ERROR] 出力 James coredata pak が生成されていません: ${OUTPUT_JAMES_CORE_PAK}"
    false
  fi
}

step_install_to_game() {
  echo ""
  echo "[10/10] ゲームの pak を差し替え (3種) ..."
  install_one "${OUTPUT_PAK}" "${GAME_ORIGINAL_PAK}" "TS2Prototype-WindowsNoEditor"
  install_one "${OUTPUT_CORE_PAK}" "${GAME_ORIGINAL_CORE_PAK}" "TS2Prototype-WindowsNoEditor-Sodor-coredata"
  install_one "${OUTPUT_JAMES_CORE_PAK}" "${GAME_ORIGINAL_JAMES_CORE_PAK}" "TS2Prototype-WindowsNoEditor-James-coredata"
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
step_migrate_v010_backup
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
