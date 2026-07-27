# zscheme-v1 — Embedded Scheme Evaluator

**Status:** Candidate Recommendation — canonical specification.
**Version:** 1.0.0, 20 July 2026.

---

## Abstract

This document specifies **zscheme**, a Scheme dialect embedded in
ma-compatible actor clients (currently `zion`, the browser workstation, and
`zscheme`, the standalone CLI REPL).

zscheme provides composable macro-expansion, local scripting, and direct
access to the distributed ma actor network using standard Lisp syntax. Any
command line containing one or more S-expression spans delimited by balanced
parentheses is pre-processed by the evaluator before normal dispatch. Each
span is evaluated and its result is spliced back into the line as a string.
The expanded line is then dispatched through the normal ma command parser.

This gives clients composable, parameterised command construction —
essentially a **distributed Scheme** where individual function-call steps
may traverse iroh QUIC transport to remote `did:ma:` actors.

This specification is aimed at implementors of ma-compatible clients and
tooling. For user documentation see the HANDBOOK and REFERENCE in the
[zscheme repository](https://github.com/bahner/ma-scheme).

Companion documents:

- [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md) — RPC message-type
  and term format
- [ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md) — message
  envelope
- [ma-crud-service-v1.md](../runtime/ma-crud-service-v1.md) — local/remote
  path grammar

Design goals:

- Allow composable, parameterised command construction without a separate
  scripting layer.
- Provide direct access to the ma actor network from within expressions.
- Remain a strict subset of standard Scheme (R7RS Small) wherever the two
  overlap, so that existing Scheme knowledge transfers.
- Keep the evaluator minimal. Functions that can be expressed in zscheme
  itself SHOULD be distributed as a standard library (see
  [Section 12](#12-standard-library)) rather than built into the evaluator.

---

## Table of contents

1. [Conventions and definitions](#1-conventions-and-definitions)
2. [Expansion model](#2-expansion-model)
3. [Lexical conventions](#3-lexical-conventions)
4. [Types](#4-types)
5. [Special forms](#5-special-forms)
6. [ma primitives](#6-ma-primitives)
7. [Core builtins](#7-core-builtins)
8. [Send primitives](#8-send-primitives)
9. [Reply tuple helpers](#9-reply-tuple-helpers)
10. [Session environment](#10-session-environment)
11. [Error handling — guard](#11-error-handling--guard)
12. [Standard library](#12-standard-library)
13. [Conformance](#13-conformance)
14. [Security considerations](#14-security-considerations)
15. [Implementation limitations](#15-implementation-limitations)
16. [References](#16-references)

---

## 1. Conventions and definitions

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in BCP 14
[RFC2119] when, and only when, they appear in all capitals.

**evaluator** — The zscheme interpreter embedded in the ma client.

**span** — A balanced parenthesised substring of a command line, including
its outermost parentheses.

**session environment** — The top-level Scheme environment associated with
a single authenticated login session.

**dot-path** — a legacy term for the local-path config-tree key grammar, of
the form `/segment[/segment…]` (root `/my` or `/ctx`). Within zscheme
expressions a local path is written with a leading `#/` (e.g. `#/my/aliases`)
to avoid colliding with the `/` division builtin ([Section 3](#3-lexical-conventions)).

**actor target** — A `did:ma:` DID-URL, optionally with a fragment, used to
address an ma actor.

---

## 2. Expansion model

### 2.1 Scan

Before a command line is submitted to the normal ma command parser, the
client MUST scan the line character-by-character for unescaped `(`
characters. Each such character begins a span.

The span ends at the matching `)`, determined by counting nesting depth.
String literals within the line (delimited by `"…"`) MUST be excluded from
depth counting; parentheses inside string literals MUST NOT affect the
nesting depth.

The `\` character inside a string literal MUST be treated as an escape
prefix; the character immediately following it MUST NOT be used for nesting
depth purposes.

If a `(` is found without a matching `)`, the implementation MUST report a
parse error and MUST NOT dispatch the line.

Lines that contain no `(` outside of string literals MUST be passed
directly to the normal command parser without evaluation.

### 2.2 Evaluation order

Top-level spans within a single command line MUST be evaluated left to
right. The evaluation of each span MUST complete before the evaluation of
any span to its right begins.

Nesting within a span is resolved by the standard Scheme evaluation rules
(innermost sub-expressions first); the text scanner is not involved.

```text
Input:  (#/my/aliases/sky)#room:look ((string-append "north" " gate"))

Step 1: Evaluate (#/my/aliases/sky)               → "did:ma:def"
Step 2: Evaluate (string-append "north" " gate") → "north gate"
Step 3: Splice   did:ma:def#room:look north gate
Step 5: Dispatch as normal actor message
```

### 2.3 Result splicing

After each span is evaluated, its result MUST be converted to a string and
substituted at the span's position in the line:

| Value | Spliced as |
|---|---|
| String | verbatim string contents |
| Integer | decimal representation |
| Float | decimal representation |
| `#t` | the literal string `#t` |
| `#f` | the literal string `#f` |
| Nil / `()` | empty string |
| List | elements joined with a single space |
| Lambda | error — MUST NOT be spliced |
| Builtin | error — MUST NOT be spliced |

If a span evaluates to a Lambda or Builtin value the implementation MUST
report an error and MUST NOT dispatch the line.

### 2.4 Bare DID handling

After expansion, if the resulting line begins with `did:ma:` (without a
leading `@`), the command parser MUST treat it as an actor message,
equivalent to the same line with a leading `@`. This supports the common
case where `(#/my/aliases/x)#frag:verb args` expands to a bare DID command.

---

## 3. Lexical conventions

The zscheme lexer MUST recognise the following token classes:

- `(` and `)` — parentheses.
- String literals — delimited by `"`. Escape sequences that MUST be
  recognised: `\\`, `\"`, `\n`, `\t`, `\r`.
- Line comments — initiated by `;` and extending to end of line. Comments
  MUST be discarded before parsing.
- Quote shorthand — `'expr` MUST be transformed to `(quote expr)` during
  lexing.
- Path atoms — tokens beginning with `#/`, followed immediately by one or
  more `/`-separated segments (e.g. `#/my/aliases/sky`, `#/ipfs/bafy…`,
  `#/ipns/k51…`). The `#/` sigil MUST NOT be confused with the `/` division
  builtin ([Section 7.1](#71-arithmetic)) — an atom consisting of exactly
  the single character `/` remains the division builtin; only tokens
  beginning with the two-character sequence `#/` are path atoms. See
  [Section 6.1](#61-path-atoms--head-starts-with-) for dispatch semantics.
- Atoms — any sequence of non-whitespace, non-parenthesis, non-semicolon
  characters that does not match the above.

Atoms beginning with `#` that are not `#t`, `#f`, or a path atom (`#/…`)
MUST be treated as string values (they represent ma fragment identifiers
such as `#room` or `#room:look`).

---

## 4. Types

Implementations MUST support the following value types:

| Type | Definition |
|---|---|
| Integer | 64-bit signed integer |
| Float | 64-bit IEEE 754 double-precision floating point |
| String | UTF-8 encoded byte sequence |
| Boolean | `#t` (true) or `#f` (false) |
| Nil | the empty list, also written `()` or `nil`; falsy |
| List | ordered sequence of values |
| Map | string-keyed associative map with values of any serialisable zscheme type |
| Lambda | closure capturing parameter list, body, and lexical environment |
| MaPath | atom beginning with `#/my` or `#/ctx`; dispatched to the local config layer in function position |
| MaActor | atom beginning with `@`; dispatched via RPC in function position |

**Truthiness:** only `#f` and Nil are falsy. All other values MUST be
treated as truthy.

---

## 5. Special forms

### 5.1 define

```scheme
(define <name> <expr>)
(define (<name> <param>…) <body>…)
(define (<name> <param>… . <rest>) <body>…)
```

Binds `<name>` in the current environment. The variadic form with
`. <rest>` MUST collect excess arguments into a list.

### 5.2 lambda / ʎ

```scheme
(lambda (<param>…) <body>…)
(lambda (<param>… . <rest>) <body>…)
```

Creates a closure. The character `ʎ` (U+028E) MUST be accepted as an alias
for the keyword `lambda`.

### 5.3 let, let*, letrec

```scheme
(let    ((<var> <init>)…) <body>…)
(let*   ((<var> <init>)…) <body>…)
(letrec ((<var> <init>)…) <body>…)
```

`let` evaluates all `<init>` in the enclosing environment before binding.
`let*` evaluates and binds each in sequence. `letrec` pre-binds all names
before evaluating any `<init>`.

### 5.4 if, cond, when, unless

```scheme
(if <cond> <then>)
(if <cond> <then> <else>)
(cond (<test> <expr>…)… (else <expr>…))
(when   <cond> <body>…)
(unless <cond> <body>…)
```

`when` MUST be equivalent to `(if <cond> (begin <body>…))`.
`unless` MUST be equivalent to `(if (not <cond>) (begin <body>…))`.

### 5.5 begin

```scheme
(begin <expr>…)
```

Evaluates each expression in order. MUST return the last value.

### 5.6 and, or

```scheme
(and <expr>…)   ; last truthy value, or #f on first falsy
(or  <expr>…)   ; first truthy value, or #f if none
```

Both forms MUST short-circuit.

### 5.7 set!

```scheme
(set! <name> <value>)
```

Mutates an existing binding in the lexical scope chain. MUST signal an
error if `<name>` is not bound.

### 5.8 quote

```scheme
(quote <expr>)   ; or '<expr>
```

Returns `<expr>` unevaluated. Symbol atoms MUST be returned as strings.

### 5.9 guard

See [Section 11](#11-error-handling--guard).

---

## 6. ma primitives

The evaluator recognises dispatch classes based on the **head** of a list
form. No new function names are introduced — the existing ma command
grammar is reused directly.

### 6.1 Path atoms — head starts with `#/`

A list form whose head atom begins with `#/` MUST be dispatched based on
its first path segment:

- `#/my/…` or `#/ctx/…` — local config layer (read-write).
- `#/ipfs/…`, `#/ipns/…`, or `#/ipld/…` — remote content fetch (read-only).
  `/ipld/` MAY be implemented identically to `/ipfs/` (aliased); a
  conforming implementation is NOT REQUIRED to provide structured DAG-CBOR
  traversal for `/ipld/` distinct from a raw `/ipfs/` fetch.

```scheme
(#/my/aliases/sky)           ; get leaf value  → String
(#/my/config/k: "v")         ; set leaf        → Nil
(#/my/aliases/old:)          ; delete subtree  → Nil

(#/ipfs/bafyxxx)             ; fetch CID content → String
(#/ipns/k51xxx)              ; resolve + fetch IPNS content → String
```

**Local config (`#/my`, `#/ctx`):**

- **Get:** `(#/path)` returns the leaf value as a String. If the path
  addresses a subtree, a List of child path strings MUST be returned.
  MUST signal an error if neither exists.
- **Set:** `(#/path: "value")` updates config; returns Nil.
- **Delete:** `(#/path:)` deletes the subtree; returns Nil. Delete is a
  destructive write — it removes the key entirely, as opposed to Set with
  an empty value, which keeps the key present.

**Remote fetch (`#/ipfs`, `#/ipns`, `#/ipld`):**

- With no arguments, `(#/ipfs/bafyxxx)` MUST fetch the referenced content
  and return it as a String. `#/ipns/…` MUST be resolved to its current
  target before fetching.
- These roots are read-only. An implementation MUST signal an error if a
  Set, Delete, or any argument is supplied against an `#/ipfs`, `#/ipns`,
  or `#/ipld` path.
- To load Scheme definitions from fetched content, pass the path atom or an
  equivalent string to `include` ([Section 7.8](#78-loading-scripts)),
  e.g. `(include #/ipfs/bafyxxx)` or `(include "/ipfs/bafyxxx")`.

Path verb dispatch (e.g. `#/path!edit`) is NOT supported within Scheme
expressions. Implementations MUST signal an error if encountered. See
[Section 15.3](#153-verbs-in-path-expressions) for rationale.

### 6.2 Actor messages — head starts with `@` or evaluates to `did:…`

A list form whose head evaluates to a MaActor value or to a String
beginning with `did:ma:` MUST be dispatched as an ma actor message.

```scheme
(@sky#room:look)                      ; atom target, auto-unwraps reply
(did:ma:abc#room:enter ticket-xyz)    ; DID string in function position
```

The implementation MUST:

1. Resolve alias references in the target.
2. If the head is a `did:ma:…` String and the first argument begins with
   `#`, append the argument to the DID without a space to form the full
   DID-URL.
3. Send the RPC via `/ma/rpc/0.0.1`
   ([ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md)).
4. Register a one-shot reply channel keyed by the message id.
5. Suspend the evaluator until the reply arrives or timeout.
6. On `:ok` reply, MUST return the payload as a String.
7. On `:error` reply or timeout, MUST propagate as an evaluator error.

Argument values sent over RPC MUST be encoded recursively as CBOR values:
integers, floats, strings, booleans, nil/null, arrays for lists, and maps for
Map values. Map keys MUST be CBOR text strings; implementations MUST NOT
encode non-string keys in zscheme maps.

Accepted target forms:

- `@alias`
- `@alias#fragment`
- `@alias#fragment:verb` (verb encoded in the DID-URL fragment)
- `did:ma:<ipns>`
- `did:ma:<ipns>#fragment`

The `@` actor syntax auto-unwraps replies: success returns a String,
failure raises an evaluator error. Use `rpc-send`
([Section 8.1](#81-rpc-send)) for explicit tuple handling.

```scheme
(define sky (#/my/aliases/sky))       ; → "did:ma:abc"
(sky "#room:enter" ticket)            ; → sends to did:ma:abc#room:enter
```

### 6.3 Focus state

```scheme
(use <target>)   ; or (use "")
```

Sets the client focus context to `<target>`, writes the resolved DID-URL to
`/my/ctx/runtime` and (if a fragment is present) to `/my/ctx/room`, and
sets `/my/ctx/use` to `"true"`.

With an empty string, toggles focus: deactivates if active, or reactivates
from stored `/my/ctx/runtime` if inactive.

---

## 7. Core builtins

### 7.1 Arithmetic

| Function | Description |
|---|---|
| `(+ n…)` | Sum; no-argument form MUST return 0 |
| `(- n…)` | Unary negation or subtraction |
| `(* n…)` | Product; no-argument form MUST return 1 |
| `(/ a b)` | Division; Integer inputs MUST produce Integer output |
| `(mod a b)` | Integer modulo; MUST error if b is zero |
| `(floor n)` | Floor; Integer input MUST return Integer |
| `(ceiling n)` | Ceiling; Integer input MUST return Integer |
| `(round n)` | Round to nearest |
| `(truncate n)` | Truncate toward zero |

### 7.2 Comparison

| Function | Description |
|---|---|
| `(= a b…)` | Equality chain; MUST support mixed Int/Float |
| `(< a b…)` | Less-than chain |
| `(> a b…)` | Greater-than chain |
| `(<= a b…)` | Less-than-or-equal chain |
| `(>= a b…)` | Greater-than-or-equal chain |
| `(equal? a b)` | Deep structural equality |

Chain comparisons MUST return `#t` iff the predicate holds for every
consecutive pair.

### 7.3 Boolean

| Function | Description |
|---|---|
| `(not v)` | `#t` if v is falsy, `#f` otherwise |

### 7.4 Lists

| Function | Description |
|---|---|
| `(list v…)` | Construct a proper list |
| `(cons a b)` | Prepend a to b |
| `(car lst)` | First element; MUST error on Nil |
| `(cdr lst)` | Tail; singleton MUST return Nil |
| `(null? v)` | `#t` for Nil and the empty list |
| `(pair? v)` | `#t` for any non-empty list |

### 7.5 Type predicates

| Function | Description |
|---|---|
| `(string? v)` | True if v is a String |
| `(number? v)` | True if v is an Integer or Float |
| `(boolean? v)` | True if v is `#t` / `#f` |
| `(procedure? v)` | True if v is a Lambda or Builtin |

### 7.6 String primitives

These operate on UTF-8 byte sequences.

| Function | Description |
|---|---|
| `(string-append s…)` | Concatenate |
| `(string-length s)` | Length in bytes |
| `(substring s start end)` | Byte-indexed substring |
| `(string-index hay needle)` | First occurrence index as Integer, or `#f` if not found |
| `(string-contains hay needle)` | `#t` if needle occurs in hay |
| `(char-upcase ch)` | Uppercase one-character string |
| `(char-downcase ch)` | Lowercase one-character string |
| `(string-upcase s)` | Uppercase (locale-independent) |
| `(string-downcase s)` | Lowercase (locale-independent) |
| `(number->string n)` | Decimal string representation |
| `(string->number s)` | Parse; `#f` on failure |

This version of zscheme has no separate character value type. The `ch`
argument to `char-upcase` and `char-downcase` is a string containing exactly
one Unicode scalar value; implementations MUST signal an error for any other
shape. Unicode case conversion can expand a character to more than one scalar
value; the result is still returned as a string.

The functions `string-split`, `string-join`, `string-lines`,
`string-unlines`, and `string-trim` MAY be provided as builtins or via the
standard library ([Section 12](#12-standard-library)).

### 7.7 I/O and control

| Function | Description |
|---|---|
| `(display v…)` | Write display representation to terminal |
| `(write v…)` | Write write/quoted representation to terminal |
| `(newline)` | No-op; provided for R7RS compatibility |
| `(error msg…)` | Raise a runtime error |
| `(assert v)` | Equivalent to `(if (not v) (error "assertion failed"))` |

### 7.8 Loading scripts

```scheme
(include path)
```

If `path` is an `/ipfs/<cid>`, `/ipns/<key>`, or `did:ma:` link
(see [Section 6.1](#61-path-atoms--head-starts-with-)), fetches and
resolves it remotely. Otherwise reads `{path}/content` from local config
and evaluates every top-level form in the current session environment,
returning the last value. MUST signal an error if the content cannot be
resolved.

Fetch and parse failures propagate as evaluator errors; wrap with `guard`
([Section 11](#11-error-handling--guard)) to handle them.

Security: fetched content is arbitrary code. See
[Section 14.1](#141-arbitrary-code-execution).

---

## 8. Send primitives

Unlike the `@`-syntax actor form
([Section 6.2](#62-actor-messages--head-starts-with--or-evaluates-to-did)),
these primitives return structured reply tuples and MUST NOT raise on
well-formed `:error` replies.

### 8.1 rpc-send

```scheme
(rpc-send target verb arg…) → (:ok value) | (:error reason) | (:timeout)
```

Sends a `/ma/rpc/0.0.1` request and blocks until reply or timeout.

- `target` — String accepted by Section 6.2 alias resolution.
- `verb` — String. If not beginning with `:`, the implementation MUST
  prepend `:`.
- `arg…` — zero or more additional arguments, converted to string.

MUST return `(:ok value)`, `(:error reason)`, or `(:timeout)`.
MUST NOT raise.

### 8.2 msg-send

```scheme
(msg-send target body) → (:ok msg-id) | (:error reason)
```

Sends a plain-text inbox message (`application/vnd.ma.message`) and returns
immediately without awaiting a reply. The `:ok` value is the dispatched
message id.

### 8.3 chat-send

```scheme
(chat-send target text) → (:ok msg-id) | (:error reason)
```

As `msg-send` but uses the `application/vnd.ma.chat` message type
([ma-chat-messages-v1.md](../core/ma-chat-messages-v1.md)).

### 8.4 emote-send

```scheme
(emote-send target text) → (:ok msg-id) | (:error reason)
```

As `msg-send` but uses the `application/vnd.ma.emote` message type
([ma-emote-messages-v1.md](../core/ma-emote-messages-v1.md)).

---

## 9. Reply tuple helpers

Reply tuples are proper lists whose first element is one of the strings
`":ok"`, `":error"`, or `":timeout"`.

| Function | Description |
|---|---|
| `(ok? reply)` | `#t` iff `(car reply)` equals `":ok"` |
| `(err? reply)` | `#t` iff `(car reply)` equals `":error"` |
| `(ok-val reply)` | Second element of `(:ok value)`; MUST error if `(ok? reply)` is `#f` |
| `(err-msg reply)` | Second element of `(:error reason)`; MUST error if `(err? reply)` is `#f` |

### Example — explicit reply handling

```scheme
(define (look-room room-alias)
  (let* ((room   (#/my/aliases/room-alias))
         (result (rpc-send (string-append room "#room") ":look")))
    (if (ok? result)
        (ok-val result)
        (error (err-msg result)))))
```

---

## 10. Session environment

Implementations MUST maintain a session environment that persists for the
duration of an authenticated login session.

- The session environment MUST be initialised to empty at session start and
  MUST be cleared at session end.
- Bindings made with `define` MUST be visible to all subsequent evaluations
  within the same session.
- Implementations are NOT REQUIRED to persist the session environment
  across page reloads or process restarts. Callers SHOULD use the path
  Set form ([Section 6.1](#61-path-atoms--head-starts-with-)) to
  persist values across sessions:

```scheme
; persist
(#/my/config/my-counter: (number->string (+ 1 (string->number (#/my/config/my-counter)))))

; read back
(string->number (#/my/config/my-counter))
```

### Scripting via documents

Multi-line Scheme programs MAY be written in client documents and evaluated
with the client's document-evaluation verb (`!eval`). Lines MUST be
executed one at a time: each Scheme expression MUST be fully expanded
(including any remote fetches) before the next line starts, so that
defines loaded via `include` are available to subsequent lines.

Documents can be published to IPFS and shared with other actors as a CID.
This provides a rudimentary distributed package mechanism.

---

## 11. Error handling — guard

zscheme provides R7RS-small structured error handling (§6.11) via the
`guard` special form. The caught variable is bound to the error message
**string**.

```scheme
(guard (<var>
        (<test> <expr>…)
        …)
  <body>…)
```

Semantics:

- `<body>` is evaluated. If it succeeds, its value MUST be returned; the
  clauses are never consulted.
- On error, `<var>` MUST be bound to the error message string in a fresh
  environment extending the enclosing one, and clauses MUST be tested in
  order. The expression sequence of the first truthy test MUST be evaluated
  and its last value returned. If the matching clause has no expressions,
  the test value itself MUST be returned.
- `(#t <expr>…)` is the catch-all clause (`else` equivalent).
- If no clause matches, the error MUST be re-raised.

```scheme
; Swallow a missing-content error, fall back to nil:
(guard (e (#t nil))
  (#/ipfs/bafyxxx))

; Log and continue:
(guard (e (#t (display (string-append "load failed: " e))))
  (#/ipfs/bafyxxx))

; Re-raise unexpected errors:
(guard (e
        ((string-contains e "not found") nil)
        (#t (error e)))
  (#/ipfs/bafyxxx))
```

`guard` is the RECOMMENDED mechanism around remote fetches, `include`, and
RPC calls that may time out.

When a document evaluated with `:eval` encounters an unguarded error,
execution MUST halt at that line. Use `guard` around any form that may fail
so subsequent lines can run.

---

## 12. Standard library

The zscheme standard library (`stdlib.ma`) provides implementations of
common functions in pure zscheme using only
[Section 7](#7-core-builtins) primitives.

The library is distributed as an IPFS-addressed document. The canonical CID
is published in the `stdlib.cid` file in the
[zscheme repository](https://github.com/bahner/ma-scheme).

Load with:

```scheme
(include "/my/doc/stdlib/ma")
```

Or from the terminal:

```text
/my/doc/stdlib/ma!fetch /ipfs/<cid>
/my/doc/stdlib/ma!eval
```

Functions provided by the standard library that are NOT required as
built-in primitives:

- **List:** `length`, `list-ref`, `list?`, `append`, `reverse`, `map`,
  `filter`, `for-each`, `fold`, `fold-left`, `cadr`, `caddr`, `cadddr`,
  `any`, `every`.
- **Map:** `map?`, `make-map`, `map-ref`, `map-set`, `map-delete`,
  `map-has-key?`, `map-keys`, `map-values`, `map->alist`, `alist->map`.
- **Numeric:** `abs`, `max`, `min`, `zero?`, `positive?`, `negative?`,
  `even?`, `odd?`, `quotient`, `remainder`.
- **String:** `string-split`, `string-join`, `string-lines`,
  `string-unlines`, `string-trim`.
- **Aliases:** `eq?`, `eqv?` (both alias `equal?`).

Implementations MAY provide any of these as builtins.

---

## 13. Conformance

A conforming implementation MUST implement:

- All special forms in [Section 5](#5-special-forms), including `guard`
  ([Section 11](#11-error-handling--guard)).
- All ma primitives in [Section 6](#6-ma-primitives).
- All core builtins in [Section 7](#7-core-builtins).
- All send primitives in [Section 8](#8-send-primitives).
- All reply tuple helpers in [Section 9](#9-reply-tuple-helpers).
- Session environment lifecycle per
  [Section 10](#10-session-environment).
- Expansion and splicing per [Section 2](#2-expansion-model).

A conforming implementation SHOULD provide or make available all standard
library functions from [Section 12](#12-standard-library).

A conforming implementation MAY provide tail-call optimisation and MAY
provide additional builtins not defined here.

---

## 14. Security considerations

### 14.1 Arbitrary code execution

zscheme evaluates arbitrary code within the client process. Content fetched
from IPFS (via `!fetch` or `#/ipfs`/`#/ipns` path atoms) MUST be reviewed by
the user before evaluation. Implementations MUST NOT evaluate fetched
content automatically.

### 14.2 Network access

The send primitives allow Scheme code to send messages to arbitrary actor
targets. Scripts obtained from untrusted sources SHOULD be reviewed before
execution.

### 14.3 Config mutation

The path Set and Delete forms modify client config, including alias
tables and focus context. Malicious scripts could redirect actor targets by
overwriting aliases.

### 14.4 Session isolation

Implementations MUST ensure that the session environment of one user is not
accessible to any other user, including across browser tabs sharing the
same origin.

---

## 15. Implementation limitations

These notes describe known limitations of the current implementations
(zion, zscheme). They are informative, not normative.

### 15.1 No proper tail-call optimisation

The evaluators use recursive `async fn` calls. Deep tail-recursive loops
(> ~1000 frames) may exhaust the async stack. Use `fold` or iterative
patterns for large accumulations.

### 15.2 Scheme in sync batches

In zion, Scheme expansion is asynchronous. Inside a sync batch, a
Scheme-containing line does **not** block the batch step counter — the
expanded line re-queues and may arrive after the batch has advanced. Avoid
Scheme expressions inside sync batches until this is resolved.

### 15.3 Verbs in path expressions

`#/path!verb` forms (e.g. `#/my/doc/notes!eval`, `#/my/inbox/5!reply`) are
not dispatched from within Scheme expressions. These are local terminal
operations that interact directly with the UI — opening the editor,
triggering document evaluation, managing the inbox — and require the full
terminal dispatch context that the Scheme evaluator does not have access
to. Only Get, Set, and Delete are available from within Scheme. Invoke
path verbs from the normal command line, outside of `(…)` spans.

---

## 16. References

### 16.1 Normative references

- [RFC2119] Bradner, S., "Key words for use in RFCs to Indicate Requirement
  Levels", BCP 14, RFC 2119, March 1997.
- [MA-RPC] [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md)
- [MA-MSG] [ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md)
- [MA-CRUD] [ma-crud-service-v1.md](../runtime/ma-crud-service-v1.md)

### 16.2 Informative references

- [R7RS] Shinn, A. et al., "Revised⁷ Report on the Algorithmic Language
  Scheme", 2013. <https://small.r7rs.org/>
- [MA-CORE] ma-core Rust crate. <https://crates.io/crates/ma-core>
- [STDLIB] zscheme standard library, HANDBOOK, and REFERENCE.
  <https://github.com/bahner/ma-scheme>
