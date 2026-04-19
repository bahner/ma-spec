# MA Identity System Tree (間)
**Status:** Experimental (Non-normative)  
**Version:** 0.1.1  
**Author:** <your-name-or-github-handle>

## 1. Terminology

The term “MA” is derived from 間 (ma), meaning interval or relational space.

This reflects a design focus on interactions between identities rather than internal structure.

---

## 2. Purpose

This document defines the minimal system-level metadata required for safe and portable management of ids under an MA identity.

---

## 3. Core model

Every MA identity MUST expose a non-messageable `system` tree.

---

## 4. Structure

system.version — MUST  
system.ids — MUST  

system.ids.<id> — MUST exist for every managed id

---

## 5. Per-id metadata

Required:

- acl  
- owner  
- allowed_effects  

Optional:

- public_cid  
- state_cid  

---

## 6. CID handling

CIDs MUST be treated as first-class values.

### 6.1 Opaque content

Content referenced by `public_cid` or `state_cid` MAY contain code, data, or any other payload.

The MA system layer treats this content as opaque.

It MUST NOT require parsing, validation, or interpretation.

---

## 7. Execution model

Execution of CID-backed content is outside the scope of this specification.

### 7.1 Sandbox responsibility

If content is executed, sandboxing and isolation are the responsibility of the host implementation.

---

## 8. Policy responsibility

ACLs and effect restrictions are enforced by the runtime, but their meaning is defined by the implementation.

The MA system layer does not define or validate policy semantics.

---

## 9. Deletion model

Removal from `system.ids` means the id no longer exists.

No history, audit, or tombstones are required.

---

## 10. Compliance

This layer does not handle GDPR, audit, or retention.

---

## 11. Conformance

Implementation MUST:

- expose system tree  
- include required fields  
- treat CID as opaque  
- not require audit/history