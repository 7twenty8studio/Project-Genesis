"""Greek dative and genitive personal pronouns with a bare English gloss
("him", "you"): after a preposition the stressed form (él, ti; ele, ti);
a dative after a verb the indirect clitic (le, les, te, os; lhe, lhes,
te, vos); a genitive object (hear, touch, bear with) the direct clitic
(lo, os; o, vos); with a participle in the same case nearby (a genitive
absolute "him speaking", a dative "him having entered") the stressed
form ("a él" for the dative)."""
from lib import *
import collections
U,T,O,F,byv=load()
M=re.compile(r'^P-(1DS|2DS|1DP|2DP|DS[MFN]|DP[MFN]|1GS|2GS|1GP|2GP|GS[MFN]|GP[MFN])$')
BARE=re.compile(r"^(him|Him|them|Them|you|You|me|Me|it|It|her|Her|us|Us)([?!.’,;]*)$")
PREP={'es':r'(?:^|\s)(de|a|con|para|por|en|sobre|contra|ante|entre|hacia|sin|tras|desde|hasta|según)$',
      'pt':r'(?:^|\s)(de|a|com|para|por|em|sobre|contra|ante|perante|entre|sem|até|desde|após)$'}
# person/number/gender key -> (stressed, dative clitic, accusative clitic)
FORMS={
 '1S':(('mí','me','me'),('mim','me','me')),
 '2S':(('ti','te','te'),('ti','te','te')),
 '1P':(('nosotros','nos','nos'),('nós','nos','nos')),
 '2P':(('vosotros','os','os'),('vós','vos','vos')),
 'SM':(('él','le','lo'),('ele','lhe','o')),
 'SF':(('ella','le','la'),('ela','lhe','a')),
 'SN':(('él','le','lo'),('ele','lhe','o')),
 'PM':(('ellos','les','los'),('eles','lhes','os')),
 'PF':(('ellas','les','las'),('elas','lhes','as')),
 'PN':(('ellos','les','los'),('eles','lhes','os')),
}
def parse(m):
    c=m[2:]
    if c[0] in '12': return c[1], c[0]+c[2]
    return c[0], c[1:]
# Greek verbs with a dative object that Spanish and Portuguese take as a
# direct object: follow, rebuke, worship, help.
TRANSITIVE={'G0190','G2008','G4352','G0997'}
# Greek verbs of remembering with a genitive: "acuérdate de mí", "lembra-te de mim".
REMEMBER={'G3403','G3415','G3421'}
DE={'es':lambda st: 'de '+st,'pt':lambda st: {'ele':'dele','ela':'dela','eles':'deles','elas':'delas'}.get(st,'de '+st)}
cnt=collections.Counter()
want={'es':collections.defaultdict(dict),'pt':collections.defaultdict(dict)}
for v,ws in byv.items():
    if v//1000000<40: continue
    for k,(pos,g,i) in enumerate(ws):
        u=U[i]
        if not M.match(u['morph']) or not BARE.match(u['gloss']): continue
        case,key=parse(u['morph'])
        word,punct=BARE.match(u['gloss']).groups()
        near=[U[ws[j][2]]['morph'] for j in range(max(0,k-2),min(len(ws),k+3)) if j!=k]
        partic=any(re.match(r'V-..P-'+case,m) for m in near)
        before=[w for w in ws[:k] if w[0]<pos]
        p=before[-1] if before else None
        for l in want:
            st,dat,acc=FORMS[key][0 if l=='es' else 1]
            prep = p and (U[p[2]]['morph'].startswith('PREP') or re.search(PREP[l],(text(T,O,l,p[2],v,p[0]) or '').rstrip(']>').strip()))
            if prep: t=st; kind='prep'
            elif partic: t=('a '+st) if case=='D' else st; kind='partic'
            elif punct and l=='es': t='a '+st; kind='punct'
            elif case=='D' and p and U[p[2]]['strongs'] in TRANSITIVE: t=acc; kind='clitic-acc'
            elif case=='G' and p and U[p[2]]['strongs'] in REMEMBER: t=DE[l](st); kind='remember'
            else: t=dat if case=='D' else acc; kind='clitic'
            cnt[(l,case,kind)]+=1
            if word[0].isupper():
                t=('a '+t[2].upper()+t[3:]) if t.startswith('a ') else t[0].upper()+t[1:]
            want[l][i][f'{v}.{pos}']=t+punct
changes=collections.Counter(); files={}
for l in want:
    for i,places in want[l].items():
        f=F[l][i]; j=files.get(f) or json.load(open(f)); files[f]=j
        common=collections.Counter(places.values()).most_common(1)[0][0]
        old=j.get('occurrences',{}).get(i,{})
        for p,t in places.items():
            if (old.get(p) or T[l][i])!=t: changes[l]+=1
        j['glosses'][i]=common
        new={p:t for p,t in places.items() if t!=common}
        for p,t in old.items():
            if p not in places: new[p]=t
        occ=j.setdefault('occurrences',{})
        if new: occ[i]=dict(sorted(new.items()))
        else: occ.pop(i,None)
for f,j in files.items():
    raw=open(f).read()
    open(f,'w').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
print(sorted(cnt.items())); print(changes)
