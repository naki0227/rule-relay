# Mac 版の署名と公証（Developer ID）

Mac 版を、警告なしにダブルクリックで開けるようにする設定。
CI の `macos-notarize` ジョブが、main への push と手動実行のときに次を行う。

1. 書き出した .app を Developer ID で署名する。
2. Apple の公証に通す。
3. 公証の結果を .app に貼り付け、成果物 `rule-relay-macos-signed` として残す。

Secrets が登録されるまでは、このジョブは何もせずに通る（PR では動かさない）。

## 登録が必要な Secrets（rule-relay のリポジトリの Settings → Secrets and variables → Actions）

| 名前 | 中身 |
|---|---|
| `MACOS_DEVELOPER_ID_P12_BASE64` | **Developer ID Application** 証明書（秘密鍵つき）を .p12 で書き出し、base64 にしたもの |
| `MACOS_DEVELOPER_ID_PASSWORD` | その .p12 のパスワード |
| `ASC_KEY_ID` | App Store Connect の API キーの Key ID |
| `ASC_ISSUER_ID` | 同じく Issuer ID |
| `ASC_P8` | 同じく .p8 ファイルの中身（テキストのまま） |

## enludus-daily の Secrets がそのまま使えない理由（2026-11-20 確認）

**1. 置き場所の違い**
- enludus-daily の Secrets は組織（Organization）の Secrets で、その組織のリポジトリからしか使えない。
- rule-relay は個人アカウント（naki0227）のリポジトリなので届かない。
- Secrets の中身は GitHub の仕組み上、誰にも読み出せない（Claude も読めない）。リポジトリ間でコピーもできない。

**2. 証明書の種類の違い**
- enludus-daily の `SIGNING_CERT_P12_BASE64` は iOS 用（Apple Development / Apple Distribution）。
- App Store の外で Mac アプリを配るには、**Developer ID Application** という別の証明書が要る。
- Developer ID の証明書を作れるのは、Apple Developer のアカウント所有者（Account Holder）だけ。

**3. 公証用の API キーは同じものを使える**
- `ASC_KEY_ID`・`ASC_ISSUER_ID`・`ASC_P8` は同じキーを使い回せる。
- 手元にあるキーのファイルと ID を、rule-relay にも登録すればよい。

## 手順（本人）

1. Apple Developer → Certificates, Identifiers & Profiles → Certificates で「＋」を押し、**Developer ID Application** を作る。
2. Mac のキーチェーンアクセスで、その証明書を秘密鍵ごと .p12 で書き出す（パスワードを付ける）。
3. ターミナルで次を実行し、出てきた文字列を `MACOS_DEVELOPER_ID_P12_BASE64` に登録する。

   ```bash
   base64 -i 書き出した.p12 | pbcopy
   ```

4. .p12 のパスワードを `MACOS_DEVELOPER_ID_PASSWORD` に、API キーの3つを `ASC_*` に登録する。
5. GitHub の Actions で「CI」を手動実行する（Run workflow）。
   - `macos-notarize` が緑になれば、`rule-relay-macos-signed` が警告なしで開ける版。

## 別のやり方: enludus-daily の組織へ移す

rule-relay は公開リポジトリなので、enludus-daily の組織へ移せば、組織の Secrets（`ASC_*`）をそのまま共有できる。
- 共有するには、組織の Secrets の「Repository access」を「All repositories」にするか、選んだリポジトリに rule-relay を入れる。
- Developer ID の証明書は、移しても新しく作る必要がある（組織の Secrets に `MACOS_DEVELOPER_ID_*` として足せば、組織の他のリポジトリでも使える）。
- 移すと URL が `enludus-daily/rule-relay` に変わる（古い URL からは GitHub が転送する）。
