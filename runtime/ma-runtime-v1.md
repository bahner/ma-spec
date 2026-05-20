# ma-runtime-v1: Runtime Specification

**Version:** 0.1.0
**Status:** Draft

This specification is implementation-agnostic and serves as the contract for
runtime generators in any language (e.g. Elixir, Rust).

For a point-by-point validation profile for generators, see
[generator-checklist-v1.md](generator-checklist-v1.md).

---

## `runtime` field in the DID document

- The `runtime` field MUST be an IPLD link to a content CID:
  ```yaml
  runtime:
    "/": bafy...runtime_root
  ```
- The runtime link MUST be directly traversable as an IPLD DAG without
  additional resolver logic.
- When the runtime manifest changes, the DID document MUST be republished so
  that `runtime` points to the new root CID.

  **Rationale:** A direct CID link enables simple, deterministic DAG traversal
  (`/ipfs/<did_doc_cid>/ma/runtime/…`) and avoids an extra IPNS indirection
  in the `runtime` field.

---

## Table of contents

1. [Runtime manifest structure](#1-runtime-manifest-structure)
2. [Extism plugins](#2-extism-plugins)
3. [Host functions](#3-host-functions)
4. [Kind system](#4-kind-system)
5. [Manifest examples](#5-manifest-examples)
6. [Security and update flow](#6-security-and-update-flow)
7. [Migration from earlier specifications](#7-migration-from-earlier-specifications)
8. [RPC dot-path grammar](#8-rpc-dot-path-grammar)
9. [Wire format and data layers](#9-wire-format-and-data-layers)
10. [Fragment-addressed messages and DID routing](#10-fragment-addressed-messages-and-did-routing)
11. [Kinds management — `:kinds.*`](#11-kinds-management----kinds)
12. [Config management — `:config.*`](#12-config-management----config)
13. [ACL and capabilities model](#13-acl-and-capabilities-model)
14. [Reserved names registry](#14-reserved-names-registry)

---

### [1] Runtime manifest structure

The runtime manifest is an IPLD object (DAG-CBOR) stored on IPFS. Its keys
fall into three categories: **reserved system keys**, **entity keys**
(prefixed with `#`), and **namespace keys** (any valid NCName not reserved).

#### 1.1 Reserved top-level keys

| Key | Required | Description |
|-----|----------|-------------|
| `acl` | yes | IPLD link to the root `AclMap` document. Absent means **deny all**. |
| `kinds` | yes | Flat map from protocol ID to IPLD link to a `KindNode` |
| `config` | yes | Key/value map for runtime metadata; publicly readable |
| `lang` | no | Map from locale code to IPLD link to an FTL locale file |
| `protocol` | no | Protocol identifier string (e.g. `/ma/runtime/0.1.0`) |

The following names are additionally **reserved as protocol-level capability
strings** and MUST NOT be used as namespace or entity names:
`rpc`, `ipfs`, `inbox`, `ping`, `read`, `create`, `update`, `delete`.

See §14 for the complete reserved-name registry.

#### 1.2 Entity keys (`#<name>`)

A top-level key whose name starts with `#` is an **entity key**. Its value
MUST be an IPLD link (`{ "/": "<cid>" }`) to an `EntityNode`. The `#` prefix
marks the key as a plugin instance; the runtime instantiates it accordingly.

The DID fragment for a root entity `#rms` is `rms`
(`did:ma:<ipns>#rms`).

#### 1.3 Namespace keys

Any top-level key that is a valid NCName and is neither reserved nor prefixed
with `#` is a **namespace key**. Its value is an inline `NamespaceNode`
object (not a link). Namespaces can contain their own `acl` sub-tree and
their own entity keys (see §1.4).

Creating a namespace requires holding both `create` AND the namespace name as
capabilities in the root ACL (see §13.7).

#### 1.4 Namespace structure

A `NamespaceNode` has:

| Key | Description |
|-----|-------------|
| `acl` | Sub-tree of named ACL documents: `acl.<name>` → IPLD link to `AclMap` |
| `#<name>` | Entity key within this namespace |
| other | Free IPLD sub-trees (blobs, lists, nested objects) |

Entity keys inside a namespace follow the same `#` convention. A namespace
entity `alice.#pet` has the DID fragment `alice.pet`
(`did:ma:<ipns>#alice.pet`).

#### 1.5 Normative top-level structure (YAML)

```yaml
# Reserved system keys
protocol: /ma/runtime/0.1.0
acl: { "/": "<cid>" }
kinds:
  /ma/stateless/python/0.0.1: { "/": "<cid>" }
  /ma/stateful/python/0.0.1:  { "/": "<cid>" }
config:
  owner: did:ma:<runtime_owner_ipns>
lang:
  en: { "/": "<cid>" }
  nb: { "/": "<cid>" }

# Entity keys at root (zero or more)
"#rms":     { "/": "<cid>" }   # → did:ma:<ipns>#rms
"#fortune": { "/": "<cid>" }   # → did:ma:<ipns>#fortune

# Namespace keys (zero or more)
alice:                         # NamespaceNode
  acl:
    open: { "/": "<cid>" }
  "#pet": { "/": "<cid>" }     # → did:ma:<ipns>#alice.pet
bahner:
  acl:
    admin: { "/": "<cid>" }
  venner: [ "did:ma:carlotta", "did:ma:fjodor" ]
```

Each kind node and entity node is a separate IPLD object linked via
`{ "/": "<cid>" }`. Namespace nodes are stored **inline** in the manifest,
not as separate IPLD links.

`kinds` is a **flat map** keyed by the full protocol identifier string
(e.g. `/ma/stateless/python/0.0.1`). There is no nested family/implementation
tree.

### [2] Extism plugins

All entities are Wasm modules (Extism plugins) stored on IPFS. Each entity
references its plugin via an IPLD link (`behavior`) to the Wasm bytes.

#### Plugin ABIs

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

#### Input encoding for `handle_cast` / `handle_call`

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

`init` receives the raw persisted state bytes (the bytes last written by
`ma_set_state`); it is not a CBOR envelope.

### [3] Host functions

Host functions are registered in the `extism:host/user` namespace. Only the
functions listed in the kind's `host_functions` field are registered for a
given plugin instance (principle of least privilege).

#### `ma_send`

Queue an outbound message. Available to all plugin kinds.

```
ma_send(Bytes) → Bytes
```

Argument — CBOR-encoded outbound envelope:

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
automatically from the original message. Available to all plugin kinds.

```
ma_reply(Bytes) → Bytes
```

Argument — CBOR-encoded reply request:

```cbor
{
  "msg":          LocalMessage, ; the original message (same shape as CastInput.msg)
  "content_type": text,         ; MIME type of the reply body
  "content":      bytes         ; reply body bytes
}
```

Return value: ignored.

#### `ma_set_state`

Queue new state bytes for IPFS persistence. Available to **stateful** plugin
kinds only.

```
ma_set_state(Bytes) → Bytes
```

Argument: raw state bytes (any encoding the plugin chooses; the runtime
treats them as opaque and passes them back to `init` on next load).

The runtime persists the bytes to IPFS after the dispatch call returns. The
call is a no-op if the bytes are identical to the last persisted snapshot.

Return value: ignored.

### [4] Kind system

Kinds define which protocols, API, and host functions a plugin receives.
This is the core of the generator contract.

#### Kind attributes

Required attributes:
- `protocol`: protocol ID for this kind
- `api`: list of required plugin exports
- `host_functions`: list of permitted host functions

Optional attributes:
- `wasi`: boolean flag for WASI capability

Example (YAML):
```yaml
protocol: /ma/runtime/cast/0.0.1
api: [handle_cast]
host_functions: [ma_send, ma_reply]
wasi: false
```

Standard kind profiles:
- `stateless`: `api: [handle_cast]`, `host_functions: [ma_send, ma_reply]`
- `stateful`: `api: [init, handle_call]`, `host_functions: [ma_send, ma_reply, ma_set_state]`

An entity references a kind by name:
```yaml
kind: /ma/stateful/python/0.0.1
```

`wasi` in an entity is an explicit snapshot of the capability from the
referenced kind at bootstrap/creation time. The runtime MUST NOT derive
`wasi` dynamically per call.

#### Normative rules for kinds

- An entity **MUST** reference an existing kind.
- The runtime **MUST** verify that a plugin implements all exports listed in
  the kind's `api`.
- The runtime **MUST NOT** register host functions beyond those listed in the
  kind's `host_functions`.

### [5] Manifest examples

#### Example A: RuntimeManifest (root)

```yaml
# Reserved system keys
protocol: /ma/runtime/0.1.0
kinds:
  /ma/stateless/python/0.0.1: { "/": "bafy...kind_stateless_python" }
  /ma/stateful/python/0.0.1:  { "/": "bafy...kind_stateful_python" }
  /ma/fortune/0.0.1:          { "/": "bafy...kind_fortune" }
acl: { "/": "bafy...acl" }
config:
  owner: did:ma:bafz...owner
lang:
  en: { "/": "bafy...en_ftl" }
  nb: { "/": "bafy...nb_ftl" }

# Root entity keys (→ did:ma:<ipns>#fortune, did:ma:<ipns>#counter)
"#fortune": { "/": "bafy...entity_fortune" }
"#counter": { "/": "bafy...entity_counter" }

# Namespace (inline NamespaceNode)
alice:
  acl:
    friends: { "/": "bafy...alice_friends_acl" }
  "#pet": { "/": "bafy...entity_alice_pet" }    # → did:ma:<ipns>#alice.pet
  venner: [ "did:ma:carlotta", "did:ma:fjodor" ]
```

#### Example B: KindNode (stateful)

```yaml
protocol: /ma/runtime/call/0.0.1
api:
  - init
  - handle_call
host_functions:
  - ma_send
  - ma_reply
  - ma_set_state
wasi: false
```

#### Example C: EntityNode (counter)

```yaml
kind: /ma/stateful/python/0.0.1
behavior:
  "/": bafy...wasm_counter
state:
  "/": bafy...state_counter
owner: did:ma:bafz...owner
acl:
  "/": bafy...acl_cid
wasi: false
```

Note: The entity name is **not** stored inside the `EntityNode` itself —
it is the key under which the node is linked in the manifest or namespace.
Implementations MUST derive the entity's address from its position in the
IPLD tree, not from a `name` field.

#### EntityNode attributes

Required attributes:
- `kind`
- `behavior`
- `owner`
- `acl`

Optional attributes:
- `state`
- `wasi`

Rules:
- For stateless entities `state` SHOULD be omitted on serialisation.
- Readers SHOULD accept both a missing `state` and `state: null` for
  backwards compatibility.

### [6] Security and update flow

The runtime manifest is published under an IPNS link and can be updated
without changing the DID document. The DID document is republished on change
or on a configurable interval.

- Changes are authorised by the identity in `config.owner`.
- Plugins receive only the host functions they need.
- State MAY be encrypted if required.

Generators SHOULD validate:
- all kind links and entity links are valid IPLD links
- all entities reference a kind listed in the manifest
- all kinds have explicit `api` and `host_functions` fields

### [7] Migration from earlier specifications

Previously `runtime` could be described via an IPNS string. It MUST now be a
direct CID-based IPLD link. Kinds, entities, and plugin architecture are now
explicitly modelled in the manifest as language-agnostic nodes with YAML
examples.

---

### [8] RPC dot-path grammar

Unfragmented RPC messages — addressed to `did:ma:<ipns>` with no fragment —
are routed to the runtime's built-in dot-path dispatcher. Fragmented messages
(`did:ma:<ipns>#<name>`) are delivered directly to the named entity plugin
(see §10).

#### Root namespaces

Two root namespaces plus one built-in atom are valid:

| Root | Description |
|------|-------------|
| `:kinds[.<protocol>]` | Kind registry (read-only) |
| `:config[.<key>]` | Runtime configuration |
| `:ping` | Liveness check |

#### Grammar (normative)

```abnf
term           = atom / tuple
atom           = ":" path-or-simple
tuple          = "[" atom *arg "]"
arg            = cbor-value         ; bytes, text, int, bool, array, map ...

path-or-simple = simple             ; ":ping", ":pong", ...
               / dotpath            ; ":config.ttl"
dotpath        = namespace *("." segment) [":" verb]
namespace      = "kinds" / "config"
segment        = 1*namechar
verb           = 1*namechar
namechar       = ALPHA / DIGIT / "_" / "-"
```

**Rules:**

- An atom without a `:verb` suffix is a *get* operation (retrieve value or
  list subtree).
- An atom with an empty verb suffix (`:config.ttl:`) is a *delete*
  operation.
- A tuple with a text argument after an atom with an empty verb is a
  *set/upsert* operation.
- Unknown verbs MUST be rejected with
  `[:error, "unknown <namespace>.<name> operation: <term>"]`.
- Unknown root namespaces MUST be rejected with
  `[:error, "unknown operation: <term>"]`.

#### Reply format (normative)

| Outcome | Reply |
|---------|-------|
| Success, no payload | `:ok` (atom) |
| Success with payload | `[:ok, <cbor-value>]` |
| Error | `[:error, "<message>"]` |
| Liveness reply | `:pong` (atom) |

Reply messages MUST set `replyTo` to the `id` of the incoming message.
The reply is delivered on the sender's `/ma/rpc/0.0.1` service.

---

### [9] Wire format and data layers

All peer-to-peer messages use **CBOR only** on the wire. JSON is never sent
between peers. This is a hard requirement.

#### Format overview

| Context | Format | Rationale |
|---------|--------|-----------|
| Peer-to-peer transport | CBOR | Compact, typed, unambiguous serialisation |
| IPFS storage | DAG-CBOR | Content-addressed, deterministic hashing |
| User interface (editor) | YAML | Human-readable and editable |
| Kubo HTTP API (internal) | JSON | Internal implementation detail; not visible to peers |
| IPFS gateway response | DAG-JSON | Gateway converts DAG-CBOR automatically |

#### Normative rules

1. `application/x-ma-rpc` content is always a single CBOR-encoded term (atom
   or tuple).
2. Bytes arguments in tuples (`CborValue::Bytes`) are raw DAG-CBOR — not JSON,
   not YAML.
3. Text arguments in tuples (`CborValue::Text`) are plain strings (e.g. CID,
   DID).
4. An EntityNode is edited in YAML by the client but is **always stored and
   transmitted as DAG-CBOR**.
5. The Kubo integration (`/api/v0/dag/put`, `/api/v0/dag/get`) is an internal
   implementation detail of the runtime. JSON returned by Kubo is **never**
   forwarded to peers.

#### `dag_put_raw` vs. `dag_put<T>`

| Function | Input | Use |
|----------|-------|-----|
| `dag_put<T: Serialize>` | Rust struct → JSON → DAG-CBOR via Kubo | Internal publishing |
| `dag_put_raw(bytes)` | Pre-encoded DAG-CBOR bytes | Client-supplied EntityNode |

`dag_put_raw` posts bytes with `input-codec=dag-cbor, store-codec=dag-cbor`
so that Kubo treats them as already-serialised DAG-CBOR and does not attempt
to parse them as JSON.

---

### [10] Fragment-addressed messages and DID routing

#### 10.1 Routing rule

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

**Algorithm:**

1. Split the fragment on `.`: `["alice", "pet"]`.
2. Walk the manifest: all segments except the last are namespace keys;
   the last segment is prepended with `#` and looked up as an entity key.
3. If any step produces a miss, reply `[:error, "entity not found: <fragment>"]`.
4. Load the entity plugin and call `handle_cast`.

**Rule:** Fragment-addressed messages are delivered on both `/ma/rpc/0.0.1`
and `/ma/inbox/0.0.1`. The runtime MUST apply the entity's own ACL before
dispatch (see §13.6).

#### 10.2 Fragment addressing in the RPC grammar

The `:entities` dot-path namespace (§8) uses **fragment-style paths** when
addressing specific entities:

```
:entities.<fragment>[:<verb>]
```

Where `<fragment>` is the same dot-path used in DID-URLs — e.g.
`:entities.alice.pet` refers to the entity at `alice.#pet` in the IPLD tree.

Example: A message to `did:ma:bafz...sky#rms` calls `handle_cast` on the
`#rms` plugin at the manifest root.

---

### [11] Kinds management — `:kinds.*`

The kinds registry is read-only from external clients.

| Term | Description | Reply |
|------|-------------|-------|
| `:kinds` | List all registered protocol IDs | `[:ok, ["/ma/stateless/python/0.0.1", ...]]` |
| `[":kinds", "<protocol>"]` | Get `KindNode` as CBOR bytes | `[:ok, <cbor-bytes>]` |

`<protocol>` is the full protocol identifier string, including the leading
slash — e.g. `/ma/stateless/python/0.0.1`. Because protocol IDs contain
slashes they cannot be encoded as dot-path segments; they are passed as a
CBOR text argument in a tuple.

Write operations on `:kinds.*` MUST be rejected with
`[:error, "kinds is read-only"]`.

---

### [12] Config management — `:config.*`

Runtime configuration can be read and written via RPC.

| Term | Description | Reply |
|------|-------------|-------|
| `:config` | List all config keys | `[:ok, ["key1", "key2", ...]]` |
| `:config.<key>` | Get config value | `[:ok, <value-text>]` |
| `[":config.<key>:", <value-text>]` | Set config value | `:ok` |
| `":config.<key>:"` | Delete config key | `:ok` |

ACL checks apply for write operations; only authorised senders may modify
config.

---

---

### [13] ACL and capabilities model

All ACL maps (`AclMap`) use a **capabilities model**: every operation a caller
can perform is guarded by a named capability string. The map is a flat YAML
object with two distinct key/value notations — **principal entries** and
**capability-grant entries** — which serve different purposes and have very
different performance characteristics.

Understanding the difference is essential for writing correct ACLs and
reasoning about runtime overhead.

---

#### 13.1 The two notations

##### 15.1.1 Principal entries — O(1)

A _principal entry_ maps an identity (a full DID or the `"*"` wildcard) to one
of three values:

| YAML value | Parsed as | Meaning |
|------------|-----------|---------|
| `null` or bare key | `Deny` | Caller is **always denied**, regardless of wildcards |
| YAML sequence | `Allow([...])` | Caller is **allowed** the listed capabilities |
| (absent) | `Deny` | No entry → same as explicit `null` |

The check is a single hash-map lookup: **O(1)**.

##### 15.1.2 Capability-grant entries — O(N)

A _capability-grant entry_ maps a **capability name** (a plain word, not a DID
or `"*"`) to a comma-separated list of _grantees_. Each grantee is either a
bare DID or a `group:<ns>.<name>` reference that must be resolved over IPFS.

| YAML value | Parsed as | Meaning |
|------------|-----------|---------|
| YAML string | `Grant([...])` | These principals (or group members) receive this capability |

Resolving a `group:` reference requires:
1. Fetching the runtime manifest from IPFS (one Kubo round-trip)
2. Following the IPFS link to the group member list (second Kubo round-trip)

Cost: **O(N)** in the number of grantees × up to 2 IPFS round-trips per
`group:` reference. These are never cached between requests. Use sparingly on
hot paths.

---

#### 13.2 Canonical YAML format

Implementations MUST serialise and accept ACL maps in this exact form. Any
other representation is non-canonical.

```yaml
# ── Principal entries (O(1)) ──────────────────────────────────────────
"*":              [rpc, ipfs]       # wildcard — everyone gets rpc + ipfs
"did:ma:alice":   ["*"]            # alice — all capabilities (wildcard cap)
"did:ma:bob":     [rpc]             # bob — RPC only
"did:ma:eve":                       # null → explicit deny (overrides wildcard)

# ── Capability-grant entries (O(N)) ───────────────────────────────────
fortune: "group:carlotta.friends,did:ma:dave"
```

Serialisation rules (normative):

- A `Deny` entry MUST serialise as a bare YAML key with no value (implicit
  `null`). Parsers MUST accept both bare key and explicit `null`.
- An `Allow` entry MUST serialise as a YAML sequence. It MUST NOT be written
  as a string. Parsers that receive a sequence MUST treat it as `Allow`.
- A `Grant` entry MUST serialise as a comma-separated string. It MUST NOT be
  written as a sequence. Parsers that receive a string MUST treat it as
  `Grant` (split by comma, trim whitespace).

  The three forms (`null`, sequence, string) are unambiguous: a conforming parser
  distinguishes them by YAML value type, not by content.

---

#### 13.3 Built-in capability strings

| Capability | Meaning |
|------------|---------|
| `"inbox"` | May deliver messages via `/ma/inbox/0.0.1` |
| `"rpc"` | May call `/ma/rpc/0.0.1` |
| `"ipfs"` | May publish DID documents via `/ma/ipfs/0.0.1` |
| `"read"` | Read entities, config, namespace contents (reserved) |
| `"create"` | Generic create permission (necessary but not sufficient for namespaces — see §13.7) |
| `"update"` | Update namespaces or entities |
| `"delete"` | Delete namespaces or entities |
| `"*"` (in Allow set) | Grants **all** capabilities for this principal |
| `"#<name>"` | Authority over root entity `<name>` (manage, update, delete) |
| `"<ns>"` (bare NCName) | Ownership grant for namespace `<ns>`; required alongside `create` to create it (see §13.7) |

Verb-level and sub-namespace ACLs may use arbitrary strings as capability
names (`"handle_cast"`, `"reply"`, etc.). The `#<name>` and `<ns>` conventions
above are reserved for resource allocation at the manifest transport ACL.

---

#### 13.4 Evaluation algorithm (normative)

Given: ACL map `A`, caller DID `caller`, required capability `cap`.

```
1. normalised = strip_fragment(caller)

2. if A[normalised] exists:
     if Allow(caps):  return caps.contains(cap) || caps.contains("*")
     if Deny:         return false          ← deny always wins

3. if A["*"] exists:
     if Allow(caps):  return caps.contains(cap) || caps.contains("*")
     if Deny:         return false

4. if A[cap] exists and is Grant(refs):     ← O(N) path
     for each ref in refs:
       if ref starts with "group:":
         members = resolve_group(root_cid, ref.strip_prefix("group:"))
         if strip_fragment(normalised) in members: return true
       else:
         if strip_fragment(ref) == normalised: return true

5. return false   ← default deny
```

Steps 2 and 3 are O(1) hash lookups. Step 4 is only reached when the caller
has **no direct or wildcard entry** and there is a capability-grant for `cap`.

**Deny always wins** in steps 2 and 3: an explicit `null` for a principal
blocks that caller even if a `"*"` wildcard allow exists.

Grant entries (step 4) cannot override a deny — they are only consulted when
the principal is entirely absent from the principal-entry space.

---

#### 13.5 Performance guidance

| Pattern | Cost | Use when |
|---------|------|----------|
| Direct DID entry | O(1) | Known principals; hot path |
| `"*"` wildcard entry | O(1) | Open-access or default policy |
| Capability-grant (`"cap": "group:..."`) | O(N) + IPFS | Large groups managed outside the manifest |

Rules of thumb:
- Put your most common callers as **direct DID entries** so they are resolved
  in a single hash lookup.
- Use `"*": [...]` for broad default policies. Override specific principals
  with direct entries.
- Use capability-grant entries only when the group is too large or too dynamic
  to enumerate statically in the manifest. Accept the latency.
- Never use capability-grant entries on the transport gate (step 2 in §13.4)
  if throughput matters — prefer direct or wildcard entries for inbox/rpc.

---

#### 13.6 ACL locations

| Location | Guards |
|----------|--------|
| `.acl` (runtime manifest) | Transport gate + resource allocation registry (see §13.7) |
| `<ns>.acl` | Create/update/delete inside namespace `<ns>` |
| `#<entity>.acl` | Who may invoke this entity's verbs |

All three locations store an **IPLD link** to an `AclMap` object. An ACL
update does not require republishing the manifest or entity node — only the
link needs updating.

A missing or unresolvable ACL link MUST be treated as **deny all**. There is
no file-based ACL. Implementations SHOULD provide a recovery mechanism for
the case where the transport gate locks out the operator.

**Client-side ACL:** Actors receiving messages MAY apply their own inbound
`AclMap` before delivering content to the application layer. The same
capability model applies — typically `inbox` and `rpc`. Reply messages
identified by a matching `reply_to` field SHOULD bypass inbound ACL
filtering. The specifics are outside the scope of this specification.

---

#### 13.7 Named resource capabilities and namespace allocation

The manifest transport ACL (`.acl` at the root) serves a dual role: it is
both a **transport gate** and a **resource allocation registry**.

Two naming conventions extend the standard capability set:

| Capability format | Grants |
|-------------------|--------|
| `#<name>` | Authority to manage the root entity `<name>` (update, delete, reload) |
| `<ns>` (bare NCName) | Ownership of namespace `<ns>` |

**Entity authority (`#<name>`):** A principal that holds `#fortune` may update
or delete the `fortune` entity at the manifest root. Generic `update` and
`delete` capabilities do **not** grant authority over specific named root
entities — the explicit `#<name>` capability is required.

**Namespace creation — two-capability rule:** To create namespace `alice`, the
calling principal MUST hold **both** capabilities simultaneously:

1. `create` — generic create permission
2. `alice` — the namespace name as an explicit allocation grant

Neither is sufficient alone. This prevents self-service namespace squatting:
the operator controls which names are available to which identities, making
namespace names a controlled resource that must be explicitly granted.

Example transport ACL:

```yaml
# bahner: owns alice namespace + manages the fortune entity
"did:ma:bahner": [create, update, delete, alice, "#fortune"]

# everyone: RPC access only, no resource authority
"*": [rpc]
```

With this ACL, `did:ma:bahner` may:
- Create, update, or delete the `alice` namespace (has `create` + `alice`)
- Manage the `#fortune` entity at root (has `#fortune`)
- Not create any other namespace (no other bare-name capability granted)

**Namespace ACL inherits and refines:** once a namespace is created, its own
`<ns>.acl` governs what happens inside it. The transport ACL does not need
updating once ownership is established.


*Draft — 20 May 2026*
