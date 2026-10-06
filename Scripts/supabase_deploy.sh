#!/bin/bash
# Deploys every Supabase Edge Function in supabase/functions and lists which
# secrets they need. Safe to run again after any change.
#
#   ./Scripts/supabase_deploy.sh
#
# Needs the Supabase CLI (brew install supabase/tap/supabase). The first run
# opens a browser to sign in (supabase login) and links this folder to the
# project. Secrets are never printed: the script only lists their names.
set -uo pipefail
cd "$(dirname "$0")/.."

PROJECT_REF="${SUPABASE_PROJECT_REF:-ulbpwygzwchsnvdeeife}"

if ! command -v supabase >/dev/null 2>&1; then
    echo "The Supabase CLI isn't installed. Install it with:"
    echo "  brew install supabase/tap/supabase"
    exit 1
fi

# Signed in? (supabase projects list fails when not.)
if ! supabase projects list >/dev/null 2>&1; then
    echo "Signing in to Supabase (a browser window opens)..."
    supabase login || exit 1
fi

if [ ! -f supabase/.temp/project-ref ] || [ "$(cat supabase/.temp/project-ref 2>/dev/null)" != "$PROJECT_REF" ]; then
    echo "Linking to project $PROJECT_REF..."
    supabase link --project-ref "$PROJECT_REF" || exit 1
fi

FAILED=()
for dir in supabase/functions/*/; do
    name=$(basename "$dir")
    [ -f "$dir/index.ts" ] || continue
    echo
    echo "Deploying $name..."
    if supabase functions deploy "$name" --project-ref "$PROJECT_REF"; then
        echo "✅ $name"
    else
        echo "❌ $name"
        FAILED+=("$name")
    fi
done

echo
echo "Secrets the functions use (names only):"
SECRETS=$(supabase secrets list --project-ref "$PROJECT_REF" 2>/dev/null | awk 'NR>2 {print $1}')
for secret in ANTHROPIC_API_KEY APNS_KEY APNS_KEY_ID APNS_TEAM_ID; do
    if echo "$SECRETS" | grep -qx "$secret"; then
        echo "  ✅ $secret"
    else
        case "$secret" in
            ANTHROPIC_API_KEY) why="study-ai (the study assistant) stays off without it" ;;
            *) why="group-notify (announcement notifications) does nothing without it" ;;
        esac
        echo "  ⚠️  $secret not set: $why. Set it in the dashboard: Edge Functions › Secrets."
    fi
done
if echo "$SECRETS" | grep -qx "ALLOW_XCODE_STOREKIT"; then
    echo "  ⚠️  ALLOW_XCODE_STOREKIT is set: remove it before release."
fi

echo
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "All functions deployed."
else
    echo "These didn't deploy: ${FAILED[*]}. Send the output above to Claude."
    exit 1
fi
