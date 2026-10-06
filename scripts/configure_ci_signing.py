"""Restore existing Android production signing from CI secrets (never log values)."""
import base64
import os
from pathlib import Path

root = Path(__file__).resolve().parents[1]
keystore = root / 'android/production.jks'
keystore.write_bytes(base64.b64decode(os.environ['ANDROID_KEYSTORE_BASE64'], validate=True))


def property_value(value):
    return value.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('=', '\\=').replace(':', '\\:').replace(' ', '\\ ')


values = {
    'storeFile': str(keystore),
    'storePassword': os.environ['ANDROID_STORE_PASSWORD'],
    'keyAlias': os.environ['ANDROID_KEY_ALIAS'],
    'keyPassword': os.environ['ANDROID_KEY_PASSWORD'],
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
