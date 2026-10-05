# eiwa.vim

[日本語版 README](README_ja.md)

A native Vim conversation UI intended for English-to-Japanese translation.
It is the Vim port of [eiwa.nvim](https://github.com/ue555/eiwa.nvim) and
shares the same Go agent and JSON Lines protocol. The Go agent connects to an
English-to-Japanese HTTP API. The default endpoint is
`http://127.0.0.1:8000/translate`. Start the API separately, then open `:Eiwa`
and submit English text. See [local Windows setup](README_ja.md) for this PC.

Configure the API with:

```vim
vim9script
import autoload 'eiwa.vim'
eiwa.Setup({
  api: {
    endpoint: 'http://127.0.0.1:8000/translate',
    timeout: 90, # seconds
    style: 'source', # source, polite, plain
    glossary: {'working tree': '作業ツリー'},
  },
})
```

Or from a legacy vimrc:

```vim
let g:eiwa_config = {'api': {'style': 'polite'}}
```

Windows users can build with `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1`.
The agent automatically resolves Windows `.exe` binaries. Restart Vim after
changing API settings. The API returns a complete translation, displayed after
generation finishes. Cancellation stops HTTP waiting, but API-side GPU work may
continue and temporarily cause HTTP 503 on the next request.

## Features

- Pure vim9script interface using `job_start()`, popup windows, and text properties
- Read-only conversation history and editable input area
- Float, right split, bottom split, and tab layouts
- Asynchronous JSON Lines communication with a pure-Go agent
- Streaming assistant events and request cancellation
- Session history retained when the window is closed
- Linux amd64, Linux arm64, Apple Silicon, and Windows amd64 builds

In the float layout the history is a popup window and the input area is a
bottom split, because Vim popup windows cannot be edited. The input is centered
at the same width as the history, with a border and an Input title. Colors follow
the Vim color scheme.

## Requirements

- Vim 9.0 or later with `+job`, `+channel`, `+popupwin`, and `+textprop`
- Go 1.21 or later when building the agent locally

## Install

### vpm

Add to `config/vpm/plugins.json`:

```json
{
  "url": "ue555/eiwa.vim",
  "build": "scripts/install-agent.sh"
}
```

### Manual

Clone into a `pack/*/start` directory and run `scripts/install-agent.sh`
(or `scripts/build.ps1` on Windows). Then run `:helptags ALL`.

## Configuration

```vim
vim9script
import autoload 'eiwa.vim'
eiwa.Setup({
  command: null,
  window: {
    position: 'float', # float, right, bottom, or tab
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

## Commands

| Command | Description |
|---|---|
| `:Eiwa` | Open or close the interface |
| `:EiwaSubmit` | Translate the entire input |
| `:EiwaClose` | Close the interface and retain its history |
| `:EiwaClear` | Clear the current history |
| `:EiwaCancel` | Cancel the active request |
| `:EiwaNewSession` | Cancel the active request and clear history |

Open the interface with `:Eiwa`. In the input area, press `Enter` to translate
the entire input, `Ctrl+J` to insert a newline, `Ctrl+C` to cancel, and `Esc` to
close. In Normal mode, `q` closes the interface. `PgUp` and `PgDn` scroll the
history. `eiwa#Submit('English text')` submits from Vim script.

Paste multiline text with `Ctrl+V` or `Shift+Insert`. These read
the clipboard directly and preserve blank lines and indentation. They avoid
changes to indentation from terminal paste. Queued Enter keys within a terminal
paste burst are treated as newlines; a separate Enter after the burst translates
the draft. For terminals that cannot distinguish paste from typing, use Ctrl+V
to read the clipboard directly. `Ctrl+J` and `Shift+Enter` insert newlines.
If your existing configuration sets `keymaps.submit` to `<F5>`, change it to `<CR>`.

## Build the agent

Install the matching release binary, with a local Go build as fallback:

```sh
scripts/install-agent.sh
```

Build for the current platform:

```sh
scripts/build.sh
```

Build all supported targets:

```sh
scripts/build.sh --all
```

Generated binaries:

```text
eiwa-agent-linux-amd64
eiwa-agent-linux-arm64
eiwa-agent-darwin-arm64
eiwa-agent-windows-amd64.exe
```

Tagged pushes trigger the release workflow and upload these binaries to
GitHub Releases.

## Tests

```sh
go test -timeout 20s ./...
vim -es -N -u tests/minimal.vim -S tests/run.vim
```

With the local API running:

```sh
vim -es -N -u tests/minimal.vim -S tests/live_api.vim
```

## Backend protocol

The Vim frontend and Go agent communicate through JSON Lines over standard
input and output.

```json
{"type":"submit","id":"request-1","content":"Hello"}
{"type":"cancel","id":"request-1"}
{"type":"shutdown"}
```

The HTTP backend posts `text`, `style`, and optional `glossary`, then emits
`started`, one `assistant_delta` containing the API's `translation`, and
`assistant_done`. Errors include the API's structured error message. A
placeholder backend remains available with `eiwa-agent serve --provider placeholder`
for UI development. CLI options include `--endpoint`, `--timeout`, `--style`, and
`--glossary`; defaults can also use `EIWA_API_URL`, `EIWA_API_TIMEOUT`,
`EIWA_API_STYLE`, and `EIWA_API_GLOSSARY` environment variables.

## License

MIT
