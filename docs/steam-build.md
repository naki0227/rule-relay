# Steam 版の作り方（応募後に使う）

> **応募後に使う。** SQUARE ENIX GAME CONTEST の条件（収益化していない・未発表）を守るため、いまは Steam に登録しない。
> 提出版（コンテスト版）はこの手順を使わずに、今までどおり `tools/check.sh --build` か CI で作る。
> 設計と理由は `docs/adr/0012-steam-build-separation.md`。ここに書いた Steam 版の動作は**まだ一度も確かめていない**。

## 0. 先に知っておくこと

- Steam のコードは `src/steam/` にだけある。提出版のプリセットは、このフォルダと `addons/godotsteam/` を書き出しから外す。
- GodotSteam（GDExtension 4.24、MIT）と Steam の再頒布ファイル（`steam_api64.dll` など）は、コミットせずにスクリプトで取る。
  - 再頒布ファイルは Valve の Steamworks SDK Access Agreement の条件で配る。Steam 版を配る前に、本人が条件を読んで同意する。
- App ID 480（Valve の見本 Spacewar）は**自分の PC での実験だけ**に使う。プリセット・書き出し・コミットには入れない。
  - `steam_appid.txt` は作らない（`.gitignore` 済み）。App ID は起動引数で渡す。

## 1. GodotSteam を取る

```bash
tools/fetch_godotsteam.sh
```

- Codeberg の公式リリースから ZIP を取り、SHA-256 を検証して `addons/godotsteam/` に置く。
- 置いた直後の最初の import は、メッセージなしで止まる（終了コード 134）ことがある。2回走らせる。

```bash
godot --headless --import || godot --headless --import
```

## 2. 自分の PC で試す（Steam クライアントを起動してログインしておく）

```bash
godot -- --steam --steam-appid=480
```

- `--steam` を付けたときだけ、タイトルに「Steam で部屋を作る（フレンドを招待）」が出る。
- 付けなければ、アドオンが置いてあっても提出版と同じ画面・同じ動きになる。
- Steam が初期化できないと、警告を出して提出版と同じ画面に戻る（Steam クライアントが起動していない、など）。
- 2人で試すには、2台の PC で別々の Steam アカウントにログインし、フレンドにしておく。片方で部屋を作り、招待のオーバーレイからもう片方を招く。

## 3. Steam 版を書き出す

```bash
mkdir -p build/steam/windows
godot --headless --export-release "Windows (Steam)" build/steam/windows/rule-relay.exe
```

- 書き出し先の `build/steam/windows/` には、`rule-relay.exe` のほかに `libgodotsteam.windows.template_release.x86_64.dll` と `steam_api64.dll` が並ぶ。全部をいっしょに配る。
- `steam_appid.txt` を書き出し先に置かない（Steam クライアントから起動すれば App ID は要らない）。
- GodotSteam の `license.md`（MIT の表示）を配布物に添える。

## 4. 提出版に戻す（大事）

GodotSteam を置いたままの木で提出版を書き出すと、`tools/check_no_steam.py` が止める。提出版を作る前に取り除く。

```bash
tools/fetch_godotsteam.sh --remove
```

```bash
godot --headless --import
```

```bash
tools/check.sh --build
```

- 最後に `no-steam: OK (build/windows/rule-relay.exe, build/macos/rule-relay.zip, build/linux/rule-relay.x86_64)` と `all checks passed` が出れば、提出版に Steam は入っていない。
- CI は GodotSteam を取らないので、CI の書き出しはいつも提出版になる。

## 5. まだ確かめていないこと

- ロビーの作成・招待・参加・P2P の接続（`src/steam/steam_transport.gd`）
- Steam 版のホスト移譲（新しいロビーの持ち主が新しいホストになる。`HostMigration.elect_by_owner`）
- 機能タグ `steam` 付きの Windows の exe の起動
- 招待から起動されたときの `+connect_lobby` の受け取り
