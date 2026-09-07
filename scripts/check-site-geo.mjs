import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const siteRoot = path.join(root, "site");
const baseURL = "https://liuzhao1225.github.io/codex-account-switcher/";
const llmsURL = `${baseURL}llms.txt`;
const latestDMGURL = "https://github.com/liuzhao1225/codex-account-switcher/releases/latest/download/Codex-Account-Switcher-macos-arm64.dmg";
const errors = [];
const pages = new Map();
const citation = fs.readFileSync(path.join(root, "CITATION.cff"), "utf8");
const releaseVersion = citation.match(/^version:\s*(\S+)/m)?.[1];
const releaseDate = citation.match(/^date-released:\s*(\S+)/m)?.[1];
const pageTypes = new Set(["WebPage", "AboutPage", "ContactPage", "ProfilePage", "TechArticle"]);

function plainText(value) {
  return value.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/\s+/g, " ").trim();
}

function validDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value ?? "") &&
    Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}

function checkTarget(href, sourceURL, label) {
  const url = new URL(href, sourceURL);
  if (!url.href.startsWith(baseURL)) return;
  const target = siteFileForURL(url.href);
  if (!target || !fs.existsSync(target)) {
    fail(`${label}: missing local target ${href}`);
    return;
  }
  if (url.hash && target.endsWith(".html")) {
    const html = fs.readFileSync(target, "utf8");
    const ids = [...html.matchAll(/\bid=["']([^"']+)["']/g)].map((match) => match[1]);
    if (!ids.includes(decodeURIComponent(url.hash.slice(1)))) fail(`${label}: broken fragment ${href}`);
  }
}

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

// This is a project subdirectory. Its robots.txt cannot control host crawling.
for (const required of ["llms.txt", "sitemap.xml"]) {
  if (!fs.existsSync(path.join(siteRoot, required))) fail(`site/${required}: missing required GEO file`);
}

const htmlFiles = listHTML(siteRoot).sort();
if (!releaseVersion || !validDate(releaseDate)) fail("CITATION.cff: release version and date are required");
for (const file of htmlFiles) {
  const relative = path.relative(root, file);
  const html = fs.readFileSync(file, "utf8");
  const title = matchOne(html, /<title[^>]*>([\s\S]*?)<\/title>/gi, "title", relative);
  const description = matchOne(html, /<meta\s+name=["']description["']\s+content=["']([^"']+)["'][^>]*>/gi, "meta description", relative);
  const robots = matchOne(html, /<meta\s+name=["']robots["']\s+content=["']([^"']+)["'][^>]*>/gi, "robots meta", relative).toLowerCase();
  const canonical = matchOne(html, /<link\s+rel=["']canonical["']\s+href=["']([^"']+)["'][^>]*>/gi, "canonical", relative);
  const describedBy = matchOne(html, /<link\s+rel=["']describedby["']\s+href=["']([^"']+)["'][^>]*>/gi, "llms.txt describedby link", relative);
  const h1Count = [...html.matchAll(/<h1\b[^>]*>/gi)].length;
  const localPath = path.relative(siteRoot, path.dirname(file)).split(path.sep).join("/");
  const expectedURL = `${baseURL}${localPath ? `${localPath}/` : ""}`;
  const language = html.match(/<html\s+lang=["']([^"']+)["']/i)?.[1];
  const alternates = Object.fromEntries([...html.matchAll(/<link\s+rel="alternate"\s+hreflang="([^"]+)"\s+href="([^"]+)"/g)].map((match) => [match[1], match[2]]));
  const ogURL = matchOne(html, /<meta\s+property="og:url"\s+content="([^"]+)"[^>]*>/g, "Open Graph URL", relative);

  if (!title) fail(`${relative}: empty title`);
  if (!description) fail(`${relative}: empty meta description`);
  if (!robots.includes("index") || !robots.includes("follow") || !robots.includes("max-snippet:-1")) {
    fail(`${relative}: robots meta must allow indexing, following, and unrestricted snippets`);
  }
  if (/noindex|nofollow|nosnippet|data-nosnippet/i.test(html)) fail(`${relative}: contains a blocking robots/snippet directive`);
  if (!canonical.startsWith(baseURL)) fail(`${relative}: canonical is outside the canonical project site`);
  if (canonical !== expectedURL) fail(`${relative}: canonical must match its own page ${expectedURL}`);
  if (ogURL !== canonical) fail(`${relative}: Open Graph URL must match canonical`);
  if (alternates[language] !== canonical) fail(`${relative}: missing self-referencing hreflang`);
  if (alternates["x-default"] !== alternates.en) fail(`${relative}: x-default must reference its English page`);
  if (describedBy !== llmsURL) fail(`${relative}: describedby must point to ${llmsURL}`);
  if (h1Count !== 1) fail(`${relative}: expected one H1, found ${h1Count}`);

  for (const language of ["en", "zh-CN", "x-default"]) {
    if (!new RegExp(`<link\\s+rel=["']alternate["'][^>]+hreflang=["']${language}["']`, "i").test(html)) {
      fail(`${relative}: missing ${language} hreflang`);
    }
  }

  const jsonLD = [...html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)];
  const nodes = [];
  if (jsonLD.length === 0) fail(`${relative}: missing JSON-LD`);
  for (const block of jsonLD) {
    try {
      const data = JSON.parse(block[1]);
      nodes.push(...(data["@graph"] ?? [data]));
    } catch (error) {
      fail(`${relative}: invalid JSON-LD: ${error.message}`);
    }
  }

  const page = nodes.find((node) => pageTypes.has(node["@type"]));
  if (!page || page.url !== canonical || page.inLanguage !== language) {
    fail(`${relative}: page structured data must identify its canonical URL and language`);
  }
  if (!validDate(page?.dateModified)) fail(`${relative}: page dateModified must be a valid ISO date`);
  if (page?.datePublished && page.dateModified < page.datePublished) fail(`${relative}: dateModified precedes publication`);
  const articleDate = html.match(/<meta\s+property="article:modified_time"\s+content="([^"]+)"/)?.[1];
  if (articleDate && articleDate !== page?.dateModified) fail(`${relative}: article modification date differs from structured data`);

  for (const node of nodes) {
    if (node["@type"] === "WebSite" && (node["@id"] !== `${baseURL}#website` || node.url !== baseURL)) {
      fail(`${relative}: both languages must reference the same website identity`);
    }
    if (node["@type"] === "SoftwareApplication") {
      if (node["@id"] !== `${baseURL}#software` || (node.url && node.url !== baseURL)) {
        fail(`${relative}: software identity must use the canonical product URL`);
      }
      if (node.softwareVersion && (node.softwareVersion !== releaseVersion || node.datePublished !== releaseDate)) {
        fail(`${relative}: software version and release date differ from CITATION.cff`);
      }
    }
    if (node["@type"] === "HowTo") {
      for (const step of node.step ?? []) checkTarget(step.url, expectedURL, relative);
    }
  }

  const visibleFAQ = [...html.matchAll(/<details[^>]*>\s*<summary>([\s\S]*?)<\/summary>\s*<p>([\s\S]*?)<\/p>\s*<\/details>/g)]
    .map(([, question, answer]) => [plainText(question), plainText(answer)]);
  const faq = nodes.find((node) => node["@type"] === "FAQPage");
  if (visibleFAQ.length && !faq) fail(`${relative}: visible FAQ is missing its structured data`);
  if (faq) {
    const structuredFAQ = (faq.mainEntity ?? []).map((question) => [plainText(question.name), plainText(question.acceptedAnswer.text)]);
    if (JSON.stringify(visibleFAQ) !== JSON.stringify(structuredFAQ)) fail(`${relative}: FAQ structured data differs from visible questions or answers`);
  }

  for (const match of html.matchAll(/(?:\bhref|\bsrc)=["']([^"']+)["']/g)) checkTarget(match[1], expectedURL, relative);
  for (const match of html.matchAll(/<meta\s+(?:property|name)="(?:og:image|twitter:image)"\s+content="([^"]+)"/g)) checkTarget(match[1], expectedURL, relative);
  pages.set(expectedURL, { relative, title, description, language, alternates, modified: page?.dateModified });

  for (const match of html.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>/gi)) {
    const target = localTargetForHref(file, match[1]);
    if (target && !fs.existsSync(target)) fail(`${relative}: broken internal link ${match[1]}`);
  }

  for (const match of html.matchAll(/https:\/\/github\.com\/liuzhao1225\/codex-account-switcher\/releases\/[^"'\s<]+\.dmg/g)) {
    if (match[0] !== latestDMGURL) fail(`${relative}: release download must use ${latestDMGURL}`);
  }
}

for (const [url, page] of pages) {
  for (const language of ["en", "zh-CN"]) {
    const alternate = pages.get(page.alternates[language]);
    if (!alternate || alternate.language !== language || alternate.alternates[page.language] !== url) {
      fail(`${page.relative}: ${language} hreflang must resolve to a reciprocal localized page`);
    }
  }
  for (const [otherURL, other] of pages) {
    if (otherURL <= url) continue;
    if (page.title === other.title) fail(`${page.relative}: duplicate title with ${other.relative}`);
    if (page.description === other.description) fail(`${page.relative}: duplicate description with ${other.relative}`);
  }
}

const sitemap = fs.readFileSync(path.join(siteRoot, "sitemap.xml"), "utf8");
const sitemapURLs = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
if (new Set(sitemapURLs).size !== sitemapURLs.length) fail("site/sitemap.xml: duplicate URLs");
for (const [, entry] of sitemap.matchAll(/<url>([\s\S]*?)<\/url>/g)) {
  const url = entry.match(/<loc>([^<]+)<\/loc>/)?.[1];
  const modified = entry.match(/<lastmod>([^<]+)<\/lastmod>/)?.[1];
  const page = pages.get(url);
  if (!validDate(modified) || modified !== page?.modified) fail(`site/sitemap.xml: lastmod differs from the page record for ${url}`);
  const alternates = Object.fromEntries([...entry.matchAll(/<xhtml:link\s+rel="alternate"\s+hreflang="([^"]+)"\s+href="([^"]+)"/g)].map((match) => [match[1], match[2]]));
  for (const language of ["en", "zh-CN", "x-default"]) {
    if (!alternates[language] || alternates[language] !== page?.alternates[language]) fail(`site/sitemap.xml: ${language} alternate differs from ${url}`);
  }
}
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
if (!llms.includes(`current release is v${releaseVersion}`)) fail("site/llms.txt: current release differs from CITATION.cff");
for (const [, href] of llms.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) checkTarget(href, baseURL, "site/llms.txt");

if (errors.length) {
  console.error(errors.join("\n"));
  process.exit(1);
}

console.log(`GEO checks passed for ${htmlFiles.length} HTML pages and ${sitemapURLs.length} sitemap URLs.`);
