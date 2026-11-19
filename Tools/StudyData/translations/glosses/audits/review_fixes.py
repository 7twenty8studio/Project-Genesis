"""The full review of 19 November 2026: every word the audits changed was
read in its verse (Spanish and Portuguese), and each correction found is a
line in review.jsonl (verse, language, the English gloss and morphology,
which of its occurrences in the verse, the text found and the text it
should be, and why). Each one is written as that place's verse-specific
gloss. A line whose place already reads the corrected text is skipped,
so this can run again; one whose text has changed since is reported."""
import collections
from lib import *
U,T,O,F,byv=load()
fixes=[json.loads(l) for l in open(os.path.join(HERE,'review.jsonl'),encoding='utf-8') if l.strip()]
files={}; done=collections.Counter(); missing=[]
def norm(s): return s.strip()
for f in fixes:
    v,l=f['verse'],f['lang']
    places=[(p,i) for p,g,i in byv.get(v,[]) if g==f['english'] and (not f.get('morph') or U[i]['morph']==f['morph'])]
    # an edition's twin at the same position counts once
    seen=[];uniq=[]
    for p,i in places:
        if p not in seen: seen.append(p); uniq.append((p,i))
    cands=[(p,i) for p,i in uniq if norm(text(T,O,l,i,v,p) or '') in (norm(f['current']),norm(f['proposed']))]
    pick=None
    if len(cands)==1: pick=cands[0]
    elif cands:
        n=f.get('nth',1)
        pick=cands[min(n,len(cands))-1]
    if not pick and uniq:
        # the audits before this one may now give another text here: the place is still
        # the n-th word with this English gloss and morphology
        pick=uniq[min(f.get('nth',1),len(uniq))-1]; done['by place']+=1
    if not pick: missing.append(f); continue
    p,i=pick
    path=F[l][i]; j=files.get(path) or json.load(open(path,encoding='utf-8')); files[path]=j
    occ=j.setdefault('occurrences',{})
    key=f'{v}.{p}'
    now=occ.get(i,{}).get(key,j['glosses'][i])
    if now==f['proposed']: done['already']+=1; continue
    d=occ.setdefault(i,{})
    if f['proposed']==j['glosses'][i]: d.pop(key,None)
    else: d[key]=f['proposed']
    if not d: occ.pop(i)
    else: occ[i]=dict(sorted(d.items()))
    O[l][(i,key)]=f['proposed']
    done['fixed']+=1
for path,j in files.items():
    raw=open(path,encoding='utf-8').read()
    open(path,'w',encoding='utf-8').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
print('review fixes:',dict(done),'not found:',len(missing))
for f in missing: print('  not found',f['verse'],f['lang'],f['english'],repr(f['current']),'->',repr(f['proposed']))
