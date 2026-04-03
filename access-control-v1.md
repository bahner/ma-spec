# Access Control v1 (Capability Patterns)

**Version:** 0.0.1
**Status:** Draft

## 1. Goal

This document specifies a flexible access control model for realm and object
operations, based on capability strings and wildcard patterns.

Key properties:

- Owner is always superuser.
- Access is capability-based.
- Capabilities are simple strings with operation suffixes.
- Grants are explicit per DID (or wildcard `*`).
- Wildcards are supported for both global and local ACLs.

## 2. Owner Rule

`owner` MAY be represented as a symbolic ACL subject key.

Example:

```yaml
acl:
  owner:
   - "object.*.method.*.invoke"
```

Normative behavior:

1. If `subject_did == owner_did`, evaluator MUST consider grants under `owner`
  in addition to normal subject and `*` grants.
1. Owner access MUST be policy-driven (no implicit bypass in evaluator).
1. ACL mutation flows SHOULD reject updates that would remove required owner
  capabilities while owner remains unchanged.

## 3. Data Model

```yaml
acl:
  "*":
    - "*.read"
    - "world.entry.invoke"
  "did:ma:badactor": []
  "did:ma:bob":
    - "*.write"
    - "object.method.windup.invoke"
```

The ACL is a map of subject -> granted capability patterns.

Subject keys:

- Exact root DID, e.g. `did:ma:abc...`
- Wildcard `*` for default grant

Values are arrays of capability patterns.

### 3.1 Capability Strings

Capabilities are dot-separated strings.

Recommended operation suffixes:

- `.read`
- `.write`
- `.invoke`

Examples:

- `world.entry.invoke`
- `room.create.invoke`
- `object.read`
- `object.method.windup.invoke`

### 3.2 Wildcards

Wildcard token `*` is allowed in capability patterns.

Examples:

- `*.read` -> grants read over all capability namespaces.
- `object.method.*.invoke` -> grants invoke on all object methods.
- `world.room.*` -> grants all capabilities under `world.room`.

Pattern match uses simple glob semantics where `*` matches zero or more
characters (including `.`).

### 3.3 Global Capability Set via CID (Avatar Defaults)

An avatar MAY reference a global capability profile by CID:

```yaml
avatar:
  capabilities: bafy...
```

The referenced document is an ACL fragment that can be merged before local ACL
evaluation.

Merge order:

1. Global profile from CID.
1. Local ACL (room/object/world scope).

Local ACL SHOULD be able to add or narrow grants by choosing explicit subject
entries over wildcard defaults.

An empty list (`[]`) means no capabilities for that subject.

## 5. Evaluation Algorithm

Given `(subject_did, owner_did, acl, requested_capability)`:

1. If `subject_did == owner_did`: allow.
1. Resolve subject grants:
   - Use `acl[subject_did]` if present.
   - Else use `acl["*"]` if present.
   - Else deny.
1. Allow if any granted capability pattern matches `requested_capability`.
1. Deny otherwise.

## 6. Pattern Matching Rules

1. Pattern matching MUST be case-sensitive.
1. `*` matches zero or more characters.
1. Exact matches and wildcard matches are both valid grants.
1. If multiple patterns match, allow result is unchanged (logical OR).

## 7. Precedence

1. Owner rule (highest)
1. Exact DID grant
1. Wildcard `*` grant
1. Implicit deny

## 8. Validation Requirements

An ACL document MUST be rejected if:

- Any DID key is invalid.
- Any subject value is not a list of strings.
- Any capability pattern is empty.

## 9. Suggested Capability Hierarchy

To avoid collisions, capability names SHOULD use stable namespaces.

Recommended roots:

- `world.*`
- `room.*`
- `object.*`
- `own.*`

Recommended capabilities:

- `world.entry.invoke`
- `room.create.invoke`
- `object.create.invoke`
- `object.read`
- `own.recycle.invoke`
- `object.method.<method>.invoke`

Object-specific variants are also valid:

- `object.<object_id>.read`
- `object.<object_id>.write`
- `object.<object_id>.recycle.invoke`
- `object.<object_id>.method.<method>.invoke`

Guidance:

- Use wildcard forms in global ACLs (for broad role policy), e.g.
  `object.*.method.*.invoke`.
- Use object-id forms in local/object ACLs (for per-object policy), e.g.
  `object.nanoid123.method.windup.invoke`.

Examples:

- Give normal users baseline rights:

```yaml
acl:
  "*":
    - "world.entry.invoke"
    - "room.create.invoke"
    - "object.create.invoke"
    - "own.recycle.invoke"
    - "object.read"
```

- Object-local ACL for specific methods:

```yaml
acl:
  "*":
    - "object.method.tap.invoke"
  "did:ma:bob":
    - "object.method.windup.invoke"
    - "object.write"
```

Short names SHOULD be avoided in persisted ACL documents.

## 10. Global + Local ACL Merge

Global and local ACLs SHOULD be evaluated as two separate policy layers.

Recommended model:

1. Global ACL: broad identity policy (avatar/profile defaults, often from CID).
1. Local ACL: resource policy (object/room/world-specific rules).
1. Effective allow: both layers must allow the requested capability.

Normative rule:

- Access is allowed only if `global_match == true` AND `local_match == true`.

Rationale:

- Global policy expresses what a subject can generally do.
- Local policy expresses what this specific resource permits.
- This avoids accidental privilege escalation from either layer alone.

### 10.1 Invocation Example

Given request `object.nanoid123.method.windup.invoke`:

- Global grants include `object.*.method.*.invoke`
- Local object ACL includes `object.nanoid123.method.windup.invoke`

Result: allowed.

If local ACL omits windup invoke, result is denied even if global wildcard exists.

### 10.2 About `object.*.invoke`

If you want "invoke all methods", prefer explicit method wildcard:

- `object.*.method.*.invoke`

This is clearer than `object.*.invoke` and avoids ambiguity between object-level
invoke and method-level invoke.

## 11. ACL Compiler (CID-Friendly)

Capability ACLs SHOULD support a compile step that produces a normalized
evaluation artifact.

Why compile:

- Stable reuse across many contexts via CID.
- Faster runtime evaluation (exact and wildcard sets pre-partitioned).
- Deterministic policy snapshots for debugging and audits.

### 11.1 Compiled Artifact (Concept)

Implementation-oriented shape:

- per-subject exact capability set
- per-subject wildcard capability list

Subject lookup order remains:

1. exact DID
1. wildcard subject `*`

### 11.2 Core API Direction

The shared core ACL module SHOULD expose functions equivalent to:

- `compile_acl(acl, source) -> compiled_acl`
- `compile_acl_from_text(raw, source) -> compiled_acl`
- `evaluate_compiled_acl(compiled_acl, subject, capability) -> bool`
- `evaluate_compiled_acl_with_owner(compiled_acl, subject, owner, capability) -> bool`

### 11.3 CID Storage Pattern

Recommended reuse model:

1. Author ACL text.
1. Compile ACL.
1. Store source ACL and/or compiled ACL as content-addressed artifacts in IPFS.
1. Reference CID from world/room/object/avatar policy slots.

Global ACL CIDs are especially good reuse candidates across multiple worlds and
runtime instances.
