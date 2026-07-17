# ma-standard-actors-v1 — Standard Runtime Actor Interfaces

**Status:** Draft  
**Version:** 0.1.0  
**Date:** 31 May 2026

---

## Abstract

This document specifies the actor-to-actor messaging interfaces for two
actors that 間 runtime implementations SHOULD provide: `#root` and
`#scheduler`. These actors are pervasive enough across conforming runtimes
that standardising their verb vocabulary and reply terms enables portable
plugins to be written once and deployed on any compliant runtime.

The fragment names `root` and `scheduler` are **reserved** across
all 間 runtimes. A runtime MUST NOT use these names for user-defined entities.

This specification defines only the **wire protocol** — what terms an actor
sends to each of these actors, and what terms it receives back. Implementation
language, backing store, and internal host-function names are
implementation-specific and outside the scope of this document.

Companion documents:

- [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md) — RPC message-type definitions
  and term format
- [ma-runtime-v1.md](ma-runtime-v1.md) — runtime specification (§16 Reserved
  names registry)
- [ma-schedules-v1.md](ma-schedules-v1.md) — static schedule format

---

## Table of contents

1. [Notational conventions](#1-notational-conventions)
2. [`#root` — entity lifecycle manager](#2-root--entity-lifecycle-manager)
3. [`#scheduler` — dynamic schedule registration](#3-scheduler--dynamic-schedule-registration)
4. [Reserved fragment names](#4-reserved-fragment-names)

---

## 1. Notational conventions

All content exchanged between actors is CBOR-encoded per
[ma-rpc-service-v1.md §3](../core/ma-rpc-service-v1.md).

- An **atom** is a CBOR text string beginning with `:` (e.g. `:ok`, `:ping`).
- A **tuple** is a CBOR array whose first element is an atom
  (e.g. `[":create", kind, cid]`).
- Verb descriptions use the form `verb_atom` for atoms and
  `[verb_atom, arg1, arg2, …]` for tuples.
- `→` separates a request from its reply.
- Arguments in `<angle brackets>` are required; arguments in `[square
  brackets]` are optional.
- All reply terms are returned as `application/x-ma-rpc-reply` messages with
  `reply_to` set to the originating message ID.

---

## 2. `#root` — entity lifecycle manager

### 2.1 Purpose

`#root` is the sole entry point for creating and deleting runtime entities.
All other actors MUST send entity lifecycle requests through `#root`. A
runtime MAY reject `ma_create_entity` and `ma_delete_entity` calls from any
entity other than its own `#root` implementation.

`#root` is **fire-and-forget from the caller's side** — it operates on a
fire-and-forget basis. Replies are delivered asynchronously as normal RPC
reply messages.

### 2.2 Verbs

#### 2.2.1 `:ping`

Liveness check.

```
:ping  →  :pong
```

#### 2.2.2 `:create`

Create a new entity on this runtime.

```
[":create", <kind>]                              →  [":ok", <fragment>]
[":create", <kind>, <label>]                     →  [":ok", [<fragment>, <label>]]
[":create", <kind>, <label>, <init>]             →  [":ok", [<fragment>, <label>]]
```

| Argument | Type | Description |
|----------|------|-------------|
| `kind` | text | Protocol ID of the kind, e.g. `/ma/counter/0.0.1` |
| `label` | text | Optional human-readable label; echoed back in the reply |
| `init` | any | Optional, opaque creation payload delivered verbatim via the kind's `:init` signal if it handles one (see [ma-runtime-v1.md §14.2.1](ma-runtime-v1.md#1421-creation-payload)). `#root` does not parse or validate it — the kind decides whether it's required, and its shape is entirely kind-defined (e.g. a snippet seeding initial state, for a kind whose behaviour is scriptable — see [ma-scheme-v1.md §3.3](ma-scheme-v1.md#33-the-init-signal--host-mechanical-genesis-only)). Passing it for a kind that ignores `:init` is simply ignored. |

On success the runtime assigns a `fragment` — the bare name under which the
new entity is reachable at `did:ma:<runtime>#<fragment>`. The caller receives
the assigned fragment as confirmation. If `init` is present, it has already
run (synchronously, before this reply is sent — see the atomicity guarantee
in [ma-runtime-v1.md §14.2](ma-runtime-v1.md#142-plugin-abi)) by the time the
caller sees `:ok`.

On failure: `[":error", <reason>]` — including if the kind requires an
`init` payload and none was supplied, or if handling `:init` itself errored.

#### 2.2.3 `:delete`

Delete an existing entity.

```
[":delete", <fragment>]  →  :ok
```

| Argument | Type | Description |
|----------|------|-------------|
| `fragment` | text | Bare entity fragment name (no `#` prefix) |

On failure: `[":error", <reason>]`

### 2.3 ACL

Any actor MAY send `:create` and `:delete` to `#root`. This follows directly
from Hewitt's Actor Model: creating new actors is a fundamental capability
available to all actors, not a privilege reserved for an owner.

The RECOMMENDED default ACL for `#root` uses the `"#"` local-actor principal
(see [ma-acl-v1.md §3](../core/ma-acl-v1.md)) to allow all entities on the same
runtime while keeping remote peers out:

```yaml
"#":  ["*"]   # all local actors: unrestricted
"*":           # remote peers: explicit deny
```

The operator MAY open `:create` to remote peers or restrict it further, but
SHOULD NOT do so by default.

---

## 3. `#scheduler` — dynamic schedule registration

### 3.1 Purpose

Wasm modules have no access to timers or system clocks — a sandboxed entity
plugin cannot wake itself up. All timed dispatch must originate from native
OS code outside the Wasm sandbox. `#scheduler` is the standardised native
actor that holds a real clock and delivers messages to entities at requested
times.

From an entity's point of view, a scheduled dispatch is an ordinary incoming
message with `msg.from` set to `<runtime>#scheduler`. The entity has no
internal clock and no way to distinguish a scheduled call from any other.

`#scheduler` itself is a **native (non-Wasm) system actor**; it cannot be
replaced by a plugin. It accepts schedule-registration messages from any
entity on the same runtime, registers the job with the OS scheduler, and
delivers the verb as a synthetic message when the time arrives.

`#scheduler` lets any entity on the same runtime register timed verb
dispatches — recurring (`:cron`, `:interval`), one-shot (`:at`), or random
re-trigger (`:random`). Schedules do not survive a runtime restart, so
registration MUST happen on **every** load, not just the first — see the
per-load lifecycle signal in [ma-runtime-v1.md §14.2](ma-runtime-v1.md#142-plugin-abi)
(e.g. the `:start` signal for a kind hosting ma-scheme, [ma-scheme-v1.md §3.4](ma-scheme-v1.md#34-the-start-signal--script-definable-every-load)).

### 3.2 Verbs

All schedule verbs share a common 4-element prefix. Extra positional
arguments (position 5+) are appended to the dispatched verb as inline args.

```
[<type>, <spec>, <target>, <verb_or_tuple>, extra_args…]  →  :ok
```

| Position | Type | Description |
|----------|------|-------------|
| 0 | atom | Schedule type: `:cron`, `:interval`, `:at`, or `:random` |
| 1 | text or integer | Type-specific spec (see §3.3) |
| 2 | text | Target fragment or full DID-URL (`did:ma:…#name`) |
| 3 | atom or array | Verb atom (`:tick`) or tuple (`[":grow", "plants+=1"]`) to dispatch |
| 4+ | any | Extra positional args appended to the dispatched verb |

On parse error: `[":error", <reason>]`

#### 3.2.1 `:cron`

Fires on a recurring cron schedule indefinitely.

```
[":cron", <spec>, <target>, <verb>]  →  :ok
```

`spec` is a 6-field cron string (`"sec min hour day month weekday"`) or an
English schedule string. See [ma-schedules-v1.md §4](ma-schedules-v1.md).

#### 3.2.2 `:interval`

Fires every N seconds indefinitely.

```
[":interval", <duration>, <target>, <verb>]  →  :ok
```

`duration` is a compact duration string (e.g. `"30m"`, `"1h"`). See
[ma-schedules-v1.md §3](ma-schedules-v1.md).

#### 3.2.3 `:at`

Fires once at a specific Unix timestamp (milliseconds).

```
[":at", <timestamp_ms>, <target>, <verb>]  →  :ok
```

`timestamp_ms` is a CBOR integer. If the timestamp is in the past the verb
fires immediately.

#### 3.2.4 `:random`

Fires after a uniform random delay between 1 and `max_secs` seconds, then
self-reschedules.

```
[":random", <max_secs>, <target>, <verb>]  →  :ok
```

`max_secs` is a CBOR integer ≥ 1.

### 3.3 Dispatch

When a schedule fires, the runtime sends a synthetic message to the target
entity containing the registered verb as CBOR content. The dispatch bypasses
all ACL checks — the runtime is the trusted caller.

### 3.4 ACL

`#scheduler` SHOULD restrict registration to entities on the same runtime
(local origin). Remote peers SHOULD NOT be able to register schedules unless
the operator explicitly opens access.

---

## 4. Reserved fragment names

The following fragment names are reserved across all 間 runtime
implementations. They MUST NOT be used for user-defined entities.

| Fragment | Actor |
|----------|-------|
| `root` | Entity lifecycle manager (§2) |
| `scheduler` | Dynamic schedule registration (§3) |

These names are also listed in the normative reserved-names registry at
[ma-runtime-v1.md §16](ma-runtime-v1.md).
