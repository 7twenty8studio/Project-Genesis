"""Word forms the full verse-by-verse review (19 November 2026) found in
many places, fixed wherever they occur (base glosses and verse-specific
ones alike):

- an article written twice, once in a contraction and once in brackets
  ("del [el] polvo", "da [a] boca de" → "del polvo", "da boca de");
- Portuguese prepositions left uncontracted ("em o lugar" → "no lugar",
  "por o tempo" → "pelo tempo", "de os três" → "dos três", "em estas" →
  "nestas");
- Spanish "entre mí" / "entre ti" for "between me / you" (H996): after
  "entre" Spanish uses "yo" and "tú";
- Spanish "le(s)" with servir (H5647, serve): its object is direct,
  "lo servirás", "servirlos".
"""
import collections, sys
from lib import *
U=None   # set by the caller (verse_fixes.py uses the rules too)

def es_rules(t, i):
    # keep the supplied-word mark on the article: "del [el] polvo" → "de[l] polvo"
    t = re.sub(r'\b(de|a)l ([\[<])el([\]>])(?= |$)', r'\1\2l\3', t)
    s = U[i]['strongs']
    if s.startswith('H0996'):
        t = re.sub(r'\bentre mí\b', 'entre yo', t)
        t = re.sub(r'\bentre ti\b', 'entre tú', t)
    if s.startswith('H7227') and '[people]' in U[i]['gloss']:
        t = re.sub(r'\b(<?)los(>?) muchos \[pueblos\]', r'\1las\2 muchas [personas]', t)
        t = t.replace('muchos [pueblos]', 'muchas [personas]')
    t = t.replace('compasion<es>', 'compasión<es>')
    if s.startswith('H5647'):
        t = re.sub(r'\ble (?=sirv|serv)', 'lo ', t)
        t = re.sub(r'\bles (?=sirv|serv)', 'los ', t)
        t = re.sub(r'\bservirle\b', 'servirlo', t)
        t = re.sub(r'\bservirles\b', 'servirlos', t)
    return t

PT_CONTRACT = {('em','o'):'no',('em','a'):'na',('em','os'):'nos',('em','as'):'nas',
               ('por','o'):'pelo',('por','a'):'pela',('por','os'):'pelos',('por','as'):'pelas',
               ('de','o'):'do',('de','a'):'da',('de','os'):'dos',('de','as'):'das'}
for d in ('este','esta','estes','estas','esse','essa','esses','essas','aquele','aquela','aqueles','aquelas'):
    PT_CONTRACT[('em',d)]='n'+d
    PT_CONTRACT[('de',d)]='d'+d

def pt_rules(t, i):
    if U[i]['strongs'].startswith('H7227') and '[people]' in U[i]['gloss']:
        t = re.sub(r'\baos muitos \[povos\]', 'às muitas [pessoas]', t)
        t = re.sub(r'\b(<?)os(>?) muitos \[povos\]', r'\1as\2 muitas [pessoas]', t)
        t = t.replace('muitos [povos]', 'muitas [pessoas]')
    t = t.replace('compaix<ões>', 'compaixão<ões>')
    # נֵכָר "foreignness": "estranheza" is oddness in Brazil
    t = t.replace('<a> estranheza', '<o> estrangeiro').replace('estranheza', 'estrangeiro')
    # "da [a] boca" → "d[a] boca": one article, still marked as supplied
    t = re.sub(r'\b(n|d|a|pel)(o|a|os|as) ([\[<])\2([\]>])(?= |$)', r'\1\3\2\4', t)
    def c(m):
        return PT_CONTRACT.get((m.group(1), m.group(2)), m.group(0))   # "por" + a demonstrative stays
    # only plain words: "em [o]" and "de <a>" stay as the interlinear writes them
    t = re.sub(r'(?<![\[<\w])(em|por|de) (o|a|os|as|este|esta|estes|estas|esse|essa|esses|essas|aquele|aquela|aqueles|aquelas)(?= )', c, t)
    return t

RULES = {'es': es_rules, 'pt': pt_rules}

if __name__ == '__main__':
  U,T,O,F,byv=load()
  changed = collections.Counter(); files = {}; log = []
  for l in ('es', 'pt'):
      for i in list(T[l]):
          path = F[l][i]
          j = files.get(path) or json.load(open(path, encoding='utf-8'))
          base = j['glosses'][i]; nb = RULES[l](base, i)
          occ = j.get('occurrences', {}).get(i, {})
          nocc = {p: RULES[l](t, i) for p, t in occ.items()}
          if nb == base and nocc == occ: continue
          files[path] = j
          if nb != base:
              j['glosses'][i] = nb; changed[l] += U[i]['count']; log.append((l, base, nb))
          for p, t in nocc.items():
              if t != occ[p]: changed[l] += 1; log.append((l, occ[p], t))
          d = {p: t for p, t in nocc.items() if t != nb}
          if d: j['occurrences'][i] = dict(sorted(d.items()))
          else: j.get('occurrences', {}).pop(i, None)
  if '--show' in sys.argv:
      for x in log: print(*x, sep=' | ')
  if '--apply' in sys.argv:
      for path, j in files.items():
          raw = open(path, encoding='utf-8').read()
          open(path, 'w', encoding='utf-8').write(json.dumps(j, ensure_ascii=False, indent=1) + ('\n' if raw.endswith('\n') else ''))
  print('forms:', dict(changed))
