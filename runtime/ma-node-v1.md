# ma-node-v1 — the `/ma/node/0.0.1` base protocol

**Status:** Recommendation
**Version:** 1.0.0
**Date:** 5 September 2026

---

## Abstract

`/ma/node/0.0.1` is the base protocol for 間 *nodes*: the persistent actors
that form a single actor tree. Every node kind extends this protocol —
`/ma/thing/0.0.1`, `/ma/room/0.0.1`, `/ma/exit/0.0.1`,
`/ma/container/0.0.1`, `/ma/agent/0.0.1`, and `/ma/trigger/0.0.1`.

A node keeps authoritative state and participates in the one actor tree. For
any node to be presented, addressed, and described by any other actor or
client — no matter which runtime hosts it — the protocol requires one tiny,
shared verb surface: four read-only questions.

A MUST verb is the minimum a **foreign** actor — one that knows nothing about
this node's implementation — needs in order to interact with it. Verbs that
only arrange or repair the node's own tree are SHOULD, not MUST (§4).

This document specifies those four questions. They are the only verbs every
conforming node MUST answer. A conforming node MAY answer many more, and
SHOULD also answer the tree-maintenance verbs in §4.

---

## Table of contents

1. [The four questions](#1-the-four-questions)
2. [Replies](#2-replies)
3. [When a value is missing](#3-when-a-value-is-missing)
4. [Tree maintenance](#4-tree-maintenance)

---

## 1. The four questions

Every `/ma/node/0.0.1` node MUST answer four read-only verbs:

| Verb | Question it answers |
| --- | --- |
| `:name?` | "What is your full name?" |
| `:nick?` | "What short label do people use for you?" |
| `:description?` | "How would you describe yourself in one line?" |
| `:kind?` | "What kind of node are you?" |

These verbs are **read-only**. They MUST NOT change the node, and they MUST be
open to every caller — no ownership, no secret, no permission. They reveal the
same information a node already shows to the world.

- `name` — the full, human-readable name, such as `"Brass Lamp"`.
- `nick` — a shorter label, such as `"lamp"`. If a node has no separate
  nickname, `nick` is the same as `name`.
- `description` — one sentence, such as `"A battered brass lamp."`.
- `kind` — the node's protocol ID, such as `/ma/thing/0.0.1`.

---

## 2. Replies

Each verb MUST reply with the ordinary success term carrying a text string:

```
:name?         →  [:ok, "Brass Lamp"]
:nick?         →  [:ok, "lamp"]
:description?  →  [:ok, "A battered brass lamp."]
:kind?         →  [:ok, "/ma/thing/0.0.1"]
```

The terms follow [ma-messaging-format-v1.md §2.4](../core/ma-messaging-format-v1.md):

| Term | Meaning |
| --- | --- |
| `[:ok, <text>]` | success, with the requested string |
| `[:error, <reason>]` | failure — see §3 for when this is not the right answer |

---

## 3. When a value is missing

The name, nick, and description questions MUST NOT fail just because a node
was never given a custom value. If a value is unset, the node MUST answer with
a sensible fallback:

| Verb | Sensible fallback |
| --- | --- |
| `:name?` | the node's own address, e.g. its fragment |
| `:nick?` | the node's name |
| `:description?` | a short generic phrase, e.g. `"A node."` |
| `:kind?` | the node's protocol ID — a node always has one |

The exact fallback text is implementation-specific. A caller MUST always be
able to ask all four questions and get something back that can be shown to a
person.

---

## 4. Tree maintenance

The four questions are the only MUST verbs. A conforming node SHOULD also
answer a small set of tree-maintenance verbs, so its runtime can repair and
recount the actor tree. These are recommended, not required: an implementation
that arranges its node tree another way MAY omit them, at the cost of losing
the standard repair and recount tooling.

| Verb | Effect |
| --- | --- |
| `:parent <ctx>` / `:child <ctx>` | propose / acknowledge a parent-child link |
| `:parent?` | reply with the current parent DID-URL |
| `:children?` | reply with the children map |
| `:roll-call [begin [secs]\|end]` | recount the children |
| `:roll-call-child` | answer a roll-call by re-announcing to the current parent |
| `:phone-home` | re-announce to the current parent |
| `:orphan-root` | fall back to the runtime root as parent |
| `:here <room>` | learn the current room and cascade it to children |

The detailed handshake and roll-call semantics are specified in
[ma-lambda-ma-v1.md](ma-lambda-ma-v1.md).

---

## Companion documents

- [ma-messaging-format-v1.md](../core/ma-messaging-format-v1.md) — the reply terms
- [ma-kinds-v1.md](ma-kinds-v1.md) — the node kinds that extend this protocol
- [ma-lambda-ma-v1.md](ma-lambda-ma-v1.md) — the world profile whose node kinds extend this protocol
- [ma-standard-actors-v1.md](ma-standard-actors-v1.md) — the reserved `#root` and `#scheduler` actors
