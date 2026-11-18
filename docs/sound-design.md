# 効果音の設計（2026-11-18、仮）

本人の指示: 「毎回、高い音やそれっぽくない音を作りがち。効果音をしっかり調べて作ってほしい」。
そのため、調べた原則を数値の基準にし、合成した音を測って確かめる仕組みにした。

## 調べたこと（出典）

| 出典 | 取り入れたこと |
|---|---|
| [STK ModalBar（Perry Cook / Gary Scavone）](https://github.com/thestk/stk/blob/master/src/ModalBar.cpp)、[McGill の STK 解説](https://caml.music.mcgill.ca/~gary/307/week10/node21.html)、[Cook の modal 講義資料](https://ccrma.stanford.edu/workshops/dsp2008/prc/modal.pdf) | 叩いた木・棒の音は、指数減衰する数本の正弦波（モーダル合成）で作れる。Marimba・Wood1・Wood2 の振動比と減衰の値をそのまま使った |
| [SMC 2019: Perceptual Evaluation of Modal Synthesis for Impact-Based Sounds](https://www.smc2019.uma.es/articles/P1/P1_05_SMC2019_paper.pdf) | フィルタを使ったモーダル合成で、ゲームの衝突音を知覚上の劣化なく作れる |
| [sfxengine: Best Practices for Game UI Sounds](https://sfxengine.com/blog/best-practices-for-game-ui-sounds)、[bugnet: UI sound design](https://bugnet.io/blog/ui-sound-design-for-indie-games)、[bugnet: satisfying UI sounds](https://bugnet.io/blog/how-to-make-ui-sounds-satisfying) | クリックは 30〜150ms、成功は 150〜300ms、通知は 500ms 以内。ホバーはごく小さく。繰り返しで疲れないよう、音程と音量を少し揺らす |
| [violet recording: How to Design UI Sounds](https://violetrecording.com/how-to-design-ui-sounds/)、[Audiokinetic: loudness for games](https://blog.audiokinetic.com/loudness-processing-best-practice-chapter-3-scalable-loudness-processing-for-games/) | 120Hz 未満のこもりを切り、2〜5kHz の耳障りな山を抑える。UI はゲームの音より小さくする |
| [Orchestral Tools: cozy game music](https://www.orchestraltools.com/tips-for-cozy-game-music)、[r/GameAudio の相談](https://reddit.birdcat.cafe/r/GameAudio/comments/1j98wto/advice_on_sfx_and_ui_sounds) | ゆるい作品には、木のコツ・トクのような自然な楽器の音が合う。1つの素材の系統から全部を作ると統一される |
| [GDC: Civilization VII UI sound design](https://schedule.gdconf.com/session/civilization-vii-impactful-ui-sound-design-at-scale/915690) | 音に階層を作り、繰り返して聞いても嫌にならないことを重視する |

数値は出典によって幅がある（特に音量）。下の基準は、それらの共通部分をとった仮の値。

## 音の系統（`tools/sfx/build_sfx.py`）

- **木**: モーダル合成のマリンバ・木片。マレットの当たりは 3ms の雑音を 0.6〜3kHz に絞り、弱くして足す。
- **布・紙・草**: 色付きの雑音（ピンク・ブラウン）を帯域で絞り、ゆっくり立ち上げる。
- **音程**: ハ長調の五音（C D E G A）で、主に C4〜C5（262〜523Hz）を使う。C6 以上は使わない。
- **成功・失敗**: 成功は上がる2〜6音、失敗は下がる2音の木の音。ブザーは使わない。
- **仕上げ**:
  - 120Hz 未満を切る（重い衝撃音は 45Hz 未満だけ）
  - 4kHz より上をなだらかに弱める
  - 短いやわらかい残響を足す
  - 各音の終わりを 15ms で消す（「ぷつっ」を防ぐ）

| 出来事 | 音 | 長さ |
|---|---|---|
| ホバー | ごく小さな木の「コッ」（C5） | 50ms |
| ホットバーを選ぶ | マリンバの「トッ」。枠の番号で五音を上がる | 280ms |
| 決定 / 取り消し | 上がる2音（G4→C5）/ 下がる2音（E4→C4） | 0.4s |
| 開く / 閉じる | 布をめくる音＋低い「トン」 | 0.2〜0.3s |
| つまむ / 置く | 丸い「ポッ」/ 木の札を置く「コトッ」 | 0.1〜0.16s |
| できない | 下がる2回の木の音（G4→D4） | 0.26s |
| 能力を渡す / 範囲 / 回収 | 上がる風＋E4・G4 / 風＋C・E・G のばらした和音 / 下がる風＋G4→C4 | 0.6〜0.7s |
| 禁止 | こもった2回の木の音 | 0.22s |
| ブロックが跳ぶ / 着地 / 動く | 木の当たり＋ゆるく上がる丸い音 / 低い胴鳴り＋1オクターブ上の木の音 / 低くこする音 | 0.24〜0.42s |
| 自分の跳躍 / 着地 / 足音 | 服がなびく音 / 草に降りる音 / 草の足音3種類 | 0.09〜0.14s |
| 保存 / 到達 | C4 E4 G4 C5 の分散和音 / 五音で上がる旋律＋やわらかい和音 | 1.2s / 2.2s |

## 数値の基準（`tools/sfx/test_sfx.py`。CI の品質ゲートで毎回確かめる）

| 基準 | 値 | 何を防ぐか |
|---|---|---|
| 4kHz 以上のエネルギー | 6% 未満 | 高すぎる、キンキンする |
| 2〜5kHz のエネルギー | 15% 未満 | 耳障り |
| いちばん強い周波数 | 1100Hz 未満（C6 未満） | 高い音程の「ピコピコ」 |
| スペクトルの重心 | 1500Hz 未満 | 全体が明るすぎる |
| A 特性で重み付けした 250Hz 以上の割合 | 60% 以上（重い衝撃音は 40%） | ノートPCの小さなスピーカーで聞こえない |
| ピーク | -3dBFS 以下 | 割れ |
| 長さ | ホバー 80ms、UI 450ms、そのほか 800ms、保存・到達は例外 | 間延び |
| UI とゲームの音量 | UI の RMS < ゲームの RMS | UI がうるさい |
| 再現性 | 同じスクリプトで同じ音が出る | 原本がない音 |

`python3 tools/sfx/analyze.py` で表を、`python3 tools/sfx/spectrogram_sheet.py out.png` でスペクトログラムを出せる（`docs/images/sound/spectrograms.png`）。

## 鳴らし方（`src/audio/sound_bank.gd`）

- UI と世界の音は、別のバス（UI −2dB、World 0dB）に分ける。世界の音は位置から鳴らす。
- 鳴らすたびに音程を ±2〜8%、音量を ±0.5〜2dB 揺らす。足音は3種類から選ぶ。
- 35ms 以内の同じ音の連打は鳴らさない（ホバーの連続など）。同時に鳴らす数は UI 8・世界 12 まで。
- ホットバーの選択音は、枠の番号で五音を上がる（1→9）。

## 限界（正直に）

- **合成した AI（Claude）は音を聴けない。** 確認は測定値とスペクトログラムだけで、「それっぽさ」を人の耳では確かめていない。本人に聴いてもらい、直したい音を名前で指定してもらう。
- 実録音の素材（木を叩く・布・草）を使えば、さらに自然になる可能性が高い。CC0 の素材を使うか、Foley を録るかは、本人と相談する。
