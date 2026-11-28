# Bande centrale de 30 cases, décodable sur une capture 16:9 plein écran.
# La signature et la parité écartent les images de menu ou masquées par un OSD.
SIGNATURE = (1, 0, 1, 1, 0, 1, 0)
C_SIGNATURE = (0, 1, 0, 0, 1, 0, 1)
COUNTER_BITS = 20
CELLS = 30


def marker(channel):
    digits = [f'mod(floor(n/{1 << bit}),2)' for bit in range(COUNTER_BITS)]
    if channel not in ('A', 'B', 'C'):
        raise ValueError('Chaîne inconnue.')
    signature = C_SIGNATURE if channel == 'C' else SIGNATURE
    bits = [str(i) for i in signature] + [str(int(channel == 'B'))] + digits
    bits.extend(['mod(' + '+'.join(digits) + ',2)', '1'])
    return ','.join(
        f"drawbox=x={480 + 32 * index}:y=640:w=32:h=20:color=white:t=fill:enable='{value}'"
        for index, value in enumerate(bits) if value != '0'
    )


