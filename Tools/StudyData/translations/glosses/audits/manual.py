import json,glob
import os
D=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..'))
def edit(lang,uid,unit=None,occ=None):
    f=[f for f in sorted(glob.glob(f'{D}/{lang}/0*.json')) if f'"{uid}"' in open(f).read()][0]
    raw=open(f).read(); j=json.loads(raw)
    if unit is not None: j['glosses'][uid]=unit
    for p,t in (occ or {}).items():
        o=j.setdefault('occurrences',{}).setdefault(uid,{})
        if t is None: o.pop(p,None)
        else: o[p]=t
        if not o: j['occurrences'].pop(uid)
    open(f,'w').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
# Matthew 5:29 (eye), 18:8-9: masculine; 5:30 (hand): feminine. One pronoun, supplied.
edit('es','3bf6528718ddc7c5','echa [lo]',{'40005030.12':'echa [la]'})
edit('pt','3bf6528718ddc7c5','lança [-o]',{'40005030.12':'lança [-a]'})
edit('pt','ae00ec64294e80cd','e [alguns que] [os] carregavam')
# Revelation 9:21: φαρμακειῶν (G5331, a feminine noun) is "sorceries";
# STEPBible's English for it reads "sorcerers" (the TR's φαρμάκων beside it reads "sorceries").
def note(lang,uid,text):
    f=[f for f in sorted(glob.glob(f'{D}/{lang}/0*.json')) if f'"{uid}"' in open(f).read()][0]
    raw=open(f).read(); j=json.loads(raw)
    j.setdefault('notes',{})[uid]=text
    open(f,'w').write(json.dumps(j,ensure_ascii=False,indent=1)+('\n' if raw.endswith('\n') else ''))
edit('es','559954b9713eede1','hechicerías')
edit('pt','559954b9713eede1','feitiçarias')
NOTE='φαρμακειῶν (G5331, N-GPF) is "sorceries"; STEPBible\'s English reads "sorcerers", so the morphology and the lexicon were followed (Rev 9:21)'
note('es','559954b9713eede1',NOTE); note('pt','559954b9713eede1',NOTE)
