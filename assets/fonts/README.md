# フォント

| ファイル | 書体 | 用途 | ライセンス |
|---|---|---|---|
| `ZenMaruGothic-Medium.ttf` | Zen Maru Gothic Medium（The Zen Maru Gothic Project Authors） | 本文・ラベル・数字 | SIL Open Font License 1.1（`OFL-zenmarugothic.txt`） |
| `ZenMaruGothic-Bold.ttf` | Zen Maru Gothic Bold | 見出し・選択中の名前 | 同上 |

- 取得元: Google Fonts のリポジトリ（github.com/google/fonts の `ofl/zenmarugothic/`）、2026-11-18。
- 選んだ理由（`docs/ui-design.md`）: やわらかく温かい箱庭の世界観に合う丸ゴシックで、子ども向けに寄りすぎず、小さい字でも読みやすい。商用和文フォントは、ゲーム組み込みライセンスの費用と継続の危険が大きい（`docs/ui-research.md`）。
- 容量を抑えるため、fonttools の `pyftsubset` で JIS X 0208（第1・第2水準）、かな、ASCII、いくつかの記号（約7,000字）に絞った。OFL では改変版を同梱できる。この書体は予約フォント名を宣言していない。
- 絞った字に無い文字は、OS のフォントで表示する（`src/ui/ui_theme.gd`）。
- 提出用の企画書には、素材のライセンス一覧としてこの表を載せる。
