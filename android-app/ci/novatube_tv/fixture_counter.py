"""Filtre de mire 1080p. Chaque dixième de seconde inscrit un compteur
redondant au centre, lisible sur la capture composée de l'écran."""
def filtres():
    parts = []
    # Positions normalisées au centre, tolérantes au léger letterboxing Android.
    for i in range(6):
        x = 480 + i * 160
        bit = f"mod(floor(t*10/{2**i}),2)"
        for y, inverse in ((365, False), (565, True)):
            parts.append(f"drawbox=x={x}:y={y}:w=160:h=150:color=black:t=fill")
            condition = f"lt({bit},0.5)" if inverse else f"gte({bit},0.5)"
            parts.append(f"drawbox=x={x}:y={y}:w=160:h=150:color=white:t=fill:enable='{condition}'")
    return ','.join(parts)

if __name__ == '__main__':
    print(filtres())
