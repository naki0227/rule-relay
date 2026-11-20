# ADR 0006: オンライン協力の通信方式（専用サーバーなし・ホスト権威・通信の差し替え）

- 状態: 採用（2026-11-20、本人と合意）
- 前提: Steam で配信する予定（本人、2026-11-20「多分」）。1〜4人の協力パズルで、ソロはオフラインで遊べる（Vault 提案書 19・20 節）。

## 決定

1. **専用サーバーは立てない。** プレイヤーの1人がホストになり、ホストの PC がゲームの状態（能力トークンの台帳・ブロック・ステージ）を確定する（ホスト権威）。参加者は「渡したい・回収したい」という依頼だけを送り、ホストが `RuleLedger` で検証して適用し、結果を全員へ配る。
2. **通信の下回りを差し替えられるようにする**（Godot の `MultiplayerPeer`）。
   - 開発・CI・**コンテスト提出版**: Steam なしの直接接続（`ENetMultiplayerPeer`）。提出版はソロ＋直接接続にする（本人合意）
   - **Steam 配信版**: Steam のロビー（招待・フレンドから参加）と Steam の P2P 通信（Valve の中継網。NAT 越えの設定不要、IP を相手に見せない）。GodotSteam の `SteamMultiplayerPeer` に差し替える
   - ゲームのコード（`src/net/` から上）は下回りを知らない
3. **ホスト移譲**: Steam のロビーはホストが抜けると自動で別の人を持ち主にするが、ゲームの状態は引き継がれない。ホストは状態を世代番号つきで全員へ配っておき、新ホストは手元の最新の状態から再開する（仕様の「一時停止→ホスト選出中…→再開、失敗ならチェックポイント」）。実装は P5。
4. **保存**: 各自の進行・報酬は各自の手元（Steam 版では Steam クラウド）に保存する。
5. **切断中の参加者への報酬は「部屋が残っている間に戻れば受け取れる」範囲で保証する**（本人合意、2026-11-20）。全員が抜けて部屋が消えた後に戻った人へ届けるには、報酬の記録だけを置く小さなサーバーが要る。必要になったら後で足す。

## 採らなかった案

- **専用サーバー**: 配信している間ずっと費用と運用がかかる。協力プレイで対戦のチート対策は要らない。ソロのオフラインとも合わない。利点（ホスト移譲が不要、切断者へ報酬を必ず届けられる）は 3 と 5 で補う。
- **最初から Steam だけ**: 審査は実行ファイルの ZIP で行うので、審査員の環境で Steam クライアント・App ID・フレンドを前提にできない。CI でも Steam は動かせない。
- **各自が状態を計算して突き合わせる（ロックステップ・ロールバック）**: 物理の結果を全員で完全に一致させる必要があり、Godot の物理（Jolt）では保証しにくい。

## 確かめていないこと・後で決めること

- GodotSteam の `SteamMultiplayerPeer` は GodotSteam が配る Godot の専用ビルドを前提にする形式がある。CI の公式 Godot 4.6.3 と合うビルドがあるかは、導入時に確かめる。
- Steamworks の登録料（1作品ごと）。配信を決めたときに本人が確認する。
- 切断の猶予時間、切断中のトークンの扱い（引き継ぎ仕様 7-1・7-5）。いまは「明示的な退出」だけを台帳の退出として扱い、通信の切断では台帳を動かさない。

## 参考

- Steamworks: Steam Networking https://partner.steamgames.com/doc/features/multiplayer/networking
- Steamworks: Steam Datagram Relay https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay
- Steamworks: Matchmaking & Lobbies https://partner.steamgames.com/documentation/matchmaking
- GodotSteam https://github.com/GodotSteam/GodotSteam
