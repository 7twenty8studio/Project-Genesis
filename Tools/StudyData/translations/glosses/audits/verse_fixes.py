"""The verse-by-verse review of every gloss (19 November 2026): every verse
of the Bible was read whole in Spanish and Portuguese, with the Hebrew or
Greek morphology, and each correction is a line in verses.jsonl (verse,
word position, language, the English gloss, the text found and the text it
should be, and why). Each is written as that place's verse-specific gloss,
for every edition's word at that position with that English gloss. A line
whose place already reads the corrected text is skipped, so this can run
again; one whose text has changed since is reported and left alone."""
import collections, sys
from lib import *
import forms
import glosses
U,T,O,F,byv=load()
forms.U=U
FINAL='--final' in sys.argv
fixes=[json.loads(l) for l in open(os.path.join(HERE,'verses.jsonl'),encoding='utf-8') if l.strip()]
files={}; done=collections.Counter(); missing=[]; rejected=[]
for f in fixes:
    v,l,pos=f['verse'],f['lang'],f['pos']
    places=[(p,i) for p,g,i in byv.get(v,[]) if p==pos and g==f['english']]
    if not places:
        places=[(p,i) for p,g,i in byv.get(v,[]) if p==pos]
    # forms.py runs after this and may contract the corrected text ("de o" → "do")
    ok=(f['current'].strip(),f['proposed'].strip(),forms.RULES[l](f['proposed'],places[0][1]).strip()) if places else ()
    hit=[(p,i) for p,i in places if (text(T,O,l,i,v,p) or '').strip() in ok]
    # --final (the last step of run.sh): the review read the whole verse, so its
    # word wins over a pattern audit that ran before it and changed the place again
    if not hit and FINAL and places and places[0][0]==pos and any(g==f['english'] for p,g,i in byv.get(v,[]) if p==pos):
        hit=[(p,i) for p,i in places]
    if not hit: missing.append(f); continue
    # a correction the structural checks would reject (an extra bracket, a capital) is left out and reported
    bad=[(p,i) for p,i in hit if set(glosses.check_gloss(U[i]['gloss'],f['proposed'],l,'',None))-set(glosses.check_gloss(U[i]['gloss'],text(T,O,l,i,v,p) or '',l,'',None))]
    if bad: rejected.append(f); continue
    for p,i in hit:
        path=F[l][i]; j=files.get(path) or json.load(open(path,encoding='utf-8')); files[path]=j
        occ=j.setdefault('occurrences',{}); key=f'{v}.{p}'
        now=occ.get(i,{}).get(key,j['glosses'][i])
        if now.strip() in ok[1:]: done['already']+=1; continue
        d=occ.setdefault(i,{})
        if f['proposed']==j['glosses'][i]: d.pop(key,None)
        else: d[key]=f['proposed']
        if not d: occ.pop(i)
        else: occ[i]=dict(sorted(d.items()))
        O[l][(i,key)]=f['proposed']; done['fixed']+=1
for path,j in files.items():
    raw=open(path,encoding='utf-8').read()
    open(path,'w',encoding='utf-8').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
print('verse fixes:',dict(done),'not found:',len(missing),'left out (checks):',len(rejected))
for f in rejected: print('  left out',f['verse'],f['pos'],f['lang'],f['english'],repr(f['current']),'->',repr(f['proposed']))
for f in missing[:40]: print('  not found',f['verse'],f['pos'],f['lang'],f['english'],repr(f['current']),'->',repr(f['proposed']))
