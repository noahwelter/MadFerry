"""HTTP access to madferry.com (WordPress REST API)."""

import hashlib
import html
import json
import re
import urllib.request
from typing import Dict, List, Optional
from urllib.parse import urlsplit, urlunsplit

from . import SITE, USER_AGENT


def http_get(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def get_page(page_id: int) -> Dict:
    return json.loads(http_get(f"{SITE}/wp-json/wp/v2/pages/{page_id}"))


def _canonical_image_url(url: str) -> str:
    """Turn a Jetpack CDN URL (i0.wp.com/madferry.com/...) into the original upload URL."""
    url = html.unescape(url)
    parts = urlsplit(url)
    path = parts.path
    if re.match(r"i\d\.wp\.com$", parts.netloc):
        host, _, path = path.lstrip("/").partition("/")
        path = "/" + path
        return urlunsplit(("https", host, path, "", ""))
    return urlunsplit((parts.scheme or "https", parts.netloc, path, "", ""))


def schedule_images(content_html: str) -> List[Dict[str, str]]:
    """Return schedule images in page order as [{url, title}]."""
    images = []
    seen = set()
    for tag in re.findall(r"<img\b[^>]*>", content_html):
        src = re.search(r'data-orig-file="([^"]+)"', tag) or re.search(r'\ssrc="([^"]+)"', tag)
        if not src:
            continue
        url = _canonical_image_url(src.group(1))
        if "/wp-content/uploads/" not in url or url in seen:
            continue
        seen.add(url)
        title = re.search(r'data-image-title="([^"]*)"', tag)
        images.append({"url": url, "title": html.unescape(title.group(1)) if title else ""})
    return images


def html_to_text(content_html: str) -> str:
    text = re.sub(r"<(script|style)\b.*?</\1>", "", content_html, flags=re.S)
    text = re.sub(r"<br\s*/?>|</p>|</div>|</li>|</h\d>|</strong>", "\n", text)
    text = html.unescape(re.sub(r"<[^>]+>", "", text)).replace("\xa0", " ")
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def paragraphs(content_html: str) -> List[str]:
    out = []
    for block in re.findall(r"<(?:p|h\d|li)\b[^>]*>(.*?)</(?:p|h\d|li)>", content_html, flags=re.S):
        text = html_to_text(block).replace("\n", " ").strip()
        if text:
            out.append(text)
    return out


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def fetch_image(url: str) -> Optional[bytes]:
    return http_get(url, timeout=60)
