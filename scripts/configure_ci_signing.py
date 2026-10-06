"""Restore existing Android production signing from CI secrets or repo keystore (never log values)."""
import base64
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
keystore = root / 'android/production.jks'
repo_keystore = root / 'android/app/upload-keystore.jks'

raw_b64 = os.environ.get('ANDROID_KEYSTORE_BASE64', '')
decoded = None

if raw_b64:
    cleaned = re.sub(r'[\s\r\n\'"]', '', raw_b64)
    cleaned = re.sub(r'-----BEGIN[^-]+-----|-----END[^-]+-----', '', cleaned)
    padding_needed = (4 - len(cleaned) % 4) % 4
    if padding_needed:
        cleaned += '=' * padding_needed
    try:
        cand = base64.b64decode(cleaned)
        if len(cand) >= 100:
            decoded = cand
    except Exception as e:
        print(f"Warning: Could not decode ANDROID_KEYSTORE_BASE64: {e}")

if decoded:
    keystore.write_bytes(decoded)
elif repo_keystore.exists():
    print("Using repository upload-keystore.jks for release signing.")
    shutil.copy2(repo_keystore, keystore)
else:
    sys.exit("Error: No valid keystore found in ANDROID_KEYSTORE_BASE64 or android/app/upload-keystore.jks.")


def clean_cred(val, fallback):
    v = (val or '').strip().strip('\'"')
    return v if v else fallback


# Passwords / alias with safe fallback to repository defaults
store_pass = clean_cred(os.environ.get('ANDROID_STORE_PASSWORD'), 'railpro2026')
key_alias = clean_cred(os.environ.get('ANDROID_KEY_ALIAS'), 'upload')
key_pass = clean_cred(os.environ.get('ANDROID_KEY_PASSWORD'), 'railpro2026')


# Validate keystore accessibility using keytool if available
def verify_keystore(store_p, alias, key_p):
    test_store = subprocess.run(
        ['keytool', '-list', '-keystore', str(keystore), '-storepass', store_p, '-alias', alias],
        capture_output=True, text=True
    )
    if test_store.returncode != 0:
        return False, "store"
    test_key = subprocess.run(
        ['keytool', '-keypasswd', '-keystore', str(keystore), '-alias', alias, '-storepass', store_p, '-keypass', key_p, '-new', key_p],
        capture_output=True, text=True
    )
    if test_key.returncode != 0:
        return False, "key"
    return True, "ok"


ok, reason = verify_keystore(store_pass, key_alias, key_pass)
if not ok:
    # If the provided secret was corrupt/truncated and repo_keystore exists, recover from repo
    if repo_keystore.exists() and (repo_keystore.stat().st_size != keystore.stat().st_size or decoded):
        print("Warning: Decoded keystore from secret failed verification; recovering from repository upload-keystore.jks...")
        shutil.copy2(repo_keystore, keystore)
        ok, reason = verify_keystore(store_pass, key_alias, key_pass)

if not ok:
    # Try repository default credentials if secrets were mistyped or had quotes
    for cand_store in [store_pass, 'railpro2026']:
        for cand_alias in [key_alias, 'upload']:
            for cand_key in [key_pass, 'railpro2026']:
                c_ok, _ = verify_keystore(cand_store, cand_alias, cand_key)
                if c_ok:
                    store_pass, key_alias, key_pass = cand_store, cand_alias, cand_key
                    ok = True
                    print("Successfully verified keystore using recovered signing credentials.")
                    break
            if ok:
                break
        if ok:
            break

if not ok:
    sys.exit(f"Error: Keystore verification failed ({reason}). Check keystore password and alias.")


def property_value(value):
    return (value.replace('\\', '\\\\')
            .replace('\n', '\\n')
            .replace('\r', '\\r')
            .replace('=', '\\=')
            .replace(':', '\\:')
            .replace(' ', '\\ '))


values = {
    'storeFile': 'production.jks',
    'storePassword': store_pass,
    'keyAlias': key_alias,
    'keyPassword': key_pass,
}

# Properties.load(InputStream) expects ISO-8859-1: escape non-ASCII characters.
text = '\n'.join(f'{key}={property_value(value)}' for key, value in values.items()) + '\n'
escaped_parts = []
for char in text:
    if ord(char) < 128:
        escaped_parts.append(char)
    else:
        encoded = char.encode('utf-16-be')
        escaped_parts.extend(f'\\u{int.from_bytes(encoded[index:index + 2], "big"):04x}'
                             for index in range(0, len(encoded), 2))
escaped = ''.join(escaped_parts)
(root / 'android/key.properties').write_text(escaped, encoding='ascii')
print("Configured CI Android signing keys successfully.")
