#!/usr/bin/env python3
"""Unit tests for the generated-scene pixel criteria in scripts/check_renderer.py."""
from __future__ import annotations

import importlib.util
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("check_renderer", SCRIPTS / "check_renderer.py")
check_renderer = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(check_renderer)

WIDTH, HEIGHT = 384, 256
MARGIN = bytes((26, 51, 77))
PAGE = bytes((255, 255, 255))
# The paused parent timeline holds the third corner on its first key; leaving it
# on the constant value is the defect the fixture has to make visible.
AUTHORED = [(0.25, 0.5), (0.75, 0.375), (0.875, 0.875), (0.375, 1.0)]
STATIC_CORNER = [(0.25, 0.5), (0.75, 0.375), (0.375, 0.875), (0.375, 1.0)]


def ppm(shade):
    """Render a 384x256 P6 frame the way the probe writes one."""
    body = bytearray()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            body += shade((x + 0.5) / WIDTH, (y + 0.5) / HEIGHT)
    return b"P6\n%d %d\n255\n" % (WIDTH, HEIGHT) + bytes(body)


def quad_mask(corners):
    """The square-to-quad homography the fixture shader inverts per fragment."""
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = corners
    sx, sy = x0 - x1 + x2 - x3, y0 - y1 + y2 - y3
    dx1, dy1 = x1 - x2, y1 - y2
    dx2, dy2 = x3 - x2, y3 - y2
    basis = dx1 * dy2 - dx2 * dy1
    g = (sx * dy2 - dx2 * sy) / basis
    h = (dx1 * sy - sx * dy1) / basis
    a, b, c = x1 - x0 + g * x1, x3 - x0 + h * x3, x0
    d, e, f = y1 - y0 + g * y1, y3 - y0 + h * y3, y0
    det = a * (e - f * h) - b * (d - f * g) + c * (d * h - e * g)
    rows = [[value / det for value in row] for row in
            [[e - f * h, c * h - b, b * f - c * e],
             [f * g - d, a - c * g, c * d - a * f],
             [d * h - e * g, b * g - a * h, a * e - b * d]]]

    def shade(u, v):
        point = (u, v, 1.0)
        w = sum(factor * value for factor, value in zip(rows[2], point))
        if w <= 0.0:
            return MARGIN
        square = [sum(factor * value for factor, value in zip(row, point)) / w for row in rows[:2]]
        return PAGE if all(0.0 <= value <= 1.0 for value in square) else MARGIN

    return shade


class PerspectiveCornerPixelTests(unittest.TestCase):
    def test_accepts_the_page_drawn_from_the_authored_first_key(self):
        self.assertTrue(check_renderer.check_generated_pixels(ppm(quad_mask(AUTHORED)), 9))

    def test_rejects_the_wedge_left_by_the_unanimated_corner(self):
        self.assertFalse(check_renderer.check_generated_pixels(ppm(quad_mask(STATIC_CORNER)), 9))

    def test_rejects_frames_with_no_page_and_frames_that_are_only_page(self):
        for fill in [MARGIN, PAGE]:
            with self.subTest(fill=fill):
                self.assertFalse(
                    check_renderer.check_generated_pixels(ppm(lambda u, v, c=fill: c), 9))

    def test_rejects_the_right_page_over_the_wrong_background(self):
        # A correct page over a cleared-to-black or recoloured target is still a
        # broken frame, so matching the two margins to each other is not enough.
        for wrong in [bytes((0, 0, 0)), bytes((26, 51, 180))]:
            with self.subTest(background=wrong):
                page = quad_mask(AUTHORED)
                shade = lambda u, v: PAGE if page(u, v) == PAGE else wrong
                self.assertFalse(check_renderer.check_generated_pixels(ppm(shade), 9))


@unittest.skipUnless(sys.platform == "darwin", "Metal-device capability probe requires the macOS SDK")
class GPUAvailabilityProbeTests(unittest.TestCase):
    def test_compiled_probe_distinguishes_device_presence_without_rendering(self):
        with tempfile.TemporaryDirectory() as directory:
            result = check_renderer.gpu_preflight(Path(directory), dict(check_renderer.os.environ))
            log = (Path(directory) / "gpu-compile_exit.log").read_text()
        self.assertEqual(result["compile_exit"], 0, log)
        self.assertIn(result["probe_exit"], (0, 77))


class GateExitStatusTests(unittest.TestCase):
    def gate(self, failed=None, timeout=False, skipped=None, gpu=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "project.json"
            project.write_text('{"file":"scene.json"}')
            calls = []

            def run(command, log, env, *args):
                name = Path(command[0]).name
                calls.append(name)
                log.write_text("[  SKIPPED ] unavailable fixture codec\n" if name == skipped else "")
                if name in ("xcrun", "gpu-availability"):
                    result = gpu[0 if name == "xcrun" else 1]
                    if result == "timeout":
                        raise check_renderer.subprocess.TimeoutExpired(command, 1)
                    return result
                if name == failed:
                    if timeout:
                        raise check_renderer.subprocess.TimeoutExpired(command, 1)
                    return 1
                if name == check_renderer.OFFSCREEN_PROBE:
                    output = Path(env["WE_TEST_OUTPUT"])
                    output.mkdir(parents=True)
                    (output / "frame-2.ppm").write_bytes(b"same synthetic pixels")
                return 0

            with contextlib.ExitStack() as stack:
                stack.enter_context(patch.object(check_renderer, "RENDERER_ARTIFACTS", root / "evidence"))
                stack.enter_context(patch.object(check_renderer, "build_environment", return_value={}))
                stack.enter_context(patch.object(check_renderer, "run", side_effect=run))
                stack.enter_context(patch.object(check_renderer, "fixtures", return_value=[]))
                for name in ("alpha_composite_fixture", "perspective_animation_fixture"):
                    stack.enter_context(patch.object(check_renderer, name, return_value=project))
                stack.enter_context(patch.object(check_renderer, "check_generated_pixels", return_value=True))
                output = io.StringIO()
                stack.enter_context(contextlib.redirect_stdout(output))
                arguments = ["--skip-build", "--assets", str(root / "assets")]
                if gpu is not None:
                    arguments.append("--allow-missing-gpu")
                status = check_renderer.main(arguments)
                self.last_output = output.getvalue()
            report = json.loads(next((root / "evidence").glob("*/report.json")).read_text())
            return status, report, calls

    def test_each_required_binary_failure_and_timeout_fail_the_gate(self):
        for binary in (*check_renderer.REGRESSION_BINARIES, check_renderer.RELOAD_PROBE):
            for timeout in (False, True):
                with self.subTest(binary=binary, timeout=timeout):
                    status, report, calls = self.gate(binary, timeout)
                    self.assertEqual(status, 1)
                    self.assertEqual(report[binary], "timeout" if timeout else 1)
                    self.assertIn(check_renderer.RELOAD_PROBE, calls)

    def test_all_successful_binaries_and_pixel_checks_pass(self):
        status, report, calls = self.gate()
        self.assertEqual(status, 0)
        self.assertTrue(all(report[name] == 0 for name in check_renderer.REGRESSION_BINARIES))
        self.assertTrue(all(case["pixels_equal"] for case in report["cases"]))

    def test_skip_reason_is_reported_separately_from_successful_exit(self):
        binary = next(iter(check_renderer.REGRESSION_BINARIES))
        status, report, _ = self.gate(skipped=binary)
        self.assertEqual(status, 0)
        self.assertEqual(report[binary], 0)
        self.assertEqual(report["skips"][binary], ["[  SKIPPED ] unavailable fixture codec"])

    def test_available_gpu_runs_every_registered_target_and_image_probe(self):
        status, report, calls = self.gate(gpu=(0, 0))
        self.assertEqual(status, 0)
        self.assertTrue(report["gpu_checks_executed"])
        self.assertTrue(set(check_renderer.REGRESSION_BINARIES).issubset(calls))
        self.assertIn(check_renderer.OFFSCREEN_PROBE, calls)

    def test_only_explicit_no_device_skips_exact_gpu_targets_and_warns(self):
        status, report, calls = self.gate(gpu=(0, 77))
        self.assertEqual(status, 0)
        expected = {name for name, needed in check_renderer.REGRESSION_BINARIES.items() if needed}
        expected.update([check_renderer.OFFSCREEN_PROBE, check_renderer.RELOAD_PROBE])
        self.assertEqual(set(report["skips"]), expected)
        self.assertTrue(expected.isdisjoint(calls))
        self.assertTrue({name for name, needed in check_renderer.REGRESSION_BINARIES.items() if not needed}.issubset(calls))
        self.assertFalse(report["gpu_checks_executed"])
        self.assertIn("::warning::", self.last_output)
        for target in expected:
            self.assertIn(target, self.last_output)

    def test_preflight_compilation_failure_is_a_failure_not_a_skip(self):
        status, report, calls = self.gate(gpu=(1, None))
        self.assertEqual(status, 1)
        self.assertEqual(report["gpu_preflight"]["compile_exit"], 1)
        self.assertEqual(report["skips"], {})
        self.assertNotIn("gpu-availability", calls)

    def test_abnormal_or_timed_out_preflight_is_a_failure_not_a_skip(self):
        for result in (1, 2, "timeout"):
            with self.subTest(result=result):
                status, report, _ = self.gate(gpu=(0, result))
                self.assertEqual(status, 1)
                self.assertEqual(report["gpu_preflight"]["probe_exit"], result)
                self.assertEqual(report["skips"], {})

    def test_started_gpu_failure_and_cpu_failure_without_gpu_still_fail(self):
        gpu_test = next(name for name, needed in check_renderer.REGRESSION_BINARIES.items() if needed)
        cpu_test = next(name for name, needed in check_renderer.REGRESSION_BINARIES.items() if not needed)
        for target, probe in ((gpu_test, (0, 0)), (cpu_test, (0, 77))):
            with self.subTest(target=target):
                status, report, _ = self.gate(failed=target, gpu=probe)
                self.assertEqual(status, 1)
                self.assertEqual(report[target], 1)
                self.assertNotIn(target, report["skips"])

    def test_image_probe_failure_or_timeout_is_not_a_missing_gpu_skip(self):
        for timeout in (False, True):
            with self.subTest(timeout=timeout):
                status, report, _ = self.gate(failed=check_renderer.OFFSCREEN_PROBE, timeout=timeout, gpu=(0, 0))
                self.assertEqual(status, 1)
                self.assertTrue(report["gpu_checks_executed"])
                self.assertFalse(any(case["pixels_equal"] for case in report["cases"]))
                self.assertNotIn(check_renderer.OFFSCREEN_PROBE, report["skips"])


if __name__ == "__main__":
    unittest.main()
