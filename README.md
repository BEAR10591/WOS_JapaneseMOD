# WOS Japanese MOD

『**Thomas & Friends™: Wonders of Sodor**』向けの日本語フォント最適化 MOD です。  
ゲームの `TS2Prototype-WindowsNoEditor.pak` を **repak** で展開・再パックし、MOD 用アセットを反映します。

補足: 中国語（簡体字）表示についても、可読性が出るよう **適切なウェイトの Noto Sans SC** を使うよう調整しています。

---

## 配布について

**GitHub Releases** に **`.zip`** を公開しています。**常に最新版の zip をダウンロード**してから、展開し、同梱の手順に従ってください。  
（リポジトリをクローンして使う場合も、以下の内容はほぼ同じです。）

---

## 同梱物

OS ごとに **ビルド用スクリプト**の拡張子が異なります。**MOD データのフォルダ**（`WOS_JapaneseMOD_Knapford/`、`WOS_JapaneseMOD_SODOR/`）は Windows / macOS で共通です。

### Windows

| 種類 | ファイル |
|------|----------|
| ビルド用バッチ | `WOS_JapaneseMOD_Knapford.bat` … **英語フォントに Knapford が採用される** |
| | `WOS_JapaneseMOD_SODOR.bat` … **英語フォントに SODOR が採用される** |
| mod データ | `WOS_JapaneseMOD_Knapford/`、`WOS_JapaneseMOD_SODOR/` |

### macOS

| 種類 | ファイル |
|------|----------|
| ビルド用スクリプト | `WOS_JapaneseMOD_Knapford.command` … **英語フォントに Knapford が採用される** |
| | `WOS_JapaneseMOD_SODOR.command` … **英語フォントに SODOR が採用される** |
| mod データ | `WOS_JapaneseMOD_Knapford/`、`WOS_JapaneseMOD_SODOR/`（Windows と同じ） |

※ 初めて `.command` を開くとき、macOS のセキュリティで止められることがあります。右クリック →「開く」から試すか、ターミナルで `chmod +x WOS_JapaneseMOD_*.command` を実行してからダブルクリックしてください。

**どちらか一方だけ**をゲームに入れる想定です。2 つの違いは、**英語表示に使うフォントを Knapford にするか、SODOR にするか**です。好みに合わせて、Windows では **`.bat`**、macOS では **`.command`** を選んでください。

---

## 事前に用意するもの（Windows）

- **Steam 版**の『Thomas & Friends™: Wonders of Sodor』が **パソコンにインストール済み**であること。
- **インターネット接続**（初回のみ、後述の **repak** を自動で取りに行くため。2 回目以降は、すでに取得済みなら省略されることがあります）。
- 可能なら、実行前に **ゲームと Steam を終了**しておくと安全です（ファイルの上書きに失敗しにくくなります）。

---

## かんたんな使い方（Windows）

1. **zip を展開する**  
   デスクトップなど、分かりやすい場所にフォルダごと置いてください。  
   （中に `.bat` ファイルや `WOS_JapaneseMOD_…` フォルダがある状態になっていれば OK です。）

2. **使いたい版の `.bat` を実行する**  
   - **Knapford 版** → `WOS_JapaneseMOD_Knapford.bat` をダブルクリック。  
   - **SODOR 版** → `WOS_JapaneseMOD_SODOR.bat` をダブルクリック。  
   黒い画面（コマンドプロンプト）が開き、処理が進みます。完了まで **閉じずに待ち**ます。

3. **初回だけバックアップが作られる**  
   ゲーム本体の元 pak が、同じフォルダ内の `Backup\TS2Prototype-WindowsNoEditor.pak` にコピーされます。**元に戻したいとき**は、このファイルをゲームの `…\Paks\` に戻す方法を検討してください（自己責任です）。
   
   ※ **ゲーム本体がアップデート**されると、ゲーム側の `TS2Prototype-WindowsNoEditor.pak` が新しいものに置き換わることがあります。その場合は **もう一度 `.bat` / `.command` を実行して MOD を再適用**してください。  
   ※ アップデート後に **バックアップも取り直したい**場合は、実行前に `Backup\` フォルダ（または `Backup\TS2Prototype-WindowsNoEditor.pak`）を **一度削除**してから実行してください（バックアップが存在するとスクリプトは再作成をスキップします）。

4. **「完了」と出たら終了**  
   スクリプトが、ビルドした pak をゲームのインストール先へコピーして差し替えます。

### うまくいかないとき

- **ゲームや Steam を起動したまま**だと、ファイルがロックされて失敗することがあります。いったんすべて終了してから再実行してください。
- **ウイルス対策ソフト**が `.bat` やダウンロードした `repak` をブロックすることがあります。警告が出た場合は、当 MOD 用フォルダを除外する／一時的に許可するなど、ご自身の判断で調整してください。
- Steam の **ライブラリを別ドライブ**に置いているなど、下記の「デフォルトのパス」と違う場合は、`.bat` をメモ帳で開き、ゲームの `TS2Prototype-WindowsNoEditor.pak` の場所に合わせて変数を編集する必要があります。

---

## スクリプトが内部的に行うこと（Windows）

1. **repak** の準備（初回は GitHub から Windows 用をダウンロードしてフォルダに展開。既に `repak.exe` がある場合は省略可）  
2. ゲームの **元 pak** を `Backup\TS2Prototype-WindowsNoEditor.pak` に保存（**初回のみ**。既にあればスキップ）  
3. その pak を **`WOS_pack_work_Knapford\TS2Prototype-WindowsNoEditor\`** または **`WOS_pack_work_SODOR\TS2Prototype-WindowsNoEditor\`** に展開する（`repak unpack` の `--output`）  
4. `WOS_JapaneseMOD_Knapford` または `WOS_JapaneseMOD_SODOR` の内容を **上書きコピー**  
5. **再パック**して、同じ作業ルート直下に `TS2Prototype-WindowsNoEditor.pak` を生成（展開フォルダと並ぶ）  
6. その pak を **ゲームの Paks フォルダ**にある同名ファイルと **差し替え**  
7. 成功したら、**`WOS_pack_work_Knapford\` と `WOS_pack_work_SODOR\` の両方**をフォルダごと削除して容量を回収（設定でオフにできます）

- **バックアップ**: `Backup\TS2Prototype-WindowsNoEditor.pak`（Knapford / SODOR で共有）  
- **作業ルート**（`WOS_pack_work_Knapford\` / `WOS_pack_work_SODOR\`）: 実行したスクリプト側のフォルダの中に **`TS2Prototype-WindowsNoEditor\`**（展開ツリー）と **`TS2Prototype-WindowsNoEditor.pak`**（ビルド結果）が置かれます。クリーンアップ有効時は **両方の作業ルートをまとめて削除**します（どちらの `.bat` / `.command` を実行しても同じです）。

---

## ゲームの pak の場所（Windows）

次の **いずれか**を自動で探します（通常の Steam 既定インストール向け）。

- `C:\Program Files (x86)\Steam\steamapps\common\Thomas & Friends™ Wonders of Sodor\WindowsNoEditor\TS2Prototype\Content\Paks\TS2Prototype-WindowsNoEditor.pak`
- `C:\Program Files\Steam\steamapps\common\...`（同上）

別フォルダにインストールしている場合は、各 `WOS_JapaneseMOD_*.bat` の **`:FIND_GAME_PAK`** 内にある PowerShell コマンド中の候補パス（`C:\Program Files (x86)\Steam\steamapps\common` / `C:\Program Files\Steam\steamapps\common`）を、実際の Steam インストール先に合わせて編集してください。

---

## 設定の変更（Windows・上級者向け）

各 `.bat` の先頭で `set` されている変数で、次のような動きを調整できます（**既定**はスクリプトに書かれている値です）。

| 変数 | 既定 | 意味 |
|------|------|------|
| `SKIP_REPAK_DL_IF_PRESENT` | `1` | `1` のとき、既に `repak.exe` があれば GitHub からの再ダウンロードを試みない。`0` だと毎回ダウンロードを試みる |
| `FORCE_REPAK_DL` | `0` | `1` だと repak を毎回取り直す（上書き展開） |
| `SKIP_REPAK_CHECK` | `1` | `0` だと**実行開始時**に `repak.exe` の存在を必須にし、無ければ即終了。`1` だとその事前チェックを省略し、[1/10] の取得処理まで進む（未取得でもエラーにしない） |
| `CLEANUP_AFTER_BUILD` | `1` | `1` で成功後に **`WOS_pack_work_Knapford` と `WOS_pack_work_SODOR` の両方**をフォルダごと削除。`0` だと残す（トラブル調査用） |

※ `SKIP_REPAK_CHECK` は **Windows の `.bat` にもあります**（macOS の `.command` と同じ名前・同じ考え方です）。

---

## macOS で使う場合

macOS では、同梱の **`WOS_JapaneseMOD_Knapford.command`** / **`WOS_JapaneseMOD_SODOR.command`** を使います。

1. **Homebrew** で **repak** を入れます。

   ```bash
   brew install bear10591/tap/repak
   ```

2. **`.command` を実行**します（ターミナルからでも、Finder でダブルクリックでも可）。  
   処理の流れは Windows 版と同様です。

3. **ゲームの pak のパス**は、デフォルトで **Sikarugir** で作成した Steam（Wine 内）を想定しています。環境が違う場合は、各 `.command` 内の `GAME_ORIGINAL_PAK` を編集してください。

   ```
   ${HOME}/Applications/Sikarugir/Steam.app/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Thomas & Friends™ Wonders of Sodor/WindowsNoEditor/TS2Prototype/Content/Paks/TS2Prototype-WindowsNoEditor.pak
   ```

4. ターミナルから実行する場合、次の **環境変数**で挙動を変えられます（省略時は括弧内の既定）。

| 変数 | 既定 | 意味 |
|------|------|------|
| `SKIP_REPAK_DL_IF_PRESENT` | `1` | `repak` が PATH にあれば `brew install` を省略 |
| `FORCE_REPAK_DL` | `0` | `1` なら `brew reinstall bear10591/tap/repak` |
| `SKIP_REPAK_CHECK` | `1` | `0` だと**実行開始時**に `repak` の存在を必須にし、無ければ即終了。`1` だとその事前チェックを省略し、[1/10] の取得処理まで進む（未取得でもエラーにしない） |
| `CLEANUP_AFTER_BUILD` | `1` | `1` で成功後に **`WOS_pack_work_Knapford` と `WOS_pack_work_SODOR` の両方**をフォルダごと削除。`0` だと残す（トラブル調査用） |

---

## 注意事項

- ゲームファイルの改変は **自己責任** です。必ず **`Backup`** の有無を確認してください。
- Knapford 用と SODOR 用では **作業フォルダと MOD フォルダは別**ですが、**ゲームに入るファイル名は同じ** `TS2Prototype-WindowsNoEditor.pak` です。**最後に実行した方**がゲームに反映されます。
- オンライン規約・アンチチート等については、ご利用環境に応じてご確認ください。

---

## ライセンス

MIT License（詳細は `LICENSE` を参照）。ゲーム本体および Steam は各権利者の商標・著作物です。
