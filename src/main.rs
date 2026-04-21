use std::ffi::OsStr;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use clap::Parser;
use regex::Regex;
#[cfg(windows)]
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;
#[cfg(windows)]
use zip::ZipArchive;

#[derive(Debug, Default, Deserialize, Serialize, Clone)]
struct PersistentState {
    repak_path: Option<String>,
    paks_dir: Option<String>,
    #[serde(rename = "data_root_dir", alias = "backup_dir")]
    data_root_dir: Option<String>,
    cleanup: Option<bool>,
}

#[derive(Debug, Parser)]
#[command(
    name = "WOS_JapaneseMOD",
    about = "WOS Japanese MOD installer (Windows/macOS)"
)]
struct Args {}

fn main() -> Result<()> {
    let _args = Args::parse();

    // When launched by double-click (Finder/Explorer), the current working directory can be HOME.
    // Also, the executable may live under dist/, so we must locate the actual repo root.
    let repo_root = repo_root_dir().context("Failed to resolve repo root directory")?;
    let mut state = load_state().unwrap_or_default();

    // repak is not configured via YAML.
    // If repak is not found, we will ask interactively what to do.
    let Some(repak) = resolve_repak_interactive(&mut state)? else {
        // macOS: user chose to install via brew; show command and exit.
        return Ok(());
    };
    // Paks directory is not configured via YAML.
    // If the default Paks directory is not found, ask interactively.
    let game_paths = resolve_game_paks_interactive(&mut state)?;

    // data_root_dir is not configured via YAML.
    // Ask interactively where to place Backup/ and workdir (unpacked/).
    let data_root_dir = resolve_data_root_dir_interactive(&mut state)?;
    let backup_dir = data_root_dir.join("Backup");
    fs::create_dir_all(&backup_dir).context("Failed to create backup directory")?;

    let backups = BackupPaths {
        main: backup_dir.join("TS2Prototype-WindowsNoEditor.pak"),
        sodor_core: backup_dir.join("TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"),
        james_core: backup_dir.join("TS2Prototype-WindowsNoEditor-James-coredata.pak"),
    };

    backup_if_missing(&game_paths.main, &backups.main)?;
    backup_if_missing(&game_paths.sodor_core, &backups.sodor_core)?;
    backup_if_missing(&game_paths.james_core, &backups.james_core)?;

    // Work directory is created alongside the Backup directory.
    // This keeps large unpacked data out of the repo folder.
    let pack_work_root = data_root_dir.join("unpacked");

    let unpack = UnpackDirs {
        main: pack_work_root.join("TS2Prototype-WindowsNoEditor"),
        sodor_core: pack_work_root.join("TS2Prototype-WindowsNoEditor-Sodor-coredata"),
        james_core: pack_work_root.join("TS2Prototype-WindowsNoEditor-James-coredata"),
    };

    // Output paks are written directly into the game's Paks directory
    // (i.e., same paths as the files that will be replaced).
    let outputs = OutputPaks {
        main: game_paths.main.clone(),
        sodor_core: game_paths.sodor_core.clone(),
        james_core: game_paths.james_core.clone(),
    };

    unpack_one(&repak, &backups.main, &unpack.main, "main pak")?;
    unpack_one(
        &repak,
        &backups.sodor_core,
        &unpack.sodor_core,
        "Sodor coredata",
    )?;
    unpack_one(
        &repak,
        &backups.james_core,
        &unpack.james_core,
        "James coredata",
    )?;

    apply_overlay(&repo_root, &unpack)?;

    // Pack
    repak_pack(&repak, &unpack.main, &outputs.main, "main pak")?;
    repak_pack(
        &repak,
        &unpack.sodor_core,
        &outputs.sodor_core,
        "Sodor coredata",
    )?;
    repak_pack(
        &repak,
        &unpack.james_core,
        &outputs.james_core,
        "James coredata",
    )?;

    verify_exists(&outputs.main)?;
    verify_exists(&outputs.sodor_core)?;
    verify_exists(&outputs.james_core)?;

    // Install step is implicit because repak pack writes directly to game_paths.*

    if resolve_cleanup_interactive(&mut state)? {
        cleanup_workdirs(&pack_work_root)?;
    }

    save_state(&state).ok();

    println!();
    println!("[OK] 完了: ゲームに配置しました。");
    println!("       このウィンドウ（タブ）は閉じて大丈夫です。");
    Ok(())
}

fn app_root_dir() -> Result<PathBuf> {
    // Prefer the directory containing the executable.
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            return Ok(dir.to_path_buf());
        }
    }
    // Fallback to current directory (useful during `cargo run`).
    Ok(std::env::current_dir().context("Failed to get current directory")?)
}

fn repo_root_dir() -> Result<PathBuf> {
    // Strategy:
    // - Start from the executable directory (best for double-click builds).
    // - Walk up a few levels and pick the first directory that looks like the repo:
    //   it contains the MOD overlay directory.
    // - Fallback to current_dir (useful for `cargo run`).

    let start = app_root_dir()?;
    if let Some(found) = find_repo_root(&start) {
        return Ok(found);
    }

    let cwd = std::env::current_dir().context("Failed to get current directory")?;
    if let Some(found) = find_repo_root(&cwd) {
        return Ok(found);
    }

    // Last resort: executable directory
    Ok(start)
}

fn find_repo_root(start: &Path) -> Option<PathBuf> {
    let mut cur = Some(start);
    for _ in 0..8 {
        let dir = cur?;
        let mod_dir = dir.join("MOD");
        if mod_dir.is_dir() {
            return Some(dir.to_path_buf());
        }
        cur = dir.parent();
    }
    None
}

#[derive(Debug, Clone)]
struct GamePaths {
    main: PathBuf,
    sodor_core: PathBuf,
    james_core: PathBuf,
}

#[derive(Debug, Clone)]
struct BackupPaths {
    main: PathBuf,
    sodor_core: PathBuf,
    james_core: PathBuf,
}

#[derive(Debug, Clone)]
struct UnpackDirs {
    main: PathBuf,
    sodor_core: PathBuf,
    james_core: PathBuf,
}

#[derive(Debug, Clone)]
struct OutputPaks {
    main: PathBuf,
    sodor_core: PathBuf,
    james_core: PathBuf,
}

fn verify_exists(p: &Path) -> Result<()> {
    if !p.exists() {
        bail!("Expected file missing: {}", p.display());
    }
    Ok(())
}

fn default_documents_data_root_dir() -> Result<PathBuf> {
    let docs = documents_dir()?;
    Ok(docs.join("WOS_JapaneseMOD"))
}

fn documents_dir() -> Result<PathBuf> {
    #[cfg(windows)]
    {
        // Prefer USERPROFILE\Documents.
        if let Some(home) = std::env::var_os("USERPROFILE") {
            return Ok(PathBuf::from(home).join("Documents"));
        }
        // Fallback: HOMEDRIVE + HOMEPATH.
        let drive = std::env::var_os("HOMEDRIVE").ok_or_else(|| anyhow!("HOMEDRIVE is not set"))?;
        let path = std::env::var_os("HOMEPATH").ok_or_else(|| anyhow!("HOMEPATH is not set"))?;
        return Ok(PathBuf::from(drive).join(path).join("Documents"));
    }

    #[cfg(not(windows))]
    {
        let home = std::env::var_os("HOME").ok_or_else(|| anyhow!("HOME is not set"))?;
        Ok(PathBuf::from(home).join("Documents"))
    }
}

fn legacy_default_backup_dirs() -> Result<Vec<PathBuf>> {
    #[cfg(windows)]
    {
        let base =
            std::env::var_os("LOCALAPPDATA").ok_or_else(|| anyhow!("LOCALAPPDATA is not set"))?;
        return Ok(vec![PathBuf::from(base)
            .join("WOS_JapaneseMOD")
            .join("Backup")]);
    }

    #[cfg(not(windows))]
    {
        let home = std::env::var_os("HOME").ok_or_else(|| anyhow!("HOME is not set"))?;
        return Ok(vec![PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("WOS_JapaneseMOD")
            .join("Backup")]);
    }
}

fn legacy_default_data_root_dirs() -> Result<Vec<PathBuf>> {
    Ok(legacy_default_backup_dirs()?
        .into_iter()
        .filter_map(|p| p.parent().map(Path::to_path_buf))
        .collect())
}

fn copy_backup_files(src: &Path, dst: &Path) -> Result<usize> {
    if src == dst {
        return Ok(0);
    }
    if !src.is_dir() {
        return Ok(0);
    }
    fs::create_dir_all(dst).ok();

    let mut copied = 0usize;
    for entry in fs::read_dir(src).with_context(|| format!("Failed to read dir: {}", src.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if path.extension().and_then(OsStr::to_str) != Some("pak") {
            continue;
        }
        let name = path.file_name().and_then(OsStr::to_str).unwrap_or("backup.pak");
        let out = dst.join(name);
        // Do not overwrite existing backups.
        if out.is_file() {
            continue;
        }
        copy_file(&path, &out)?;
        copied += 1;
    }
    Ok(copied)
}

fn move_backup_best_effort(src_backup_dir: &Path, dst_backup_dir: &Path) -> Result<usize> {
    // 1) Copy .pak files (do not overwrite).
    let copied = copy_backup_files(src_backup_dir, dst_backup_dir)?;

    // 2) Verify all .pak files in src exist in dst (either pre-existing or copied).
    if src_backup_dir.is_dir() {
        for entry in fs::read_dir(src_backup_dir)
            .with_context(|| format!("Failed to read dir: {}", src_backup_dir.display()))?
        {
            let entry = entry?;
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            if path.extension().and_then(OsStr::to_str) != Some("pak") {
                continue;
            }
            let name = path.file_name().and_then(OsStr::to_str).unwrap_or("");
            let dst = dst_backup_dir.join(name);
            if !dst.is_file() {
                bail!(
                    "Backup migration verification failed: {} was not created",
                    dst.display()
                );
            }
        }
    }

    // 3) After successful verification, delete the source Backup directory entirely.
    // This avoids leaving empty dirs or non-pak leftovers behind.
    if src_backup_dir.is_dir() {
        // Retry a few times in case of transient "Directory not empty" errors.
        let mut last_err: Option<std::io::Error> = None;
        for _ in 0..5 {
            match fs::remove_dir_all(src_backup_dir) {
                Ok(()) => {
                    last_err = None;
                    break;
                }
                Err(e) => {
                    last_err = Some(e);
                    std::thread::sleep(Duration::from_millis(200));
                }
            }
        }
        if src_backup_dir.exists() {
            if let Some(e) = last_err {
                bail!(
                    "Failed to delete source Backup dir after migration: {} ({e})",
                    src_backup_dir.display()
                );
            }
            bail!(
                "Failed to delete source Backup dir after migration: {}",
                src_backup_dir.display()
            );
        }
    }

    Ok(copied)
}

fn resolve_data_root_dir_interactive(state: &mut PersistentState) -> Result<PathBuf> {
    // Note: `state.data_root_dir` used to store the full backup directory (ending with /Backup)
    // From now on, it stores the *parent* directory where both `Backup/` and `unpacked/` live.

    // If user previously specified a path, ask whether to keep using it.
    if let Some(raw) = state.data_root_dir.as_deref() {
        let existing_raw = PathBuf::from(raw);
        if existing_raw.as_os_str().is_empty() {
            state.data_root_dir = None;
        } else {
            // Backward compatibility: if it points to ".../Backup", convert to parent.
            let existing_root = if existing_raw
                .file_name()
                .and_then(OsStr::to_str)
                .map(|s| s.eq_ignore_ascii_case("Backup"))
                .unwrap_or(false)
            {
                existing_raw.parent().map(Path::to_path_buf).unwrap_or(existing_raw)
            } else {
                existing_raw
            };

            println!();
            println!("[select] データ保存先（前回設定）");
            println!("         {}", existing_root.display());
            println!("         （この中に `Backup/` と `unpacked/` を作成します）");
            let keep = prompt_yes_no("         引き続きこの場所を使用しますか？ (y/n): ")?;
            if keep {
                // Persist normalized root.
                state.data_root_dir = Some(existing_root.to_string_lossy().to_string());
                save_state(state).ok();
                // If the chosen root is a legacy default root, offer migration to the new default.
                return maybe_migrate_legacy_data_to_new_default(state, existing_root);
            }
            // User chose not to keep using it → allow choosing new root, with optional copy.
            return choose_new_data_root_dir_with_optional_copy(state, Some(&existing_root));
        }
    }

    choose_new_data_root_dir_with_optional_copy(state, None)
}

fn maybe_migrate_legacy_data_to_new_default(
    state: &mut PersistentState,
    chosen_root: PathBuf,
) -> Result<PathBuf> {
    // If the chosen root is one of the legacy default roots AND it contains state/backup,
    // offer moving everything to the new default root (Documents/WOS_JapaneseMOD).
    let legacy_roots = legacy_default_data_root_dirs().unwrap_or_default();
    let is_legacy_root = legacy_roots.iter().any(|p| *p == chosen_root);
    if !is_legacy_root {
        return Ok(chosen_root);
    }

    let legacy_backup = chosen_root.join("Backup");
    let has_legacy = legacy_backup.is_dir() && dir_has_any_file(&legacy_backup)?;
    if !has_legacy {
        return Ok(chosen_root);
    }

    let new_def = default_documents_data_root_dir()?;
    if new_def == chosen_root {
        return Ok(chosen_root);
    }

    println!();
    println!("[select] 旧保存先の移行");
    println!("         旧: {}", chosen_root.display());
    println!("         新: {}", new_def.display());
    println!("         ※ `Backup/` を新しい既定保存先へ移動します。");
    if !prompt_yes_no("         移動しますか？ (y/n): ")? {
        return Ok(chosen_root);
    }

    fs::create_dir_all(&new_def).ok();
    let copied = move_backup_best_effort(&legacy_backup, &new_def.join("Backup"))?;
    let _ = copied; // keep silent; we print in caller flow if needed later.

    state.data_root_dir = Some(new_def.to_string_lossy().to_string());
    save_state(state).ok();
    Ok(new_def)
}

fn choose_new_data_root_dir_with_optional_copy(
    state: &mut PersistentState,
    prev_root_dir: Option<&Path>,
) -> Result<PathBuf> {
    let def_root = default_documents_data_root_dir()?;

    // If legacy default contains backups, mention it and offer copying.
    let mut legacy_root_with_data: Option<PathBuf> = None;
    if prev_root_dir.is_none() {
        for root in legacy_default_data_root_dirs()? {
            let has_state = root.join("state.json").is_file();
            let backup = root.join("Backup");
            let has_backup = backup.is_dir() && dir_has_any_file(&backup).unwrap_or(false);
            if has_state || has_backup {
                legacy_root_with_data = Some(root);
                break;
            }
        }
    }

    println!();
    println!("[select] データ保存先（Backup と作業フォルダの保存先）");
    println!("         既定: {}", def_root.display());
    println!("         （この中に `Backup/` と `unpacked/` を作成します）");
    println!("         例: {}", def_root.display());

    println!();
    println!("       y: 既定（ドキュメント）を使用 / n: 別の場所を指定");
    let use_default = prompt_yes_no("         既定の保存先を使用しますか？ (y/n): ")?;
    let chosen_root = if use_default {
        def_root
    } else {
        loop {
            let raw = prompt_path("         データ保存先のフルパスを入力してください: ")?;
            let dir = expand_path(&raw.to_string_lossy())?;
            if dir.as_os_str().is_empty() {
                eprintln!("         パスを入力してください。");
                continue;
            }
            break dir;
        }
    };

    // Optional copy from previous/legacy backup directory if it contains backups.
    let prev_backup_dir = prev_root_dir.map(|p| p.join("Backup"));
    let chosen_backup_dir = chosen_root.join("Backup");
    let copy_src_backup_dir = if let Some(p) = prev_backup_dir.as_ref() {
        if p.is_dir() && dir_has_any_file(p).unwrap_or(false) {
            Some(p.to_path_buf())
        } else {
            None
        }
    } else {
        legacy_root_with_data.as_ref().map(|r| r.join("Backup"))
    };
    if let Some(src_backup_dir) = copy_src_backup_dir {
        println!();
        if let Some(ref legacy_root) = legacy_root_with_data {
            println!("[info] 旧バージョン（v0.2.1）の既定保存先にバックアップが見つかりました:");
            println!("       {}", legacy_root.display());
            println!();
        }
        println!("[select] バックアップ移行");
        println!("         元: {}", src_backup_dir.display());
        println!("         先: {}", chosen_backup_dir.display());
        println!("         ※ 移行後、コピー元の `Backup/` は削除されます。");
        if prompt_yes_no("         旧保存先の .pak を新しい保存先へ移動しますか？ (y/n): ")? {
            let copied = move_backup_best_effort(&src_backup_dir, &chosen_backup_dir)?;
            println!("       移動: {copied} ファイル");
        }
    }

    state.data_root_dir = Some(chosen_root.to_string_lossy().to_string());
    save_state(state).ok();
    Ok(chosen_root)
}

fn backup_if_missing(src: &Path, dst: &Path) -> Result<()> {
    println!();
    println!(
        "[backup] {}",
        dst.file_name().and_then(OsStr::to_str).unwrap_or("pak")
    );
    if dst.is_file() {
        println!("       既にバックアップがあります。再コピー・Backup の作り直しはしません。");
        println!("       {}", dst.display());
        return Ok(());
    }
    if !src.is_file() {
        bail!("[ERROR] 元 pak が見つかりませんでした: {}", src.display());
    }
    fs::create_dir_all(dst.parent().unwrap())?;
    copy_file(src, dst)?;
    println!("       バックアップを作成しました: {}", dst.display());
    Ok(())
}

fn copy_file(src: &Path, dst: &Path) -> Result<()> {
    if let Some(parent) = dst.parent() {
        fs::create_dir_all(parent).ok();
    }
    fs::copy(src, dst)
        .with_context(|| format!("copy failed: {} -> {}", src.display(), dst.display()))?;
    Ok(())
}

fn unpack_one(repak: &Path, pak: &Path, out: &Path, label: &str) -> Result<()> {
    println!();
    println!("[unpack] {} ...", label);
    if !repak.is_file() {
        bail!("repak not found: {}", repak.display());
    }
    if !pak.is_file() {
        bail!("Backup pak missing: {}", pak.display());
    }

    // If the output directory already has files, reuse it and skip unpack.
    // This is useful when the previous run stopped mid-way; we can continue.
    if out.is_dir() && dir_has_any_file(out)? {
        println!("       既存の展開済みフォルダを使用します（unpack をスキップ）");
        println!("       展開先: {}", out.display());
        return Ok(());
    }

    fs::create_dir_all(out)?;

    let status = Command::new(repak)
        .arg("unpack")
        .arg(pak)
        .arg("--output")
        .arg(out)
        .arg("--force")
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .with_context(|| format!("Failed to run repak unpack for {}", label))?;

    if !status.success() {
        // Accept non-zero if output exists (repak sometimes returns non-zero despite output)
        if dir_has_any_file(out)? {
            eprintln!(
                "[WARN] repak unpack exited non-zero but output exists; continuing ({label})"
            );
        } else {
            bail!("repak unpack failed ({label}): {status}");
        }
    }

    println!("       展開先: {}", out.display());
    Ok(())
}

fn dir_has_any_file(dir: &Path) -> Result<bool> {
    for entry in WalkDir::new(dir).into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_file() {
            return Ok(true);
        }
    }
    Ok(false)
}

fn apply_overlay(repo_root: &Path, unpack: &UnpackDirs) -> Result<()> {
    println!();
    println!("[overlay] MOD を pak 展開先 (3種) に上書きコピー ...");

    let base = repo_root.join("MOD");
    let overlay_main = base.join("TS2Prototype-WindowsNoEditor");
    let overlay_sodor = base.join("TS2Prototype-WindowsNoEditor-Sodor-coredata");
    let overlay_james = base.join("TS2Prototype-WindowsNoEditor-James-coredata");

    if !overlay_main.is_dir() {
        bail!("MOD overlay dir missing: {}", overlay_main.display());
    }
    if !unpack.main.is_dir() {
        bail!("Unpacked main dir missing: {}", unpack.main.display());
    }
    if !unpack.sodor_core.is_dir() {
        bail!(
            "Unpacked coredata dir missing: {}",
            unpack.sodor_core.display()
        );
    }
    if !unpack.james_core.is_dir() {
        bail!(
            "Unpacked James coredata dir missing: {}",
            unpack.james_core.display()
        );
    }

    // coredata only: delete existing Japanese story assets before overlay
    delete_japanese_story_assets(&unpack.sodor_core)
        .context("Failed to cleanup coredata Japanese story assets")?;
    delete_japanese_story_assets(&unpack.james_core)
        .context("Failed to cleanup James coredata Japanese story assets")?;

    copy_dir_merge(&overlay_main, &unpack.main)?;
    if overlay_sodor.is_dir() {
        copy_dir_merge(&overlay_sodor, &unpack.sodor_core)?;
    } else {
        eprintln!(
            "[WARN] Sodor coredata overlay dir missing; skipping: {}",
            overlay_sodor.display()
        );
    }
    if overlay_james.is_dir() {
        copy_dir_merge(&overlay_james, &unpack.james_core)?;
    } else {
        eprintln!(
            "[WARN] James coredata overlay dir missing; skipping: {}",
            overlay_james.display()
        );
    }

    println!("       反映先: {}", unpack.main.display());
    println!("       反映先: {}", unpack.sodor_core.display());
    println!("       反映先: {}", unpack.james_core.display());
    Ok(())
}

fn delete_japanese_story_assets(root: &Path) -> Result<()> {
    let re = Regex::new(r".*_S_(?:\d+|StoryName)_ja\.(?:uasset|uexp)$")?;
    let mut deleted = 0usize;
    for entry in WalkDir::new(root).into_iter().filter_map(|e| e.ok()) {
        if !entry.file_type().is_file() {
            continue;
        }
        let path = entry.path();
        let name = path.file_name().and_then(OsStr::to_str).unwrap_or("");
        if re.is_match(name) {
            fs::remove_file(path).ok();
            deleted += 1;
        }
    }
    println!("       coredata: 削除 {deleted} ファイル");
    Ok(())
}

fn copy_dir_merge(src: &Path, dst: &Path) -> Result<()> {
    // Copy files recursively, preserving relative paths (overwrite)
    for entry in WalkDir::new(src).into_iter().filter_map(|e| e.ok()) {
        if entry.file_type().is_dir() {
            continue;
        }
        let rel = entry.path().strip_prefix(src)?;
        let out = dst.join(rel);
        if let Some(parent) = out.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::copy(entry.path(), &out).with_context(|| {
            format!(
                "Failed to copy {} -> {}",
                entry.path().display(),
                out.display()
            )
        })?;
    }
    Ok(())
}

fn repak_pack(repak: &Path, input_dir: &Path, output_pak: &Path, label: &str) -> Result<()> {
    println!();
    println!("[pack] {} ...", label);
    if !repak.is_file() {
        bail!("repak not found: {}", repak.display());
    }
    if !input_dir.is_dir() {
        bail!("Pack input dir missing: {}", input_dir.display());
    }
    if let Some(parent) = output_pak.parent() {
        fs::create_dir_all(parent).ok();
    }

    let status = Command::new(repak)
        .arg("pack")
        .arg("--compression")
        .arg("Zlib")
        .arg("--version")
        .arg("V11")
        .arg(input_dir)
        .arg(output_pak)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .context("Failed to run repak pack")?;

    if !status.success() {
        bail!("repak pack failed ({label}): {status}");
    }

    println!("       出力: {}", output_pak.display());
    Ok(())
}

fn cleanup_workdirs(pack_work_root: &Path) -> Result<()> {
    println!();
    println!(
        "[cleanup] unpacked をフォルダごと削除（容量削減） ...\n       {}",
        pack_work_root.display()
    );
    if pack_work_root.is_dir() {
        // Retry a few times in case of transient "Directory not empty" (macOS: os error 66)
        let mut last_err: Option<std::io::Error> = None;
        let mut ok = false;
        for _ in 0..5 {
            match fs::remove_dir_all(pack_work_root) {
                Ok(()) => {
                    ok = true;
                    break;
                }
                Err(e) => {
                    last_err = Some(e);
                    std::thread::sleep(Duration::from_millis(200));
                }
            }
        }
        if ok && !pack_work_root.exists() {
            println!("       削除: {}", pack_work_root.display());
        } else if let Some(e) = last_err {
            eprintln!(
                "[WARN] 作業フォルダの削除に失敗しました: {} ({e})",
                pack_work_root.display()
            );
        } else {
            eprintln!(
                "[WARN] 作業フォルダの削除に失敗しました: {}",
                pack_work_root.display()
            );
        }
    }
    Ok(())
}

fn resolve_cleanup_interactive(state: &mut PersistentState) -> Result<bool> {
    println!();
    println!("[select] 後処理");
    let default_label = match state.cleanup {
        Some(true) => "はい",
        _ => "いいえ",
    };
    println!(
        "         作業フォルダ（unpacked）を削除しますか？（既定: {default_label}）"
    );
    println!("         ※ 原因調査や再実行のため、基本的には削除しないことを推奨します。");
    let v = prompt_yes_no("         削除する (y/n): ")?;
    state.cleanup = Some(v);
    save_state(state).ok();
    Ok(v)
}

fn resolve_game_paks_interactive(state: &mut PersistentState) -> Result<GamePaths> {
    if let Some(dir) = state.paks_dir.as_deref() {
        let dir = PathBuf::from(dir);
        if let Ok(p) = resolve_game_paks_from_dir(&dir) {
            return Ok(p);
        }
    }

    // 1) Try the known default install locations first.
    if let Some(dir) = detect_default_game_pak_dir()? {
        match resolve_game_paks_from_dir(&dir) {
            Ok(p) => return Ok(p),
            Err(e) => {
                eprintln!();
                eprintln!("[WARN] 既定の Paks ディレクトリは見つかりましたが、内容の確認に失敗しました。");
                eprintln!("       {} ({e})", dir.display());
            }
        }
    }

    // 2) Ask the user for the Paks directory path.
    println!();
    println!("[select] Paks ディレクトリを指定してください");
    println!("         （`.pak` が入っているフォルダ。例: .../TS2Prototype/Content/Paks）");
    loop {
        let raw = prompt_path("         Paks ディレクトリのフルパス: ")?;
        let dir = expand_path(&raw.to_string_lossy())?;
        if !dir.is_dir() {
            eprintln!("         ディレクトリが見つかりません: {}", dir.display());
            continue;
        }
        match resolve_game_paks_from_dir(&dir) {
            Ok(p) => {
                state.paks_dir = Some(dir.to_string_lossy().to_string());
                save_state(state).ok();
                return Ok(p);
            }
            Err(e) => {
                eprintln!("         無効な Paks ディレクトリです: {} ({e})", dir.display());
            }
        }
    }
}

fn resolve_game_paks_from_dir(dir: &Path) -> Result<GamePaths> {
    if !dir.is_dir() {
        bail!("Paks directory not found: {}", dir.display());
    }

    let main = dir.join("TS2Prototype-WindowsNoEditor.pak");
    let sodor_core = dir.join("TS2Prototype-WindowsNoEditor-Sodor-coredata.pak");
    let james_core = dir.join("TS2Prototype-WindowsNoEditor-James-coredata.pak");

    if !main.is_file() {
        bail!("Game pak not found: {}", main.display());
    }
    if !sodor_core.is_file() {
        bail!("Game coredata pak not found: {}", sodor_core.display());
    }
    if !james_core.is_file() {
        bail!(
            "Game James coredata pak not found: {}",
            james_core.display()
        );
    }

    Ok(GamePaths {
        main,
        sodor_core,
        james_core,
    })
}

fn detect_default_game_pak_dir() -> Result<Option<PathBuf>> {
    #[cfg(windows)]
    {
        // User-specified default
        let p = PathBuf::from(
            r"C:\Program Files (x86)\Steam\steamapps\common\Thomas & Friends™ Wonders of Sodor\WindowsNoEditor\TS2Prototype\Content\Paks",
        );
        if p.is_dir() {
            return Ok(Some(p));
        }
        return Ok(None);
    }

    #[cfg(not(windows))]
    {
        // User-specified default
        let p = expand_path("~/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Thomas & Friends™ Wonders of Sodor/WindowsNoEditor/TS2Prototype/Content/Paks")?;
        if p.is_dir() {
            Ok(Some(p))
        } else {
            Ok(None)
        }
    }
}

fn legacy_state_dir() -> Result<PathBuf> {
    #[cfg(windows)]
    {
        let base =
            std::env::var_os("LOCALAPPDATA").ok_or_else(|| anyhow!("LOCALAPPDATA is not set"))?;
        return Ok(PathBuf::from(base).join("WOS_JapaneseMOD"));
    }

    #[cfg(not(windows))]
    {
        let home = std::env::var_os("HOME").ok_or_else(|| anyhow!("HOME is not set"))?;
        return Ok(PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("WOS_JapaneseMOD"));
    }
}

fn load_state() -> Result<PersistentState> {
    let legacy = legacy_state_dir()?.join("state.json");
    if !legacy.is_file() {
        return Ok(PersistentState::default());
    }
    let s = fs::read_to_string(&legacy)
        .with_context(|| format!("Failed to read state: {}", legacy.display()))?;
    let st: PersistentState = serde_json::from_str(&s)
        .with_context(|| format!("Invalid state JSON: {}", legacy.display()))?;
    Ok(st)
}

fn save_state(state: &PersistentState) -> Result<()> {
    let path = legacy_state_dir()?.join("state.json");
    save_state_at(state, &path)
}

fn save_state_at(state: &PersistentState, path: &Path) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create state dir: {}", parent.display()))?;
    }
    let tmp = path.with_extension("json.tmp");
    let s = serde_json::to_string_pretty(state).context("Failed to serialize state")?;
    fs::write(&tmp, s).with_context(|| format!("Failed to write {}", tmp.display()))?;
    fs::rename(&tmp, &path).with_context(|| {
        format!(
            "Failed to replace state file: {} -> {}",
            tmp.display(),
            path.display()
        )
    })?;
    Ok(())
}

fn expand_path(s: &str) -> Result<PathBuf> {
    // Minimal expansion for convenience:
    // - Windows: %VAR%
    // - macOS/Linux: $VAR and leading ~/
    let mut out = s.to_string();

    #[cfg(windows)]
    {
        let re = Regex::new(r"%([A-Za-z0-9_]+)%")?;
        out = re
            .replace_all(&out, |caps: &regex::Captures| {
                std::env::var(&caps[1]).unwrap_or_default()
            })
            .to_string();
    }
    #[cfg(not(windows))]
    {
        if let Some(stripped) = out.strip_prefix("~/") {
            if let Some(home) = std::env::var_os("HOME") {
                out = PathBuf::from(home)
                    .join(stripped)
                    .to_string_lossy()
                    .to_string();
            }
        }
        let re = Regex::new(r"\$([A-Za-z0-9_]+)")?;
        out = re
            .replace_all(&out, |caps: &regex::Captures| {
                std::env::var(&caps[1]).unwrap_or_default()
            })
            .to_string();
    }

    Ok(PathBuf::from(out.trim_matches('"')))
}

fn resolve_repak_interactive(state: &mut PersistentState) -> Result<Option<PathBuf>> {
    // 1) Try PATH first, but ensure it is the latest supported version.
    // `repak -V` should output: "repak_cli 0.2.3" (as of now).
    const LATEST_REPAK_V: &str = "repak_cli 0.2.3";
    if let Ok(p) = which("repak") {
        match repak_version_string(&p) {
            Ok(Some(v)) if v.trim() == LATEST_REPAK_V => {
                return Ok(Some(p));
            }
            Ok(Some(v)) => {
                println!();
                println!("[repak] PATH 上の repak は最新版ではありません。");
                println!("       検出: {v}");
                println!("       期待: {LATEST_REPAK_V}");
            }
            Ok(None) => {
                println!();
                println!("[repak] PATH 上の repak のバージョン取得に失敗しました。");
            }
            Err(e) => {
                println!();
                println!("[repak] PATH 上の repak のバージョン確認に失敗しました: {e}");
            }
        }
    }

    // 2) Reuse previously provided full path if available and valid.
    if let Some(p) = state.repak_path.as_deref() {
        let p = PathBuf::from(p);
        if p.is_file() {
            if let Ok(Some(v)) = repak_version_string(&p) {
                if v.trim() == LATEST_REPAK_V {
                    return Ok(Some(p));
                }
            }
        }
    }

    #[cfg(windows)]
    {
        println!();
        println!("[repak] 最新版の repak が見つかりません。");
        if prompt_yes_no("       GitHub Releases から最新版をダウンロードしますか？ (y/n): ")? {
            // Always fetch "latest" when user agrees.
            let p = download_repak_windows(true, None)?;
            state.repak_path = Some(p.to_string_lossy().to_string());
            save_state(state).ok();
            return Ok(Some(p));
        }

        let p = prompt_path("       repak.exe のフルパスを入力してください: ")?;
        if p.is_file() {
            state.repak_path = Some(p.to_string_lossy().to_string());
            save_state(state).ok();
            return Ok(Some(p));
        }
        bail!("repak.exe が見つかりません: {}", p.display());
    }

    #[cfg(not(windows))]
    {
        println!();
        println!("[repak] 最新版の repak が見つかりません。");
        if prompt_yes_no("       Homebrew で repak をインストールしますか？ (y/n): ")? {
            println!();
            println!("次のコマンドを実行してください:");
            println!();
            println!("  brew install bear10591/tap/repak");
            println!();
            println!("インストール後、もう一度このツールを実行してください。");
            return Ok(None);
        }

        let p = prompt_path("       repak（repak.exe）のフルパスを入力してください: ")?;
        if p.is_file() {
            state.repak_path = Some(p.to_string_lossy().to_string());
            save_state(state).ok();
            return Ok(Some(p));
        }
        bail!("repak が見つかりません: {}", p.display());
    }
}

fn repak_version_string(repak: &Path) -> Result<Option<String>> {
    let out = Command::new(repak)
        .arg("-V")
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output()
        .with_context(|| format!("Failed to run {} -V", repak.display()))?;

    if !out.status.success() {
        return Ok(None);
    }

    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if s.is_empty() {
        Ok(None)
    } else {
        Ok(Some(s))
    }
}

fn prompt_yes_no(prompt: &str) -> Result<bool> {
    println!("       y: はい / n: いいえ");
    loop {
        print!("{prompt}");
        io::stdout().flush().ok();
        let mut line = String::new();
        io::stdin().read_line(&mut line).context("Failed to read input")?;
        let s = line.trim().to_ascii_lowercase();
        match s.as_str() {
            "y" | "yes" => return Ok(true),
            "n" | "no" => return Ok(false),
            _ => eprintln!("       y または n を入力してください。"),
        }
    }
}

fn prompt_path(prompt: &str) -> Result<PathBuf> {
    loop {
        print!("{prompt}");
        io::stdout().flush().ok();
        let mut line = String::new();
        io::stdin().read_line(&mut line).context("Failed to read input")?;
        let s = line.trim().trim_matches('"');
        if s.is_empty() {
            eprintln!("       パスを入力してください。");
            continue;
        }
        return Ok(PathBuf::from(s));
    }
}

fn which(name: &str) -> Result<PathBuf> {
    let paths = std::env::var_os("PATH").ok_or_else(|| anyhow!("PATH not set"))?;
    for dir in std::env::split_paths(&paths) {
        let candidate = dir.join(name);
        if candidate.is_file() {
            return Ok(candidate);
        }
        #[cfg(windows)]
        {
            let candidate = dir.join(format!("{name}.exe"));
            if candidate.is_file() {
                return Ok(candidate);
            }
        }
    }
    bail!("not found: {name}")
}

#[cfg(windows)]
#[derive(Debug, Deserialize)]
struct GhRelease {
    assets: Vec<GhAsset>,
    tag_name: String,
}

#[cfg(windows)]
#[derive(Debug, Deserialize)]
struct GhAsset {
    name: String,
    browser_download_url: String,
}

#[cfg(windows)]
fn download_repak_windows(
    force: bool,
    dir_override: Option<&str>,
) -> Result<PathBuf> {
    let repak_dir = if let Some(s) = dir_override {
        expand_path(s)?
    } else {
        let base =
            std::env::var_os("LOCALAPPDATA").ok_or_else(|| anyhow!("LOCALAPPDATA is not set"))?;
        PathBuf::from(base)
            .join("WOS_JapaneseMOD")
            .join("repak_cli-x86_64-pc-windows-msvc")
    };
    let repak_exe = repak_dir.join("repak.exe");

    if !force && repak_exe.is_file() {
        println!("       既存の repak を使用: {}", repak_exe.display());
        return Ok(repak_exe);
    }

    println!();
    println!("[repak] ダウンロード (GitHub Releases) ...");

    if repak_dir.exists() {
        let _ = fs::remove_dir_all(&repak_dir);
    }
    fs::create_dir_all(&repak_dir)?;

    let client = Client::builder()
        .user_agent("wonders-of-sodor-mod/wosmod")
        .build()?;

    let release: GhRelease = client
        .get("https://api.github.com/repos/trumank/repak/releases/latest")
        .send()
        .context("Failed to fetch repak latest release")?
        .error_for_status()
        .context("GitHub API returned error")?
        .json()
        .context("Failed to parse GitHub release JSON")?;

    let asset_name = "repak_cli-x86_64-pc-windows-msvc.zip";
    let asset = release
        .assets
        .iter()
        .find(|a| a.name == asset_name)
        .ok_or_else(|| anyhow!("Release asset not found: {asset_name}"))?;

    let tmp_zip = std::env::temp_dir().join(format!("repak_cli_{}.zip", release.tag_name));
    download_to_file(&client, &asset.browser_download_url, &tmp_zip)?;

    extract_zip_flat(&tmp_zip, &repak_dir)?;
    if !repak_exe.is_file() {
        bail!(
            "repak.exe not found after extraction: {}",
            repak_exe.display()
        );
    }
    println!("       配置完了: {}", repak_exe.display());
    Ok(repak_exe)
}

#[cfg(windows)]
fn download_to_file(client: &Client, url: &str, dst: &Path) -> Result<()> {
    let mut resp = client.get(url).send().context("Download failed")?;
    resp.error_for_status_ref()
        .context("Download returned HTTP error")?;
    let mut f =
        fs::File::create(dst).with_context(|| format!("Failed to create {}", dst.display()))?;
    let mut buf = Vec::new();
    resp.copy_to(&mut buf)
        .context("Failed to read download body")?;
    f.write_all(&buf)?;
    Ok(())
}

#[cfg(windows)]
fn extract_zip_flat(zip_path: &Path, dst_dir: &Path) -> Result<()> {
    let f = fs::File::open(zip_path)?;
    let mut zip = ZipArchive::new(f).context("Invalid zip")?;
    for i in 0..zip.len() {
        let mut file = zip.by_index(i)?;
        let name = file.name().to_string();
        if name.ends_with('/') {
            continue;
        }
        // Flatten single top-level folder if present: take only the filename.
        let out_name = Path::new(&name)
            .file_name()
            .and_then(OsStr::to_str)
            .ok_or_else(|| anyhow!("Invalid zip entry name"))?;
        let out_path = dst_dir.join(out_name);
        let mut out = fs::File::create(&out_path)?;
        io::copy(&mut file, &mut out)?;
    }
    Ok(())
}
