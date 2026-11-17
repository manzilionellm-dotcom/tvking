"""Calcule les positions DER de l'enveloppe CMS AES du seul APK de ce contrôle."""
def element(data, pos, expected):
    if data[pos] != expected:
        raise ValueError(f'Balise DER inattendue à {pos}')
    first = data[pos+1]
    if first < 128:
        return pos+2, pos+2+first
    count = first-128
    if not 1 <= count <= 5:
        raise ValueError('Longueur DER inattendue')
    start = pos+2+count
    size = int.from_bytes(data[pos+2:start], 'big')
    if start+size > len(data):
        raise ValueError('Enveloppe tronquée')
    return start, start+size

def cms_parts(data):
    outer,end = element(data,0,0x30)
    assert end == len(data)
    _,after_oid=element(data,outer,0x06)
    content,_=element(data,after_oid,0xa0)
    env,_=element(data,content,0x30)
    _,after_version=element(data,env,0x02)
    recipients,after_recipients=element(data,after_version,0x31)
    rcpt,_=element(data,recipients,0x30)
    _,identifier=element(data,rcpt,0x02)
    _,algorithm=element(data,identifier,0x30)
    _,keypos=element(data,algorithm,0x30)
    k,ke=element(data,keypos,0x04)
    encrypted_info,_=element(data,after_recipients,0x30)
    _,alg=element(data,encrypted_info,0x06)
    alg_params,encrypted=element(data,alg,0x30)
    _,param=element(data,alg_params,0x06)
    iv,ive=element(data,param,0x04)
    a,b=element(data,encrypted,0x80)
    assert ive-iv==16 and ke-k in (256,384,512)
    return bytes(data[k:ke]),bytes(data[iv:ive]),(a,b)
