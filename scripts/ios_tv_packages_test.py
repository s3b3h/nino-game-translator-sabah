#!/usr/bin/env python3
"""Nino: iPhone derlemesinin TV paketleri (scripts/ios-tv-packages.sh) dist/tv-app'ten gelir, CouchSubs'tan inmez."""

import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "ios-tv-packages.sh"


class IosTvPackageTests(unittest.TestCase):
    def run_build(self, with_dist: bool):
        temp = Path(tempfile.mkdtemp(prefix="nino-ios-tv-"))
        self.addCleanup(shutil.rmtree, temp)
        home, dist, output = temp / "home", temp / "dist", temp / "output"
        cache = home / "Library" / "Caches" / "Nino" / "ios-tv-release"
        cache.mkdir(parents=True)
        dist.mkdir()
        output.mkdir()
        (cache / "couchsubs-androidtv.apk").write_bytes(b"previous-apk")
        (cache / "couchsubs-lg.ipk").write_bytes(b"previous-ipk")
        (cache / "release.properties").write_text("release=nino-0.9.1\ncouchsubs-androidtv.apk=old.apk\n", encoding="utf-8")
        if with_dist:
            with zipfile.ZipFile(dist / "couchsubs-androidtv_0.9.30.apk", "w") as archive:
                archive.writestr("AndroidManifest.xml", b"")
            (dist / "com.couchsubs.tv_0.9.30_all.ipk").write_bytes(b"new-ipk")
        env = dict(os.environ, HOME=str(home), NINO_TV_DIST=str(dist))
        env.pop("COUCHSUBS_REQUIRE_TV_PACKAGES", None)
        result = subprocess.run(["/bin/sh", str(SCRIPT), str(output)], cwd=str(ROOT), env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return cache, output / "tv", result

    def test_packages_come_from_dist(self):
        cache, out, _ = self.run_build(with_dist=True)
        self.assertEqual((out / "couchsubs-lg.ipk").read_bytes(), b"new-ipk")
        props = (out / "tv-packages.properties").read_text(encoding="utf-8")
        self.assertIn("release=nino-0.9.30", props)
        self.assertIn("couchsubs-androidtv.apk=couchsubs-androidtv_0.9.30.apk", props)
        self.assertIn("couchsubs-lg.ipk=com.couchsubs.tv_0.9.30_all.ipk", props)
        self.assertTrue((out / "couchsubs-samsung.wgt").exists())

    def test_without_dist_previous_copy_is_kept(self):
        cache, out, result = self.run_build(with_dist=False)
        self.assertEqual((out / "couchsubs-lg.ipk").read_bytes(), b"previous-ipk")
        self.assertIn("release=nino-0.9.1", (out / "tv-packages.properties").read_text(encoding="utf-8"))
        self.assertIn("önceki kopya", result.stdout)

    def test_never_downloads_from_couchsubs(self):
        self.assertNotIn("yorulmazsinan/couchsubs", SCRIPT.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
