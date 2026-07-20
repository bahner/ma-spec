# ma-scheme-v1 — Embedded Actor Scripting Language

**Status:** Candidate Recommendation
**Version:** 1.0.0
**Date:** 20 July 2026

---

## Abstract

This document specifies **ma-scheme**, a minimal, sandboxed Scheme dialect
that runs *inside* entity plugins (Wasm, any Extism-capable language) so
that end users can define an entity's entire behaviour by writing a script
— without ever writing, compiling, or publishing Wasm themselves.

ma-scheme is deliberately small. An entity plugin that hosts it exposes
one mandatory hook, `on-message`, one optional hook for every
runtime-originated lifecycle event, `on-signal`, and a handful of
primitives for reading/writing the entity's own persistent properties,
for managing its own behaviour source, and for sending messages. There is
no `eval` — no arbitrary string, message
content, or other runtime-computed value can ever be treated as code — and
no ambient network access of any kind beyond the messaging primitives
(§10). The **one** narrowly-scoped exception is `ma-include-ipfs`
(§11.1): a top-level-only construct whose argument is a literal
`#/ipfs/<cid>`/`#/ipns/<key>` token fixed in the script's own source
text — never a computed or message-derived value — expanded once, before
any evaluation begins, exactly like R7RS `include`. Composing a shared
library into a script's own behaviour happens *through this one
primitive*, at the author's own explicit and static choice, not via any
runtime-level text-preprocessing invisible to the language.

**Naming convention: `ma-`-prefixed primitives cross the sandbox boundary
into the runtime; unprefixed names are pure, local ma-scheme.** Every
primitive that maps directly onto a host function (§15) is spelled with an
`ma-` prefix — `ma-save-state!`, `ma-send!`, `ma-reply!`, `ma-log!`,
`ma-get-config-key`, `ma-create-actor`, `ma-entity-exists?`,
`ma-include-ipfs` — so a reader can tell at a glance
which calls leave the sandbox and which don't. The state-property
primitives (`get-prop`/`set-prop!`/`inc-prop!`/`del-prop!`/`has-prop?`, §9)
are the one deliberate exception: they are considered internal to an
entity's own
data, not a "reach out to the runtime" in the same sense, and stay
unprefixed. Core builtins (`+`, `car`, `string-append`, …) and special
forms (`define`, `if`, `let`, …) are never prefixed.

Everything a script can do, it does through the primitives in this
document — which are themselves subject to the runtime's ordinary
entity-level ACL (per-verb capability checks), exactly like any other verb
dispatch.

**ma-scheme is not zscheme.** [zscheme-v1.md](../zscheme/zscheme-v1.md)
specifies a much larger, client-side Scheme dialect that runs in `zion` and
the `zscheme` CLI, with full network access, config mutation, and general
dynamic code loading (`include`, reachable anywhere, any argument) — a
power-user/developer tool. ma-scheme runs **inside the sandbox**, is
written by (and safe for) non-developers editing an entity's behaviour,
and a runtime is one of its hosts, not merely a transport it scripts.
ma-scheme's own, much narrower `ma-include-ipfs` (§11.1) — top-level-only,
literal-token-only argument, no network access beyond that one fetch — is
not comparable in power to zscheme's `include`; the two dialects share no
implementation and are not required to share syntax beyond ordinary
S-expressions; where this document and zscheme-v1.md overlap (e.g.
`define`, `if`, `let`), ma-scheme values staying a *subset* of zscheme so
that reader knowledge transfers, but this is a design preference, not a
conformance requirement.

This specification is implementation-language-agnostic: it can be conformed
to by a host written in Rust, Python, Go, C, Zig, or any other
Extism-capable language. It does not mandate an implementation language, an
internal value representation, or a parser implementation strategy.

Companion documents:

- [zscheme-v1.md](../zscheme/zscheme-v1.md) — the unrelated, larger,
  client-side Scheme dialect (see note above — do not confuse the two)
- [ma-runtime-v1.md](ma-runtime-v1.md) — entity/kind plugin model, ACL,
  fragment routing, and behaviour-source resolution (`EntityNode.behaviour`,
  `KindNode.behaviour` source links)
- [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md) — RPC term format
- [ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md) — message
  envelope

---

## Table of contents

1. [Conventions and definitions](#1-conventions-and-definitions)
2. [Design goals](#2-design-goals)
3. [Lifecycle — `on-message`, `on-signal`](#3-lifecycle--on-message-on-signal)
4. [The `msg` record](#4-the-msg-record)
5. [Types and lexical conventions](#5-types-and-lexical-conventions)
6. [CBOR ↔ ma-scheme value mapping](#6-cbor--ma-scheme-value-mapping)
7. [Special forms](#7-special-forms)
8. [Core builtins](#8-core-builtins)
9. [State](#9-state)
10. [Messaging primitives](#10-messaging-primitives)
11. [Behaviour composition](#11-behaviour-composition)
   - 11.1. [`ma-include-ipfs` — top-level-only library composition](#111-ma-include-ipfs--top-level-only-library-composition)
12. [Logging](#12-logging)
13. [Error handling](#13-error-handling)
14. [Resource limits](#14-resource-limits)
15. [Standard library conventions (non-normative)](#15-standard-library-conventions-non-normative)
16. [Kind conformance](#16-kind-conformance)
17. [Conformance](#17-conformance)
18. [Security considerations](#18-security-considerations)
19. [References](#19-references)

---

## 1. Conventions and definitions

The key words "MUST", "MUST NOT", "SHOULD", "SHOULD NOT", and "MAY" are to
be interpreted as described in RFC 2119.

- **Host** — the entity plugin binary (any Extism-capable language) that
  embeds an ma-scheme reader/evaluator and exposes it to the runtime via
  the plugin ABI defined in [ma-runtime-v1.md](ma-runtime-v1.md).
- **Script** — the ma-scheme source text a host receives via the
  `:set-behaviour` signal (§3.2). The runtime resolves it from wherever it
  is actually stored (a single `EntityNode.behaviour` reference — see
  [ma-runtime-v1.md §14.2.2](ma-runtime-v1.md#1422-behaviour-resolution))
  and always hands the host back plain text, as stored — no runtime-level
  composition of any kind; a script MAY compose further library content
  into itself via `ma-include-ipfs` (§11.1), the one narrowly-scoped
  exception to "ma-scheme has no notion of where text physically lives."
- **Runtime** — the ma-compatible entity host process (e.g. the reference
  `ma` runtime) that loads the plugin and delivers messages to it. The
  runtime evaluates no ma-scheme itself; all evaluation happens inside the
  entity plugin's sandbox. The runtime *does* resolve behaviour source
  and drives the lifecycle calls of §3.

## 2. Design goals

- Let non-developers define an entity's entire externally-visible behaviour
  by writing a script — no Wasm compilation step, ever.
- **Three tiers of reuse, increasing in specificity:** the **kind** (the
  compiled Wasm binary, most generic — e.g. a single `/ma/scheme/actor/0.0.1`
  binary usable for any purpose), the **behaviour** (a ma-scheme template
  one author writes and reuses across every entity they create from it —
  e.g. "my restaurant behaviour"), and the **`:init` signal's payload**
  (specific to one particular entity instance — e.g. *this* restaurant's
  name and owner). See §3.3 for how these compose.
- Keep the evaluator minimal. Anything expressible in ma-scheme itself
  SHOULD be distributed as a convention/standard-library snippet (§15)
  rather than built into the host evaluator.
- No ambient authority: a script can only observe its own state and the
  contents of the one `msg` it is currently handling, and can only act
  through `ma-send!`/`ma-reply!` and the entity-management primitives
  `ma-create-actor`/`ma-entity-exists?`, plus the one narrowly-scoped
  exception of `ma-include-ipfs` (§11.1 — literal-token-argument-only,
  unreachable from `on-message` by construction). It cannot read another
  entity's state, cannot make arbitrary host calls, and cannot change its
  own or any other entity's behaviour reference from within a script (§11,
  §18).
- Behaviour composition is never a hidden backdoor: `ma-include-ipfs`
  (§11.1) always works the same way regardless of ACL (it isn't a
  runtime-mediated verb at all — resolution happens purely between the
  script and the Kubo-backed fetch), but its argument being a fixed
  literal in the script's own source means the *set* of content any
  script can ever cause to load is entirely determined once, by whoever
  wrote that source — never by an incoming message or any other runtime
  value.

## 3. Lifecycle — `on-message`, `on-signal`

A conforming host implements the general plugin ABI defined in
[ma-runtime-v1.md §14.2](ma-runtime-v1.md#142-plugin-abi): **exactly two**
Wasm-level exports, always — `on_message` for incoming messages, `on_signal`
for every runtime-originated lifecycle event. An earlier draft of this
specification had six separately-named exports (`set_state`/
`set_behaviour`/`do_init`/`do_start`/`do_shutdown`/`on_message`); the first
five have been collapsed into the single `on_signal` export, which the
runtime calls in this fixed order on every load, whenever each signal is
applicable:

```
on-signal([:set-state, state])       <- only if persisted state already exists
on-signal([:set-behaviour, text])    <- only if a behaviour reference resolves
on-signal([:init, payload])          <- only on this entity's very first load
on-signal(:start)                    <- called on every load
    (message loop begins)
    on-message(msg)                   <- called once per incoming message
on-signal(:shutdown)                  <- called once, best-effort, before teardown
```

Each signal is a **term** in exactly the same shape as a message dispatch
term (§6): a bare atom (`:start`, `:shutdown`) when there is no associated
data, or a two-element list (`(:set-state state)`, `(:set-behaviour
text)`, `(:init payload)`) when there is. A conforming host recovers the
signal name and data with the same `verb-of`/`args-of` idiom already used
for `on-message` dispatch (§6, §15) — one calling convention, shared by
both exports.

**Not every signal reaches a script.** `:set-state`, `:set-behaviour`, and
`:init` are host-mechanical — the host's own fixed internal logic handles
them (decode state bytes into the live state table, §9; parse+evaluate
behaviour text; evaluate the creation payload) regardless of what, if
anything, the loaded script defines. There is no `(define (set-state
...) ...)`/`(define (set-behaviour ...) ...)` form in ma-scheme, and a
script never sees these three signals arrive as calls to anything it
defines — the host intercepts and handles them entirely on its own before
ever considering a script lookup (`:set-behaviour`, in particular,
*cannot* look up a script handler: at the point it runs, the script's own
definitions don't exist yet — evaluating the given text is precisely what
*creates* them).

`:start` and `:shutdown`, by contrast, are the two genuinely
script-definable signals — a conforming host looks up and calls a single,
optional script-defined `on-signal` function, exactly the way it looks up
and calls `on-message` for a message:

```scheme
(define (on-signal term)
  (cond ((equal? (verb-of term) :start) ...)
        ((equal? (verb-of term) :shutdown) ...)
        ;; a script MAY leave this open for future signals it doesn't
        ;; recognize yet — falling through silently is fine, nothing
        ;; requires exhaustive handling.
        ))
```

If the script does not define `on-signal` at all, the host silently does
nothing for `:start`/`:shutdown` — there is no fallback behaviour of any
kind (see §3.4 for why this specifically matters for `:shutdown`). This
is the same "no hidden magic" principle applied throughout this
specification (§2): an author who wants shutdown-time persistence writes
`(ma-save-state!)` into their own `on-signal` explicitly (typically via
the stdlib convention, §15), never implicitly on their behalf.

**Why collapse five exports into one.** Adding a future lifecycle
concept (e.g. a hypothetical pause/resume/migrate signal) no longer
requires *any* ABI change — no new Wasm export, no new `KindNode` field,
no host-side registration change. It only requires the runtime to start
sending a new atom at the appropriate point, and a script that cares about
it adds a `cond` branch to its own `on-signal`. Scripts that don't care
about a new signal are unaffected automatically, by construction — they
already fall through whatever `cond`/`case` they wrote.

### 3.1 The `:set-state` signal — host-mechanical, conditional

Fires **only if persisted state already exists** for this entity (i.e.
not on a brand-new entity's very first load). The associated data is the
raw persisted state bytes. Decodes them directly into the live in-memory
state table (§9) — plain deserialization, nothing evaluated, no script
involvement.

### 3.2 The `:set-behaviour` signal — host-mechanical, conditional

Fires **only if a behaviour reference resolves** to something (i.e. the
kind declares a `behaviour` dialect per
[ma-runtime-v1.md §11.2](ma-runtime-v1.md#112-kindnode-structure) and
`EntityNode.behaviour` points at actual content). The associated data is
already fully resolved, plain ma-scheme source text — the host parses and
evaluates it top-to-bottom in a fresh environment, defining `on-signal`/
`on-message`/helpers. No script involvement in the resolution itself; the
host just receives and evaluates what it's given.

If a kind's entities never have a behaviour reference (e.g. a kind that
doesn't declare `KindNode.behaviour` at all), this signal is simply never
fired, and a script wanting `on-message`/`on-signal` to exist would need
some other mechanism entirely outside ma-scheme's scope — this
specification only describes what happens when a behaviour dialect *is*
declared.

### 3.3 The `init` signal — host-mechanical, genesis only

Fires **at most once, ever**, for a given entity — only as part of its
very first load, after `:set-state`/`:set-behaviour` have already fired
(so `on-signal`/`on-message`/helpers already exist and any pre-existing
state is already loaded) — per the atomicity guarantee in
[ma-runtime-v1.md §14.2](ma-runtime-v1.md#142-plugin-abi) (this runs
*before* the entity is reachable by any message). It never fires again on
a later reload.

The associated `payload` is the **third and most specific tier** of the
reuse hierarchy in §2: the kind (Wasm binary) is generic, the behaviour
(§3.2) is a reusable template, and `payload` is what makes *this* entity
instance unique.

Unlike `:start`/`on-message`/`:shutdown`, `:init` is **not** dispatched to
a script-defined function at all — the host MUST instead evaluate
`payload` itself, directly, as ma-scheme source text, top-to-bottom, in
the same environment `:set-behaviour` (§3.2) already populated. This is
the exact same mechanism `:set-behaviour` uses for the resolved behaviour
text, just applied to a second, later piece of source. This resolves what
would otherwise be a gap: ma-scheme has no general `eval` a script could
call to process `payload` itself (§18), so the host performs this one
evaluation for it, scoped specifically to entity creation.

A typical `payload` is therefore an ordinary sequence of top-level forms,
no wrapping function needed:

```scheme
(set-prop! "owner" "did:ma:meg")
(set-prop! "name" "A luxurious restaurant")
(set-prop! "description" "...")
```

Since `payload` evaluates in the same environment as the behaviour, it MAY
also define or redefine `on-message`/`on-signal`/helpers — though the
common case is simply seeding initial state via `set-prop!`, leaving the
behaviour template's own definitions untouched. `payload` is entirely
optional; a kind MAY require it to be present and reject creation with a
clear error if it is missing or malformed (per
[ma-standard-actors-v1.md §2.2.2](ma-standard-actors-v1.md#222-create)).

### 3.4 The `:start` signal — script-definable, every load

Fires on **every** load — both the very first (immediately after `:init`
fires, §3.3) and every subsequent reload. No associated data. A script
handles it, if it cares to, inside its own `on-signal` (§3 above).
Typical uses: announcing the entity is back up (e.g. `(ma-send! owner-did
'(:status "back online"))`), or re-registering a schedule with
`#scheduler` — schedules do not survive a runtime restart and MUST be
re-registered on every startup regardless of whether this is a fresh
entity or a reload, so handling `:start` (not `:init`) is the right place
for that, not a one-time-only concern.

### 3.5 `on-message` (msg) — required

A conforming host MUST call exactly one script-defined function for every
incoming fragment-addressed message:

```scheme
(define (on-message msg) ...)
```

`on-message` takes exactly one argument, the [`msg` record](#4-the-msg-record).
Its return value is **ignored** — a script communicates outbound
exclusively via the [messaging primitives](#10-messaging-primitives)
(`ma-send!`, `ma-reply!`).

If the current script does not define `on-message`, the host SHOULD reply
`[:error, "no behaviour configured"]` if the message expects a reply, and
otherwise silently drop it.

`on-message` is named for what it is: a trigger fired by the host, not a
general request/response RPC handler the script calls into itself — the
counterpart to `on-signal` (§3), not a `do-`-style imperative call.
Messages come from other actors; signals come from the runtime itself —
same shape, different source, hence one name each rather than one shared
name for both.

### 3.6 The `:shutdown` signal — script-definable, NOT hidden

The host fires this best-effort, once, before tearing an entity down
(e.g. a graceful runtime shutdown). No associated data. Handled, if a
script cares to, inside its own `on-signal` (§3 above) — it has no fixed
hardcoded behaviour of any kind:

- If the script's `on-signal` handles `:shutdown`, it is entirely up to
  the script what to do — the common case is just `(ma-save-state!)`, but
  a script MAY do something else instead or in addition (e.g. notify
  everyone currently in a room before the entity disappears).
- If the script does **not** define `on-signal` at all, or its `on-signal`
  doesn't recognize `:shutdown`, **nothing happens** — the host has no
  built-in fallback of any kind. A conforming host MUST NOT call
  `ma-save-state!` (or anything else) on the script's behalf; doing so
  silently on undefined behaviour is exactly the kind of invisible,
  unscriptable magic this specification avoids elsewhere (§2). A kind
  that wants "save on shutdown" as its default composes an ordinary
  `(define (on-signal term) (when (equal? (verb-of term) :shutdown)
  (ma-save-state!)))` into the entity's behaviour text like any other
  definition — typically via the stdlib convention (§15) spliced in with
  an ordinary `(ma-include-ipfs #/ipfs/<stdlib-cid>)` top-level form
  (§11.1), not a host special case. A script's own, later
  `(define (on-signal term) ...)` in the same composed text simply
  rebinds the name, overriding the stdlib default — ordinary lexical
  scoping, nothing bespoke.

  This is best-effort only: a crash, a kill, or any non-graceful termination
  can never invoke it. Its return value is ignored.

## 4. The `msg` record

`msg` is a **read-only** record provided by the host. A script MUST NOT be
able to mutate it (there is no `set-msg!` of any kind); replying or sending
always goes through explicit primitives that take the DID/term to use.
`msg` is not merely data — it is a capability/context object: `ma-reply!`
(§10) requires the original `msg` precisely because the reply address,
dispatch audit trail, and any future auth context ride along with it.

The host MUST provide these accessors (exact internal representation is an
implementation detail — vector, alist, or otherwise — scripts MUST only use
these accessor names):

| Accessor | Type | Description |
|---|---|---|
| `(msg-id msg)` | string | Message ID |
| `(msg-from msg)` | string | Sender DID(-URL) |
| `(msg-to msg)` | string | Recipient DID-URL (this entity) |
| `(msg-created-at msg)` | integer | Unix seconds the message was created |
| `(msg-exp msg)` | integer | Unix seconds — absolute epoch timestamp when this message expires (`0` = never expires). Matches the wire field name `exp` exactly (ma-messaging-format-v1.md §2), not spelled out as `expires`. Not a duration/TTL — do not subtract from `msg-created-at` expecting a relative offset without checking for `0` first |
| `(msg-reply-to msg)` | string or `#f` | Message ID this is a reply to, if any |
| `(msg-type msg)` | string | MIME message type — the routing/dispatch category, e.g. `"application/vnd.ma.chat"`, `"application/vnd.ma.emote"`, `"application/vnd.ma.broadcast"`, `"application/vnd.ma.message"`, `"application/vnd.ma.rpc.request"` (see table below) |
| `(msg-content-type msg)` | string | MIME content type — the *format* of `msg-content`'s payload bytes, e.g. `"application/vnd.ma.term"`, `"application/cbor"`, `"text/plain"` |
| `(msg-content msg)` | any | The message body, decoded per §6 |

Note `msg-id`/`msg-from`/etc. are plain accessors, not `ma-`-prefixed —
they read fields off a value the host already handed the script (via the
`on-message` call itself), not a fresh call out to the runtime.

`msg-type` and `msg-content-type` are both genuine MIME type strings (not
merely MIME-*like*) and answer two different questions: `msg-type` says
*what kind of message this is* (a chat line? an emote? a broadcast? an RPC
call?); `msg-content-type` says *how the payload bytes are encoded*. A
script that wants to, say, render emotes differently from chat MUST
dispatch on `msg-type`, not `msg-content-type`:

```scheme
(define (on-message msg)
  (cond ((equal? (msg-type msg) "application/vnd.ma.emote")
         (handle-emote msg))
        ((equal? (msg-type msg) "application/vnd.ma.chat")
         (handle-chat msg))
        (else (handle-rpc msg))))
```

In practice, fragment-addressed dispatch delivers only these `msg-type`
values to a script (per [ma-runtime-v1.md §10](ma-runtime-v1.md#10-fragment-routing)):
`"application/vnd.ma.chat"`, `"application/vnd.ma.emote"`,
`"application/vnd.ma.broadcast"`, `"application/vnd.ma.message"`, and
`"application/vnd.ma.rpc.request"`. Other message types defined elsewhere in ma
(`application/vnd.ma.crud.request`, `application/vnd.ma.doc`,
`application/vnd.ma.identity.publish.request`, `application/vnd.ma.ipfs.request`, …) are
handled by dedicated runtime services, not delivered to entity scripts.

A host MAY additionally provide `(msg? x)` — a predicate that is `#t` only
for values produced by the host as a `msg`.

## 5. Types and lexical conventions

ma-scheme values: integers, floats, strings, booleans (`#t`/`#f`), symbols,
proper lists (built from pairs, `'()` empty list), string-keyed maps,
lambdas, the opaque `msg` record type, and the opaque **CID-reference
literal** (see below). There is no vector or general record type available
to scripts beyond maps and `msg`, and no `eval`-able code-as-data —
`quote` produces inert list/symbol data only, never something re-enterable
as code.

Maps are deterministic, string-keyed associative values. Map keys MUST be
strings. Map values MAY be any ordinary ma-scheme data value, including
nested maps, provided that the value can be CBOR-encoded when it crosses a
state/message boundary (§6, §9). Maps are semantically unordered; hosts
SHOULD expose keys and values in deterministic key order.

Lexical syntax is standard S-expression Scheme: parenthesised forms,
`;` line comments, `'x` as sugar for `(quote x)`, standard numeric and
string literal syntax. Symbols beginning with `:` (e.g. `:ok`, `:enter`)
are ordinary symbols by convention, used the same way the rest of the ma
ecosystem uses `:verb` atoms on the wire (§6) — they are not a distinct
type from other symbols.

**CID-reference literal.** A token of the exact form `#/ipfs/<cid>` or
`#/ipns/<key>` (no whitespace inside it) is a distinct literal type, read
as a single, opaque, non-symbol, non-string token — it is not a string
(`string?` is `#f` on it), not a symbol (`symbol?` is `#f` on it), and
cannot be constructed, computed, or converted from any other value (no
`string->cid`-style coercion of any kind exists). Its **only** legal use in
the whole language is as the direct, literal argument to `ma-include-ipfs`
(§11.1) — nowhere else accepts it, and there is no predicate to test for
it, no accessor to inspect it, no way to move it through a variable, and
no way to produce one at runtime from data (message content, a string, or
anything else). This is a deliberately narrow, single-purpose literal, not
a general CID/reference value type.

## 6. CBOR ↔ ma-scheme value mapping

`msg-content` is the message body after CBOR decoding, converted to
ma-scheme values as follows (this MUST be the mapping every conforming
host uses, so that a script sees the same shape of data regardless of host
implementation language):

| CBOR | ma-scheme |
|---|---|
| Text starting with `:` (e.g. `":ping"`) | Symbol (e.g. `:ping`) |
| Text not starting with `:` | String |
| Integer | Integer |
| Float | Float |
| Boolean | Boolean |
| Null | `'()` |
| Array | Proper list, each element mapped recursively |
| Map with text-string keys | Map, each value mapped recursively |

CBOR maps with any non-text key are not valid ma-scheme values. A host
encountering such a map as message content MUST treat it as a decode error
for the purposes of script dispatch (reply `[:error, "map key unsupported"]`
if a reply is expected) rather than silently coercing, dropping, or guessing
a key representation.

When encoding ma-scheme values back to CBOR, maps MUST be encoded as CBOR
maps with text-string keys. Hosts SHOULD use deterministic encoding for
state and message content: shortest-form CBOR encodings and deterministic
map entry ordering. The string-key restriction is specifically chosen so
that deterministic map encoding and stable persisted state are practical.

This mirrors the existing wire convention used throughout ma
([ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md)): a verb dispatch
term is either a bare atom (`:ping`) or an array whose first element is the
verb atom (`[:enter, "ticket-123"]`). A script recovers the verb and
arguments with:

```scheme
(define (verb-of term) (if (pair? term) (car term) term))
(define (args-of term) (if (pair? term) (cdr term) '()))
```

(§15 shows this as part of the optional dispatch-table convention.)

## 7. Special forms

A conforming host MUST support at least:

`define`, `lambda`, `let`, `let*`, `letrec`, `if`, `cond`, `when`, `unless`,
`begin`, `and`, `or`, `quote`, `set!`.

`let*`, `letrec`, `when`, and `unless` are **required**, not optional sugar
— an earlier draft deferred them to a convention prelude on the theory
(borrowed from zscheme) that anything not built in could be loaded as a
standard library. That reasoning does not transfer here: ma-scheme's only
inclusion mechanism, `ma-include-ipfs` (§11.1), composes libraries of
ordinary `define`d values/procedures — there is no `define-syntax` or any
other macro system, so a library can never add new *syntax*. Special
forms are exactly the one category of language feature no ma-scheme
library can ever supply, so anything in this category not required here
would have to be hand-rolled by every non-developer script author from
scratch — directly against the goal in §2. `guard`/`try` remains
genuinely optional (§13 explains why a script does not need one).

A conforming host MUST NOT support `eval`, and MUST NOT support any
include-like or dynamic-code-loading mechanism **other than**
`ma-include-ipfs` exactly as specified in §11.1 (top-level-only, literal
CID-reference argument, expanded once before evaluation begins) — no
general mechanism exists (or may be added by a conforming host) for
treating a string, message content, or any other runtime-computed value
as code. See §18.

**Tail calls.** A conforming host MUST implement proper tail-call
elimination for self-tail-calls — a call to the enclosing function in tail
position (including through `if`/`cond`/`begin`/`and`/`or`/`let`/`let*`/
`letrec`/`when`/`unless`) MUST execute in O(1) host stack, not grow a call
stack per iteration. This is what makes the common iteration idiom safe to
require of non-developers:

```scheme
(define (count-down n)
  (if (= n 0) 'done (count-down (- n 1))))
```

Because a properly tail-recursive loop consumes no growing resource, a
conforming host MUST NOT impose an artificial recursion-depth or step-count
limit (see §14) — a script that loops forever this way merely spins,
bounded only by the surrounding Wasm call's own execution timeout, exactly
like any other non-terminating computation. Deep **non-tail** recursion
(each call doing work after the recursive call returns) is bounded by the
host's own native stack and MAY produce an error rather than succeeding;
that is an acceptable, contained failure of that one call (§13), not a
specification concern.

`set!` mutates a lexical binding (e.g. a local accumulator inside a single
`on-message` call). It has no effect on the entity's persistent state —
that is exclusively the job of the [state primitives](#9-state) (§9).
Conflating the two is a common mistake: a `set!` on a variable is gone the
moment the call returns; only `set-prop!` (and friends) survive until the
next message.

## 8. Core builtins

A conforming host MUST support at least:

- **Arithmetic:** `+`, `-`, `*`, `/`
- **Comparison:** `=`, `<`, `>`, `<=`, `>=`
- **Boolean:** `not`
- **Pairs/lists:** `cons`, `car`, `cdr`, `list`, `null?`, `pair?`
- **Type predicates:** `string?`, `number?`, `boolean?`, `symbol?`, `map?`, `procedure?`
- **Strings:** `string-append`, `string-prefix?`, `number->string`, `string->number`
- **Maps:** `make-map`, `map-ref`, `map-set`, `map-delete`,
  `map-has-key?`, `map-keys`, `map-values`, `map->alist`, `alist->map`
- **Equality:** `equal?`

String primitives are pure local data operations:

- `(string-append string...)` concatenates all arguments.
- `(string-prefix? prefix string)` returns `#t` when `string` begins with
  `prefix`, otherwise `#f`.
- `(number->string number)` converts a number to its textual representation.
- `(string->number string)` parses an integer or floating-point number from
  text, or returns `#f` when parsing fails.

Map primitives are pure local data operations:

- `(make-map [key value]...)` builds a map from alternating string keys and
  values; duplicate keys are last-write-wins.
- `(map? value)` returns `#t` if `value` is a map.
- `(map-ref map key [default])` returns the value for string `key`, or
  `default` if supplied, otherwise `#f`.
- `(map-set map key value)` returns a new map with string `key` set to
  `value`.
- `(map-delete map key)` returns a new map without string `key`.
- `(map-has-key? map key)` returns `#t` if string `key` is present.
- `(map-keys map)` returns a list of keys in deterministic order.
- `(map-values map)` returns values in the same order as `(map-keys map)`.
- `(map->alist map)` returns an association list of `(key . value)` pairs in
  key order.
- `(alist->map alist)` builds a map from an association list with string keys.

`map-set` and `map-delete` are intentionally non-mutating. Persisting a
map change therefore remains explicit and visible:

```scheme
(let ((current (get-prop "exits")))
  (set-prop! "exits"
    (map-set (if (map? current) current (make-map)) "north" exit-url)))
(ma-save-state!)
```

A future version MAY add mutating map operations, but only after specifying
the aliasing semantics for maps already stored in props.

This is intentionally small (§2). Anything else a script needs — `map`,
`filter`, `length`, `string-split`, and so on — is either written by the
script author in ma-scheme itself, or provided by a convention prelude
(§15), never by growing this list without a version bump.

## 9. State

Every entity has a single, flat, host-managed **state** table — a
string-keyed map of arbitrary property *data* (plain values, never code).
This is the *entirety* of what persists between messages and across entity
reloads. The runtime treats it as a completely opaque blob it must persist
unmodified (round-tripped via the plugin ABI's state mechanism, e.g.
`ma_set_state` in the reference runtime) — the runtime never parses or
interprets any of its keys. **Behaviour is never part of state** — see
§11; it lives entirely outside this table, managed by the runtime.

Encoding is CBOR (consistent with §6 and with everything else in this
ecosystem) — nothing about Wasm or Extism mandates any particular format
for state (the reference runtime's `ma_set_state` host function simply
compares and stores whatever bytes it's given, uninterpreted); CBOR is
simply the convention already used throughout this ecosystem.

A conforming host MUST provide (unprefixed — see the naming convention in
the Abstract; these are considered internal to the entity's own data, not
a "reach out to the runtime" in the same sense as everything else in this
document):

| Primitive | Effect |
|---|---|
| `(get-prop key)` | Returns the current value for `key`, or `#f` if absent |
| `(set-prop! key value)` | Sets `key` to `value` |
| `(inc-prop! key [amount])` | Adds `amount` (default `1`) to the numeric value at `key`, creating it at `0` first if absent |
| `(del-prop! key)` | Removes `key` |
| `(has-prop? key)` | `#t` if `key` is present |

`key` is always a string. `value` may be any ma-scheme value the host can
CBOR-encode using the inverse of the §6 mapping (i.e. lists, maps,
strings, numbers, booleans — no lambdas, no builtins, no `msg`, no
CID-reference literals). Maps may be nested recursively; any non-encodable
value anywhere inside the structure makes the whole state encode fail.

**Persistence is NOT automatic — a script MUST call `(ma-save-state!)`
explicitly for any state change to survive an entity reload.**
`get-prop`/`set-prop!`/`inc-prop!`/`del-prop!` only mutate the *in-memory*
table immediately (visible to subsequent `get-prop` calls within the same
running session, including later dispatches, since the host's live
environment persists across messages the way any stateful plugin's memory
does — see [ma-runtime-v1.md](ma-runtime-v1.md)); none of that is durably
persisted until `(ma-save-state!)` actually calls the host's underlying
state mechanism (`ma_set_state` in the reference runtime). If the entity
is reloaded (e.g. a runtime restart) before `(ma-save-state!)` is called,
any unsaved in-memory changes are lost and the entity comes back with
whatever was last actually saved.

`(ma-save-state!)` — unlike the props primitives above, this one *is*
prefixed: it's a deliberate, explicit call out to the runtime's
persistence mechanism, not a local data operation.

This is a deliberate design choice, not an oversight: `ma_set_state`
persists to IPFS, and — exactly like the stateless/stateful kind
distinction itself — persisting on every single dispatch regardless of
whether anything meaningful changed would flood IPFS with encrypted,
always-unique blobs for no reason (e.g. a purely read-only `:look` verb has
nothing worth saving). A script decides for itself when a change is worth
persisting and calls `(ma-save-state!)` only then.

**Shutdown safety net.** See §3.6 (the `:shutdown` signal) — a script MAY
handle `:shutdown` in its own `on-signal` to call `(ma-save-state!)` (or
anything else); the host has no fallback of its own if a script doesn't
(§3.6). Either way this is best-effort: a crash or a kill can never
deliver `:shutdown` at all, so unsaved changes can still be lost in that
case — no worse off than before `ma-save-state!` existed.

Because state is persisted through the same mechanism as every other
entity's state — encrypted before being stored (see
[ma-runtime-v1.md](ma-runtime-v1.md)) — its contents are not readable by
anyone fetching the raw persisted bytes off IPFS.

**Stdlib/prelude is composed via `ma-include-ipfs`, not stored in state
and not compiled into the Wasm binary.** A kind's standard library or
convention prelude (§15) is ordinary ma-scheme source, published to IPFS
like any other behaviour content and composed in via a top-level
`(ma-include-ipfs #/ipfs/<stdlib-cid>)` form (§11.1) — never in persisted
state, and never baked into the kind's compiled binary. This means
upgrading a kind's stdlib never requires rebuilding or republishing the
kind's Wasm binary at all — only republishing the stdlib content itself
(trivially, via an `/ipns/<key>`-backed reference, without touching any
including script's own source).

### 9.1 Config — `ma-get-config-key` (read-only)

Separate from an entity's own mutable state, a conforming host MUST
provide one read-only lookup primitive:

| Primitive | Effect |
|---|---|
| `(ma-get-config-key key)` | Returns the value for the well-known key `key`, or `#f` if unknown |

`ma-get-config-key` is strictly for values that are genuinely immutable
for an entity's entire lifetime. A conforming host MUST support at least:

| Key | Type | Description |
|---|---|---|
| `"self"` | string | This entity's own DID-URL |
| `"fragment"` | string | This entity's bare fragment name |
| `"behaviour"` | string | This entity's own `EntityNode.behaviour` reference (a single CID), snapshotted at load time — not fetched, not resolved, not `ma-include-ipfs`-expanded, just the reference itself as a string |

`ma-get-config-key` is **read-only** — there is no setter, and behaviour
is immutable for an entity's lifetime in this specification: there is no
primitive that changes `EntityNode.behaviour` from within a script (§11).
An entity's behaviour reference changes only via ordinary external CRUD
(e.g. the reference runtime's `:entities.<name>: <cid>` RPC verb) — the
same mechanism used to change anything else about an entity from the
outside — followed by a reload, never from inside `on-message` itself.
Composing in an updated *library* without any external CRUD or reload at
all is still possible via an `/ipns/<key>`-backed `ma-include-ipfs`
reference (§11.1), which naturally resolves to whatever the key currently
points at on the entity's *next* reload.

**Further keys (non-normative, not yet specified):** additional
runtime-wide well-known keys — e.g. which fragment currently implements
`#house` — are planned but deferred. When specified, they are additional
read-only keys in this same `ma-get-config-key` space, not a separate
mechanism.

## 10. Messaging primitives

A conforming host MUST provide:

- **`(ma-send! target term)`** — fire-and-forget message to `target` (a
  `#fragment`, bare local fragment, `did:ma:...`, or
  `did:ma:...#fragment` string). Local fragment targets are delivered
  directly inside the same runtime; DID/DID-URL targets use the host's
  outbound delivery path. Maps onto the host's outbound send primitive
  (`ma_send` in the reference runtime). There is no reply-waiting, no
  synchronous request/response — see
  [rust-ma-runtime AGENTS.md](../../rust-ma-runtime/AGENTS.md) for why
  synchronous inter-actor calls are architecturally excluded.
- **`(ma-reply! msg term)`** — reply to the message currently being
  handled. Requires the original `msg` (§4) — a script cannot fabricate a
  reply target out of thin air; the reply address is derived from `msg` by
  the host.

  There is **no built-in `say`, `emit`, or `broadcast`** — these are ordinary
  messages a script sends to whichever targets it decides on (e.g. by asking
  another actor for a list of present avatars and caching the result in a
  prop, then iterating with `ma-send!` when it wants to announce something).
  Recipient-list management is entirely the script's responsibility, not a
  host or runtime concern.

### 10.1 Entity-management primitives

The reference ma-scheme actor also exposes two runtime-crossing entity
management primitives:

- **`(ma-entity-exists? actor)`** — returns `#t` if `actor` names a live
  local entity and `#f` otherwise. `actor` MUST be a string: a bare fragment,
  `#fragment`, or a local DID-URL. It maps to the runtime's
  `ma_entity_exists` host function, which receives raw UTF-8 and returns raw
  UTF-8 `true` or `false`.
- **`(ma-create-actor kind behaviour init)`** — queues creation of a new
  entity via the runtime's `ma_create_entity` host function. `kind` MUST be
  a protocol-ID string such as `/ma/scheme/actor/0.0.1`; `behaviour` MUST be
  a string reference (`/ipfs/<cid>` or `/ipns/<key>`) or `#f`; `init` MUST be
  a string of ma-scheme source or `#f`. The host call receives a CBOR map
  with keys `kind`, `behaviour`, and `init`; `init`, when present, is encoded
  as bytes and delivered as the new entity's `:init` payload (§3.3). On
  success, the primitive returns the newly generated fragment string. The
  entity is loaded after the current dispatch returns; success means the
  creation request was queued, not that the entity is already live.

## 11. Behaviour composition

There is **no reserved-verb mechanism** for reading or changing behaviour.
Behaviour source lives in a single `EntityNode.behaviour` reference the
runtime fetches **as a single, flat, unprocessed blob of text** — the
runtime performs no scanning, no recursion, no composition of any kind on
it (see
[ma-runtime-v1.md §14.2.2](ma-runtime-v1.md#1422-behaviour-resolution)).
**All composition happens inside ma-scheme itself**, through exactly one
primitive: `ma-include-ipfs` (§11.1). This composes with the three-tier
reuse model (§2, §3.3): a shared library and an entity-specific script can
be published separately and composed with one `ma-include-ipfs` line,
fully visible in the script's own source, not hidden in a runtime-level
preprocessing step the language itself never sees.

### 11.1 `ma-include-ipfs` — top-level-only library composition

```scheme
(ma-include-ipfs #/ipfs/bafy...)
(ma-include-ipfs #/ipns/k51...)
```

`ma-include-ipfs` is **not an ordinary special form** evaluated wherever it
appears — it is recognized and expanded **only when it is a direct
top-level form** in the text delivered via the `:set-behaviour` signal
(§3.2) or the `:init` signal's payload (§3.3), in a pre-pass that runs
once, completely before any evaluation of that text begins. Semantically
this is R7RS `include`, not `load`: the referenced content's top-level
forms are spliced in place, becoming part of the *same*, persistent,
whole-lifetime environment as the rest of the script — not evaluated in
an isolated scope, and not re-run later.

**A conforming host MUST NOT recognize `ma-include-ipfs` anywhere except as
a direct top-level form.** If it appears nested inside a `define`, `lambda`
body, `on-message`, or any other expression position, it MUST NOT be
treated specially — since it is deliberately not installed as an ordinary
callable procedure either, a host referencing it from such a position MUST
produce an ordinary unbound-variable error at that call site, exactly as
any other undefined name would. This is not a policy scripts must remember
to follow — it is a structural guarantee: the expansion pass only ever
looks at the outermost list of top-level forms, so nothing reachable from
`on-message` can ever trigger a fetch, and the "a slow resolution is fine"
property (below) is unconditionally true, not merely true if used
correctly.

**Argument is a literal CID-reference token, never a computed value.** The
argument MUST be written literally as `#/ipfs/<cid>` or `#/ipns/<key>` in
the source (§5) — it is read as syntax, not evaluated as an expression,
exactly like `quote`'s argument. There is no way to construct this token
from a string, from `msg-content`, or from any other runtime value — the
set of content a script can ever cause to be included is therefore fully
determined by literal tokens present in the script's own source text,
decided once by whoever authored it. This is what makes `ma-include-ipfs`
safe despite reintroducing dynamic content loading into the language: it
is not `eval`, because there is no path from untrusted runtime data (an
incoming message, in particular) to a reference actually being resolved.

**Resolution.** A conforming host:

1. Fetches the content at the literal reference (`/ipfs/<cid>` via a plain
   content-addressed fetch; `/ipns/<key>` via a resolve-then-fetch) as
   UTF-8 text.
2. Parses it into top-level forms and recursively repeats this expansion
   on *that* content's own top-level `ma-include-ipfs` forms, exactly as
   for the outer text.
3. Splices the fully-expanded forms in place of the original
   `ma-include-ipfs` form.

Implementations MUST bound this recursion (e.g. a maximum depth) and MUST
reject a reference chain that revisits a reference already in its own
ancestor chain (a cycle) — the reference host uses a depth limit of 16 and
an ancestor-chain guard, mirroring the equivalent, now-removed runtime-level
mechanism this replaces. Note that true cycles are structurally impossible
for pure `/ipfs/<cid>` references (a CID is a hash of already-finalised
content); the guard exists for `/ipns/<key>` references, where a mutable
pointer could in principle be updated to close a loop.

**Resolving a slow `/ipns/<key>` is acceptable.** Because expansion only
ever happens while handling the `:set-behaviour`/`:init` signals — never
reachable from `on-message` — a multi-second resolution is a one-time
cost on an already network-bound load path (the runtime is already
fetching Wasm bytes and the entity's own behaviour reference at this
point), not a tax on message throughput. A conforming host's dedicated
per-entity execution context (the reference runtime uses one dedicated OS
thread per entity) MAY block during this resolution without affecting any
other entity.

**`/ipns/<key>` composition and "resolve once, fresh every load."** An
`/ipns/`-backed reference is deliberately mutable — this is the intended
mechanism for a shared library to evolve without every including script
needing to update its own reference. Because expansion happens completely
fresh every time the `:set-behaviour` signal is handled, and that signal
itself already fires completely fresh on every entity load, an
`/ipns/`-backed include naturally resolves to whatever the key currently
points at on each load — with no additional caching or freshness logic
required of a conforming host. Nothing about a running entity re-checks
the reference between reloads; republishing a shared library under its
existing key propagates to every including script's *next* load, not
immediately.

**There is no way to change an entity's own `EntityNode.behaviour`
reference from within ma-scheme, deliberately.** An earlier draft of this
specification had `ma-get-behaviour`/`ma-get-behaviour-cid`/
`ma-set-behaviour-cid!` host-function-backed primitives, plus a
script-level hot-reload pattern built on them. All three have been
removed: an entity's behaviour reference is immutable for its lifetime as
far as ma-scheme is concerned, changeable only via ordinary external CRUD
(e.g. the reference runtime's `:entities.<name>: <cid>` RPC verb) followed
by a reload — never from inside `on-message`. The realistic reason to want
runtime mutation — picking up an updated shared library without republishing
every including entity — is already fully covered by an `/ipns/<key>`-backed
`ma-include-ipfs` reference (above); introspecting an entity's own current
source is likewise already possible externally (e.g. `zion` reading a
remote actor's behaviour reference and fetching its content directly), so
no `ma-scheme`-level primitive is needed for that either. Removing these
three primitives also removes the corresponding host-side machinery
entirely (queuing a pending mutation, republishing `EntityNode`, repointing
the manifest) — one less moving part for both script authors and host
implementers, for a capability that turned out not to be needed.

## 12. Logging

A conforming host MUST provide:

| Primitive | Effect |
|---|---|
| `(ma-log! message)` | Writes `message` (a string) to the host's own log, via Extism's built-in logging facility |

This does **not** require a new custom host function in the Extism
sense — it maps onto whatever native logging mechanism the Extism PDK for
the host's implementation language already exposes (e.g. `extism_pdk::log!`
in Rust), not something `/ma/scheme/actor/0.0.1` (or any kind) needs to declare
in its own `host_functions` list.

## 13. Error handling

There is no `guard`/`try` special form required in v1 (§7) — a host MAY
provide one for scripts that want to contain a failure in their own
ordinary evaluated code, but a script author does not strictly need one
for ordinary operation: if evaluating `(on-message msg)` raises an
unhandled error, the **host** catches it (a script MUST NOT be able to
crash the entity or the runtime by erroring) and:

- replies `[:error, reason]` if the incoming message is of a type that
  expects a reply,
- otherwise logs and drops it,

and leaves the entity's environment exactly as it was before the failed
call. Since persistence is explicit (§9 — `(ma-save-state!)`), an error
mid-way through a handler simply means whatever it had not yet saved is
lost from memory but was never durable anyway; the last successfully-saved
state on disk/IPFS is completely unaffected either way.

## 14. Resource limits

There is no step-count or gas-metering requirement in this specification.
The tail-call guarantee in §7 means a script that loops forever through
proper tail recursion consumes no growing host resource — it merely spins,
bounded only by whatever wall-clock/interrupt mechanism the surrounding
Wasm runtime already enforces on any plugin call (e.g. the reference
runtime's epoch-interrupt call timeout). An infinite loop of this kind is
the script author's problem, not a host safety concern, and a conforming
host MUST NOT reject it pre-emptively with an artificial limit.

Deep **non-tail** recursion is bounded by the host's own native call stack
rather than by anything ma-scheme-specific. A host SHOULD contain a stack
overflow as an ordinary catchable error (per §13) where the underlying
platform makes that possible, rather than aborting the whole process, but
this is a quality-of-implementation goal, not a normatively specified
limit or number.

## 15. Standard library conventions (non-normative)

The following is **not required** of a conforming host, but documented
here as the recommended convention for verb dispatch and for a default
`:shutdown` handler, so that scripts written for different hosts look the
same.
This is not just prose — the reference host
([rust-ma-scheme-actor](https://github.com/bahner/rust-ma-scheme-actor))
ships it as an actual, runnable `stdlib.ma` source file, published to
IPFS like any other behaviour content, meant to be composed into an
entity's behaviour via an ordinary top-level
`(ma-include-ipfs #/ipfs/<stdlib-cid>)` form (§11.1) — not baked into the
Wasm binary, and not a host-level special case of any kind. A kind author
who wants this default simply puts that form first in every
`EntityNode.behaviour` (or template) they publish for that kind; one who
doesn't, leaves it out. Because expansion happens completely before
evaluation begins, a script's own later definitions simply rebind the
same names — there is no precedence rule to learn beyond ordinary lexical
scoping.

```scheme
(define (verb-of term) (if (pair? term) (car term) term))
(define (args-of term) (if (pair? term) (cdr term) '()))

(define (on-signal term)
  (when (equal? (verb-of term) :shutdown)
    (ma-save-state!)))

(define *methods* '())

(define (set-method! verb fn)
  (set! *methods* (cons (cons verb fn) *methods*)))

(define (find-method verb)
  (let loop ((table *methods*))
    (cond ((null? table) #f)
          ((equal? (car (car table)) verb) (cdr (car table)))
          (else (loop (cdr table))))))

(define (on-message msg)
  (let* ((term (msg-content msg))
         (verb (if (pair? term) (car term) term))
         (args (if (pair? term) (cdr term) '()))
         (fn (find-method verb)))
    (if fn
        (fn args msg)
        (ma-reply! msg (list :error "unknown verb")))))
```

A script using this convention writes verb handlers with `set-method!`
instead of hand-rolling its own `cond` inside `on-message`:

```scheme
(set-method! :look
  (lambda (args msg)
    (ma-reply! msg (list :ok (get-prop "description")))))
```

A script MAY instead define `on-message` directly for full custom dispatch
(e.g. pattern-matching without verb-based routing at all) — composing the
stdlib in only provides a default `:shutdown` handler inside `on-signal`;
it never forces a particular `on-message` shape on a script that defines
its own afterward (that later `define` simply overrides the stdlib's). A
script that wants to handle *other* signals too (e.g. `:start`) simply
defines its own `on-signal` afterward, which entirely replaces — not
merges with — the stdlib's (ordinary `define` rebinding, no special
signal-dispatch-table mechanism for `on-signal` itself in this stdlib,
unlike the verb table above for `on-message`).

## 16. Kind conformance

A kind that hosts ma-scheme (e.g. the reference `/ma/scheme/actor/0.0.1`,
optionally declaring a kind-level `behaviour` CID containing a standard
library source layer per
[ma-runtime-v1.md §11.2](ma-runtime-v1.md#112-kindnode-structure)) MUST:

- Declare `attributes.stateful: true` (an entity's state, §9, requires
  persistence — see the stateless/stateful distinction in
  [ma-runtime-v1.md §11.2](ma-runtime-v1.md#112-kindnode-structure); this
  has nothing to do with ma-scheme specifically, it is the ordinary
  stateful-kind requirement).
- Declare a shared `cid` (the ma-scheme interpreter binary, shared by
  every entity of this kind) — this kind is the "shared binary + source
  behaviour" case, never the "no shared `cid`, entity supplies its own
  binary" case (that's what a kind like `/ma/python/actor/0.0.1` is for,
  which has no scriptable behaviour at all).
- Export **exactly two** Wasm functions, `on_message` and `on_signal`
  (§14.2 in ma-runtime-v1.md) — for a kind whose whole purpose is hosting
  arbitrary, unknown-in-advance scripts, both exports MUST always be
  present at the Wasm level regardless of what any given script happens
  to define, since the host can't know in advance which signals a loaded
  script cares about. There is no `KindNode.api`/`lifecycle` field to
  populate — both have been removed (ma-runtime-v1.md §11.2); this kind's
  Wasm export list is simply always these two, unconditionally.
   - `on_signal` MUST decode the incoming term (§3) and:
      - For `:set-state`: decode the given bytes into the live state table
        (§3.1, §9) — unconditionally, whenever the signal fires.
      - For `:set-behaviour`: parse and evaluate the given text
        top-to-bottom into a fresh environment (§3.2) — unconditionally,
        whenever the signal fires.
      - For `:init`: evaluate the given payload as ma-scheme source
        top-to-bottom, in that same environment (§3.3) — unconditionally,
        whenever the signal fires.
      - For `:start`/`:shutdown` (and any signal this specification does
        not yet define): look up a script-defined `on-signal` function in
        the current environment and call it with the term if one is
        defined; otherwise do nothing (§3.4, §3.6). These three
        (`:set-state`/`:set-behaviour`/`:init`) MUST NOT be dispatched to a
        script-defined `on-signal` — they are handled entirely by the
        host's own fixed logic before any script lookup is even
        considered.
   - `on_message` MUST look up and call the script-defined `on-message`
     (§3.5) — this is the one export whose script-defined counterpart is
     never optional, and creation SHOULD fail if the resolved
     behaviour/payload never defines it.
- Require at least `ma_reply`, `ma_set_state`, `ma_send` in
  `host_functions`. A host MAY require additional host functions for
  features beyond this specification, but MUST NOT require fewer than
  these three — messaging/state persistence (§9, §10) are not optional.
  (`ma-log!`, §12, does not require a separate entry here — it uses
  Extism's own built-in logging, not a custom host function.) A kind
  whose scripts may use `ma-include-ipfs` (§11.1) additionally requires
  `ma_ipfs_include`. A host exposing the entity-management primitives of
  §10.1 additionally requires `ma_create_entity` and `ma_entity_exists`.
- Set `attributes.wasi: false` unless the implementation language actually
  requires WASI (e.g. a Python/CPython host does; a Rust
  `wasm32-unknown-unknown` host does not).

  Example (Rust host, no WASI needed):

```yaml
protocol: /ma/scheme/actor/0.0.1
cid: bafy...wasmbinary
type: extism
behaviour:
  "/": bafy...stdlib-source
attributes:
  stateful: true
  wasi: false
host_functions:
  - ma_reply
  - ma_set_state
  - ma_send
  - ma_ipfs_include
  - ma_create_entity
  - ma_entity_exists
```

## 17. Conformance

An implementation conforms to this specification if it:

1. Implements the two Wasm exports of §3 — `on_message` and `on_signal` —
   with `on_signal` handling the five signals in the documented order and
   conditionality: `:set-state` (only if prior state exists),
   `:set-behaviour` (only if a behaviour reference resolves), `:init`
   (host-mechanical, evaluates the payload as source, only at genesis),
   `:start` (script-definable via `on-signal`, every load), and
   `on_message` (required, every message). `:shutdown` (script-definable
   via `on-signal`, best-effort before teardown — no host fallback of any
   kind if undefined, §3.6) fires outside this load-time sequence, at
   teardown.
2. Implements the §6 CBOR mapping exactly, so script authors see identical
   data shapes regardless of host language.
3. Implements all special forms in §7 (including `let*`/`letrec`/`when`/
   `unless`, which are required, not optional sugar), all builtins in §8,
   the state table and its unprefixed props primitives (§9),
   `ma-get-config-key` and its required keys including `"behaviour"`
   (§9.1), both `ma-`-prefixed messaging primitives (§10),
   `ma-include-ipfs` exactly as constrained in §11.1 (top-level-only,
   literal-token-only argument), and `ma-log!` (§12).
4. Implements proper tail-call elimination for self-tail-calls per §7, and
   does not impose an artificial recursion-depth or step-count limit.
5. `ma-include-ipfs` resolutions are never cached across separate
   `:set-behaviour`/`:init` signal deliveries per §11.1 (each resolves
   fresh, from whatever the reference currently points at).
6. Follows the naming convention exactly: `ma-`-prefixed for every
   primitive that crosses into the runtime except the props primitives
   (§9, deliberately unprefixed), no prefix on core builtins/special
   forms.
7. Does not implement `eval`, or any include/dynamic-code-loading
   mechanism other than `ma-include-ipfs` exactly as specified in §11.1 —
   in particular, MUST NOT recognize it anywhere except as a direct
   top-level form, and MUST NOT accept anything but a literal
  `#/ipfs/<cid>`/`#/ipns/<key>` token as its argument.

   Conformance does not require implementing §15 (non-normative) or any
   builtins beyond §8 — a host MAY offer more, but scripts relying on more
   than this specification requires are not portable across conforming hosts.

## 18. Security considerations

- **No `eval`, no dynamic code loading from untrusted or computed data,
  anywhere in ma-scheme.** The one exception, `ma-include-ipfs` (§11.1),
  cannot be reached from `on-message` by construction (its expansion pass
  only ever inspects the top-level forms of the text delivered via the
  `:set-behaviour`/`:init` signals) and its argument must be a literal
  token fixed in the script's own source — never a string, never
  `msg-content`, never anything computed at runtime. There is no path
  from an incoming message (attacker-controlled by definition) to a
  reference actually being resolved: the complete set of content any
  script can ever cause to be loaded is fixed the moment its own source
  was written, by whoever wrote it. This is meaningfully different from
  the rejected "load whatever the remote party imposes" class of risk —
  no third party visiting or messaging an entity can choose what it
  includes; only the entity's own author, once, statically, can.
- **No ambient network/file access.** The only ways out of the sandbox are
  `ma-send!`, `ma-reply!`, `ma-create-actor`, `ma-entity-exists?` (§10),
  `ma-log!` (§12), and the fetch underlying `ma-include-ipfs` (§11.1,
  itself unreachable outside load time) — a
  script cannot open a raw socket, read a file, or otherwise reach
  anything the surrounding plugin ABI does not already expose.
- **No cross-entity state access.** `get-prop`/`set-prop!`/etc. (§9) only
  ever touch the calling entity's own state. There is no primitive that
  reads or writes another entity's state directly.
- **Behaviour is immutable from within ma-scheme — not a backdoor of any
  kind.** There is no primitive that changes an entity's own or any other
  entity's `EntityNode.behaviour` reference (§11) — that removal is
  deliberate (an earlier draft had `ma-set-behaviour-cid!`; it never
  shipped in a released version and has been removed from this draft
  entirely). The only way behaviour changes at all is ordinary external
  CRUD followed by a reload, or an `/ipns/<key>`-backed `ma-include-ipfs`
  reference resolving to updated content on the entity's next reload
  (§11.1) — neither is reachable from `on-message`.
- **A misbehaving script cannot corrupt the entity.** Per-call error
  containment (§13) means a bad incoming message can, at worst, produce an
  error reply — never a crashed entity, never lost state beyond whatever
  that one call had not yet saved.
- **No artificial resource limits, deliberately (§14).** The tail-call
  guarantee (§7) means an infinite loop just spins, bounded only by the
  surrounding Wasm sandbox's own execution timeout — that timeout, not a
  scripting-level step counter, is the actual backstop of last resort.

## 19. References

- [zscheme-v1.md](../zscheme/zscheme-v1.md)
- [ma-runtime-v1.md](ma-runtime-v1.md)
- [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md)
- [ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md)
- [ma-acl-v1.md](../core/ma-acl-v1.md)
