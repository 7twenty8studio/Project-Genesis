"""Hebrew/Aramaic adjectives and demonstratives after their noun: gender
agreement with the Spanish/Portuguese noun (OT)."""
import sys
sys.argv=[sys.argv[0]]+[a for a in sys.argv[1:]]
APPLY='--apply' in sys.argv
import agree2 as A
from lib import *
import collections
U,T,O,F,byv=A.U,A.T,A.O,A.F,A.byv
def last(m): return m.split('/')[-1] or ' '
def noun(m):
    x=re.match(r'^Nc([mfb])([sp])',last(m)[1:] if last(m)[0] in 'HA' else last(m))
    return x.groups() if x else None
def adj(m):
    s=last(m); s=s[1:] if s[0] in 'HA' and len(s)>1 and s[1].isupper() else s
    x=re.match(r'^(?:Aa|Ao|Pd)([mfbc])([sp])',s)
    return x.groups() if x else None
log=[]; changes={'es':{},'pt':{}}
for v,ws in byv.items():
    if v//1000000>=40: continue
    info=[(pos,i,U[i]['morph']) for pos,g,i in ws]
    for k,(pos,i,m) in enumerate(info):
        a=adj(m)
        if not a or k==0: continue
        eg=U[i]['gloss']
        if re.match(r'^(and |or |but |as |like )?(a|an)\b',eg,re.I): continue
        if re.search(r'\[(is|are|was|were|be)\]',eg) or re.search(r'\b(of|by|to|without|with|for|from|in)\b',eg): continue
        # the noun right before (or before another adjective)
        j=k-1
        while j>=0 and adj(info[j][2]): j-=1
        if j<0 or k-j>2: continue
        n=noun(info[j][2])
        st=re.match(r'^(?:[HA])?Nc[mfb][sp](\w)',last(info[j][2]))
        if st and st.group(1)=='c': continue   # construct: the adjective is its genitive
        if not n or n[1]!=a[1] or (a[0] in 'mf' and n[0] in 'mf' and a[0]!=n[0]): continue
        if U[info[j][1]]['strongs'][0]!='H' and U[info[j][1]]['strongs'][0]!='A': pass
        for l in ('es','pt'):
            mt=changes[l].get((i,f'{v}.{pos}')) or text(T,O,l,i,v,pos)
            content=[w.group(0).lower() for w in A.words(re.sub(r'\[[^\]]*\]','',mt or '')) if w.group(0).lower() not in A.STOP[l]]
            if len(content)!=1: continue
            nt=text(T,O,l,info[j][1],v,info[j][0]); h=A.head(l,nt)
            if not h or h in A.SKIPHEAD or (nt and nt.strip('[<¿¡')[:1].isupper()): continue
            mg=A.modgender(l,'A',mt); ng=A.gender(l,h)
            if not mg or not ng: continue
            ng='F' if ng=='A' else ng
            if mg!=ng:
                new=A.fix(l,'A',mt,ng)
                if new!=mt and A.modgender(l,'A',new)==ng:
                    changes[l][(i,f'{v}.{pos}')]=new; log.append((l,v,mt,new,nt,U[info[j][1]]['gloss']))
print(collections.Counter(x[0] for x in log))
pass
if APPLY:
    files={}
    for l in changes:
        byid=collections.defaultdict(dict)
        for (i,p),t in changes[l].items(): byid[i][p]=t
        for i,newp in byid.items():
            f=F[l][i]; j=files.get(f) or json.load(open(f)); files[f]=j
            occ=j.setdefault('occurrences',{}); cur=dict(occ.get(i,{})); cur.update(newp)
            cur={p:t for p,t in cur.items() if t!=j['glosses'][i]}
            if cur: occ[i]=dict(sorted(cur.items()))
            else: occ.pop(i,None)
    for f,j in files.items():
        raw=open(f).read(); open(f,'w').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
    print('applied',len(files))
