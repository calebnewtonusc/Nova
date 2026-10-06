import os, sys, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import brief


def _brief(email, texts, calendar):
    return {"email": {"available": email}, "texts": {"available": texts},
            "calendar": {"available": calendar}}


class FallbackTest(unittest.TestCase):
    def test_every_dead_source_names_its_fallback(self):
        b = brief.with_fallbacks(_brief(False, False, False))
        for name in ("email", "texts", "calendar"):
            self.assertIn("fallback", b[name])

    def test_live_source_gets_no_fallback(self):
        b = brief.with_fallbacks(_brief(True, False, True))
        self.assertNotIn("fallback", b["email"])
        self.assertNotIn("fallback", b["calendar"])
        self.assertIn("fallback", b["texts"])


if __name__ == "__main__":
    unittest.main()
