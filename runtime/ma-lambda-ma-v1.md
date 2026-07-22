# ma-lambda-ma-v1 — Lambda-ma World Profile

**Status:** Draft
**Version:** 0.1.0
**Date:** 22 July 2026

---

## Abstract

This document defines a **runtime profile** for world-style actor interaction,
based on the lambda-ma actor model. It is designed to be broadly reusable as a
general pattern for interoperable multi-user actor spaces (rooms, avatars,
movement, and movable entities), while still remaining **optional**.

A runtime does not need this profile to conform to
[ma-runtime-v1.md](ma-runtime-v1.md). However, runtimes and clients that
implement this profile gain a shared behavioral contract that improves
cross-world interoperability.

---

## 1. Scope

This profile standardizes world-layer behavior only:

- focus routing boundaries between avatar-mediated and direct methods,
- enter semantics and required enter context shape,
- authority boundaries for room ownership and parent-mediated transfer,
- movement/traversal sequencing between room and exit actors.

Out of scope:

- DID method rules (see [../did-ma-spec-v1.md](../did-ma-spec-v1.md)),
- core message envelope and service contracts (see [../core/README.md](../core/README.md)),
- generic runtime conformance requirements (see [ma-runtime-v1.md](ma-runtime-v1.md)).

---

## 2. Conformance and requirement level

This is a **profile specification**, not a base runtime requirement.

- A runtime MAY implement this profile.
- A runtime that claims conformance to this profile MUST satisfy sections 4–7.
- A runtime that does not implement this profile remains conformant to
  [ma-runtime-v1.md](ma-runtime-v1.md).

Interoperability recommendation:

- Runtimes targeting cross-world client interoperability SHOULD implement this
  profile.
- Clients targeting world-like runtimes SHOULD support this profile when
  available.

---

## 3. Design intent

The profile is intentionally generic despite originating from lambda-ma.

- It does not require a specific implementation language.
- It does not require a specific internal storage model.
- It defines actor-facing behavior and message semantics, not host internals.

The goal is to provide a stable common contract for world interaction that
multiple runtimes can share.

---

## 4. Transport and term model

This profile uses the standard runtime RPC transport and term encoding:

1. Service protocol: `/ma/rpc/0.0.1`
2. Message types: `application/vnd.ma.rpc.request` and
  `application/vnd.ma.rpc.reply`
3. `contentType`: `application/vnd.ma.term`
4. Payload: CBOR term (`:atom` or tuple/list with atom head)

This profile adds world semantics on top of those base rules.

---

## 5. Focus routing contract

When a client provides focus shorthand, routing semantics are:

1. Commands without leading `:` are avatar-mediated user commands.
2. Commands with leading `:` are direct methods on the focused room/target.

Runtimes and world actors conforming to this profile MUST preserve this
boundary and MUST NOT require avatar proxying for colon-prefixed methods.

Examples:

- avatar-mediated: `look`, `say hello`, `go north`, `dig east`
- direct: `:help`, `:prop name Garden`, `:look`

---

## 6. Client context term (`:ctx`) format

This profile distinguishes two different context payload concepts.

1. Enter request context map (section 7.2): map keyed by plain strings
  (`"kind"`, `"name"`, `"nick"`, `"description"`).
2. Client update context term (this section): `:ctx` term keyed by symbol-like
  text keys (`":protocol"`, `":kind"`, `":root"`, `":avatar"`, `":room"`,
  `":nick"`, `":text"`).

The lambda-ma context protocol ID is `/ma/lambda/ctx/0.0.1`.

Canonical client context term shape:

```text
[:ctx,
  [
  [":protocol", "/ma/lambda/ctx/0.0.1"],
  [":kind",   <effective_kind>],
   [":root",   <root_did_url>],
   [":avatar", <avatar_did_url>],
   [":nick",   <nick>],
   [":room",   <room_did_url>],
   [":text",   <display_text_or_empty>]
  ]
]
```

Reply-wrapped form (also valid):

```text
[:ok, [:ctx, [[":protocol", "/ma/lambda/ctx/0.0.1"], ...]]]
```

Field meanings:

| Key | Type | Meaning |
| --- | --- | --- |
| `:protocol` | text | Context protocol ID; MUST be `/ma/lambda/ctx/0.0.1` for this version |
| `:kind` | text | Effective session/presence kind chosen by the world, such as `avatar` or `agent` |
| `:root` | text | Root/placement actor DID-URL |
| `:avatar` | text | Active avatar DID-URL, or empty when this context does not use an avatar |
| `:room` | text | Active room DID-URL |
| `:nick` | text | Display nickname |
| `:text` | text | User-facing status line |

Processing recommendations:

1. Receivers MUST reject unknown or unsupported `:protocol` values.
2. Receivers SHOULD ignore unknown `:ctx` key pairs after protocol validation.
3. Receivers SHOULD tolerate missing optional keys.
4. Clients SHOULD treat empty-string values as delete/clear for that field.

Trust recommendations:

1. A `:ctx` update SHOULD be accepted only from trusted actors (expected root,
  expected avatar, or in-progress enter target).
2. If an enter request is pending, clients SHOULD require `:room` to match the
  pending target before commit.

---

## 7. Enter contract

### 7.1 Room-first behavior

When a concrete room target is known, enter flow MUST be room-first:

1. Client sends `:enter` to the room actor.
2. Room validates enter context.
3. Room requests authoritative arrival registration from root/placement actor.

A runtime MAY also provide a root-only compatibility enter path, but room-first
behavior is the profile baseline.

### 7.2 Enter request payload (`ctx`) shape

Room-first enter MAY carry no payload, or MAY carry one extensible map named
`ctx`. Profile terminology uses `ctx`; alternate parallel map names are out of
profile.

Missing `ctx.kind` means free identity entry: the caller has its own DID and asks
the room/world to choose an effective session kind and return committed context.

Direct non-avatar occupants MUST identify themselves with a strict `ctx` map
containing non-empty strings:

- `kind` (`agent` or `thing`)
- `name`
- `nick`
- `description`

Rules:

1. Missing `ctx.kind` MUST NOT be interpreted as direct local occupancy.
2. `ctx.kind = "agent"` or `"thing"` with missing or empty required keys MUST be
  rejected.
3. Additional keys MAY be included and MUST be tolerated for forward
  compatibility.

Canonical request term:

```text
[:enter, {
  "name": "display-name",
  "nick": "short-nick",
  "description": "human-readable description"
  ... optional extension keys ...
}]
```

`ctx` key definitions:

| Key | Type | Required | Meaning |
| --- | --- | --- | --- |
| `kind` | text | no for free identity entry; yes for direct occupants | Caller category hint (`agent`, `thing`, or explicit profile extension) |
| `name` | text | yes for direct occupants | Long display name |
| `nick` | text | optional for free identity entry; yes for direct occupants | Short in-room display name |
| `description` | text | yes for direct occupants | Human-readable profile/identity description |

Validation requirements:

1. Request payload, when present, MUST be a map.
2. Direct occupant requests MUST be rejected if any required key is missing.
3. Direct occupant requests MUST be rejected if any required value is empty text.
4. Unknown keys MUST NOT cause rejection by themselves.

### 7.3 Enter reply and commit semantics

Room enter is asynchronous in two phases:

1. Immediate reply acknowledging the request term.
2. Later context update reflecting committed location.

Recommended immediate success reply:

```text
[:ok, "entering"]
```

Recommended error reply:

```text
[:error, <reason>]
```

`reason` SHOULD be stable machine-usable text when interoperability decisions
depend on it (for example `invalid-enter-ctx`), but human-readable text is
allowed.

### 7.4 Client commit behavior

Client context/focus commit SHOULD be acknowledgment-driven:

- send of enter request alone does not imply commit,
- commit occurs when acknowledgment is received from expected actor path.

---

## 8. Movement and traversal message structure

### 8.1 Core traversal verbs

| Verb | Typical sender | Typical receiver | Canonical args |
| --- | --- | --- | --- |
| `:go` | avatar | room | `<direction>` |
| `:traverse` | room | exit | `<avatar> <source-room?> <user?> <nick?>` |
| `:enter` | root or exit | room | `<avatar> <old-room?>` |
| `:enter` | exit | room | `<user> <avatar> <old-room> <nick?>` |
| `:arrived` | room | root | `<avatar> <room>` |
| `:arrive-user` | room | root | `<user> <room> <nick?>` |

### 8.2 Sequencing model

A conforming profile implementation SHOULD follow this sequencing model:

1. Avatar/user command reaches current room.
2. Room delegates traversal to exit actor.
3. Exit emits enter call to target room (`:enter`) using one of the two payload
  shapes defined above.
4. Target room requests authoritative arrival registration from root/placement
  actor.
5. Root/placement actor updates authoritative location registry and context
  propagation.

### 8.3 Existing-room link handshake

For existing-room link targets, room-to-room handshake SHOULD be used:

1. Source room records pending request.
2. Source room sends `:ping` to target room.
3. Target answers `:pong`.
4. Source requests `:authorize-link`.
5. Target returns `:link-authorized` or `:link-denied`.
6. Source creates/replaces exit only on authorization.

---

## 9. Authority model

### 9.1 Room ownership

Room ownership is by user DID.

- Avatar is a delegation surface for user commands.
- Direct room calls evaluate caller identity from `msg.from`.

### 9.2 Parent-mediated transfer

Movable entities are authoritative for their own `owner` and `parent` state.

- `take` and `drop` are governed by current parent authority.
- Caller requesting transfer MUST be the current parent.
- Target parent is transfer payload, not an independent authority caller.
- Current parent and target parent do not need direct peer negotiation.

Canonical transfer requests:

```text
[:take, <user-did>, <carrier-parent-did-url>, <ctx-map?>]
[:drop, <user-did>, <target-parent-did-url>, <ctx-map?>]
```

Validation requirements:

1. Caller MUST be current parent.
2. If owner is set, user argument MUST match owner for protected transfers.
3. On successful transfer, entity updates its own `parent`.
4. User argument MUST be a `did:ma:...` DID.
5. Parent reference MUST be a `did:ma:...` DID-URL or local `#fragment`.
6. Optional `ctx-map` (when present) MUST include non-empty string fields:
  `kind`, `name`, `nick`, `description`.

Room enter `ctx.kind` routing guidance:

1. Missing `ctx.kind` or `ctx.kind = "avatar"` SHOULD use root arrival
  registration flow and return committed context.
2. `ctx.kind = "thing"` or `"agent"` MAY be categorized locally by room
  policy without root avatar registration.

---

## 10. Error behavior and stability guidance

World verbs use standard RPC error term form:

```text
[:error, <reason>]
```

Guidance:

1. `reason` SHOULD be stable across locales when clients need branching logic.
2. Human-readable text is valid for user-facing diagnostics.
3. Implementations MAY add profile-specific error codes as long as success and
  failure term shapes remain compatible.

---

## 11. Interoperability guidance

This profile is optional, but recommended for runtimes that want shared world
semantics with minimal client-specific branching.

- Implementing this profile improves predictability for clients like zion.
- Not implementing this profile is valid; clients may fall back to
  runtime-specific behavior.

---

## 12. Relationship to lambda-ma

lambda-ma is the reference world/profile that motivated this document.

- Canonical implementation-oriented world documentation remains in the lambda-ma
  repository.
- This profile captures portable rules suitable for cross-runtime interop.
- Implementation-specific details may evolve independently from this profile as
  long as profile-level semantics remain satisfied.

---

## 13. Conformance checklist

This checklist is non-normative in format, but each item references normative
requirements from this document.

### 13.1 Runtime/profile implementer checklist

To claim conformance to this profile, an implementation MUST satisfy:

1. Uses `/ma/rpc/0.0.1` with standard RPC request/reply message types and
  term encoding (section 4).
2. Preserves focus routing boundary:
  non-colon commands are avatar-mediated, colon-prefixed commands are direct
  room/target methods (section 5).
3. Supports room-first enter when a room target is known (section 7.1).
4. Validates enter payload as one `ctx` map with required non-empty string keys
  `kind`, `name`, `nick`, `description` (section 7.2).
5. Tolerates unknown extra `ctx` keys for forward compatibility (section 7.2).
6. Emits/accepts compatible client `:ctx` term shape as specified in section 6,
  or an equivalent representation that is unambiguously mappable to it.
7. Enforces parent-mediated transfer authority for movable entities so current
  parent is transfer caller authority (section 9.2).
8. Preserves standard RPC error term compatibility as `[:error, <reason>]`
  (section 10).

### 13.2 Interop quality checklist (SHOULD)

The following are strongly recommended for predictable cross-world behavior:

1. Client context commit is acknowledgment-driven for enter transitions
  (section 7.4).
2. `:ctx` updates are accepted only from trusted actor paths (section 6).
3. Traversal sequencing follows section 8.2.
4. Existing-room linking uses the handshake model in section 8.3.
5. Error `reason` values are stable enough for client control flow when needed
  (section 10).

---

## References

- [ma-runtime-v1.md](ma-runtime-v1.md)
- [ma-standard-actors-v1.md](ma-standard-actors-v1.md)
- [ma-scheme-v1.md](ma-scheme-v1.md)
- [../core/ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md)
- [../core/ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md)
