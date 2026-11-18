# AAA タイトルの UI 調査（2026-11-18）

本人の指示: 「UI の感じとかフォントとかめっちゃインディで嫌。AAA タイトル並みに整ったものがいい」。
最初の作り直し（淡い紙・丸いピル・明朝。`.claude/skills/app-quality-bar` の StudyReel トーン）は採らず、この調査をもとに作り直した。
リポジトリのスキルの既定と、今回の本人の指示がぶつかったため、指示を優先した（CLAUDE.md の決まり）。

## 調べたこと（出典）

| 出典 | 分かったこと |
|---|---|
| [80.lv: A Deep Dive Into God of War Ragnarök's User Interface](https://80.lv/articles/a-deep-dive-into-god-of-war-ragnar-k-s-user-interface) | 書体は見出し用と本文用の2つだけで、中央のスタイルシートで管理する。文字は最大 XX-Large まで拡大でき、すべての UI がそれに対応する。大きな文字ほど拡大の段階を小さくする。HUD の要素は、ほかの要素との相対位置で配置する（Dynamic Layouts）。知らせは1つの列で、一度に1件だけ出す。HUD の枠は、中身が入るまで隠しておく |
| [Game Developer: Ghost of Tsushima Design Analysis](https://www.gamedeveloper.com/game-platforms/ghost-of-tsushima-design-analysis) | HUD は最小限。道案内は風（ゲーム世界の中の表現）で行う。敵の強さは数字ではなく服装で示す。案内の印は近づいたときだけ出す |
| [GMTK: Can I fix Zelda's UI](https://gmtk.substack.com/p/can-i-fix-zeldas-ui-using-unity) / [The Famicast: BotW の UI](https://www.thefamicast.com/2017/12/part-2-immersive-impressionable-ui.html) / [GamesRadar: TotK 開発者の声](https://www.gamesradar.com/23-game-developers-explain-why-zelda-tears-of-the-kingdom-will-be-talked-about-for-years) | 情報は必要なときだけ出し、画面に余白を残す。TotK では UI を最小限まで減らす検討をした |
| [GDC: Art Direction for AAA UI](https://gdcvault.com/play/1027158/Cutting-Apart-The-Diegetic-Interface)（関連セッション） | ゲシュタルトなど、グラフィックデザインの原則を HUD に適用する。ゲーム世界の中に UI を置く方法（diegetic UI）と、使いやすさを両立させる |
| [Game UI Database](https://www.gameuidatabase.com/)（[Creative Bloq の紹介](https://www.creativebloq.com/3d/video-game-design/game-ui-database-20-is-the-ultimate-free-reference-tool-for-game-designers)） | 1,300本以上のゲーム画面を、画面の種類別に参照できる。今後、メニュー・インベントリの型を比べるときに使う |
| [GameBusiness.jp: フォントワークス LETS のゲーム組込オプション終了](https://www.gamebusiness.jp/article/2025/12/01/25629.html) | 2025年に商用和文フォントのゲーム組み込みライセンスが終了した。移行先の Monotype では、年約6万円から約320万円以上（5ライセンス）になると報じられている。商用フォントに頼る設計は、費用と継続の危険が大きい |
| [Impress Watch: LINE Seed JP が Google Fonts に](https://internet.watch.impress.co.jp/docs/news/2080437.html) / [GIGAZINE: IBM Plex Sans JP](https://gigazine.net/gsc_news/en/20210726-ibm-plex-sans-jp) | OFL の和文ゴシックの選択肢（Noto Sans JP / LINE Seed JP / IBM Plex Sans JP） |

注: 書体名まで公表している AAA タイトルは少ない（ゼルダの UI 書体は公式には未公表）。そのため、ここでは数値ではなく、組み方の型を抽出した。

## 抽出した型（インディっぽく見える原因との対比）

| 項目 | インディ・モバイルっぽく見えた所（前の版） | AAA の型（今回の版） |
|---|---|---|
| 面 | 淡い紙の箱・丸いピル・影 | 暗い半透明の面、1px の線、角丸 4px。箱を減らし、文字が集まる所だけ端から暗がりを敷く |
| 書体 | 明朝の見出し＋丸みのあるゴシック、字間の詰めが無い | 癖のない骨太なゴシック1書体（Noto Sans JP の可変ウェイト）。見出しは太く、小さな英字ラベル（PAUSED・INVENTORY）は字間を開けて金色にする |
| 色 | 水色と桃色の2色 | 中立（温かい白と黒の透明度の段階）＋強調色の金1つ。赤は禁止の印だけ |
| HUD の量 | キー一覧・方式・保存数を常に表示 | 照準・ホットバー・知らせだけ。ホットバーは4秒操作が無いと薄くなる。キーの案内は狙ったものに応じて照準の下に出す |
| 知らせ | 上中央にピルを積む | 画面左の1か所に、金の線付きの1行で出し、順に消える（最大3件） |
| メニュー | 画面中央の小さなカード | 全画面で背景をぼかして暗くする。左に項目の列、右に詳しい説明、下に操作の帯 |
| 到達の演出 | カード | 箱を使わない映画のテロップ風の帯。大きな文字と、左右に伸びる細い金の線 |
| 解像度 | 1600×900 の固定ピクセル | 1920×1080 を基準に、`canvas_items` で拡大縮小（4K でも同じ配置） |
| 動き | まちまち | ease-out 0.15〜0.22 秒にそろえる |

## まだ AAA に届いていない所（次にやる）

- 文字サイズの設定（God of War の XX-Large までの拡大）と、高コントラストの設定
- 操作の音（選ぶ・決定・取り消し・付与・回収・失敗）
- ゲームパッドの操作と、ボタンの絵（いまはキーボードの文字のキー）
- ホットバー・照準・ブロックのアイコンの線の太さと描き方の統一（いまはメダルの立体アイコンと、平面の UI が混ざっている）
- 1920×1080 以外の解像度・アスペクト比（ウルトラワイド・16:10）での確認

## 方針の変更（2026-11-18、3回目の指示）

上の AAA の型で作った版（暗い半透明の面）は、本人から「開発用プロトタイプや管理ツールのように見える」と言われた。
本人が示した参考は「ゆるふわで温かみのある3Dブロックの箱庭」。そのため、トーンを「生成りの紙と木の札」に変えた（`docs/ui-design.md`）。
上の調査のうち、次の型はそのまま使う（トーンに依存しない）:

- HUD は必要なときだけ出す
- 知らせは1か所に順に出す
- 操作の案内は文脈で出す（今回は、慣れたら消える形に強めた）
- 書体と色は1か所で管理する
- 1920×1080 を基準に拡大縮小する

暗い面・金の強調・英字のラベル・全画面を強く暗くするぼかしは、やめた。
