# ゲームプレイ動画の素材を自動で撮る（tools/capture_video.sh）

- 状態: 2026-11-22 作成（v0.3.0、main `a1f9a29` の上で撮った）。
- 目的: `docs/submission/video-plan.md` の場面のうち、決まった手順で再現できるものを、画面なしの環境（CI と同じ Linux）で毎回同じ絵に撮る。編集の下書き（どの場面をどの長さで見せるか・字幕の位置）と、企画書の画面写真の候補に使う。
- 撮れないもの・提出の動画で人がやることは、下の「人の手で撮る・直すもの」。

## 撮り方

```bash
tools/capture_video.sh                      # 全部のクリップ（1280x720・30 fps）
tools/capture_video.sh range_lend throw_arc # 選んだクリップだけ
tools/capture_video.sh --1080p              # 1920x1080（ソフトウェア描画なので約 2 倍の時間）
tools/capture_video.sh --stills             # 撮ったあと、代表の 1 枚を docs/images/video/<clip>.png へ写す
GODOT=/path/to/godot tools/capture_video.sh # Godot の場所を変える（既定は godot）
```

- 要るもの: Godot 4.6.3、`xvfb-run`、Mesa の lavapipe（Vulkan のソフトウェア描画。`/usr/share/vulkan/icd.d/lvp_icd.json`）。ほかの `tools/capture_*.gd` と同じ。
- mp4 にするには ffmpeg が要る（`which ffmpeg`。2026-11-22 の作業環境には `/usr/bin/ffmpeg` があった）。無いときは PNG の連番と WAV だけ作り、そう表示する。入れ方:
  - Ubuntu / Debian: `sudo apt-get install ffmpeg`
  - macOS（Homebrew）: `brew install ffmpeg`
  - Windows: `winget install Gyan.FFmpeg`（または https://ffmpeg.org/download.html の配布物）
- 時間: 1280x720 で 1 クリップ数分（ソフトウェア描画は 1 フレーム約 0.6〜1 秒。準備の区間も描く）。全部で 30〜50 分ほど。
- 撮っている間は、同じ作業ツリーで `tools/check.sh` を走らせない（下の「しくみ」の override.cfg が効いてしまう）。

## クリップ（video-plan.md の場面との対応）

| clip | 長さ | 場所 | 映るもの | video-plan の # |
|---|---|---|---|---|
| `hub_walk` | 13.4 秒 | 広場（草原） | 出現地点から門の並びの間を歩き、西と東の門を見回して、導入の門に F で入る（島に入った直後まで） | 2 |
| `jump_lend` | 10.9 秒 | 1-1 跳ぶ力を貸す | 岩棚の前で跳んでも届かない → 窪みのブロックにジャンプを単発で貸す → 乗って持ち上がり岩棚へ → ゴールの窪みを見下ろす（ジャンプはホットバーに戻っている） | 3 |
| `creature_medal` | 10.5 秒 | 1-4 押し石の小道 | 子どもの動物に移動（D）だけを渡す → 段のふもとまで歩き、吹き出しにジャンプのメダル → ジャンプを渡すと段を上がる。奥に巣の光の柱 | 5 |
| `range_lend` | 11.0 秒 | 1-4 押し石の小道 | 右クリックのプレビューの輪 → 地面の円の中へジャンプを繰り返しで一度に貸す → 一斉に跳ねる地面を、視点を回して見せる | 6 |
| `throw_arc` | 9.4 秒 | 1-4 押し石の小道 | C で「投げる」→ メダルが弧を描いて遠くの地面のセルに当たる → そのセルが繰り返し跳ねる（途中から横の撮影用カメラ） | 7 |
| `coop_jumps` | 12.1 秒 | 1-1 跳ぶ力を貸す（2 人） | 2P がジャンプを 1P へ渡す → 1P がジャンプ ×2 で岩棚へ → 上から 2 つとも 2P へ渡す → 2 人でゴールに入ってクリア。1P の画面（HUD つき）に、2P の画面を左上に小さく重ねる | 11 |
| `clear_return` | 8.7 秒 | 1-1 → 広場 | 岩棚の上からゴールの窪みへ降りてクリアの表示 → 入った門の前へ戻り、振り返って門を見る | 4 |

長さは 2026-11-22 に 1280x720 で撮ったときの値。撮るたびに `build/video/<clip>/marks.txt` とスクリプトの表示（`capture_video: frames …`）で確かめられる。

## 出力（すべて `build/video/`。`build/` は `.gitignore` 済みでコミットしない）

| パス | 中身 |
|---|---|
| `build/video/<clip>.mp4` | H.264（yuv420p、CRF 18）＋ AAC 192 kbps。30 fps |
| `build/video/<clip>/frames/00000.png …` | 使う範囲の PNG の連番（30 fps）。編集ソフトに連番として読ませてもよい |
| `build/video/<clip>/<clip>.wav` | 同じ範囲の音（ゲームの BGM と効果音。48 kHz ステレオ） |
| `build/video/<clip>/still.png` | 代表の 1 枚（真ん中より少し後ろのフレーム） |
| `build/video/<clip>/godot.log`・`marks.txt` | Godot の出力と、使った範囲（描いたフレームの番号の始まりと終わり） |

コミットするのは、各クリップの代表の 1 枚だけ（`docs/images/video/<clip>.png`、1280x720）。`--stills` は真ん中より少し後ろの 1 枚を写す。2026-11-22 の 7 枚のうち `hub_walk`・`creature_medal`（吹き出しのジャンプのメダル）・`range_lend`（プレビューの輪）・`throw_arc`（飛んでいるメダル）・`coop_jumps`（2 人がゴールでクリア）は、場面がよく分かるフレームを `frames/` から手で選んで写した。mp4 と連番は大きいので、リポジトリにも Release にも入れない。

## しくみ

- `tools/capture_video.gd`（SceneTree のスクリプト）がゲーム本体のシーン（`scenes/prototype_island.tscn`。HUD・BGM・効果音つき）を起動し、クリップごとの手順を流す。
  - 操作はプレイヤーと同じ入力: 移動は `move_forward` のキー、向きは視点（カメラの向き）、渡す・F・跳ぶはゲームの操作と同じ関数。視点は毎フレーム目標の向きへ少しずつ寄せるので、なめらかに回る。
  - 準備（島の読み込み・下ごしらえ。例: 動物のジャンプを借りておく）は映さない区間で行い、そこだけは位置を直接置くことがある。
  - `coop_jumps` は `tools/capture_video_coop.gd` が 2P を作る。同じプロセスの中で、専用の SceneMultiplayer と別の物理の世界（own_world_3d の SubViewport）を持つ参加者を作り、ENet（127.0.0.1）で 1P（ホスト）の部屋に入る（`tests/integration/net_party.gd` と同じつなぎ方）。
- 撮るのは Godot の Movie Maker（`--write-movie`、`--fixed-fps 30`）。描いたフレームを全部 PNG に、ゲームの音を WAV に書く。時間はフレーム数で進むので、同じ版なら毎回同じ絵と音になる（通信を使う `coop_jumps` だけは、ENet の届く順で数フレームずれることがある）。
- Movie Maker の大きさは `--resolution` ではなくプロジェクトの `window_width_override`（1600x900）で決まるので、包みのスクリプトが撮る間だけ `override.cfg` を作って上書きし、終わったら必ず消す（`trap`）。`override.cfg` は提出の ZIP の検査でも入っていないことを確かめている（`tools/check_submission.py`）。
- スクリプトが `marks.txt` に「使う範囲」を書き、包みが範囲の外（準備の区間）を捨てて、音も同じ範囲で切る。
- 包みは `build/video/.gdignore` を置く。無いと、次の `godot --import`（`tools/check.sh` の import）が何千枚もの PNG を読み込もうとして落ちる。

## 人の手で撮る・直すもの

- **提出の動画は Windows 11 実機（GPU あり）で撮り直すのが基本**。自動の素材はソフトウェア描画（lavapipe）で、色・明るさ・影が実機と違う（全体に白っぽい）。
- 協力の場面（video-plan の 10・12〜15）: 3〜4 人・観戦・投票・ホスト移譲は、人と PC をそろえて撮る。`coop_jumps` は同じ PC の中の 2 人の 1 場面だけで、2P の画面に HUD は無い（左上の小さな画面）。
- 自動のクリップが無い場面: タイトル、禁止の札、重さの板・水・風などの仕掛け、育った広場（`-- --campaign` で順にクリアした記録が要る）、頂の祭り、広場の空撮、エンドカード。
- `throw_arc` の投げたメダルは、この距離だと小さく、飛ぶのは 1 秒ほど。弧をはっきり見せるなら、実機で近くから撮るか、編集でスローにする。
- `jump_lend` の「跳んでも届かない」は短く、岩棚に近いので分かりにくい。字幕で補う。
- 字幕・場面のつなぎ・タイトルの文字（いまは「（タイトル未定）」）は編集で入れる。
- 音: ゲームの BGM と効果音は入っている。クリップの切れ目で BGM が途切れるので、編集で BGM を通しで敷き直すか、つなぎ目をクロスフェードする。
- W1 のステージ（1-1・1-4）は別の作業で教え方を直している最中。地形や物の位置が変わると、クリップの手順（歩く先・渡す相手）が合わなくなることがある。そのときは `tools/capture_video.gd` の座標を直す（スクリプトは、歩けなかったときに `capture_video: could not walk to …` と警告を出す）。
