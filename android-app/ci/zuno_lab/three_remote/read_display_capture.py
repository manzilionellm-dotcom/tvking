from regional_live_source import CELLS, COUNTER_BITS, C_SIGNATURE, SIGNATURE


def decode(row):
    if len(row) != CELLS or any(60 < value < 190 for value in row):
        return '', ''
    bits = [int(value >= 190) for value in row]
    signature = tuple(bits[:7])
    if signature not in (SIGNATURE, C_SIGNATURE) or bits[-1] != 1:
        return '', ''
    counter = bits[8:8 + COUNTER_BITS]
    if sum(counter) % 2 != bits[-2]:
        return '', ''
    if signature == C_SIGNATURE and bits[7]:
        return '', ''
    channel = 'C' if signature == C_SIGNATURE else ('B' if bits[7] else 'A')
    return channel, sum(bit << i for i, bit in enumerate(counter))


