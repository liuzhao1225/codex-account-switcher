<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0"
  xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:sm="http://www.sitemaps.org/schemas/sitemap/0.9"
  xmlns:xhtml="http://www.w3.org/1999/xhtml"
  exclude-result-prefixes="sm xhtml">
  <xsl:output method="html" encoding="UTF-8" indent="yes" />

  <xsl:template match="/">
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Codex Account Switcher Sitemap</title>
        <style>
          :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; }
          body { margin: 0; background: #f5f5f7; color: #1d1d1f; }
          main { width: min(880px, calc(100% - 40px)); margin: 0 auto; padding: 72px 0; }
          p { color: #6e6e73; line-height: 1.6; }
          table { width: 100%; margin-top: 32px; border-collapse: collapse; overflow: hidden; border: 1px solid #d2d2d7; border-radius: 14px; background: #fff; }
          th, td { padding: 16px 18px; border-bottom: 1px solid #e5e5ea; text-align: left; }
          th { color: #6e6e73; font-size: 13px; font-weight: 600; }
          tr:last-child td { border-bottom: 0; }
          a { color: #06c; text-decoration: none; overflow-wrap: anywhere; }
          a:hover { text-decoration: underline; }
          @media (prefers-color-scheme: dark) {
            body { background: #000; color: #f5f5f7; }
            p, th { color: #a1a1a6; }
            table { border-color: #38383a; background: #1c1c1e; }
            th, td { border-bottom-color: #38383a; }
            a { color: #2997ff; }
          }
          @media (max-width: 600px) {
            main { padding: 40px 0; }
            th:nth-child(2), td:nth-child(2) { display: none; }
            th, td { padding: 14px; }
          }
        </style>
      </head>
      <body>
        <main>
          <h1>Codex Account Switcher Sitemap</h1>
          <p>This XML sitemap helps search engines discover the English and Simplified Chinese product pages.</p>
          <table>
            <thead>
              <tr>
                <th>URL</th>
                <th>Last updated</th>
              </tr>
            </thead>
            <tbody>
              <xsl:for-each select="sm:urlset/sm:url">
                <tr>
                  <td><a href="{sm:loc}"><xsl:value-of select="sm:loc" /></a></td>
                  <td><xsl:value-of select="sm:lastmod" /></td>
                </tr>
              </xsl:for-each>
            </tbody>
          </table>
        </main>
      </body>
    </html>
  </xsl:template>
</xsl:stylesheet>
