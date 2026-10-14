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


class CalendarSyncTest(unittest.TestCase):
    def test_failing_sync_is_unavailable_so_fallback_fires(self):
        cal = brief.calendar_result([{"summary": "old"}], ["Google (error 11294)"])
        self.assertFalse(cal["available"])
        self.assertIn("11294", cal["reason"])
        self.assertIn("fallback", brief.with_fallbacks(
            {"email": {"available": True}, "texts": {"available": True},
             "calendar": cal})["calendar"])

    def test_healthy_sync_is_available(self):
        self.assertTrue(brief.calendar_result([], [])["available"])


if __name__ == "__main__":
    unittest.main()
