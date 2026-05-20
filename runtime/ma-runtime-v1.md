# ma-runtime-v1 — 間 Runtime Specification

**Status:** Draft  
**Version:** 0.1.0  
**Date:** 21 May 2026

---

## Abstract

A 間 (*ma*) runtime is an autonomous, content-addressed actor host. It
maintains a **runtime manifest** on IPFS, registers three iroh QUIC services
(RPC, inbox, and IPFS publishing), and manages a set of **entity plugins** —
Wasm modules compiled from any Extism-compatible language. Each entity is
addressable by a DID-URL fragment derived from its position in the IPLD
manifest tree.

This document is the normative specification for conforming 間 runtime
implementations. Companion documents:

- [ma-runtime-guide-v1.md](ma-runtime-guide-v1.md) — prose guide for
  operators and developers
- [generator-checklist-v1.md](generator-checklist-v1.md) — validation
  checklist for runtime generators

---

## Table of contents

1. [Introduction](#1-introduction)
2. [Overview](#2-overview)
3. [Identity integration](#3-identity-integration)
4. [Runtime manifest](#4-runtime-manifest)
5. [Namespaces](#5-namespaces)
6. [Transport services](#6-transport-services)
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
- the three **transport services** an implementation MUST register;
- the **dot-path grammar** for CRUD operations over RPC;
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
| **Namespace** | A named sub-tree in the manifest containing entities and data |
| **Fragment** | The part of a DID-URL after `#`; identifies an entity by dot-path |
| **Operator** | The DID identity that owns and controls the runtime |

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
 │  │ (dot-path CRUD, │  │ inbox/   │  │ (delegated IPNS  │ │
 │  │  fragment route)│  │ 0.0.1    │  │  publishing)     │ │
 │  └────────┬────────┘  └────┬─────┘  └──────────────────┘ │
 │           │                │                              │
 │  ┌────────▼────────────────▼──────────────────────────┐   │
 │  │  Manifest (IPLD DAG-CBOR root on IPFS / IPNS)      │   │
 │  │  ├── kinds:       flat protocol-ID → KindNode CID  │   │
 │  │  ├── #fortune:    EntityNode CID                   │   │
 │  │  ├── alice:       NamespaceNode (inline)           │   │
 │  │  │     └── #pet:  EntityNode CID                   │   │
 │  │  ├── config: { … }                                 │   │
 │  │  └── acl: { "/": "<cid>" }                         │   │
 │  └────────────────────────────────────────────────────┘   │
 └───────────────────────────────────────────────────────────┘
```

### 2.2 Key concepts

- **Content-addressed manifest.** All runtime state is a DAG of IPLD objects
  stored on IPFS. The manifest root CID is the single source of truth. The
  runtime's DID document contains an IPLD link to the current root.

- **Three services.** A conforming runtime MUST register exactly three iroh
  QUIC services: `/ma/rpc/0.0.1`, `/ma/inbox/0.0.1`, and (optionally)
  `/ma/ipfs/0.0.1`. See §6.

- **Entity plugins.** Each entity is an Extism Wasm module stored on IPFS and
  referenced from the manifest via an IPLD link. Entities are addressed by DID
  fragment (§10). The runtime loads plugins at startup, not on demand.

- **Capabilities, not ownership.** Access control uses named capability strings
  in `AclMap` documents (§13). There is no file-system-style ownership model.

- **CBOR on the wire; YAML for humans.** All peer-to-peer messages use CBOR.
  Operators author manifests and ACLs in YAML; the runtime converts to
  DAG-CBOR before publishing to IPFS. See §7.

### 2.3 Related specifications

- `did-ma-spec.md` — `did:ma` method, DID document structure, key types
- `ma-rpc-service-v1.md` — RPC content-type definitions
- `ma-ipfs-service-v1.md` — IPFS publish request format
- `messaging-format.md` — encrypted envelope format

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
`<fragment>` is the dot-path position of the entity key in the IPLD tree
(§10), traversable via `/ipfs/<did_doc_cid>/ma/runtime/…`.

---

## 4. Runtime manifest

The runtime manifest is the root IPLD DAG-CBOR object of the runtime's
content-addressed state. Its keys fall into three categories:

| Category | Key pattern | Stored as |
|----------|------------|-----------|
| Reserved system keys | `acl`, `kinds`, `config`, `lang`, `protocol` | Inline or IPLD link |
| Entity keys | `#<name>` | IPLD link → `EntityNode` |
| Namespace keys | NCName, not reserved | Inline `NamespaceNode` |

### 4.1 Reserved top-level keys

| Key | Required | Type | Description |
|-----|----------|------|-------------|
| `protocol` | yes | string | Protocol identifier (e.g. `/ma/runtime/0.1.0`) |
| `acl` | yes | IPLD link | Link to the root `AclMap` document. Absent means **deny all**. |
| `kinds` | yes | flat map | Protocol ID → IPLD link to a `KindNode` |
| `config` | yes | inline map | Key/value map for runtime metadata; publicly readable |
| `lang` | no | map | Locale code → IPLD link to an FTL locale file |

### 4.2 Entity keys (`#<name>`)

A top-level key whose name starts with `#` is an **entity key**. Its value
MUST be an IPLD link (`{ "/": "<cid>" }`) to an `EntityNode`. The `#` prefix
marks the key as a plugin instance.

The DID fragment for root entity `#rms` is `rms` (`did:ma:<ipns>#rms`).

### 4.3 Namespace keys

Any top-level key that is a valid NCName, is not reserved (§16.1), and does
not start with `#` is a **namespace key**. Its value is an inline
`NamespaceNode` object (not an IPLD link). See §5.

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

# Entity keys at root (zero or more)
"#rms":     { "/": "<cid>" }   # → did:ma:<ipns>#rms
"#fortune": { "/": "<cid>" }   # → did:ma:<ipns>#fortune

# Namespace keys (zero or more)
alice:                         # NamespaceNode (inline)
  acl:
    open: { "/": "<cid>" }
  "#pet": { "/": "<cid>" }     # → did:ma:<ipns>#alice.pet
bahner:
  acl:
    admin: { "/": "<cid>" }
  venner: [ "did:ma:carlotta", "did:ma:fjodor" ]
```

**Rules:**

- `kinds` is a **flat map** keyed by the full protocol identifier string.
  There is no nested family/implementation tree.
- Each kind node and entity node is a separate IPLD object linked via
  `{ "/": "<cid>" }`.
- Namespace nodes are stored **inline** in the manifest, not as separate
  IPLD links.

---

## 5. Namespaces

### 5.1 NamespaceNode structure

A `NamespaceNode` is an inline IPLD map with the following key categories:

| Key | Description |
|-----|-------------|
| `acl` | **Required.** IPLD link (CID) to the namespace `AclMap`. Controls which principals may reach any `#entity` in this namespace. A namespace without a resolvable `acl` is unreachable. |
| `acls` | *Optional.* Flat map of named IPLD links (CIDs) to `AclMap` documents: `acls.<name>` → CID. Used as the entity verb-ACL library; `EntityNode.acl` name strings resolve against this map. No further nesting inside `acls`. |
| `#<name>` | Entity key within this namespace — IPLD link to an `EntityNode` |
| other | Free IPLD sub-trees (blobs, lists, nested objects — including group membership lists) |

Namespace contents are stored inline in the manifest; they are not separately
linked IPLD nodes.

### 5.2 Namespace entity addressing

Entity keys inside a namespace follow the same `#` convention. A namespace
entity `alice.#pet` has the DID fragment `alice.pet`
(`did:ma:<ipns>#alice.pet`).

The fragment for a nested entity `bahner.alice.#bot` is `bahner.alice.bot`.

### 5.3 Namespace creation

Creating a namespace requires the calling principal to hold **both**
capabilities simultaneously in the root ACL (see §13.9):

1. `create` — generic create permission
2. `<ns>` — the namespace name as an explicit allocation grant

Neither capability is sufficient alone.

### 5.4 Namespace access control

Each namespace MUST carry an `acl` key — an IPLD link (CID) to an `AclMap`
that gates all access to entities and resources within the namespace. Without
a resolvable `acl`, the namespace is unreachable regardless of the root ACL.

The namespace `AclMap` uses the same format as the root ACL. Capability
strings in a namespace AclMap have namespace-scoped semantics:

| Capability | Grants within the namespace |
|-----------|-----------------------------|
| `read` | List or read namespace contents |
| `#<name>` | Access the entity at `#<name>` (send messages to it) |
| `<key>` (bare NCName) | Access to sub-key `<key>` within this namespace |
| `create`, `update`, `delete` | CRUD operations on namespace contents |
| `*` | All of the above |

Example:

```yaml
"*":                  [read, "#fortune"]   # everyone: read + reach #fortune
"did:ma:alice":       ["*"]                # alice: full control
"did:ma:carlotta":    [project2, create, update]
"group:alice.enemies":                    # bare key → explicit deny
```

The optional `acls` sub-tree is a flat map of named IPLD links (CIDs).
Entity verb-ACL names (stored in `EntityNode.acl`) are resolved against this
map. Granting access to many entities sharing the same ACL name requires
updating only one entry in `acls`.

**ACL resolution order** for an operation within namespace `<ns>`:

1. Root `.acl` — transport gate (checked on every incoming message)
2. `<ns>.acl` — namespace gate (checked before dispatching to any entity)
3. `<ns>.acls.<name>` — entity verb-ACL (checked inside entity dispatch)

The root transport ACL does not need updating after a namespace is created.

---

## 6. Transport services

### 6.1 Service requirements

A conforming runtime MUST register at least one of `/ma/rpc/0.0.1` or
`/ma/inbox/0.0.1` at startup. A runtime that registers neither is unreachable.

| Protocol ID | Content-type accepted | Requirement | Section |
|-------------|----------------------|-------------|---------|
| `/ma/rpc/0.0.1` | `application/x-ma-rpc` only | RECOMMENDED | §7, §9 |
| `/ma/inbox/0.0.1` | any non-RPC content type | REQUIRED to receive non-RPC messages | §6.3 |
| `/ma/ipfs/0.0.1` | `application/x-ma-ipfs-request` | OPTIONAL | §8 |

**Rules:**

- A runtime that only registers `/ma/rpc/0.0.1` MUST reject messages whose
  content type is not `application/x-ma-rpc`.
- A runtime that wants to receive text messages, chat, emotes, or any
  content not covered by RPC MUST register `/ma/inbox/0.0.1`.
- `/ma/ipfs/0.0.1` is an example of a purpose-specific service. Implementations
  SHOULD register additional services for well-defined message types rather
  than overloading the inbox with custom content types.
- All registered services MUST be advertised in `ma.services` in the DID
  document.

### 6.2 Service identity

Services are identified by their full protocol ID string. The runtime's own
DID document MUST advertise the services it has registered via the `services`
field (per `did-ma-spec.md`).

### 6.3 Inbox service — `/ma/inbox/0.0.1`

The inbox service carries text messages, chat messages, emotes, and any
content type other than `application/x-ma-rpc`.

#### Dispatch rules

| Message addressing | Handling |
|--------------------|---------|
| `did:ma:<ipns>` (no fragment) | Deliver to runtime operator inbox |
| `did:ma:<ipns>#<fragment>` | Route to entity plugin via §10 fragment lookup |

#### Transport gate

1. Check root ACL: caller holds `inbox` capability?  
   No → reply `[:error, "forbidden"]` and drop message.
2. If fragment present: resolve entity (§10); apply entity-level ACL.
3. Dispatch to entity plugin (`handle_cast`) or operator inbox.

Reply messages (non-null `reply_to` field) SHOULD bypass the entity ACL check
and be delivered directly, as they are responses to messages the entity
already sent.

ACL check: caller MUST hold `inbox` in the root ACL. Fragment-addressed
messages additionally require `inbox` in the entity's own ACL.

### 6.4 Content-type routing

The runtime MUST route incoming messages based on `content_type`:

- `application/x-ma-rpc` → §7 RPC dispatcher
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
| `":ping"` | Liveness check atom |
| `":kinds"` | List all registered kinds |
| `[":kinds", "/ma/stateless/python/0.0.1"]` | Get a kind by protocol ID |
| `[":config.ttl:", "3600"]` | Set config key `ttl` to `"3600"` |

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

Unfragmented RPC messages (`did:ma:<ipns>`, no `#`) are routed to the
dot-path dispatcher (§9).

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

Requests carry content-type `application/x-ma-ipfs-request` and are
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
   - check content-type;
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

### 9.1 Overview

Unfragmented RPC messages are dispatched through a dot-path grammar. Two
named root namespaces and one built-in atom are valid at the root level:

| Root | Description |
|------|-------------|
| `:kinds[.<protocol>]` | Kind registry CRUD (see §11) |
| `:config[.<key>]` | Runtime configuration CRUD (see §12) |
| `:ping` | Liveness check — reply `:pong` |

Unknown root namespaces MUST be rejected with
`[:error, "unknown operation: <term>"]`.

### 9.2 Grammar (normative ABNF)

```abnf
term           = atom / tuple
atom           = ":" path-or-simple
tuple          = "[" atom *arg "]"
arg            = cbor-value

path-or-simple = simple
               / dotpath
dotpath        = namespace *("." segment) [":" [verb]]
namespace      = "kinds" / "config"
segment        = 1*namechar
verb           = 1*namechar
namechar       = ALPHA / DIGIT / "_" / "-"
```

### 9.3 Operation semantics

| Pattern | Operation | Example |
|---------|-----------|---------|
| `:ns.key` | **Get** — retrieve leaf value or list subtree | `:config.ttl` |
| `":ns.key:"` (atom, empty verb) | **Delete** | `":config.ttl:"` |
| `[":ns.key:", <value>]` (tuple) | **Set / upsert** | `[":config.ttl:", "3600"]` |
| `:ns.key:verb` | **Verb dispatch** | `:kinds` list |

**Rules:**

- An atom without a `:verb` suffix is a *get* operation.
- An atom with an empty verb suffix (`:ns.key:`) is a *delete* operation.
- A tuple with a value argument after an empty-verb atom is a *set* operation.
- Unknown verbs MUST be rejected with
  `[:error, "unknown <namespace>.<name> operation: <term>"]`.
- Unknown root namespaces MUST be rejected with
  `[:error, "unknown operation: <term>"]`.
- Write operations require the caller to hold the appropriate CRUD capability
  (`create`, `update`, or `delete`) in the root ACL.

---

## 10. Fragment routing

### 10.1 Routing rule

Messages addressed to `did:ma:<ipns>#<fragment>` are routed **directly** to
the named entity plugin, bypassing the dot-path dispatcher.

The fragment identifies an entity by its **dot-path position** in the IPLD
tree, with the `#` prefix stripped from the entity key name:

| IPLD key path | DID fragment | DID-URL |
|---------------|-------------|---------|
| `#rms` (at root) | `rms` | `did:ma:<ipns>#rms` |
| `#fortune` (at root) | `fortune` | `did:ma:<ipns>#fortune` |
| `alice` / `#pet` | `alice.pet` | `did:ma:<ipns>#alice.pet` |
| `bahner` / `alice` / `#bot` | `bahner.alice.bot` | `did:ma:<ipns>#bahner.alice.bot` |

### 10.2 Resolution algorithm (normative)

1. Split the fragment on `.`: e.g. `["alice", "pet"]`.
2. Walk the manifest: all segments except the last are namespace keys; the
   last segment is prepended with `#` and looked up as an entity key in the
   current node.
3. If any step produces a miss, reply `[:error, "entity not found: <fragment>"]`.
4. Check the entity's own ACL: caller holds the required capability?  
   No → reply `[:error, "forbidden"]`.
5. Call the entity plugin's dispatch function (`handle_cast` for stateless /
   inbox messages; `handle_call` for stateful).

**Rule:** Fragment routing applies to both `/ma/rpc/0.0.1` and
`/ma/inbox/0.0.1`. The runtime MUST apply the entity's own ACL before
dispatch.

---

## 11. Kinds management

### 11.1 Overview

The `kinds` registry maps full protocol ID strings to IPLD links to
`KindNode` objects. Because protocol IDs contain slashes, they cannot be
embedded in dot-path segments; they are always passed as a CBOR text argument
in a tuple.

### 11.2 CRUD operations

| Term | Description | Reply |
|------|-------------|-------|
| `:kinds` | List all registered protocol IDs | `[:ok, ["/ma/stateless/python/0.0.1", ...]]` |
| `[":kinds", "<protocol>"]` | Get `KindNode` as CBOR bytes | `[:ok, <cbor-bytes>]` |
| `[":kinds:", "<protocol>", <cbor-bytes>]` | Create or update a kind | `:ok` |
| `[":kinds:", "<protocol>"]` | Delete a kind | `:ok` |

### 11.3 Rules

- `<protocol>` is the full protocol identifier string including the leading
  slash, e.g. `/ma/stateless/python/0.0.1`.
- Upsert and delete are distinguished by argument count: one text argument
  after `":kinds:"` is a delete; a text argument followed by bytes is an
  upsert.
- The runtime MUST verify that a `KindNode` being upserted has non-empty
  `api` and `host_functions` fields before accepting it.
- Write operations (upsert, delete) require the caller to hold `create`,
  `update`, or `delete` capability (as appropriate) in the root ACL.

### 11.4 KindNode structure

```yaml
protocol: /ma/runtime/cast/0.0.1
api:
  - handle_cast
host_functions:
  - ma_send
  - ma_reply
wasi: false
```

**Required fields:** `protocol`, `api`, `host_functions`.  
**Optional fields:** `wasi` (default `false`).

Standard kind profiles:

| Profile | `api` | `host_functions` |
|---------|-------|-----------------|
| `stateless` | `[handle_cast]` | `[ma_send, ma_reply]` |
| `stateful` | `[init, handle_call]` | `[ma_send, ma_reply, ma_set_state]` |

---

## 12. Config management

### 12.1 CRUD operations

Runtime configuration can be read and written via RPC.

| Term | Description | Reply |
|------|-------------|-------|
| `:config` | List all config keys | `[:ok, ["key1", "key2", ...]]` |
| `:config.<key>` | Get config value | `[:ok, <value>]` |
| `[":config.<key>:", <value>]` | Set config value | `:ok` |
| `":config.<key>:"` | Delete config key | `:ok` |

Write operations require the caller to hold `update` or `delete` capability
in the root ACL.

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

Groups are referenced as **principals** using the `group:<ns>.<name>` prefix:

```yaml
group:alice.venner: [fortune, secret]
group:alice.admins: [admin, supersecret]
```

A `group:` entry works exactly like a DID entry: the runtime resolves the
group's membership list (§13.5) and, if the caller is a member, applies that
entry's capabilities.

---

### 13.2 Canonical YAML format

Implementations MUST serialise and accept ACL maps in this exact form:

```yaml
# Transport gate — who may use which protocols
"*":              [rpc]            # everyone: RPC access
"did:ma:alice":   [rpc, inbox]     # alice: RPC + inbox
"did:ma:eve":                      # bare key → explicit deny

# Group entries — group members inherit these capabilities
"group:alice.venner": [fortune, secret]
"group:alice.admins": [admin, supersecret]
"group:alice.fiender":             # group is explicitly denied
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

The following capability strings have normative meanings at the transport and
resource-allocation layer. They MUST NOT be used as namespace or entity names
(see §16).

| Capability | Layer | Meaning |
|------------|-------|---------|
| `"inbox"` | Transport | May deliver messages via `/ma/inbox/0.0.1` |
| `"rpc"` | Transport | May call `/ma/rpc/0.0.1` |
| `"ipfs"` | Transport | May publish via `/ma/ipfs/0.0.1` |
| `"ping"` | Transport | May send `:ping` atom (subset of `rpc`) |
| `"read"` | CRUD | Read entities, config, namespace contents |
| `"create"` | CRUD | Generic create permission (required alongside a name cap) |
| `"update"` | CRUD | Update existing entities or namespace contents |
| `"delete"` | CRUD | Delete entities or namespaces |
| `"*"` (in Allow set) | Any | Grants all capabilities for this principal |
| `"#<name>"` | Resource | Authority over root entity `<name>` |
| `"<ns>"` (bare NCName) | Resource | Ownership grant for namespace `<ns>` |

Entity-level ACLs may use arbitrary strings as capability names
(`"handle_cast"`, `"reply"`, `"secret"`, etc.). The `#<name>` and `<ns>`
forms above are reserved only at the **root transport ACL** layer.

---

### 13.4 Evaluation algorithm (normative)

This section defines the **mandatory evaluation order** for implementations.
Deviation from this order produces incorrect deny-wins semantics.

**Input:** ACL map `A`, caller DID `caller`, required capability set
`required` (one or more capability strings, AND semantics).

**Pre-processing at load time (build once, reuse per check):**

- `null_groups` — set of ACL entry keys that start with `group:` and have a
  Deny value. Built by scanning the ACL map once at load time.
- `cap_index` — map from capability string → list of principal entry keys
  (DIDs, `group:` refs, or `"*"`) whose Allow set includes that capability.
  Built by scanning the ACL map once at load time.

**Per-check algorithm:**

```
normalised = strip_fragment(caller)

# Step 1 — Direct DID lookup (O(1))
if A[normalised] exists:
    entry = A[normalised]
    if entry is Deny:
        return DENY
    if entry is Allow(caps):
        if caps.contains("*") or required ⊆ caps:
            return ALLOW
        return DENY          ← direct entry but insufficient caps

# Step 2 — Check null groups (O(1) lookup per group)
for each group in null_groups:
    if normalised ∈ resolve_group(group):
        return DENY

# Step 3 — Wildcard entry (O(1))
if A["*"] exists:
    entry = A["*"]
    if entry is Deny:
        return DENY
    if entry is Allow(caps):
        accumulated = caps

# Step 4 — Capability-indexed group scan
for cap in required:
    if cap already satisfied by accumulated: continue
    for group in cap_index.get(cap, []):
        if A[group] is Deny: continue
        if normalised ∈ resolve_group(group):
            accumulated.add_all(A[group].caps)
            break

# Step 5 — Final decision
if required ⊆ accumulated or accumulated.contains("*"):
    return ALLOW
return DENY
```

**Rules:**

1. An explicit `null` (Deny) for the caller's DID terminates evaluation
   immediately — no wildcard or group can override it.
2. A direct DID match (step 1) terminates evaluation — the caller does not
   fall through to group or wildcard checks.
3. An empty sequence `[]` on a principal is a no-op allow (no capabilities
   granted). This is a warning condition, not an error.
4. Multiple required capabilities use **AND semantics**: ALL must be satisfied
   for the check to pass.
5. Group membership is checked lazily in step 4, guided by the capability
   index, to avoid loading groups that cannot satisfy the required cap.
6. A `group:` principal with a Deny value is skipped in step 4. Groups can
   only be denied via direct deny entries.

---

### 13.5 Group membership

Groups are **IPLD lists** stored as leaf values in the namespace tree:

```yaml
# In the RuntimeManifest
alice:
  venner: [ "did:ma:carlotta", "did:ma:fjodor" ]
  admins: [ "did:ma:bahner" ]
  fiender: [ "did:ma:eve" ]
```

A group reference in an ACL uses the path from the manifest root,
dot-separated: `group:alice.venner`, `group:alice.admins`.

**Resolution:** The runtime walks the IPLD path from the manifest root CID.
If the path leads to a list, each element is compared (fragment-stripped) to
the caller DID. If the path does not exist or does not resolve to a list,
membership is treated as **empty** (fail-closed).

---

### 13.6 Group cache

Group resolution is cached to avoid repeated IPFS round-trips on hot paths.

Cache structure (per runtime instance):

```
group_cache: HashMap<path, { cid: Cid, members: HashSet<Did> }>
```

- The cache key is the dot-path string (e.g. `alice.venner`).
- The `cid` field is the last-known CID of the list node.
- The `members` set is the resolved membership list.

**Refresh:** The cache entry is invalidated when the manifest root CID
changes or when the list node CID changes. A stale cache MUST NOT cause a
false ALLOW — on cache miss or uncertainty, implementations MUST re-resolve
from IPFS.

---

### 13.7 Performance guidance

| Pattern | Cost | Use when |
|---------|------|----------|
| Direct DID entry | O(1) | Known principals; hot path |
| `"*"` wildcard entry | O(1) | Open-access or default policy |
| Group entry (`"group:…"`) | O(1) cached / O(N)+IPFS cold | Large or dynamic groups |

Rules of thumb:
- Put the most common callers as **direct DID entries**.
- Use `"*": [...]` for broad default policies.
- Use group entries for large or dynamic membership lists.
- Do **not** use group entries on the transport gate if throughput matters.

---

### 13.8 ACL locations

ACL documents exist at five locations. CID columns store IPLD links to
`AclMap` documents; `EntityNode.acl` stores a **name string**, not a CID.

| Location | Type | Purpose |
|----------|------|---------|
| Root `.acl` | CID | Transport gate for the whole runtime (§13.9) |
| Root `.acls.<name>` | CID | Named ACL library for root-level `#entities` |
| `<ns>.acl` | CID | Namespace gate — controls access to all entities in `<ns>` |
| `<ns>.acls.<name>` | CID | Named ACL library for entities within `<ns>` |
| `EntityNode.acl` | name string | Verb-level gate — resolved via `acls.<name>` in scope |

Updating an ACL requires only replacing the CID at the relevant location —
no manifest republish, no entity node change.

**`EntityNode.acl` name resolution:**

1. Short name (e.g. `"fortune"`) — look up `acls.fortune` in the containing
   scope (current namespace, or manifest root if the entity is at root).
2. Full path (e.g. `"bob.acls.venner"`) — traverse the manifest from root,
   following the dot-separated key path.

Using a shared name means updating one `acls.<name>` entry propagates to all
entities that reference it, without modifying any `EntityNode`.

**Resolution order** for a fragment-addressed message to `<ns>.#entity`:

1. Root `.acl` — must hold the service capability (`rpc` or `inbox`)
2. `<ns>.acl` — must hold `#entity` (or `*`) capability
3. `<ns>.acls.<entity.acl>` — must hold the required verb capability

A missing or unresolvable CID at any level MUST be treated as **deny all**.
Implementations SHOULD provide an operator recovery path for the case where
the root ACL becomes unreachable.

**Client-side ACL:** Actors receiving messages MAY apply their own inbound
`AclMap` before delivering content to the application layer. Reply messages
identified by a matching `reply_to` field SHOULD bypass inbound ACL filtering.

---

### 13.9 Named resource capabilities and namespace allocation

The root transport ACL serves a dual role: it is both a **transport gate**
and a **resource allocation registry**.

Two naming conventions extend the standard capability set:

| Capability format | Grants |
|-------------------|--------|
| `#<name>` | Authority to manage the root entity `<name>` (update, delete, reload) |
| `<ns>` (bare NCName) | Ownership of namespace `<ns>` |

**Entity authority (`#<name>`):** A principal holding `#fortune` may update
or delete the `#fortune` entity at the manifest root. Generic `update` and
`delete` capabilities do **not** grant authority over specific named root
entities — the explicit `#<name>` capability is required.

**Namespace creation — two-capability rule:** To create namespace `alice`, the
calling principal MUST hold **both** capabilities simultaneously:

1. `create` — generic create permission
2. `alice` — the namespace name as an explicit allocation grant

Neither is sufficient alone. This prevents namespace squatting: the operator
controls which names can be claimed and by whom.

Example transport ACL:

```yaml
# bahner: owns alice namespace + manages the fortune entity
"did:ma:bahner": [create, update, delete, alice, "#fortune"]

# everyone: RPC access only
"*": [rpc]
```

With this ACL, `did:ma:bahner` may:
- Create, update, or delete the `alice` namespace (has `create` + `alice`)
- Manage the `#fortune` entity at root (has `#fortune`)
- Not create any other namespace (no other bare-name capability granted)

---

## 14. Entities

### 14.1 EntityNode structure

An `EntityNode` is an IPLD DAG-CBOR object stored separately from the
manifest and linked via `{ "/": "<cid>" }`.

| Attribute | Required | Description |
|-----------|----------|-------------|
| `kind` | yes | Full protocol ID of the kind (e.g. `/ma/stateless/python/0.0.1`) |
| `behavior` | yes | IPLD link (CID) to the Wasm module bytes |
| `acl` | yes | Name string resolved to an `AclMap` via `acls.<name>` in scope (see §13.8). Governs which verbs this entity's callers may invoke. |
| `state` | no | IPLD link (CID) to persisted state bytes (stateful only) |
| `wasi` | no | Boolean; WASI capability snapshot (default `false`) |

Example (YAML, before DAG-CBOR conversion):

```yaml
kind: /ma/stateful/python/0.0.1
behavior:
  "/": bafy...wasm_counter
state:
  "/": bafy...state_counter
acl: counter          # resolves to <ns>.acls.counter or root .acls.counter
wasi: false
```

**Rules:**

- The entity name is **not** stored inside the `EntityNode` — it is the key
  under which the node is linked in the manifest or namespace.
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
    "created_at":   uint,        ; Unix nanoseconds
    "expires":      uint,        ; Unix nanoseconds
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
4. **Register the kind.** Send `[":kinds:", "<protocol>", <kind-dag-cbor>]`
   to the runtime via RPC.
5. **Create an EntityNode.** Author a YAML file referencing the kind and the
   behavior CID; publish to IPFS as DAG-CBOR.
6. **Register the entity.** Place the entity in the manifest via the
   runtime's CRUD interface or via a new bootstrap.

### 15.3 Bootstrap workflow

The reference implementation supports a YAML bootstrap file that defines the
full initial manifest:

```yaml
runtime:
  "#fortune":
    kind: /ma/stateless/python/0.0.1
    behavior_cid: <wasm-cid>
    acl: ""
```

Running `ma --bootstrap bootstrap.yaml` publishes all KindNodes and
EntityNodes to IPFS, builds the manifest DAG, and registers it under the
operator's IPNS key.

### 15.4 Kind-plugin validation

At bootstrap and at kind upsert time, the runtime SHOULD verify that the
plugin Wasm module exports all functions listed in the kind's `api` field.
This catches mismatches between the kind descriptor and the actual module
before any messages are dispatched.

---

## 16. Reserved names registry

The following names are reserved and MUST NOT be used as namespace keys,
entity key names (with or without `#` prefix), or user-defined capability
strings at the root manifest level.

### 16.1 Reserved system keys (manifest top level and namespace level)

These names are used as structural keys in the `RuntimeManifest` and in every
`NamespaceNode`. They MUST NOT be used as namespace names or entity key names:

| Name | Role |
|------|------|
| `acl` | ACL gate document link (CID) — at root and inside every namespace |
| `acls` | Named ACL library map — at root and inside every namespace |
| `config` | Runtime configuration map |
| `kinds` | Kind registry |
| `lang` | Locale file links |
| `protocol` | Runtime protocol identifier |

### 16.2 Reserved capability strings (transport and CRUD layer)

These names are used as built-in capability strings (§13.3). They MUST NOT
be used as namespace names because they would be ambiguous with capability
grants in ACL entries:

| Name | Meaning |
|------|---------|
| `rpc` | Access to `/ma/rpc/0.0.1` |
| `ipfs` | Access to `/ma/ipfs/0.0.1` |
| `inbox` | Access to `/ma/inbox/0.0.1` |
| `ping` | Liveness check atom |
| `read` | Read-only access |
| `create` | Generic create permission |
| `update` | Update permission |
| `delete` | Delete permission |

### 16.3 Caution: names resembling service endpoints

Namespace names that match, abbreviate, or closely resemble a service name
create ambiguity in logs, tooling, ACL authoring, and future protocol
extensions. Operators SHOULD avoid the following as namespace or entity names:

- Any name that is also a segment of a registered `did:ma` protocol ID
  (e.g. `ma`, `stateless`, `stateful`, `python`, `ping`, `rpc`, `ipfs`,
  `inbox`).
- Version-like names: `v0`, `v1`, `v2`, `0.0.1`, and similar.
- Names that shadow iroh service identifiers or future reserved protocol
  namespaces.

The runtime SHOULD warn (and MAY reject) namespace creation where the name
matches a known protocol ID path segment from its own `kinds` registry.

### 16.4 Enforcement

- The runtime MUST reject any attempt to create a namespace or entity whose
  name (stripped of `#` prefix) appears in §16.1 or §16.2.
- The runtime MUST reject any `acl` document where a YAML key in the
  capability position matches a reserved system key from §16.1.
- Validators (generators, linters) SHOULD flag reserved names at build time.
- The reserved list MAY be extended in future minor versions of this
  specification.

---

*Draft — 21 May 2026*
