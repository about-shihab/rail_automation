import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
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
        for value in ['http://example.com', 'https://github.com/private', 'https://token@example.com']:
            with self.assertRaises(ValueError):
                release.public_url(value)


if __name__ == '__main__':
    unittest.main()
