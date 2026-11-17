# poolpack.py denemeleri: ağ ve API yok. Çalıştırma: python3 -m unittest tools/packs/test_poolpack.py
import json, sys, tempfile, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import poolpack as pp


class PoolPackTests(unittest.TestCase):
    def test_query_is_read_only_and_escaped(self):
        sql = pp.query_sql(title="ppsa12345", game="Grand Theft_Auto's 100%")
        self.assertTrue(sql.startswith("SELECT"))
        self.assertIn("title_id = 'PPSA12345'", sql)
        self.assertIn("'%Grand Theft^_Auto''s 100^%%' ESCAPE '^'", sql)
        self.assertIn("exported = 0", sql)
        command = pp.wrangler(sql)
        self.assertIn('--remote --json --command "SELECT', command)
        self.assertIn("'", pp.wrangler('SELECT "x"').split("--command ")[1][0])
        with self.assertRaises(SystemExit):
            pp.query_sql(title="x'; DELETE FROM lines; --")
        with self.assertRaises(SystemExit):
            pp.query_sql()
        with self.assertRaises(AssertionError):
            pp.wrangler("DELETE FROM lines")

    def test_clean_merges_sorts_and_drops_noise(self):
        rows = [
            {"text": "LUCIA: Get in the car, Jason.", "installs": 3},
            {"text": "Get in the car, Jason!", "installs": 4},
            {"text": "Keep your head down.", "installs": 9},
            {"text": "Oturum Açtı şimdi", "installs": 50},
            {"text": "We need ou$3e now", "installs": 50},
            {"text": "Hold", "installs": 50},
            {"text": "Already in a pack.", "installs": 50},
        ]
        known = {pp.c.key("Already in a pack.")}
        out, dropped = pp.clean(rows, known)
        self.assertEqual([r["text"] for r in out], ["Keep your head down.", "Get in the car, Jason."])
        self.assertEqual(out[1]["installs"], 7)
        self.assertEqual(out[1]["speaker"], "LUCIA")
        self.assertEqual(out[1]["raw"], "LUCIA: Get in the car, Jason.")
        self.assertEqual(dropped, {"bozuk": 1, "türkçe": 1, "kısa": 1, "pakette": 1})

    def test_reads_wrangler_and_export_formats(self):
        with tempfile.TemporaryDirectory() as d:
            a, b = Path(d) / "a.json", Path(d) / "b.json"
            a.write_text(json.dumps([{"results": [{"text": "One two.", "installs": 2}], "success": True}]))
            b.write_text(json.dumps({"lines": [{"text": "One two.", "installs": 2}]}))
            self.assertEqual(pp.load_export(a), pp.load_export(b))

    def test_dry_run_never_translates(self):
        with tempfile.TemporaryDirectory() as d:
            export = Path(d) / "pool.json"
            export.write_text(json.dumps({"lines": [{"text": "Keep your head down, Jason.", "installs": 5}]}))
            pp.main(["plan", str(export), "--id", "gta-6", "--out-dir", d])
            self.assertTrue((Path(d) / "gta-6.rows.jsonl").is_file())
            self.assertFalse((Path(d) / "gta-6.tr.json").exists())
            self.assertNotIn("llm", sys.modules)
            with self.assertRaises(SystemExit):
                pp.main(["plan", str(export), "--id", "gta-6", "--out-dir", d, "--translate"])
            self.assertNotIn("llm", sys.modules)

    def test_estimate_and_prompt(self):
        e = pp.estimate([{"text": "Keep your head down. Get in the car."}] * 80, 3000)
        self.assertEqual(e["chunks"], 2)
        self.assertEqual(e["sentences"], 160)
        self.assertLess(e["usd"][0], e["usd"][1])
        prompt = pp.system_prompt(str(Path(pp.HERE) / "glossary/gta6.json"))
        self.assertIn("Vice City", prompt)
        self.assertIn("dude = ahbap", prompt)
        self.assertIn("Output only the requested JSON.", prompt)


if __name__ == "__main__":
    unittest.main()
