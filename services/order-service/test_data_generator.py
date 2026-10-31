import unittest
from unittest.mock import patch

import data_generator


class TestDataGenerator(unittest.TestCase):
    @patch("data_generator.SessionLocal")
    def test_seed_skips_existing_data(self, session_factory):
        db = session_factory.return_value
        db.query.return_value.count.return_value = 101

        data_generator.seed_db()

        db.add_all.assert_not_called()
        db.commit.assert_not_called()
        db.close.assert_called_once()

    @patch("data_generator.requests.post")
    def test_send_transaction(self, post):
        post.return_value.status_code = 200
        post.return_value.json.return_value = {"order_id": 42}

        data_generator.send_transaction(1)

        post.assert_called_once_with(data_generator.API_URL, timeout=5)
        post.return_value.json.assert_called_once()


if __name__ == "__main__":
    unittest.main()
