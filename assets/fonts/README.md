# フォント

| ファイル | 書体 | 用途 | ライセンス |
|---|---|---|---|
| `NotoSansJP-VF.ttf` | Noto Sans JP（可変ウェイト 100〜900。Adobe / Google） | 画面の全文字（見出しは太さと字間で区別） | SIL Open Font License 1.1（`OFL-notosansjp.txt`） |

- 取得元: Google Fonts のリポジトリ（github.com/google/fonts の `ofl/notosansjp/`）、2026-11-18。
- 選んだ理由（`docs/ui-research.md`）:
  - AAA の画面に合う、癖のない骨太なゴシック（Source Han Sans 系）
  - 1ファイルで太さを変えられる
  - 商用フォントのゲーム組み込みライセンスは、2025年に費用が大きく上がった（フォントワークス LETS の組み込みオプション終了）
- 容量を抑えるため、fonttools の `pyftsubset` で JIS X 0208（第1・第2水準）、かな、ASCII、いくつかの記号（約7,000字）に絞った。可変ウェイトはそのまま残している。予約フォント名は 'Source' のみで、改変版（このファイル）はその名前を使っていない。
- 絞った字に無い文字は、OS のフォントで表示する（`src/ui/ui_theme.gd`）。
- 提出用の企画書には、素材のライセンス一覧としてこの表を載せる。
