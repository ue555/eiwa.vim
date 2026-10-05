# eiwa.vim

> [!WARNING]
> **このプラグインは現在開発中です。** API、設定、動作は予告なく変更される
> 可能性があります。

英語から日本語への翻訳を目的とした、Vimネイティブの対話UIです。
[eiwa.nvim](https://github.com/ue555/eiwa.nvim) のVim移植版で、Goバックエンドと
JSON Linesプロトコルを共用しています。Goバックエンドから英日翻訳HTTP APIを
呼び出し、日本語を履歴に表示します。既定の接続先は
`http://127.0.0.1:8000/translate` です。

## このPCのローカル翻訳APIと連携する

Windows用バックエンドはビルド済みです。再ビルドする場合：

```powershell
Set-Location 'C:\Users\zeroz\dev\eiwa.vim'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
```

翻訳APIが停止している場合は、別途起動してください。APIが既に起動中なら不要です。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\zeroz\ai\eiwa\scripts\start_background_api.ps1
```

ローカルのプラグインを試す場合は、vimrcで runtimepath に追加します。

```vim
set runtimepath^=C:/Users/zeroz/dev/eiwa.vim
let g:eiwa_config = {
      \ 'api': {
      \   'endpoint': 'http://127.0.0.1:8000/translate',
      \   'timeout': 90,
      \   'style': 'source',
      \   'glossary': {'working tree': '作業ツリー'},
      \ },
      \ }
```

vim9scriptからは `eiwa.Setup({...})` を呼び出せます。

```vim
vim9script
import autoload 'eiwa.vim'
eiwa.Setup({api: {style: 'polite'}})
```

**`:Eiwa` で画面を開き、英文を貼り付けて Enter を押すと全文を翻訳します。**
手動で改行を入れる場合はCtrl+Jを押してください。
複数行の英文は、コピーして入力欄で **Ctrl+V** を押して
貼り付けてください。改行・空行・インデントを保持し、Enterを押すまで送信しません。
端末から連続して届く貼り付け入力も、途中のEnterを改行として扱います。
貼り付けと通常のキー入力を区別できない端末では、Ctrl+Vでクリップボードを
直接読む方法が確実です。
`call eiwa#Submit('English text')` からも送信できます。
既定設定だけでもローカルAPIに接続します。

APIは一括応答のため、生成完了後に全文を表示します。Ctrl+CでHTTP待機とUIの要求を中断できますが、
API側のGPU計算が完了するまでは次の要求が503になる場合があります。設定変更はVim再起動後に反映されます。
VimからはGoが通信するので、ブラウザー用のCORS設定は不要です。

## 機能

- vim9scriptのみで実装したUI（`job_start()`、ポップアップウィンドウ、テキストプロパティ）
- 上部の読み取り専用履歴と下部の入力欄
- フロート、右分割、下分割、新規タブの4表示形式
- JSON Linesを使用したGoバックエンドとの非同期通信
- ストリーミング表示とリクエストのキャンセル
- ウィンドウを閉じてもセッション履歴を保持
- Apple Silicon、Linux amd64、Linux arm64、Windows amd64向けビルド

フロート表示では、Vimのポップアップウィンドウが編集できないため、履歴を
ポップアップに、入力欄を画面下の分割ウィンドウに表示します。入力欄は履歴と
同じ幅に中央配置し、枠と「Input」の見出しを表示します。色はVimの配色に従います。

## 必要要件

- Vim 9.0以降（`+job`、`+channel`、`+popupwin`、`+textprop`）
- バックエンドをローカルビルドする場合はGo 1.21以降

## インストール

### vpm

`config/vpm/plugins.json` に追加します。

```json
{
  "url": "ue555/eiwa.vim",
  "build": "scripts/install-agent.sh"
}
```

### 手動

`pack/*/start` 以下にcloneし、`scripts/install-agent.sh`（Windowsは
`scripts/build.ps1`）を実行してから `:helptags ALL` を実行してください。

## 設定

```vim
vim9script
import autoload 'eiwa.vim'
eiwa.Setup({
  window: {
    position: 'float', # float, right, bottom, tab
    width: 0.8,
    height: 0.8,
    split_width: 0.4,
    split_height: 0.35,
    input_height: 3,
    border: 'rounded', # rounded, single, double, solid, none
  },
  history: {
    max_messages: 100,
  },
  keymaps: {
    submit: '<CR>',
    cancel: '<C-c>',
    close: 'q',
  },
})
```

## コマンド

| コマンド | 内容 |
|---|---|
| `:Eiwa` | UIを開く、または閉じる |
| `:EiwaSubmit` | 入力欄の全文を翻訳する |
| `:EiwaClose` | 履歴を残してUIを閉じる |
| `:EiwaClear` | 現在の履歴を削除する |
| `:EiwaCancel` | 実行中のリクエストを中断する |
| `:EiwaNewSession` | リクエストを中断して履歴を削除する |

入力欄では`Enter`で全文を送信、挿入モードの`Ctrl+J`で改行、`Ctrl+C`で中断、`Esc`で閉じます。
`Ctrl+V`または`Shift+Insert`で貼り付け、`Ctrl+J`または`Shift+Enter`でも改行できます。
以前の設定で`keymaps.submit`を`<F5>`にしている場合は`<CR>`に変更してください。
ノーマルモードでは`q`で閉じます。`PgUp`と`PgDn`で履歴を移動します。
分割・タブ表示の履歴ウィンドウでは`i`で入力欄に移動します。

## Goバックエンド

現在のOS・CPUに対応するバイナリをGitHub Releasesから取得します。
まだリリースがない場合は、ローカルのGoでビルドします。

```sh
scripts/install-agent.sh
```

現在の環境向けにビルドします。

```sh
scripts/build.sh
```

全対応環境向けにクロスビルドします。

```sh
scripts/build.sh --all
```

Goバックエンドは `POST /translate` に `text`、`style`、`glossary` を送り、
応答の `translation` を表示します。接続失敗、タイムアウト、APIのエラーを履歴に表示します。
CLIでは `eiwa-agent serve --endpoint URL --timeout 90s --style polite --glossary '{"term":"訳語"}'`
を利用できます。UI開発用の仮応答は `--provider placeholder` で明示的に選択できます。

検証：`go test -timeout 20s ./...`、
`vim -es -N -u tests/minimal.vim -S tests/run.vim`。
起動中のローカルAPIとの実通信検証は
`vim -es -N -u tests/minimal.vim -S tests/live_api.vim`。

## ライセンス

MIT
