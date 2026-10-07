import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import io
import json
import tempfile
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def run_prepare(self, responses):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('version: 1.0.1+2\n')
            args = SimpleNamespace(site_url='https://about-shihab.github.io/rail-pro',
                                   release_repo='about-shihab/rail-pro', force=False,
                                   previous_manifest_url='https://old.example/update.json')
            def fetch(request, **kwargs):
                item = responses.pop(0)
                if isinstance(item, Exception):
                    raise item
                return io.BytesIO(json.dumps(item).encode())
            with patch.object(release, 'ROOT', root), patch.object(release, 'urlopen', side_effect=fetch):
                release.prepare(args)
            return json.loads((root / 'build/release-plan.json').read_text())

    def test_migration_preserves_previous_public_build(self):
        missing = HTTPError('https://example.com', 404, 'Missing', {}, None)
        result = self.run_prepare([missing, missing, {
            'version': '1.0.5', 'build_number': 6, 'minimum_build_number': 5,
        }])
        self.assertEqual(result['version'], '1.0.6')
        self.assertEqual(result['build_number'], 7)
        self.assertEqual(result['minimum_build_number'], 5)
        self.assertEqual(result['apk_url'],
                         'https://github.com/about-shihab/rail-pro/releases/latest/download/Rail-Pro.apk')

    def test_release_asset_prevents_reuse_when_pages_is_behind(self):
        responses = [
            {'version': '1.0.8', 'build_number': 20, 'minimum_build_number': 18},
            {'version': '1.0.9', 'build_number': 21, 'minimum_build_number': 21},
        ]
        result = self.run_prepare(responses)
        self.assertEqual(result['version'], '1.0.10')
        self.assertEqual(result['build_number'], 22)
        self.assertEqual(result['minimum_build_number'], 21)
        self.assertEqual(responses, [])  # Old hosting is no longer queried.

    def test_distribution_outage_aborts_version_allocation(self):
        with self.assertRaises(HTTPError):
            self.run_prepare([HTTPError('https://example.com', 503, 'Unavailable', {}, None)])

    def test_local_apk_build_is_not_reused_before_first_public_deployment(self):
        baseline = release.local_baseline('1.0.1+2', {'version': '1.0.2', 'build_number': 3})
        self.assertEqual(release.next_release(baseline)['build_number'], 4)
        self.assertEqual(release.next_release(baseline)['version'], '1.0.3')

    def test_initial_release_increments_existing_app(self):
        self.assertEqual(release.next_release('1.0.1+2'), {
            'version': '1.0.2', 'build_number': 3, 'minimum_build_number': 0})

    def test_published_version_is_authoritative_and_minimum_is_preserved(self):
        previous = {'version': '1.0.8', 'build_number': 20, 'minimum_build_number': 18}
        self.assertEqual(release.next_release('1.0.1+2', previous), {
            'version': '1.0.9', 'build_number': 21, 'minimum_build_number': 18})

    def test_force_update_targets_the_newly_published_build(self):
        self.assertEqual(release.next_release('1.0.1+2', force=True)['minimum_build_number'], 3)

    def test_a_new_minor_baseline_keeps_the_build_monotonic(self):
        result = release.next_release('1.1.0+3', {
            'version': '1.0.8', 'build_number': 20, 'minimum_build_number': 18})
        self.assertEqual(result['version'], '1.1.1')
        self.assertEqual(result['build_number'], 21)

    def test_private_or_insecure_download_hosts_are_rejected(self):
        for value in ['http://example.com', 'https://token@example.com', 'ftp://example.com']:
            with self.assertRaises(ValueError):
                release.public_url(value)
        self.assertEqual(
            release.public_url('https://github.com/about-shihab/rail_automation'),
            'https://github.com/about-shihab/rail_automation'
        )


if __name__ == '__main__':
    unittest.main()
