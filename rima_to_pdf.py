#!/usr/bin/env python3
"""
Scrapes all pages of the RIMA GitBook and combines them into a single PDF.
Requires: requests, beautifulsoup4, weasyprint
"""

import re
import sys
import time
import requests
from bs4 import BeautifulSoup
from weasyprint import HTML, CSS
from weasyprint.text.fonts import FontConfiguration

BASE_URL = "https://liulab-dfci.github.io/RIMA/"

PAGES = [
    ("index.html",                        "Introduction"),
    ("how-to-run-rima.html",              "How to run RIMA"),
    ("Preprocessing.html",                "Pre-processing of bulk RNA-seq data"),
    ("Differential.html",                 "Differential gene analysis"),
    ("Repertoire.html",                   "Immune repertoire"),
    ("Infiltration.html",                 "Immune Infiltration"),
    ("Response.html",                     "Immune Response"),
    ("HLA.html",                          "HLA Typing & Neoantigens"),
    ("fusion.html",                       "Fusion"),
    ("microbiome.html",                   "Microbiome"),
    ("customize-your-own-reference.html", "Customize your own reference"),
]

CSS_OVERRIDE = """
@page {
    size: A4;
    margin: 2cm 2.5cm;
    @bottom-center {
        content: counter(page);
        font-size: 10pt;
        color: #666;
    }
}

body {
    font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.6;
    color: #222;
}

h1 { font-size: 20pt; margin-top: 1.5em; border-bottom: 2px solid #333; padding-bottom: 0.3em; }
h2 { font-size: 16pt; margin-top: 1.2em; }
h3 { font-size: 13pt; margin-top: 1em; }

pre, code {
    font-family: "Courier New", Courier, monospace;
    font-size: 9pt;
    background: #f5f5f5;
    border-radius: 3px;
}
pre {
    padding: 0.8em;
    overflow-wrap: break-word;
    white-space: pre-wrap;
    border-left: 3px solid #ccc;
}

img {
    max-width: 100%;
    height: auto;
}

a { color: #2c5f9e; text-decoration: none; }

.chapter-break {
    page-break-before: always;
    margin-top: 0;
}

table {
    border-collapse: collapse;
    width: 100%;
    margin: 1em 0;
}
th, td {
    border: 1px solid #ccc;
    padding: 6px 10px;
    text-align: left;
}
th { background: #f0f0f0; font-weight: bold; }
"""


def fetch_page(url: str):
    try:
        r = requests.get(url, timeout=30)
        r.raise_for_status()
        return BeautifulSoup(r.text, "html.parser")
    except requests.RequestException as e:
        print(f"  WARNING: could not fetch {url}: {e}", file=sys.stderr)
        return None


def extract_content(soup, page_url: str) -> str:
    """Extract main readable content from a GitBook/bookdown page."""

    # bookdown GitBook uses .chapter inside .book-body
    content = soup.find("div", class_="chapter")
    if not content:
        content = soup.find("div", {"role": "main"})
    if not content:
        content = soup.find("main")
    if not content:
        content = soup.find("div", id="content")
    if not content:
        content = soup.body

    if content is None:
        return ""

    # Fix relative image URLs so weasyprint can resolve them
    for img in content.find_all("img"):
        src = img.get("src", "")
        if src and not src.startswith(("http://", "https://", "data:")):
            img["src"] = BASE_URL + src.lstrip("./")

    # Make relative links absolute so they remain clickable in the PDF
    for a in content.find_all("a", href=True):
        href = a["href"]
        if href and not href.startswith(("http://", "https://", "#", "mailto:")):
            a["href"] = BASE_URL + href.lstrip("./")

    return str(content)


def build_html(sections: list) -> str:
    """Wrap all extracted sections in a single HTML document."""
    body_parts = []
    for i, (title, html_content) in enumerate(sections):
        cls = "chapter-break" if i > 0 else ""
        body_parts.append(f'<section class="{cls}">{html_content}</section>')

    body = "\n".join(body_parts)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>RIMA — RNA-seq Immune landscape Analysis</title>
</head>
<body>
{body}
</body>
</html>"""


def main():
    output_path = "RIMA_book.pdf"
    print(f"Fetching {len(PAGES)} pages from {BASE_URL}\n")

    sections = []

    for filename, title in PAGES:
        url = BASE_URL + filename
        print(f"  Fetching: {url}")
        soup = fetch_page(url)
        if soup is None:
            sections.append((title, f"<h1>{title}</h1><p><em>Page could not be fetched.</em></p>"))
            continue
        content = extract_content(soup, url)
        sections.append((title, content))
        time.sleep(0.3)  # be polite to the server

    print(f"\nBuilding combined HTML ({len(sections)} sections)...")
    combined_html = build_html(sections)

    print(f"Converting to PDF → {output_path}  (may take a minute)...")
    font_config = FontConfiguration()
    css = CSS(string=CSS_OVERRIDE, font_config=font_config)
    HTML(string=combined_html, base_url=BASE_URL).write_pdf(
        output_path,
        stylesheets=[css],
        font_config=font_config,
    )

    print(f"\nDone! Saved to: {output_path}")


if __name__ == "__main__":
    main()
