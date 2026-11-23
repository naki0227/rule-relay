# 引き継ぎ: W1 の教える案内（2026-11-22、ブランチ `claude/w1-teaching`）

最初の 10 分の見直し（HUD・UI・タイトル・メニュー・カメラ）の作業と、同じファイルに触れる所のメモ。

## HUD（`src/ui/hud.gd`）で変えた所

- `update_context` の中身の「案内を並べる」部分を、新しい `src/ui/teach_hints.gd`（`TeachHints.pick`）に移した。
  案内は**いつも 1 つだけ**になる。`_first_step_prompts` / `_place_prompts` / `_lend_prompts` / `_fire_prompts` /
  `_retry_prompts` / `_selected_token` / `_stage_name` と `_stage_names` は hud.gd から消えて、teach_hints.gd にある。
- 照準の下の札（`_context`）の作り・見た目・狙っている相手の名前は変えていない。
- 目的の札（`ObjectivePanel`、ノード名 `Objectives`）が大きく出ている間は、案内を出さない（`TeachHints._objectives_big`）。
  ノード名を変えるときは、そこも直してほしい。

## 入力（`src/ui/player_input.gd`）で足した所

- 案内の記録を数える `_note_press`（W/A/S/D/Space）、`_note_mode`（繰り返しへの切りかえ）、地面・禁止の F を数える 2 行。
  キーの割り当て・カメラの扱いは触っていない。

## 広場（W1 のポータルの案内だけ）

- `OverworldLayout.PortalSpec.next` と `Overworld._mark_next`: W1 で次に遊ぶポータルに印。
- `OverworldPortal`: 印のある門に光の柱（`NextBeam`）。門の上の文字は「はじめはここから」（最初の門）／「つぎはここ」。

## ゲームの決まりで変えた所（UI ではないが、持ち物の画面に関係する）

- ブロック・生き物に最初から付いていた能力・禁止を F で取ると、ホットバーに空きがあればそこへ入る
  （`WorldLending.to_hotbar_if_free`）。落ちている器を拾ったときは今までどおりかばんへ。重い・浮く・泳ぐもかばんへ。

詳しくは [docs/w1-teaching.md](../w1-teaching.md)。
