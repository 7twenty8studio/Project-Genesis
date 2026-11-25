#!/usr/bin/env python3
"""Checks the map routes in the bundled Study.sqlite against ROUTES.

    python3 Tools/StudyData/test_routes.py
"""
import os
import sqlite3
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_study import OUTPUT, ROUTES  # noqa: E402


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(OUTPUT)

    def tearDown(self):
        self.db.close()

    def stops(self, route_id):
        return self.db.execute(
            "SELECT p.name, p.latitude, p.longitude FROM route_stops s JOIN places p ON p.id = s.place_id "
            "WHERE s.route_id = ? ORDER BY s.position", (route_id,)).fetchall()

    def test_bundled_routes_match_the_script(self):
        for route_id, title, _, _, stops in ROUTES:
            named = [s for s in stops if not isinstance(s, tuple)]
            self.assertEqual(len(self.stops(route_id)), len(named), title)
            path = self.db.execute("SELECT count(*) FROM route_path WHERE route_id = ?", (route_id,)).fetchone()[0]
            self.assertEqual(path, len(stops), title)

    def test_exodus_succoth_is_in_egypt(self):
        succoth = [s for s in self.stops("exodus") if s[0] == "Succoth"]
        self.assertEqual(len(succoth), 1)
        self.assertLess(succoth[0][2], 33)  # east of the Delta, not the Jordan valley

    def test_exodus_goes_around_edom(self):
        stops = self.stops("exodus")
        hor = next(s for s in stops if s[0] == "Mount Hor")
        path = self.db.execute("SELECT latitude, longitude FROM route_path WHERE route_id = 'exodus' ORDER BY position").fetchall()
        self.assertTrue(any(lon > hor[2] + 0.4 for _, lon in path))
        self.assertEqual(stops[-1][0], "Abel-shittim")

    def test_points_between_stops_stay_near_the_region(self):
        for route_id, title, _, _, stops in ROUTES:
            lats = [s[1] for s in self.stops(route_id)]
            lons = [s[2] for s in self.stops(route_id)]
            for point in (s for s in stops if isinstance(s, tuple)):
                self.assertTrue(min(lats) - 1 <= point[0] <= max(lats) + 1, f"{title}: {point}")
                self.assertTrue(min(lons) - 1 <= point[1] <= max(lons) + 1, f"{title}: {point}")


if __name__ == "__main__":
    unittest.main()
