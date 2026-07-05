# ma-runtime-v1 — 間 Runtime Specification

**Status:** Draft  
**Version:** 0.2.0  
**Date:** 5 July 2026

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
- [ma-standard-actors-v1.md](ma-standard-actors-v1.md) — standard actor interfaces (`#root`, `#scheduler`, `#logger`)

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
| `/ma/rpc/0.0.1` | `application/x-ma-rpc` and `application/x-ma-rpc-reply` only | OPTIONAL | §7 |
| `/ma/inbox/0.0.1` | any message type not claimed by a registered designated service (see rules) | OPTIONAL | §6.3 |
| `/ma/ipfs/0.0.1` | `application/x-ma-ipfs-request` only | OPTIONAL | §8 |

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
unconditionally to the target entity's `handle_cast`/`handle_message`
export (or dropped if unfragmented or the fragment is unknown). The `inbox`
capability string (§13.3) exists for implementations that choose to gate
this service, but the reference runtime does not check it here.

Access control for inbox-delivered messages, if desired, is the
**entity's own responsibility**: an entity plugin that wants to filter
senders must do so itself inside its Wasm handler — for example by sending
a `[:contains, caller]` query to a `ma-set` actor it manages (the same
mechanism used for `+#<fragment>` group resolution in §13.4) and dropping
or rejecting the message based on the result. The runtime provides no
built-in inbox ACL enforcement to delegate to.

### 6.4 Message-type routing

The runtime MUST route incoming messages based on the `type` field
(§2 of `ma-messaging-format-v1.md`) — **never** on `contentType`, which
carries no routing meaning — regardless of which registered service the
message physically arrived on (subject to the exclusivity rule in §6.1 —
once a designated service is registered, its message type MUST NOT also be
accepted on `/ma/inbox/0.0.1`):

- `application/x-ma-rpc` and `application/x-ma-rpc-reply` → §7 RPC dispatcher
- `application/x-ma-ipfs-request` → §8 IPFS publisher
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

1. `application/x-ma-rpc` content is always a single CBOR-encoded term (atom
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

Requests carry message type `application/x-ma-ipfs-request` and are
CBOR-encoded `IpfsRequestPayload` envelopes (defined in `ma-ipfs-service-v1.md`).

The payload contains:

- the caller's signed DID document (DAG-CBOR bytes);
- the caller's IPNS private key (used once for publishing, then zeroized);
- a timestamp for replay protection.

### 8.3 Validation

Before publishing, the runtime MUST:

1. Check the root ACL: caller holds `ipfs` capability. No → reject.
2. Apply replay protection (`ReplayGuard`, 120-second sliding window).
3. Validate the CBOR envelope:
   - verify the envelope signature;
   - check the message type;
   - validate and verify the DID document (including proof);
   - assert that the sender's IPNS identity matches the document's DID.
4. Publish via Kubo. Zeroize the IPNS key immediately after use.

### 8.4 Security

The IPNS private key in each request grants full publishing authority over
the sender's DID. It MUST be used exactly once and zeroized immediately after
the Kubo call completes. The runtime MUST NOT log, cache, or otherwise retain
the key material.

---

## 9. CRUD interface

Structured CRUD operations (get/set/delete of entities, kinds, config, and
ACLs) are provided **exclusively** by the `/ma/crud/0.0.1` service — see
[ma-crud-service-v1.md](ma-crud-service-v1.md) for the normative protocol
definition (`/`-separated path grammar, GET/SET/DELETE semantics,
`/ipfs/`/`/ipns/` value references, and reply conventions).

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
entity plugin's verb dispatch (`handle_cast` for stateless/inbox messages,
`handle_call` for stateful RPC messages).

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
5. Call the entity plugin's dispatch function (`handle_cast` for
   stateless / inbox messages; `handle_call` for stateful).

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
api:
  - handle_cast
host_functions:
  - ma_send
  - ma_reply
attributes:
  stateful: false
  wasi: false
```

**Required fields:** `protocol`, `api`, `host_functions`, `attributes.stateful`, `attributes.wasi`.

`attributes.stateful` is the authoritative source for whether a kind is stateful.
The runtime uses this to load persisted state, call `init()`, and persist state
after each `handle_call`.  It is never inferred from the `api` list.

Standard kind profiles:

| Profile | `attributes.stateful` | `api` | `host_functions` |
|---------|----------------------|-------|------------------|
| `stateless` | `false` | `[handle_cast]` | `[ma_send, ma_reply]` |
| `stateful` | `true` | `[init, handle_call]` | `[ma_send, ma_reply, ma_set_state]` |

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

Groups are referenced as **principals** using the `+#<fragment>` prefix,
where `<fragment>` is the bare name of a local entity implementing the
`ma-set` kind (an actor holding a set of member DIDs). There is no
dot-path or namespace notation for groups — `+#<fragment>` referencing a
local actor is the only supported group-reference syntax:

```yaml
+#fortune-friends: [fortune, secret]
+#admins: [admin, supersecret]
```

A `+group` entry works exactly like a DID entry: the runtime resolves group
membership by sending a `[:contains, caller]` RPC term to the local
`#<fragment>` actor referenced by the group and, if the actor reports the
caller as a member, applies that entry's capabilities. Resolution is a
single-member probe ("is `caller` a member?"), not a bulk membership fetch.
See §13.4 for the full evaluation order.

---

### 13.2 Canonical YAML format

Implementations MUST serialise and accept ACL maps in this exact form:

```yaml
# Transport gate — who may use which protocols
"*":              [rpc]            # everyone: RPC access
"did:ma:alice":   [rpc, inbox]     # alice: RPC + inbox
"did:ma:eve":                      # bare key → explicit deny

# Group entries — group members inherit these capabilities
"+#fortune-friends": [fortune, secret]
"+#admins": [admin, supersecret]
"+#banned":                    # group is explicitly denied
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
| `"ipfs"` | Transport | Enforced. Required to send to `/ma/ipfs/0.0.1` (§8). Bypassed for owners. |
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
`"handle_cast"`, `"enter"`) rather than this built-in list. An entity with
an empty `acl` field is deny-all (fail-closed).

Entity-level ACLs may use arbitrary strings as capability names
(`"handle_cast"`, `"reply"`, `"secret"`, etc.).

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

# Step 3 — Group principal scan (async, +prefix keys only)
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

The ACL document lives at the manifest root:

| Location | Type | Purpose |
|----------|------|---------|
| Root `.acl` | CID | Transport gate for the whole runtime (§13.7) |

Updating the ACL requires only replacing the CID at this location —
no manifest republish needed.

A missing or unresolvable CID MUST be treated as **deny all**.
Implementations SHOULD provide an operator recovery path for the case where
the root ACL becomes unreachable.

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
| `behavior` | yes | IPLD link (CID) to the Wasm module bytes |
| `state` | no | IPLD link (CID) to persisted state bytes (stateful only) |
| `wasi` | no | Boolean; WASI capability snapshot (default `false`) |

Example (YAML, before DAG-CBOR conversion):

```yaml
kind: /ma/stateful/python/0.0.1
behavior:
  "/": bafy...wasm_counter
state:
  "/": bafy...state_counter
wasi: false
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

### 14.2 Plugin ABIs

Two ABIs are defined. The kind protocol string determines which ABI a plugin
implements.

**Stateless ABI** — kind protocol contains `stateless`:

| Export | Signature | Description |
|--------|-----------|-------------|
| `handle_cast` | `(Bytes) → Bytes` | Called for every incoming fragment-addressed message |

**Stateful ABI** — kind protocol contains `stateful`:

| Export | Signature | Description |
|--------|-----------|-------------|
| `init` | `(Bytes) → Bytes` | Called once at plugin load; argument is persisted state bytes |
| `handle_call` | `(Bytes) → Bytes` | Called for every incoming fragment-addressed message |

The return value of every export is **ignored**. Plugins communicate outbound
via host functions only.

### 14.3 `CastInput` encoding

Both dispatch exports receive a single CBOR-encoded `CastInput` value:

```cbor
{
  "msg": {
    "id":           text,        ; unique message ID
    "from":         text,        ; sender DID or DID-URL
    "to":           text,        ; recipient DID-URL
    "reply_to":     text / null, ; message ID being replied to (if any)
    "content_type": text,        ; MIME type of content
    "content":      bytes        ; raw payload bytes
  },
  "ctx": {
    "self": text                 ; DID-URL of this entity, e.g. "did:ma:<ipns>#fortune"
  }
}
```

`init` receives the raw persisted state bytes; it is not a `CastInput` envelope.

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

### 14.5 Kind enforcement rules

- An entity **MUST** reference an existing kind.
- The runtime **MUST** verify that a plugin implements all exports listed in
  the kind's `api`.
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
def handle_cast():
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
5. **Create an EntityNode.** Author a YAML file referencing the kind and the
   behavior CID; publish to IPFS as DAG-CBOR.
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
      api: [handle_cast]
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
plugin Wasm module exports all functions listed in the kind's `api` field.
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
| `logger` | Structured log store |

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
