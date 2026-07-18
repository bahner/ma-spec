# ma-schedules-v1 — Entity Schedule Specification

**Status:** Draft  
**Version:** 0.2.0  
**Date:** 31 May 2026

---

## Abstract

This document specifies how 間 entity plugins register scheduled verb
dispatches — recurring or one-shot calls that fire autonomously without an
incoming message.

**Architectural constraint:** Wasm modules have no access to timers, clocks,
or any OS-level scheduling primitives. An entity plugin cannot wake itself
up. All timed dispatch must therefore come from **outside** the Wasm sandbox
— from native runtime code that holds a real clock and delivers a message to
the entity at the appropriate time. `#scheduler` is the standardised
interface to that native capability.

From the entity's perspective, a scheduled invocation is indistinguishable
from any other incoming message: it arrives as a normal `on_message` input
with `msg.from` set to `<runtime>#scheduler`. The entity
has no internal clock and no knowledge that the call was timer-triggered.

Schedules are registered **dynamically at runtime** by sending a message to
the `#scheduler` system actor. There is no static schedule declaration in
`EntityNode`. A plugin that needs a schedule registers it while handling
the `:start` signal (§6 below; fires on every load, per
[ma-runtime-v1.md §14.2](ma-runtime-v1.md#142-plugin-abi)) on every startup.

Companion documents:

- [ma-runtime-v1.md](ma-runtime-v1.md) — runtime specification (§14 Entities)
- [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md) — RPC message-type definitions
- [ma-standard-actors-v1.md](ma-standard-actors-v1.md) — `#scheduler` wire
  interface reference

---

## Table of contents

1. [Schedule types](#1-schedule-types)
2. [Registering a schedule](#2-registering-a-schedule)
3. [Duration string format](#3-duration-string-format)
4. [Cron spec format](#4-cron-spec-format)
5. [Dispatch semantics](#5-dispatch-semantics)
6. [Lifecycle](#6-lifecycle)
7. [Security](#7-security)
8. [Examples](#8-examples)

---

## 1. Schedule types

Four schedule types are defined:

| Type | Spec argument | Behaviour |
|------|---------------|-----------|
| `:cron` | 6-field cron string or English spec | Fires on schedule indefinitely. |
| `:interval` | Duration string | Fires every N seconds indefinitely. |
| `:at` | Unix timestamp (ms, integer) | Fires once; if in the past, fires immediately. |
| `:random` | `max_secs` (integer ≥ 1) | Fires after a random 1–N second delay, then self-reschedules. |

---

## 2. Registering a schedule

A plugin registers a schedule by sending a CBOR message to
`did:ma:<runtime>#scheduler` using `ma_send`. The call is fire-and-forget;
`#scheduler` replies `:ok` immediately and registers the job asynchronously.

### 2.1 Wire format

The message content is a CBOR array:

```
[<type>, <spec>, <target>, <verb_or_tuple>, extra_args…]
```

| Position | Type | Description |
|----------|------|-------------|
| 0 | atom | Schedule type: `:cron`, `:interval`, `:at`, or `:random` |
| 1 | text or integer | Type-specific spec (see §1) |
| 2 | text | Target fragment (bare name `"myfragment"`) or full DID-URL |
| 3 | atom or array | Verb atom (e.g. `":tick"`) or tuple (e.g. `[":grow", "plants+=1"]`) |
| 4+ | any | Optional extra positional args, appended to the dispatched verb |

### 2.2 The right place to register: the `:start` signal

Schedules do not survive a runtime restart. A plugin MUST re-register all
needed schedules while handling the `:start` signal (§6) — fired on
**every** load, not just the entity's first — every startup. Registering
in response to `:start` (not the genesis-only `:init`) is the canonical
pattern.

A plugin MAY also register new schedules from `on_message`
in response to an incoming message — for example to schedule a one-shot
`:at` job for a future event.

### 2.3 Targeting another entity

The `target` field (position 2) addresses which entity receives the dispatch
when the schedule fires. It SHOULD be a full DID-URL
(`did:ma:<runtime>#fragment`) to be unambiguous. A bare fragment name is
also accepted and resolved relative to the same runtime.

An entity MAY schedule verbs on **itself** by passing its own fragment as
the target. It MAY also schedule verbs on **other entities** on the same
runtime, subject to the target entity's ACL.

---

## 3. Duration string format

The `:interval` type uses a compact human-readable duration string.

### 3.1 Grammar

```abnf
duration    = 1*unit-pair
unit-pair   = 1*DIGIT unit
unit        = "s" / "m" / "h" / "d"
```

| Suffix | Meaning | Seconds |
|--------|---------|---------|
| `s` | seconds | 1 |
| `m` | minutes | 60 |
| `h` | hours | 3 600 |
| `d` | days | 86 400 |

Units MAY be combined in descending order. The total duration is the sum of
all unit-pairs.

### 3.2 Examples

| String | Duration |
|--------|----------|
| `"30s"` | 30 seconds |
| `"5m"` | 5 minutes |
| `"1h"` | 1 hour |
| `"1d"` | 24 hours |
| `"1h30m"` | 90 minutes |
| `"2d12h"` | 60 hours |

### 3.3 Constraints

- Total duration MUST be greater than zero.
- A string ending with digits but no unit suffix is a parse error.
- An unknown unit character is a parse error.
- On parse error, `#scheduler` MUST reply `[":error", <reason>]`.

---

## 4. Cron spec format

### 4.1 6-field cron

```
<sec> <min> <hour> <day-of-month> <month> <day-of-week>
```

| Field | Values |
|-------|--------|
| `sec` | 0–59 |
| `min` | 0–59 |
| `hour` | 0–23 |
| `day` | 1–31 |
| `month` | 1–12 |
| `weekday` | 0–7 (0 and 7 = Sunday) |

Standard cron wildcards apply: `*`, `,`, `-`, `/`.

| Spec | Fires |
|------|-------|
| `"0 0 * * * *"` | every hour on the hour |
| `"0 */15 * * * *"` | every 15 minutes |
| `"0 0 8 * * 1-5"` | weekdays at 08:00:00 |

### 4.2 English spec

Natural-language schedules are also accepted:

| String | Equivalent cron |
|--------|----------------|
| `"every hour"` | `"0 0 * * * *"` |
| `"every minute"` | `"0 * * * * *"` |
| `"every day"` | `"0 0 0 * * *"` |

Support for English specs is implementation-defined.

---

## 5. Dispatch semantics

### 5.1 Invocation

When a schedule fires, the runtime constructs a synthetic message to the
target entity. The message has the following fields:

| Field | Value |
|-------|-------|
| `msg.from` | `"<runtime-did>#scheduler"` |
| `msg.to` | `"<runtime-did>#<fragment>"` |
| `msg.reply_to` | `null` |
| `msg.content_type` | `"application/vnd.ma.term"` |
| `msg.content` | CBOR-encoded verb (atom or array) |

The content is built from position 3 (verb) and positions 4+ (extra args)
of the registration tuple:

- If no extra args: content is the verb atom, e.g. `":tick"`.
- If extra args are present: content is a CBOR array with the verb as first
  element followed by the extra args.

### 5.2 ACL

Scheduled dispatch **bypasses all ACL checks**. The runtime is the trusted
caller. The operator is responsible for ensuring that registered schedules
only invoke verbs appropriate for the target entity.

### 5.3 State persistence

State changes made during scheduled dispatch are persisted to IPFS normally.

### 5.4 Random rescheduling

For `:random` schedules, the runtime fires the job after a uniform random
delay in `[1, max_secs]` seconds. After the call returns a new independent
job is registered with a fresh random delay. The cycle continues
indefinitely.

---

## 6. Lifecycle

Schedules are in-memory only and are not persisted to IPFS or the manifest.

**Restart as garbage collection.** When the runtime stops, all registered
schedules are discarded. On the next startup, each entity receives the
`:start` signal again and re-registers exactly the schedules that entity
currently needs. This means a restart is a natural GC pass: orphaned
schedules from deleted or replaced plugins simply never come back, and
there is no stale schedule state to clean up manually.

- **Restart**: schedules are lost. Each entity re-registers when it
  handles `:start` again. Only schedules that handling registers will be
  active.
- **Entity deletion**: existing jobs for a deleted entity are not
  automatically cancelled. They become no-ops because the entity lookup
  fails at dispatch time. A runtime restart clears them completely.
- **Plugin replacement**: replacing an entity's Wasm and restarting causes
  the new code's `:start` handling to run, registering whatever schedules
  the new code declares. Old schedules from the previous version do not
  carry over.

---

## 7. Security

### 7.1 ACL bypass

Scheduled dispatch bypasses all ACL checks (§5.2). Schedules are authorised
solely by the `#scheduler` ACL — only actors permitted to send to
`#scheduler` can register schedules. The operator controls this via the
`scheduler` ACL entry in the root manifest.

The RECOMMENDED default ACL for `#scheduler` allows only local entities
(same runtime DID prefix) and denies all remote peers.

### 7.2 Resource exhaustion

A plugin that registers schedules in a tight loop can flood the scheduler.
Implementations SHOULD impose a per-entity limit on the number of live
scheduled jobs.

---

## 8. Examples

### 8.1 Clock entity — tick every minute, chime every hour

While handling the `:start` signal, the plugin sends two messages to
`#scheduler`:

```cbor
; Register :tick every minute (sent to #scheduler)
[":interval", "1m", "did:ma:<runtime>#clock", ":tick"]

; Register :chime every hour on the hour
[":cron", "0 0 * * * *", "did:ma:<runtime>#clock", ":chime"]
```

### 8.2 Dog entity — scratch randomly, wake at a specific time

```cbor
; Scratch after 1–300 random seconds, then reschedule
[":random", 300, "did:ma:<runtime>#dog", ":scratch", "left_ear"]

; Wake once at a specific Unix timestamp (ms)
[":at", 1748700000000, "did:ma:<runtime>#dog", ":wake"]
```

### 8.3 Garden entity — grow with arguments every 30 minutes

```cbor
[":interval", "30m", "did:ma:<runtime>#garden", [":grow", "plants+=1"]]
```

### 8.4 Scheduling a verb on a different entity

An orchestrator entity can schedule work on another entity:

```cbor
; From an orchestrator's :start signal handling, schedule a daily digest on another entity
[":cron", "0 0 6 * * *", "did:ma:<runtime>#digest", ":flush"]
```
