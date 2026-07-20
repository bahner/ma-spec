# ma-runtime-guide-v1: 間 Runtime Operator and Developer Guide

**Status:** Candidate Recommendation
**Version:** 1.0.0
**Date:** 20 July 2026

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
4. [CRUD — the `/ma/crud/0.0.1` interface](#4-crud--the-macrud001-interface)
5. [ACLs — capabilities replace ownership](#5-acls--capabilities-replace-ownership)
6. [Entities — the cornerstone](#6-entities--the-cornerstone)
7. [Development — writing and deploying plugins](#7-development--writing-and-deploying-plugins)

---

## 1. What is a 間 runtime

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
  accepts `application/vnd.ma.rpc.request` messages; anything else is rejected.
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
":ping"                                       — atom (liveness check)
":enter"                                      — atom (entity verb, fragment-addressed)
[":enter", "#room"]                          — tuple (entity verb with an argument)
```

Atoms are compact and readable. Tuples carry arguments. `/ma/rpc/0.0.1` is
for discrete verb calls only — it is NOT how you read or write structured
data (kinds, config, entities, ACLs). That's a separate service, `/ma/crud/0.0.1`
(§4).

### Unfragmented vs. fragment-addressed

The destination DID-URL determines how a message is dispatched:

- **`did:ma:<ipns>`** (no `#`) — only the `:ping` liveness atom is
  supported.
- **`did:ma:<ipns>#fortune`** — routed directly to the entity plugin whose
  IPLD key is `#fortune` at the manifest root.

Fragment addresses are derived from the entity's *position* in the IPLD tree,
not from a name field inside the entity.

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
2. It packages the document together with its IPNS private key into an
   `application/vnd.ma.identity.publish.request` CBOR envelope and sends it to
   the runtime on `/ma/ipfs/0.0.1`.
3. The runtime validates the request (signature, message-type, DID proof,
   replay guard, `identity-publish` capability), calls Kubo's `dag/put` and
   IPNS publish, then zeroizes the private key immediately.
4. The runtime replies `:ok` or `[:error, "…"]`.

The IPNS private key grants full publishing authority over the sender's DID.
It is used exactly once — passing it to a runtime is a trust decision, not
just an API call.

The `/ma/ipfs/0.0.1` service illustrates the broader pattern: when a
well-defined operation needs its own protocol guarantees (replay protection,
strict message-type enforcement, immediate key zeroization), it SHOULD get its
own service rather than being shoehorned into the inbox.

---

## 4. CRUD — the `/ma/crud/0.0.1` interface

Structured data (config, entities, kinds, ACLs) is read and written
exclusively through a separate service, `/ma/crud/0.0.1` — never through
`/ma/rpc/0.0.1`. Paths are `/`-separated, e.g. `/config`, `/config/ttl`,
`/kinds/ma/stateless/python/0.0.1`, `/entities/fortune`. See
[ma-crud-service-v1.md](ma-crud-service-v1.md) for the full wire protocol.

There is no `:`/dot-path CRUD grammar layered on top of `/ma/rpc/0.0.1`
(`:config.ttl`, `:kinds.<protocol>`, or similar) — no such syntax is valid
on that service. All CRUD goes through `/ma/crud/0.0.1` with `/`-paths.

### Reading and writing config

```
["/config"]                        — list all keys
["/config/ttl"]                    — get the value of "ttl"
["/config/ttl", "3600"]            — set "ttl" to "3600"
["/config/ttl", ""]                — delete "ttl"
```

Config values are plain strings. Structured data can be JSON-encoded into a
config value if needed.

### Reading and writing kinds

Protocol IDs contain slashes; they are simply appended as path segments:

```
["/kinds"]                                              — list all registered protocol IDs
["/kinds/ma/stateless/python/0.0.1"]                    — get a KindNode as CBOR
["/kinds/ma/stateless/python/0.0.1", "/ipfs/<cid>"]     — upsert a kind
["/kinds/ma/stateless/python/0.0.1", ""]                — delete a kind
```

The `/ipfs/<cid>` in an upsert references the DAG-CBOR CID of a `KindNode`
already stored on IPFS. The runtime fetches and validates that it has
non-empty `api` and `host_functions` before accepting it.

For GET and DELETE, a missing CRUD resource is reported as `[":error",
"not-found"]` or a namespace-specific code ending in `"-not-found"`, such as
`"kind-not-found"` or `"entity-not-found"`. Client-local commands such as
`!edit` may treat this error family on a creatable path as an instruction to
open a blank editor for creating the resource.

### Write authorisation

Every `/ma/crud/0.0.1` request first requires the caller to hold the blanket
`crud` capability in the root ACL (or be an owner). Beyond that single gate,
the reference runtime enforces only two additional, entity-specific checks:
deleting an entity requires `delete` + `entities`, and registering/replacing
an entity requires the entity's own `kind` protocol ID as a capability.
Kind management, config management, and ACL-document management currently
require nothing beyond the blanket `crud` capability — see
[ma-runtime-v1.md §13.3](ma-runtime-v1.md#133-built-in-capability-strings).

---

## 5. ACLs — capabilities replace ownership

### The model in one sentence

A principal is allowed to perform an operation if it holds the required
capability string in the relevant `AclMap`. There is no owner, no role
hierarchy, no file permissions — just named capabilities.

### AclMap format

```yaml
"*":              [rpc]            # everyone: RPC access
"did:ma:alice":   [rpc, crud]      # alice: RPC + CRUD
"did:ma:eve":                      # bare key → explicit deny (all access)
```

A bare key with no value is an explicit deny. A YAML sequence is an allow set.
**Deny always wins** — a direct deny overrides any wildcard or group allow.

### Where ACLs live

ACL documents live at the manifest root.

| Location | Type | What it controls |
|----------|------|-----------------|
| Root `.acl` | CID | Transport gate for the whole runtime |

Updating an ACL is a one-CID swap. No entity nodes or manifest structure
changes. A missing or unresolvable CID is treated as **deny all**.

### The transport gate

Every incoming `/ma/rpc/0.0.1`, `/ma/ipfs/0.0.1`, or `/ma/crud/0.0.1` message
is checked against the root ACL before anything else:

- `/ma/rpc/0.0.1` messages require the `rpc` capability.
- `/ma/ipfs/0.0.1` messages require the `ipfs` capability.
- `/ma/crud/0.0.1` messages require the `crud` capability.
- `/ma/inbox/0.0.1` messages are **not gated at all** by the reference
  runtime — there is no `inbox` capability check. An entity that wants to
  filter inbox senders must implement that itself (see
  [ma-runtime-v1.md §6.3](ma-runtime-v1.md#63-inbox-service--mainbox001)).

Owners bypass all of the above unconditionally.

The evaluation order is: direct DID entry → null groups → wildcard → group
scan. A direct entry (allow or deny) terminates evaluation immediately.

---

## 6. Entities — the cornerstone

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
wasi: false                        # WASI capability (snapshotted at creation)
```

For stateful entities, a `state` field links to the last-persisted state blob.

### Kinds

A **kind** is a descriptor that defines a plugin's contract:

```yaml
protocol: /ma/stateless/python/0.0.1
api:            [on_message]
host_functions: [ma_send, ma_reply]
wasi: false
```

The `api` list declares which Wasm exports the plugin must provide. The
`host_functions` list declares which host functions the runtime registers for
it — plugins receive *only* the functions they need (principle of least
privilege).

Every kind exports the same single dispatch function, `on_message` — there
is no separate export per statefulness; `handle_cast`/`handle_call` were an
earlier, synchronous way of thinking and are no longer used. Two built-in
profiles exist, differing only in whether `init` and state persistence are
used (statelessness exists purely to avoid needlessly persisting/publishing
empty or unchanged state to IPFS — since content is encrypted, even
identical plaintext state yields a unique CID each time, which is wasteful
for plugins that never need persistence):

- **Stateless** — exports only `on_message`; receives `ma_send` and
  `ma_reply`. No `init`, no persistence.
- **Stateful** — additionally exports `init`; additionally receives
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

## 7. Development — writing and deploying plugins

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
def on_message():
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

1. **Write the plugin.** Implement `on_message` (all kinds) and, for
   stateful kinds, `init` as well.
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
   echo '{"protocol":"/ma/stateless/python/0.0.1","api":["on_message"],"host_functions":["ma_send","ma_reply"],"wasi":false}' \
     | ipfs dag put --store-codec dag-cbor --input-codec dag-json
   # → bafy...kind_cid
   ```

5. **Register the kind** via the `/ma/crud/0.0.1` service:

   ```
   ["/kinds/ma/stateless/python/0.0.1", "/ipfs/bafy...kind_cid"]
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
```

Run:

```sh
ma --bootstrap bootstrap.yaml
```

This publishes all nodes, assembles the manifest DAG, pins it, and registers
the root CID under the operator's IPNS key.

### Testing a plugin

Send a fragment-addressed RPC message directly to the entity using the `ego`
browser terminal or any `did:ma`-capable client:

```text
@runtime#fortune hello world
```

The runtime dispatches to `on_message` and the plugin's reply appears in
your inbox.

### Iterating

Update the Wasm, re-add to IPFS to get a new behavior CID, build a new
EntityNode pointing to it, and upsert the entity in the manifest. The runtime
does not hot-reload — a restart picks up the new entity node from IPFS.

---

Candidate Recommendation — 20 July 2026
