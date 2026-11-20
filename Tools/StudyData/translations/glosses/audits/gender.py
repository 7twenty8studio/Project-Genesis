import re
def plur(ws):
    out=set()
    for w in ws:
        out.add(w)
        if re.search(r'[aeiouáéóãêíúô]$',w): out.add(w+'s')
        elif w.endswith('z'): out.add(w[:-1]+'ces')
        else: out.add(w+'es')
    return out
ES_F=plur('ley grey carne fe muerte luz voz mujer mente cruz noche sangre gente cárcel señal paz imagen simiente fiebre parte llave calle red sal sazón serpiente vid raíz hoz tribu virgen piel flor frente nave torre suerte leche clase matriz dracma sirte nube fuente cohorte costumbre lumbre plebe especie pared sed salud miel hiel mano labor faz nariz cerviz mies madre perdiz codorniz cicatriz lombriz superficie base hueste corte'.split())
ES_F|={'imágenes','vírgenes','cárceles','raíces','cruces','luces','voces','mujeres','madres','leyes','manos','artes','sazones','redes','paredes','tribus','mieses'}
ES_M=plur('día profeta mapa planeta idioma tema sistema programa problema poema clima dogma drama fantasma enigma anatema carisma aroma patriarca tetrarca monarca evangelista bautista homicida hipócrita escriba mesías cometa sofá papá idólatra exorcista espía flautista cambista helenista asiarca centurión juez pez guía compatriota alfa adúltero'.split())|{'centuriones','jueces','peces','guías','alfa'}
ES_F|=plur('agua alma ave hacha área águila arca ala alba arpa ancla hambre habla arma asna aula ansia asta hada'.split())
ES_A={'agua','alma','ave','hacha','área','águila','arca','ala','alba','arpa','ancla','hambre','habla','arma','asna','aula','ansia','asta','hada','haz'}
PT_F=plur('lei grei carne fé morte luz voz mulher mente cruz noite gente fonte ponte sorte torre nave chave rede parede sede febre lebre serpente semente frente parte arte árvore fome nuvem ordem origem virgem imagem viagem margem coragem mensagem linhagem pele cal flor dor cor colher mão tribo paz raiz foice face cerviz matriz perdiz codorniz vez irmã lã maçã manhã romã rã mó hoste corte espécie superfície base plebe tez rês vontade comunhão corrente veste trave coorte paixão região religião legião opinião união ocasião velhice tolice'.split())|{'mãos','raízes','cruzes','luzes','vozes','nuvens','virgens','imagens','viagens','ordens','mensagens','flores','dores','cores','leis','mulheres'}
PT_M=plur('dia profeta mapa planeta idioma tema sistema programa problema poema clima dogma drama fantasma enigma anátema carisma aroma patriarca tetrarca monarca evangelista batista homicida hipócrita escriba messias cometa sofá papa idólatra exorcista espiã flautista cambista helenista asiarca pão irmão coração cão chão verão sermão dragão trovão leão ladrão patrão cristão cidadão pagão órfão grão capitão centurião ancião cálice artífice jordão sangue leite peixe dente monte ventre nome homem bem sal sinal nariz juiz mel fel maná guia compatriota alfa'.split())|{'pães','irmãos','corações','cães','leões','ladrões','cidadãos','cristãos','pagãos','órfãos','grãos','capitães','juízes'}
NONNOUN={'es','eres','que','como','siendo','lo','dar','comer','sufrir','crujir','delante','divinamente','cerca','cierto','oh','son','era','fue','está','hay','ser','estar','sumo','tercer','gran','buen','poca','plena','completa','buenas','falsa','sagrada','falso','profundo','grandes','malos','otros','mortal','natural','moral','estéril','ardiente','glorioso','injusto','indocto','justo','principal','principales','pobre','joven','jóvenes','amado','todopoderoso','sumos'}
def gender(L,w):
    w=w.lstrip('¿¡')
    if w in NONNOUN: return None
    if L=='es':
        if w in ES_A: return 'A'
        if w in ES_F: return 'F'
        if w in ES_M: return 'M'
        if re.search(r'(a|as|ión|iones|dad|dades|tad|tades|tud|tudes|umbre|umbres|ez|eza|ezas|sis)$',w): return 'F'
        return 'M'
    else:
        if w in PT_F: return 'F'
        if w in PT_M: return 'M'
        if re.search(r'(a|as|ção|ções|são|sões|dade|dades|tude|tudes|ade|ades|gem|gens|ez|eza|ezas|ise|ises|ose|dão|dões)$',w): return 'F'
        return 'M'
PT_F|={'paixões','regiões','religiões','legiões','opiniões','uniões','ocasiões','comunhões','ave','aves','hostes','espécies'}

PT_F|={'mãe','mães'}
ES_M|={'escorpión','escorpiones','anfitrión','anfitriones','gorrión'}
