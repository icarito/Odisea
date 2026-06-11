const API_BASE_URL = import.meta.env.VITE_API_URL || "";

const getAuthToken = () => sessionStorage.getItem("odisea_token");

export async function apiFetch(endpoint: string, options: RequestInit = {}) {
  const token = getAuthToken();
  const headers = {
    ...options.headers,
    "Authorization": `Bearer ${token}`,
  };

  const url = `${API_BASE_URL}${endpoint}`;
  const response = await fetch(url, { ...options, headers });

  if (response.status === 401) {
    sessionStorage.removeItem("odisea_token");
    window.location.reload();
    throw new Error("Unauthorized");
  }

  return response;
}

export async function getStatus() {
  const response = await apiFetch("/status");
  return response.json();
}

export async function getHealth() {
  const response = await fetch("/health");
  return response.json();
}

export async function getWebTelemetry() {
  const response = await apiFetch("/telemetry/web?limit=300");
  return response.json();
}

export async function getGhosts(scene?: string, platform?: string, since?: number) {
  let url = "/api/ghosts?";
  if (scene) url += `scene=${scene}&`;
  if (platform) url += `platform=${platform}&`;
  if (since) url += `since=${since}&`;
  const response = await apiFetch(url);
  return response.json();
}

export async function getHeatmap(scene: string, resolution: number = 5) {
  const response = await apiFetch(`/api/ghosts/heatmap?scene=${scene}&resolution=${resolution}`);
  return response.json();
}

export async function getSessionHistory() {
  const response = await apiFetch("/sessions/history");
  return response.json();
}

export async function getHistoricalSessions() {
  const response = await apiFetch("/api/ghosts/sessions");
  return response.json();
}

export async function getActiveGhosts() {
  const response = await apiFetch("/api/ghosts/active");
  return response.json();
}

export async function getGhostData(playerId: string, sessionId: string) {
  const response = await apiFetch(`/api/ghosts?player_id=${playerId}&session_id=${sessionId}&limit=10000`);
  return response.json();
}

export async function getScenes(): Promise<string[]> {
  const response = await apiFetch("/api/scenes");
  return response.json();
}

export async function sendCommand(playerId: string, action: string, args: any = {}) {
  const response = await apiFetch("/command", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      player_id: playerId,
      action,
      args,
    }),
  });
  return response.json();
}
