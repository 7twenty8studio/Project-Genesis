from lib import *
U,T,O,F,byv=load()
ACC=re.compile(r'^P-(1AS|2AS|1AP|2AP|AS[MFN]|AP[MFN])$')
BARE=re.compile(r"^(him|Him|them|Them|you|You|me|Me|it|It|her|Her|us|Us|me myself|Me myself)([?!.’,;]*)$")
INF=re.compile(r'V-..N$')
out=[]
for v,ws in byv.items():
    if v//1000000<40: continue
    for k,(pos,g,i) in enumerate(ws):
        u=U[i]
        if not ACC.match(u['morph']) or not BARE.match(u['gloss']): continue
        before=[w for w in ws[:k] if w[0]<pos]
        p=U[before[-1][2]] if before else None
        if p and p['morph'].startswith('PREP'): kind='prep'
        else:
            before=any(INF.match(U[ws[j][2]]['morph']) for j in range(max(0,k-3),k)) and any(U[ws[j][2]]['morph'].startswith('T-') for j in range(max(0,k-4),k))
            after=any(INF.match(U[ws[j][2]]['morph']) for j in range(k+1,min(len(ws),k+3)))
            kind='review' if (before or after) else 'obj'
        out.append((v,pos,i,kind,' | '.join(('**'+x[1]+'**' if j==k else x[1]) for j,x in enumerate(ws[max(0,k-5):k+4],start=max(0,k-5)))))
import collections
print(collections.Counter(o[3] for o in out))
json.dump(out,open(os.path.join(HERE,'cand.json'),'w'),ensure_ascii=False)
if not os.path.exists(os.path.join(HERE,'review.txt')):
  with open(os.path.join(HERE,'review.txt'),'w') as f:
    for n,o in enumerate([o for o in out if o[3]=='review']): f.write(f"{n}\t{o[0]}.{o[1]}\t{o[4]}\n")
