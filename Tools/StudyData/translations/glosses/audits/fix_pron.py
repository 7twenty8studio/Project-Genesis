"""Greek accusative personal pronouns: a clitic for an object (lo, la, los,
te, os; o, a, os, te, vos), the stressed form after a preposition (él, ti,
vosotros; ele, ti, vós), the subject form for the subject of an infinitive
(hand-picked in review.txt: S)."""
from lib import *
import collections
U,T,O,F,byv=load()
cand=json.load(open(os.path.join(HERE,'cand.json')))
S1={11,13,17,32,39,44,45,53,57,59,64,65,68,75,76,87,96,97,98,99,106}
S2={110,111,113,119,126,129,132,137,138,139,140,141,142,143,147,149,150,153,155,156,157,159,160,161,162,163,164,165,168,169,171,174,175,176,177,179,180,181,183,184,188,190,191,192,193,198,202,204,205,206,209,216}
SUBJ=S1|S2
rev=[c for c in cand if c[3]=='review']
subjects={(c[0],c[1],c[2]) for n,c in enumerate(rev) if n in SUBJ}
#            clitic      stressed      subject
FORMS={
 '1AS':(('me','mí','yo'),('me','mim','eu')),
 '2AS':(('te','ti','tú'),('te','ti','tu')),
 '1AP':(('nos','nosotros','nosotros'),('nos','nós','nós')),
 '2AP':(('os','vosotros','vosotros'),('vos','vós','vós')),
 'ASM':(('lo','él','él'),('o','ele','ele')),
 'ASF':(('la','ella','ella'),('a','ela','ela')),
 'ASN':(('lo','él','él'),('o','ele','ele')),
 'APM':(('los','ellos','ellos'),('os','eles','eles')),
 'APF':(('las','ellas','ellas'),('as','elas','elas')),
 'APN':(('los','ellos','ellos'),('os','eles','eles')),
}
BARE=re.compile(r"^(him|Him|them|Them|you|You|me|Me|it|It|her|Her|us|Us|me myself|Me myself)([?!.’,;]*)$")
def form(lang,u,kind):
    code=u['morph'][2:]
    es,pt=FORMS[code]
    f=es if lang=='es' else pt
    m=BARE.match(u['gloss']); word,punct=m.groups()
    emph=word.lower()=='me myself'
    up=word[0].isupper()
    if kind=='obj':
        if emph: t=('a mí mismo' if lang=='es' else 'a mim mesmo')
        elif punct and lang=='es': t='a '+f[1]
        else: t=f[0]
    elif kind=='prep':
        t=f[1]+((' mismo' if lang=='es' else ' mesmo') if emph else '')
    else:
        t=f[2]+((' mismo' if lang=='es' else ' mesmo') if emph else '')
    if up:
        # "a Él", "Lo", "Ti": capital on the pronoun
        if t.startswith('a '): t='a '+t[2].upper()+t[3:]
        else: t=t[0].upper()+t[1:]
    return t+punct
# targets per occurrence
want={'es':collections.defaultdict(dict),'pt':collections.defaultdict(dict)}
PREP={'es':r'(?:^|\s)(de|a|con|para|por|en|sobre|contra|ante|entre|hacia|sin|tras|desde|hasta|según)$',
      'pt':r'(?:^|\s)(de|a|com|para|por|em|sobre|contra|ante|perante|entre|sem|até|desde|após)$'}
prevof={}
for v,ws in byv.items():
    if v//1000000<40: continue
    for k,(pos,g,i) in enumerate(ws):
        # the word before this place (another edition's word at the same place doesn't count)
        before=[w for w in ws[:k] if w[0]<pos]
        if before: prevof[(v,pos)]=before[-1]
nprep=collections.Counter()
for v,pos,i,kind,_ in cand:
    k='subj' if (v,pos,i) in subjects else ('obj' if kind=='review' else kind)
    for l in want:
        kk=k
        if kk=='obj' and (v,pos) in prevof:
            ppos,_g,pi=prevof[(v,pos)]
            pt_=text(T,O,l,pi,v,ppos) or ''
            if re.search(PREP[l],pt_.rstrip(']>').strip()): kk='prep'; nprep[l]+=1
        t=form(l,U[i],kk)
        # δεῖ αὐτόν "it is necessary for him": le conviene / convém-lhe.
        ws=byv[v]; k_=[n for n,w in enumerate(ws) if w[0]==pos and w[2]==i][0]
        near={U[ws[n][2]]['strongs'] for n in (k_-1,k_+1) if 0<=n<len(ws)}
        if kk=='obj' and 'G1163' in near and U[i]['morph'][2] not in '12':
            dat={'es':{'S':'le','P':'les'},'pt':{'S':'lhe','P':'lhes'}}[l][U[i]['morph'][3]]
            m=BARE.match(U[i]['gloss']); t=(dat[0].upper()+dat[1:] if m.group(1)[0].isupper() else dat)+m.group(2)
        want[l][i][f'{v}.{pos}']=t
changes=collections.Counter()
files={}
for l in want:
    for i,places in want[l].items():
        f=F[l][i]
        j=files.get(f) or json.load(open(f)); files[f]=j
        common=collections.Counter(places.values()).most_common(1)[0][0]
        if j['glosses'][i]!=common: changes[(l,'unit')]+=1
        j['glosses'][i]=common
        occ=j.setdefault('occurrences',{})
        old=occ.get(i,{})
        new={p:t for p,t in places.items() if t!=common}
        # keep any non-pronoun occurrence (none expected)
        for p,t in old.items():
            if p not in places: new[p]=t
        if new: occ[i]=dict(sorted(new.items()))
        else: occ.pop(i,None)
        changes[(l,'occ')]+=sum(1 for p,t in places.items() if (old.get(p) or T[l][i])!=t)
for f,j in files.items():
    raw=open(f).read()
    open(f,'w').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
print(changes, len(files), nprep)
