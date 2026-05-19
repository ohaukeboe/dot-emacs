# Role Selection Guide

Use this to decide which roles to spawn for a given task. Not every role is needed every time. Over-staffing wastes context budget; under-staffing leaves gaps.

## Quick heuristic

| Task involves... | Spawn |
|---|---|
| Web UI / browser features | Frontend Developer |
| REST/GraphQL APIs, databases, auth | Backend Architect |
| iOS / Android / React Native / Flutter | Mobile App Builder |
| Auth, secrets, user data, payments, compliance | Security Engineer |
| UI that needs visual proof | Evidence Collector |
| Multi-layer feature going to production | Reality Checker |
| Public-facing APIs / third-party integrations | API Tester |

## Minimum viable roster

- **Frontend-only feature** (e.g. UI polish, new component): Frontend Developer + Evidence Collector
- **Backend-only feature** (e.g. new API endpoint, DB migration): Backend Architect + API Tester
- **Full-stack feature** (e.g. new user flow end to end): Frontend Developer + Backend Architect + Evidence Collector + Reality Checker
- **Security-sensitive work** (auth, payments, PII): add Security Engineer to any of the above
- **Mobile feature**: replace or supplement Frontend Developer with Mobile App Builder
- **Anything going to production**: add Reality Checker

## When to add Security Engineer

Always add Security Engineer when the slice touches:
- Authentication or authorisation logic
- Passwords, tokens, API keys, or secrets
- Payment processing or financial data
- Personally identifiable information (PII)
- File uploads or user-supplied file paths
- External API integrations that handle credentials

## When to add API Tester

Add API Tester when:
- A new public-facing API endpoint is being built
- Third-party integrations are involved
- Performance SLAs on API response times are contractual
- The backend architect's tests only cover happy paths

## When NOT to spawn

- **Reality Checker**: skip for tiny isolated fixes not going to production soon
- **Evidence Collector**: skip for purely backend/API-only work (no UI)
- **API Tester**: skip if Backend Architect's tests already cover contract + security + performance

## Confirming the roster

After selecting roles, present the list to the user:

```
Proposed team for this task:
  ✦ Frontend Developer — [reason]
  ✦ Backend Architect — [reason]
  ✦ Evidence Collector — [reason]
  ✦ Reality Checker — [reason]

Any roles to add or remove?
```

User confirms before you spawn anyone.
