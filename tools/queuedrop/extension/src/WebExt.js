// FFI for the slice of the WebExtension API queuedrop needs. Uses the
// `webextension-polyfill` global (`browser`) so the same code runs on
// Chromium MV3 and Firefox. esbuild injects the polyfill (see build).
import browser from "webextension-polyfill";

// ── runtime / messaging ──────────────────────────────────────────────────
export const onMessageImpl = (handler) => () => {
	browser.runtime.onMessage.addListener((msg) => {
		// handler returns an Aff-like (Effect (Promise))? We keep it simple:
		// handler :: Foreign -> Effect (Promise Foreign). Return the promise.
		return handler(msg)();
	});
};

export const sendMessageImpl = (msg) => () => browser.runtime.sendMessage(msg);

// Listen for {kind:"queue", url} messages from content scripts. `handler` is
// PS: String -> Effect (Promise Boolean). We reply with {ok} so the content
// button can show success/fail.
export const onQueueMessageImpl = (handler) => () => {
	browser.runtime.onMessage.addListener((msg) => {
		if (msg && msg.kind === "queue" && typeof msg.url === "string") {
			return handler(msg.url)().then((ok) => ({ ok }));
		}
		return undefined; // not ours; let other listeners handle
	});
};

// ── active tab url ─────────────────────────────────────────────────────────
export const queryActiveTabUrlImpl = (nothing) => (just) => () =>
	browser.tabs.query({ active: true, currentWindow: true }).then((tabs) => {
		const u = tabs && tabs[0] && tabs[0].url;
		return u ? just(u) : nothing;
	});

// ── badge feedback on the toolbar action ───────────────────────────────────
export const setBadgeImpl = (text) => (color) => () => {
	const action = browser.action || browser.browserAction;
	if (!action) return Promise.resolve({});
	return Promise.resolve()
		.then(() => action.setBadgeBackgroundColor({ color }))
		.then(() => action.setBadgeText({ text }));
};

// ── context menu ───────────────────────────────────────────────────────────
export const createContextMenuImpl = (id) => (title) => (contexts) => () => {
	// remove-then-create to avoid duplicate-id errors on SW restart
	return Promise.resolve()
		.then(() => browser.contextMenus.removeAll())
		.then(() => browser.contextMenus.create({ id, title, contexts }));
};

export const onContextMenuClickedImpl = (handler) => () => {
	browser.contextMenus.onClicked.addListener((info, _tab) => {
		const url = info.linkUrl || info.pageUrl || (info.srcUrl ?? "");
		handler(url)();
	});
};

export const onActionClickedImpl = (handler) => () => {
	const action = browser.action || browser.browserAction;
	action.onClicked.addListener((_tab) => handler()());
};

// ── storage (options) ──────────────────────────────────────────────────────
export const storageGetImpl = (key) => (nothing) => (just) => () =>
	browser.storage.sync.get(key).then((obj) => {
		const v = obj && obj[key];
		return v === undefined || v === null ? nothing : just(v);
	});

export const storageSetImpl = (key) => (value) => () =>
	browser.storage.sync.set({ [key]: value });

// ── notifications (best-effort) ─────────────────────────────────────────────
export const notifyImpl = (title) => (message) => () => {
	if (!browser.notifications) return Promise.resolve("");
	return browser.notifications.create({
		type: "basic",
		iconUrl: browser.runtime.getURL("icon-128.png"),
		title,
		message,
	});
};
