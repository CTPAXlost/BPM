import base64
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import catalog_builder as cb  # noqa: E402


def uuid_for(index: int) -> str:
    return f"00000000-0000-0000-0000-{index:012x}"


class CatalogBuilderTests(unittest.TestCase):
    def test_extract_plain_and_base64(self) -> None:
        raw = (
            f"vless://{uuid_for(1)}@example.com:443?security=tls#France\n"
            "trojan://pw@example.net:443#Germany"
        )
        self.assertEqual(len(cb.extract_links(raw)), 2)
        encoded = base64.b64encode(raw.encode()).decode()
        self.assertEqual(len(cb.extract_links(encoded)), 2)

    def test_parse_vmess(self) -> None:
        payload = base64.b64encode(
            json.dumps(
                {
                    "v": "2",
                    "ps": "France",
                    "add": "example.com",
                    "port": "443",
                    "id": uuid_for(2),
                    "aid": "0",
                    "net": "ws",
                }
            ).encode()
        ).decode()
        node = cb.parse_link("vmess://" + payload, "test")
        self.assertIsNotNone(node)
        self.assertEqual(node.protocol, "vmess")
        self.assertIsNone(cb.compatibility_error(node))

    def test_parse_shadowsocks_and_reject_plugin(self) -> None:
        auth = base64.urlsafe_b64encode(b"aes-256-gcm:secret").decode().rstrip("=")
        node = cb.parse_link(f"ss://{auth}@example.com:8388#Germany", "test")
        self.assertIsNotNone(node)
        self.assertIsNone(cb.compatibility_error(node))
        plugin = cb.parse_link(
            f"ss://{auth}@example.com:8388?plugin=v2ray-plugin#Germany", "test"
        )
        self.assertIsNotNone(plugin)
        self.assertIn("plugin", cb.compatibility_error(plugin))

    def test_accepts_official_legacy_shadowsocks_cipher(self) -> None:
        auth = base64.urlsafe_b64encode(b"aes-256-cfb:legacy-secret").decode().rstrip("=")
        node = cb.parse_link(f"ss://{auth}@legacy.example:8388#Legacy", "test")
        self.assertIsNotNone(node)
        self.assertIsNone(cb.compatibility_error(node))

    def test_reality_raw_is_accepted_and_xhttp_is_rejected(self) -> None:
        raw = cb.parse_link(
            f"vless://{uuid_for(3)}@white.example:443"
            "?type=raw&security=reality&sni=example.com&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA&flow=xtls-rprx-vision"
            "#WHITE-CIDR",
            "Белые списки RU",
            "whitelist",
        )
        self.assertIsNotNone(raw)
        self.assertIsNone(cb.compatibility_error(raw))
        self.assertEqual(raw.metadata["catalog_class"], "whitelist")

        malformed = cb.parse_link(
            f"vless://{uuid_for(33)}@bad-key.example:443"
            "?type=raw&security=reality&sni=example.com&pbk=public-key"
            "&flow=xtls-rprx-vision#bad-key",
            "test",
        )
        self.assertIsNotNone(malformed)
        self.assertIn("reality public key", cb.compatibility_error(malformed))

        xhttp = cb.parse_link(
            f"vless://{uuid_for(4)}@bad.example:443"
            "?type=xhttp&security=tls&sni=example.com#bad",
            "test",
        )
        self.assertIsNotNone(xhttp)
        self.assertIn("unsupported transport", cb.compatibility_error(xhttp))

    def test_separate_caps_for_each_whitelist_family_and_regular_catalogs(self) -> None:
        whitelist = []
        for family_index, subtype in enumerate(("mobile", "cidr_checked", "cidr_all", "sni")):
            for i in range(1, 61):
                node = cb.parse_link(
                    f"vless://{uuid_for(i + family_index * 1000)}@{subtype}{i}.example:443"
                    "?type=raw&security=reality&sni=example.com&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA#white",
                    f"Белые списки {subtype}",
                    "whitelist",
                )
                self.assertIsNotNone(node)
                node.metadata["catalog_subtype"] = subtype
                whitelist.append(node)
        regular = [
            cb.parse_link(
                f"vless://{uuid_for(i + 10000)}@regular{i}.example:443"
                "?type=tcp&security=tls&sni=example.com#regular",
                "Обычный VPN",
                "regular",
            )
            for i in range(1, 61)
        ]
        with patch.object(cb, "public_host", return_value=True):
            result = cb.build_catalog(
                [node for node in whitelist + regular if node], 50, True, 1.0
            )
        self.assertEqual(result["schema"], 3)
        self.assertEqual(result["counts"]["whitelist"], 200)
        self.assertEqual(result["whitelist_counts"], {
            "mobile": 50,
            "cidr_checked": 50,
            "cidr_all": 50,
            "sni": 50,
            "other": 0,
        })
        self.assertEqual(result["counts"]["vless"], 50)
        self.assertEqual(len(result["nodes"]), 250)

    def test_mirror_group_uses_fallback(self) -> None:
        config = {
            "sources": [
                {
                    "id": "primary",
                    "name": "primary",
                    "url": "https://example.invalid/primary",
                    "mirror_group": "same-feed",
                    "catalog_class": "whitelist",
                },
                {
                    "id": "mirror",
                    "name": "mirror",
                    "url": "https://example.invalid/mirror",
                    "mirror_group": "same-feed",
                    "catalog_class": "whitelist",
                },
            ]
        }
        link = (
            f"vless://{uuid_for(999)}@example.com:443"
            "?type=raw&security=reality&sni=example.com&pbk=AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA#mirror"
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "sources.json"
            path.write_text(json.dumps(config), encoding="utf-8")
            with patch.object(
                cb,
                "fetch",
                side_effect=[OSError("primary unavailable"), link],
            ) as mocked:
                nodes = cb.collect(path)
        self.assertEqual(mocked.call_count, 2)
        self.assertEqual(len(nodes), 1)
        self.assertEqual(nodes[0].source, "mirror")
        self.assertEqual(nodes[0].metadata["catalog_class"], "whitelist")

    def test_v2nodes_crawler_follows_country_and_server_pages(self) -> None:
        listing = '<a href="/servers/105028/">server</a><a href="?page=2">next</a>'
        detail = (
            f"<code>vless://{uuid_for(77)}@fr.example:443"
            "?type=grpc&security=tls&sni=fr.example#France</code>"
        )
        with patch.object(cb, "fetch", side_effect=[listing, "", detail]):
            found = cb.crawl_v2nodes("https://ru.v2nodes.com/country/fr/", 2)
        self.assertTrue(any("vless://" in link for link, _ in found))


if __name__ == "__main__":
    unittest.main()
