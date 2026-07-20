# ma-house-v1 — House (Placement Authority) Actor Interface

**Status:** Candidate Recommendation
**Version:** 1.0.0
**Date:** 20 July 2026

---

## Abstract

This document specifies the `#house` actor: the single placement authority
for a 間 runtime. It tracks a containment tree of agents and things, manages
a ticket-based two-phase entry contract for agents, and provides read-only
queries for navigation.

`#house` is a **standard runtime actor**. Implementations SHOULD provide it
as an Extism plugin loaded at startup under the fragment name `house`.

Companion documents:

- [ma-avatar-v1.md](ma-avatar-v1.md) — avatar identity (used internally by
  `#house` to derive `avatar_id` from agent DIDs)
- [ma-standard-actors-v1.md](ma-standard-actors-v1.md) — standard actor
  registry
- [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md) — RPC term format

---

## Table of contents

1. [Placement model](#1-placement-model)
2. [Fragment name and protocol](#2-fragment-name-and-protocol)
3. [State](#3-state)
4. [Agent entry protocol](#4-agent-entry-protocol)
5. [Verbs — open to all callers](#5-verbs--open-to-all-callers)
6. [Verbs — restricted callers](#6-verbs--restricted-callers)
7. [Verbs — runtime-internal only](#7-verbs--runtime-internal-only)
8. [Ticket lifecycle](#8-ticket-lifecycle)
9. [Error terms](#9-error-terms)

---

## 1. Placement model

Every agent and thing on the runtime has exactly zero or one **container**.
The relationship is tracked in two complementary maps:

```
fwd: { subject_id → [container, type] }
rev: { container  → [[subject_id, type], …] }
```

- `subject_id` is an `avatar_id` (for agents) or an arbitrary thing id.
- `container` is a fragment identifier (e.g. `"#room"`) or a full
  DID-URL fragment.
- `type` is `"agent"` or `"thing"`.

Agents enter containers through the ticket protocol (§4). Things are placed
unilaterally by runtime-internal actors.

---

## 2. Fragment name and protocol

| Property | Value |
|---|---|
| Reserved fragment | `house` |
| Service protocol | `/ma/rpc/0.0.1` |
| Handle function | `on_message` |

---

## 3. State

```
STATE = {
  "fwd":     { <subject_id>: [<container>, <type>] },
  "rev":     { <container>:  [[<subject_id>, <type>], …] },
  "tickets": { <ticket_id>:  [<container_did>, <avatar_id>, <expires_at_secs>] }
}
```

State is persisted via `ma_set_state` after every write.

---

## 4. Agent entry protocol

Entry is a **two-phase commit** mediated by `#house`:

```
Phase 1 — Agent requests entry:
  Agent  → #house:enter <container_did>
  #house → [:ok, ticket_id]

Phase 2 — Container finalises:
  Agent  → @container:enter <ticket_id>     (normal actor message)
  Room   → #house:admit <ticket_id>
  #house → [:ok, avatar_id]                 (room gets avatar_id for announcements)
  Room   → Agent [:ok, ...]                 (room's own reply to the agent)
```

The container MAY instead reject the ticket:

```
  Room   → #house:reject <ticket_id>
  #house → [:ok, null]                      (idempotent)
```

Tickets expire after 60 seconds if not presented.

---

## 5. Verbs — open to all callers

### 5.1 `:enter <container_did>`

Phase-1 entry: agent requests to enter a container.

`#house` calls `#avatar:id` internally to compute the caller's `avatar_id`
from `msg.from`. The DID is never stored.

```
→ [:ok, ticket_id]
→ [:error, reason]
```

`ticket_id` is a short random string prefixed `"ticket-"`.

### 5.2 `:parent`

Return the container of the caller (by `msg.from`).

```
→ [:ok, container_fragment]
→ [:ok, null]    ; caller has no container
```

### 5.3 `:children`

Return the direct contents of the caller's own container.

```
→ [:ok, [[subject_id, type], …]]
→ [:ok, []]      ; empty
```

### 5.4 `:count`

Return the total number of placed subjects (agents + things).

```
→ [:ok, integer]
```

---

## 6. Verbs — restricted callers

### 6.1 `:admit <ticket_id>`

Phase-2 entry: the container presents the ticket to finalise placement.

The caller **must** be the container named in the ticket (verified by
comparing `msg.from` fragment to the stored `container_did`). The ticket is
consumed and the agent's `avatar_id` is placed in the container.

```
→ [:ok, avatar_id]       ; placement succeeded
→ [:error, reason]       ; wrong caller, unknown ticket, or expired
```

`#house` also calls `#avatar:register <avatar_id> <sender_did>` to store
the delivery DID for internal routing.

### 6.2 `:reject <ticket_id>`

Container refuses the ticket without placing the agent.

The caller must be the container named in the ticket (same check as
`:admit`). Idempotent — returns `:ok` if the ticket is already gone.

```
→ [:ok, null]
→ [:error, reason]
```

### 6.3 `:release <subject_id>`

Remove a subject from its container. Only the subject itself or its current
container may call this.

```
→ [:ok, null]
→ [:error, reason]
```

---

## 7. Verbs — runtime-internal only

Callers whose `from` field contains `#` are considered runtime-internal.

### 7.1 `:place <subject_id> [type]`

Unilateral placement for things. The **caller** becomes the container.
`type` defaults to `"thing"`.

```
→ [:ok, null]
→ [:error, reason]
```

### 7.2 `:contents <container>`

Return all direct contents of any container.

```
→ [:ok, [[subject_id, type], …]]
```

### 7.3 `:where <subject_id>`

Return the container of any subject.

```
→ [:ok, [container, type]]
→ [:ok, null]    ; not placed
```

### 7.4 `:descendants <container>`

Return all subjects recursively contained under `container` (full subtree).

```
→ [:ok, [subject_id, …]]
```

---

## 8. Ticket lifecycle

| Property | Value |
|---|---|
| TTL | 60 seconds from `:enter` |
| ID format | `"ticket-"` + 10 random alphanumeric characters |
| Invalidation | Consumed on `:admit`; removed on `:reject`; expires naturally |
| Reuse | Not permitted — each ticket is single-use |

Expired tickets are checked at `:admit` time. A background sweep is not
required; the ticket map is bounded by the TTL.

---

## 9. Error terms

| Term | Meaning |
|---|---|
| `[:error, "house :enter requires container_did"]` | `:enter` called with no argument |
| `[:error, "house :enter: avatar id computation failed: …"]` | `#avatar:id` returned an error |
| `[:error, "house :admit requires ticket_id"]` | `:admit` called with no argument |
| `[:error, "house :admit: unknown or expired ticket '…'"]` | Ticket not found |
| `[:error, "house :admit: only the intended container may admit"]` | Caller mismatch |
| `[:error, "house :admit: ticket '…' has expired"]` | Ticket past TTL |
| `[:error, "house :reject requires ticket_id"]` | `:reject` called with no argument |
| `[:error, "house :place: only runtime-internal entities may place"]` | External `:place` |
| `[:error, "house :release requires subject_id"]` | `:release` called with no argument |
| `[:error, "house :release: only the subject or its container may release"]` | Unauthorized release |
| `[:error, "house :contents requires container id"]` | `:contents` with no argument |
| `[:error, "house :where requires subject_id"]` | `:where` with no argument |
| `[:error, "house :descendants requires container id"]` | `:descendants` with no argument |
| `[:error, "house: unknown verb: …"]` | Unrecognised verb |
