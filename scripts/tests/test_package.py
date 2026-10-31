#!/usr/bin/env python3
"""Unit tests for scripts/package.py: the minimum macOS a packaged bundle can claim and how warnings are shown."""
from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import check_licenses  # noqa: E402
import notices  # noqa: E402
import package  # noqa: E402


class RaisedMinimumTests(unittest.TestCase):
    def test_libraries_at_or_below_the_target_keep_it(self):
        floor, newer = package.raised_minimum("15.0", {"liblz4.1.dylib": "14.0", "libqjs.0.dylib": "15.0"})
        self.assertEqual(floor, "15.0")
        self.assertEqual(newer, {})

    def test_the_newest_library_sets_the_floor(self):
        floor, newer = package.raised_minimum("15.0", {"libqjs.0.dylib": "26.0", "libfreetype.6.dylib": "27.0", "liblz4.1.dylib": "14.0"})
        self.assertEqual(floor, "27.0")
        self.assertEqual(newer, {"libqjs.0.dylib": "26.0", "libfreetype.6.dylib": "27.0"})

    def test_versions_compare_numerically(self):
        floor, newer = package.raised_minimum("15.0", {"libfreetype.6.dylib": "15.10"})
        self.assertEqual(floor, "15.10")
        self.assertEqual(list(newer), ["libfreetype.6.dylib"])


class ResolveLibrariesTests(unittest.TestCase):
    """The Homebrew closure the app bundles, read from fake load commands."""

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        root = Path(self.scratch.name).resolve()
        self.prefix = root / "homebrew"
        self.app = root / "build/WallpaperMachine.app/Contents/MacOS/WallpaperMachine"
        self.freetype = self.prefix / "opt/freetype/lib/libfreetype.6.dylib"
        self.decoder = self.prefix / "opt/brotli/lib/libbrotlidec.1.dylib"
        self.common = self.prefix / "opt/brotli/lib/libbrotlicommon.1.dylib"
        for file in (self.app, self.freetype, self.decoder, self.common):
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(b"")
        self.loads = {
            self.app: [str(self.freetype), "@rpath/libswiftCore.dylib"],
            self.freetype: [str(self.decoder)],
            # brotli's decoder loads its sibling through @rpath and its own @loader_path rpath.
            self.decoder: ["@rpath/libbrotlicommon.1.dylib"],
            self.common: [],
        }
        self.rpaths = {self.decoder: ["@loader_path/../lib"]}

    def tearDown(self):
        self.scratch.cleanup()

    def resolve(self):
        with mock.patch.object(package, "dependencies", lambda file: self.loads[Path(file).resolve()]), \
             mock.patch.object(package, "rpaths", lambda file: self.rpaths.get(Path(file).resolve(), [])):
            return package.resolve_libraries([self.app], [], self.prefix)

    def test_a_keg_library_loaded_through_its_own_rpath_is_bundled(self):
        libraries = self.resolve()
        self.assertEqual(sorted(libraries), ["libbrotlicommon.1.dylib", "libbrotlidec.1.dylib", "libfreetype.6.dylib"])
        self.assertEqual(libraries["libbrotlicommon.1.dylib"], self.common.resolve())

    def test_an_app_already_relocated_by_an_earlier_run_is_refused(self):
        self.loads[self.app] = ["@rpath/libfreetype.6.dylib"]
        with self.assertRaisesRegex(package.PackagingError, "fresh, unrelocated"):
            self.resolve()

    def test_an_rpath_that_leaves_the_homebrew_prefix_is_not_followed(self):
        outside = Path(self.scratch.name).resolve() / "elsewhere/lib"
        outside.mkdir(parents=True)
        (outside / "libbrotlicommon.1.dylib").write_bytes(b"")
        self.rpaths[self.decoder] = [str(outside)]
        with self.assertRaisesRegex(package.PackagingError, "libbrotlicommon"):
            self.resolve()


class ReportTests(unittest.TestCase):
    def test_a_warning_seen_by_both_the_bundle_and_the_image_check_prints_once(self):
        reported = set()
        with contextlib.redirect_stdout(io.StringIO()) as output:
            package.report(["extension adds get-task-allow"], reported)
            package.report(["extension adds get-task-allow", "image adds another key"], reported)
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 2)
        self.assertTrue(lines[0].endswith("extension adds get-task-allow"))
        self.assertTrue(lines[1].endswith("image adds another key"))


def noticeset(*, missing=()):
    found = [notices.Notice("cfg-if", "1.0.4", "MIT", ("MIT",), "cargo registry", (("LICENSE-MIT", "MIT text"),))]
    absent = [notices.Notice(name, "1.0.0", "MIT", ("MIT",), "cargo registry", (), ("MIT",)) for name in missing]
    result = notices.NoticeSet(found + absent)
    result.text = "THIRD-PARTY NOTICES\n"
    return result


class ThirdPartyNoticesTests(unittest.TestCase):
    def generate(self, require=False, **patch):
        patch = patch or {"return_value": noticeset()}
        with mock.patch.object(notices, "generate", **patch) as generate, \
                mock.patch.object(check_licenses, "cargo_environment", return_value={}), \
                contextlib.redirect_stdout(io.StringIO()) as stdout:
            text = package.third_party_notices(Path("/nonexistent/WallpaperMachine.app"), require)
        return text, stdout.getvalue(), generate

    def test_the_generated_text_is_returned_for_the_bundle(self):
        text, stdout, generate = self.generate()
        self.assertEqual(text, "THIRD-PARTY NOTICES\n")
        self.assertIn("1 components, 1 with license text, 0 without", stdout)
        self.assertEqual(generate.call_args.args[0].app, Path("/nonexistent/WallpaperMachine.app"))

    def test_a_tool_failure_stops_packaging(self):
        with self.assertRaisesRegex(package.PackagingError, "could not be generated: cargo tree failed"):
            self.generate(side_effect=check_licenses.ToolError("cargo tree failed"))

    def test_an_empty_closure_stops_packaging(self):
        with self.assertRaisesRegex(package.PackagingError, "closure is empty"):
            self.generate(return_value=notices.NoticeSet([]))

    def test_a_missing_license_text_is_named_and_does_not_stop_packaging_by_default(self):
        text, stdout, _ = self.generate(return_value=noticeset(missing=["objc2", "uniffi"]))
        self.assertEqual(text, "THIRD-PARTY NOTICES\n")
        self.assertIn("LICENSE TEXT NOT FOUND for 2 of 3 components: objc2 1.0.0, uniffi 1.0.0", stdout)

    def test_a_missing_license_text_stops_packaging_when_required(self):
        with self.assertRaisesRegex(package.PackagingError, "LICENSE TEXT NOT FOUND for 1 of 2 components: objc2 1.0.0"):
            self.generate(True, return_value=noticeset(missing=["objc2"]))


class WriteLicensesTests(unittest.TestCase):
    def test_the_notices_file_lands_in_resources_and_replaces_an_older_one(self):
        with tempfile.TemporaryDirectory() as directory:
            resources = Path(directory)
            (resources / "THIRD-PARTY-NOTICES.txt").write_text("old")
            package.write_licenses(resources, {}, "new notices\n")
            self.assertEqual((resources / "THIRD-PARTY-NOTICES.txt").read_text(), "new notices\n")
            self.assertTrue((resources / "LICENSING.md").is_file())


if __name__ == "__main__":
    unittest.main()
