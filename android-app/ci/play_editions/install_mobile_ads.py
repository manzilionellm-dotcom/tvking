"""Branche la bannière des réglages mobiles sur la fiche ZUNO existante."""
from pathlib import Path
import sys

APP = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(APP / 'ci/mobile/free/ads'))
from prepare_ads import install_android

if __name__ == '__main__':
    install_android(APP, ('ca-app-pub-3909645366985922~7796738037',
                          'ca-app-pub-3909645366985922/8723127695'),
                    expected_package='com.sevenmotion.tv.seven_tv')
