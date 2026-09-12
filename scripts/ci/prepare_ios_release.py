"""Prepare App Store signing metadata and Google configuration on a CI runner."""
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


def prepare():
    temporary = Path(os.environ['RUNNER_TEMP'])
    profile = plistlib.loads(subprocess.check_output([
        'security', 'cms', '-D', '-i', str(temporary / 'systock.mobileprovision')
    ]))
    entitlements = profile['Entitlements']
    bundle_id = 'mz.ladans.systock'
    team = profile['TeamIdentifier'][0]
    if (profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices')
            or entitlements.get('get-task-allow')
            or not entitlements.get('beta-reports-active')):
        raise ValueError('Use an App Store distribution provisioning profile.')
    if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError('The provisioning profile has expired.')
    if entitlements['application-identifier'].split('.', 1)[1] != bundle_id:
        raise ValueError('The provisioning profile must match mz.ladans.systock.')
    destination = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(temporary / 'systock.mobileprovision', destination / f"{profile['UUID']}.mobileprovision")
    managed = profile.get('IsXcodeManaged', False)
    options = {
        'method': 'app-store-connect',
        'destination': 'export',
        'signingStyle': 'automatic' if managed else 'manual',
        'signingCertificate': 'Apple Distribution',
        'teamID': team,
        'manageAppVersionAndBuildNumber': False,
        'uploadSymbols': True,
    }
    if not managed:
        options['provisioningProfiles'] = {bundle_id: profile['UUID']}
    with (temporary / 'ExportOptions.plist').open('wb') as output:
        plistlib.dump(options, output)
    with open(os.environ['GITHUB_ENV'], 'a') as output:
        output.write(f"IOS_TEAM_ID={team}\nIOS_PROFILE_UUID={profile['UUID']}\n")
    client_id = os.environ['GOOGLE_IOS_CLIENT_ID'].strip()
    if not client_id.endswith('.apps.googleusercontent.com'):
        raise ValueError('GOOGLE_IOS_CLIENT_ID must be an iOS OAuth client ID.')
    Path('defines.json').write_text(json.dumps({
        'GOOGLE_IOS_CLIENT_ID': client_id,
        'GOOGLE_SERVER_CLIENT_ID': os.environ.get('GOOGLE_SERVER_CLIENT_ID', ''),
    }))
    path = Path('ios/Runner/Info.plist')
    with path.open('rb') as source:
        info = plistlib.load(source)
    previous_scheme = '.'.join(reversed(info.get('GIDClientID', '').split('.')))
    info['GIDClientID'] = client_id
    for entry in info.get('CFBundleURLTypes', []):
        entry['CFBundleURLSchemes'] = [
            scheme for scheme in entry.get('CFBundleURLSchemes', [])
            if scheme != previous_scheme
        ]
    info.setdefault('CFBundleURLTypes', []).append({
        'CFBundleTypeRole': 'Editor',
        'CFBundleURLSchemes': ['.'.join(reversed(client_id.split('.')))],
    })
    with path.open('wb') as output:
        plistlib.dump(info, output)


if __name__ == '__main__':
    prepare()
