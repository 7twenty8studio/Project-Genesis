"""Gender agreement of Greek articles, adjectives, demonstratives and
possessives with the Spanish/Portuguese noun they go with (the Greek noun
of the same case, number and gender: the first such word after an article,
the nearest such noun for the others). Fixes the modifier in that verse."""
from lib import *
from gender import gender, ES_M, PT_M
import collections, sys
U,T,O,F,byv=load()
ES_M|={'guarda','guardas','hades'}; PT_M|={'guarda','guardas','hades'}
SKIPHEAD={'mar','mares','cualquiera','cualquier','alguien','nadie','uno','qualquer','alguém','ninguém','cada'}
def cng(m):
    m=m.split(' + ')[0]
    mm=re.match(r'^(?:T|A|D|N|K|Q)-([NGDAV])([SP])([MFN])(-\w+)?$',m)
    if mm: return mm.groups()[:3], mm.group(4)
    mm=re.match(r'^S-\d[SP]([NGDAV])([SP])([MFN])$',m)
    if mm: return mm.groups(), None
    mm=re.match(r'^V-\w+P-([NGDAV])([SP])([MFN])$',m)
    if mm: return mm.groups(), 'participle'
    return None, None
STOP={'es':set('de del a al en el la los las lo un una unos unas y o para por con e u ni que no muy más tan arriba abajo fuera dentro encima afuera adentro cerca lejos aquí allí allá ahora así'.split()),
      'pt':set('de do da dos das a à ao aos às em no na nos nas o os as um uma uns umas e ou nem para por pelo pela pelos pelas com que não muito mais tão cima baixo fora dentro perto longe aqui ali lá agora assim'.split())}
NEUTER={'es':{'esto','eso','aquello','ello','lo','todo lo','lo que'},'pt':{'isto','isso','aquilo','o que'}}
PAIRS={'es':[('el','la'),('los','las'),('del','de la'),('al','a la'),('un','una'),('unos','unas'),('este','esta'),('estos','estas'),('ese','esa'),('esos','esas'),('aquel','aquella'),('aquellos','aquellas'),('mío','mía'),('míos','mías'),('tuyo','tuya'),('suyo','suya'),('nuestro','nuestra'),('nuestros','nuestras'),('vuestro','vuestra'),('vuestros','vuestras'),('ninguno','ninguna'),('ningún','ninguna'),('algún','alguna'),('primer','primera'),('tercer','tercera'),('buen','buena'),('mal','mala')],
       'pt':[('o','a'),('os','as'),('do','da'),('dos','das'),('no','na'),('nos','nas'),('ao','à'),('aos','às'),('pelo','pela'),('pelos','pelas'),('um','uma'),('uns','umas'),('este','esta'),('estes','estas'),('esse','essa'),('esses','essas'),('aquele','aquela'),('aqueles','aquelas'),('meu','minha'),('meus','minhas'),('teu','tua'),('teus','tuas'),('seu','sua'),('seus','suas'),('nosso','nossa'),('nossos','nossas'),('vosso','vossa'),('vossos','vossas'),('bom','boa'),('bons','boas'),('mau','má'),('maus','más'),('nenhum','nenhuma'),('algum','alguma'),('ele','ela'),('eles','elas')]}
GEN={l:{} for l in PAIRS}; SW={l:{} for l in PAIRS}
for l,ps in PAIRS.items():
    for m,f in ps:
        if ' ' not in m: GEN[l][m]='M'
        if ' ' not in f: GEN[l][f]='F'
        SW[l][(m,'F')]=f; SW[l][(f,'M')]=m
EXC=('ista','istas','cida','cidas','ita','itas','ota','otas','eta','etas','ía','ías')
def adjgender(w):
    if len(w)<3 or w.endswith(('ão','ãos','ões')): return None
    if w.endswith(('o','os')): return 'M'
    if w.endswith(('a','as')) and not w.endswith(EXC): return 'F'
    return None
TOK=re.compile(r"[\wáéíóúñãõâêôçàü]+",re.I)
# Words the translations already use: an adjective is only changed to a
# form that's attested ("nueva" → "nuevo"), never made up ("pureza" → "purezo").
VOCAB={l:set() for l in ('es','pt')}
for _l in VOCAB:
    for _t in list(T[_l].values())+[x for (_i,_p),x in O[_l].items()]:
        VOCAB[_l].update(w.lower() for w in TOK.findall(_t))
def words(t): return [m for m in TOK.finditer(t or '')]
def modgender(l,kind,t):
    ws=[m.group(0).lower() for m in words(re.sub(r'\[[^\]]*\]','',t or ''))]
    low=' '.join(ws)
    if any(low==n or low.startswith(n+' ') for n in NEUTER[l]): return None
    for w in ws:
        if w in GEN[l]: return GEN[l][w]
    if kind=='T': return None
    for w in reversed(ws):
        if w in STOP[l]: continue
        return adjgender(w)
    return None
def head(l,t):
    t=re.sub(r'\[[^\]]*\]','',t or '')
    for m in words(t):
        w=m.group(0).lower()
        if w in STOP[l]: continue
        return w
    return None
def fix(l,kind,t,want):
    """Turn every gendered word of the modifier to `want`."""
    out=[];last=0
    ms=words(t)
    # the adjective: last non-stop word not in the pairs tables
    adj=None
    if kind!='T':
        for m in reversed(ms):
            w=m.group(0).lower()
            if w in STOP[l] or w in GEN[l]: continue
            adj=m; break
    for m in ms:
        w=m.group(0); lw=w.lower(); new=None
        if kind!='T' and l=='pt' and lw in ('a','as','o','os','à','às','no','nos','na','nas'): new=None
        elif lw in ('tudo','todo lo'): new=None
        elif (lw,want) in SW[l]: new=SW[l][(lw,want)]
        elif m is adj and adjgender(lw) and adjgender(lw)!=want:
            if want=='F': new=re.sub(r'o(s?)$',r'a\1',lw)
            else: new=re.sub(r'a(s?)$',r'o\1',lw)
            if new not in VOCAB[l] or lw in ('cada','grávida','grávidas'): new=None
        if new:
            if w[0].isupper(): new=new[0].upper()+new[1:]
            out.append(t[last:m.start()]); out.append(new); last=m.end()
    out.append(t[last:])
    r=''.join(out)
    if l=='es':
        r=re.sub(r'\b([Aa]) el\b',lambda m:m.group(1)+'l',r)
        r=re.sub(r'\b([Dd])e el\b',lambda m:m.group(1)+'el',r)
    return r
changes={'es':{},'pt':{}}; log=[]
for v,ws in byv.items():
    if v//1000000<40: continue
    info=[(pos,i,U[i]['morph'])+cng(U[i]['morph']) for pos,g,i in ws]
    for k,(pos,i,m,c,suf) in enumerate(info):
        if not c: continue
        kind=m.split('-')[0]
        if kind in ('N','V'): continue
        hn=None
        if kind=='T':
            for j in range(k+1,min(len(info),k+6)):
                if info[j][3]==c:
                    if info[j][2].startswith('N-'): hn=j
                    elif info[j][2].split('-')[0] in ('A','S','D'):
                        # ἡ ἐντολὴ ἡ ἐμή: the article of an adjective that goes with a noun
                        for jj in sorted(range(max(0,j-4),min(len(info),j+5)),key=lambda x:abs(x-j)):
                            if jj not in (j,k) and info[jj][3]==c and info[jj][2].startswith('N-'): hn=jj; break
                    break
        else:
            for j in sorted(range(max(0,k-4),min(len(info),k+5)),key=lambda j:abs(j-k)):
                if j!=k and info[j][3]==c and info[j][2].startswith('N-'): hn=j; break
        if hn is None or info[hn][4]: continue
        if kind!='T':
            eg=U[i]['gloss']
            if re.match(r'^(a|an|the)\b',eg,re.I) or re.search(r'\b(of|by|to|without|with|for|from|in)\b',eg) or len(re.sub(r'\[[^\]]*\]|<[^>]*>','',eg).split())>2: continue
            # next to its noun (or with only articles between)
            between=range(min(k,hn)+1,max(k,hn))
            if any(not (info[b][2].startswith('T-') or re.match(r'^P-[123]?G',info[b][2]) or (kind=='D' and U[info[b][1]]['strongs'].startswith('G1510'))) for b in between): continue
        for l in ('es','pt'):
            mt0=changes[l].get((i,f'{v}.{pos}')) or text(T,O,l,i,v,pos)
            if kind=='T':
                arts={'es':{'el','la','los','las','del','al','lo','de','a','en','por','para','con'},'pt':{'o','a','os','as','do','da','dos','das','no','na','nos','nas','ao','à','aos','às','pelo','pela','pelos','pelas','de','em','por','para','com'}}[l]
                if any(w.group(0).lower() not in arts for w in words(re.sub(r'\[[^\]]*\]','',mt0 or ''))): continue
            if kind!='T':
                content=[w.group(0).lower() for w in words(re.sub(r'\[[^\]]*\]','',mt0 or '')) if w.group(0).lower() not in STOP[l]]
                if len(content)!=1 or content[0] in ('cuatro','quatro'): continue
            mt=changes[l].get((i,f'{v}.{pos}')) or text(T,O,l,i,v,pos)
            nt=text(T,O,l,info[hn][1],v,info[hn][0])
            mg=modgender(l,kind,mt); h=head(l,nt)
            if not mg or not h or h in SKIPHEAD: continue
            ng=gender(l,h)
            if ng is None: continue
            if ng=='A':
                if kind=='T' and c[1]=='S': continue
                ng='F'
            if mg!=ng:
                new=fix(l,kind,mt,ng)
                if new!=mt and modgender(l,kind,new)==ng:
                    changes[l][(i,f'{v}.{pos}')]=new
                    log.append((l,v,kind,mt,new,nt))
if __name__=="__main__": print(collections.Counter((x[0],x[2]) for x in log), len(log))
pass
if __name__=='__main__' and '--apply' in sys.argv:
    files={}
    for l in changes:
        byid=collections.defaultdict(dict)
        for (i,p),t in changes[l].items(): byid[i][p]=t
        for i,newp in byid.items():
            f=F[l][i]; j=files.get(f) or json.load(open(f)); files[f]=j
            allp=[f'{v}.{pos}' for v,pos in OCC[i]] if False else None
            occ=j.setdefault('occurrences',{})
            cur=dict(occ.get(i,{}))
            cur.update(newp)
            # drop occurrences equal to the unit's gloss
            cur={p:t for p,t in cur.items() if t!=j['glosses'][i]}
            if cur: occ[i]=dict(sorted(cur.items()))
            else: occ.pop(i,None)
    for f,j in files.items():
        raw=open(f).read()
        open(f,'w').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
    print('applied to',len(files),'files')
