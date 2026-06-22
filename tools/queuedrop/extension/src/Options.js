// Tiny DOM helpers for the options page (avoids pulling web-dom deps for v0).
export const getValueImpl = (id) => () => {
	const el = document.getElementById(id);
	return el ? el.value : "";
};

export const setValueImpl = (id) => (val) => () => {
	const el = document.getElementById(id);
	if (el) el.value = val;
};

export const setTextImpl = (id) => (txt) => () => {
	const el = document.getElementById(id);
	if (el) el.textContent = txt;
};

export const onClickImpl = (id) => (handler) => () => {
	const el = document.getElementById(id);
	if (el) el.addEventListener("click", () => handler());
};
