use std::ffi::OsStr;
use std::fs;
use std::io::Read;
#[cfg(windows)]
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

use anyhow::{anyhow, bail, Context, Result};
use clap::{Parser, ValueEnum};
use regex::Regex;
#[cfg(windows)]
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;
#[cfg(windows)]
use zip::ZipArchive;

#[derive(Debug, Clone, Copy, ValueEnum, Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
enum Variant {
    #[value(name = "knapford")]
    Knapford,
    #[value(name = "sodor")]
    Sodor,
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

    let cfg = load_config_with_fallbacks(&repo_root)?;

    let force_repak = cfg
        .repak
        .as_ref()
        .and_then(|r| r.force_redownload)
        .unwrap_or(false);
    let repak = resolve_repak(&repo_root, force_repak, cfg.repak.as_ref())?;
    let game_paths = resolve_game_paks_from_config(&cfg)?;

    let backup_dir = resolve_backup_dir(cfg.backup_dir.as_deref())?;
    fs::create_dir_all(&backup_dir).context("Failed to create backup directory")?;

    let backups = BackupPaths {
        main: backup_dir.join("TS2Prototype-WindowsNoEditor.pak"),
        sodor_core: backup_dir.join("TS2Prototype-WindowsNoEditor-Sodor-coredata.pak"),
        james_core: backup_dir.join("TS2Prototype-WindowsNoEditor-James-coredata.pak"),
    };

    backup_if_missing(&game_paths.main, &backups.main)?;
    backup_if_missing(&game_paths.sodor_core, &backups.sodor_core)?;
    backup_if_missing(&game_paths.james_core, &backups.james_core)?;

    let pack_work_root = match cfg.variant {
        Variant::Knapford => repo_root.join("WOS_pack_work_Knapford"),
        Variant::Sodor => repo_root.join("WOS_pack_work_SODOR"),
    };

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

    apply_overlay(&repo_root, cfg.variant, &unpack)?;

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

    if cfg.cleanup.unwrap_or(true) {
        cleanup_workdirs(&repo_root)?;
    }

    println!();
    println!("[OK] 完了: ゲームに配置しました。");
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
    //   it contains at least one of the MOD overlay directories.
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
        let kn = dir.join("WOS_JapaneseMOD_Knapford");
        let so = dir.join("WOS_JapaneseMOD_SODOR");
        if kn.is_dir() || so.is_dir() {
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

fn default_backup_dir() -> Result<PathBuf> {
    #[cfg(windows)]
    {
        let base =
            std::env::var_os("LOCALAPPDATA").ok_or_else(|| anyhow!("LOCALAPPDATA is not set"))?;
        return Ok(PathBuf::from(base).join("WOS_JapaneseMOD").join("Backup"));
    }

    #[cfg(not(windows))]
    {
        let home = std::env::var_os("HOME").ok_or_else(|| anyhow!("HOME is not set"))?;
        return Ok(PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("WOS_JapaneseMOD")
            .join("Backup"));
    }
}

fn resolve_backup_dir(override_path: Option<&str>) -> Result<PathBuf> {
    if let Some(s) = normalize_opt_str(override_path) {
        return Ok(expand_path(s)?);
    }
    default_backup_dir()
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
    if !repak.exists() {
        bail!("repak not found: {}", repak.display());
    }
    if !pak.is_file() {
        bail!("Backup pak missing: {}", pak.display());
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

fn apply_overlay(repo_root: &Path, variant: Variant, unpack: &UnpackDirs) -> Result<()> {
    println!();
    println!("[overlay] MOD を pak 展開先 (3種) に上書きコピー ...");

    let base = match variant {
        Variant::Knapford => repo_root.join("WOS_JapaneseMOD_Knapford"),
        Variant::Sodor => repo_root.join("WOS_JapaneseMOD_SODOR"),
    };

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

fn cleanup_workdirs(repo_root: &Path) -> Result<()> {
    println!();
    println!(
        "[cleanup] WOS_pack_work_Knapford / WOS_pack_work_SODOR をフォルダごと削除（容量削減） ..."
    );
    for d in ["WOS_pack_work_Knapford", "WOS_pack_work_SODOR"] {
        let p = repo_root.join(d);
        if p.is_dir() {
            // Retry a few times in case of transient "Directory not empty" (macOS: os error 66)
            let mut last_err: Option<std::io::Error> = None;
            let mut ok = false;
            for _ in 0..5 {
                match fs::remove_dir_all(&p) {
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
            if ok && !p.exists() {
                println!("       削除: {}", p.display());
            } else if let Some(e) = last_err {
                eprintln!(
                    "[WARN] 作業フォルダの削除に失敗しました: {} ({e})",
                    p.display()
                );
            } else {
                eprintln!("[WARN] 作業フォルダの削除に失敗しました: {}", p.display());
            }
        }
    }
    Ok(())
}

fn resolve_game_paks_from_config(cfg: &Config) -> Result<GamePaths> {
    let dir = if let Some(s) = cfg.game_pak_dir.as_deref() {
        if s.trim().is_empty() {
            detect_default_game_pak_dir()?.ok_or_else(|| {
                anyhow!("`game_pak_dir` is empty and no default Paks directory was found")
            })?
        } else {
            expand_path(s)?
        }
    } else {
        detect_default_game_pak_dir()?.ok_or_else(|| {
            anyhow!("`game_pak_dir` is missing and no default Paks directory was found")
        })?
    };

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

fn resolve_repak(
    _repo_root: &Path,
    _force: bool,
    repak_cfg: Option<&RepakConfig>,
) -> Result<PathBuf> {
    #[cfg(windows)]
    {
        let dir_override = repak_cfg.and_then(|c| normalize_opt_str(c.windows_dir.as_deref()));
        return download_repak_windows(_repo_root, _force, dir_override);
    }

    #[cfg(not(windows))]
    {
        if let Some(c) = repak_cfg {
            if let Some(p) = normalize_opt_str(c.path.as_deref()) {
                let p = expand_path(p)?;
                if p.is_file() {
                    return Ok(p);
                }
                bail!("repak path from config not found: {}", p.display());
            }
        }
        // On macOS/Linux: rely on PATH (e.g., brew install repak).
        if let Ok(p) = which("repak") {
            return Ok(p);
        }
        bail!("repak が見つかりません。macOS では `brew install bear10591/tap/repak` を実行してください。");
    }
}

#[derive(Debug, Deserialize, Serialize)]
struct Config {
    variant: Variant,
    /// Directory path containing TS2Prototype-WindowsNoEditor*.pak
    game_pak_dir: Option<String>,
    /// Optional backup directory override
    backup_dir: Option<String>,
    /// true by default
    cleanup: Option<bool>,
    /// repak config
    repak: Option<RepakConfig>,
}

#[derive(Debug, Deserialize, Serialize)]
struct RepakConfig {
    /// macOS: explicit repak path (optional). If omitted, use PATH.
    path: Option<String>,
    /// Windows: directory to place/download repak (optional)
    windows_dir: Option<String>,
    /// If true, re-download repak even if already present (Windows only)
    force_redownload: Option<bool>,
}

fn load_config(path: &Path) -> Result<Config> {
    let mut s = String::new();
    fs::File::open(path)
        .with_context(|| format!("Config file not found: {}", path.display()))?
        .read_to_string(&mut s)?;
    let cfg: Config = serde_yaml::from_str(&s).context("Invalid YAML")?;
    Ok(cfg)
}

fn default_config_dir() -> Result<PathBuf> {
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

fn default_config_path() -> Result<PathBuf> {
    Ok(default_config_dir()?.join("config.yaml"))
}

fn load_config_with_fallbacks(repo_root: &Path) -> Result<Config> {
    // Priority:
    // 1) persistent config: <AppSupport>/WOS_JapaneseMOD/config.yaml
    //
    // Additionally, if persistent config does not exist but a bundled template exists
    // next to the executable / repo root, copy it to the persistent location on first run.
    let persistent = default_config_path()?;

    if persistent.is_file() {
        return load_config(&persistent);
    }

    // Seed from bundled template if available
    let bundled = repo_root.join("config.yaml");
    if bundled.is_file() {
        if let Some(parent) = persistent.parent() {
            fs::create_dir_all(parent).ok();
        }
        fs::copy(&bundled, &persistent).with_context(|| {
            format!(
                "Failed to copy bundled config to persistent location: {} -> {}",
                bundled.display(),
                persistent.display()
            )
        })?;
        return load_config(&persistent);
    }

    bail!(
        "設定ファイルが見つかりません。\n\
         次の場所に `config.yaml` を配置してください:\n\
         - {}\n\
         （ヒント: 配布物に同梱されている config.yaml をコピーして編集してください）",
        persistent.display()
    );
}

fn normalize_opt_str<'a>(s: Option<&'a str>) -> Option<&'a str> {
    match s {
        None => None,
        Some(v) => {
            let t = v.trim();
            if t.is_empty() {
                None
            } else {
                Some(t)
            }
        }
    }
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
    repo_root: &Path,
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
