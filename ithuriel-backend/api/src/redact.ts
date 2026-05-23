/**
 * Server-side redaction — mirrors macOS agent patterns for secrets in context.
 */
const PATTERNS: Array<{ name: string; pattern: RegExp; replacement: string }> = [
  {
    name: "aws_access_key",
    pattern: /\b(AKIA[0-9A-Z]{16})\b/g,
    replacement: "[REDACTED_AWS_KEY]",
  },
  {
    name: "aws_secret",
    pattern: /\b([A-Za-z0-9/+=]{40})\b(?=.*aws)/gi,
    replacement: "[REDACTED_AWS_SECRET]",
  },
  {
    name: "openai_key",
    pattern: /\bsk-[A-Za-z0-9]{20,}\b/g,
    replacement: "[REDACTED_OPENAI_KEY]",
  },
  {
    name: "github_token",
    pattern: /\b(ghp_[A-Za-z0-9]{36,})\b/g,
    replacement: "[REDACTED_GITHUB_TOKEN]",
  },
  {
    name: "github_oauth",
    pattern: /\b(gho_[A-Za-z0-9]{36,})\b/g,
    replacement: "[REDACTED_GITHUB_OAUTH]",
  },
  {
    name: "bearer_token",
    pattern: /\bBearer\s+[A-Za-z0-9\-._~+/]+=*/gi,
    replacement: "Bearer [REDACTED]",
  },
  {
    name: "jwt",
    pattern: /\beyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b/g,
    replacement: "[REDACTED_JWT]",
  },
  {
    name: "private_key",
    pattern: /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/g,
    replacement: "[REDACTED_PRIVATE_KEY]",
  },
  {
    name: "env_secret",
    pattern: /(?:password|secret|api[_-]?key|token|credential)\s*[=:]\s*['"]?[^\s'"]{8,}['"]?/gi,
    replacement: "[REDACTED_ENV_SECRET]",
  },
  {
    name: "generic_api_key",
    pattern: /\b(api[_-]?key|apikey)\s*[=:]\s*['"]?[A-Za-z0-9\-_]{16,}['"]?/gi,
    replacement: "[REDACTED_API_KEY]",
  },
  {
    name: "slack_token",
    pattern: /\bxox[baprs]-[A-Za-z0-9-]{10,}\b/g,
    replacement: "[REDACTED_SLACK_TOKEN]",
  },
  {
    name: "stripe_key",
    pattern: /\b(sk|pk)_(live|test)_[A-Za-z0-9]{20,}\b/g,
    replacement: "[REDACTED_STRIPE_KEY]",
  },
];

export function redactContent(input: string): string {
  let result = input;
  for (const { pattern, replacement } of PATTERNS) {
    result = result.replace(pattern, replacement);
  }
  return result;
}

export function redactSnapshotFields<T extends { rawContent?: string }>(
  body: T
): T {
  if (typeof body.rawContent === "string") {
    return { ...body, rawContent: redactContent(body.rawContent) };
  }
  return body;
}
