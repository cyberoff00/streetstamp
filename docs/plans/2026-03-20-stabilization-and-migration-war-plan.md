# Stabilization And Migration War Plan

Date: 2026-03-20
Status: Draft
Owner: Codex

## Goal

Stabilize the current multi-track architecture and prepare a safe server migration without expanding product scope.

This plan treats the current work as one program with a single outcome:

- converge auth authority
- converge data ownership
- make server migration executable, verifiable, and reversible

## Non-Goals

- no new social features
- no new UI redesign work
- no expansion of CloudKit and backend dual-write behavior
- no direct lift-and-shift of the current backend as-is onto a new server

## Program Priorities

### 1. Converge Identity And Auth

Target state:

- business APIs accept backend-issued tokens as the only primary auth credential
- Firebase remains only as an explicit compatibility layer during migration
- client session restoration, refresh, logout, and reauthentication follow one main path

Why first:

- auth ambiguity blocks safe migration verification
- auth ambiguity amplifies rollback complexity
- auth ambiguity makes data migration defects harder to diagnose

### 2. Converge Data Ownership And Persistence

Target state:

- PostgreSQL becomes the real source of truth for core backend entities
- JSON blob persistence is retired from the steady state
- high-risk APIs stop accepting client-owned full business snapshots without strict server ownership rules

Why second:

- migration safety depends on stable server-owned data
- the current persistence model already caused data isolation incidents
- the current model is not suitable for multi-user concurrent operation

### 3. Build Migration Safety Rails

Target state:

- new environment is reproducible
- backups and restore are rehearsed
- cutover is performed in a write-freeze window
- rollback is explicit and tested
- production release gates are defined before cutover

Why third:

- migration is an operational event, not just a code deploy
- without safety rails the team cannot tell whether cutover succeeded

## Workstreams

### Backend Engineer A

Focus:

- auth convergence
- persistence convergence
- API ownership hardening

Deliverables:

- backend auth convergence design
- target relational data model and migration mapping
- high-risk API hardening list

Definition of done:

- target auth authority is documented
- target core tables are agreed
- deprecated and compatibility API paths are listed

### Backend Engineer B

Focus:

- migration execution model
- deployment reproducibility
- import/export and rollback design

Deliverables:

- migration runbook
- environment baseline
- backup and restore procedure

Definition of done:

- new environment topology is documented
- backup scope is explicit
- cutover and rollback steps are explicit

### Frontend / iOS Engineer

Focus:

- single client auth path
- source-of-truth matrix
- user-scope and rollback safety

Deliverables:

- client auth/session state machine
- data ownership matrix
- environment switching and high-risk feature flags

Definition of done:

- all token read/refresh paths are inventoried
- user-scope boundaries are inventoried
- migration-era client behavior is explicit

### SRE / Ops

Focus:

- environment baseline
- monitoring and alerts
- write freeze and cutover window

Deliverables:

- new environment baseline
- monitoring minimum set
- migration execution window and rollback criteria

Definition of done:

- infrastructure prerequisites are listed
- minimum monitoring exists on paper before cutover
- freeze/cutover/rollback timeline is explicit

### QA

Focus:

- auth regression
- data isolation validation
- migration and rollback acceptance

Deliverables:

- auth regression matrix
- data consistency and ownership checks
- migration smoke and rollback smoke checklist

Definition of done:

- production gates are explicit
- migration cannot proceed without passing them

### Product Manager

Focus:

- feature freeze
- decision cadence
- migration communication

Deliverables:

- freeze scope
- two-week stabilization objective
- migration window communication draft

Definition of done:

- non-stabilization work is paused
- go/no-go criteria are explicit

## Sequence

### Phase 1: Design Freeze

- finish auth convergence design
- finish target data model and migration mapping
- finish migration runbook and release gates

Exit criteria:

- all three documents reviewed
- no new feature work enters scope

### Phase 2: Implementation

- backend implements auth convergence and persistence cutover path
- client implements single-path auth/session behavior and migration flags
- ops prepares new environment and restore rehearsal
- QA builds regression and migration gates

Exit criteria:

- cutover candidate is deployable in a staging-like environment
- backup/restore rehearsal has been run

### Phase 3: Migration Readiness

- execute final dry run
- verify write freeze mechanics
- verify import/export and data checks
- verify rollback path

Exit criteria:

- go/no-go review passed

### Phase 4: Production Cutover

- enter write freeze
- perform final backup
- import and verify
- cut traffic
- observe
- either confirm steady state or execute rollback

## Immediate Outputs

This plan depends on the following companion documents:

- `docs/plans/2026-03-20-backend-auth-and-storage-convergence.md`
- `docs/ops/2026-03-20-server-migration-runbook.md`
- `docs/ops/2026-03-20-migration-acceptance-gates.md`

## Current Stop List

Do not start these before the stabilization program is through design freeze:

- new social features
- new navigation or UI revamps
- new sync surfaces that add more multi-writer behavior
- direct server migration of the current backend without auth and persistence convergence
