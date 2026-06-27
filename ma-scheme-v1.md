# ma-scheme-v1 — Embedded Scheme Evaluator

> **This specification has moved.**
> The canonical home for all ma-scheme documentation, the reference manual,
> the user handbook, and the standard library is the
> [ma-scheme repository](https://github.com/bahner/ma-scheme).
>
> This file is kept here for cross-reference only.

---

## Abstract

This document specifies the embedded Scheme evaluator in `zion` (the
browser-based `did:ma:` actor workstation). Any command line containing one
or more `(…)` spans is pre-processed by the evaluator before normal
dispatch. Each span is evaluated as a Scheme expression and its string
result is spliced back into the line. The final expanded line is then
dispatched through the normal ma command parser.

This gives `zion` composable macro-expansion, scripting, and direct access
to the ma actor network from within a standard Lisp syntax — essentially a
**distributed Scheme** where function calls can span iroh QUIC to any
`did:ma:` actor.

Companion documents:

- [ma-rpc-service-v1.md](ma-rpc-service-v1.md) — RPC content-type and term
  format
- [ma-messaging-format-v1.md](ma-messaging-format-v1.md) — message envelope

---

## Table of contents

1. [Overview](#1-overview)
2. [Expansion model](#2-expansion-model)
3. [ma primitives](#3-ma-primitives)
4. [Special forms](#4-special-forms)
5. [Builtin functions](#5-builtin-functions)
6. [Send primitives](#6-send-primitives)
7. [Reply tuple helpers](#7-reply-tuple-helpers)
8. [Session environment](#8-session-environment)
9. [Limitations](#9-limitations)

---

## 1. Overview

The evaluator is activated by the presence of `(` in a command line. It
operates as a **pre-processing step** before normal ma command parsing. The
normal `.` (dot-command) and `@` (actor message) syntaxes are unchanged; `(`
is a third namespace that can appear anywhere in the line.

```
Input:  (.my.aliases.sky)#room:enter ((.my.aliases.ms)#house:enter #room)

Step 1: Evaluate (.my.aliases.ms)       → "did:ma:abc"
Step 2: Evaluate (did:ma:abc#house:enter #room) → "ticket-x7k2"
Step 3: Evaluate (.my.aliases.sky)      → "did:ma:def"
Step 4: Splice   did:ma:def#room:enter ticket-x7k2
Step 5: Dispatch as normal actor message
```

---

## 2. Expansion model

### 2.1 Top-level scan

The expander scans the input string character-by-character for unescaped
`(` characters. Each `(` starts a span that extends to its balanced `)`.
String literals inside spans are handled correctly (inner parens inside
`"…"` are not counted toward nesting depth).

### 2.2 Evaluation order

Top-level spans are evaluated **left to right**. Nesting within a span is
handled by the Scheme evaluator itself (innermost sub-expressions first),
not by the text scanner.

### 2.3 Result splicing

Each span's result is converted to a string and substituted at the span's
position. Conversion rules:

| `SchemeVal` | Spliced as |
|---|---|
| `Str(s)` | `s` (verbatim) |
| `Int(n)` | decimal string |
| `Float(f)` | decimal string |
| `Bool(#t)` | `"#t"` |
| `Bool(#f)` | `"#f"` |
| `Nil` | `""` (empty) |
| `List(v)` | space-joined elements |
| `Lambda` | error — not spliceable |
| `Builtin` | error — not spliceable |

### 2.4 Bare DID handling

After expansion, lines starting with `did:ma:…` (no `@` prefix) are accepted
by the command parser as actor messages. This supports the common case where
`(.my.aliases.x)#frag:verb args` expands to a bare DID command.

---

## 3. ma primitives

The evaluator recognises two dispatch classes based on the **head character**
of a list form. No new function names are introduced — the existing ma
command grammar is reused directly.

### 3.1 Dot-path commands — head starts with `.`

```scheme
(.my.aliases.sky)           ; get leaf value → SchemeVal::Str
(.my.doc.notes.content)     ; get leaf value
(.my.config.k: "v")         ; set leaf       → SchemeVal::Nil
(.my.aliases.old:)          ; delete subtree → SchemeVal::Nil
```

Read operations return the stored string value. If the path names a subtree
(not a leaf), a `List` of child path strings is returned. Verb invocations
(`.path:verb`) are **not** supported inside Scheme expressions — use the
send primitives instead.

### 3.2 Actor messages — head starts with `@` or evaluates to `did:…`

```scheme
(@ma#house:enter #room)              ; atom target
(did:ma:abc#room:enter ticket-xyz)   ; DID string in function position
```

When the head of a list evaluates to a `did:…` string (e.g. the result of a
`.my.aliases` lookup), and the first argument starts with `#`, the argument
is appended to the DID without a space to form the full fragment address:

```scheme
; head = "did:ma:abc", first arg = "#house:enter"
; → target = "did:ma:abc#house:enter", verb = "enter"
(("did:ma:abc") "#house:enter" "#room")   ; equivalent
```

Actor-message forms send an RPC and await the reply.  On success they return
`SchemeVal::Str(content)`.  On failure or timeout they propagate as a
`SchemeErr::MaError`.  For explicit `:ok`/`:error` tuples use `rpc-send`
(§6).

---

## 4. Special forms

| Form | Semantics |
|---|---|
| `(define name val)` | Bind `name` in current environment |
| `(define (name p…) body…)` | Shorthand for lambda definition |
| `(lambda (p…) body…)` | Create closure |
| `(lambda (p… . rest) body…)` | Variadic lambda |
| `(let ((x e)…) body…)` | Parallel bindings |
| `(let* ((x e)…) body…)` | Sequential bindings |
| `(letrec ((x e)…) body…)` | Recursive bindings |
| `(if cond then)` | Conditional, no else branch returns nil |
| `(if cond then else)` | Conditional with else |
| `(cond (test expr…)… (else expr…))` | Multi-way conditional |
| `(begin expr…)` | Sequence; returns last |
| `(and expr…)` | Short-circuit conjunction |
| `(or expr…)` | Short-circuit disjunction |
| `(when cond body…)` | `(if cond (begin body…))` |
| `(unless cond body…)` | `(if (not cond) (begin body…))` |
| `(set! name val)` | Mutate existing binding |
| `(quote expr)` | Return unevaluated (atoms → strings) |
| `'expr` | Shorthand for `(quote expr)` |

---

## 5. Builtin functions

### 5.1 Arithmetic

| Function | Description |
|---|---|
| `(+ n…)` | Sum |
| `(- n…)` | Difference; unary negation |
| `(* n…)` | Product |
| `(/ a b)` | Division (integer or float) |
| `(mod a b)` | Modulo (integers) |
| `(remainder a b)` | Alias for `mod` |
| `(quotient a b)` | Integer quotient |
| `(abs n)` | Absolute value |
| `(max n…)` | Maximum |
| `(min n…)` | Minimum |
| `(floor n)` | Floor |
| `(ceiling n)` | Ceiling |
| `(round n)` | Round to nearest |
| `(truncate n)` | Truncate toward zero |

### 5.2 Comparison

| Function | Description |
|---|---|
| `(= a b…)` | Numeric or structural equality |
| `(< a b…)` | Less-than chain |
| `(> a b…)` | Greater-than chain |
| `(<= a b…)` | Less-than-or-equal chain |
| `(>= a b…)` | Greater-than-or-equal chain |
| `(equal? a b)` | Deep equality |
| `(eqv? a b)` | Alias for `equal?` |
| `(eq? a b)` | Alias for `equal?` |

### 5.3 Numeric predicates

| Function | Description |
|---|---|
| `(zero? n)` | True if n = 0 |
| `(positive? n)` | True if n > 0 |
| `(negative? n)` | True if n < 0 |
| `(even? n)` | True if n mod 2 = 0 |
| `(odd? n)` | True if n mod 2 ≠ 0 |

### 5.4 Lists

| Function | Description |
|---|---|
| `(list v…)` | Construct list |
| `(cons a b)` | Prepend; `(cons 1 '(2 3))` → `(1 2 3)` |
| `(car lst)` | First element |
| `(cdr lst)` | Rest (tail) |
| `(append lst…)` | Concatenate lists |
| `(reverse lst)` | Reverse list |
| `(length lst)` | Length |
| `(list-ref lst i)` | Element at index `i` |
| `(map f lst)` | Map function over list (async-safe) |
| `(filter f lst)` | Keep elements where `(f e)` is truthy |
| `(for-each f lst)` | Side-effect iteration |
| `(fold f init lst)` | Left fold |
| `(fold-left f init lst)` | Alias for `fold` |

### 5.5 Type predicates

| Function | Description |
|---|---|
| `(null? v)` | True for `()` and nil |
| `(pair? v)` | True for non-empty list |
| `(list? v)` | True for list or nil |
| `(string? v)` | True for strings |
| `(number? v)` | True for integers and floats |
| `(boolean? v)` | True for `#t` / `#f` |
| `(procedure? v)` | True for lambdas and builtins |

### 5.6 Strings

| Function | Description |
|---|---|
| `(string-append s…)` | Concatenate strings |
| `(string-length s)` | Length in bytes |
| `(substring s start end)` | Substring by byte index |
| `(string-contains hay needle)` | True if needle in hay |
| `(string-upcase s)` | Uppercase |
| `(string-downcase s)` | Lowercase |
| `(number->string n)` | Number to decimal string |
| `(string->number s)` | Parse number; `#f` on failure |

### 5.7 I/O and control

| Function | Description |
|---|---|
| `(display v…)` | Write to terminal (display form) |
| `(write v…)` | Write to terminal (write form, strings quoted) |
| `(newline)` | No-op (terminal already handles line separation) |
| `(error msg…)` | Raise a runtime error |
| `(assert v)` | Error if `v` is falsy |

---

## 6. Send primitives

These functions provide explicit control over ma message sending and return
structured reply tuples (see §7) rather than unwrapped strings. Use them
when you need error handling or want to send non-RPC messages.

### 6.1 `rpc-send`

```scheme
(rpc-send target verb arg…) → (:ok value) | (:error reason) | (:timeout)
```

Sends an RPC request and **blocks** (cooperatively via `async/await`) until
the reply arrives or the session timeout is reached.

- `target` — string: a fully-resolved DID-URL (`"did:ma:abc#house"`) or an
  alias in `@name` form.
- `verb` — string: the verb name (e.g. `":enter"`, `":ping"`). The leading
  `:` is optional — `send_rpc` adds it automatically if absent — but
  including it is idiomatic and consistent with the ma RPC term format.
- `arg…` — zero or more additional arguments, each converted to string.

Unlike the `@` sugar form, `rpc-send` returns the raw reply tuple and never
throws on a well-formed `:error` reply.

### 6.2 `msg-send`

```scheme
(msg-send target body) → (:ok msg-id) | (:error reason)
```

Sends a plain-text inbox message (`application/x-ma-message`). Returns
immediately after the message is dispatched — does **not** await a reply.
The `:ok` value is the dispatched message id.

### 6.3 `chat-send`

```scheme
(chat-send target text) → (:ok msg-id) | (:error reason)
```

Sends an ephemeral chat message (`application/x-ma-chat`). Otherwise
identical to `msg-send`.

### 6.4 `emote-send`

```scheme
(emote-send target text) → (:ok msg-id) | (:error reason)
```

Sends an emote message (`application/x-ma-emote`). Otherwise identical to
`msg-send`.

---

## 7. Reply tuple helpers

Reply tuples are plain Scheme lists whose first element is a keyword atom
string: `":ok"`, `":error"`, or `":timeout"`.

| Function | Description |
|---|---|
| `(ok? reply)` | True if `(car reply)` is `":ok"` |
| `(err? reply)` | True if `(car reply)` is `":error"` |
| `(ok-val reply)` | Second element of an `(:ok value)` tuple |
| `(err-msg reply)` | Second element of an `(:error reason)` tuple |

### Example — robust entry flow

```scheme
(define (enter-room house-alias room-alias)
  (let* ((house  (.my.aliases.house-alias))
         (room   (.my.aliases.room-alias))
         (result (rpc-send (string-append house "#house") ":enter" room)))
    (if (ok? result)
        (let ((ticket (ok-val result)))
          (rpc-send (string-append room "#room") ":enter" ticket))
        (error (err-msg result)))))
```

---

## 8. Session environment

Definitions made with `(define …)` persist in a **session environment** for
the duration of the login session. The environment is:

- **Initialised** at login (`init_session_env()`).
- **Reset** on logout (`reset_session_env()`).
- **Stored** in a thread-local variable in the WASM module's memory — not in
  IndexedDB. Definitions do not survive a page refresh.

To persist a value across sessions, write it to config:

```scheme
; persist
(.my.config.my-counter: (number->string (+ 1 (string->number (.my.config.my-counter)))))

; read back
(string->number (.my.config.my-counter))
```

### Scripting via `.my.doc`

Multi-line Scheme programs may be written in `.my.doc` documents and
evaluated with `:eval`:

```
.my.doc.boot:edit          ; open CodeMirror
.my.doc.boot:eval          ; execute line-by-line through Scheme evaluator
```

Documents can be published to IPFS (`:publish`) and shared with other actors
as a CID. This provides a rudimentary distributed package mechanism.

---

## 9. Limitations

### 9.1 No proper tail-call optimisation

The evaluator uses recursive `async fn` calls with `Box::pin`. Deep
tail-recursive loops (> ~1000 frames) may exhaust the WASM async stack. Use
`fold` or iterative patterns for large accumulations.

### 9.2 Scheme in sync batches

Scheme expansion is asynchronous (`spawn_local`). Inside a `.batch:sync`
block, a Scheme-containing line does **not** block the batch step counter —
the expanded line re-queues via `input_queue` and may arrive after the batch
has advanced. Avoid Scheme expressions inside sync batches until this is
resolved.

### 9.3 Verbs in dot-path expressions

`.path:verb` forms (e.g. `.my.doc.notes:eval`, `.my.inbox.5:reply`,
`.my.identity:publish`) are **not** dispatched from within Scheme expressions.
These are local terminal operations that interact directly with the UI —
opening the editor, triggering document evaluation, managing the inbox — and
require the full terminal dispatch context that the Scheme evaluator does not
have access to.

Only the three config operations are available from within Scheme: `Get`,
`Set`, and `Delete`. `Delete` is semantically a destructive write — it removes
the key from the config map entirely, as opposed to `Set` with an empty value
which keeps the key present.

Invoke dot-path verbs from the normal command line, outside of `(…)` spans.
