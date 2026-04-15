# WOS Japanese MOD

![スクリーンショット](screenshots/screenshot-01.jpg)

「**きかんしゃトーマス™: ソドー島の不思議**」向けの日本語表示最適化 MOD です。  
ゲームの `TS2Prototype-WindowsNoEditor.pak` を **repak** で展開・再パックし、MOD 用アセットを反映します。

### ※ 現時点では翻訳（テキスト）そのものの修正は一部のみ、試験的実装です。今後のアップデートで順次修正範囲を拡大予定です。

補足: 中国語（簡体字）表示についても、可読性が出るよう **適切なウェイトの Noto Sans SC** を使うよう調整しています。

---

## 配布について

**GitHub Releases** に **`.zip`** を公開しています。**常に最新版の zip をダウンロード**してから、展開し、同梱の手順に従ってください。  
（リポジトリをクローンして使う場合も、以下の内容はほぼ同じです。）

---

## 同梱物

**MOD データのフォルダ**（`WOS_JapaneseMOD_Knapford/`、`WOS_JapaneseMOD_SODOR/`）は Windows / macOS で共通です。  
適用処理は **Rust 製 CLI** が行います（バックアップ → 展開 → 上書きコピー → 再パック → ゲームへ書き戻し）。  
Windows: `WOS_JapaneseMOD.exe` / macOS: `WOS_JapaneseMOD`

### 設定ファイル（共通）

同梱テンプレ `config.yaml` をベースに設定します。初回実行時に、ユーザー固有の永続設定として次の場所へコピーされ、以後は **永続設定が優先**されます。

- Windows: `%LOCALAPPDATA%\WOS_JapaneseMOD\config.yaml`
- macOS: `~/Library/Application Support/WOS_JapaneseMOD/config.yaml`

※ ZIP を別バージョンに更新しても設定を引き継ぎたい場合は、上記の **永続設定**を編集してください。

### 実行ファイル（配布物）

- macOS: `dist/macos/WOS_JapaneseMOD`
- Windows: （同等の Windows 向けビルドを配布物に同梱）

---

## 事前に用意するもの（Windows）

- **Steam 版**の『Thomas & Friends™: Wonders of Sodor』が **パソコンにインストール済み**であること。
- **インターネット接続**（初回のみ、後述の **repak** を自動で取りに行くため。2 回目以降は、すでに取得済みなら省略されることがあります）。
- 可能なら、実行前に **ゲームと Steam を終了**しておくと安全です（ファイルの上書きに失敗しにくくなります）。

---

## かんたんな使い方（Windows）

1. **zip を展開する**  
   デスクトップなど、分かりやすい場所にフォルダごと置いてください。  
   （中に `WOS_JapaneseMOD.exe` と `config.yaml`、`WOS_JapaneseMOD_…` フォルダがある状態になっていれば OK です。）

2. **`config.yaml` を必要に応じて編集する**  
   `variant`（knapford / sodor）や `game_pak_dir` を設定します。

3. **`WOS_JapaneseMOD.exe` を実行する**  
   黒い画面（コマンドプロンプト）が開き、処理が進みます。完了まで **閉じずに待ち**ます。

4. **初回だけバックアップが作られる**  
   ゲーム本体の元 pak が、既定で `%LOCALAPPDATA%\WOS_JapaneseMOD\Backup\` に保存されます。**元に戻したいとき**は、ここに保存されたファイルをゲームの `…\Paks\` に戻す方法を検討してください（自己責任です）。
   
   ※ **ゲーム本体がアップデート**されると、ゲーム側の pak が新しいものに置き換わることがあります。その場合は **もう一度 `WOS_JapaneseMOD.exe` を実行して MOD を再適用**してください。  
   ※ アップデート後に **バックアップも取り直したい**場合は、実行前に `%LOCALAPPDATA%\WOS_JapaneseMOD\Backup\` を **一度退避/削除**してから実行してください（バックアップが存在すると再作成をスキップします）。

5. **「完了」と出たら終了**  
   ツールが、再パックした pak をゲームの `Paks\` に書き戻して差し替えます（3種）。

### うまくいかないとき

- **ゲームや Steam を起動したまま**だと、ファイルがロックされて失敗することがあります。いったんすべて終了してから再実行してください。
- **ウイルス対策ソフト**がダウンロードした `repak` をブロックすることがあります。警告が出た場合は、`%LOCALAPPDATA%\WOS_JapaneseMOD\` を除外する／一時的に許可するなど、ご自身の判断で調整してください。
- Steam の **ライブラリを別ドライブ**に置いているなど、デフォルトの場所と違う場合は、永続設定（`%LOCALAPPDATA%\WOS_JapaneseMOD\config.yaml`）で `game_pak_dir` を設定してください。

---

## 内部的に行うこと（Windows）

1. **repak** の準備（初回は GitHub から Windows 用を自動ダウンロードして配置。2 回目以降は再利用）  
2. ゲームの **元 pak（3種）** をバックアップに保存（**初回のみ**。既にあればスキップ）  
3. バックアップから pak を作業フォルダへ展開（`repak unpack`）  
4. `WOS_JapaneseMOD_Knapford/` または `WOS_JapaneseMOD_SODOR/` の内容を **上書きコピー**  
5. **再パック**して、ゲームの `Paks\` に **直接書き戻し**（`repak pack`）  
6. 成功したら、作業フォルダを削除（`cleanup: true` の場合）

- **バックアップ**: `%LOCALAPPDATA%\WOS_JapaneseMOD\Backup\`  
- **作業フォルダ**: 展開した ZIP の中（`WOS_pack_work_Knapford\` / `WOS_pack_work_SODOR\`）。成功時は削除されます（失敗時に残ることがあります）。

---

## ゲームの pak の場所（Windows）

`config.yaml` の `game_pak_dir` が空の場合、次の場所を自動で探します（通常の Steam 既定インストール向け）。

- `C:\Program Files (x86)\Steam\steamapps\common\Thomas & Friends™ Wonders of Sodor\WindowsNoEditor\TS2Prototype\Content\Paks`

別フォルダにインストールしている場合は、永続設定（`%LOCALAPPDATA%\WOS_JapaneseMOD\config.yaml`）で `game_pak_dir` を設定してください。

---

## macOS で使う場合

macOS では、`brew` で `repak` を入れた上で、同梱の `WOS_JapaneseMOD` を実行します。

1. **Homebrew** で **repak** を入れます。

   ```bash
   brew install bear10591/tap/repak
   ```

2. `config.yaml` を必要に応じて編集します（`variant` / `game_pak_dir`）。

3. `dist/macos/WOS_JapaneseMOD` を実行します（ターミナルからでも、Finder でダブルクリックでも可）。  
   処理の流れは Windows と同様です。

4. **ゲームの pak の場所**は、デフォルトで **Sikarugir** で作成した Steam（Wine 内）を想定しています。環境が違う場合は `config.yaml` の `game_pak_dir` を設定してください。

---

## 注意事項

- ゲームファイルの改変は **自己責任** です。必ず **`Backup`** の有無を確認してください。
- Knapford 用と SODOR 用では **作業フォルダと MOD フォルダは別**ですが、**ゲームに入るファイル名は同じ** `TS2Prototype-WindowsNoEditor.pak` です。**最後に実行した方**がゲームに反映されます。
- オンライン規約・アンチチート等については、ご利用環境に応じてご確認ください。

---

## ライセンス

MIT License（詳細は `LICENSE` を参照）。ゲーム本体および Steam は各権利者の商標・著作物です。

---

## スクリーンショット

![スクリーンショット 02](screenshots/screenshot-02.jpg)
![スクリーンショット 03](screenshots/screenshot-03.jpg)
![スクリーンショット 04](screenshots/screenshot-04.jpg)
