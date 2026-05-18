# lsp-mcp

Expose [lsp-mode](https://emacs-lsp.github.io/lsp-mode/) capabilities as
[MCP](https://modelcontextprotocol.io/) tools so LLM agents can use the same
LSP servers already configured in Emacs.

## Tools

| Tool                       | Description                                                          |
|----------------------------|----------------------------------------------------------------------|
| `lsp-find-definitions`     | Go-to-definition for symbol at file:line:column                      |
| `lsp-find-references`      | Find all references to symbol at file:line:column                    |
| `lsp-find-implementations` | Find concrete implementations of an interface/abstract symbol        |
| `lsp-find-type-definition` | Find the type definition of a symbol (e.g. struct a function returns)|
| `lsp-hover`                | Hover documentation for symbol at file:line:column                   |
| `lsp-get-diagnostics`      | Errors and warnings for a file                                       |
| `lsp-workspace-symbols`    | Search symbols across the workspace by query string                  |
| `lsp-document-symbols`     | All symbols defined in a file                                        |
| `lsp-call-hierarchy`       | Callers or callees of a function (incoming/outgoing)                 |
| `lsp-signature-help`       | Signature(s) at a call site with per-parameter docs                  |
| `lsp-inlay-hints`          | Inferred types and parameter names the server computed for a file    |
| `lsp-document-highlight`   | Read/write occurrences of a symbol within the same file              |
| `lsp-format-buffer`        | Format an entire file via LSP and save it                            |
| `lsp-format-region`        | Format a region of a file via LSP and save it                        |

All tools return JSON. Position tools return `{file, line, column}` arrays.
`line` is 1-indexed; `column` is 0-indexed (LSP convention).

## Requirements

- Emacs 29.1+
- [lsp-mode](https://github.com/emacs-lsp/lsp-mode) 9.0+
- [mcp-server-lib](https://github.com/laurynas-biveinis/mcp-server-lib) 0.1+

## Usage

```elisp
(require 'lsp-mcp)

;; Enable (registers all tools with mcp-server-lib)
(lsp-mcp-enable)

;; Disable (unregisters all tools)
(lsp-mcp-disable)
```

Call `lsp-mcp-enable` once at startup, e.g. in your `use-package` `:config`
block or `after-init-hook`.

### With use-package

```elisp
(use-package lsp-mcp
  :after (lsp-mode mcp-server-lib)
  :config (lsp-mcp-enable))
```

### With mcp-server-lib auto-start

If `mcp-server-lib` is configured to auto-start tools, add `lsp-mcp-enable`
to `mcp-server-lib-after-start-hook`.

## How it works

When a tool is called with a file path, `lsp-mcp` opens the file in a buffer
(if not already open), starts an LSP workspace if needed, waits up to 15 s for
initialization, then issues the LSP request synchronously and returns JSON.

Buffers opened this way remain open; Emacs reuses them on subsequent calls.

## Tool reference

### `lsp-find-definitions`

```
file   – absolute path to file
line   – line number (1-indexed)
column – column number (0-indexed)
```

Returns a JSON array of locations:

```json
[{"file": "/path/to/foo.py", "line": 42, "column": 4}]
```

### `lsp-find-references`

Same parameters as `lsp-find-definitions`. Includes the declaration site.

### `lsp-hover`

Same parameters as `lsp-find-definitions`. Returns a plain-text or Markdown
string with documentation for the symbol. Returns an empty string when the
server has no hover info.

### `lsp-get-diagnostics`

```
file – absolute path to file
```

Returns a JSON array of diagnostics:

```json
[
  {"severity": "error", "line": 10, "column": 2,
   "message": "undefined variable 'x'", "code": "E0001"}
]
```

Severity values: `"error"`, `"warning"`, `"information"`, `"hint"`.
`code` is omitted when the server does not supply one.

### `lsp-workspace-symbols`

```
query – search string (empty string returns all symbols)
```

Returns a JSON array:

```json
[{"name": "MyClass", "kind": "Class", "file": "/src/foo.py", "line": 5, "column": 0}]
```

### `lsp-document-symbols`

```
file – absolute path to file
```

Returns a JSON array. Nested symbols use dot-separated breadcrumb names:

```json
[
  {"name": "MyClass",        "kind": "Class",    "line": 1,  "column": 0},
  {"name": "MyClass.method", "kind": "Method",   "line": 5,  "column": 4,
   "detail": "(self, x: int) -> None"}
]
```

`detail` is omitted when the server does not supply one.

### `lsp-find-implementations`

Same parameters as `lsp-find-definitions`. Returns concrete implementations of
an interface method or abstract symbol — distinct from `lsp-find-definitions`,
which returns the declaration. Returns a JSON array of `{file, line, column}`.

### `lsp-find-type-definition`

Same parameters as `lsp-find-definitions`. Returns the definition of the *type*
of the symbol, not the function or value itself. For example, given
`let x = make_widget()`, this jumps to the `Widget` struct rather than to
`make_widget`. Returns a JSON array of `{file, line, column}`.

### `lsp-call-hierarchy`

```
file      – absolute path to file
line      – line number (1-indexed)
column    – column number (0-indexed)
direction – "incoming" (who calls this) or "outgoing" (what this calls)
```

Returns one level of the call hierarchy. Each entry is the caller/callee with
its location plus the call-site line numbers within that function:

```json
[
  {"name": "handle-request", "kind": "Function",
   "file": "/src/server.py", "line": 88, "column": 0,
   "call-sites": [92, 107]}
]
```

`call-sites` is omitted when the server does not return `fromRanges`.

### `lsp-signature-help`

Same parameters as `lsp-find-definitions`. Returns all overloaded signatures
at the call site with per-parameter documentation. The active signature
(the one matching the cursor position) has `"active": true`.

```json
[
  {
    "label": "foo(x: int, y: str) -> bool",
    "documentation": "Does the foo thing.",
    "parameters": [
      {"label": "x: int", "documentation": "The x value."},
      {"label": "y: str"}
    ],
    "active": true,
    "activeParameter": 0
  }
]
```

`documentation` on the signature and each parameter is omitted when not
supplied. `activeParameter` is omitted when the server does not return it.

### `lsp-inlay-hints`

```
file – absolute path to file
```

Returns inferred types and parameter names the language server computes but
the source does not spell out:

```json
[
  {"line": 5, "column": 12, "kind": "type",      "label": ": i32"},
  {"line": 9, "column": 4,  "kind": "parameter", "label": "value:"}
]
```

`kind` is `"type"`, `"parameter"`, or `"other"`.

### `lsp-document-highlight`

Same parameters as `lsp-find-definitions`. Returns all occurrences of the
symbol in the same file, annotated with whether each is a read, write, or
plain text reference:

```json
[
  {"kind": "read",  "line": 3, "column": 4, "end-line": 3, "end-column": 9},
  {"kind": "write", "line": 7, "column": 0, "end-line": 7, "end-column": 5}
]
```

`kind` is `"read"`, `"write"`, or `"text"` (when the server does not
distinguish).

### `lsp-format-buffer`

```
file – absolute path to file
```

Formats the entire file using the LSP server (`textDocument/formatting`) and
saves it. Returns `"formatted"`.

### `lsp-format-region`

```
file         – absolute path to file
start-line   – start line (1-indexed)
start-column – start column (0-indexed)
end-line     – end line (1-indexed)
end-column   – end column (0-indexed)
```

Formats the specified region using the LSP server
(`textDocument/rangeFormatting`) and saves the file. Returns `"formatted"`.

## Running tests

```bash
cd workstation/emacs/packages/lsp-mcp
emacs -batch -L . -l lsp-mcp-test.el -f ert-run-tests-batch-and-exit
```

Tests use `mcp-server-lib-ert` for the tool-registration tests; no live LSP
server is required.
