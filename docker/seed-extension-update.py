#!/usr/bin/env python3
"""Stage a full-form FreePBX extension edit in the disposable lab only."""
import os
import re
import sys
import urllib.parse
import urllib.request
import urllib.error
import http.cookiejar
from html.parser import HTMLParser
from pathlib import Path

root = Path(__file__).resolve().parents[1]
env_file = Path(os.environ.get("FREEPBX_LAB_ENV_FILE", root / ".env.lab"))
for line in env_file.read_text().splitlines():
    if "=" in line and not line.lstrip().startswith("#"):
        key, value = line.split("=", 1)
        os.environ.setdefault(key, value)
base = os.environ.get("FREEPBX_LAB_URL", "http://127.0.0.1:8080")

class Form(HTMLParser):
    def __init__(self):
        super().__init__(); self.fields = {}; self.in_form = False; self.select = None
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "form" and a.get("id") == "frm_extensions": self.in_form = True
        if not self.in_form: return
        if tag == "input" and a.get("name") and (a.get("type") not in {"checkbox", "radio"} or "checked" in a):
            self.fields[a["name"]] = a.get("value", "")
        elif tag == "select" and a.get("name"):
            self.select = a["name"]
        elif tag == "option" and self.select:
            # Browsers submit the first option when markup has no explicit
            # `selected` attribute. Preserve that HTML form behavior.
            if "selected" in a:
                self.fields[self.select] = a.get("value", "")
            else:
                self.fields.setdefault(self.select, a.get("value", ""))
    def handle_endtag(self, tag):
        if tag == "select": self.select = None
        elif tag == "form": self.in_form = False

jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
opener.open(base + "/admin/config.php").read()
login = urllib.parse.urlencode({"username": os.environ["FREEPBX_LAB_ADMIN_USER"], "password": os.environ["FREEPBX_LAB_ADMIN_PASSWORD"]}).encode()
opener.open(base + "/admin/config.php", login).read()
url = base + "/admin/config.php?display=extensions&extdisplay=7001"
parser = Form(); parser.feed(opener.open(url).read().decode("utf-8", "replace"))
if not parser.fields: raise SystemExit("extension edit form was not available")
parser.fields.update({"display": "extensions", "action": "edit", "extdisplay": "7001", "extension": "7001", "name": "WhatChanged Lab Extension Updated"})
request = urllib.request.Request(url, urllib.parse.urlencode(parser.fields).encode(), headers={"Referer": url})
try:
    response = opener.open(request).read().decode("utf-8", "replace")
except urllib.error.HTTPError as error:
    # The lab's PHP configuration does not always write form exceptions to
    # Apache's log. Return only a short server diagnostic, never field values.
    detail = error.read().decode("utf-8", "replace")[:1500]
    raise SystemExit(f"extension edit returned HTTP {error.code}: {detail}")
if "There was an error" in response:
    raise SystemExit("extension edit returned a FreePBX error page")
alerts = re.findall(r"javascript:alert\('([^']+)'\)", response)
if alerts:
    raise SystemExit("extension edit validation failed: " + "; ".join(alerts[:3]))
print("Staged disposable extension 7001 name update")
