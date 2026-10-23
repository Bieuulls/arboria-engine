import unittest
import tempfile
import json
from pathlib import Path

from tools.arboria_ai.bench import checked_metrics, compare

class TestBenchmarkMetricsStrict(unittest.TestCase):

    def test_reject_zero_gpu_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "metrics.json"
            p.write_text(json.dumps({
                "gpu_p95_ms": 0.0,
                "frame_p95_ms": 16.6,
                "vram_mb": 150.0,
                "visible_clusters": 500,
                "visual_error": 0.0
            }))
            with self.assertRaisesRegex(ValueError, "positivos"):
                checked_metrics(p)

    def test_reject_zero_frame_time(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "metrics.json"
            p.write_text(json.dumps({
                "gpu_p95_ms": 5.0,
                "frame_p95_ms": 0.0,
                "vram_mb": 150.0,
                "visible_clusters": 500,
                "visual_error": 0.0
            }))
            with self.assertRaisesRegex(ValueError, "positivos"):
                checked_metrics(p)

    def test_reject_zero_vram(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "metrics.json"
            p.write_text(json.dumps({
                "gpu_p95_ms": 5.0,
                "frame_p95_ms": 16.0,
                "vram_mb": 0.0,
                "visible_clusters": 500,
                "visual_error": 0.0
            }))
            with self.assertRaisesRegex(ValueError, "positivos"):
                checked_metrics(p)

    def test_reject_zero_clusters(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "metrics.json"
            p.write_text(json.dumps({
                "gpu_p95_ms": 5.0,
                "frame_p95_ms": 16.0,
                "vram_mb": 150.0,
                "visible_clusters": 0,
                "visual_error": 0.0
            }))
            with self.assertRaisesRegex(ValueError, "zero clusters"):
                checked_metrics(p)

    def test_reject_negative_visual_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "metrics.json"
            p.write_text(json.dumps({
                "gpu_p95_ms": 5.0,
                "frame_p95_ms": 16.0,
                "vram_mb": 150.0,
                "visible_clusters": 100,
                "visual_error": -0.5
            }))
            with self.assertRaisesRegex(ValueError, "negativo"):
                checked_metrics(p)

    def test_reject_missing_required_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "metrics.json"
            p.write_text(json.dumps({
                "gpu_p95_ms": 5.0,
                "frame_p95_ms": 16.0
                # vram_mb, visible_clusters, visual_error missing
            }))
            with self.assertRaisesRegex(ValueError, "ausente ou inválida"):
                checked_metrics(p)

    def test_accept_strictly_valid_metrics(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "metrics.json"
            valid_data = {
                "gpu_p95_ms": 4.5,
                "frame_p95_ms": 16.2,
                "vram_mb": 128.5,
                "visible_clusters": 450,
                "visual_error": 0.0002
            }
            p.write_text(json.dumps(valid_data))
            res = checked_metrics(p)
            self.assertEqual(res["gpu_p95_ms"], 4.5)
            self.assertEqual(res["visible_clusters"], 450.0)

if __name__ == "__main__":
    unittest.main()
