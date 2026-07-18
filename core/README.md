# core — recommended interop conventions

These documents define the *conventions layer* of the ma specifications:
service protocols, message types, DID document field extensions,
and the access-control model.

## Are these required?

**No — not for using `did:ma` as a DID.** The identity layer
([did-ma-spec-v1.md](../did-ma-spec-v1.md)) and the message envelope
([ma-messaging-format-v1.md](ma-messaging-format-v1.md)) stand on their
own. You can mint DIDs, publish DID documents, and exchange signed
messages without implementing anything else in this directory.

**Yes — for talking to a runtime.** A conforming
[ma-runtime](../runtime/README.md) advertises and expects these services
and message types. Any client or peer that wants to interoperate with a
runtime — or with other ma implementations in general — must implement
the relevant specs here.

The message types (chat, emote) are *recommended standards*: if your
application sends chat or emote messages, use these message types so
other implementations can render them.

## Documents

| Document | Defines |
|---|---|
| [ma-messaging-format-v1.md](ma-messaging-format-v1.md) | Signed CBOR message envelope, base message types, encryption, replay protection. The foundational wire contract. |
| [ma-did-ma-fields-v1.md](ma-did-ma-fields-v1.md) | The `ma` key in DID documents: `ma.services` reachability, `ma.kind` hint, service protocol ids. |
| [ma-rpc-service-v1.md](ma-rpc-service-v1.md) | `/ma/rpc/0.0.1` — request/reply RPC with CBOR terms (atoms, tuples). |
| [ma-inbox-service-v1.md](ma-inbox-service-v1.md) | `/ma/inbox/0.0.1` — durable message delivery, TTL/expiry, reply correlation. |
| [ma-ipfs-service-v1.md](ma-ipfs-service-v1.md) | `/ma/ipfs/0.0.1` — delegated IPFS/IPNS publishing of DID documents. |
| [ma-chat-messages-v1.md](ma-chat-messages-v1.md) | `application/vnd.ma.chat` — ephemeral real-time chat (IRC *say*). |
| [ma-emote-messages-v1.md](ma-emote-messages-v1.md) | `application/vnd.ma.emote` — third-person action text (IRC */me*). |
| [ma-acl-v1.md](ma-acl-v1.md) | Capability-based ACL model with deny-wins semantics, shared by all services. |

## Intended audience

- **Client developers** building anything that talks to ma actors:
  implement the services and message types you need. Start with the
  messaging format, then the inbox and RPC services.
- **Runtime developers** implementing an actor framework: all of these
  are prerequisites — see [runtime/](../runtime/README.md).
- **Not for end users.** If you just want to *use* zion or zscheme, read
  the [zscheme handbook](https://github.com/bahner/ma-scheme) instead.
