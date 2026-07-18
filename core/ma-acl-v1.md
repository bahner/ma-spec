# ACL and Capabilities Model

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines the capabilities-based access control model used
across 間 services. An `AclMap` maps principals to named capability strings
using deny-wins semantics.

**Applicable to:** Any 間 service that needs access control. The transport
gate and CRUD resource management on a runtime are the primary users, but
the model is general and MAY be applied at any layer (entity-level verb
gates, client-side inbox filters, etc.).

---

## 1. Model overview

All access control uses a **capabilities model**: every operation a caller
can perform is guarded by a named capability string. Access control is
expressed as an `AclMap` — a flat YAML object mapping principals (or the
wildcard `*`) to their allowed capabilities.

**Deny always wins.** An explicit `null` value for any principal overrides
every allow, including the wildcard. An empty or missing ACL denies
everyone.

---

## 2. AclMap format

An `AclMap` is a flat YAML object. Each key is either a **principal** (a
full DID or `*`). Every value is one of:

| YAML value | Meaning |
|------------|---------|
| `null` or bare key | **Explicit deny** — overrides all wildcards |
| YAML sequence | **Allow** — caller receives exactly the listed capabilities |
| (absent) | Equivalent to explicit deny |

There is no "grant-by-capability" notation. All grants are per-principal.

---

## 3. Group principals (`+`)

A key beginning with `+` is a **group principal** — a reference to a set of
member DIDs rather than a single DID. The `+` sigil is reserved at this
core layer, but the concrete syntax used to identify a group and the
mechanism used to resolve its membership are **implementation-defined**.
This document does not mandate a specific group-reference grammar.

The mechanism implemented by the reference runtime is a flat `+<name>`
principal (no nested path, no `#fragment`), resolved by looking up `<name>`
in a runtime-maintained named group registry — a manifest-stored map from
group name to an IPLD link to a plain list of member DIDs. See
[ma-runtime-v1.md §13.1](../runtime/ma-runtime-v1.md#131-aclmap-format) for
the registry's storage location and format. Other implementations MAY
define different group-reference syntaxes and resolution mechanisms.

Once resolved, a group entry behaves exactly like a DID entry: if the
caller is a member, that entry's capabilities apply. In the reference
runtime, resolution is a synchronous, in-memory cache lookup — no message
dispatch, no round-trip — but it is still evaluated as a separate pass from
the synchronous direct/wildcard checks in §7, since arbitrary
implementations MAY resolve groups by other means (including asynchronous
ones). See [ma-runtime-v1.md §13.4](../runtime/ma-runtime-v1.md#134-evaluation-algorithm-normative)
for the reference runtime's full evaluation order, including group
expansion.

---

## 4. Local-actor principal (`"#"`)

The special key `"#"` matches any actor whose DID-URL shares the **same
IPNS root** as the runtime evaluating the ACL — i.e. any entity on the same
runtime, regardless of fragment.

```yaml
"#":  [on_message]   # all local actors may call on_message
"*":  [read]         # everyone else: read-only
```

**Matching rule:** A caller matches `"#"` if and only if
`strip_fragment(caller)` equals the runtime's own DID.

The `"#"` key is evaluated **after** a direct DID match (step 1 in §7) and
**before** the `"*"` wildcard (step 2 in §7). It may be used as an allow
entry or an explicit deny.

**Rationale:** Actors are the unit of locality in the Actor Model. Entities
running on the same runtime share an address space and trust boundary;
giving them a dedicated principal avoids enumerating individual DIDs in ACL
documents and enables the default open-to-local pattern for system actors
such as `#root` and `#scheduler`.

---

## 5. AclMap format (continued)

Implementations MUST serialise and accept ACL maps in this exact form:

```yaml
# Transport gate — who may use which protocols
"*":              [rpc]            # everyone: RPC access
"did:ma:alice":   [rpc, inbox]     # alice: RPC + inbox
"did:ma:eve":                      # bare key → explicit deny

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

## 6. Built-in capability strings

The following capability strings have normative meanings at the transport and
resource-allocation layer. They MUST NOT be used as entity
names (see [ma-runtime-v1.md §16](../runtime/ma-runtime-v1.md)).

| Capability | Layer | Meaning |
|------------|-------|---------|
| `"inbox"` | Transport | May deliver messages via `/ma/inbox/0.0.1` |
| `"rpc"` | Transport | May call `/ma/rpc/0.0.1` |
| `"ipfs"` | Transport | May send `application/vnd.ma.ipfs.request` (generic content storage) via `/ma/ipfs/0.0.1` |
| `"identity-publish"` | Transport | May send `application/vnd.ma.identity.publish.request` (delegated DID-document publishing) via `/ma/ipfs/0.0.1`. Independent of `"ipfs"` — granting one does not grant the other; see [ma-ipfs-service-v1.md §4.2](ma-ipfs-service-v1.md). |
| `"crud"` | Transport | May call `/ma/crud/0.0.1` |
| `"ping"` | Transport | May send `:ping` atom (subset of `rpc`) |
| `"read"` | CRUD | Read entities and config |
| `"create"` | CRUD | Generic create permission |
| `"update"` | CRUD | Update existing entities |
| `"delete"` | CRUD | Delete entities |
| `"entities"` | CRUD | Required (with `create`/`delete`) for entity management |
| `"kinds"` | CRUD | Required (with `create`/`delete`) for kind management |
| `"*"` (in Allow set) | Any | Grants all capabilities for this principal |

Entity-level ACLs may use arbitrary strings as capability names
(`"on_message"`, `"reply"`, `"secret"`, etc.).

---

## 7. Evaluation algorithm (normative)

**Input:** ACL map `A`, caller DID `caller`, capability set `required`
(one or more strings; **OR semantics** — the check passes if the caller
holds **at least one** of the listed capabilities).

**Per-check algorithm:**

```
normalised = strip_fragment(caller)
runtime_did = strip_fragment(our_did)

# Step 1 — Direct DID lookup (terminates evaluation)
if A[normalised] exists:
    if A[normalised] is Deny:  return DENY
    if A[normalised] is Allow(caps):
        if caps.contains("*") or caps ∩ required ≠ ∅:  return ALLOW
        return DENY

# Step 2 — Local-actor principal
if normalised == runtime_did and A["#"] exists:
    if A["#"] is Deny:  return DENY
    if A["#"] is Allow(caps):
        if caps.contains("*") or caps ∩ required ≠ ∅:  return ALLOW
        return DENY

# Step 3 — Wildcard entry (terminates evaluation)
if A["*"] exists:
    if A["*"] is Deny:  return DENY
    if A["*"] is Allow(caps):
        if caps.contains("*") or caps ∩ required ≠ ∅:  return ALLOW
        return DENY

# Step 4 — Default deny
return DENY
```

Rules:

1. An explicit Deny for the caller's DID terminates evaluation immediately.
2. A direct DID match (step 1), local-actor match (step 2), or wildcard match
   (step 3) terminates evaluation immediately.
3. An empty sequence `[]` on a principal is a no-op. Implementations SHOULD
   log a warning at load time.
4. Multiple strings in `required` use **OR semantics**.

---

## 8. ACL locations (runtime)

On a 間 runtime, the ACL document lives at the manifest root:

| Location | Type | Purpose |
|----------|------|---------|
| Root `.acl` | CID | Transport gate for the whole runtime |

A missing or unresolvable CID MUST be treated as **deny all**.

---

## References

- [ma-runtime-v1.md](../runtime/ma-runtime-v1.md)
- [ma-crud-service-v1.md](../runtime/ma-crud-service-v1.md)
- [ma-messaging-format-v1.md](ma-messaging-format-v1.md)
