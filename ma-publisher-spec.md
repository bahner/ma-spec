# ma-publisher spec (draft)

## Goal

A stateless `did:ma` publication service that can be operated as an actor over iroh.

Core requirements:

- stateless publication pipeline
- valid `did:ma` document checks before publication
- signed requests
- ACL managed by owner at runtime using normal MA actor commands

## Decision: separate service, actor interface

`ma-publisher` should be a distinct service, not built into `ma-world`.

Why:

- clean blast radius (publisher compromise is separate from world runtime)
- independent scaling and deployment lifecycle
- can still speak normal MA actor protocol over iroh
- can use Kubo colocated with service host

`ma-world` integration can be optional later via delegation, but default should stay separate.

## Transport and model

`ma-publisher` runs as an actor endpoint on iroh, receives signed MA messages, and executes publication commands.

Startup minimal config:

- owner DID root (required)
- kubo API URL (default local)
- iroh secret path
- optional ACL bootstrap text

No persistent DB required.

## ACL model

ACL text syntax (same semantics as requested):

- `*` everyone allowed
- `!did:ma:bully` explicit deny
- `did:ma:bahner` explicit allow

Rules:

- deny takes precedence over allow
- if wildcard `*` exists: default allow unless denied
- without wildcard: default deny, only explicit allows pass

Examples:

Public with one deny:

```txt
*
!did:ma:bully
```

Private:

```txt
did:ma:bahner
did:ma:bahner#thecooldude
```

For principal matching, evaluate against DID root first (`did:ma:<id>`), then optional fragment exact match when present.

## Command surface (actor commands)

Admin/owner commands:

- `@publisher acl show`
- `@publisher acl set <text>`
- `@publisher acl add <rule>`
- `@publisher acl rm <rule>`
- `@publisher owner set <did>`

Publish commands:

- `@publisher did prepare <json-bytes-base64>`
- `@publisher did publish <json-bytes-base64> <signed-intent-base64> <ipns-private-key-base64> [key-name]`

## Stateless signed flow

### Prepare (no mutation)

- validates JSON is a valid `did:ma` document
- computes deterministic content CID
- returns CID + canonical document hash
- does not add to IPFS, does not publish to IPNS

### Publish (mutation)

Input includes:

- same document bytes
- signed intent containing: operation, cid, requester DID, expiry, audience
- IPNS private key bytes (base64)

Service checks:

- requester DID signature is valid
- requester passes ACL
- document validates as `did:ma`
- recomputed CID equals signed CID
- intent not expired

Then:

- Kubo add document
- import key
- IPNS publish
- remove imported key (default true)

Idempotency:

- same CID to same IPNS target is semantically idempotent
- service remains stateless

## Security constraints

- require signed commands (no unsigned publish)
- small max document size
- strict timeout to Kubo calls
- scrub key material from logs
- optional external bearer auth in front proxy

## First implementation slices

1. keep existing HTTP microservice for local testing
2. add prepare endpoint with strict DID validation and deterministic CID
3. add signed publish intent verification
4. add actor transport wrapper over iroh using MA protocol
5. add owner + ACL actor commands

This yields an actor-operated stateless publisher with minimal moving parts.
