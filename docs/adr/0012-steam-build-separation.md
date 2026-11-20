# ADR 0012: Steam 版を提出版から切り離す（GodotSteam GDExtension・機能タグ・書き出しの検査）

- 状態: 採用（2026-11-20。Claude が設計。Steam 版の動作そのものは**未検証**）
- 前提（本人、2026-11-20）:
  - いまは Steam に登録しない。SQUARE ENIX GAME CONTEST は、収益化しておらず未発表の作品が条件のため。
  - Steam の作業をしてよいのは、きれいに分けられる場合だけ。提出版には Steam のコード・Steam のバイナリ・`steam_appid.txt` を一切入れず、今と同じ動き（ソロと ENet の直接接続）にする。
  - 登録・支払いはしない。秘密情報をコミットしない。大きな他者のバイナリはコミットせず、スクリプトで取って gitignore する。
  - 開発用の App ID 480（Valve の見本 Spacewar）はローカルの実験だけで使い、書き出しには入れない。
- 関係: ADR 0006（通信の差し替え・ホスト移譲）

## 調べたこと（2026-11-20）

**どの GodotSteam を使うか**
- GodotSteam の配布元は GitHub から Codeberg（https://codeberg.org/godotsteam/godotsteam）へ移っていた。この環境から GitHub のリリースは開けず（プロキシで 403）、Codeberg の API とサイト（https://godotsteam.com）で確かめた。
- **GDExtension 版 4.24**（タグ `v4.24-gde`、2026-11-07）を使う。
  - 配布物: `godotsteam-4.24-gdextension-plugin-4.4.zip`（27,431,841 バイト、SHA-256 `d4358888959a03f4df0c71aafbcdca8f34b8cb9d4522aa5c8454f0e9e3debbf7`）
  - URL: https://codeberg.org/godotsteam/godotsteam/releases/download/v4.24-gde/godotsteam-4.24-gdextension-plugin-4.4.zip
  - リリースの説明は「Godot 4.4 以上ならどの版でも動く」。`godotsteam.gdextension` の `compatibility_minimum = "4.4"`。Steamworks SDK 1.65。
  - 4.23 の変更履歴に「Godot 4.6 より前で GDExtension が落ちる問題を直した」とある。4.6.3 はその対象外。
- **専用の Godot ビルドは使わない。** 同じ 4.24 のエディタ・テンプレート同梱版（`v4.24`）は Godot 4.5.2 と 4.7.2 向けだけで、4.6.3 向けが無い。GDExtension 版なら CI は公式の Godot 4.6.3 のままでよい。
- **`SteamMultiplayerPeer` は GDExtension に入っている。** 別の拡張は要らない（MultiplayerPeer のリポジトリは本体へ統合済み。変更履歴 https://godotsteam.com/changelog/multiplayer_peer/ ）。このサンドボックスで実際に読み込み、`create_host` / `create_client` / `host_with_lobby` / `connect_to_lobby` / `get_steam_id_for_peer_id` と `server_relay` があることを確かめた。

**ライセンス**
- GodotSteam は **MIT**（`license.md`、「Copyright (c) 2015-Current | GP Garcia, Chris Ridenour, and Contributors」）。同梱するなら著作権表示と許諾文を付ける。
- ZIP に入っている Steam の再頒布ファイル（`steam_api64.dll`・`libsteam_api.so`・`libsteam_api.dylib`）は Valve の Steamworks SDK の条件に従う。SDK Access Agreement 1.1(b) は、SDK の `redistributable_bin` の中身を「Licensee Software（Steamworks のサービスを使うゲーム）と一緒に、オブジェクトコードの形で」再頒布することを認めている（https://partner.steamgames.com/documentation/sdk_access_agreement ）。契約の当事者は SDK を使う開発者自身なので、Steam 版を配る前に本人が条件を読んで同意する必要がある（このリポジトリでは同意も登録もしていない）。
- 2026-06 の GodotSteam のブログに、ライセンスを変える計画は「Godot 5 の頃まで見送り」とある（https://godotsteam.com/blog/category/licenses/ ）。版を上げるときは `license.md` を読み直す。

**サンドボックスで読み込んでみた結果**（Linux x86_64、Godot 4.6.3 公式、Steam クライアントなし）
- `Engine.has_singleton("Steam")` と `ClassDB.class_exists("SteamMultiplayerPeer")` はどちらも true。
- `steamInitEx(480, false)` は `{status: 1, verbal: "Failed to load module '/root/.steam/sdk64/steamclient.so'"}`（Steam クライアントが無い）。
- **初期化に失敗したまま `SteamMultiplayerPeer.create_host(0)` を呼ぶと、Godot ごと落ちる**（signal 11、`SteamAPI_ISteamNetworkingSockets_CreateListenSocketP2P`）。なので peer を作る関数は、初期化に成功した後だけ動くようにした（決定 4）。
- アドオンを置いた直後の最初の `godot --headless --import` は、メッセージなしで SIGABRT（終了コード 134）で終わった。2回目からは正常に終わる。Steam 版の書き出し手順では import を2回走らせる。
- アドオンを置いたままでも、門番が閉じていれば（`--steam` なし）全テスト 408 件が通った。`project.godot` は書き換わらなかった。

## 決定

1. **GodotSteam は GDExtension 版 4.24 を使い、`tools/fetch_godotsteam.sh` で取る。** SHA-256 を検証し、64 ビットの Windows・Linux・macOS の分だけを `addons/godotsteam/` に展開する。エディタ用の更新プラグイン（Asset Library へ通信する）は展開しない。`addons/godotsteam/` と `steam_appid.txt` は `.gitignore` に入れる。CI では取らない。
2. **書き出しのプリセットで分ける。**
   - 提出版（`Windows Desktop`・`macOS`・`Linux`）: `exclude_filter` に `addons/godotsteam/*, src/steam/*` を足す。
   - Steam 版（`Windows (Steam)`）: `custom_features="steam"`（機能タグ）。書き出し先は `build/steam/windows/`（提出版と混ざらない）。Linux・macOS の Steam 版は必要になったら同じ形で足す。
3. **Steam のコードは `src/steam/` に置き、`SteamGate` だけが load する。**
   - `src/net/steam_gate.gd`（提出版にも入る唯一の Steam 関係のコード）は Steam の関数を一度も呼ばない。次の3つがそろったときだけ `src/steam/steam_transport.gd` を load する。
     - Steam 版として起動した: `OS.has_feature("steam")`、または開発中に `--` の後ろへ `--steam`
     - `Engine.has_singleton("Steam")`
     - スクリプトが pck にある（`ResourceLoader.exists`）
   - 提出版では 1 と 3 が必ず欠けるので、`GameRoot.steam` はいつも null。タイトル・ホスト移譲・通信は今までと同じ道を通る。
   - `steam_transport.gd` には `class_name` を付けない（付けると提出版のクラス一覧に名前が残る）。
   - タイトルの Steam の項目は、Steam 版の通信が `TitleMenu.add_entry` / `add_note` で足す。`TitleMenu` 自体は Steam を知らない。
4. **Steam 版の通信（`src/steam/steam_transport.gd`、未検証）**
   - `start(app_id)`: `steamInitEx`。成功したときだけ、ロビーの知らせ（`lobby_created`・`lobby_joined`・`join_requested`）をつなぎ、`run_callbacks` を毎フレーム呼ぶ（一時停止中も）。
   - ホスト: `createLobby(フレンドだけ, 4)` → `lobby_created` → `SteamMultiplayerPeer.create_host(0)`（`server_relay = true`）→ 招待のオーバーレイを開く。
   - 参加者: 招待（`join_requested`、または起動引数 `+connect_lobby <ID>`）→ `joinLobby` → `lobby_joined` → ロビーの持ち主へ `create_client`。
   - できた peer は ENet と同じく `NetWorld.start_host` / `start_client` に渡す（`GameRoot._host_with` / `_join_with`）。ゲームのコードは変えない。
   - App ID: 既定は 0（Steam クライアントから起動したときは Steam が知っている）。開発中だけ `--steam --steam-appid=480`。書き出しやプリセットには入れない。
5. **Steam 版のホスト移譲は「新しいロビーの持ち主 = 新しいホスト」にする。**
   - ホストは状態の荷物に `{プレイヤー ID: SteamID}` を足して配る（`HostMigration.link` があるときだけ）。
   - ホストが落ちたら、Steam がロビーの持ち主を移すのを待つ（最大 30 秒）。持ち主になった人がホストとして待ち受け、ほかの人は持ち主へつなぐ（`HostMigration.elect_by_owner`）。
   - ENet の「残った中で ID がいちばん小さい人」は使わない。理由: Steam ではロビーの持ち主を全員が同じに見るので、これも話し合い不要。しかも、後から招待で入る人もロビーの持ち主へつなぐので、ホストとロビーの持ち主がずれない。最小 ID のままだと、ホストでない持ち主が残り、`setLobbyOwner` での付け替えが要る。
   - ENet のとき（`link` が null）の選出・つなぎ直しは今までどおり。
6. **提出版に Steam が無いことを機械で確かめる**（`tools/check_no_steam.py`）。
   - `--source`（`tools/check.sh` で毎回）: GodotSteam・Steam の DLL・`steam_appid.txt` が Git に入っていない。`project.godot` に GodotSteam の設定が無い。`.gitignore` に入っている。提出版のプリセットが `addons/godotsteam/*` と `src/steam/*` を外している。
   - 書き出しの検査（`tools/check.sh --build` = CI で毎回）: Windows の exe・macOS の zip・Linux の実行ファイルについて、
     - 同じフォルダに `steam_api*`・`libgodotsteam*`・`steam_appid.txt` が無い
     - 埋め込まれた pck のファイル一覧を読み（pck 形式 3 を自前で解析）、`addons/godotsteam/`・`src/steam/` が無い
     - pck の各ファイルとエンジン部分に、`godotsteam`・`steam_api`・`steam_appid`・`libsteam`・`src/steam/`・`SteamMultiplayerPeer`・`steam_transport` の文字列が無い
   - 例外: pck の `.godot/uid_cache.bin` は、Godot がプロジェクトの全ファイルの「UID → パス」の表をそのまま入れる（書き出さない `tests/` も載る）。ここに載る `src/steam/steam_transport.gd` のパス文字列だけは許す。コードではなく、そのファイルは pck に無い。`godotsteam` が載っていたら、アドオンを置いたままの木で書き出したということなので止める。
   - 確かめたこと: アドオンを置いて書き出した Steam 版は、この検査で 9 件の違反として止まった（検査が効いている）。アドオンなしの提出版 3 つは通った。アドオンを置いたまま書き出した提出版は、`uid_cache.bin` の `godotsteam` だけで止まった（DLL・`.gdextension`・`extension_list.cfg` は入っていなかった）。

## 採らなかった案

- **GodotSteam の専用 Godot ビルド（エディタ・テンプレート同梱版）**: 4.6.3 向けが配られていない。CI のエディタとテンプレートを差し替えることになり、提出版も Steam 入りのエンジンになる。
- **ソースに `if OS.has_feature("steam")` を散らす**: 提出版に Steam の分岐がそのまま残る。検査も文字列では書けない。
- **Steam のコードを `.gdignore` のフォルダに置き、Steam 版の書き出し時だけ写す**: `uid_cache.bin` のパスも消せるが、CI でスクリプトの読み込み検査とテストができなくなり、写す手順を忘れる危険が増える。パス文字列1つと引き換えにするほどの差がない。
- **Steam 版を別ブランチで持つ**: main と離れて腐る。プリセットと門番で分ければ、提出版の検査を毎回 CI で回せる。

## 確かめていないこと（応募後に `docs/steam-build.md` の手順で確かめる）

- ロビーの作成・招待・参加・P2P の接続と、Steam 版のホスト移譲。Steam クライアントと App ID が無いので一度も動かしていない。
- 機能タグ `steam` 付きで書き出した Windows の exe の起動（Windows の実機が要る）。
- 招待から起動されたときに `+connect_lobby` が `OS.get_cmdline_args()` に届くか。
- ロビーの持ち主が移るまでの時間（落ちたホストを Steam が抜けたと判断するまで）。30 秒で足りるか。
- Steamworks の登録料・Steam のストアの条件（本人がコンテストの後に判断する）。

## 参考

- GodotSteam（Codeberg）https://codeberg.org/godotsteam/godotsteam
- GodotSteam GDExtension の変更履歴 https://godotsteam.com/changelog/gdextension/
- GodotSteam: MultiplayerPeer のチュートリアル https://godotsteam.com/tutorials/multiplayer_peer/
- GodotSteam: 初期化 https://godotsteam.com/tutorials/initializing/
- GodotSteam: 書き出しと配布 https://godotsteam.com/tutorials/exporting_shipping/
- Steamworks SDK Access Agreement https://partner.steamgames.com/documentation/sdk_access_agreement
