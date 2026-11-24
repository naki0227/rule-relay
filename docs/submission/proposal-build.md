# 企画書 PDF の作り方

- 状態: 2026-11-24 作成（AI＝Claude Code）。PDF の中身は下書き [proposal-draft.md](proposal-draft.md) を、公式の 15 ページ以内に収まるよう絵と短い文に組み直したもの。
- 原稿: [proposal/index.html](proposal/index.html)（HTML と SVG）と [proposal/proposal.css](proposal/proposal.css)。図は HTML と SVG で描いていて、画像生成 AI は使っていない。
- 道具: `tools/build_proposal.js`（Node.js ＋ Playwright の Chromium で HTML を印刷して PDF にする）。
- 出力: `build/proposal/proposal.pdf`（Git には入れない）と、ページごとの小さな見本 [proposal-preview/](proposal-preview/)（Git に入れる。GitHub で中身を見るため）。

## 準備（初回だけ）

Node.js 18 以上が要る（Mac なら `brew install node`）。リポジトリの外の好きな場所で一度だけ:

```bash
npm install -g playwright
npx playwright install chromium
```

`npm install -g` を避けたいときは、リポジトリの直下で `npm install --no-save playwright` でもよい（`node_modules/` は `.gitignore` に入れてある）。

## 作る

```bash
node tools/build_proposal.js            # PDF と見本 PNG
node tools/build_proposal.js --no-preview   # PDF だけ
node tools/build_proposal.js --final    # 印が 1 つでも残っていたら失敗（提出の直前に使う）
```

道具は次を確かめ、問題があれば失敗で終わる:

- 画像・書体が全部読めた（パスの書き間違い）。
- 中身がページの外や札の外へあふれていない。
- PDF のページ数が原稿のページ（`<section class="page">`）の数と同じで、**15 ページ以内**。
- 本人が埋める・確かめる印の一覧を、ページ番号つきで出す。

書体はゲームと同じ `assets/fonts/` の Zen Maru Gothic（SIL OFL 1.1）を読むので、ネットにつながなくても Linux と Mac で同じ見た目になる。画面写真は `docs/images/` のものをそのまま使う。

## 印（PDF の中で蛍光ペンの見た目になる）

| 印 | 意味 | 下書きでの書き方 |
|---|---|---|
| 【要確認】（黄） | AI がコード・テスト・文書で確かめきれなかったこと | 【要確認】 |
| 【記入】（水色） | 本人しか知らない事実（氏名・SNS・AI のモデル名など）。AI は推測で埋めない | 【本人が記入】 |
| 【未決】（薄紫） | 本人がまだ決めていないこと（タイトル・価格など） | 【未決・本人が決める】 |
| 案（点線の小さな札） | AI の提案で、本人はまだ選んでいない | 【提案】 |

印を埋めたら `index.html` の `<span class="mark ...">【…】</span>` を消して中身を書く。下書き（proposal-draft.md）も同じように直す。

## 直すときの決まり

- 数字・仕様は下書きと、その出典（ADR・`docs/campaign-plan.md`・コード）で確かめてから書く。各ページの下の小さな文字が出典。
- 色は `src/ui/ui_theme.gd` と `src/game/art_palette.gd` の値だけ（`proposal.css` の `:root`）。禁止の赤は禁止にだけ使う。
- 文字を増やすより写真を大きくする（本人は文章の多い資料を好まない）。
- 提出の写真は、アートスタイルを決めたあと Windows 実機（GPU あり）で撮り直したものに差し替える（いまはソフトウェア描画の画面。表紙に注記あり）。
- 「技術と品質」の自動テストの件数（`#test-count`）は、PDF にする日の `tools/check.sh` の結果で書き直す。

## 2026-11-24 の版で下書きから変えたこと

- 対象の版を v0.3.0 から **v0.3.1** にした（`export_presets.cfg`）。
- W1 で教える操作を v0.3.1 の並び（1-5 で投げる・装備、1-6 で禁止）にした（`docs/w1-teaching.md`、v0.3.1 のリリースノート）。`docs/campaign-plan.md` の 2-1 にはまだ「禁止の初出」とあり、食い違いは PDF に【要確認】で残した。
- 3D モデルの数を、下書きの「15 点」から、2026-11-24 の `assets/models/` の `.glb` の数（50 点）にした。
- 協力の入口を v0.3.1 のタイトル画面（「友だちと遊ぶ」の中に「部屋を作る」「部屋に入る」）に合わせた（`src/ui/title_menu.gd`）。
