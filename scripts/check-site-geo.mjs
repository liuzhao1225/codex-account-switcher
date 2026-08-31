import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const siteRoot = path.join(root, "site");
const baseURL = "https://liuzhao1225.github.io/codex-account-switcher/";
const llmsURL = `${baseURL}llms.txt`;
const latestDMGURL = "https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-macos-arm64.dmg";
const errors = [];

function fail(message) {
  errors.push(message);
}

function listHTML(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const target = path.join(directory, entry.name);
    return entry.isDirectory() ? listHTML(target) : entry.name === "index.html" ? [target] : [];
  });
}

function matchOne(html, expression, label, file) {
  const matches = [...html.matchAll(expression)];
  if (matches.length !== 1) {
    fail(`${file}: expected one ${label}, found ${matches.length}`);
    return "";
  }
  return matches[0][1]?.trim() ?? "";
}

function siteFileForURL(url) {
  if (!url.startsWith(baseURL)) return null;
  const relative = decodeURIComponent(url.slice(baseURL.length)).replace(/[?#].*$/, "");
  return path.join(siteRoot, relative, relative.endsWith("/") || relative === "" ? "index.html" : "");
}

function localTargetForHref(file, href) {
  const clean = href.split(/[?#]/, 1)[0];
  if (!clean || /^(?:https?:|mailto:|tel:|javascript:)/i.test(clean)) return null;
  const resolved = path.resolve(path.dirname(file), clean);
  return clean.endsWith("/") ? path.join(resolved, "index.html") : resolved;
}

for (const required of ["llms.txt", "sitemap.xml", "robots.txt"]) {
  if (!fs.existsSync(path.join(siteRoot, required))) fail(`site/${required}: missing required GEO file`);
}

const htmlFiles = listHTML(siteRoot).sort();
for (const file of htmlFiles) {
  const relative = path.relative(root, file);
  const html = fs.readFileSync(file, "utf8");
  const title = matchOne(html, /<title[^>]*>([\s\S]*?)<\/title>/gi, "title", relative);
  const description = matchOne(html, /<meta\s+name=["']description["']\s+content=["']([^"']+)["'][^>]*>/gi, "meta description", relative);
  const robots = matchOne(html, /<meta\s+name=["']robots["']\s+content=["']([^"']+)["'][^>]*>/gi, "robots meta", relative).toLowerCase();
  const canonical = matchOne(html, /<link\s+rel=["']canonical["']\s+href=["']([^"']+)["'][^>]*>/gi, "canonical", relative);
  const describedBy = matchOne(html, /<link\s+rel=["']describedby["']\s+href=["']([^"']+)["'][^>]*>/gi, "llms.txt describedby link", relative);
  const h1Count = [...html.matchAll(/<h1\b[^>]*>/gi)].length;

  if (!title) fail(`${relative}: empty title`);
  if (!description) fail(`${relative}: empty meta description`);
  if (!robots.includes("index") || !robots.includes("follow") || !robots.includes("max-snippet:-1")) {
    fail(`${relative}: robots meta must allow indexing, following, and unrestricted snippets`);
  }
  if (/noindex|nofollow|nosnippet|data-nosnippet/i.test(html)) fail(`${relative}: contains a blocking robots/snippet directive`);
  if (!canonical.startsWith(baseURL)) fail(`${relative}: canonical is outside the canonical project site`);
  if (describedBy !== llmsURL) fail(`${relative}: describedby must point to ${llmsURL}`);
  if (h1Count !== 1) fail(`${relative}: expected one H1, found ${h1Count}`);

  for (const language of ["en", "zh-CN", "x-default"]) {
    if (!new RegExp(`<link\\s+rel=["']alternate["'][^>]+hreflang=["']${language}["']`, "i").test(html)) {
      fail(`${relative}: missing ${language} hreflang`);
    }
  }

  const jsonLD = [...html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)];
  if (jsonLD.length === 0) fail(`${relative}: missing JSON-LD`);
  for (const block of jsonLD) {
    try {
      JSON.parse(block[1]);
    } catch (error) {
      fail(`${relative}: invalid JSON-LD: ${error.message}`);
    }
  }

  for (const match of html.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>/gi)) {
    const target = localTargetForHref(file, match[1]);
    if (target && !fs.existsSync(target)) fail(`${relative}: broken internal link ${match[1]}`);
  }

  for (const match of html.matchAll(/https:\/\/github\.com\/liuzhao1225\/codex-account-switcher\/releases\/[^"'\s<]+\.dmg/g)) {
    if (match[0] !== latestDMGURL) fail(`${relative}: release download must use ${latestDMGURL}`);
  }
}

const sitemap = fs.readFileSync(path.join(siteRoot, "sitemap.xml"), "utf8");
const sitemapURLs = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
const expectedURLs = htmlFiles.map((file) => {
  const relative = path.relative(siteRoot, path.dirname(file)).split(path.sep).join("/");
  return relative === "" ? baseURL : `${baseURL}${relative}/`;
});

for (const url of expectedURLs) {
  if (!sitemapURLs.includes(url)) fail(`site/sitemap.xml: missing ${url}`);
}
for (const url of sitemapURLs) {
  const target = siteFileForURL(url);
  if (!target || !fs.existsSync(target)) fail(`site/sitemap.xml: URL has no matching page ${url}`);
}

const llms = fs.readFileSync(path.join(siteRoot, "llms.txt"), "utf8");
if (!llms.startsWith("# Codex Account Switcher\n")) fail("site/llms.txt: must start with the canonical project H1");
if (!llms.includes("> Codex Account Switcher is")) fail("site/llms.txt: missing concise project summary");

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log(`GEO checks passed for ${htmlFiles.length} HTML pages and ${sitemapURLs.length} sitemap URLs.`);
