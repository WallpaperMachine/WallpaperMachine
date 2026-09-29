#!/usr/bin/env python3
"""Unit tests for scripts/update_sponsors.py."""
from __future__ import annotations

import http.server
import importlib.util
import json
import sys
import threading
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("update_sponsors", SCRIPTS / "update_sponsors.py")
update_sponsors = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(update_sponsors)

Wall = update_sponsors.Wall

README = f"""# Title

## Thank you. To every Supporter.

Intro.

{update_sponsors.START}
No one is on the list yet.
{update_sponsors.END}

## License
"""


class ParseWallTests(unittest.TestCase):
    def test_reads_names_in_order_and_the_private_count(self):
        wall = update_sponsors.parse_wall(
            {"supporters": [{"name": "Alice", "since": "2026-09"}, {"name": "张三", "since": None}], "hidden": 2}
        )
        self.assertEqual(wall, Wall(("Alice", "张三"), 2))

    def test_collapses_whitespace_and_drops_invisible_characters(self):
        wall = update_sponsors.parse_wall(
            {"supporters": [{"name": "  A​l‮ice \n\t Smith "}, {"name": "​ "}], "hidden": 0}
        )
        self.assertEqual(wall.names, ("Alice Smith",))

    def test_rejects_answers_that_are_not_the_wall(self):
        for payload in (
            [],
            {"hidden": 0},
            {"supporters": {}, "hidden": 0},
            {"supporters": [], "hidden": -1},
            {"supporters": [], "hidden": True},
            {"supporters": [], "hidden": "1"},
            {"supporters": [{"name": 3}], "hidden": 0},
            {"supporters": ["Alice"], "hidden": 0},
        ):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                update_sponsors.parse_wall(payload)


class RenderTests(unittest.TestCase):
    def test_empty_wall(self):
        block = update_sponsors.render(Wall((), 0))
        self.assertIn("No one is on the list yet.", block)
        self.assertNotIn("<p", block)

    def test_only_private_supporters_are_counted_not_named(self):
        block = update_sponsors.render(Wall((), 3))
        self.assertIn("3 Supporters so far, all private.", block)

    def test_listed_supporters_are_named_with_the_private_count(self):
        block = update_sponsors.render(Wall(("Alice", "Bob"), 1))
        self.assertIn("Alice&ensp;·&ensp;Bob", block)
        self.assertIn("2 Supporters on the list. 1 more supports privately.", block)
        self.assertEqual(update_sponsors.count_line(Wall(("Alice",), 0)), "1 Supporter on the list.")

    def test_a_name_can_never_become_markup(self):
        hostile = f"[x](https://evil) <img src=x> ![i](y) *b* `c` {update_sponsors.END}"
        block = update_sponsors.render(Wall((hostile,), 0))
        names = block.splitlines()[2]
        for text in ("<", ">", "[", "]", "(", ")", "*", "`", "!"):
            self.assertNotIn(text, names)
        # The markers still delimit exactly one block, so the next run finds it.
        self.assertEqual(block.count(update_sponsors.END), 1)
        self.assertEqual(update_sponsors.BLOCK.fullmatch(block).group(), block)
        once = update_sponsors.rewrite(README, Wall((hostile,), 0))
        self.assertEqual(update_sponsors.rewrite(once, Wall((), 0)), README)


class RewriteTests(unittest.TestCase):
    def test_replaces_only_the_block(self):
        after = update_sponsors.rewrite(README, Wall(("Alice",), 0))
        self.assertIn("Alice", after)
        self.assertNotIn("No one is on the list yet.", after)
        before_block, after_block = README.split(update_sponsors.START)[0], README.split(update_sponsors.END)[1]
        self.assertTrue(after.startswith(before_block))
        self.assertTrue(after.endswith(after_block))

    def test_is_idempotent(self):
        once = update_sponsors.rewrite(README, Wall(("Alice", "Bob"), 2))
        self.assertEqual(update_sponsors.rewrite(once, Wall(("Alice", "Bob"), 2)), once)
        self.assertEqual(update_sponsors.rewrite(once, Wall((), 0)), README)

    def test_refuses_a_readme_without_exactly_one_block(self):
        for text in ("# Title\n", README + README):
            with self.subTest(blocks=text.count("supporters:start")), self.assertRaises(ValueError):
                update_sponsors.rewrite(text, Wall((), 0))

    def test_the_repository_readme_has_the_block(self):
        update_sponsors.rewrite(update_sponsors.README.read_text(encoding="utf-8"), Wall((), 0))


class FetchTests(unittest.TestCase):
    def serve(self, status, body):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *args):
                pass

        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_port}/api/sponsors"

    def test_reads_the_wall(self):
        url = self.serve(200, json.dumps({"supporters": [{"name": "Alice"}], "hidden": 1}).encode())
        self.assertEqual(update_sponsors.fetch_wall(url), Wall(("Alice",), 1))

    def test_a_page_that_is_not_json_is_an_error(self):
        url = self.serve(200, b"<!doctype html><title>Just a moment...</title>")
        with self.assertRaises(ValueError):
            update_sponsors.fetch_wall(url)

    def test_an_error_status_is_an_error(self):
        url = self.serve(500, b'{"error":"server_error"}')
        with self.assertRaises(update_sponsors.urllib.error.HTTPError):
            update_sponsors.fetch_wall(url)


if __name__ == "__main__":
    unittest.main()
