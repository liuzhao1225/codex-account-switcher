import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const script = fs.readFileSync(path.join(root, "site/app.js"), "utf8");
function pages(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? pages(file) : entry.name === "index.html" ? [file] : [];
  });
}
function redirect(html, query) {
  const canonical = html.match(/rel="canonical" href="([^"]+)"/)[1];
  const location = new URL(`${canonical}${query}`);
  const language = html.match(/<html lang="([^"]+)"/)[1];
  let destination;
  vm.runInNewContext(script, {
    URL, URLSearchParams,
    document: {
      documentElement: { lang: language, dataset: {} },
      querySelector(selector) {
        const target = selector.match(/hreflang="([^"]+)"/)?.[1];
        const href = target && html.match(new RegExp(`rel="alternate" hreflang="${target}" href="([^"]+)"`))?.[1];
        return href ? { href } : null;
      },
    },
    window: {
      location: { href: location.href, search: location.search, hash: location.hash, replace: url => { destination = String(url); } },
      matchMedia: () => ({ matches: false, addEventListener() {} }),
    },
    localStorage: { getItem: () => null },
  });
  return destination;
}

test("legacy language links use each page's real translated URL, preserving query and fragment", () => {
  for (const file of pages(path.join(root, "site"))) {
    const html = fs.readFileSync(file, "utf8");
    const chinese = html.includes('<html lang="zh-CN">');
    const target = chinese ? "en" : "zh-CN";
    const alternate = html.match(new RegExp(`rel="alternate" hreflang="${target}" href="([^"]+)"`))[1];
    for (const queryLanguage of chinese ? ["en", "EN"] : ["zh", "zh-cn", "zh-CN"]) {
      assert.equal(redirect(html, `?lang=${queryLanguage}&utm_source=guide#main`), `${alternate}?utm_source=guide#main`, file);
    }
  }
});

test("same-language, missing and unsupported language parameters do not redirect", () => {
  for (const file of pages(path.join(root, "site"))) {
    const html = fs.readFileSync(file, "utf8");
    const current = html.includes('<html lang="zh-CN">') ? "zh" : "en";
    for (const query of ["", "?lang=fr", `?lang=${current}`]) assert.equal(redirect(html, query), undefined, file);
  }
});
