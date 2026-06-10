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
