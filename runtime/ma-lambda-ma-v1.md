# ma-lambda-ma-v1 - Lambda-ma World Profile

**Status:** Draft
**Version:** 0.2.0
**Date:** 1 August 2026

---

## Abstract

This document defines the lambda-ma world profile: rooms, avatars, exits,
containers, visible entities, and the command traffic that moves actors between
parents. It is an optional profile on top of the ma runtime RPC service.

The central data concept in this profile is `ctx`. A ctx describes the
situation of an actor or thing: where it is, how it is presented, and which
actor references are relevant to that situation. A ctx is not the actor's full
state, not a generic state exchange, and not a command-flow protocol.

This version defines exactly three ctx shapes:

- `avatar-ctx`
- `room-ctx`
- `container-ctx`

No `enter-ctx`, `traversal-ctx`, or movement ctx shape is defined by this
profile.

---

## 1. Scope

This profile standardises world-layer behaviour only:

- focus routing boundaries between avatar-mediated commands and direct methods,
- room-first entry semantics,
- the three defined ctx shapes,
- authority boundaries for ownership and parent changes,
- movement sequencing between avatars or agents, rooms, and exits,
- container and inventory situation reporting.

Out of scope:

- DID method rules; see [../did-ma-spec-v1.md](../did-ma-spec-v1.md),
- core message envelopes; see [../core/ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md),
- base RPC service rules; see [../core/ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md),
- generic runtime conformance.

---

## 2. Conformance and requirement level

This is a profile specification, not a base runtime requirement.

- A runtime MAY implement this profile.
- A runtime that claims conformance to this profile MUST satisfy sections 4-10.
- A runtime that does not implement this profile remains conformant to the base
  runtime and core service specifications it otherwise implements.

Clients targeting world-like runtimes SHOULD support this profile when it is
available.

---

## 3. Transport and term model

This profile uses standard ma RPC traffic:

1. Service protocol: `/ma/rpc/0.0.1`.
2. Message types: `application/vnd.ma.rpc.request` and
   `application/vnd.ma.rpc.reply`.
3. Content type: `application/vnd.ma.term`.
4. Payload: CBOR term, either an atom such as `:look` or a list with an atom
   head such as `[:look, "lamp"]`.

All actor references crossing actor, client, or runtime message boundaries MUST
be full DIDs or DID-URLs. Runtime-local `#fragment` shorthand is an internal
runtime convenience and MUST NOT be sent or persisted in ctx.

---

## 4. Focus routing contract

Clients MAY provide focus shorthand. When they do, routing is split by the
leading colon:

1. Commands without leading `:` are avatar-mediated user commands.
2. Commands with leading `:` are direct methods on the focused room or target.

Avatar-mediated command dispatch MUST normalise the command word only. The
first word of a shorthand command, or equivalently the first term in the RPC
argument list, is matched case-insensitively. Arguments MUST NOT be
case-normalised. For example, `Look` is handled as `look`, while
`Say Hello THERE` is handled as verb `say` with text `Hello THERE`.

World actors conforming to this profile MUST preserve this boundary and MUST
NOT require avatar proxying for colon-prefixed room methods.

Examples:

- Avatar-mediated: `look`, `say hello`, `go north`, `dig east`.
- Direct: `:help`, `:prop name Garden`, `:look`.

---

## 5. Ctx model

Ctx is a situational description. It says what actor or thing is being
described, where it currently belongs, and how it may be presented or located by
neighbouring actors. It is deliberately narrower than state.

Ctx MUST NOT be used as a generic command-flow envelope. Entry, traversal,
take, drop, and ownership changes are commands. They may carry ordinary maps or
arguments as implementation details, but those maps are not new ctx shapes unless
this profile defines them as such.

### 5.1 Common ctx rules

The following rules apply to all ctx shapes in this profile:

1. A ctx describes one actor or thing situation.
2. A ctx is not direct authority over the described actor.
3. A ctx is not the actor's complete state.
4. Unknown fields MUST be tolerated after the receiver has identified the ctx
   shape.
5. Known actor references MUST be full DIDs or DID-URLs.
6. If a ctx conflicts with the described actor's self-authenticated current
   situation, the actor wins.

Only `msg.from` is authenticated by the message layer. Receivers MUST treat ctx
fields such as `actor`, `avatar`, `room`, `parent`, `root`, and `inv` as
claims until validated against `msg.from` and local policy. For avatar ctx,
validation SHOULD include deterministic avatar derivation for the controlling
DID where that relation matters.

### 5.2 Ctx definitions

The `/ma/ctx/*/0.0.1` strings name the ctx definitions in this profile. They are
not fields inside the payload. Ctx payloads are flat maps or association lists;
receivers recognise them by message routing, expected sender, and required data
fields.

The defined ctx payloads are:

| Ctx payload | Definition |
| --- | --- |
| `avatar-ctx` | `/ma/ctx/avatar/0.0.1` |
| `room-ctx` | `/ma/ctx/room/0.0.1` |
| `container-ctx` | `/ma/ctx/container/0.0.1` |

Implementations MUST NOT invent additional ctx shapes for entry or traversal
under this profile.

---

## 6. Avatar ctx

Avatar ctx describes the active avatar situation for a controlling DID. It is
the ctx shape a client such as zion consumes to update focus, prompt, and saved
session context.

Canonical wire term:

```text
[:ctx,
  [
   [":kind", "avatar"],
   [":root", <root-did-url>],
   [":avatar", <avatar-did-url>],
   [":inv", <inventory-container-did-url-or-empty>],
   [":nick", <nick>],
   [":room", <room-did-url>],
   [":text", <display-text-or-empty>]
  ]]
```

Reply-wrapped form is also valid:

```text
[:ok, [:ctx, [[":kind", "avatar"], ...]]]
```

Fields:

| Key | Type | Meaning |
| --- | --- | --- |
| `:kind` | text | Effective session kind, normally `avatar`. |
| `:root` | DID-URL | Runtime root actor. |
| `:avatar` | DID-URL | Active avatar actor. |
| `:inv` | DID-URL or empty text | Avatar's configured inventory container. |
| `:nick` | text | Active display nickname. |
| `:room` | DID-URL | Current room actor. |
| `:text` | text | Optional user-facing status line. |

A client SHOULD accept avatar ctx only from an expected root, expected avatar,
or an actor path trusted by an in-progress room entry. A client MUST NOT treat
room ctx, container ctx, or transient movement traffic as committed session
focus.

Avatars SHOULD create or reuse a deterministic local `/ma/container/0.0.1`
container as inventory. The avatar ctx `:inv` field publishes that
container DID-URL. Carried actors SHOULD be parented to the inventory container,
not directly to the avatar.

---

## 7. Room ctx

Room ctx describes a room's visible situation. It is a full snapshot, not a
delta. A room sends fresh room ctx to present avatars when visible room state
changes: avatar presence, agent presence, thing/container visibility, labels,
room text, or exit topology.

Room ctx is a string-keyed map. It MUST contain:

| Key | Type | Meaning |
| --- | --- | --- |
| `protocol` | text | Room actor behaviour identifier, normally `/ma/room/0.0.1`. |
| `kind` | text | Exactly `room`. |
| `actor` | DID-URL | Room actor that produced the snapshot. |
| `parent` | DID-URL | Parent/root actor. |
| `rev` | integer | Monotonic room-local revision. |
| `name` | text | Room name. |
| `nick` | text | Room display name. |
| `description` | text | Room description. |
| `who` | list | Visible avatar entries. |
| `agents` | list | Visible agent entries. |
| `things` | list | Visible thing or container entries. |
| `exits` | list | Visible exit entries. |

Entries SHOULD include `actor`, `kind`, `protocol`, `name`, `nick`, and
`description` when known. Exit entries SHOULD also include `direction`.

Avatars SHOULD keep only the newest room ctx by `rev`. Older or equal revisions
SHOULD be ignored. Avatar-mediated `look <name>` SHOULD resolve from carried
inventory first, then from stored room ctx, and then ask the resolved target
actor to present itself. Room ctx grants lookup and presentation information; it
does not grant mutation authority over referenced actors.

---

## 8. Container ctx

Container ctx describes a container's contents situation. It is a full snapshot,
not a delta. A container sends fresh container ctx to its current parent when
contents presentation changes: child admission, child removal, stale-entry
pruning, or explicit reconciliation.

Container ctx is a string-keyed map. It MUST contain:

| Key | Type | Meaning |
| --- | --- | --- |
| `protocol` | text | Container actor behaviour identifier, normally `/ma/container/0.0.1`. |
| `kind` | text | Exactly `container`. |
| `actor` | DID-URL | Container actor that produced the snapshot. |
| `parent` | DID-URL | Parent actor the snapshot was sent to. |
| `rev` | integer | Monotonic container-local revision. |
| `name` | text | Container name. |
| `nick` | text | Container display name. |
| `description` | text | Container description. |
| `contents` | map | Child presentation entries keyed by full child DID-URL. |

A parent MAY ignore container ctx. Parents that care, such as avatars treating a
configured container as inventory, SHOULD keep only the newest snapshot by
`rev`. Container contents are last-known-good presentation data. They are not
stronger than the child actor's own accepted parent situation.

---

## 9. Entry

Entry is command traffic, not a ctx shape.

When a concrete room target is known, entry MUST be room-first:

1. The client sends `:enter` to the room actor.
2. The room validates the entry intent.
3. For ordinary DID entry, the room creates or reuses the deterministic local
   avatar for that DID.
4. If the avatar already exists, the room or root MAY ask it to enter with the
   narrow `:enter-room` method.
5. The avatar sends `:enter` to the room.
6. The room commits presence and sends avatar ctx to the avatar.
7. The avatar persists the committed room and forwards avatar ctx to the DID
   principal.

Root entry is a compatibility path for clients that know only the runtime root.
The root MAY create or find the deterministic avatar and ask it to publish its
current avatar ctx to the DID principal. The root MUST NOT message rooms on the
client's behalf.

Direct non-avatar admission, such as an agent or thing entering a room, is
room-local policy. An implementation MAY require a map containing situational
presentation fields such as `kind`, `actor`, `parent`, `protocol`, `name`,
`nick`, and `description`. That map is an admission payload, not a fourth ctx
shape.

---

## 10. Movement and exits

Movement is command traffic, not a ctx shape.

Typical movement sequence:

1. A DID sends avatar-mediated `go <direction>`.
2. The avatar resolves `<direction>` from its current room ctx.
3. The avatar asks the exit actor to traverse.
4. The exit applies its own policy, such as locked or unlocked.
5. If blocked, the avatar prints the blocked text and remains in its current
   room.
6. If allowed, the avatar asks the target room to admit it.
7. The target room commits entry and sends avatar ctx to the avatar.
8. The avatar persists the committed room, forwards avatar ctx to the DID
   principal, and only then notifies the old room for cleanup.

Any transient map used between an avatar, room, or exit during movement is
implementation traffic. It MUST NOT be consumed by clients as committed focus,
and it MUST NOT be specified as `traversal-ctx` or any other public ctx shape.

Existing-room exit linking SHOULD use a room-to-room handshake:

1. Source room records a pending request.
2. Source room pings the target room.
3. Target room replies with liveness.
4. Source room asks target room for link authorisation.
5. Target room authorises or denies based on room policy.
6. Source room creates or replaces the exit only after authorisation.

New-room digging MAY be asynchronous. If actor creation is not immediately
live, the source room SHOULD record pending state and wait for a child-alive or
equivalent readiness callback before installing the exit.

---

## 11. Authority model

### 11.1 Room ownership

Room ownership is by bare user DID.

- Avatar actors are delegation surfaces for user commands.
- Rooms MAY recognise the deterministic same-runtime avatar for the owner DID.
- Rooms MUST NOT treat arbitrary avatar claims as ownership proof.

### 11.2 Parent changes

Movable actors are authoritative for their own accepted parent situation.
Parents and containers keep derived caches.

Parent/child method names describe the receiver's role:

- `:parent` is sent to an actor that is being asked to act as parent.
- `:child` is sent to an actor that is being asked or informed as child.

Therefore a child actor proposes or reports parent state by sending
`<parent>:parent <ctx>`. A parent confirms, rejects, or informs child state by
sending `<child>:child <ctx>`.

Drop and reparenting MUST preserve this direction. A carried actor sends
`<new-parent>:parent <desired-ctx>` to request adoption by the new parent. If
accepted, the new parent sends `<actor>:child <committed-ctx>` back. The actor
MUST accept the committed ctx only when `ctx.parent == msg.from` and the ctx
matches the actor's own identity and pending parent-change expectation. After
committing the new parent, the actor SHOULD send a courtesy
`<old-parent>:parent <departure-or-new-parent-ctx>` update so the old parent can
remove or refresh derived cache entries. Implementations MUST NOT reverse this
direction by sending child-to-parent traffic as `:child` or parent-to-child
traffic as `:parent`.

Target-accepted parent changes SHOULD follow this shape:

1. The moving actor currently belongs to `old_parent`.
2. The moving actor, or an authorised current parent, requests admission to
   `new_parent`.
3. `new_parent` accepts or rejects.
4. On acceptance, the moving actor commits `new_parent` locally.
5. The moving actor notifies `old_parent` after commit.
6. `old_parent` clears derived caches and has no ordinary veto after commit.

Canonical transfer command forms:

```text
[:take, <user-did>, <carrier-parent-did-url>, <optional-situational-map>]
[:drop, <user-did>, <target-parent-did-url>, <optional-situational-map>]
```

Validation requirements:

1. User arguments MUST be bare `did:ma:...` DIDs.
2. Parent references MUST be DID-URLs.
3. If an owner is set, protected transfers MUST require the user argument to
   match the owner.
4. Optional situational maps MUST NOT be treated as authority without sender
   validation.

---

## 12. Error behaviour

World verbs use standard RPC error terms:

```text
[:error, <reason>]
```

`reason` SHOULD be stable when clients need branching logic. Human-readable
diagnostics are allowed for user-facing failures.

---

## 13. Interoperability guidance

Implementing this profile improves predictability for clients such as zion.
Not implementing this profile is valid; clients may fall back to
runtime-specific behaviour.

Clients SHOULD:

1. Route focus shorthand according to section 4.
2. Commit focus only from trusted avatar ctx.
3. Ignore room ctx and container ctx for session focus.
4. Treat unknown ctx fields as forward-compatible data.
5. Avoid inventing client-side movement or entry ctx shapes.

World actors SHOULD:

1. Publish room ctx and container ctx as full snapshots with monotonic `rev`.
2. Publish avatar ctx only after committed avatar situation changes.
3. Use full DID-URLs in ctx.
4. Keep transient movement maps actor-internal.
5. Keep old-parent cleanup after target admission commit.

---

## 14. Conformance checklist

To claim conformance to this profile, an implementation MUST:

1. Use standard ma RPC term traffic for world commands.
2. Preserve the focus routing boundary between avatar-mediated and direct
   methods.
3. Define no public ctx shapes beyond avatar ctx, room ctx, and container ctx.
4. Treat ctx as situational description, not actor state or command exchange.
5. Include `:inv` in avatar ctx when an inventory container is configured.
6. Use room-first entry when a concrete room target is known.
7. Ensure movement commits through target-room admission before publishing new
   avatar ctx to the client.
8. Use full DID or DID-URL references in ctx.
9. Keep parent, occupant, and container contents caches derived from accepted
   actor situations.
10. Return standard `[:error, <reason>]` terms for command failures.

---

## References

- [../did-ma-spec-v1.md](../did-ma-spec-v1.md)
- [../core/ma-rpc-service-v1.md](../core/ma-rpc-service-v1.md)
- [../core/ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md)
