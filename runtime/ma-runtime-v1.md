# ma-runtime-v1 — 間 Runtime Specification

**Status:** Draft  
**Version:** 0.3.0  
**Date:** 7 July 2026

---

## Abstract

A 間 (*ma*) runtime is an autonomous, content-addressed actor host. It
maintains a **runtime manifest** on IPFS, optionally registers any of three
iroh QUIC services (RPC, inbox, and IPFS publishing), and manages a set of
**entity plugins** —
Wasm modules compiled from any Extism-compatible language. Each entity is
addressable by a DID-URL fragment derived from its position in the IPLD
manifest tree.

This document is the normative specification for conforming 間 runtime
implementations. Companion documents:

- [ma-runtime-guide-v1.md](ma-runtime-guide-v1.md) — prose guide for
  operators and developers
- [ma-schedules-v1.md](ma-schedules-v1.md) — schedule registration via `#scheduler`
- [ma-standard-actors-v1.md](ma-standard-actors-v1.md) — standard actor interfaces (`#root`, `#scheduler`)

---

## Table of contents

1. [Introduction](#1-introduction)
2. [Overview](#2-overview)
3. [Identity integration](#3-identity-integration)
4. [Runtime manifest](#4-runtime-manifest)
7. [RPC](#7-rpc)
8. [IPFS publishing service](#8-ipfs-publishing-service)
9. [CRUD interface](#9-crud-interface)
10. [Fragment routing](#10-fragment-routing)
11. [Kinds management](#11-kinds-management)
12. [Config management](#12-config-management)
13. [ACL and capabilities model](#13-acl-and-capabilities-model)
14. [Entities](#14-entities)
15. [Development](#15-development)
16. [Reserved names registry](#16-reserved-names-registry)

---

## 1. Introduction

### 1.1 Scope

This specification defines the conformance requirements for a 間 runtime
implementation. It covers:

- the structure and semantics of the **runtime manifest** (IPLD DAG-CBOR);
- the three **transport services** an implementation MAY register;
- the **`/ma/crud/0.0.1` service** for structured CRUD operations (see
  [ma-crud-service-v1.md](ma-crud-service-v1.md));
- the **entity plugin ABI** and kind system;
- the **ACL and capabilities model** for access control;
- the registry of **reserved names**.

This specification is language- and framework-agnostic. The reference
implementation is `ma-runtime` (Rust / Tokio), but conforming implementations
may be written in any language.

### 1.2 Normative language

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**,
**SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this
document are to be interpreted as described in [RFC 2119].

### 1.3 Terminology

| Term | Definition |
|------|-----------|
| **Runtime** | A conforming implementation of this specification |
| **Manifest** | The IPLD DAG-CBOR object at the root of the runtime's IPLD tree |
| **Entity** | An Extism Wasm plugin registered in the manifest |
| **Kind** | A descriptor that defines a plugin's ABI, exports, and host functions |
| **Fragment** | The part of a DID-URL after `#`; identifies an entity by its globally unique name in the `entities` map |
| **
---

## 2. Overview

### 2.1 Architecture

A 間 runtime consists of four cooperating subsystems:

```
 ┌───────────────────────────────────────────────────────────┐
 │  iroh QUIC endpoint (own DID:  did:ma:<ipns>)             │
 │                                                           │
 │  ┌─────────────────┐  ┌──────────┐  ┌──────────────────┐ │
 │  │ /ma/rpc/0.0.1   │  │ /ma/     │  │ /ma/ipfs/0.0.1   │ │
 │  │ (:ping, entity  │  │ inbox/   │  │ (delegated IPNS  │ │
 │  │  verb dispatch) │  │ 0.0.1    │  │  publishing)     │ │
 │  └────────┬────────┘  └────┬─────┘  └──────────────────┘ │
 │           │                │                              │
 │  ┌────────▼────────────────▼──────────────────────────┐   │
 │  │  Manifest (IPLD DAG-CBOR root on IPFS / IPNS)      │   │
 │  │  ├── entities:  flat name → EntityNode CID         │   │
 │  │  │     fortune: { "/": "<cid>" }                   │   │
 │  │  │     rms:     { "/": "<cid>" }                   │   │
 │  │  ├── kinds:     flat protocol-ID → KindNode CID    │   │
 │  │  ├── config: { … }                                 │   │
 │  │  └── acl: { "/": "<cid>" }                         │   │
 │  └──────

### 2.2 Key concepts

- **Content-addressed manifest.** All runtime state is a DAG of IPLD objects
  stored on IPFS. The manifest root CID is the single source of truth. The
  runtime's DID document contains an IPLD link to the current root.

- **Three optional services.** A conforming runtime MAY register any subset
  of three iroh QUIC services: `/ma/rpc/0.0.1`, `/ma/inbox/0.0.1`, and
  `/ma/ipfs/0.0.1`. Each is independently OPTIONAL; a runtime that registers
  none of them is unreachable over the network but is still conforming
  (e.g. while shut down or in maintenance mode). See §6.

- **Entity plugins.** Each entity is an Extism Wasm module stored on IPFS and
  referenced from the manifest via an IPLD link. Entities are addressed by DID
  fragment (§10). The runtime loads plugins at startup, not on demand.

- **Capabilities, not ownership.** Access control uses named capability strings
  in `AclMap` documents (§13). There is no file-system-style ownership model.

- **CBOR on the wire; YAML for humans.** All peer-to-peer messages use CBOR.
  Operators author manifests and ACLs in YAML; the runtime converts to
  DAG-CBOR before publishing to IPFS. See §7.

### 2.3 Related specifications

- `did-ma-spec-v1.md` — `did:ma` method, DID document structure, key types
- `ma-rpc-service-v1.md` — RPC message-type definitions
- `ma-ipfs-service-v1.md` — IPFS publish request format
- `ma-messaging-format-v1.md` — encrypted envelope format

---

## 3. Identity integration

### 3.1 The `ma.runtime` field

A 間 DID document MUST include a `ma.runtime` field whose value is an IPLD
link to the current runtime manifest. The field lives inside the `ma` map
alongside `ma.kind` and `ma.services`:

```json
{
  "ma": {
    "kind": "runtime",
    "runtime": { "/": "<base32-CIDv1-runtime-root>" },
    "services": [
      "/iroh/<endpoint-id>/ma/rpc/0.0.1",
      "/iroh/<endpoint-id>/ma/inbox/0.0.1"
    ]
  }
}
```

**Rules:**

- `ma.runtime` MUST be an IPLD link to a content CID.
- The link MUST be directly traversable as an IPLD DAG without additional
  resolver logic.
- When the runtime manifest changes, the DID document MUST be republished so
  that `ma.runtime` points to the new root CID.

  **Rationale:** A direct CID link enables simple, deterministic DAG traversal
  (`/ipfs/<did_doc_cid>/ma/runtime/…`) and avoids an extra IPNS indirection.

### 3.2 DID document republication

The runtime MUST republish its DID document:

- on startup (after loading the manifest);
- whenever the manifest root CID changes;
- on a configurable periodic interval (default: 12 hours) to refresh IPNS TTL.

### 3.3 Fragment addressing

Entity addresses are DID-URLs of the form `did:ma:<ipns>#<fragment>`, where
`<fragment>` is the entity's globally unique bare name in the manifest
`entities` map (§4.2). Fragment routing is a direct `entities[fragment]`
lookup — no dot-path traversal, no namespace prefix.

---

## 4. Runtime manifest

The runtime manifest is the root IPLD DAG-CBOR object of the runtime's
content-addressed state. Its keys fall into three categories:

| Category | Key pattern | Stored as |
|----------|------------|-----------|
| Reserved system keys | `acl`, `kinds`, `config`, `lang`, `protocol`, `entities` | Inline or IPLD link |

### 4.1 Reserved top-level keys

| Key | Type | Description |
|-----|------|-------------|
| `protocol` | string | Protocol identifier (e.g. `/ma/runtime/0.1.0`) |
| `acl` | IPLD link | Link to the root `AclMap` document. Absent means **deny all**. |
| `kinds` | flat map | Full protocol ID → IPLD link to a `KindNode` |
| `entities` | flat map | Bare entity name → IPLD link to an `EntityNode` |
| `config` | inline map | Key/value map for runtime metadata; publicly readable |
| `lang` | map | Locale code → IPLD link to an FTL locale file |

### 4.2 Entity map (`entities`)

The top-level `entities` key contains a flat map from bare entity name to an
IPLD link (`{ "/": "<cid>" }`) to an `EntityNode`. Entity names MUST be
globally unique across the entire runtime.

```yaml
entities:
  rms:     { "/": "<cid>" }   # → did:ma:<ipns>#rms
  fortune: { "/": "<cid>" }   # → did:ma:<ipns>#fortune
```

The DID fragment for entity `fortune` is `fortune` (`did:ma:<ipns>#fortune`).
Entity names MUST NOT start with `#`; the `#` appears only in DID-URLs, not
in the manifest key.

### 4.4 Normative top-level structure

```yaml
# Reserved system keys
protocol: /ma/runtime/0.1.0
acl: { "/": "<cid>" }
kinds:
  /ma/stateless/python/0.0.1: { "/": "<cid>" }
  /ma/stateful/python/0.0.1:  { "/": "<cid>" }
config:
  poll_interval_ms: 500
lang:
  en: { "/": "<cid>" }
  nb: { "/": "<cid>" }

# Entity map (flat, globally unique names)
entities:
  rms:     { "/": "<cid>" }   # → did:ma:<ipns>#rms
  fortune: { "/": "<cid>" }   # → did:ma:<ipns>#fortune
```

**Rules:**

- `kinds` and `entities` are both **flat maps** at the manifest root.
- Entity names are globally unique and MUST NOT match any reserved key (§16.1).
- Each kind node and entity node is a separate IPLD object linked via
  `{ "/": "<cid>" }`.


## 6. Transport services

### 6.1 Service requirements

All three transport services are OPTIONAL. A runtime MAY register any
subset of them — zero, one, two, or all three — at startup. A runtime that
registers none of them is unreachable over the network, but this is a valid
configuration (for example while shut down for maintenance), not a
conformance violation.

Designated services exist to give a message type a dedicated handler for
cleaner, purpose-built reception and parsing — not to gate functionality.
`/ma/inbox/0.0.1` remains the universal fallback: a client that does not
find a matching designated service advertised in a target's `ma.services`
MAY still attempt delivery via `/ma/inbox/0.0.1`.

| Protocol ID | Message type accepted (`type` field) | Requirement | Section |
|-------------|----------------------|-------------|---------|
| `/ma/rpc/0.0.1` | `application/vnd.ma.rpc.request` and `application/vnd.ma.rpc.reply` only | OPTIONAL | §7 |
| `/ma/inbox/0.0.1` | any message type not claimed by a registered designated service (see rules) | OPTIONAL | §6.3 |
| `/ma/ipfs/0.0.1` | `application/vnd.ma.identity.publish.request` and `application/vnd.ma.ipfs.request` only | OPTIONAL | §8 |

**Rules:**

- Routing is always performed on the message's `type` field (§2 of
  `ma-messaging-format-v1.md`), **never** on `contentType`. `contentType`
  only describes the semantic shape of the decoded payload and plays no
  part in service or dispatch selection.
- Each service other than `/ma/inbox/0.0.1` is a **designated service**: it
  is bound to exactly one message type and MUST reject any other message
  type it receives.
- `/ma/inbox/0.0.1` MAY accept any message type, but is not required to
  support all of them.
- If a runtime registers a designated service for a given message type
  (e.g. `/ma/rpc/0.0.1` for RPC, `/ma/ipfs/0.0.1` for IPFS requests) and
  advertises it in `ma.services`, clients MUST prefer that designated
  service over `/ma/inbox/0.0.1` for messages of that type. A runtime that
  receives such a message on `/ma/inbox/0.0.1` while the matching
  designated service is registered MUST reject it (see §7, §8).
- If a client cannot find a designated service for the message type it
  wants to send advertised in the target's `ma.services`, it MAY attempt
  delivery via `/ma/inbox/0.0.1` instead.
- If a runtime does **not** register a designated service for a given
  message type, `/ma/inbox/0.0.1` MAY accept that message type as a
  fallback and dispatch it internally per §6.4. This makes it possible to
  build a fully functional runtime with only `/ma/inbox/0.0.1` registered.
- `/ma/ipfs/0.0.1` is an example of a purpose-specific designated service.
  Implementations SHOULD register additional designated services for
  well-defined message types rather than overloading the inbox with custom
  types.
- All registered services MUST be advertised in `ma.services` in the DID
  document. A runtime with no registered services MUST publish an empty
  `ma.services` list rather than omitting the field.
- A useful, reachable runtime will normally register at least one service —
  a runtime with none is functionally inert — but this specification does not
  mandate a minimum.

### 6.2 Service identity

Services are identified by their full protocol ID string. The runtime's own
DID document MUST advertise the services it has registered via the `services`
field (per `did-ma-spec-v1.md`).

### 6.3 Inbox service — `/ma/inbox/0.0.1`

The inbox service carries text messages, chat messages, emotes, and any
other message type not claimed by a registered designated service. If the
corresponding designated service (e.g. `/ma/rpc/0.0.1`, `/ma/ipfs/0.0.1`) is
not registered, `/ma/inbox/0.0.1` MAY accept that message type instead and
dispatch it internally per §6.4.

#### Dispatch rules

| Message addressing | Handling |
|--------------------|---------|
| `did:ma:<ipns>` (no fragment) | Logged and dropped (no operator inbox mailbox in the reference runtime) |
| `did:ma:<ipns>#<fragment>` | Route to entity plugin via §10 fragment lookup |

#### Transport gate

The reference runtime applies **no ACL check** to `/ma/inbox/0.0.1`. Every
signed, well-formed message accepted by the transport is dispatched
unconditionally to the target entity's `on_message`
export (or dropped if unfragmented or the fragment is unknown). The `inbox`
capability string (§13.3) exists for implementations that choose to gate
this service, but the reference runtime does not check it here.

Access control for inbox-delivered messages, if desired, is the
**entity's own responsibility**: an entity plugin that wants to filter
senders must do so itself inside its Wasm handler — for example by
maintaining its own list of allowed senders in its persisted state and
checking membership before accepting a message. This is unrelated to the
runtime's own `+<name>` ACL group mechanism (§13.1) — an entity's inbox
filtering is entirely its own logic, not delegated to or shared with the
runtime's group registry. The runtime provides no built-in inbox ACL
enforcement to delegate to.

### 6.4 Message-type routing

The runtime MUST route incoming messages based on the `type` field
(§2 of `ma-messaging-format-v1.md`) — **never** on `contentType`, which
carries no routing meaning — regardless of which registered service the
message physically arrived on (subject to the exclusivity rule in §6.1 —
once a designated service is registered, its message type MUST NOT also be
accepted on `/ma/inbox/0.0.1`):

- `application/vnd.ma.rpc.request` and `application/vnd.ma.rpc.reply` → §7 RPC dispatcher
- `application/vnd.ma.identity.publish.request` and `application/vnd.ma.ipfs.request` → §8 IPFS publisher
- all other types → §6.3 inbox dispatch

---

## 7. RPC

### 7.1 Wire format

All peer-to-peer messages use **CBOR only**. JSON is never sent between
peers. This is a hard requirement.

| Context | Format | Rationale |
|---------|--------|-----------|
| Peer-to-peer transport | CBOR | Compact, typed, unambiguous |
| IPFS storage | DAG-CBOR | Content-addressed, deterministic |
| User interface | YAML | Human-readable and editable |
| Kubo HTTP API (internal) | JSON | Implementation detail; never forwarded |
| IPFS gateway response | DAG-JSON | Gateway converts DAG-CBOR automatically |

### 7.2 Term encoding

An RPC message body is a single CBOR-encoded **term**: either an **atom** or a
**tuple**.

```abnf
term  = atom / tuple
atom  = text           ; a CBOR text string beginning with ":"
tuple = array          ; a CBOR array whose first element is an atom
```

Examples:

| CBOR | Meaning |
|------|---------|
| `":ping"` | Liveness check atom (unfragmented) |
| `":enter"` | Verb dispatch to a fragment-addressed entity plugin (§10) |
| `[":enter", "#room"]` | Verb dispatch with an argument |

### 7.3 Normative encoding rules

1. `application/vnd.ma.rpc.request` content is always a single CBOR-encoded term (atom
   or tuple).
2. Text arguments in tuples (`CborValue::Text`) are plain strings (CID, DID,
   config value, etc.).
3. An EntityNode is authored in YAML by the client but is **always stored and
   transmitted as DAG-CBOR**.
4. The Kubo integration (`/api/v0/dag/put`, `/api/v0/dag/get`) is an internal
   implementation detail. JSON returned by Kubo is **never** forwarded to
   peers.

### 7.4 Reply format

Every RPC message addressed to the runtime MUST receive a reply. The reply is
delivered on the sender's `/ma/rpc/0.0.1` service and MUST set `reply_to` to
the `id` of the incoming message.

| Outcome | Reply |
|---------|-------|
| Success, no payload | `:ok` |
| Success with payload | `[:ok, <cbor-value>]` |
| Error | `[:error, "<message>"]` |
| Liveness reply | `:pong` |

### 7.5 Routing

Unfragmented RPC messages (`did:ma:<ipns>`, no `#`) support only the
`:ping` liveness atom (§7.4). `/ma/rpc/0.0.1` is NOT a CRUD transport —
structured CRUD operations MUST go through the separate `/ma/crud/0.0.1`
service (§9).

Fragment-addressed RPC messages (`did:ma:<ipns>#<fragment>`) are delivered
directly to the named entity plugin (§10).

---

## 8. IPFS publishing service

### 8.1 Overview

The optional `/ma/ipfs/0.0.1` service allows a caller to delegate IPNS
publishing to the runtime. This enables browser-based actors (which cannot
reach Kubo directly) to publish their DID documents.

The service is enabled by default. It MAY be disabled by operator
configuration (`ipfs_publisher: false`).

### 8.2 Request format

The service accepts two independent message types, each with its own payload
shape and its own required capability (see §8.3):

- `application/vnd.ma.identity.publish.request` — delegated DID-document
  publishing. The payload contains:
   - the caller's signed DID document (DAG-CBOR bytes);
   - the caller's IPNS private key (used once for publishing, then zeroized).
- `application/vnd.ma.ipfs.request` — generic content storage. The payload
  contains:
   - raw content bytes;
   - a content-type string describing the payload.

Both are CBOR-encoded envelopes; see `ma-ipfs-service-v1.md` for the
normative payload definitions. A message ID and replay window (§8.3) provide
replay protection for both types.

### 8.3 Validation

Before acting on a request, the runtime MUST:

1. Determine the message type and required capability:
   - `application/vnd.ma.identity.publish.request` requires `identity-publish`.
   - `application/vnd.ma.ipfs.request` requires `ipfs`.
   These are two independent capabilities (see `ma-ipfs-service-v1.md` §4.2)
   — a principal granted one does not thereby gain the other.
2. Check the root ACL for the required capability. No → reject.
3. Apply replay protection (`ReplayGuard`, 120-second sliding window).
4. For identity-publish: validate the CBOR envelope — verify the envelope
   signature; validate and verify the DID document (including proof);
   assert that the sender's IPNS identity matches the document's DID; then
   publish via Kubo and zeroize the IPNS key immediately after use.
5. For generic store: validate the CBOR envelope, then call `ipfs add` on
   the content bytes.

### 8.4 Security

The IPNS private key in an identity-publish request grants full publishing
authority over the sender's DID. It MUST be used exactly once and zeroized
immediately after the Kubo call completes. The runtime MUST NOT log, cache,
or otherwise retain the key material. Generic store requests (§2.2 of
`ma-ipfs-service-v1.md`) carry no key material and pose no equivalent risk —
this is why the two message types are gated by separate capabilities.

---

## 9. CRUD interface

Structured CRUD operations (get/set/delete of entities, kinds, config, and
ACLs) are provided **exclusively** by the `/ma/crud/0.0.1` service — see
[ma-crud-service-v1.md](ma-crud-service-v1.md) for the normative protocol
definition (`/`-separated path grammar, GET/SET/DELETE semantics,
`/ipfs/`/`/ipns/` value references, and reply conventions).
CRUD error-code conventions, including the `not-found` / `*-not-found`
missing-resource family, are normative in that service specification.

`/ma/rpc/0.0.1` (§7) is NOT a CRUD transport. It carries only the `:ping`
liveness atom when unfragmented, and entity verb dispatch when
fragment-addressed (§10). There is no colon/dot-path CRUD grammar layered on
top of `/ma/rpc/0.0.1` — no such syntax (`:entities.<name>`, `:kinds.<protocol>`,
`:config.<key>`, or similar) is valid on this service. All CRUD MUST go
through `/ma/crud/0.0.1`.

Wire-level sigil conventions used across this specification:

| Sigil | Meaning |
|-------|---------|
| `/path` | CRUD path — `/ma/crud/0.0.1` only |
| `:verb` | RPC verb/command atom — `/ma/rpc/0.0.1` (§7, §10); e.g. `:ping`, an entity's own verbs |
| `!verb` | Client-local side-effect command (e.g. zion's `!edit`, `!eval`, `!publish`) — parsed and dispatched entirely client-side, NEVER sent over the wire |

---

## 10. Fragment routing

### 10.1 Routing rule

Messages addressed to `did:ma:<ipns>#<fragment>` are delivered to the named
entity plugin's verb dispatch — the single `on_message` export, used by
both stateless and stateful kinds alike.

The fragment is the entity's **globally unique bare name** in the manifest
`entities` map. Fragment resolution is a direct `entities[fragment]` lookup
— no dot-path traversal, no namespace prefix.

| Entity name | DID-URL |
|-------------|--------|
| `rms` | `did:ma:<ipns>#rms` |
| `fortune` | `did:ma:<ipns>#fortune` |

Fragment-addressed messages are always verb dispatch to the entity plugin.
There is no CRUD-via-fragment mechanism: entity registration and deletion
are CRUD operations performed via `/ma/crud/0.0.1`'s `/entities/<name>`
path (§9), never by sending a message to the fragment address itself.

### 10.2 Resolution algorithm (normative)

1. Extract fragment from `to` DID-URL: `did:ma:<ipns>#<fragment>`.
2. Look up `entities[fragment]` in the entity registry.
3. If `entities[fragment]` misses, reply
   `[:error, "entity not found: <fragment>"]`.
4. Check entity ACL: caller holds the required capability?
   No → reply `[:error, "forbidden"]`.
5. Call the entity plugin's `on_message` dispatch function (same export
   for both stateless and stateful kinds).

### 10.3 Intra-runtime messages

Messages whose `from` field is `<our_did>#<entity>` (an entity on **this**
runtime sending to another entity on the same runtime) bypass the root ACL
transport gate. They are trusted local dispatches; the `rpc` capability check
is skipped.

**Rule:** Fragment routing applies to both `/ma/rpc/0.0.1` and
`/ma/inbox/0.0.1`. The runtime MUST apply the entity's own ACL before
dispatch.

---

## 11. Kinds management

### 11.1 Overview

The `kinds` registry maps full protocol ID strings to IPLD links to
`KindNode` objects. Because protocol IDs contain slashes, they are simply
passed through as-is when building a `/ma/crud/0.0.1` path — e.g. the
protocol `/ma/stateless/python/0.0.1` is reachable at
`/kinds/ma/stateless/python/0.0.1`. See
[ma-crud-service-v1.md](ma-crud-service-v1.md) for GET/SET/DELETE semantics.
There is no separate RPC-based kinds grammar; §9 applies.

### 11.2 KindNode structure

```yaml
protocol: /ma/runtime/cast/0.0.1
cid:
  "/": bafy...wasmbinary
type: extism
host_functions:
  - ma_send
  - ma_reply
attributes:
  stateful: false
  wasi: false
```

**Required fields:** `protocol`, `type`, `host_functions`, `attributes.stateful`, `attributes.wasi`. `cid` is **optional** (see below).

- `cid` (optional) — IPLD link to the compiled Wasm module bytes **shared by
  every entity of this kind**. Present for the common case: one binary
  reused across all entities of the kind (this field lives here, not on
  `EntityNode` §14.1, precisely so it isn't duplicated identically across
  every entity). **Absent** for a kind whose entities each supply their
  *own*, distinct Wasm binary instead (e.g. a generic
  "bring-your-own-compiled-actor" kind) — for those, `EntityNode.behaviour`
  (§14.1) holds that entity's own Wasm bytes directly, instantiated as-is,
  never resolved as interpreted text.
  A kind MUST declare exactly one of: `cid` present (shared binary), or
  `cid` absent with entities required to supply `EntityNode.behaviour`
  (own binary) — never both, never neither.
- `type` — how the runtime executes the Wasm bytes for this kind (was
  `evaluator` in an earlier draft of this spec — same field, renamed).
  `extism` is the only currently-implemented value; others (`native`,
  `bash`, `lua`) are reserved for future use and MUST cause `load()` to
  fail cleanly if requested.
- `behaviour` (optional) — a **behaviour-dialect identifier** (e.g.
  `/ma/scheme/actor/0.0.1`). Only meaningful when `cid` (above) is
  present: it declares that this kind's entities each have their own
  per-entity *interpreted source text* (§14.2.2), resolved by the runtime
  according to the named dialect's rules and delivered via the
  `:set-behaviour` signal (§14.2) as a single, flat fetch — the runtime
  performs no scanning/composition of any kind on it (the dialect's own
  `ma-include-ipfs`-equivalent primitive, if it has one, handles
  composition entirely on the guest side via `ma_ipfs_include`, §14.2.2).
  Kinds with no per-entity scriptable behaviour (including kinds with no
  shared `cid` at all) simply omit this field.

  `attributes.stateful` is the authoritative source for whether a kind is
  stateful. The runtime uses this to load persisted state and fire the
  `:set-state` signal as applicable on load (§14.2), and persist state
  after each `on_message` dispatch. Statelessness exists purely to avoid
  needlessly persisting/publishing state to IPFS for plugins that never
  need it — since content is encrypted, even identical plaintext state
  yields a unique CID each time, which is wasteful.

  Standard kind profiles:

| Profile | `attributes.stateful` | `host_functions` |
|---------|----------------------|------------------|
| `stateless` | `false` | `[ma_send, ma_reply]` |
| `stateful` | `true` | `[ma_send, ma_reply, ma_set_state]` |

There is no `api`/`lifecycle` field anymore — an earlier draft had both,
enumerating which of five separately-named lifecycle exports a kind
provided and in what order the runtime should invoke them. Both fields
are gone along with the exports they described (§14.2): every kind
exports exactly `on_message` and `on_signal`, always, and which of the
five lifecycle signals actually does anything for a given entity is
determined purely by data availability (does state exist? does a
behaviour reference exist? is this genesis?) — nothing left for a
`KindNode` to declare about this. A kind whose `on_signal` has nothing to
do for a particular signal simply no-ops on it.

`behaviour` (above) is additionally meaningful only for kinds whose
entities carry their own interpreted source text; in which case
`host_functions` additionally requires `ma_ipfs_include` if the dialect
supports library composition (ma-scheme does — see ma-scheme-v1.md
§11.1) — see §14.2.2.

---

## 12. Config management

Runtime configuration is read and written via the `/ma/crud/0.0.1` service
under the `/config` namespace (e.g. `/config/i18n`) — see
[ma-crud-service-v1.md](ma-crud-service-v1.md) for GET/SET/DELETE semantics.
There is no separate RPC-based config grammar; §9 applies.

Some configuration keys are protected (never exposed or writable via CRUD,
e.g. secret material) and writes to manifest-backed keys require the
appropriate capability in the root ACL (§13). These policies are
implementation-defined and out of scope for this wire-protocol
specification.

---

## 13. ACL and capabilities model

All access control in the runtime uses a **capabilities model**: every
operation a caller can perform is guarded by a named capability string.
Access control is expressed as an `AclMap` — a flat YAML object mapping
principals (or the wildcard `*`) to their allowed capabilities.

**Deny always wins.** An explicit `null` value for any principal overrides
every allow, including the wildcard.

---

### 13.1 AclMap format

An `AclMap` is a flat YAML object. Each key is either a **principal** (a
full DID or `*`) or is absent. Every value is one of:

| YAML value | Meaning |
|------------|---------|
| `null` or bare key | **Explicit deny** — overrides all wildcards |
| YAML sequence | **Allow** — caller receives exactly the listed capabilities |
| (absent) | Equivalent to explicit deny |

There is no "grant-by-capability" notation. All grants are per-principal.

Groups are referenced as **principals** using the flat `+<name>` prefix,
where `<name>` is looked up directly in the runtime's named group registry
— `manifest.grp`, a map from group name to an IPLD link to a plain flat
list of member DIDs (CRUD-addressed as `/grp/<name>`, §9). There is no
nested path and no `#fragment` in a group reference — `+<name>` is the only
supported group-reference syntax:

```yaml
+fortune-friends: [fortune, secret]
+admins: [admin, supersecret]
```

The special group name `"owners"` (`/grp/owners`) is the runtime's
authoritative owner list — same storage as any other group, no special
resolution logic — but it is protected against deletion (the entry may be
set to an empty list, but never removed via CRUD). See §13.6 for the
manifest location.

A `+group` entry works exactly like a DID entry: the runtime resolves group
membership by looking up `<name>` in the named group registry and, if the
caller is listed as a member, applies that entry's capabilities. This is a
synchronous, in-memory cache lookup in the reference runtime — no message
dispatch, no round-trip. See §13.4 for the full evaluation order.

---

### 13.2 Canonical YAML format

Implementations MUST serialise and accept ACL maps in this exact form:

```yaml
# Transport gate — who may use which protocols
"*":              [rpc]            # everyone: RPC access
"did:ma:alice":   [rpc, inbox]     # alice: RPC + inbox
"did:ma:eve":                      # bare key → explicit deny

# Group entries — group members inherit these capabilities
"+fortune-friends": [fortune, secret]
"+admins": [admin, supersecret]
"+banned":                    # group is explicitly denied
```

Serialisation rules (normative):

- A deny entry MUST serialise as a bare YAML key with no value (implicit
  `null`). Parsers MUST accept both bare key and explicit `null`.
- An allow entry MUST serialise as a YAML sequence. Parsers MUST treat any
  sequence as an allow set.
- An empty sequence `[]` is valid YAML but has no effect. Implementations
  SHOULD log a warning at load time when an empty sequence is encountered
  (it is a likely authoring mistake).

---

### 13.3 Built-in capability strings

The following capability strings have normative meanings at the transport
layer. They MUST NOT be used as entity names (see §16).

| Capability | Layer | Meaning |
|------------|-------|---------|
| `"rpc"` | Transport | Enforced. Required to send to `/ma/rpc/0.0.1` (§7). Bypassed for owners and for intra-runtime senders. |
| `"ipfs"` | Transport | Enforced. Required for `application/vnd.ma.ipfs.request` (generic content storage) on `/ma/ipfs/0.0.1` (§8). Bypassed for owners. |
| `"identity-publish"` | Transport | Enforced. Required for `application/vnd.ma.identity.publish.request` (DID-document publishing) on `/ma/ipfs/0.0.1` (§8). Independent of `"ipfs"` — granting one does not grant the other. Bypassed for owners. |
| `"crud"` | Transport | Enforced. Required to send to `/ma/crud/0.0.1` (§9). Bypassed for owners. This is the **only** gate most CRUD operations receive — see the note below. |
| `"inbox"` | Transport | Reserved, **not enforced** by the reference runtime. `/ma/inbox/0.0.1` has no ACL check at all (§6.3); this string exists only for implementations that choose to gate inbox delivery themselves. |
| `"*"` (in Allow set) | Any | Grants all capabilities for this principal |

Beyond the two ad-hoc checks in §13.7 (entity delete requires `delete` +
`entities`; entity upsert requires the entity's own `kind` protocol ID as a
capability), the reference runtime does **not** enforce separate `read`,
`create`, `update`, or `kinds` capabilities anywhere. Kind management,
config management, and named/root ACL-document management currently
require nothing beyond the blanket `crud` capability (or owner status).
These generic capability strings remain reserved for use by
implementations or entity-level ACLs that want finer-grained checks, but
authors MUST NOT assume the reference runtime enforces them at the CRUD
transport layer.

Entity-level ACLs (§13.7, §7.2) are a separate mechanism: each entity
carries its own named `AclMap` (`entity.acl` → `acls.<name>`), which is
consulted only for fragment-addressed `/ma/rpc/0.0.1` verb dispatch and
uses arbitrary capability strings (typically verb names, e.g.
`"on_message"`, `"enter"`) rather than this built-in list. An entity with
an empty `acl` field is deny-all (fail-closed).

Entity-level ACLs may use arbitrary strings as capability names
(`"on_message"`, `"reply"`, `"secret"`, etc.).

---

### 13.4 Evaluation algorithm (normative)

This section defines the **mandatory evaluation order** for implementations.
Deviation from this order produces incorrect deny-wins semantics.

**Input:** ACL map `A`, caller DID `caller`, capability set `required`
(one or more strings, **OR semantics** — the check passes if the caller
holds **at least one** of the listed capabilities).

**Per-check algorithm:**

```
normalised = strip_fragment(caller)

# Step 1 — Direct DID lookup (O(1), terminates evaluation)
if A[normalised] exists:
    if A[normalised] is Deny:
        return DENY
    if A[normalised] is Allow(caps):
        if caps.contains("*") or caps ∩ required ≠ ∅:
            return ALLOW
        return DENY          ← direct entry but no matching cap

# Step 2 — Wildcard entry (O(1), terminates evaluation)
if A["*"] exists:
    if A["*"] is Deny:
        return DENY
    if A["*"] is Allow(caps):
        if caps.contains("*") or caps ∩ required ≠ ∅:
            return ALLOW
        return DENY

# Step 3 — Group principal scan (+prefix keys only; synchronous cache
# lookup in the reference runtime, see §13.1)
# 3a: deny groups — checked first, deny wins
for each key in A where key.starts_with("+") and A[key] is Deny:
    if normalised ∈ resolve_group(key):
        return DENY

# 3b: allow groups
for each key in A where key.starts_with("+") and A[key] is Allow(caps):
    if normalised ∈ resolve_group(key):
        if caps.contains("*") or caps ∩ required ≠ ∅:
            return ALLOW

# Step 4 — Default deny
return DENY
```

**Rules:**

1. An explicit `null` (Deny) for the caller's DID terminates evaluation
   immediately — no wildcard or group can override it.
2. A direct DID match (step 1) or wildcard match (step 2) terminates
   evaluation — the caller does not fall through to group checks.
3. An empty sequence `[]` on a principal is a no-op allow (no capabilities
   granted). Implementations SHOULD log a warning at load time.
4. Multiple capability strings in `required` use **OR semantics**: the check
   passes as soon as the caller holds any one of them.
---

### 13.5 Performance guidance

| Pattern | Cost | Use when |
|---------|------|----------|
| Direct DID entry | O(1) | Known principals; hot path |
| `"*"` wildcard entry | O(1) | Open-access or default policy |

Rules of thumb:

- Put the most common callers as **direct DID entries**.
- Use `"*": [...]` for broad default policies.

---

### 13.6 ACL locations

The ACL document and named group registry live at the manifest root:

| Location | Type | Purpose |
|----------|------|---------|
| Root `.acl` | CID | Transport gate for the whole runtime (§13.7) |
| `.grp.<name>` | CID | Named group registry entry (§13.1), a plain `Vec<String>` of member DIDs. CRUD-addressed as `/grp/<name>` (§9). The `"owners"` entry is the runtime's authoritative owner list. |

Updating the ACL requires only replacing the CID at this location —
no manifest republish needed.

A missing or unresolvable CID MUST be treated as **deny all**.
Implementations SHOULD provide an operator recovery path for the case where
the root ACL becomes unreachable. The `"owners"` group entry MUST NOT be
deletable via CRUD (it may be set to an empty list, but the entry itself
must always exist) — this guarantees an operator recovery path for owners
specifically, independent of the root ACL's own availability.

**Client-side ACL:** Actors receiving messages MAY apply their own inbound
`AclMap` before delivering content to the application layer. Reply messages
identified by a matching `reply_to` field SHOULD bypass inbound ACL filtering.

---

### 13.7 Entity management capabilities

Beyond the blanket `crud` transport gate (§13.3), the root ACL enforces
exactly two additional checks for entity management — they are **not**
symmetric:

- **Delete** an entity: the caller MUST hold both `delete` and `entities`
  in the root ACL.
- **Upsert** (register/replace) an entity: the caller MUST hold the
  entity's own `kind` protocol ID (e.g. `/ma/stateless/python/0.0.1`) as a
  capability in the root ACL — there is no `create`/`entities`
  requirement. This lets an operator grant "may register avatar-kind
  entities" without granting entity deletion or other kinds.

  Getting/listing entities requires only the blanket `crud` capability (or
  owner status); there is no separate `read` check.

  Example transport ACL:

```yaml
# bahner: may delete any entity, and register/replace avatar-kind entities
"did:ma:bahner": [crud, delete, entities, "/ma/avatar/0.0.1"]

# everyone: RPC access only
"*": [rpc]
```

With this ACL, `did:ma:bahner` may:

- Delete any entity (has `delete` + `entities`)
- Register or replace an entity whose `EntityNode.kind` is
  `/ma/avatar/0.0.1` (has that kind's protocol ID as a capability)
- NOT register an entity of any other kind

---

## 14. Entities

### 14.1 EntityNode structure

An `EntityNode` is an IPLD DAG-CBOR object stored separately from the
manifest and linked via `{ "/": "<cid>" }`.

| Attribute | Required | Description |
|-----------|----------|-------------|
| `kind` | yes | Full protocol ID of the kind (e.g. `/ma/stateless/python/0.0.1`) |
| `behaviour` | no | IPLD link (CID) — this entity's own content reference, a single link only (never a list — composition, when needed, is a ma-scheme-level concern via `ma-include-ipfs`, not something this layer resolves, §14.2.2). Its **meaning** depends on `KindNode.cid`/`KindNode.behaviour` (§11.2): if the kind declares a shared `cid` **and** a `behaviour` dialect, this is per-entity *interpreted source text* fed to that shared binary (e.g. the ma-scheme case). If the kind has **no** shared `cid` at all, this is instead the entity's **own Wasm binary bytes**, instantiated directly — never interpreted. Present only where the kind requires it; absent otherwise. |
| `state` | no | IPLD link (CID) to persisted state bytes (stateful only) |
| `wasi` | no | Boolean; WASI capability snapshot (default `false`) |

Example (YAML, before DAG-CBOR conversion) — an ordinary hand-compiled
kind with no per-entity behaviour:

```yaml
kind: /ma/stateful/python/0.0.1
state:
  "/": bafy...state_counter
wasi: true
```

Example — an entity of a kind that declares `behaviour: /ma/scheme/actor/0.0.1`
(§11.2), referencing a reusable behaviour template (shared by every entity
created from it) plus a per-instance `:init` signal payload supplied only
at creation time (§14.2.1 — not persisted on the `EntityNode` at all):

```yaml
kind: /ma/scheme/actor/0.0.1
behaviour:
  "/": bafy...restaurant_template
state:
  "/": bafy...state_props
wasi: false
```

Example — an entity of a kind with **no shared `cid`** at all (e.g.
`/ma/python/actor/0.0.1`, a generic "bring-your-own-compiled-actor" kind):
`behaviour` here is that entity's *own* Wasm binary, not interpreted text.

```yaml
kind: /ma/python/actor/0.0.1
behaviour:
  "/": bafy...my_custom_actor_wasm
state:
  "/": bafy...state
wasi: true
```

**Rules:**

- The entity name is **not** stored inside the `EntityNode` — it is the key
  under which the node is linked in the manifest.
- Implementations MUST derive the entity's address from its IPLD tree
  position, not from a `name` field.
- For stateless entities, `state` SHOULD be omitted on serialisation.
- Readers MUST accept both a missing `state` and `state: null`.
- `wasi` MUST NOT be derived dynamically per call; it is snapshotted at
  bootstrap/creation time.
- An entity of a kind with no shared `KindNode.cid` (§11.2) MUST supply
  `behaviour`; the runtime rejects creation/load otherwise.

### 14.2 Plugin ABI

Before any export runs, the runtime loads Wasm bytes per `KindNode.cid`'s
presence (§11.2): a shared binary if `cid` is set, or this entity's own
binary from `EntityNode.behaviour` if not. Every kind — stateless or
stateful, no exceptions — exports **exactly two** functions:

| Export | Signature | Description |
|--------|-----------|--------------|
| `on_message` | `(Bytes) → Bytes` | Called for every incoming fragment-addressed message |
| `on_signal` | `(Bytes) → Bytes` | Called for every runtime-originated lifecycle event (below) — never for messages |

There is no per-kind declaration of which lifecycle stages a kind
"supports." An earlier draft of this specification had five additional,
separately-named exports (`set_state`/`set_behaviour`/`do_init`/
`do_start`/`do_shutdown`), each optionally listed in `KindNode.api`/
`KindNode.lifecycle` (§11.2). All five, and both of those `KindNode`
fields, have been removed entirely — collapsed into the single
`on_signal` export above. Whether a given signal actually does anything
for a given entity is determined purely by data availability, never by
anything a kind declares:

| Signal | Argument | Fires when |
|--------|-----------|-------------|
| `:set-state` | persisted state bytes | Only if persisted state already exists for this entity (never on a brand-new entity's very first load) |
| `:set-behaviour` | fully-resolved behaviour text | Only if `KindNode.behaviour` is set and `EntityNode.behaviour` points at content (§14.2.2) |
| `:init` | opaque, kind-defined creation payload (§14.2.1) | Only on this entity's very first ever load, after `:set-state`/`:set-behaviour` above. Never fires again on any later reload. |
| `:start` | none | Every load, unconditionally, after `:init` (if this is genesis) or immediately after `:set-state`/`:set-behaviour` (on a reload) |
| `:shutdown` | none | Best-effort, once, before an entity is torn down (e.g. graceful runtime shutdown). Not guaranteed on a crash or non-graceful termination. |

The runtime always fires whichever of these are applicable in the fixed
order above, on every single `on_signal`-exporting kind — there is nothing
to configure and nothing that can be selectively opted out of at the
`KindNode` level. A plugin implementation that has nothing to do for a
given signal simply does nothing when it receives it (a no-op is a
perfectly conforming response).

**Encoding.** Each signal is a CBOR term in exactly the same shape as a
message dispatch term: a bare atom (`":start"`, `":shutdown"`) when there
is no associated data, or a two-element array (`[":set-state", bytes]`,
`[":set-behaviour", text]`, `[":init", payload]`) when there is. A
conforming plugin recovers the signal name and data with the same
verb/args idiom already used for `on_message` dispatch content — the two
exports share one calling convention, not two.

**Host-mechanical vs. script-definable is a plugin-implementation detail,
not a runtime concern.** `:set-state`, `:set-behaviour`, and `:init` are
the three signals a well-behaved plugin handles with its own fixed
internal logic (decode state bytes; parse+evaluate behaviour text;
evaluate the creation payload) regardless of what, if anything, the
entity's own loaded script defines — see
[ma-scheme-v1.md §3](ma-scheme-v1.md#3-lifecycle) for how the reference
ma-scheme host does this. `:start` and `:shutdown` are the two genuinely
script-definable hooks. The runtime itself calls the *same* `on_signal`
export for all five, in all cases — it has no visibility into, and no
need to know, how a given plugin internally routes each one.

**Atomicity guarantee.** The `:init` signal (when applicable) fires
synchronously as part of entity creation itself, before the entity is
registered in the manifest and before it becomes reachable by any
message. This closes a race that would otherwise exist for any kind whose
behaviour depends on creation-time setup (e.g. an owner field) — there is
no window in which a freshly created, not-yet-initialized entity is
addressable by a racing caller.

The return value of every export is **ignored**. Plugins communicate
outbound via host functions only.

#### 14.2.1 Creation payload

A caller creating a new entity MAY supply an additional, opaque
**creation payload** alongside the usual `kind`/`acl` fields of the
creation request — delivered via the `:init` signal (above) if this is
the entity's first ever load. This payload is:

- **Not** part of the persisted `EntityNode` (§14.1) — it exists only for
  the single `:init` signal and is discarded afterward; whatever the kind
  wants to keep from it, it persists itself via `ma_set_state` during that
  same `:init` handling.
- **Opaque to the runtime** — exactly like state bytes, the runtime never
  parses or validates its shape. Its schema is entirely kind-defined. It
  has nothing to do with behaviour source (§14.2.2) — for kinds that
  declare `behaviour` (§11.2), this payload is used purely to seed initial
  *state* (e.g. `(set-prop! "owner" "did:ma:me")` for an ma-scheme kind —
  see [ma-scheme-v1.md §3.3](ma-scheme-v1.md#33-the-init-signal--host-mechanical-genesis-only)).
  This is deliberately the **most specific** of three tiers of reuse: the
  kind (`KindNode.cid`) is the most generic (a compiled binary usable for
  any purpose), the behaviour (§14.2.2) is a reusable template an author
  writes once and applies to many entities, and the creation payload is
  what makes one particular entity instance unique.
- A kind MAY require this payload to be present and reject creation with a
  clear error if it is missing or malformed, if it has no sensible default
  behaviour for an uninitialized instance.

#### 14.2.2 Behaviour resolution

This section covers the **shared-binary** case only — kinds that declare
both `KindNode.cid` (a shared binary) *and* `KindNode.behaviour` (a
behaviour-dialect identifier, e.g. `/ma/scheme/actor/0.0.1`), letting each
of their entities carry its *own* interpreted source, separate from that
shared Wasm binary. For kinds with **no** shared `cid` at all,
`EntityNode.behaviour` instead holds the entity's own Wasm bytes directly
(§14.1) — there is no "resolution" step, no text, and none of this
section applies.

**Storage.** `EntityNode.behaviour` (§14.1) is a **single** IPLD link — a
reference into content the runtime can fetch (e.g. via its own Kubo
access).

**The runtime performs a single, flat fetch — no recursion, no scanning,
no composition of any kind.** `EntityNode.behaviour` is fetched once,
decoded as UTF-8 text, and delivered via the `:set-behaviour` signal
(§14.2) exactly as read. Multi-piece library composition (a shared
library plus an entity-specific script) is entirely a ma-scheme-level
concern handled by the dialect's own `ma-include-ipfs` primitive
([ma-scheme-v1.md §11.1](ma-scheme-v1.md#111-ma-include-ipfs--top-level-only-library-composition)),
not something this runtime layer is aware of or resolves on the dialect's
behalf. (An earlier draft of this specification had the runtime itself
scan fetched content for `#!/ipfs/<cid>`/`#!/ipns/<key>` directive lines
and recursively splice them before ever delivering it — that mechanism
has been removed. Composition now happens *inside* the scripting
language, visibly, at the author's explicit choice, not via runtime-level
text-preprocessing invisible to the dialect.)

This composes cleanly with the three-tier reuse model (§14.2.1): the
**kind** (`KindNode.cid`) is the generic compiled binary, the
**behaviour** (this single reference) is a reusable template an author
writes once — using `ma-include-ipfs` internally to pull in any shared
library it needs — and applies to every entity created from it, and the
**`:init` creation payload** (§14.2.1) is evaluated once, at genesis, to
specialise one particular instance — see [ma-scheme-v1.md §3.3](ma-scheme-v1.md#33-the-init-signal--host-mechanical-genesis-only).

**Host functions** (declared in `KindNode.host_functions`, §11.2, only by
kinds that declare `behaviour`):

| Function | Signature | Description |
|----------|-----------|--------------|
| `ma_ipfs_include` | `(Bytes) → Bytes` | Fetches the content at a reference (`/ipfs/<cid>`: plain content-addressed fetch; `/ipns/<key>`: resolve then fetch), returning it as UTF-8 text. A single, flat fetch — no recursion, no directive scanning, no notion of ma-scheme syntax at all. This is a dumb "give me the bytes at this reference" primitive; the recursive expansion algorithm (depth limit, cycle guard, splicing into the current environment) is entirely the guest's own responsibility, implementing [ma-scheme-v1.md §11.1](ma-scheme-v1.md#111-ma-include-ipfs--top-level-only-library-composition) by calling this host function once per reference it encounters |

There is no host function that lets a script read back its own
`EntityNode.behaviour` content or change its own or any other entity's
behaviour reference — an earlier draft had `ma_get_behaviour`/
`ma_get_behaviour_cid`/`ma_set_behaviour_cid` for exactly this, including a
queued-mutation-and-republish mechanism mirroring `ma_create_entity`/
`ma_delete_entity` (§14.4). All three, and the republish machinery behind
them, have been removed: an entity's behaviour reference is immutable from
within ma-scheme for its entire lifetime (see
[ma-scheme-v1.md §11](ma-scheme-v1.md#11-behaviour-composition)) — it only
ever changes via ordinary external CRUD followed by a reload. A script
that needs its own behaviour reference (not its fetched content) reads it
from config instead — see `"behaviour"` in
[ma-scheme-v1.md §9.1](ma-scheme-v1.md#91-config--ma-get-config-key-read-only).

### 14.3 `CastInput` encoding

Only `on_message` receives a CBOR-encoded `CastInput` value:

```cbor
{
  "msg": {
    "id":           text,        ; unique message ID
    "from":         text,        ; sender DID or DID-URL
    "to":           text,        ; recipient DID-URL
    "created_at":   integer,     ; Unix epoch seconds
    "exp":          integer,     ; Unix epoch seconds (0 = never expires) — matches ma-messaging-format-v1.md §2's `exp` field name exactly, not spelled out as "expires"
    "reply_to":     text / null, ; message ID being replied to (if any)
    "message_type": text,        ; MIME routing/dispatch category, e.g. "application/vnd.ma.rpc.request"
    "content_type": text,        ; MIME type of content
    "content":      bytes        ; raw payload bytes
  }
}
```

There is no `ctx` wrapper — a plugin's own identity (`self`, the DID-URL of
this entity) and related runtime-assigned values (`id`, `kind`, `cid`,
`behaviour`, `runtime`, `iroh_node_id`, `started_at`, `parent`) are
delivered via the Extism plugin's own config map (read with
`ma-get-config-key`, see
[ma-scheme-v1.md §9.1](ma-scheme-v1.md#91-config)), set once at load time —
not re-sent with every `CastInput`. `behaviour` (present only for kinds
that declare `KindNode.behaviour`) is `EntityNode.behaviour`'s reference
string, a snapshot taken at load time — not the fetched/expanded text, and
not re-checked if `EntityNode.behaviour` changes via external CRUD before
the entity's next reload.

The other export, `on_signal`, receives a CBOR-encoded signal term instead
of a `CastInput` — a bare atom or a two-element array, exactly matching
the shape of a message dispatch term (§14.2):

| Signal term | Meaning |
|--------|----------|
| `["set-state", bytes]` | Raw persisted state bytes |
| `["set-behaviour", text]` | Raw resolved, composed behaviour text (§14.2.2) |
| `["init", payload]` | Raw, opaque creation payload (§14.2.1); byte layout is entirely kind-defined |
| `"start"` | No associated data |
| `"shutdown"` | No associated data |

### 14.4 Host functions

Host functions are registered in the `extism:host/user` namespace. Only the
functions listed in the kind's `host_functions` field are registered for a
given plugin instance (principle of least privilege).

#### `ma_send`

Queue an outbound message. Available to all plugin kinds.

```
ma_send(Bytes) → Bytes
```

Argument — CBOR-encoded `SendEnvelope`:

```cbor
{
  "to":           text,        ; recipient DID or DID-URL
  "content_type": text,        ; MIME type
  "content":      bytes,       ; payload
  "reply_to":     text / null  ; message ID if this is a reply
}
```

Return value: ignored.

#### `ma_reply`

Convenience wrapper around `ma_send`. Derives `to` and `reply_to`
automatically from the original message.

```
ma_reply(Bytes) → Bytes
```

Argument — CBOR-encoded `ReplyRequest`:

```cbor
{
  "msg":          CastInput.msg, ; the original message
  "content_type": text,          ; MIME type of the reply body
  "content":      bytes          ; reply body bytes
}
```

Return value: ignored.

#### `ma_set_state`

Queue new state bytes for IPFS persistence. Available to **stateful** plugin
kinds only.

```
ma_set_state(Bytes) → Bytes
```

Argument: raw state bytes (any encoding; treated as opaque by the runtime).

The runtime persists the bytes to IPFS after the dispatch call returns. This
is a no-op if the bytes are identical to the last persisted snapshot.

Return value: ignored.

#### `ma_ipfs_include`

Available only to kinds that declare `KindNode.behaviour` (§11.2, §14.2.2)
— a behaviour-dialect identifier such as `/ma/scheme/actor/0.0.1` — and
whose dialect supports library composition (ma-scheme does, via
`ma-include-ipfs`, ma-scheme-v1.md §11.1).

```
ma_ipfs_include(Bytes) → Bytes  ; raw UTF-8 reference bytes (e.g. "#!/ipfs/bafy...")
                                 ; in, raw content bytes out. Single flat
                                 ; fetch — no recursion, no caching.
```

There is no `ma_get_behaviour`/`ma_get_behaviour_cid`/`ma_set_behaviour_cid`
in this specification — an earlier draft had all three, including a
queued-mutation-and-republish mechanism mirroring `ma_create_entity`/
`ma_delete_entity` below. They have been removed entirely: an entity's
behaviour reference is immutable from within ma-scheme (see
[ma-scheme-v1.md §11](ma-scheme-v1.md#11-behaviour-composition)) — a
script that needs its own reference reads it from config instead (`"self"`
style key, §14.3).

### 14.5 Kind enforcement rules

- An entity **MUST** reference an existing kind.
- The runtime **MUST** verify that a plugin implements both required
  exports, `on_message` and `on_signal` (§14.2).
- The runtime **MUST NOT** register host functions beyond those listed in the
  kind's `host_functions`.
- `wasi` in an entity is an explicit snapshot of the capability from the
  referenced kind at bootstrap/creation time. The runtime MUST NOT derive
  `wasi` dynamically per call.

---

## 15. Development

### 15.1 Writing a plugin

A 間 entity plugin is an Extism Wasm module. Any language with an Extism SDK
may be used (Python, Rust, Go, C, etc.).

**Minimal stateless plugin (Python):**

```python
import extism
import cbor2

@extism.plugin_fn
def on_message():
    data = extism.input_bytes()
    cast = cbor2.loads(data)
    msg = cast["msg"]
    reply_body = cbor2.dumps({"ok": True, "echo": msg["content"]})
    extism.output_bytes(reply_body)
```

The plugin is compiled to Wasm using the language-specific Extism toolchain
(e.g. `extism-py` for Python).

### 15.2 Building and publishing a plugin

1. **Compile to Wasm.** Use the Extism toolchain for your language.
2. **Add to IPFS.** Upload the Wasm bytes via `ipfs add` or Kubo's
   `/api/v0/add`. Record the CID.
3. **Create a KindNode.** Author a YAML file and publish it to IPFS via
   `ipfs dag put --store-codec dag-cbor --input-codec dag-json`.
4. **Register the kind.** SET `/kinds/<protocol>` to `/ipfs/<kind-cid>` via
   `/ma/crud/0.0.1` (see [ma-crud-service-v1.md](ma-crud-service-v1.md)).
5. **Create an EntityNode.** Author a YAML file referencing the kind (the
   Wasm binary itself is referenced once, on the `KindNode`, not repeated
   per entity — §11.2, §14.1); publish to IPFS as DAG-CBOR.
6. **Register the entity.** Place the entity in the manifest via the
   runtime's CRUD interface or via a new bootstrap.

### 15.3 Bootstrap workflow

The reference implementation supports a YAML bootstrap file that defines the
full initial manifest:

```yaml
runtime:
  kinds:
    /ma/stateless/python/0.0.1:
      wasi: true
      host_functions: [ma_reply, ma_send]
  entities:
    fortune: <entity-node-cid>
```

Rules:

- `kinds` keys are **full protocol ID strings**. The `protocol` field is
  derived from the map key — do not repeat it in the value.
- `entities` values are **pre-published EntityNode CIDs**. Each `EntityNode`
  must be stored on IPFS via `ipfs dag put --store-codec dag-cbor` before
  running bootstrap.

  Running `ma --gen-root-cid bootstrap.yaml` publishes all `KindNode` and
  `AclMap` objects to IPFS, builds the manifest DAG, and prints the root CID.

### 15.4 Kind-plugin validation

At bootstrap and at kind upsert time, the runtime SHOULD verify that the
plugin Wasm module exports both `on_message` and `on_signal` (§14.2).
This catches mismatches between the kind descriptor and the actual module
before any messages are dispatched.

---

## 16. Reserved names registry

The following names are reserved and MUST NOT be used as
entity key names (with or without `#` prefix), or user-defined capability
strings at the root manifest level.

### 16.1 Reserved system keys (manifest top level)

These names are used as structural keys in the `RuntimeManifest`.
They MUST NOT be used as entity key names:

| Name | Role |
|------|------|
| `acl` | ACL gate document link (CID) at root |
| `config` | Runtime configuration map |
| `entities` | Global entity registry (flat map of entity names to IPLD links) |
| `kinds` | Kind registry |
| `lang` | Locale file links |
| `protocol` | Runtime protocol identifier |

### 16.2 Reserved capability strings (transport and CRUD layer)

These names are used as built-in capability strings (§13.3). They MUST NOT
be used as entity names because they would be ambiguous with capability
grants in ACL entries:

| Name | Meaning |
|------|---------|
| `rpc` | Access to `/ma/rpc/0.0.1` (enforced) |
| `ipfs` | Access to `/ma/ipfs/0.0.1` (enforced) |
| `crud` | Access to `/ma/crud/0.0.1` (enforced; the only gate on most CRUD operations) |
| `inbox` | Reserved for inbox ACL gating; **not enforced** by the reference runtime (§6.3) |
| `entities` | Used (with `delete`) by the reference runtime's entity-delete check (§13.7) |
| `read`, `create`, `update`, `kinds` | Reserved names; not currently enforced anywhere in the reference runtime |

### 16.3 Caution: names resembling service endpoints

Entity names that match, abbreviate, or closely resemble a service name
create ambiguity in logs, tooling, ACL authoring, and future protocol
extensions. Operators SHOULD avoid the following as entity names:

- Any name that is also a segment of a registered `did:ma` protocol ID
  (e.g. `ma`, `stateless`, `stateful`, `python`, `ping`, `rpc`, `ipfs`,
  `inbox`).
- Version-like names: `v0`, `v1`, `v2`, `0.0.1`, and similar.
- Names that shadow iroh service identifiers or future reserved protocol
  namespaces.

  The runtime SHOULD warn (and MAY reject) entity creation where the name
  matches a known protocol ID path segment from its own `kinds` registry.

### 16.4 Reserved entity fragment names

The following entity fragment names are reserved for standard runtime actors
and MUST NOT be used for user-defined entities. Their wire interfaces are
specified in [ma-standard-actors-v1.md](ma-standard-actors-v1.md).

| Fragment | Actor |
|----------|-------|
| `root` | Entity lifecycle manager |
| `scheduler` | Dynamic schedule registration |

### 16.5 Enforcement

- The runtime MUST reject any attempt to create an entity whose
  name (stripped of `#` prefix) appears in §16.1, §16.2, or §16.4.
- The runtime MUST reject any `acl` document where a YAML key in the
  capability position matches a reserved system key from §16.1.
- Validators (generators, linters) SHOULD flag reserved names at build time.
- The reserved list MAY be extended in future minor versions of this
  specification.

---

Draft — 5 July 2026
