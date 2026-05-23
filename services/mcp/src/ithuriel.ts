// Thin client over the Ithuriel REST API. Owns auth + retry.
//
// Auth: a bearer token must be supplied per request (either via env
// `ITHURIEL_API_TOKEN` for local stdio mode, or extracted from the
// inbound `Authorization` header for the HTTP transport).

export interface Snapshot {
  id: string;
  userId: string;
  capturedAt: string;
  workspacePath?: string | null;
  gitBranch?: string | null;
  gitCommit?: string | null;
  activeFiles?: string[];
  summaryShort?: string | null;
  summaryMedium?: string | null;
  summaryFull?: string | null;
}

export interface AgentRun {
  id: string;
  userId: string;
  task: string;
  status: "running" | "completed" | "failed" | "killed";
  startedAt: string;
  finishedAt?: string | null;
  transcript: string[];
  error?: string | null;
}

export type InjectTarget =
  | "claude-code"
  | "claude-desktop"
  | "cursor"
  | "chatgpt"
  | "copilot-chat"
  | "gemini";

export class IthurielAPI {
  constructor(
    private readonly baseURL: string,
    private readonly token: string,
  ) {
    if (!baseURL) throw new Error("ITHURIEL_API_URL is required");
    if (!token) throw new Error("Ithuriel bearer token is required");
  }

  async currentContext(): Promise<Snapshot> {
    return this.get<Snapshot>("/v1/context/current");
  }

  async snapshot(id: string): Promise<Snapshot> {
    return this.get<Snapshot>(`/v1/context/${encodeURIComponent(id)}`);
  }

  async history(limit = 25): Promise<{ items: Snapshot[]; nextCursor?: string }> {
    return this.get(`/v1/context/history?limit=${limit}`);
  }

  async formatForTarget(target: InjectTarget, snapshotId?: string): Promise<{ target: string; payload: string }> {
    return this.post("/v1/context/inject", { target, snapshotId });
  }

  async agentRuns(limit = 25): Promise<{ items: AgentRun[] }> {
    return this.get(`/v1/agent/runs?limit=${limit}`);
  }

  // ---- internals ----

  private async get<T>(path: string): Promise<T> {
    return this.request<T>("GET", path);
  }

  private async post<T>(path: string, body: unknown): Promise<T> {
    return this.request<T>("POST", path, body);
  }

  private async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const url = new URL(path, this.baseURL).toString();
    const res = await fetch(url, {
      method,
      headers: {
        Authorization: `Bearer ${this.token}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`Ithuriel API ${method} ${path} → ${res.status}: ${text.slice(0, 300)}`);
    }
    return (await res.json()) as T;
  }
}
