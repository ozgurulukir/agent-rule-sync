---
name: golang-security
description: Audit Go code for security vulnerabilities: exposed secrets, broken access control, missing auth validation, insecure payment flows, and client-side trust issues. Use when reviewing Go code for security or when user asks about security best practices.
---

# Golang Security Skill

Audit Go codebases for common security vulnerabilities.

## Checks

- **Secrets exposure**: Hardcoded API keys, tokens, credentials
- **Access control**: Broken RLS, missing auth middleware, unauthorized access
- **Input validation**: Missing sanitization, SQL injection, XSS vectors
- **Authentication**: Weak session management, missing 2FA, insecure password storage
- **Payment security**: Card data handling, insecure webhook verification
- **Client trust**: Over-reliance on client-side validation

## Usage

Trigger when:
- User asks about "security" or "vulnerabilities" in Go code
- Requesting security audit or code review
- Handling auth, payments, or user data
- Mentions "secure coding" or "OWASP"

## References

See `references/` directory for detailed checklists and examples.
