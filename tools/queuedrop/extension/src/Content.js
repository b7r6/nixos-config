// Injects a small floating "Queue" button into the page. On click it asks the
// background SW to queue the current page URL (content scripts can't always
// reach arbitrary hosts due to page CSP, so we delegate to the SW via runtime).
import browser from "webextension-polyfill";

export const injectButtonImpl = (label) => () => {
	if (document.getElementById("queuedrop-btn")) return;
	const btn = document.createElement("button");
	btn.id = "queuedrop-btn";
	btn.textContent = label;
	Object.assign(btn.style, {
		position: "fixed",
		bottom: "16px",
		right: "16px",
		zIndex: "2147483647",
		padding: "8px 12px",
		background: "#1f1f1f",
		color: "#fff",
		border: "1px solid #444",
		borderRadius: "8px",
		font: "13px system-ui, sans-serif",
		cursor: "pointer",
		opacity: "0.85",
	});
	btn.addEventListener("click", () => {
		btn.textContent = "Queuing…";
		browser.runtime
			.sendMessage({ kind: "queue", url: window.location.href })
			.then((resp) => {
				btn.textContent = resp && resp.ok ? "Queued ✓" : "Failed ✗";
				setTimeout(() => (btn.textContent = label), 2000);
			})
			.catch(() => {
				btn.textContent = "Failed ✗";
				setTimeout(() => (btn.textContent = label), 2000);
			});
	});
	document.body.appendChild(btn);
};
