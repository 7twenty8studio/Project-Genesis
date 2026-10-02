#!/bin/bash
# Lists the app's strings that have no Spanish yet, as Xcode itself sees them.
#
#   ./Scripts/localization_check.sh
#
# Xcode exports every string the code uses (xcodebuild -exportLocalizations);
# this compares that with the Spanish in the String Catalogs and writes what's
# missing to build/untranslated-es.txt. Send that file to Claude, who adds the
# Spanish. Nothing in the project is changed.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null 2>&1 && xcodegen generate --quiet >/dev/null
OUT=build/Localizations
rm -rf "$OUT"
mkdir -p "$OUT"
echo "Exporting strings (this builds the app, a minute or two)..."
if ! xcodebuild -exportLocalizations -project Genesis.xcodeproj -localizationPath "$OUT" \
        -exportLanguage es -skipPackagePluginValidation >"$OUT/export.log" 2>&1; then
    echo "❌ Export failed; see $OUT/export.log"
    tail -n 20 "$OUT/export.log"
    exit 1
fi
python3 Tools/Localization/untranslated.py "$OUT" > build/untranslated-es.txt
COUNT=$(grep -c . build/untranslated-es.txt || true)
if [ "$COUNT" -eq 0 ]; then
    echo "✅ Every string has Spanish."
    rm -f build/untranslated-es.txt
else
    echo "⚠️  $COUNT strings have no Spanish yet. Send build/untranslated-es.txt to Claude."
fi
