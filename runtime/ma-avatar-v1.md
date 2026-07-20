# ma-avatar-v1 — Avatar Actor Interface

**Status:** Candidate Recommendation
**Version:** 1.0.0
**Date:** 20 July 2026

---

## Abstract

This document specifies the `#avatar` actor: a per-runtime privacy-preserving
identity layer that maps sender DIDs to short, pseudonymous `avatar_id`s and
optional display names.

`#avatar` is a **standard runtime actor**. Implementations SHOULD provide it
as an Extism plugin loaded at startup under the fragment name `avatar`.

Companion documents:

- [ma-house-v1.md](ma-house-v1.md) — placement authority (depends on
  `#avatar` for agent identification)
- [ma-standard-actors-v1.md](ma-standard-actors-v1.md) — standard actor
  registry
- [ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md) — RPC term format

---

## Table of contents

1. [Privacy model](#1-privacy-model)
2. [Fragment name and protocol](#2-fragment-name-and-protocol)
3. [State](#3-state)
4. [Verbs — open to all callers](#4-verbs--open-to-all-callers)
5. [Verbs — caller-identity verbs](#5-verbs--caller-identity-verbs)
6. [Verbs — runtime-internal only](#6-verbs--runtime-internal-only)
7. [Error terms](#7-error-terms)

---

## 1. Privacy model

`#avatar` never stores a caller's DID. Instead it derives a
**`avatar_id`** — a short hex string — using a keyed hash:

```
avatar_id = blake3_keyed(runtime_ipns_key_derived_secret, caller_did)[:12].hex
```

Properties:

- **Deterministic per runtime:** the same DID always produces the same
  `avatar_id` on a given runtime.
- **Cross-world opaque:** a different runtime (with a different
  `runtime_ipns_key`) produces a different `avatar_id` for the same DID.
- **Non-reversible:** the underlying DID cannot be recovered from the
  `avatar_id` without the runtime secret.

Only `avatar_id → { name }` mappings are persisted in state.

---

## 2. Fragment name and protocol

| Property | Value |
|---|---|
| Reserved fragment | `avatar` |
| Service protocol | `/ma/rpc/0.0.1` |
| Handle function | `on_message` |

---

## 3. State

```
STATE = {
  "avatars": {
    <avatar_id>: { "name": <string | null> }
  }
}
```

State is persisted via `ma_set_state` after every write. DIDs are never
stored.

---

## 4. Verbs — open to all callers

### 4.1 `:alias <avatar_id>`

Look up the display name for a known `avatar_id`.

```
→ [:ok, name_string]
→ [:ok, null]          ; if registered but no name set
→ [:error, reason]
```

### 4.2 `:ls`

List all registered avatars (no DIDs returned).

```
→ [:ok, [[avatar_id, name], …]]
```

### 4.3 `:count`

Return the number of registered avatars.

```
→ [:ok, integer]
```

---

## 5. Verbs — caller-identity verbs

These verbs operate on the **caller's own** identity. The `avatar_id` is
computed from `msg.from` — the caller never needs to know their own
`avatar_id` in advance.

### 5.1 `:claim <name>`

Register or update the caller's display name.

```
→ [:ok, avatar_id]
→ [:error, reason]
```

The returned `avatar_id` is the caller's pseudonymous identity on this
runtime.

### 5.2 `:unclaim`

Remove the caller's display name registration.

```
→ [:ok, null]
→ [:error, reason]
```

---

## 6. Verbs — runtime-internal only

These verbs are only accessible to other runtime entities (callers whose
`from` field contains `#`, indicating a fragment-addressed local actor).

### 6.1 `:id <did>`

Compute the `avatar_id` for any DID without registering anything.

```
→ [:ok, avatar_id]
→ [:error, reason]
```

Used by `#house` to derive `avatar_id` from the entering agent's DID.

### 6.2 `:avatar <did>`

Return `[avatar_id, name]` for a DID.

```
→ [:ok, [avatar_id, name_or_null]]
→ [:error, reason]
```

### 6.3 `:register <avatar_id> <did>`

Called by `#house` at `:admit` time to store the delivery DID alongside
the `avatar_id` (for internal routing purposes only — the DID is never
returned to external callers).

```
→ [:ok, null]
→ [:error, reason]
```

---

## 7. Error terms

| Term | Meaning |
|---|---|
| `[:error, "avatar :claim requires a name"]` | `:claim` called with no argument |
| `[:error, "avatar :alias requires avatar_id"]` | `:alias` called with no argument |
| `[:error, "avatar :register: runtime-internal only"]` | External caller attempted `:register` |
| `[:error, "avatar :id: runtime-internal only"]` | External caller attempted `:id` |
