import datetime
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

from prepare_ios_release import prepare


class SigningOptionsTest(unittest.TestCase):
    def test_managed_and_manual_app_store_profiles(self):
        for managed in (True, False):
            with self.subTest(managed=managed), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root / 'ios/Runner').mkdir(parents=True)
                (root / 'ios/Runner/Info.plist').write_bytes(plistlib.dumps({}))
                (root / 'systock.mobileprovision').write_bytes(b'fixture')
                profile = {
                    'TeamIdentifier': ['TEAM'], 'UUID': 'PROFILE',
                    'IsXcodeManaged': managed,
                    'ExpirationDate': datetime.datetime(2099, 1, 1),
                    'Entitlements': {
                        'application-identifier': 'TEAM.mz.ladans.systock',
                        'beta-reports-active': True,
                    },
                }
                environment = {
                    'RUNNER_TEMP': folder, 'GITHUB_ENV': str(root / 'env'),
                    'GOOGLE_IOS_CLIENT_ID': 'test.apps.googleusercontent.com',
                }
                previous = Path.cwd()
                try:
                    os.chdir(root)
                    with patch.dict(os.environ, environment), \
                            patch('prepare_ios_release.Path.home', return_value=root), \
                            patch('prepare_ios_release.subprocess.check_output', return_value=plistlib.dumps(profile)):
                        prepare()
                    options = plistlib.loads((root / 'ExportOptions.plist').read_bytes())
                    self.assertEqual(options['method'], 'app-store-connect')
                    self.assertEqual(options['teamID'], 'TEAM')
                    if managed:
                        self.assertEqual(options['signingStyle'], 'automatic')
                        self.assertNotIn('provisioningProfiles', options)
                    else:
                        self.assertEqual(options['signingStyle'], 'manual')
                        self.assertEqual(options['provisioningProfiles'], {'mz.ladans.systock': 'PROFILE'})
                finally:
                    os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
