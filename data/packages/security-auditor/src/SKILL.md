# security-auditor

Automated security code review skill for AI coding agents.

## Overview

This skill runs a security-focused review pass over code the agent writes or modifies. It checks for:

- Exposed API keys, credentials, and secrets in source code
- Missing authentication and authorization checks
- Broken access control (Supabase RLS, Firebase rules, etc.)
- Client-side trust issues (accepting data from client without server-side validation)
- Insecure payment flows and financial data handling
- Missing input validation and sanitization
- SQL injection, XSS, CSRF vectors
- Insecure session handling and cookie configuration
- Missing rate limiting and brute-force protection

## Usage

Invoke automatically or with `/security-auditor` in supported agents.

Run proactively: any time you are writing or reviewing code that handles auth, payments,
database access, API keys, secrets, or user data — even if security is not explicitly mentioned.

## Review Checklist

1. **Secrets**: No API keys, passwords, tokens in source — use env vars or secret manager
2. **Auth**: Every protected endpoint has auth; JWT validated server-side; sessions HttpOnly
3. **Access Control**: Server-side checks on every mutation; no client-enforced permissions
4. **Input Validation**: Validate and sanitize all external input; parameterized queries only
5. **Data Handling**: Sensitive data encrypted at rest and in transit; PII minimization
6. **Dependencies**: No known CVEs; pinned versions; minimal dependency surface
7. **Error Handling**: No stack traces or internal details leaked to clients
8. **Rate Limiting**: Bruteforce and abuse vectors mitigated

## Output Format

For each finding:
- **Severity**: Critical / High / Medium / Low
- **Location**: file:line or component
- **Issue**: What is wrong
- **Fix**: Concrete code-level remediation
