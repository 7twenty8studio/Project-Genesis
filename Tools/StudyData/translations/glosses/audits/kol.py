"""Hebrew and Aramaic כָּל ("all", H3605, H3606) glossed "todo": it agrees with the noun phrase
after it, in Spanish and Portuguese ("toda [la] tierra", "todos tus
siervos", "todas as mulheres"). The article, demonstrative or possessive
of the next word gives the number (and the gender where it has one);
otherwise the noun's gender. "todo Israel", "todo hombre" (no article) stay.
Like the other audits it only changes what it finds."""
import collections, sys
from lib import *
from gender import gender
U,T,O,F,byv=load()
DET={'es':{'el':'MS','la':'FS','los':'MP','las':'FP','este':'MS','esta':'FS','estos':'MP','estas':'FP','ese':'MS','esa':'FS','esos':'MP','esas':'FP',
           'aquel':'MS','aquella':'FS','aquellos':'MP','aquellas':'FP','nuestro':'MS','nuestra':'FS','nuestros':'MP','nuestras':'FP','vuestro':'MS','vuestra':'FS','vuestros':'MP','vuestras':'FP',
           'mi':'?S','tu':'?S','su':'?S','mis':'?P','tus':'?P','sus':'?P','del':'MS','al':'MS'},
     'pt':{'o':'MS','a':'FS','os':'MP','as':'FP','este':'MS','esta':'FS','estes':'MP','estas':'FP','esse':'MS','essa':'FS','esses':'MP','essas':'FP',
           'aquele':'MS','aquela':'FS','aqueles':'MP','aquelas':'FP','meu':'MS','minha':'FS','meus':'MP','minhas':'FP','teu':'MS','tua':'FS','teus':'MP','tuas':'FP',
           'seu':'MS','sua':'FS','seus':'MP','suas':'FP','nosso':'MS','nossa':'FS','nossos':'MP','nossas':'FP','vosso':'MS','vossa':'FS','vossos':'MP','vossas':'FP'}}
FORM={'MS':'todo','FS':'toda','MP':'todos','FP':'todas'}
want=collections.defaultdict(dict); why=collections.Counter()
for v,ws in byv.items():
    if v//1000000>=40: continue
    seen=[]; 
    for pos,g,i in ws:
        if pos not in [p for p,_ in seen]: seen.append((pos,i))
    for n,(pos,i) in enumerate(seen):
        if not U[i]['strongs'].startswith(('H3605','H3606')) or n+1>=len(seen): continue
        np_,ni=seen[n+1]
        for l in ('es','pt'):
            cur=text(T,O,l,i,v,pos) or ''
            m=re.fullmatch(r'(.*?\b)todo([\]>]?)',cur)
            if not m: continue
            nxt=(text(T,O,l,ni,v,np_) or '').strip()
            toks=re.findall(r"[^\W\d_]+",nxt.lower())
            if not toks: continue
            first=toks[0]
            # skip a preposition-led next gloss ("de", "en"): not this noun phrase
            if first not in DET[l]: continue
            if len(toks)>1 and toks[1] in ('quem','quien','cual','qual'): continue   # "a quem": a preposition
            gn=DET[l][first]
            if gn[0]=='?':
                noun=next((t for t in toks[1:] if t not in ('de','do','da','y','e')),None)
                if not noun: continue
                gg=gender(l,noun)
                if gg is None: continue
                gn=('F' if gg in 'FA' else 'M')+gn[1]
            if l=='es' and first=='el' and len(toks)>1 and gender('es',toks[1])=='A': gn='FS'   # toda el agua
            new=m.group(1)+FORM[gn]+m.group(2)
            if new!=cur:
                want[(l,i)][f'{v}.{pos}']=new; why[(l,FORM[gn])]+=1
show='--show' in sys.argv
if show:
    for (l,i),pl in list(want.items()):
        for p,t in list(pl.items())[:2]:
            v,pos=p.split('.'); ws=byv[int(v)]
            k=[n for n,w in enumerate(ws) if str(w[0])==pos][0]
            print(l,p,t,'|',' | '.join(text(T,O,l,w[2],int(v),w[0]) or '' for w in ws[k+1:k+3]))
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
print('kol:',sum(len(p) for p in want.values()),dict(why))
