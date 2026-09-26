const root = document.documentElement;
const themeButton = document.querySelector("[data-theme-toggle]");
const colorPreference = window.matchMedia("(prefers-color-scheme: dark)");
const requestedLanguage = new URLSearchParams(window.location.search).get("lang")?.toLowerCase();

const targetLanguage = requestedLanguage === "zh" || requestedLanguage === "zh-cn"
  ? "zh-CN" : requestedLanguage === "en" ? "en" : null;
if (targetLanguage && root.lang.toLowerCase() !== targetLanguage.toLowerCase()) {
  const alternate = document.querySelector(`link[rel="alternate"][hreflang="${targetLanguage}"]`);
  if (alternate) {
    const target = new URL(alternate.href);
    target.search = window.location.search;
    target.searchParams.delete("lang");
    target.hash = window.location.hash;
    window.location.replace(target);
  }
}

function currentTheme() {
  const savedTheme = root.dataset.theme;
  if (savedTheme === "light" || savedTheme === "dark") {
    return savedTheme;
  }
  return colorPreference.matches ? "dark" : "light";
}

function updateThemeLabel() {
  if (!themeButton) return;

  const nextTheme = currentTheme() === "dark" ? "light" : "dark";
  const isChinese = root.lang.toLowerCase() === "zh-cn";
  const labels = isChinese
    ? { light: "浅色", dark: "深色" }
    : { light: "Light", dark: "Dark" };

  const actionLabel = isChinese
    ? `切换到${labels[nextTheme]}模式`
    : `Switch to ${labels[nextTheme].toLowerCase()} mode`;
  themeButton.dataset.nextTheme = nextTheme;
  themeButton.setAttribute("aria-label", actionLabel);
  themeButton.setAttribute("title", actionLabel);
}

const savedTheme = localStorage.getItem("site-theme");
if (savedTheme === "light" || savedTheme === "dark") {
  root.dataset.theme = savedTheme;
}

themeButton?.addEventListener("click", () => {
  const nextTheme = currentTheme() === "dark" ? "light" : "dark";
  root.dataset.theme = nextTheme;
  localStorage.setItem("site-theme", nextTheme);
  updateThemeLabel();
});

colorPreference.addEventListener("change", updateThemeLabel);
updateThemeLabel();
