# MA Host Runtime API
**Status:** Experimental (Non-normative)  
**Version:** 0.4.0  
**Author:** <your-name-or-github-handle>

## 1. Terminology

The term “MA” is derived from 間 (ma), meaning interval or relational space.

This reflects a design focus on interactions between identities rather than internal structure.

In this document:

- `id` means a primitive identifier under an MA identity
- `@root` means the distinguished root object of an MA identity
- `@self` means the current execution target, when applicable
- `system` means the non-messageable system tree defined by the MA Identity System Tree specification
- `binding` means a language-facing API such as Elixir, Scheme, Rust, or another host language
- `host` means the implementation layer that performs resolution, messaging, transport, signing, serialization, and runtime isolation

---

## 2. Purpose

This document defines a minimal runtime/FFI API for programmatic treatment of MA ids.

It is intended to support:

- Rust implementations
- Elixir bindings using an Iroh FFI
- Scheme or other embedded languages
- other future language bindings

This specification does **not** define one required programming language syntax.

It defines:

- the minimum runtime object model
- the minimum host capability surface
- required behavior for root-directed and id-directed operations
- the contract between a host implementation and higher-level bindings

This document is intended to be used together with:

- **MA Identity System Tree (間)**
- **MA Root Meta Protocol**

---

## 3. Scope

This specification defines how an MA host exposes:

- the current identity root
- the current execution target
- ids under an identity
- request/reply messaging
- structured data access
- publication and CID handling

This specification does **not** require:

- a local actor runtime
- a scheduler
- BEAM semantics
- one mailbox model
- one persistence model
- one sandbox technology

A host MAY internally use tasks, threads, callbacks, tables, processes, actors, or any other mechanism.

---

## 4. Core runtime model

### 4.1 Identity root

Every MA identity has a root address:

`did:ma:<identity>`

Messages sent to this address MUST be handled by `@root`.

### 4.2 Id

An `id` is a primitive identifier under an identity.

An id MAY represent any addressable internal entity.

Examples:

- `did:ma:<identity>#duck`
- `did:ma:<identity>#room42`
- `did:ma:<identity>#avatar`

### 4.3 Root rule

For every MA identity, there MUST exist a distinguished root object, referred to as `@root`.

`@root` is message-addressable via:

`did:ma:<identity>`

This specification does NOT require a standardized `#root` fragment.

### 4.4 System tree

Every MA identity MUST expose a non-messageable `system` tree.

Runtime operations that create or destroy ids MUST preserve the invariants of the system tree.

### 4.5 Binding independence

Bindings MAY choose idiomatic names.

For example, an Elixir binding MAY expose:

- `root/0`
- `self/0`
- `send_msg/2`
- `ask/2`
- `recv/0`
- `create_id/2`

A Scheme binding MAY expose:

- `(root)`
- `(self)`
- `(send ref value)`
- `(ask ref value)`

A Rust host MAY expose:

- functions
- traits
- async methods

Bindings MUST preserve the semantics defined here.

---

## 5. Host value model

A conforming host MUST support a language-neutral value model.

At minimum, the runtime boundary MUST support:

- `null`
- `bool`
- `int`
- `float`
- `string`
- `bytes`
- `list`
- `map<string, value>`
- `ref`
- `cid`

### 5.1 Maps

Map keys MUST be strings.

### 5.2 Refs

A `ref` MUST be representable as a first-class value.

At minimum, a ref MUST support round-tripping to textual MA form such as:

- `did:ma:<identity>`
- `did:ma:<identity>#<id>`

### 5.3 CIDs

A `cid` MUST be representable as a first-class value.

Bindings and hosts MUST be able to pass CIDs without lossy transformation.

### 5.4 IPLD alignment

The value model SHOULD map cleanly onto IPLD/DAG-CBOR-like structures.

---

## 6. Required host/runtime capabilities

A conforming host MUST expose capabilities equivalent to the following functions.

The names shown below are descriptive only.

### 6.1 `root() -> ref`

Returns the current identity root ref.

The returned value MUST identify:

`did:ma:<identity>`

### 6.2 `self() -> ref`

Returns the current execution ref.

If execution is happening on behalf of a specific id, the returned value SHOULD be that id's full ref.

If no more specific execution target exists, `self()` MAY equal `root()`.

### 6.3 `resolve(target) -> value`

Resolves a DID or ref into structured data.

`target` MAY be:

- a root ref
- an id ref
- a textual MA address

The returned data MAY include:

- DID-related structure
- identity metadata
- transport metadata
- implementation-defined derived state

### 6.4 `get(target) -> value`

Reads structured data from a target.

A target MAY be:

- a ref
- a system path
- a structured path
- an implementation-defined readable handle

A host SHOULD support reading at least:

- identity-related structured data
- the system tree
- CID-backed published values, when resolvable

### 6.5 `set(target, value) -> result`

Updates structured data.

This specification does not require one persistence model.

If the host distinguishes local mutation from publication, `set` describes only the update step.

A host MUST ensure that updates do not violate required `system` invariants.

### 6.6 `send(ref, content, opts?) -> result`

Sends a message to a target ref.

The binding provides message content only.

The host MUST own:

- envelope construction
- message ids
- correlation fields
- serialization
- signing
- transport submission

The host MUST NOT require the binding to construct full wire-level envelopes.

When the destination is:

`did:ma:<identity>`

the message MUST be handled by `@root`.

When the destination is:

`did:ma:<identity>#<id>`

the message MUST be handled by the addressed id.

### 6.7 `ask(ref, content, opts?) -> value | result`

Sends a message and waits for a correlated reply.

The host MUST:

1. send the request
2. correlate the reply
3. return the reply content or documented full result

If the message layer uses fields such as `id` and `replyTo`, the host MUST use them for correlation.

If timeouts are supported, the host SHOULD allow them to be passed through `opts`.

### 6.8 `recv(opts?) -> message`

Receives the next available inbound message.

A returned message SHOULD include at least:

- source ref
- destination ref
- message id
- content
- correlation metadata when available

The host MAY implement blocking, polling, mailbox draining, or callback-driven behavior internally.

### 6.9 `publish(value, opts?) -> result`

Publishes structured content using the host's publication layer.

This MAY return:

- a CID
- a ref
- a result map
- another documented publication result

### 6.10 `log(level, value) -> null`

Emits diagnostic output.

This function has no protocol semantics.

---

## 7. Optional host/runtime capabilities

The following capabilities are optional.

### 7.1 `now() -> value`

Returns current host time.

### 7.2 `sleep(ms) -> null`

Suspends execution for approximately the requested time.

### 7.3 `subscribe(target, opts?) -> result`

Registers interest in a topic, inbox, or other implementation-defined target.

### 7.4 `unsubscribe(target, opts?) -> result`

Cancels a prior subscription.

### 7.5 `spawn(opts?) -> result`

This specification does not require a local actor runtime.

If a host exposes `spawn`, it MUST document its local meaning.

It MUST NOT be assumed to be portable MA semantics.

---

## 8. Root meta helpers

The following helpers are RECOMMENDED for bindings, but they are not required host primitives.

They SHOULD be implemented by sending messages to `@root`, not by bypassing root semantics.

Recommended helpers:

- `create(id, attrs)`
- `destroy(id_or_ref)`
- `list()`
- `inspect(id_or_ref)`
- `capabilities()`

These map to the MA Root Meta Protocol.

### 8.1 Create helper semantics

A binding-level `create` helper SHOULD send a root-directed message and MUST result, on success, in a valid `system.ids.<id>` entry.

### 8.2 Destroy helper semantics

A binding-level `destroy` helper SHOULD send a root-directed message and MUST remove the corresponding `system.ids.<id>` entry on success.

### 8.3 Inspect helper semantics

A binding-level `inspect` helper SHOULD return information derived from `system.ids.<id>` and other implementation-defined state.

---

## 9. Opaque CID-backed content

Content referenced by `public_cid` or `state_cid` MAY contain:

- code
- data
- structured IPLD
- encrypted blobs
- implementation-defined payloads

The host runtime MUST treat such content as opaque at the MA metalayer unless a higher layer explicitly interprets it.

The MA host/runtime layer MUST NOT require:

- parsing of code
- semantic validation of code
- language-level validation of code
- approval of content meaning

### 9.1 Sandbox responsibility

If CID-backed content is executed, sandboxing and runtime isolation are the responsibility of the host implementation.

### 9.2 Policy responsibility

ACLs and effect restrictions MAY constrain what executed content can do, but the MA host/runtime layer does not define the meaning or correctness of those policies.

---

## 10. Root/system coupling

The host/runtime layer MUST preserve the following coupling to the system tree:

- successful root-level `create` MUST create a corresponding `system.ids.<id>` entry
- successful root-level `destroy` MUST remove the corresponding `system.ids.<id>` entry
- root-level `list` MUST reflect the keys of `system.ids`, or a documented policy-filtered subset
- root-level `inspect` MUST derive its result at least in part from `system.ids.<id>`

The `system` tree itself MUST remain non-messageable.

---

## 11. Error handling

A conforming host MUST document how errors are represented across the runtime boundary.

A host MUST support at least one of:

- exceptions
- tagged error values
- both

The following error classes SHOULD be distinguishable:

- invalid ref
- invalid cid
- resolution failure
- transport failure
- timeout
- permission denied
- unsupported operation
- invalid value encoding
- publication failure
- system invariant violation

---

## 12. Invariants

A conforming host MUST preserve the following invariants:

1. messages sent to `did:ma:<identity>` are handled by `@root`
2. `system` is not message-addressable
3. every currently exposed managed id appears in `system.ids`
4. every `system.ids.<id>` entry contains:
   - `acl`
   - `owner`
   - `allowed_effects`
5. `public_cid` and `state_cid`, when present, are preserved losslessly
6. bindings are not required to construct wire envelopes manually
7. opaque content remains opaque unless interpreted by a higher layer

---

## 13. Elixir-oriented binding guidance

This section is informative only.

An Elixir binding using an Iroh FFI can map the required runtime capabilities to ordinary Elixir functions.

Example naming:

- `root/0`
- `self/0`
- `resolve/1`
- `get/1`
- `set/2`
- `send_msg/2`
- `ask/2`
- `recv/0`
- `publish/1`

And root helpers:

- `create_id/2`
- `destroy_id/1`
- `list_ids/0`
- `inspect_id/1`
- `root_capabilities/0`

Such helpers MUST still route through `did:ma:<identity>` and preserve root semantics.

### 13.1 Example Elixir pseudocode

```elixir
def create_id(id, attrs) do
  ask(root(), %{
    "kind" => "create",
    "id" => id,
    "attrs" => attrs
  })
end

def inspect_id(id) do
  ask(root(), %{
    "kind" => "inspect",
    "id" => id
  })
end

def send_msg(ref, content) do
  send(ref, content)
end
```

This is only a binding example. The semantics are normative; the names are not.

---

## 14. Minimal conformance

An implementation conforms to this specification if it:

1. exposes runtime capabilities equivalent to the functions defined in Section 6
2. supports the value model in Section 5
3. routes identity-root messages to `@root`
4. preserves the root/system coupling defined in Section 10
5. treats CIDs as first-class values
6. treats CID-backed content as opaque at the MA metalayer
7. documents its error model

---

## 15. Rationale

This specification is intentionally small.

It defines the host/runtime contract needed so that higher-level bindings can manipulate MA ids programmatically without re-implementing transport, serialization, signing, or system invariants in each language.

This is especially useful for an Elixir binding over an Iroh FFI:

- the Iroh layer handles transport and endpoint behavior
- the host/runtime layer handles MA semantics and invariants
- the binding exposes an idiomatic API
- `@root` remains the normative administrative/meta target
- `system.ids` remains the normative non-messageable registry

This makes it possible to sit on one machine, call `create` against a remote identity root, and rely on the runtime contract rather than rewriting core semantics in every world or language.
