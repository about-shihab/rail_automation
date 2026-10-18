import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location('publish_github', Path(__file__).parents[1] / 'publish_github.py')
publish_github = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish_github)


class PublishGithubTests(unittest.TestCase):
    def test_publish_ipa_requires_ipa_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.object(publish_github, 'ROOT', root), \
                 patch.object(publish_github, 'github_token', return_value='fake_token'), \
                 patch.object(publish_github, 'api', return_value={'private': False}):
                with self.assertRaises(FileNotFoundError):
                    publish_github.publish_ipa('test/repo')

    def test_publish_ipa_uploads_to_existing_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ipa_dir = root / 'build/ios/ipa'
            ipa_dir.mkdir(parents=True)
            ipa_file = ipa_dir / 'RailPro.ipa'
            ipa_file.write_bytes(b'PK_FAKE_IPA_DATA')

            api_calls = []

            def fake_api(token, path, method='GET', data=None, content_type='application/json'):
                api_calls.append((path, method, content_type))
                if path == 'repos/test/repo':
                    return {'private': False, 'default_branch': 'main'}
                elif path == 'repos/test/repo/releases/latest':
                    return {
                        'id': 12345,
                        'tag_name': 'v1.0.3',
                        'upload_url': 'https://uploads.github.com/repos/test/repo/releases/12345/assets{?name,label}',
                        'assets': [{'id': 999, 'name': 'RailPro.ipa'}]
                    }
                elif path == 'repos/test/repo/releases/assets/999':
                    return None
                elif 'RailPro.ipa' in path:
                    return {'id': 1000, 'name': 'RailPro.ipa'}
                return {}

            with patch.object(publish_github, 'ROOT', root), \
                 patch.object(publish_github, 'github_token', return_value='fake_token'), \
                 patch.object(publish_github, 'api', side_effect=fake_api):
                publish_github.publish_ipa('test/repo')

            # Verify existing asset was deleted before uploading new one
            deleted = any(call[0] == 'repos/test/repo/releases/assets/999' and call[1] == 'DELETE' for call in api_calls)
            self.assertTrue(deleted)

            # Verify upload call
            uploaded = any('RailPro.ipa' in call[0] and call[1] == 'POST' for call in api_calls)
            self.assertTrue(uploaded)


if __name__ == '__main__':
    unittest.main()
