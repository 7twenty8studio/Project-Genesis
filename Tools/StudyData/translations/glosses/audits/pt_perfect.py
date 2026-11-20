"""Portuguese "tem/tenho + participle" for a completed Hebrew or Greek action
(the full review, 19 November 2026): in Brazil the compound perfect means
something going on until now ("tenho dito" = I keep saying), so a finished
act takes the simple past ("disse"). Each gloss was read with its verses;
the ones that are an ongoing state kept the compound form and aren't in
pt_perfect.json. Only a gloss still reading the old text is changed, so
this can run again."""
import collections
from lib import *
U, T, O, F, byv = load()
want = json.load(open(os.path.join(HERE, 'pt_perfect.json'), encoding='utf-8'))
files = {}; done = collections.Counter()
for i, w in want.items():
    if i not in F['pt']: done['missing'] += 1; continue
    path = F['pt'][i]
    j = files.get(path) or json.load(open(path, encoding='utf-8'))
    changed = False
    if j['glosses'][i] == w['from']:
        j['glosses'][i] = w['to']; changed = True; done['glosses'] += 1
    occ = j.get('occurrences', {}).get(i)
    if occ:
        d = {p: (w['to'] if t == w['from'] else t) for p, t in occ.items()}
        d = {p: t for p, t in d.items() if t != j['glosses'][i]}
        if d != occ:
            changed = True; done['occurrences'] += 1
            if d: j['occurrences'][i] = dict(sorted(d.items()))
            else: j['occurrences'].pop(i)
    if changed: files[path] = j
for path, j in files.items():
    raw = open(path, encoding='utf-8').read()
    open(path, 'w', encoding='utf-8').write(json.dumps(j, ensure_ascii=False, indent=1) + ('\n' if raw.endswith('\n') else ''))
print('pt perfect:', dict(done))
