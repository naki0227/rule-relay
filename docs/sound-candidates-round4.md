# 音の候補 4回目（Stable Audio 3）: 足音とホットバーの音

- **生成した日: 2026-11-21**（00:33〜00:37、この Mac の時刻）
- footstep（足音）と ui_select（ホットバーを回す音）は、2回目に基準を満たした候補があったが、鳴り終わるまでが長すぎて採用できなかった。今回は「1回だけの短い打音」を条件にして作り直した。1イベントにつき seed を変えて5つ
- **ゲームの音（`assets/`）には触れていない。** 気に入ったものを ID（U01 など）で指定してもらえれば、rule-relay 側で取り込む
- **2026-11-21 に採用した**: footstep は本人の判断（2026-11-20）で U01・U03・U04・U05 の 4 つ全部を footstep_1〜4 として順番に鳴らす。ui_select は AI が余裕で U07 を選んだ。経緯と数値は `docs/sound-design.md` の 6回目

## 使ったもの

- 生成: Audio Studio MCP 1.2.0（この Mac でローカル生成）、モデル Stable Audio 3 medium（Stability AI、Hugging Face `stabilityai/stable-audio-3-optimized` の MLX 版 `dit_medium_f16`、リビジョン `30cb2644da54bfa63275d1bc7f1fa67fc718680f`）、steps 8。cfg は footstep が 1.0、ui_select が 4.0
- 置き場所: `art/audio/stable-audio/sfx4/<イベント名>_<n>.wav`（16bit モノラル 44.1kHz）。生成の設定は各ファイルの `.json`、測定値は `measurements.json`
- 加工と測定: `uv run --with numpy --with scipy --with soundfile python tools/sfx/stable_audio_candidates.py ~/AudioStudio --round 4`

## 基準（前回と同じもの＋今回の条件）

| 条件 | footstep | ui_select |
|---|---|---|
| −20dB まで落ちる時間（音の始まりから、2ms の RMS 包絡が最後に −20dB 以上だったところまで） | 120ms 以内 | 100ms 以内 |
| 打音の数（包絡が −20dB 未満に下がってから、また −12dB 以上に上がったら2打目と数える） | 1 | 1 |
| 主な周波数 | （音程の無い音として扱う） | 200〜600Hz |
| ファイルの長さ（−20dB の上限＋60ms） | 180ms 以内 | 160ms 以内 |
| そのほか | 前回までと同じ（こもり・シャー・甲高さ・小さなスピーカー・ピーク） | 同じ |

## 加工

1. モノラルにする
2. （ui_select だけ）**ピッチを −3 半音下げる**（テープを遅く回すのと同じで、長さも 1.19 倍になる）。頭をはっきりさせると主な周波数が 680〜700Hz になり、低くさせようとするとこもったため（下の「試し」を参照）。ゲームで音程を上げて鳴らすので、元を下げておいた。ピッチを変える前の主な周波数は U06〜U10 で 658〜981Hz（U09 以外は 658〜700Hz）
3. 150Hz 未満を切る・9kHz より上を弱める（前回までと同じ）。footstep はさらに 6000Hz のローパス（4次。「なし／6000／4500／3500Hz」のうち合格がいちばん多い値で、同じ数なら高い周波数）
4. 頭の無音を切る
5. **頭の1打だけを切り出す**: 2打目の手前（包絡がいちばん小さいところ）、包絡が −30dB を下回ったところ、上限（−20dB の上限の時間）のうち、いちばん早いところで切り、10ms のフェードで終える。一覧の「切る前」は、切り出す前の −20dB までの時間
6. ピークをそろえる（footstep −4dBFS、ui_select −9dBFS。前回までと同じ）

## 結果

10 個のうち、基準をすべて満たしたのは **8 個**。

| イベント | 合格した候補 | 外れたもの | 採用（2026-11-21） |
|---|---|---|---|
| footstep | 4/5（U01・U03・U04・U05） | U02（hits） | U01→footstep_1、U03→footstep_2、U04→footstep_3、U05→footstep_4 |
| ui_select | 4/5（U06・U07・U08・U10） | U09（centroid >4k main-range） | U07→ui_select |

- footstep の5つは、主な周波数が 149〜272Hz、長さが 38〜134ms でばらけている。順番に鳴らしても同じ音の繰り返しには聞こえにくいはず（AI は聴けないので、数値からの見立て）
- U02（footstep_2）は、かかとの後に草の小さな「くしゃ」が −12dB 以上で鳴り、打音2つと数えた
- U09（ui_select_4）は、2打目の手前で切ったため 24ms と短く、明るい成分が多い（主な周波数 818Hz）

## 試し（採用しなかった組）

試しの音はリポジトリに入れていない。プロンプトは下の表に残した。
- footstep の最初の試し（cfg 4、「soft rubber heel, warm low-mid thump」、negative に grass rustle・hiss など）: 短くはなった（−20dB まで 34〜51ms）が、4つともこもった（頭の明るさ 3〜22%）→ 2回目で合格した「cfg 1.0 で輪郭を残し、高域は加工のローパスで削る」に戻した
- ui_select の最初の試し（「small hard wooden game piece… low-mid woody tone」、negative に high-pitched click）: 4つ中3つがこもった（合格は1つ）
- ui_select の2回目の試し（3回目の ui_confirm で効いた「small hard wooden block struck with a hard wooden stick」）: 打つ瞬間ははっきりした（33〜59%）が、主な周波数が 677〜981Hz → **この組を採用し、加工でピッチを −3 半音下げた**
- ui_select の3回目の試し（「thick hollow hardwood block, like a low wooden temple block」）: 4つともこもり、主な周波数も 654〜999Hz で下がらなかった
- 鐘（3回目）と同じで、このモデルでは「低い木の音」と「はっきりした頭」が一緒に出にくい

## 聴いてほしい順番

1. footstep（U01〜U05）を、0.34 秒おきに順番に鳴らして
2. ui_select（U06〜U10）を、音程を上げながら続けて鳴らして

## 一覧

印の意味: decay＝−20dB まで落ちる時間が長い／hits＝打音が2つ以上／main-range＝主な周波数が 200〜600Hz の外／muffled＝頭 20ms が暗い／>4k・>9k＝シャー・シャリ／centroid＝全体が甲高い。LP＝追加のローパス

| ID | ファイル | seed | cfg | LP | ピッチ | 長さ | −20dB まで（切る前→後） | 打音 | 切り方 | 主な周波数 | 頭20msの明るさ | 重心 | >4k | >9k | 250Hz以上(A) | 印 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **U01** | `sfx4/footstep_1.wav` | 6100 | 1.0 | 6000Hz | — | 134ms | 113→111ms | 1 | −30dB で切った | 180Hz | 61% | 1179Hz | 7% | 0.0% | 98% | ok・**採用（footstep_1）** |
| **U02** | `sfx4/footstep_2.wav` | 6101 | 1.0 | 6000Hz | — | 132ms | 113→112ms | 2 | −30dB で切った | 272Hz | 29% | 2103Hz | 17% | 0.0% | 99% | ⚠ hits |
| **U03** | `sfx4/footstep_3.wav` | 6102 | 1.0 | 6000Hz | — | 114ms | 33→30ms | 1 | −30dB で切った | 149Hz | 62% | 1383Hz | 8% | 0.0% | 99% | ok・**採用（footstep_2）** |
| **U04** | `sfx4/footstep_4.wav` | 6103 | 1.0 | 6000Hz | — | 38ms | 112→24ms | 1 | −30dB で切った | 183Hz | 65% | 1518Hz | 10% | 0.0% | 97% | ok・**採用（footstep_3）** |
| **U05** | `sfx4/footstep_5.wav` | 6104 | 1.0 | 6000Hz | — | 102ms | 170→32ms | 1 | −30dB で切った | 245Hz | 70% | 1242Hz | 7% | 0.0% | 98% | ok・**採用（footstep_4）** |
| **U06** | `sfx4/ui_select_1.wav` | 6300 | 4.0 | — | -3 半音 | 59ms | 145→43ms | 1 | −30dB で切った | 597Hz | 56% | 1570Hz | 8% | 0.0% | 100% | ok |
| **U07** | `sfx4/ui_select_2.wav` | 6301 | 4.0 | — | -3 半音 | 48ms | 916→39ms | 1 | 2打目の手前で切った | 567Hz | 55% | 1327Hz | 1% | 0.0% | 100% | ok・**採用（ui_select）** |
| **U08** | `sfx4/ui_select_3.wav` | 6302 | 4.0 | — | -3 半音 | 56ms | 124→48ms | 1 | 2打目の手前で切った | 588Hz | 34% | 1173Hz | 2% | 0.0% | 100% | ok |
| **U09** | `sfx4/ui_select_4.wav` | 6303 | 4.0 | — | -3 半音 | 24ms | 57→17ms | 1 | 2打目の手前で切った | 818Hz | 64% | 2696Hz | 36% | 0.0% | 100% | ⚠ centroid >4k main-range |
| **U10** | `sfx4/ui_select_5.wav` | 6304 | 4.0 | — | -3 半音 | 87ms | 651→72ms | 1 | −30dB で切った | 552Hz | 56% | 1419Hz | 1% | 0.0% | 100% | ok |

## プロンプト（同じイベントの5つは seed だけが違う。サーバーが付けた先頭の `TrackType: SFX,` を含む）

| イベント | プロンプト | negative_prompt |
|---|---|---|
| footstep | `TrackType: SFX, a single footstep of a soft shoe on short grass over firm soil, one light heel step, a clear short pat with a tiny crunch of grass, single hit, very short, grass blades over packed soil, warm, gentle and natural, close-up, outdoors, dry.` | —（cfg 1.0 では効かない） |
| ui_select | `TrackType: SFX, a small hard wooden block struck once with a hard wooden stick, one single dry clack with a crisp click at the very start, very short, a single hit only, thick dense maple block, dry, articulate, warm woody tone, close-miked, dry, no reverb.` | `multiple hits, rattle, reverb tail, long ring, hiss, muffled, dull, thud, boomy, metallic` |

### 採用しなかった試しのプロンプト

| イベント | 試し | seed | cfg | プロンプト | negative_prompt |
|---|---|---|---|---|---|
| footstep | 1 | 6000〜6003 | 4.0 | `TrackType: SFX, a single footstep, the heel of a soft shoe landing on short grass over firm soil, one short soft heel tap with a clear start, stops almost immediately, a single hit only, soft rubber heel on packed earth, warm low-mid thump, tiny bit of grass, close-miked, outdoors, dry.` | `multiple steps, walking sequence, reverb tail, grass rustle, hiss, crunch, gravel, muffled, boomy, long decay` |
| ui_select | 1 | 6200〜6203 | 4.0 | `TrackType: SFX, a small hard wooden game piece set down once on a thick wooden board, one single short knock with a crisp clear click at the start, stops almost immediately, a single hit only, dense hardwood piece and board, low-mid woody tone, dry, articulate, close-miked, dry, no reverb.` | `multiple hits, rattle, rolling, reverb tail, long decay, hiss, muffled, dull, thud, metallic, high-pitched click` |
| ui_select | 3 | 6400〜6403 | 4.0 | `TrackType: SFX, a thick hollow hardwood block, like a low wooden temple block, struck once with a hard wooden stick, one single dry clack with a crisp click at the very start, very short, a single hit only, large dense hardwood, dry, articulate, lower woody pitch, close-miked, dry, no reverb.` | `multiple hits, rattle, reverb tail, long ring, hiss, muffled, dull, thud, boomy, metallic` |
