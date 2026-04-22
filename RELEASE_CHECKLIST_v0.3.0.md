## v0.3.0 リリース準備チェックリスト（まだリリースしない）

このファイルは **準備用**です。タグ作成（`v0.3.0`）や GitHub Release 公開は、実行タイミングが来るまで行いません。

### 事前確認

- [ ] `main` がクリーン（`git status` が空）
- [ ] `Cargo.toml` の `version = "0.3.0"` になっている
- [ ] `CHANGELOG.md` に `[0.3.0]` セクションがある（Unreleased のままで OK）
- [ ] `.github/workflows/release.yml` の `dry_run` が既定で `true` のまま

### ローカルでの最低限の動作確認（任意）

- [ ] `cargo build --release` が通る
- [ ] 生成物 `target/release/WOS_JapaneseMOD`（macOS）/ `WOS_JapaneseMOD.exe`（Windows）が想定どおり

### CI / 配布物（タグを打つ前にできること）

- [ ] GitHub Actions の `Release` を `workflow_dispatch` で **dry-run（`dry_run=true`）** 実行し、成果物 ZIP が作れることを確認
  - 期待: `WOS_JapaneseMOD-Windows-<tag>.zip` と `WOS_JapaneseMOD-macOS-<tag>.zip` が artifacts として出る

### リリース直前に決めること（ここでは未実施）

- [ ] `CHANGELOG.md` の `0.3.0` を日付に確定（例: `2026-xx-xx`）
- [ ] タグ `v0.3.0` を作成して push（この push が GitHub Release 公開トリガーになる）
