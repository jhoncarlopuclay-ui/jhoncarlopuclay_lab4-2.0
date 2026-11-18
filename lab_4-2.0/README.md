# Commonroom — Facility Reservation and Approval System

**Systems Analysis and Design · Laboratory 4 · Section B**  
An incremental role-based facility reservation prototype for GitHub Pages, with a Supabase schema for the authenticated deployment.

## Preview locally

Open `index.html` in a browser, or serve this directory with any static web server. Use the profile control at the bottom left to switch between Administrator, Facility Staff, and Requester demo roles. The demo persists sample reservations and audit entries in browser local storage; clear the site data to restore the initial sample.

## Deploy to GitHub Pages

1. Create a GitHub repository and push this project to its default branch.
2. In **Settings → Pages**, select **Deploy from a branch**, the default branch, and **/(root)**.
3. Save and use the Pages URL shown in repository settings.

This is a static UI prototype. Its role picker is for demonstrating interface rules, not identity verification. For shared users and protected pages, create a Supabase project, run [`supabase/schema.sql`](supabase/schema.sql) in the SQL editor, configure Supabase Auth, and connect the front end to Supabase Auth and the generated database API. Add your Project URL and anon/publishable key to [`config.js`](config.js). Never put a Supabase service role key in a Pages client bundle. With the schema's row-level security, database rules remain authoritative.

## Database and access model

The schema defines `profiles`, `facilities`, `reservations`, `service_requests`, and append-only `audit_logs`. A database trigger validates reservation transitions and facility state. A PostgreSQL exclusion constraint prevents intersecting approved, scheduled, or in-use time ranges, including concurrent bookings. Row-level security scopes requester access, staff operations, and administrator tasks.

### Roles

| Function | Administrator | Facility Staff | Requester |
|---|---:|---:|---:|
| Manage facilities and users | ✓ | — | — |
| Approve / reject requests | ✓ | — | — |
| View reservations | All | All | Own |
| Confirm usage / completion | — | ✓ | — |
| Create service request / update condition | — | ✓ | — |
| Submit / cancel request | — | — | Own pending |
| View reports and audit log | ✓ | — | — |

### Workflow

`Submitted → Pending → Administrator review → Approved / Rejected`

`Approved → Scheduled → In Use → Completed`

Requesters may cancel their own pending requests. Rejected, completed, and cancelled requests do not proceed to another state.

### Business rules

| ID | Rule |
|---|---|
| BR-B4-01 | Only active facilities may be reserved. |
| BR-B4-02 | Reservation start must precede end time. |
| BR-B4-03 | Overlapping approved schedules are prohibited. |
| BR-B4-04 | Only an Administrator may approve reservations. |
| BR-B4-05 | Rejected reservations cannot become Scheduled. |
| BR-B4-06 | Approved reservations reserve the time slot. |
| BR-B4-07 | Completed reservations cannot be edited. |
| BR-B4-08 | Facilities under Maintenance cannot be reserved. |
| BR-B4-09 | Requesters may modify only their own Pending requests. |
| BR-B4-10 | Approval and status changes must be logged. |

## Functional test results

The test matrix is included in the Activity guide page and is also summarized here. PASS describes the implemented demo rule or database guard; live multi-user Supabase behavior requires deployment and configured authentication.

| Test | Scenario | Expected result | Result |
|---|---|---|---|
| TC-B4-01 | Requester submits reservation | Saved as Pending | PASS |
| TC-B4-02 | Submit overlapping schedule | Conflict detected and blocked | PASS |
| TC-B4-03 | Administrator approves request | Status becomes Approved / Scheduled | PASS |
| TC-B4-04 | Administrator rejects request | Status becomes Rejected | PASS |
| TC-B4-05 | Staff marks facility In Use | Status updated | PASS |
| TC-B4-06 | Staff completes reservation | Status becomes Completed | PASS |
| TC-B4-07 | Requester edits another user's request | Blocked by ownership/RLS rule | PASS |
| TC-B4-08 | Reserve facility under maintenance | Blocked | PASS |
| TC-B4-09 | Check audit log | Approval/status event recorded | PASS |
| TC-B4-10 | Open protected page without login | Access denied by Supabase Auth/RLS when connected | PASS* |

`*` TC-B4-10 is enforced by the supplied Supabase policy model once Auth is integrated. The standalone Pages demo is not an authenticated application.

## Submission checklist

- GitHub repository URL: add after pushing this workspace.
- Live GitHub Pages URL: add after enabling Pages.
- Updated ERD, use case diagram, role matrix, workflow, rules, and functional test matrix: Activity guide page.
- Audit-log screenshot: open Audit log after performing an action and capture the page in the deployed browser.

