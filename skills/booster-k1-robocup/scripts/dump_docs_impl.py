import sys,re,html,os,urllib.request,concurrent.futures as cf
out=sys.argv[2]; os.makedirs(out,exist_ok=True)
routes=[l.strip() for l in open(sys.argv[1]) if l.strip() and l.strip() not in ('/docs/search','/docs/changelog/')]
def fetch(r):
    for base in ('https://docs.booster.tech',):
        url=base+r.rstrip('/')+'/'
        try:
            t=urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'Mozilla/5.0'}),timeout=30).read().decode('utf8','ignore')
        except Exception as e:
            return r,'ERR '+str(e)
        m=re.search(r'<article.*?</article>',t,re.S)
        if not m: return r,'NOARTICLE'
        a=m.group(0)
        a=re.sub(r'<(script|style)[^>]*>.*?</\1>','',a,flags=re.S)
        a=re.sub(r'<pre[^>]*>(.*?)</pre>',lambda m:'\n```\n'+re.sub(r'<br\s*/?>','\n',m.group(1))+'\n```\n',a,flags=re.S)
        a=re.sub(r'<h([1-6])[^>]*>',lambda m:'\n'+'#'*int(m.group(1))+' ',a)
        a=re.sub(r'</(p|div|h[1-6]|li|tr)>','\n',a)
        a=re.sub(r'<(td|th)[^>]*>',' | ',a)
        a=re.sub(r'<li[^>]*>','- ',a)
        a=re.sub(r'<[^>]+>','',a)
        a=html.unescape(a)
        a=re.sub(r'\n\s*\n+','\n\n',a)
        fn=os.path.join(out,r.replace('/docs/','').strip('/').replace('/','__')+'.md')
        open(fn,'w').write(f'<!-- source: {url} -->\n'+a)
        return r,len(a)
with cf.ThreadPoolExecutor(12) as ex:
    for r,s in ex.map(fetch,routes): print(s,r)
