# ACL and Capabilities Model

**Version:** 0.1.0
**Status:** Draft

## Abstract

This document defines the capabilities-based access control model used
across 間 services. An `AclMap` maps principals to named capability strings
using deny-wins semantics.

**Applicable to:** Any 間 service that needs access control. The transport
gate and CRUD namespace management on a runtime are the primary users, but
the model is general and MAY be applied at any layer (entity-level verb
gates, namespace gates, client-side inbox filters, etc.).

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
full DID or `*`) or a group reference (see §5). Every value is one of:

| YAML value | Meaning |
|------------|---------|
| `null` or bare key | **Explicit deny** — overrides all wildcards |
| YAML sequence | **Allow** — caller receives exactly the listed capabilities |
| (absent) | Equivalent to explicit deny |

There is no "grant-by-capability" notation. All grants are per-principal.

---

## 3. Canonical YAML format

Implementations MUST serialise and accept ACL maps in this exact form:

```yaml
# Transport gate — who may use which protocols
"*":              [rpc]            # everyone: RPC access
"did:ma:alice":   [rpc, inbox]     # alice: RPC + inbox
"did:ma:eve":                      # bare key → explicit deny

# Group entries — group members inherit these capabilities
"+alice.venner": [fortune, secret]
"+alice.project4.admins": [admin, supersecret]
"+alice.fiender":             # group is explicitly denied
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

## 4. Built-in capability strings

The following capability strings have normative meanings at the transport and
resource-allocation layer. They MUST NOT be used as namespace or entity
names (see [ma-runtime-v1.md §16](ma-runtime-v1.md)).

| Capability | Layer | Meaning |
|------------|-------|---------|
| `"inbox"` | Transport | May deliver messages via `/ma/inbox/0.0.1` |
| `"rpc"` | Transport | May call `/ma/rpc/0.0.1` |
| `"ipfs"` | Transport | May publish via `/ma/ipfs/0.0.1` |
| `"crud"` | Transport | May call `/ma/crud/0.0.1` |
| `"ping"` | Transport | May send `:ping` atom (subset of `rpc`) |
| `"read"` | CRUD | Read entities, config, namespace contents |
| `"create"` | CRUD | Generic create permission |
| `"update"` | CRUD | Update existing entities or namespace contents |
| `"delete"` | CRUD | Delete entities or namespaces |
| `"entities"` | CRUD | Required (with `create`/`delete`) for entity management |
| `"kinds"` | CRUD | Required (with `create`/`delete`) for kind management |
| `"*"` (in Allow set) | Any | Grants all capabilities for this principal |
| `"<ns>"` (bare NCName) | Resource | Ownership grant for namespace `<ns>` |

Entity-level ACLs may use arbitrary strings as capability names
(`"handle_cast"`, `"reply"`, `"secret"`, etc.).

---

## 5. Group principals

Groups are referenced in an `AclMap` using the `+<handle>.<path>` prefix.
The path is dot-separated and may be of arbitrary depth:

```yaml
+alice.venner: [fortune, secret]
+alice.project4.admins: [admin, supersecret]
+alice.fiender:             # group is explicitly denied
```

A `+group` entry works exactly like a DID entry: the runtime resolves the
group's membership list (§6) and, if the caller is a member, applies that
entry's capabilities.

---

## 6. Evaluation algorithm (normative)

**Input:** ACL map `A`, caller DID `caller`, capability set `required`
(one or more strings; **OR semantics** — the check passes if the caller
holds **at least one** of the listed capabilities).

**Per-check algorithm:**

```
normalised = strip_fragment(caller)

# Step 1 — Direct DID lookup (terminates evaluation)
if A[normalised] exists:
    if A[normalised] is Deny:  return DENY
    if A[normalised] is Allow(caps):
        if caps.contains("*") or caps ∩ required ≠ ∅:  return ALLOW
        return DENY

# Step 2 — Wildcard entry (terminates evaluation)
if A["*"] exists:
    if A["*"] is Deny:  return DENY
    if A["*"] is Allow(caps):
        if caps.contains("*") or caps ∩ required ≠ ∅:  return ALLOW
        return DENY

# Step 3 — Group principal scan (+prefix keys only)
# 3a: deny groups — checked first
for each key in A where key.starts_with("+") and A[key] is Deny:
    if normalised ∈ resolve_group(key):  return DENY

# 3b: allow groups
for each key in A where key.starts_with("+") and A[key] is Allow(caps):
    if normalised ∈ resolve_group(key):
        if caps.contains("*") or caps ∩ required ≠ ∅:  return ALLOW

# Step 4 — Default deny
return DENY
```

Rules:

1. An explicit Deny for the caller's DID terminates evaluation immediately.
2. A direct DID match (step 1) or wildcard match (step 2) terminates
   evaluation — the caller does not fall through to group checks.
3. An empty sequence `[]` on a principal is a no-op. Implementations SHOULD
   log a warning at load time.
4. Multiple strings in `required` use **OR semantics**.
5. Group deny entries (step 3a) are scanned before group allow entries
   (step 3b) — a caller in both a deny group and an allow group is denied.

---

## 7. Group membership resolution

Groups are **IPLD lists** stored as leaf values in the namespace tree:

```yaml
alice:
  venner: [ "did:ma:carlotta", "did:ma:fjodor" ]
  admins: [ "did:ma:bahner" ]
```

**Resolution:** Strip the `+` sigil, replace each `.` with `/`, walk the
IPLD DAG from the manifest root. If the path resolves to a list, compare
each element (fragment-stripped) to the caller DID. A missing path or
non-list node is treated as **empty** (fail-closed).

Group resolution results SHOULD be cached keyed by `(path, node-cid)`.
A stale cache MUST NOT cause a false ALLOW — on cache miss, re-resolve
from IPFS.

---

## 8. ACL locations (runtime)

On a 間 runtime, ACL documents live at four locations in the manifest:

| Location | Type | Purpose |
|----------|------|---------|
| Root `.acl` | CID | Transport gate for the whole runtime |
| Root `.acls.<name>` | CID | Named ACL library — resolved by `EntityNode.acl` name |
| `<ns>.acl` | CID | Namespace gate |
| `<ns>.acls.<name>` | CID | Named ACL within a namespace |
| `EntityNode.acl` | name string | Verb-level gate |

A missing or unresolvable CID at any level MUST be treated as **deny all**.

---

## References

- [ma-runtime-v1.md](ma-runtime-v1.md)
- [ma-crud-service-v1.md](ma-crud-service-v1.md)
- [messaging-format.md](../messaging-format.md)
