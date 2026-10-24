#!/usr/bin/env python3
"""Upload an Android App Bundle (.aab) to Google Play, or query the latest version code.

Examples:
  python3 google_play/upload_to_google_play.py --get-latest-version
  python3 google_play/upload_to_google_play.py                       # default AAB, internal track
  python3 google_play/upload_to_google_play.py --track production --status draft
"""
import argparse
import os
import sys

import google_auth_httplib2
import httplib2
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]
# The client's default 60s socket timeout is too short for a ~100 MB bundle.
HTTP_TIMEOUT_SECONDS = 600
UPLOAD_RETRIES = 3

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_PACKAGE = "com.matchlab.duplicatesweep"
DEFAULT_KEY_FILE = os.path.join(SCRIPT_DIR, "google-play-credentials.json")
DEFAULT_AAB = os.path.join(PROJECT_ROOT, "build/app/outputs/bundle/release/app-release.aab")


def fail(message: str) -> None:
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload an Android App Bundle to Google Play")
    parser.add_argument("--aab", default=DEFAULT_AAB, help=f"Path to the .aab (default: {DEFAULT_AAB})")
    parser.add_argument("--get-latest-version", action="store_true",
                        help="Print the highest version code on Play Console and exit")
    parser.add_argument("--package-name", default=os.environ.get("PLAY_PACKAGE_NAME", DEFAULT_PACKAGE),
                        help=f"Application ID (default: {DEFAULT_PACKAGE})")
    parser.add_argument("--key-file", default=os.environ.get("PLAY_KEY_FILE", DEFAULT_KEY_FILE),
                        help="Service account key JSON (default: google_play/google-play-credentials.json)")
    parser.add_argument("--track", default="internal", choices=["internal", "alpha", "beta", "production"],
                        help="Release track (default: internal)")
    parser.add_argument("--status", default="completed", choices=["completed", "draft"],
                        help="Release status; use draft while the app itself is still a draft in Play Console")
    parser.add_argument("--release-notes", help="en-US release notes for this version")
    args = parser.parse_args()

    package_name = args.package_name
    if not os.path.isfile(args.key_file):
        fail(f"Service account key not found: {args.key_file} (pass --key-file)")
    if not args.get_latest_version and not os.path.isfile(args.aab):
        fail(f"AAB not found: {args.aab} (build it with 'flutter build appbundle --release')")

    try:
        creds = service_account.Credentials.from_service_account_file(args.key_file, scopes=SCOPES)
        http = google_auth_httplib2.AuthorizedHttp(creds, http=httplib2.Http(timeout=HTTP_TIMEOUT_SECONDS))
        service = build("androidpublisher", "v3", http=http, cache_discovery=False)
    except Exception as e:
        fail(f"Failed to authenticate with Google APIs: {e}")

    edits = service.edits()
    try:
        edit_id = edits.insert(packageName=package_name, body={}).execute()["id"]
    except Exception as e:
        fail(f"Failed to open an edit. Check that '{package_name}' exists in Play Console "
             f"and the service account has access to it: {e}")

    if args.get_latest_version:
        try:
            bundles = edits.bundles().list(packageName=package_name, editId=edit_id).execute()
            codes = [b["versionCode"] for b in bundles.get("bundles", [])]
            print(f"LATEST_VERSION_CODE={max(codes) if codes else 0}")
        except Exception as e:
            fail(f"Failed to list uploaded bundles: {e}")
        finally:
            # Read-only query: discard the edit so it doesn't linger in Play Console.
            try:
                edits.delete(packageName=package_name, editId=edit_id).execute()
            except Exception:
                pass
        return

    print(f"Uploading {args.aab} to {package_name} (this may take a few minutes)...")
    try:
        media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True)
        version_code = edits.bundles().upload(
            editId=edit_id, packageName=package_name, media_body=media
        ).execute(num_retries=UPLOAD_RETRIES)["versionCode"]
        print(f"✓ Uploaded. Version code: {version_code}")
    except Exception as e:
        fail(f"Upload failed: {e}")

    release = {
        "versionCodes": [str(version_code)],
        "status": args.status,
        "name": f"Release {version_code}",
    }
    if args.release_notes:
        release["releaseNotes"] = [{"language": "en-US", "text": args.release_notes}]

    print(f"Assigning version {version_code} to track '{args.track}' ({args.status})...")
    try:
        edits.tracks().update(
            editId=edit_id, packageName=package_name, track=args.track, body={"releases": [release]}
        ).execute()
    except Exception as e:
        fail(f"Failed to update track '{args.track}': {e}")

    try:
        edits.commit(editId=edit_id, packageName=package_name).execute()
    except Exception as e:
        fail(f"Failed to commit the edit: {e}")
    print(f"🎉 Version {version_code} is on the '{args.track}' track in Google Play Console.")


if __name__ == "__main__":
    main()
