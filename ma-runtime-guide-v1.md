# ma-runtime-guide-v1 — 間 Runtime Operator and Developer Guide

**Status:** Draft  
**Version:** 0.1.0  
**Date:** 21 May 2026

---

This guide is a prose introduction to the 間 runtime. It is written for
operators deploying a runtime and developers writing entity plugins. It
assumes familiarity with IPFS and the `did:ma` method.

For the normative specification, see [ma-runtime-v1.md](ma-runtime-v1.md).  
---

## Table of contents

1. [What is a 間 runtime?](#1-what-is-a-間-runtime)
2. [RPC — how messages work](#2-rpc--how-messages-work)
3. [IPFS — delegated publishing](#3-ipfs--delegated-publishing)
4. [CRUD — the dot-path interface](#4-crud--the-dot-path-interface)
5. [Namespaces — layout and naming](#5-namespaces--layout-and-naming)
6. [ACLs — capabilities replace ownership](#6-acls--capabilities-replace-ownership)
7. [Entities — the cornerstone](#7-entities--the-cornerstone)
8. [Development — writing and deploying plugins](#8-development--writing-and-deploying-plugins)

---

## 1. What is a 間 runtime?

A 間 runtime is an actor host. It gives a `did:ma` identity a set of
*capabilities* — plugin-backed behaviours that other actors can invoke by
sending messages to a DID-URL fragment address.

Think of a runtime as an always-on process that:

- **holds an identity** — its own `did:ma:<ipns>` DID, with an iroh QUIC
  endpoint advertising its services;
- **manages a manifest** — a content-addressed IPLD tree stored on IPFS that
  records what entities it runs, what kinds they are, and who may talk to
  them;
- **routes messages** — incoming messages are inspected and dispatched to the
  right entity plugin, or rejected with an error reply if the sender has no
  permission;
- **persists state** — stateful entities write their state back to IPFS after
  each dispatch; the runtime keeps track of the current state CID.

### The manifest as the source of truth

Everything the runtime knows about itself lives in the **manifest** — a
DAG-CBOR object pinned on IPFS and linked from the runtime's DID document
under `ma.runtime`. When an entity is added or updated, when an ACL changes,
when config is tweaked: the manifest is updated and the DID document is
republished with the new root CID. There is no database, no mutable server
state outside of what IPFS holds.

This design means that the runtime's entire configuration is inspectable,
forkable, and reproducible from the content-addressed IPLD tree. An auditor
can traverse `/ipfs/<did_doc_cid>/ma/runtime/…` and read everything.

### Services

A runtime advertises one or more iroh QUIC services. The two core services are:

- **`/ma/rpc/0.0.1`** — for discrete function calls (RECOMMENDED). Only
  accepts `application/x-ma-rpc` messages; anything else is rejected.
- **`/ma/inbox/0.0.1`** — for text messages, chat, emotes, and all other
  non-RPC content (REQUIRED to receive those types).

A runtime that wants to be fully reachable registers both. A runtime that
only handles structured function calls may register only `/ma/rpc/0.0.1`.
Additional purpose-specific services (like `/ma/ipfs/0.0.1` for delegated
IPNS publishing) can be registered as needed.

---

## 2. RPC — how messages work

### The term grammar

Every RPC message body is a single CBOR-encoded **term**: either an **atom**
(a text string beginning with `:`) or a **tuple** (an array whose first
element is an atom).

```
":ping"                                       — atom
":kinds"                                      — atom (list kinds)
[":kinds", "/ma/stateless/python/0.0.1"]      — tuple (get one kind)
[":config.ttl:", "3600"]                      — tuple (set config value)
```

Atoms are compact and readable. Tuples carry arguments. Protocol IDs contain
slashes and cannot be embedded in dot-path segments, so operations on the
`kinds` registry always use tuples.

### Unfragmented vs. fragment-addressed

The destination DID-URL determines how a message is dispatched:

- **`did:ma:<ipns>`** (no `#`) — routed to the runtime's built-in dot-path
  dispatcher. This is where CRUD operations on kinds, config, and namespaces
  land.
- **`did:ma:<ipns>#fortune`** — routed directly to the entity plugin whose
  IPLD key is `#fortune` at the manifest root. The dot-path dispatcher is
  bypassed entirely.
- **`did:ma:<ipns>#alice.pet`** — routed to the entity at `alice` → `#pet`
  in the manifest tree.

Fragment addresses are derived from the entity's *position* in the IPLD tree,
not from a name field inside the entity. Move an entity to a different
namespace key and its address changes.

### Replies

Every RPC message receives a reply on the sender's own `/ma/rpc/0.0.1`
service. Replies always set `reply_to` to the original message's `id`.

| Outcome | Reply body |
|---------|-----------|
| Success, no value | `:ok` |
| Success with value | `[:ok, <cbor-value>]` |
| Error | `[:error, "human-readable message"]` |
| Ping | `:pong` |

### CBOR on the wire; YAML for humans

All peer-to-peer traffic is CBOR. JSON never travels between runtimes.
Operators author manifests, ACLs, and entity nodes in YAML; the runtime
converts to DAG-CBOR before pushing to IPFS. The Kubo HTTP API uses JSON
internally, but that is an implementation detail invisible to peers.

---

## 3. IPFS — delegated publishing

Browser-based `did:ma` actors cannot reach the Kubo API directly. The
optional `/ma/ipfs/0.0.1` service lets them delegate IPNS publishing to a
runtime that *can* talk to Kubo.

The workflow is:

1. The browser actor builds and signs its updated DID document.
2. It packages the document together with its IPNS private key into a
   `IpfsRequestPayload` CBOR envelope and sends it to the runtime on
   `/ma/ipfs/0.0.1`.
3. The runtime validates the request (signature, content-type, DID proof,
   replay guard), calls Kubo's `dag/put` and IPNS publish, then zeroizes
   the private key immediately.
4. The runtime replies `:ok` or `[:error, "…"]`.

The IPNS private key grants full publishing authority over the sender's DID.
It is used exactly once — passing it to a runtime is a trust decision, not
just an API call.

The `/ma/ipfs/0.0.1` service illustrates the broader pattern: when a
well-defined operation needs its own protocol guarantees (replay protection,
strict content-type enforcement, immediate key zeroization), it SHOULD get its
own service rather than being shoehorned into the inbox.

---

## 4. CRUD — the dot-path interface

Unfragmented RPC messages reach the runtime's dot-path dispatcher. Two root
namespaces are available:

| Root | What it manages |
|------|----------------|
| `:config` | Runtime configuration key/value pairs |
| `:kinds` | The kind registry |

Plus the built-in `:ping` → `:pong` liveness check.

### Reading and writing config

```
:config              — list all keys
:config.ttl          — get the value of "ttl"
[":config.ttl:", "3600"]    — set "ttl" to "3600"
":config.ttl:"       — delete "ttl"
```

Config values are plain strings. Structured data can be JSON-encoded into a
config value if needed.

### Reading and writing kinds

Because protocol IDs contain slashes they cannot appear as dot-path segments.
The kinds interface always uses tuples:

```
:kinds                                             — list all registered protocol IDs
[":kinds", "/ma/stateless/python/0.0.1"]           — get a KindNode as CBOR
[":kinds:", "/ma/stateless/python/0.0.1", <cid>]   — upsert a kind
[":kinds:", "/ma/stateless/python/0.0.1"]           — delete a kind
```

The `<cid>` in an upsert is the DAG-CBOR CID of a `KindNode` already stored on
IPFS. The runtime fetches and validates that it has non-empty `api` and
`host_functions` before accepting it.

### Write authorisation

All write operations (set, upsert, delete) require the caller to hold the
appropriate CRUD capability (`create`, `update`, or `delete`) in the root ACL.
The transport gate checks `rpc` capability before any dot-path parsing happens.

---

## 5. Namespaces — layout and naming

The manifest top level is divided into three zones:

```
protocol, acl, kinds, config, lang   ← reserved system keys
"#fortune", "#rms"                   ← entity keys (prefixed with #)
alice, bahner, public                ← namespace keys (any NCName not reserved)
```

### What a namespace is

A namespace is an inline sub-tree in the manifest. It is not a separate IPLD
object — it is stored inline in the manifest DAG-CBOR. A namespace can hold:

- `acl` — **required** CID (IPLD link) to the namespace AclMap that gates all
  access to entities and resources inside this namespace;
- `acls` — *optional* flat map of named CIDs: `acls.<name>` → IPLD link to an
  `AclMap`; entity verb-ACL names resolve against this map;
- `#<name>` — entity keys (IPLD links to `EntityNode`);
- arbitrary IPLD data — group membership lists, blobs, nested objects.

```yaml
alice:
  acl: { "/": "bafy...alice_acl" }           # required — namespace gate
  acls:
    friends: { "/": "bafy...friends_acl" }   # named verb-ACL for entities
    public:  { "/": "bafy...public_acl" }
  "#pet": { "/": "bafy...entity_alice_pet" } # → did:ma:<ipns>#alice.pet
  venner: [ "did:ma:carlotta", "did:ma:fjodor" ] # group list used by ACL
```

### Fragment addressing in namespaces

An entity at `alice.#pet` is addressed as `did:ma:<ipns>#alice.pet`. The
runtime splits the fragment on `.`, walks namespace keys for all segments
except the last, then looks up the last segment prefixed with `#`.

Nesting is allowed: `bahner.alice.#bot` → `did:ma:<ipns>#bahner.alice.bot`.

### Creating a namespace — the two-capability rule

Namespaces cannot be squatted. To create namespace `alice`, the caller must
hold **both** `create` and `alice` in the root ACL at the same time. The
operator controls which names can be claimed and by whom. Neither capability
alone is sufficient.

### Reserved names

The names `acl`, `config`, `kinds`, `lang`, and `protocol` are reserved as
system keys and cannot be used as namespace names. The transport-layer
capability strings (`rpc`, `ipfs`, `inbox`, `ping`, `read`, `create`,
`update`, `delete`) are also reserved. See the RFC §16 for the full registry.

---

## 6. ACLs — capabilities replace ownership

### The model in one sentence

A principal is allowed to perform an operation if it holds the required
capability string in the relevant `AclMap`. There is no owner, no role
hierarchy, no file permissions — just named capabilities.

### AclMap format

```yaml
"*":              [rpc]            # everyone: RPC access
"did:ma:alice":   [rpc, inbox]     # alice: RPC + inbox
"did:ma:eve":                      # bare key → explicit deny (all access)
"group:alice.venner": [fortune, secret]
```

A bare key with no value is an explicit deny. A YAML sequence is an allow set.
**Deny always wins** — a direct deny overrides any wildcard or group allow.

### Where ACLs live

ACL documents live at five locations. Four store CIDs; one stores a name string.

| Location | Type | What it controls |
|----------|------|-----------------|
| Root `.acl` | CID | Transport gate + resource allocation for the whole runtime |
| Root `.acls.<name>` | CID | Named verb-ACL library for root-level `#entities` |
| `<ns>.acl` | CID | Namespace gate — who may reach any entity inside `<ns>` |
| `<ns>.acls.<name>` | CID | Named verb-ACL library for entities within `<ns>` |
| `EntityNode.acl` | name string | Verb gate — resolved via `acls.<name>` in scope |

Updating an ACL is a one-CID swap. No entity nodes or manifest structure
changes. A missing or unresolvable CID is treated as **deny all**.

### Namespace ACL capabilities

The namespace AclMap (`<ns>.acl`) controls who can reach each entity and
sub-key within the namespace. The capabilities are namespace-scoped:

| Capability | Grants |
|-----------|--------|
| `read` | List or read namespace contents |
| `#<name>` | Send messages to entity `#<name>` |
| `<key>` (bare name) | Access sub-key `<key>` within this namespace |
| `create`, `update`, `delete` | CRUD on namespace contents |
| `*` | All of the above |

Example — the `alice` namespace ACL:

```yaml
"*":                  [read, "#fortune"]   # everyone: read + reach #fortune
"did:ma:alice":       ["*"]               # alice: full control
"did:ma:carlotta":    [project2, create, update]
"group:alice.enemies":                    # explicit deny
```

Everyone may read and invoke `#fortune`; alice has full control; carlotta may
create and maintain a `project2` sub-key but nothing else.

### Entity verb-ACL — the `acls` library

`EntityNode.acl` holds a plain name string, not a CID. The runtime resolves it
against the `acls` map in the entity's containing scope:

```
acl: "fortune"     →  <ns>.acls.fortune  (or root .acls.fortune)
acl: "bob.acls.venner"  →  full manifest path traversal
```

This indirection is the key to maintainability: 200 entities sharing the name
`"fortune"` all use the same `acls.fortune` AclMap. Denying Bob requires one
change — update `acls.fortune`. No entity nodes are touched.

### The transport gate

Every incoming message is checked against the root ACL before anything else:

- `/ma/rpc/0.0.1` messages require the `rpc` capability.
- `/ma/inbox/0.0.1` messages require the `inbox` capability.
- `/ma/ipfs/0.0.1` messages require the `ipfs` capability.

The evaluation order is: direct DID entry → null groups → wildcard → group
scan. A direct entry (allow or deny) terminates evaluation immediately.

### Resource allocation

The root ACL doubles as a resource allocation registry via two naming
conventions:

- **`#<name>`** — grants authority over root entity `<name>`. A principal
  holding `#fortune` may update or delete `#fortune`. Generic `update` and
  `delete` do not grant this.
- **`<ns>` (bare NCName)** — grants ownership of namespace `<ns>`. Required
  together with `create` to create the namespace.

### Groups

Groups are IPLD lists stored in the namespace tree:
`alice.venner: [ "did:ma:carlotta", "did:ma:fjodor" ]`. An ACL entry
`group:alice.venner: [fortune, secret]` means: members of that list receive
`fortune` and `secret` capabilities. Group membership is resolved lazily and
cached by manifest root CID.

---

## 7. Entities — the cornerstone

### What an entity is

An entity is an **Extism Wasm plugin** stored on IPFS and registered in the
manifest under a `#<name>` key. When a fragment-addressed message arrives
(`did:ma:<ipns>#fortune`), the runtime calls the plugin's dispatch function
with a CBOR-encoded message envelope and lets the plugin respond via host
functions.

The entity's **address** is determined by its IPLD tree position — the runtime
derives it from the key path, not from a name field inside the entity node.

### EntityNode

Each entity is described by an `EntityNode`:

```yaml
kind: /ma/stateless/python/0.0.1  # which ABI this plugin implements
behavior:
  "/": bafy...wasm_bytes           # link to the Wasm module
acl: fortune                       # name string → resolves to <ns>.acls.fortune
wasi: false                        # WASI capability (snapshotted at creation)
```

For stateful entities, a `state` field links to the last-persisted state blob.

**Two distinct ACL levels apply to every entity:**

1. **Namespace gate** (`<ns>.acl`) — checked first. The caller must hold the
   `#<name>` capability (or `*`) to reach this entity at all.
2. **Verb gate** (`EntityNode.acl`) — checked inside dispatch. The caller must
   hold the required verb capability to perform the specific operation.

`EntityNode.acl` is a **name string**, never a CID. The runtime looks up
`<ns>.acls.<name>` to find the actual AclMap. This means all entities sharing
the same name share the same policy — one update covers all of them.

### Kinds

A **kind** is a descriptor that defines a plugin's contract:

```yaml
protocol: /ma/stateless/python/0.0.1
api:            [handle_cast]
host_functions: [ma_send, ma_reply]
wasi: false
```

The `api` list declares which Wasm exports the plugin must provide. The
`host_functions` list declares which host functions the runtime registers for
it — plugins receive *only* the functions they need (principle of least
privilege).

Two built-in profiles exist:

- **Stateless** — exports `handle_cast`; receives `ma_send` and `ma_reply`.
  The plugin is effectively stateless: no `init`, no persistence.
- **Stateful** — exports `init` and `handle_call`; additionally receives
  `ma_set_state`. State is persisted to IPFS after each dispatch.

### Dispatch

Every fragment-addressed message (on both `/ma/rpc/0.0.1` and
`/ma/inbox/0.0.1`) is delivered to the plugin as a CBOR-encoded `CastInput`:

```
msg.id, msg.from, msg.to, msg.content_type, msg.content, msg.reply_to, ...
ctx.self   ← DID-URL of this entity, e.g. "did:ma:<ipns>#fortune"
```

The plugin responds exclusively via host functions — the return value of the
Wasm export is ignored.

### Host functions

| Function | Available to | Purpose |
|----------|-------------|---------|
| `ma_send(bytes)` | all kinds | Enqueue an outbound message |
| `ma_reply(bytes)` | all kinds | Convenience: reply to the current message |
| `ma_set_state(bytes)` | stateful only | Queue state bytes for IPFS persistence |

`ma_send` and `ma_reply` take CBOR-encoded envelopes. `ma_set_state` takes
opaque bytes — the runtime stores them as-is and passes them back to `init`
on next load.

---

## 8. Development — writing and deploying plugins

### Choosing a language

Any language with an Extism SDK can produce a 間 entity plugin: Python, Rust,
Go, C, Zig, and more. The SDK provides the host function bindings and the
WASI interface. Python via `extism-py` is the reference implementation in
this project.

### Minimal stateless plugin (Python)

```python
import extism
import cbor2

@extism.plugin_fn
def handle_cast():
    data = extism.input_bytes()
    cast = cbor2.loads(data)
    msg = cast["msg"]
    # echo the content back to the sender
    reply_body = cbor2.dumps({"echo": msg["content"]})
    extism.output_bytes(reply_body)
```

The function takes no arguments and returns nothing. Input and output go
through the Extism host I/O functions. Call `ma_reply` via the Extism host
bindings to send a reply.

### Build steps

1. **Write the plugin.** Implement `handle_cast` (stateless) or `init` +
   `handle_call` (stateful).
2. **Compile to Wasm.** Use the Extism toolchain for your language
   (e.g. `extism-py build fortune.py -o fortune.wasm`).
3. **Add the Wasm to IPFS.**
   ```sh
   ipfs add fortune.wasm
   # → QmXxx...
   ```
4. **Write a KindNode** (YAML) for the protocol, if one does not already
   exist. Convert to DAG-CBOR:
   ```sh
   echo '{"protocol":"/ma/stateless/python/0.0.1","api":["handle_cast"],"host_functions":["ma_send","ma_reply"],"wasi":false}' \
     | ipfs dag put --store-codec dag-cbor --input-codec dag-json
   # → bafy...kind_cid
   ```
5. **Register the kind** by sending to the runtime:
   ```
   [":kinds:", "/ma/stateless/python/0.0.1", "bafy...kind_cid"]
   ```
6. **Write an EntityNode** (YAML), publish as DAG-CBOR:
   ```yaml
   kind: /ma/stateless/python/0.0.1
   behavior:
     "/": QmXxx...  # Wasm CID from step 3
   acl:
     "/": bafy...acl_cid
   wasi: false
   ```
   ```sh
   cat entity.json | ipfs dag put --store-codec dag-cbor --input-codec dag-json
   # → bafy...entity_cid
   ```
7. **Register the entity** in the manifest via the runtime's CRUD interface,
   or include it in the bootstrap YAML before first startup.

### Bootstrap workflow

For new runtimes, the reference implementation supports a YAML bootstrap file:

```yaml
runtime:
  "#fortune":
    kind: /ma/stateless/python/0.0.1
    behavior_cid: QmXxx...   # Wasm CID
    acl: ""                  # empty → uses runtime default ACL
```

```sh
ma --bootstrap bootstrap.yaml
```

This publishes all nodes, assembles the manifest DAG, pins it, and registers
the root CID under the operator's IPNS key.

### Testing a plugin

Send a fragment-addressed RPC message directly to the entity using the `ego`
browser terminal or any `did:ma`-capable client:

```
@runtime#fortune hello world
```

The runtime dispatches to `handle_cast` and the plugin's reply appears in
your inbox.

### Iterating

Update the Wasm, re-add to IPFS to get a new behavior CID, build a new
EntityNode pointing to it, and upsert the entity in the manifest. The runtime
does not hot-reload — a restart picks up the new entity node from IPFS.

---

*Draft — 21 May 2026*
