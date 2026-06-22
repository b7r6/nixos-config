// Minimal fetch wrapper for the queue endpoint. Returns a Promise<string>
// (the response body text) or rejects; the PS side parses + classifies.
export const postQueueImpl = (endpoint) => (token) => (url) => () => {
	const headers = { "Content-Type": "application/json" };
	if (token) headers["Authorization"] = "Bearer " + token;
	return fetch(endpoint, {
		method: "POST",
		headers,
		body: JSON.stringify({ url }),
	}).then((res) =>
		res.text().then((body) => {
			if (!res.ok) throw new Error("HTTP " + res.status + ": " + body);
			return body;
		}),
	);
};
