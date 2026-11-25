#!/usr/bin/env bash
set -euo pipefail

# Room calcule le nom de la classe et appelle son constructeur public sans argument.
analyzer="${ANDROID_HOME:?}/cmdline-tools/latest/bin/apkanalyzer"
if [[ "${2:-}" == --if-present ]]; then
  manifest=$("$analyzer" manifest print "$1")
  if ! grep -Fq 'android:name="androidx.work.' <<< "$manifest"; then
    # Les variantes sans la dépendance ne déclarent aucun composant WorkManager et ne
    # définissent ni la base, ni son implémentation, ni l'initialiseur en DEX.
    present=$("$analyzer" dex packages --defined-only "$1" | awk '
      $1 == "C" && $NF ~ /^androidx\.work\.(impl\.WorkDatabase(_Impl)?|(impl\.)?WorkManagerInitializer)$/ { found=1 }
      END { print found+0 }')
    if [[ "$present" == 0 ]]; then
      echo 'WorkManager absent du manifeste et du DEX de cette variante.'
      exit 0
    fi
  fi
fi
bytecode=$("$analyzer" dex code --class androidx.work.impl.WorkDatabase_Impl "$1")
if ! grep -Fxq '.super Landroidx/work/impl/WorkDatabase;' <<< "$bytecode" ||
   ! grep -Fxq '.method public constructor <init>()V' <<< "$bytecode"; then
  echo 'DEX invalide : WorkManager ne peut pas instancier WorkDatabase_Impl au démarrage.' >&2
  exit 1
fi
