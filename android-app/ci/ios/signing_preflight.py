#!/usr/bin/env python3
"""Échoue explicitement si la signature Apple ne peut pas commencer."""
import os
import re
required=['APPLE_TEAM_ID','APPLE_BUNDLE_ID','APPLE_CERT_P12_BASE64',
          'APPLE_CERT_P12_PASSWORD','APPLE_PROFILE_BASE64']
missing=[name for name in required if not os.environ.get(name)]
if missing: raise SystemExit('Secrets Apple manquants : '+', '.join(missing))
if not re.fullmatch(r'[A-Z0-9]{10}',os.environ['APPLE_TEAM_ID']):
    raise SystemExit('APPLE_TEAM_ID invalide')
if os.environ['APPLE_BUNDLE_ID']!='com.manzilionellm.sevenmotion':
    raise SystemExit('Le profil doit correspondre au Bundle ID verrouillé dans source.lock.json')
print('Variables Apple présentes ; certificat et profil seront vérifiés avant archivage.')
