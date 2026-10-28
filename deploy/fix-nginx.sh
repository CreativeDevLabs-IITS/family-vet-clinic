#!/usr/bin/env bash
# Fixes 404s for .js and .html files on sites created with `cpanel sites new` (Static / React SPA).
# That template only allows .js under /assets/ or /static/ and returns 404 for any other file
# extension, so scripts in /js/ and extra .html pages stop loading.
#
# Usage:  sudo bash deploy/fix-nginx.sh your-domain.example
# This copy also maps /privacy, /resources/... to privacy.html etc., because this site has several pages.
# Safe to run more than once. It backs up the config, tests it, and restores the backup if the test fails.
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then echo "Usage: sudo bash deploy/fix-nginx.sh your-domain.example" >&2; exit 1; fi
if [ "$(id -u)" -ne 0 ] && [ -z "${CONF:-}" ]; then echo "Run with sudo." >&2; exit 1; fi

CONF="${CONF:-/etc/nginx/sites-enabled/$DOMAIN}"
if [ ! -f "$CONF" ]; then echo "Config not found: $CONF" >&2; exit 1; fi

BACKUP="${BACKUP:-/root/$DOMAIN.nginx.bak}"
if ! grep -q "# static-files-fix" "$CONF" || ! grep -q "# static-pages-fix" "$CONF"; then
  cp "$CONF" "$BACKUP"
  echo "Backup saved to $BACKUP"
fi

CONF="$CONF" python3 - <<'PY'
import os, re, sys
p = os.environ['CONF']
s = open(p).read()
changed = False

# 1. Allow scripts, pages and documents that the template would 404.
if '# static-files-fix' not in s:
    marker = '    location ~* \\.[a-z0-9]+$ {'
    if marker not in s:
        print('Could not find the catch-all rule (location ~* \\.[a-z0-9]+$). Config left unchanged.')
        sys.exit(2)
    add = '''    # static-files-fix: allow scripts, pages and documents that the template would 404
    location ~* \\.(js|mjs)$ {
        expires 1d;
        access_log off;
        try_files $uri =404;
    }

    location ~* \\.(html|txt|xml|json|webmanifest|pdf|xlsx|docx|csv|mp4|webm|mp3)$ {
        try_files $uri =404;
    }

'''
    s = s.replace(marker, add + marker, 1)
    changed = True

# 2. Multi-page sites: serve /privacy from privacy.html or privacy/index.html instead of always index.html.
if '# static-pages-fix' not in s:
    pat = re.compile(r'(    location / \{\n)(\s*)try_files /index\.html =404;')
    if not pat.search(s):
        print('Could not find "location /" with try_files /index.html. Page routing left unchanged.')
    else:
        s = pat.sub(lambda m: m.group(1) + m.group(2) + '# static-pages-fix: map /page to page.html\n' + m.group(2) + 'try_files $uri $uri.html $uri/index.html =404;', s, count=1)
        changed = True

if changed:
    open(p, 'w').write(s)
    print('Patched.')
else:
    print('Already patched, nothing to change.')
PY

if [ -n "${SKIP_RELOAD:-}" ]; then exit 0; fi
if nginx -t 2>&1 | tail -2 | grep -q "successful"; then
  systemctl reload nginx
  echo "Nginx reloaded. Hard-refresh the site (Ctrl+Shift+R). If you use Cloudflare, purge its cache."
else
  echo "Nginx test failed, restoring the backup." >&2
  cp "$BACKUP" "$CONF"
  exit 1
fi
