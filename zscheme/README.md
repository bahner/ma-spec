# zscheme — the client scripting layer

This directory specifies the embedded Scheme evaluator shared by the ma
clients:

- **zion** — the browser-based actor workstation
- **zscheme** — the standalone CLI REPL

zion and zscheme are *clients* — users of the [runtime](../runtime/README.md)
framework, not part of it. A runtime never evaluates Scheme; all expansion
happens client-side before messages are sent. Nothing in this directory is
required to implement `did:ma`, the [core](../core/README.md) conventions,
or a runtime.

## Documents

| Document | Defines |
|---|---|
| [zscheme-v1.md](zscheme-v1.md) | The zscheme dialect: expansion model, ma primitives (`#/` path atoms, actor RPC, `/ipfs`/`/ipns`/`/ipld` remote fetch), special forms incl. `guard`, builtins, send primitives, session environment, conformance. |

## Intended audience

- **Client implementors** adding scripting to a ma-compatible client:
  this spec is the conformance target.
- **End users** should *not* start here. User documentation lives in the
  [zscheme repository](https://github.com/bahner/zscheme):
  the **HANDBOOK** (tutorial) and **REFERENCE** (function-by-function
  manual), plus the standard library sources.
