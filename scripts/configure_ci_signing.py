"""Restore existing Android production signing from CI secrets (never log values)."""
import base64
import os
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
keystore = root / 'android/production.jks'

raw_b64 = os.environ.get('ANDROID_KEYSTORE_BASE64', '')
if not raw_b64:
    sys.exit("Error: ANDROID_KEYSTORE_BASE64 secret is not set or empty.")

# Remove whitespace, newlines, carriage returns, quotes
cleaned = re.sub(r'[\s\r\n\'"]', '', raw_b64)
# Strip PEM boundaries if user used certutil or openssl
cleaned = re.sub(r'-----BEGIN[^-]+-----|-----END[^-]+-----', '', cleaned)

# Pad if base64 length is not multiple of 4
padding_needed = (4 - len(cleaned) % 4) % 4
if padding_needed:
    cleaned += '=' * padding_needed

try:
    decoded = base64.b64decode(cleaned)
except Exception as e:
    sys.exit(f"Error: Failed to base64-decode ANDROID_KEYSTORE_BASE64: {e}")

if len(decoded) < 100:
    sys.exit(f"Error: Decoded keystore is suspiciously small ({len(decoded)} bytes). Expected a valid .jks file.")

keystore.write_bytes(decoded)


def property_value(value):
    return (value.replace('\\', '\\\\')
            .replace('\n', '\\n')
            .replace('\r', '\\r')
            .replace('=', '\\=')
            .replace(':', '\\:')
            .replace(' ', '\\ '))


values = {
    'storeFile': 'production.jks',
    'storePassword': os.environ.get('ANDROID_STORE_PASSWORD', ''),
    'keyAlias': os.environ.get('ANDROID_KEY_ALIAS', ''),
    'keyPassword': os.environ.get('ANDROID_KEY_PASSWORD', ''),
}

missing = [k for k, v in values.items() if not v]
if missing:
    sys.exit(f"Error: Required secret(s) missing or empty: {', '.join(missing)}")

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
