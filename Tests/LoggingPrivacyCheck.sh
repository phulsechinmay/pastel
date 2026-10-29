#!/bin/sh
# Logging privacy check (plan v3 C10/C14, tier 1: CI-runnable, no Swift needed).
# Fails if a log entry point interpolates a forbidden item field.
# This is a grep heuristic, NOT a proof: it cannot catch every pre-formatted
# string, which is why the canary test (fixture with a unique URL/title,
# asserting no log line contains it) is required on macOS before leaving draft.
# Usage: sh Tests/LoggingPrivacyCheck.sh
set -eu
cd "$(dirname "$0")/.."
# Search log calls (Logger, NSLog, pasteLog, print) for forbidden interpolations.
# Excludes the allowlisted structured logs in ClipboardSearchIndex (numbers only).
if grep -rnE 'logger\.(info|warning|error|debug|notice)\([^)]*(textContent|fullTextContent|htmlContent|urlTitle|sourceAppName|sourceAppBundleID|imagePath|thumbnailPath|urlFaviconPath|urlPreviewImagePath|contentHash|stableID|labelKey)' Pastel --include='*.swift' | grep -v 'ClipboardSearchIndex' ; then
  echo "FAIL: forbidden item field in a log call (see above)" >&2
  exit 1
fi
if grep -rn 'pasteLog(' Pastel --include='*.swift' | grep -E 'frontmost|bundleIdentifier|localizedName|urlString|imagePath|title=' ; then
  echo "FAIL: pasteLog with app/URL/path/title data (see above)" >&2
  exit 1
fi
if grep -rn 'NSLog(' Pastel --include='*.swift' | grep -E 'urlString|imagePath|sourceApp|title' ; then
  echo "FAIL: NSLog with item data (see above)" >&2
  exit 1
fi
echo "Logging privacy grep check passed (heuristic only; canary test still required on macOS)"
