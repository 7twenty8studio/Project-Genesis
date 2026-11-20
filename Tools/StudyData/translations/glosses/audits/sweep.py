"""Follow-ups from the full review of 19 November 2026, over every verse:
the patterns the reviewers found, wherever else they occur.

1. Spanish "a él?" / "a mí!" (a stressed pronoun without its clitic) for a
   plain Greek object, where no preposition comes before: the clitic, as in
   Portuguese ("lo?", "me!"), keeping an opening ¿ or ¡.
2. A pronoun governed by a preposition further back ("μετὰ πάντων ὑμῶν",
   "ἄχρι καὶ ὑμῶν", "between you and him"): the stressed form.
3. A clitic after a gloss ending in an adverb of place that takes "de"
   ("delante", "adiante", "encima"..., and "antes" glossing a word on its own) or "junto": "delante de ellos",
   "junto a él", "adiante deles".
4. A genitive pronoun after a noun or "all" (his hand, all of you): the
   possessive "de él" / "dele", never a clitic.
5. Spanish "buen", "mal", "primer", "tercer" after their noun:
   "bueno", "malo", "primero", "tercero".
6. Verbs whose Spanish and Portuguese object differs from the Greek case:
   burlarse de / zombar de (ἐμπαίζω), servir (λατρεύω), amenazar /
   ameaçar, mirar / olhar (ἐμβλέπω) take a direct object; preguntar /
   perguntar (ἐπερωτάω, ἐρωτάω) and suplicar (δέομαι) an indirect one.
7. Spanish "el agua", "el alma", "del arca": a feminine noun beginning
   with a stressed a takes el / un in the singular (the article a word of
   its own before it).
Like the other audits it only changes what it finds, so it can run again."""
import collections
from lib import *
U,T,O,F,byv=load()
STRESSED={'es':{'me':'mí','te':'ti','nos':'nosotros','os':'vosotros','lo':'él','la':'ella','los':'ellos','las':'ellas','le':'él','les':'ellos'},
          'pt':{'me':'mim','te':'ti','nos':'nós','vos':'vós','o':'ele','a':'ela','os':'eles','as':'elas','lhe':'ele','lhes':'eles'}}
# person/number/gender -> (stressed, dative clitic, accusative clitic)
FORMS={
 '1S':(('mí','me','me'),('mim','me','me')), '2S':(('ti','te','te'),('ti','te','te')),
 '1P':(('nosotros','nos','nos'),('nós','nos','nos')), '2P':(('vosotros','os','os'),('vós','vos','vos')),
 'SM':(('él','le','lo'),('ele','lhe','o')), 'SF':(('ella','le','la'),('ela','lhe','a')), 'SN':(('él','le','lo'),('ele','lhe','o')),
 'PM':(('ellos','les','los'),('eles','lhes','os')), 'PF':(('ellas','les','las'),('elas','lhes','as')), 'PN':(('ellos','les','los'),('eles','lhes','os')),
}
PM=re.compile(r'^P-(?:([12])([ADG])([SP])|([ADG])([SP])([MFN]))$')
BARE=re.compile(r"^(him|Him|them|Them|you|You|me|Me|it|It|her|Her|us|Us)([?!.’,;]*)$")
PREP={'es':r'(?:^|\s)(de|a|con|para|por|en|sobre|contra|ante|entre|hacia|sin|tras|desde|hasta|según)$',
      'pt':r'(?:^|\s)(de|a|com|para|por|em|sobre|contra|ante|perante|entre|sem|até|desde|após)$'}
DE_ADV={'es':r'(?:^|\s)(delante|detrás|encima|debajo|alrededor|dentro|enfrente)$',
        'pt':r'(?:^|\s)(adiante|diante|atrás|acima|abaixo|redor|dentro)$'}
JUNTO=r'(?:^|\s)junto$'
DE={'es':lambda s: 'de '+s,'pt':lambda s: {'ele':'dele','ela':'dela','eles':'deles','elas':'delas'}.get(s,'de '+s)}
ACC_VERBS={'G3000','G0546','G1689'}           # serve, threaten, look at: direct object
DAT_VERBS={'G1905','G2065','G1189','G0154'}   # ask, beg: indirect object (when glossed so)
ASK={'es':r'\b(pregunt|rog|supli|pid|ped)','pt':r'\b(pergunt|rog|supli|ped)'}
DE_VERBS={'G1702'}                            # mock: burlarse de / zombar de
def key(m):
    a=PM.match(m)
    if not a: return None
    if a.group(1): return a.group(2), a.group(1)+a.group(3)
    return a.group(4), a.group(5)+a.group(6)
def cap(t,up):
    if not up: return t
    if t.startswith('de ') or t.startswith('a '): h,_,r=t.partition(' '); return h+' '+r[0].upper()+r[1:]
    if t in ('dele','dela','deles','delas'): return "d'E"+t[2:]
    return t[0].upper()+t[1:]
want=collections.defaultdict(dict); why=collections.Counter()
# places a reviewer corrected by hand (review.jsonl) are left as corrected
REVIEWED=set()
for line in open(os.path.join(HERE,'review.jsonl'),encoding='utf-8'):
    if line.strip():
        r=json.loads(line)
        for p,g,i in byv.get(r['verse'],[]):
            if g==r['english']: REVIEWED.add((r['lang'],r['verse'],p))
for v,ws in byv.items():
    if v//1000000<40: continue
    for k,(pos,g,i) in enumerate(ws):
        u=U[i]; kk=key(u['morph']); m=BARE.match(u['gloss'])
        if not kk or not m: continue
        case,pn=kk; word,punct=m.groups(); up=word[0].isupper()
        before=[w for w in ws[:k] if w[0]<pos]
        prev=before[-1] if before else None
        # nearest verb before, within three words
        verb=next((U[w[2]]['strongs'] for w in reversed(before[-3:]) if U[w[2]]['morph'].startswith('V-')),None)
        for l in ('es','pt'):
            cur=text(T,O,l,i,v,pos) or ''
            lead=cur[0] if cur[:1] in '¿¡' else ''
            body=cur[len(lead):]
            st,dat,acc=FORMS[pn][0 if l=='es' else 1]
            vt=next((w for w in reversed(before[-3:]) if U[w[2]]['morph'].startswith('V-')),None)
            vtext=text(T,O,l,vt[2],v,vt[0]) if vt else ''
            if (l,v,pos) in REVIEWED: continue
            ptxt=(text(T,O,l,prev[2],v,prev[0]) or '').rstrip(']>').strip() if prev else ''
            prep_prev=prev and (U[prev[2]]['morph'].startswith('PREP') or re.search(PREP[l],ptxt))
            bare_core=re.sub(r"[?!.’,;]+$",'',body)
            is_clitic=bare_core.lower() in STRESSED[l]
            new=None
            # 2. a preposition further back, with only "and", "all", adverbs or pronouns between
            far_prep=False
            tags=[U[w[2]]['morph'] for w in before[-4:]]
            for n in range(len(tags)-1,-1,-1):
                if tags[n].startswith('PREP'):
                    mid=tags[n+1:]
                    far_prep = bool(mid) and (all(t.startswith(('CONJ','A-')) for t in mid) or (len(mid)==2 and mid[0].startswith('P-') and mid[1].startswith('CONJ')))
                    break
            if is_clitic and (re.search(DE_ADV[l],ptxt) or ptxt.lower()=='antes'): new=DE[l](st); why[(l,'adverb+de')]+=1
            elif is_clitic and re.search(JUNTO,ptxt): new='a '+st; why[(l,'junto a')]+=1
            elif is_clitic and far_prep and not prep_prev and case!='A': new=st; why[(l,'preposition further back')]+=1
            elif is_clitic and case=='G' and prev and (U[prev[2]]['morph'].startswith('N-') or re.match(r'A-GP',U[prev[2]]['morph'])): new=DE[l](st); why[(l,'possessive genitive')]+=1
            elif is_clitic and verb in DE_VERBS and case=='D' and not prep_prev: new=DE[l](st); why[(l,'burlarse de')]+=1
            elif is_clitic and verb in ACC_VERBS and case=='D' and not prep_prev and bare_core.lower()!=acc: new=acc; why[(l,'direct object verb')]+=1
            elif is_clitic and verb in DAT_VERBS and case in 'AG' and not prep_prev and pn[0] not in '12' and pn[-1]!='N' and bare_core.lower()!=dat and vtext and re.search(ASK[l],vtext,re.I): new=dat; why[(l,'indirect object verb')]+=1
            elif l=='es' and not prep_prev and not re.search(r'\b(como|semejante|igual)$',ptxt) and re.fullmatch(r'a (mí|ti|nosotros|vosotros|él|ella|ellos|ellas)',bare_core,re.I) and not re.search(DE_ADV[l]+'|'+JUNTO,ptxt) and verb not in DE_VERBS:
                new=(dat if case=='D' else acc); why[(l,'es clitic for a plain object')]+=1
            if new is None: continue
            t=lead+cap(new,up)+punct
            if t!=cur: want[(l,i)][f'{v}.{pos}']=t
# 5. Spanish short forms not followed by a noun
SHORT={'buen':'bueno','mal':'malo','primer':'primero','tercer':'tercero'}
for v,ws in byv.items():
    for k,(pos,g,i) in enumerate(ws):
        cur=text(T,O,'es',i,v,pos) or ''
        mm=re.fullmatch(r'(.*?)\b(buen|mal|primer|tercer)\b([\]>?!.,;’]*)',cur)
        if not mm: continue
        mo=U[i]['morph']
        if not (mo.startswith('A-') or re.search(r'(^|/)A[ao]',mo[1:] if mo.startswith('H') else '')): continue
        if mm.group(2)=='mal' and not U[i]['morph'].startswith('A-'): continue   # Hebrew "evil" is often the noun (el mal)
        if U[i]['morph'].startswith('A-') and U[i]['morph'].endswith('N'): continue   # "el mal", a neuter used as a noun
        if re.match(r'\W*(el|la|los|las|lo|de|del|al|y|un|una|en)\b',cur): continue
        prv=[w for w in ws[:k] if w[0]<pos]
        pm=U[prv[-1][2]]['morph'] if prv else ''
        if not (pm.startswith('N-') or re.search(r'(^|/)N[cp]',pm[1:] if pm.startswith('H') else '')): continue
        nxt=[w for w in ws[k+1:] if w[0]>pos]
        nm=U[nxt[0][2]]['morph'] if nxt else ''
        noun_next = nm.startswith('N-') or bool(re.search(r'(^|/)N[cp]',nm[1:] if nm.startswith('H') else ''))
        if noun_next: continue
        t=mm.group(1)+SHORT[mm.group(2)]+mm.group(3)
        want[('es',i)][f'{v}.{pos}']=t; why[('es','short form '+mm.group(2))]+=1
# 7. el agua, el alma
TONIC_A=r'[\[<]?(agua|alma|águila|área|arca|hambre|hacha|ala|arpa|ancla|asta|ave|habla|alba|aya|ascua)\b'
ART={'la':'el','una':'un','de la':'del','a la':'al','para la':'para el','por la':'por el','en la':'en el','con la':'con el'}
for v,ws in byv.items():
    seen=set(); prev=None
    for pos,g,i in ws:
        if pos in seen: continue
        seen.add(pos)
        t=text(T,O,'es',i,v,pos) or ''
        if prev and re.match(TONIC_A,t):
            pp,pi,pt_=prev
            m=re.fullmatch(r'([\[<]?)(la|una|de la|a la|para la|por la|en la|con la)([\]>]?)',pt_)
            if m and (pi,pp) not in [(x[2],x[0]) for x in []]:
                want[('es',pi)][f'{v}.{pp}']=m.group(1)+ART[m.group(2)]+m.group(3); why[('es','el agua')]+=1
        prev=(pos,i,t)
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
print('sweep:',sum(len(p) for p in want.values()),dict(sorted(why.items())))
if '--show' in sys.argv:
    for (l,i),places in sorted(want.items()):
        for p,t in places.items(): print(l,p,U[i]['gloss'],U[i]['morph'],'->',t)
