# Backend Production Hardening Design

**Scope:** Harden the Node backend and production configuration for the upcoming beta without changing iOS behavior unless a backend change proves impossible to consume safely.

## Goals

- Close the current P0 risks around permissive CORS, missing security headers, unlimited cross-origin writes, and weak request controls.
- Make production configuration explicit and parameterized instead of relying on insecure compose defaults.
- Improve deployment confidence with safer health checks, read-only verification, and a production Nginx template.

## Approach

- Keep the existing single-process Node architecture for now.
- Avoid new npm dependencies so the hardening can be deployed quickly with minimal operational risk.
- Add small internal middleware for security headers, origin checks, rate limiting, request-size handling, and trusted health metadata.
- Add production-facing config examples and Nginx guidance in-repo so the deployed server can match the application hardening.

## Backend Changes

- Disable `x-powered-by`.
- Replace wildcard CORS with a configurable origin allowlist.
- Add baseline security headers at the application layer.
- Add in-memory rate limiting for the highest-risk write/auth endpoints.
- Make JSON body limit configurable and lower by default for production use.
- Return clear JSON errors for oversized uploads, oversized JSON payloads, and throttled clients.
- Expand `/v1/health` to expose only non-sensitive operational metadata.

## Production Config Changes

- Add a production env example for required secrets and hardening knobs.
- Parameterize compose defaults where safe.
- Add an Nginx config template covering TLS redirect behavior, security headers, body limits, timeouts, and caching for static media.
- Update launch and verification docs to distinguish read-only checks from mutating smoke tests.

## Risks

- In-memory rate limiting only protects a single process. This is acceptable for the current single-instance deployment, but not a long-term horizontal scaling solution.
- The current single-row JSONB persistence model remains a structural scaling limit. This work hardens the deployment but does not remove that architectural bottleneck.
- Tightening CORS requires the production allowed origins to be configured correctly before deploy.
