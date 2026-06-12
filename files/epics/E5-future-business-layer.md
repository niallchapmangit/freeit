# E5 — Future Business Layer  · PARKED

- **Phase:** 5 — Business layer
- **Status:** PARKED (deferred until the business is real; single-tenant removes the need for now)
- **Depends on:** a real business case

## Goal
The layer that turns the demo into a product for SMBs.

## Scope (deferred)
- Tenant control plane.
- Billing & metering.
- Admin / management console.
- Customer docs & branding/theming.

## Tension to keep in your back pocket
Strict single-tenant and "cheap" pull against each other at scale. k3s-per-company is the cheap
end of *true* isolation; namespace-per-company is cheaper but less isolated. The demo doesn't
care; the business will.

## Definition of Done
- [ ] Revisit only when a real customer/business case exists.
