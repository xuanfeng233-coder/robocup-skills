#!/usr/bin/env python3
"""Dump docs.booster.tech (Docusaurus) pages to markdown, skipping T1/T2-only pages.
Usage: dump_docs.py OUT_DIR"""
import re, subprocess, sys, urllib.request, os, tempfile
out = sys.argv[1]
home = urllib.request.urlopen("https://docs.booster.tech/docs/product-manual/k1/getting-started/overview/").read().decode()
main_js = re.search(r'src="([^"]*/main\.[0-9a-f]+\.js)"', home).group(1)
js = urllib.request.urlopen(main_js).read().decode("utf8", "ignore")
routes = sorted({r.replace("/en/", "/") for r in re.findall(r'"(/(?:en/)?docs/[A-Za-z0-9_/.-]+)"', js)})
keep = [r for r in routes
        if not re.search(r"/-[0-9a-f]{3}$", r) and not r.endswith("/")
        and not re.search(r"/t[12](/|-|$)", r)
        and re.search(r"developer-guide|product-manual/k1|changelog", r)]
with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
    f.write("\n".join(keep)); lst = f.name
subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "dump_docs_impl.py"), lst, out], check=True)
