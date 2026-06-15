const API_BASE_URL = import.meta.env.VITE_API_URL || "";

const getAuthToken = () => localStorage.getItem("odisea_token");

export async function apiFetch(endpoint: string, options: RequestInit = {}) {
  const token = getAuthToken();
  const headers = {
    ...options.headers,
    "Authorization": `Bearer ${token}`,
  };

  const url = `${API_BASE_URL}${endpoint}`;
  const response = await fetch(url, { ...options, headers });

  if (response.status === 401) {
    localStorage.removeItem("odisea_token");
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
  const response = await apiFetch("/health");
  return response.json();
}

export async function getWebTelemetry() {
  const response = await apiFetch("/telemetry/web?limit=300");
  return response.json();
}

export async function getGhosts(scene?: string, platform?: string, since?: number) {
  let url = "/ghosts?";
  if (scene) url += `scene=${scene}&`;
  if (platform) url += `platform=${platform}&`;
  if (since) url += `since=${since}&`;
  const response = await apiFetch(url);
  const json = await response.json();
  return Array.isArray(json) ? json : (json.data || []);
}

export async function getHeatmap(scene: string, resolution: number = 5) {
  const response = await apiFetch(`/ghosts/heatmap?scene=${scene}&resolution=${resolution}`);
  return response.json();
}

export async function getHistoricalSessions() {
  const response = await apiFetch("/ghosts/sessions");
  return response.json();
}

export async function getActiveGhosts() {
  const response = await apiFetch("/ghosts/active");
  return response.json();
}

export async function getGhostStats() {
  const response = await apiFetch("/ghosts/stats");
  const json = await response.json();
  // Return headline part for backward compatibility if needed,
  // or the whole object if the dashboard expects it.
  return json.headline || json;
}

export async function getGeoPlayers() {
  const response = await apiFetch("/api/geo-players");
  const json = await response.json();
  return Array.isArray(json) ? json : [];
}

export async function getGhostData(playerId: string, sessionId: string) {
  const response = await apiFetch(`/ghosts?player_id=${playerId}&session_id=${sessionId}&limit=10000`);
  const json = await response.json();
  return Array.isArray(json) ? json : (json.data || []);
}

export async function getScenes(): Promise<string[]> {
  const response = await apiFetch("/scenes");
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

export async function getVapidKey() {
  const response = await apiFetch("/push/key");
  return response.json();
}

export async function subscribePush(subscription: any, settings: any = {}) {
  const response = await apiFetch("/push/subscribe", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      subscription,
      player_id: "admin",
      settings,
    }),
  });
  return response.json();
}

export async function sendPush(payload: any) {
  const response = await apiFetch("/push/send", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  return response.json();
}

// Player tag endpoints
export async function getPlayerTags() {
  const response = await apiFetch("/api/player-tags");
  return response.json();
}

export async function postPlayerTag(tag: { player_id: string; display_name: string; notes?: string; color?: string }) {
  const response = await apiFetch("/api/player-tags", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(tag),
  });
  return response.json();
}

export async function deletePlayerTag(playerId: string) {
  const response = await apiFetch(`/api/player-tags/${encodeURIComponent(playerId)}`, {
    method: "DELETE",
  });
  return response.json();
}

// List hotzone ghosts (most recent first).
export async function getHotzones() {
  const response = await apiFetch("/hotzones");
  return response.json();
}

// Get a signed download link for a hotzone (valid for 5 mins).
export async function getHotzoneDownloadLink(hotzoneId: string): Promise<{ url: string }> {
  const response = await apiFetch(`/hotzones/${encodeURIComponent(hotzoneId)}/dl-link`);
  return response.json();
}

// Download a hotzone ghost binary as an authenticated blob and save it. The
// endpoint needs the Bearer token, so a plain <a download> link won't work.
export async function downloadHotzone(hotzoneId: string, suggestedName?: string) {
  const response = await apiFetch(`/hotzones/${encodeURIComponent(hotzoneId)}/download`);
  if (!response.ok) throw new Error(`download failed (${response.status})`);
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `${suggestedName ? `${suggestedName}-` : ""}hotzone-${hotzoneId.slice(0, 8)}.bin`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

// Delete a hotzone ghost (DB row + backing blob) on the central server.
export async function deleteHotzone(hotzoneId: string) {
  const response = await apiFetch(`/hotzones/${encodeURIComponent(hotzoneId)}`, {
    method: "DELETE",
  });
  if (!response.ok) throw new Error(`delete failed (${response.status})`);
  return response.json();
}
