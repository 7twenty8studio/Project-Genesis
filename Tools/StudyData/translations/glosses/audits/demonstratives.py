"""Hebrew demonstratives with the article after their noun ("the day the
this", STEPBible's "<the> this"): the article and the demonstrative agree
with the Spanish or Portuguese noun ("<el> día <el> este", "<la> palabra
<la> esta"), not the Hebrew one (דָּבָר is masculine, "palabra" feminine).
The noun is the nearest word before it with the article, skipping
adjectives. Places the full review corrected by hand are left alone."""
import collections, sys
import agree2 as A
from lib import *
U,T,O,F,byv=A.U,A.T,A.O,A.F,A.byv
FORMS={'es':{('this','M','S'):'<el> este',('this','F','S'):'<la> esta',('this','M','P'):'<los> estos',('this','F','P'):'<las> estas',
             ('that','M','S'):'<el> aquel',('that','F','S'):'<la> aquella',('that','M','P'):'<los> aquellos',('that','F','P'):'<las> aquellas'},
       'pt':{('this','M','S'):'<o> este',('this','F','S'):'<a> esta',('this','M','P'):'<os> estes',('this','F','P'):'<as> estas',
             ('that','M','S'):'<o> aquele',('that','F','S'):'<a> aquela',('that','M','P'):'<os> aqueles',('that','F','P'):'<as> aquelas'}}
EN={'this':('this','S'),'these':('this','P'),'that':('that','S'),'those':('that','P')}
REVIEWED=set()
for name in ('review.jsonl','verses.jsonl'):
    path=os.path.join(HERE,name)
    if not os.path.exists(path): continue
    for line in open(path,encoding='utf-8'):
        if line.strip():
            r=json.loads(line)
            if 'pos' in r: REVIEWED.add((r['lang'],r['verse'],r['pos']))
            else:
                for p,g,i in byv.get(r['verse'],[]):
                    if g==r['english']: REVIEWED.add((r['lang'],r['verse'],p))
def last(m): return m.split('/')[-1]
def isadj(m): return bool(re.match(r'^[HA]?(Aa|Ao)',last(m)))
def isnoun(m): return bool(re.match(r'^[HA]?Nc[mfb][sp]a',last(m))) and '/Td' in '/'+m or bool(re.match(r'^[HA]?Td/Nc',m))
want=collections.defaultdict(dict); log=[]
for v,ws in byv.items():
    if v//1000000>=40: continue
    seen=[]
    for p,g,i in ws:
        if p not in [x[0] for x in seen]: seen.append((p,g,i))
    for k,(pos,g,i) in enumerate(seen):
        m=re.fullmatch(r'<the> (this|these|that|those)',g)
        if not m or U[i]['strongs'][0] not in 'HA': continue
        dem,num=EN[m.group(1)]
        j=k-1
        while j>=0 and isadj(U[seen[j][2]]['morph']): j-=1
        if j<0 or k-j>3 or not re.search(r'Nc',last(U[seen[j][2]]['morph'])): continue
        for l in ('es','pt'):
            if (l,v,pos) in REVIEWED: continue
            cur=text(T,O,l,i,v,pos) or ''
            if cur not in FORMS[l].values(): continue
            nt=text(T,O,l,seen[j][2],v,seen[j][0]) or ''
            h=A.head(l,nt)
            if not h or h in A.SKIPHEAD or nt.strip('[<¿¡')[:1].isupper(): continue
            gg=A.gender(l,h)
            if not gg: continue
            gg='F' if gg=='A' else gg
            # the noun's own number in the translation (a Hebrew plural can be a Spanish singular: "agua")
            n='P' if re.search(r's\]?$',h) and not h.endswith(('ís','és','ás','us','is')) else num
            new=FORMS[l][(dem,gg,n)]
            if new!=cur:
                want[(l,i)][f'{v}.{pos}']=new; log.append((l,v,nt,cur,new))
if '--show' in sys.argv:
    for x in log[:80]: print(*x)
if '--apply' in sys.argv:
    files={}
    for (l,i),places in want.items():
        path=F[l][i]; j=files.get(path) or json.load(open(path,encoding='utf-8')); files[path]=j
        occ=j.setdefault('occurrences',{}); d=occ.setdefault(i,{})
        for p,t in places.items():
            if t==j['glosses'][i]: d.pop(p,None)
            else: d[p]=t
        if d: occ[i]=dict(sorted(d.items()))
        else: occ.pop(i)
    for path,j in files.items():
        raw=open(path,encoding='utf-8').read()
        open(path,'w',encoding='utf-8').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
print('demonstratives:',collections.Counter(x[0] for x in log))
