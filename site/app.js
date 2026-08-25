const root = document.documentElement;
const themeButton = document.querySelector("[data-theme-toggle]");
const colorPreference = window.matchMedia("(prefers-color-scheme: dark)");
const requestedLanguage = new URLSearchParams(window.location.search).get("lang")?.toLowerCase();

if ((requestedLanguage === "zh" || requestedLanguage === "zh-cn") && root.lang === "en") {
  const target = new URL("zh-CN/", window.location.href);
  target.search = "";
  window.location.replace(target);
}

if (requestedLanguage === "en" && root.lang.toLowerCase() === "zh-cn") {
  const target = new URL("../", window.location.href);
  target.search = "";
  window.location.replace(target);
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

  themeButton.textContent = labels[nextTheme];
  themeButton.setAttribute(
    "aria-label",
    isChinese ? `切换到${labels[nextTheme]}模式` : `Switch to ${labels[nextTheme].toLowerCase()} mode`
  );
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
