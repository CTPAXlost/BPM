#!/usr/bin/env python3
"""Build a capped public VPN catalog from plain/base64 subscriptions and v2nodes pages.

The script uses only the Python standard library so it runs on GitHub-hosted runners.
It never generates or publishes WARP private keys; WARP is generated locally in the app.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import concurrent.futures
import datetime as dt
import hashlib
import html
import ipaddress
import json
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable

SCHEMES = ("vless", "vmess", "trojan", "ss", "shadowsocks", "hysteria2", "hysteria", "hy2", "tuic")
LINK_RE = re.compile(r"(?:(?:" + "|".join(SCHEMES) + r")://[^\s\"'<>]+)", re.I)
SERVER_LINK_RE = re.compile(r'href=["\'](?P<url>(?:https?://[^"\']+)?/servers/\d+/)["\']', re.I)
HREF_RE = re.compile(r'href=["\'](?P<url>[^"\']+)["\']', re.I)
MAX_DOWNLOAD = 8 * 1024 * 1024
USER_AGENT = "Pokolenie-VPN-Catalog/0.9.3 (+GitHub Actions)"
COUNTRIES = {
    "germany": ("DE", "Германия"), "герман": ("DE", "Германия"),
    "france": ("FR", "Франция"), "франц": ("FR", "Франция"),
    "netherlands": ("NL", "Нидерланды"), "нидерланд": ("NL", "Нидерланды"),
    "finland": ("FI", "Финляндия"), "финлянд": ("FI", "Финляндия"),
    "united states": ("US", "США"), "usa": ("US", "США"), "сша": ("US", "США"),
    "hong kong": ("HK", "Гонконг"), "гонконг": ("HK", "Гонконг"),
    "singapore": ("SG", "Сингапур"), "сингапур": ("SG", "Сингапур"),
    "italy": ("IT", "Италия"), "итал": ("IT", "Италия"),
    "norway": ("NO", "Норвегия"), "норвег": ("NO", "Норвегия"),
    "sweden": ("SE", "Швеция"), "швец": ("SE", "Швеция"),
    "poland": ("PL", "Польша"), "польш": ("PL", "Польша"),
    "turkey": ("TR", "Турция"), "турц": ("TR", "Турция"),
    "japan": ("JP", "Япония"), "япон": ("JP", "Япония"),
    "canada": ("CA", "Канада"), "канада": ("CA", "Канада"),
    "russia": ("RU", "Россия"), "росси": ("RU", "Россия"),
    "ukraine": ("UA", "Украина"), "украин": ("UA", "Украина"),
    "switzerland": ("CH", "Швейцария"), "швейцар": ("CH", "Швейцария"),
    "united kingdom": ("GB", "Великобритания"), "великобрит": ("GB", "Великобритания"),
    "kazakhstan": ("KZ", "Казахстан"), "казахстан": ("KZ", "Казахстан"),
}

@dataclass(slots=True)
class Node:
    id: str
    name: str
    protocol: str
    raw_config: str
    host: str
    port: int
    transport: str
    country_code: str
    country_name: str
    source: str
    latency_ms: int | None = None
    health: str = "unknown"
    favorite: bool = False
    last_checked: str | None = None
    metadata: dict | None = None


def b64decode_flexible(value: str) -> bytes:
    value = re.sub(r"\s+", "", value).replace("-", "+").replace("_", "/")
    value += "=" * ((4 - len(value) % 4) % 4)
    return base64.b64decode(value, validate=False)


def fetch(url: str, timeout: float = 20.0) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    context = ssl.create_default_context()
    with urllib.request.urlopen(request, timeout=timeout, context=context) as response:
        data = response.read(MAX_DOWNLOAD + 1)
        if len(data) > MAX_DOWNLOAD:
            raise ValueError(f"source too large: {url}")
        charset = response.headers.get_content_charset() or "utf-8"
        return data.decode(charset, errors="replace")


def normalize_subscription(raw: str) -> str:
    text = html.unescape(raw).strip()
    if "://" in text or "\n" in text:
        return text
    try:
        decoded = b64decode_flexible(text).decode("utf-8", errors="replace")
        return decoded if "://" in decoded else text
    except Exception:
        return text


def extract_links(raw: str) -> list[str]:
    text = normalize_subscription(raw)
    result: list[str] = []
    seen: set[str] = set()
    for match in LINK_RE.finditer(text):
        link = match.group(0).rstrip("),;]}>")
        if link not in seen:
            seen.add(link)
            result.append(link)
    return result


def decode_name(fragment: str, fallback: str) -> str:
    name = urllib.parse.unquote(fragment or "").strip()
    return re.sub(r"\s+", " ", name)[:180] or fallback


def guess_country(name: str) -> tuple[str, str]:
    lowered = name.lower()
    for token, country in COUNTRIES.items():
        if token in lowered:
            return country
    flags = re.findall(r"[\U0001F1E6-\U0001F1FF]{2}", name)
    if flags:
        code = "".join(chr(ord(ch) - 127397) for ch in flags[0])
        return code, code
    return "", ""


def parse_ss(raw: str, source: str, catalog_class: str = "regular") -> Node | None:
    value = re.sub(r"^shadowsocks://", "ss://", raw, flags=re.I)
    parsed = urllib.parse.urlsplit(value)
    host, port, method, password = parsed.hostname or "", parsed.port or 0, "", ""
    if host and port:
        auth = urllib.parse.unquote(parsed.username or "")
        if parsed.password is not None:
            method, password = auth, urllib.parse.unquote(parsed.password)
        else:
            try:
                auth = b64decode_flexible(auth).decode()
            except Exception:
                pass
            if ":" in auth:
                method, password = auth.split(":", 1)
    else:
        payload = value[5:].split("#", 1)[0].split("?", 1)[0]
        decoded = b64decode_flexible(payload).decode()
        auth, endpoint = decoded.rsplit("@", 1)
        method, password = auth.split(":", 1)
        host, port_text = endpoint.rsplit(":", 1)
        port = int(port_text)
    if not host or not port or not method or not password:
        return None
    name = decode_name(parsed.fragment, "Shadowsocks")
    cc, country = guess_country(name)
    query = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
    metadata = {"method": method, "password": password, "query": query}
    if query.get("plugin"):
        metadata["plugin"] = query["plugin"]
    return make_node(raw, source, "ss", name, host, port, "TCP/UDP", cc, country,
                     metadata, catalog_class)


def parse_vmess(raw: str, source: str, catalog_class: str = "regular") -> Node | None:
    payload = raw.split("://", 1)[1]
    data = json.loads(b64decode_flexible(payload).decode("utf-8"))
    host, port = str(data.get("add", "")), int(data.get("port", 0))
    if not host or not port:
        return None
    name = str(data.get("ps") or "VMess")[:180]
    cc, country = guess_country(name)
    return make_node(raw, source, "vmess", name, host, port, str(data.get("net") or "tcp"), cc, country, data, catalog_class)


def parse_generic(raw: str, source: str, catalog_class: str = "regular") -> Node | None:
    normalized = re.sub(r"^(hy2|hysteria)://", "hysteria2://", raw, flags=re.I)
    parsed = urllib.parse.urlsplit(normalized)
    scheme = parsed.scheme.lower()
    protocol = "hysteria2" if scheme in {"hy2", "hysteria", "hysteria2"} else scheme
    host, port = parsed.hostname or "", parsed.port or 0
    if not host or not port:
        return None
    fallback = {"vless": "VLESS", "trojan": "Trojan", "hysteria2": "Hysteria 2", "tuic": "TUIC"}.get(protocol, protocol)
    name = decode_name(parsed.fragment, fallback)
    query = dict(urllib.parse.parse_qsl(parsed.query, keep_blank_values=True))
    transport = query.get("type") or query.get("network") or ("QUIC" if protocol in {"hysteria2", "tuic"} else "TCP")
    cc, country = guess_country(name)
    user_info = urllib.parse.unquote(parsed.username or "")
    if parsed.password is not None:
        user_info += ":" + urllib.parse.unquote(parsed.password)
    return make_node(raw, source, protocol, name, host, port, transport, cc, country, {"query": query, "user_info": user_info}, catalog_class)


def make_node(raw: str, source: str, protocol: str, name: str, host: str, port: int,
              transport: str, cc: str, country: str, metadata: dict,
              catalog_class: str = "regular") -> Node:
    identifier = hashlib.sha256(raw.encode()).hexdigest()[:20]
    lowered = f"{source} {name}".lower()
    metadata = dict(metadata or {})
    detected_whitelist = any(
        token in lowered
        for token in ("белые списки", "white list", "whitelist", "sni-ru", "cidr")
    )
    effective_class = "whitelist" if catalog_class == "whitelist" or detected_whitelist else "regular"
    metadata["catalog_class"] = effective_class
    if effective_class == "whitelist":
        metadata["special_class"] = "whitelist"
    return Node(identifier, name, protocol, raw, host, port, transport, cc, country, source, metadata=metadata)


def parse_link(raw: str, source: str, catalog_class: str = "regular") -> Node | None:
    try:
        scheme = raw.split(":", 1)[0].lower()
        if scheme in {"ss", "shadowsocks"}:
            return parse_ss(raw, source, catalog_class)
        if scheme == "vmess":
            return parse_vmess(raw, source, catalog_class)
        return parse_generic(raw, source, catalog_class)
    except Exception:
        return None


def _is_uuid(value: str) -> bool:
    return bool(re.fullmatch(
        r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
        value.strip(),
    ))


def _valid_reality_public_key(value: str) -> bool:
    if not re.fullmatch(r"[A-Za-z0-9_-]{43}={0,1}", value):
        return False
    try:
        normalized = value + "=" * ((4 - len(value) % 4) % 4)
        return len(base64.urlsafe_b64decode(normalized)) == 32
    except (ValueError, binascii.Error):
        return False


def compatibility_error(node: Node) -> str | None:
    if not node.host or not (0 < node.port <= 65535):
        return "invalid endpoint"
    metadata = node.metadata or {}
    query = metadata.get("query") if isinstance(metadata.get("query"), dict) else {}

    user_info = urllib.parse.unquote(str(metadata.get("user_info") or "").strip())
    if node.protocol in {"vless", "trojan", "hysteria2", "tuic"} and not user_info:
        return "missing credentials"
    if node.protocol == "vless" and not _is_uuid(user_info):
        return "invalid vless uuid"
    if node.protocol == "vmess":
        if not _is_uuid(str(metadata.get("id") or "")):
            return "invalid vmess uuid"
        cipher = str(metadata.get("scy") or "auto").lower().strip()
        if cipher not in {"", "auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305"}:
            return f"unsupported vmess cipher {cipher}"
    if node.protocol == "tuic":
        uuid, separator, password = user_info.partition(":")
        if not separator or not _is_uuid(uuid) or not password:
            return "invalid tuic credentials"

    if node.protocol == "ss":
        plugin = str(metadata.get("plugin") or query.get("plugin") or "").strip()
        if plugin:
            return "unsupported shadowsocks plugin"
        supported_methods = {
            "aes-128-gcm", "aes-192-gcm", "aes-256-gcm",
            "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305",
            "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm",
            "2022-blake3-chacha20-poly1305",
            "aes-128-ctr", "aes-192-ctr", "aes-256-ctr",
            "aes-128-cfb", "aes-192-cfb", "aes-256-cfb",
            "rc4-md5", "chacha20-ietf", "xchacha20", "none",
        }
        method = str(metadata.get("method") or "").lower().strip()
        if method not in supported_methods:
            return f"unsupported shadowsocks method {method}"
        return None

    if node.protocol in {"hysteria2", "tuic"}:
        return None

    transport = str(query.get("type") or query.get("network") or node.transport or "").lower().strip()
    supported = {"", "tcp", "raw", "ws", "websocket", "grpc", "http", "h2", "httpupgrade"}
    if transport not in supported:
        return f"unsupported transport {transport}"
    header_type = str(query.get("headerType") or query.get("header_type") or "").lower().strip()
    if header_type not in {"", "none"}:
        return f"unsupported tcp header {header_type}"

    security = str(query.get("security") or "").lower().strip()
    if security not in {"", "none", "tls", "reality"}:
        return f"unsupported security {security}"
    if node.protocol == "vless":
        encryption = str(query.get("encryption") or "none").lower().strip()
        if encryption not in {"", "none"}:
            return "vless encryption must be none"
        flow = str(query.get("flow") or "").lower().strip()
        if flow not in {"", "xtls-rprx-vision"}:
            return f"unsupported vless flow {flow}"
        if flow and transport not in {"", "tcp", "raw"}:
            return "vless vision requires tcp/raw"
    if security in {"tls", "reality"}:
        sni = str(query.get("sni") or query.get("serverName") or "").strip()
        if not sni or "://" in sni or " " in sni:
            return "invalid sni"
    if security == "reality":
        public_key = str(query.get("pbk") or query.get("publicKey") or "").strip()
        if not _valid_reality_public_key(public_key):
            return "invalid reality public key"
        short_id = str(query.get("sid") or query.get("shortId") or "").strip()
        if short_id and (not re.fullmatch(r"[0-9a-fA-F]{2,16}", short_id) or len(short_id) % 2):
            return "invalid reality short id"
    return None


def public_host(host: str) -> bool:

    lowered = host.rstrip(".").lower()
    if lowered in {"localhost", "localhost.localdomain"} or lowered.endswith(".local"):
        return False
    try:
        addresses = {item[4][0] for item in socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)}
    except OSError:
        return False
    if not addresses:
        return False
    for address in addresses:
        ip = ipaddress.ip_address(address.split("%", 1)[0])
        if ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast or ip.is_unspecified or ip.is_reserved:
            return False
    return True


def tcp_probe(node: Node, timeout: float) -> Node:
    # Hysteria2 and TUIC are UDP protocols. DNS/public-address validation is the safe prefilter;
    # full protocol verification happens in the client or in verified upstream feeds.
    if node.protocol in {"hysteria2", "tuic"}:
        node.health = "unknown"
        return node
    started = time.monotonic()
    try:
        with socket.create_connection((node.host, node.port), timeout=timeout):
            pass
        node.latency_ms = max(1, round((time.monotonic() - started) * 1000))
        node.health = "online" if node.latency_ms <= 700 else "slow"
        node.last_checked = dt.datetime.now(dt.timezone.utc).isoformat()
    except OSError:
        node.health = "offline"
    return node


def crawl_v2nodes(seed: str, max_pages: int) -> list[tuple[str, str]]:
    """Crawl country pagination first, then fetch up to 60 server detail pages."""
    seed_parts = urllib.parse.urlsplit(seed)
    listing_queue = [seed]
    listing_visited: set[str] = set()
    server_pages: list[str] = []
    server_seen: set[str] = set()
    found: list[tuple[str, str]] = []

    while listing_queue and len(listing_visited) < max(1, min(max_pages, 20)):
        url = listing_queue.pop(0)
        if url in listing_visited:
            continue
        listing_visited.add(url)
        try:
            page = fetch(url)
        except Exception as exc:
            print(f"warning: v2nodes listing failed {url}: {exc}", file=sys.stderr)
            continue
        source_name = f"V2Nodes {urllib.parse.urlsplit(url).path.rstrip('/').split('/')[-1] or 'catalog'}"
        found.extend((link, source_name) for link in extract_links(page))
        for match in HREF_RE.finditer(page):
            related = urllib.parse.urljoin(url, html.unescape(match.group("url")))
            parts = urllib.parse.urlsplit(related)
            if parts.scheme != "https" or parts.netloc != seed_parts.netloc:
                continue
            normalized = urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, parts.query, ""))
            if re.fullmatch(r"/servers/\d+/?", parts.path):
                if normalized not in server_seen:
                    server_seen.add(normalized)
                    server_pages.append(normalized)
                continue
            same_country = parts.path == seed_parts.path
            page_path = parts.path.startswith(seed_parts.path + "page/") or parts.path.startswith(seed_parts.path + "p/")
            page_query = "page=" in parts.query
            if (same_country or page_path or page_query) and normalized not in listing_visited and normalized not in listing_queue:
                listing_queue.append(normalized)

    pages = server_pages[:60]
    def load_server(url: str) -> list[tuple[str, str]]:
        try:
            page = fetch(url)
            server_id = urllib.parse.urlsplit(url).path.rstrip('/').split('/')[-1]
            return [(link, f"V2Nodes France #{server_id}") for link in extract_links(page)]
        except Exception as exc:
            print(f"warning: v2nodes server failed {url}: {exc}", file=sys.stderr)
            return []

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as executor:
        for pairs in executor.map(load_server, pages):
            found.extend(pairs)
    return found


def collect(sources_file: Path) -> list[Node]:
    config = json.loads(sources_file.read_text(encoding="utf-8"))
    nodes: dict[str, Node] = {}
    groups: dict[str, list[dict]] = {}
    for source in config.get("sources", []):
        if not source.get("enabled", True):
            continue
        key = str(source.get("mirror_group") or source.get("id") or source.get("url"))
        groups.setdefault(key, []).append(source)

    for mirrors in groups.values():
        selected_name = " / ".join(str(item.get("name", "Источник")) for item in mirrors)
        pairs: list[tuple[str, str, str, str]] = []
        for source in mirrors:
            name, url = str(source.get("name", "Источник")), str(source.get("url", ""))
            if not url.startswith("https://"):
                print(f"warning: skipped non-HTTPS source {name}", file=sys.stderr)
                continue
            try:
                if source.get("type") in {"v2nodes_seed", "v2nodes_country"}:
                    candidate_raw = crawl_v2nodes(url, min(int(source.get("max_pages", 20)), 50))
                    candidate = [(link, actual_source, str(source.get("catalog_class") or "regular"), str(source.get("catalog_subtype") or "")) for link, actual_source in candidate_raw]
                else:
                    candidate = [(link, name, str(source.get("catalog_class") or "regular"), str(source.get("catalog_subtype") or "")) for link in extract_links(fetch(url))]
                if not candidate:
                    raise ValueError("source contains no supported configurations")
                pairs = candidate
                selected_name = name
                break
            except Exception as exc:
                print(f"warning: source mirror failed {name}: {exc}", file=sys.stderr)
        if not pairs:
            print(f"warning: all mirrors failed {selected_name}", file=sys.stderr)
            continue
        for link, actual_source, catalog_class, catalog_subtype in pairs:
            node = parse_link(link, actual_source, catalog_class)
            if node and catalog_subtype:
                node.metadata["catalog_subtype"] = catalog_subtype
            if node and node.protocol in {"vless", "vmess", "trojan", "ss", "hysteria2", "tuic"}:
                key = node.id
                if (node.metadata or {}).get("catalog_class") == "whitelist":
                    key = f"{(node.metadata or {}).get('catalog_subtype') or 'other'}:{node.id}"
                nodes.setdefault(key, node)
        print(f"{selected_name}: total unique {len(nodes)}")
    return list(nodes.values())


def _round_robin_sources(nodes: list[Node], limit: int) -> list[Node]:
    """Keep candidate diversity instead of taking one large source first."""
    by_source: dict[str, list[Node]] = {}
    for node in nodes:
        by_source.setdefault(node.source or "unknown", []).append(node)
    selected: list[Node] = []
    groups = list(by_source.values())
    cursor = 0
    while groups and len(selected) < limit:
        next_groups: list[list[Node]] = []
        for group in groups:
            if cursor < len(group):
                selected.append(group[cursor])
                if len(selected) >= limit:
                    break
            if cursor + 1 < len(group):
                next_groups.append(group)
        cursor += 1
        groups = next_groups
    return selected


def _probe_candidates(nodes: list[Node], cap: int) -> list[Node]:
    # Probing every URI from large public feeds can mean thousands of sockets.
    # Four times the output cap per bucket gives enough fallback capacity while
    # keeping hourly GitHub builds predictable. Source round-robin avoids one
    # feed crowding out all other providers before the health check.
    limit = max(cap * 4, 100)
    selected: list[Node] = []
    for subtype in ("mobile", "cidr_checked", "cidr_all", "sni", "other"):
        group = [
            node for node in nodes
            if (node.metadata or {}).get("catalog_class") == "whitelist"
            and ((node.metadata or {}).get("catalog_subtype") or "other") == subtype
        ]
        selected.extend(_round_robin_sources(group, limit))
    for protocol in ("vless", "trojan", "ss", "vmess", "hysteria2", "tuic"):
        group = [
            node for node in nodes
            if node.protocol == protocol
            and (node.metadata or {}).get("catalog_class") != "whitelist"
        ]
        selected.extend(_round_robin_sources(group, limit))
    return selected


def build_catalog(nodes: Iterable[Node], max_per_protocol: int, no_ping: bool, timeout: float) -> dict:
    all_nodes = list(nodes)
    rejected = [node for node in all_nodes if compatibility_error(node) is not None]
    compatible = [node for node in all_nodes if compatibility_error(node) is None]
    cap = max(1, min(max_per_protocol, 50))
    candidates = compatible if no_ping else _probe_candidates(compatible, cap)

    unique_hosts = sorted({node.host for node in candidates})
    with concurrent.futures.ThreadPoolExecutor(max_workers=64) as executor:
        host_results = dict(zip(unique_hosts, executor.map(public_host, unique_hosts)))
    valid = [node for node in candidates if host_results.get(node.host, False)]

    if not no_ping:
        with concurrent.futures.ThreadPoolExecutor(max_workers=64) as executor:
            valid = list(executor.map(lambda n: tcp_probe(n, timeout), valid))
        valid = [node for node in valid if node.health != "offline"]

    selected: list[Node] = []
    counts: dict[str, int] = {}

    whitelist_subtypes = ("mobile", "cidr_checked", "cidr_all", "sni", "other")
    whitelist_counts: dict[str, int] = {}
    for subtype in whitelist_subtypes:
        group = [
            node for node in valid
            if (node.metadata or {}).get("catalog_class") == "whitelist"
            and ((node.metadata or {}).get("catalog_subtype") or "other") == subtype
        ]
        group.sort(key=lambda n: (n.latency_ms is None, n.latency_ms or 10**9, n.name.lower()))
        chosen = group[:cap]
        selected.extend(chosen)
        whitelist_counts[subtype] = len(chosen)
    counts["whitelist"] = sum(whitelist_counts.values())

    protocols = ("vless", "trojan", "ss", "vmess", "hysteria2", "tuic")
    for protocol in protocols:
        group = [
            node for node in valid
            if node.protocol == protocol
            and (node.metadata or {}).get("catalog_class") != "whitelist"
        ]
        group.sort(key=lambda n: (n.latency_ms is None, n.latency_ms or 10**9, n.name.lower()))
        chosen = group[:cap]
        selected.extend(chosen)
        counts[protocol] = len(chosen)

    return {
        "schema": 3,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "counts": counts,
        "whitelist_counts": whitelist_counts,
        "rejected_incompatible": len(rejected),
        "nodes": [asdict(node) for node in selected],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", default="catalog/sources.json")
    parser.add_argument("--output", default="catalog/public_catalog.json")
    parser.add_argument("--max-per-protocol", type=int, default=50)
    parser.add_argument("--timeout", type=float, default=2.5)
    parser.add_argument("--no-ping", action="store_true")
    parser.add_argument("--allow-empty", action="store_true")
    args = parser.parse_args()
    max_per = max(1, min(args.max_per_protocol, 50))
    nodes = collect(Path(args.sources))
    catalog = build_catalog(nodes, max_per, args.no_ping, args.timeout)
    if not catalog["nodes"] and not args.allow_empty:
        print("error: catalog is empty", file=sys.stderr)
        return 2
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {len(catalog['nodes'])} nodes to {output}")
    print(json.dumps(catalog["counts"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
