import unittest

from src.greeting import greet


class GreetTests(unittest.TestCase):
    def test_greets_by_name(self):
        self.assertEqual(greet("Asha"), "Hello, Asha!")


if __name__ == "__main__":
    unittest.main()
