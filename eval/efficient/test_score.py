import unittest
from score import covered_bytes


class CoverageTest(unittest.TestCase):
    def test_uncovered_and_clipped_intervals(self):
        gold = ("person", 10, 20)
        self.assertEqual(covered_bytes(gold, [("person", 0, 5)]), 0)
        self.assertEqual(covered_bytes(gold, [("location", 0, 15)]), 5)
        self.assertEqual(covered_bytes(gold, [("person", 0, 30)]), 10)

    def test_overlaps_are_not_counted_twice(self):
        self.assertEqual(covered_bytes(("location", 0, 10),
                         [("person", 0, 6), ("location", 4, 8), ("person", 8, 10)]), 10)

    def test_gaps_remain_uncovered(self):
        self.assertEqual(covered_bytes(("person", 0, 10),
                         [("person", 0, 3), ("person", 5, 8)]), 6)


if __name__ == "__main__":
    unittest.main()
