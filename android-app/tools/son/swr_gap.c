/*
 * Mesure le décalage du chemin FFmpeg de Media3 1.5.1.
 *
 * ffmpeg_jni.cc (Media3 1.5.1, le même schéma que le décodeur Jellyfin
 * 1.5.0) fait :
 *   outSamples   = swr_get_out_samples(swr, nb_samples);
 *   bufferOutSize = taille_echantillon * voies * outSamples;   // des OCTETS
 *   swr_convert(swr, &sortie, bufferOutSize, ...);             // attend des ÉCHANTILLONS
 *   sortie += bufferOutSize;                                   // avance d'OCTETS
 *
 * On rejoue la conversion planaire flottant → 16 bits entrelacé, même
 * fréquence, même nombre de voies (ce que le décodeur AAC demande).
 * On compte les échantillons en trop que l'avance d'octets ajouterait
 * entre deux trames de 1 024 (une trame AAC).
 *
 * Aucun flux. Signal synthétique.
 */
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int convertir(SwrContext *swr, int nb, int *extra_si_on_avance_trop)
{
    float *plans[2];
    plans[0] = calloc((size_t)nb, sizeof(float));
    plans[1] = calloc((size_t)nb, sizeof(float));
    if (!plans[0] || !plans[1]) return -1;
    for (int i = 0; i < nb; i++) {
        /* Voix très simple : gauche = sinus, droite = l'inverse.
         * On ne juge pas le son. On compte les échantillons. */
        plans[0][i] = 0.2f;
        plans[1][i] = -0.2f;
    }
    int borne = swr_get_out_samples(swr, nb);
    int taille = av_get_bytes_per_sample(AV_SAMPLE_FMT_S16);
    int voies = 2;
    int octets = taille * voies * borne;
    uint8_t *sortie = calloc((size_t)octets + 64, 1);
    if (!sortie) return -1;
    /* Le JNI passe le nombre d'OCTETS là où swr attend des échantillons. */
    int obtenus = swr_convert(swr, &sortie, octets, (const uint8_t **)plans, nb);
    int restants = swr_get_out_samples(swr, 0);
    int octets_reels = obtenus > 0 ? obtenus * taille * voies : 0;
    int octets_en_trop = octets - octets_reels;
    int echantillons_en_trop = octets_en_trop / (taille * voies);
    printf("trame %5d  borne %5d  obtenus %5d  octets_jni %6d  octets_reels %6d  "
           "ech_en_trop %5d  restants %d\n",
           nb, borne, obtenus, octets, octets_reels, echantillons_en_trop, restants);
    if (extra_si_on_avance_trop) *extra_si_on_avance_trop = echantillons_en_trop;
    free(plans[0]);
    free(plans[1]);
    free(sortie);
    return obtenus;
}

int main(void)
{
    SwrContext *swr = NULL;
    AVChannelLayout disposition;
    av_channel_layout_default(&disposition, 2);
    int r = swr_alloc_set_opts2(&swr,
                                &disposition, AV_SAMPLE_FMT_S16, 48000,
                                &disposition, AV_SAMPLE_FMT_FLTP, 48000,
                                0, NULL);
    if (r < 0 || swr_init(swr) < 0) {
        fprintf(stderr, "swr_init a echoue (%d)\n", r);
        return 1;
    }
    printf("conversion FLTP planaire -> S16 entrelace, 48 kHz, stereo, meme disposition\n");
    int extra = 0;
    int somme = 0;
    for (int i = 0; i < 8; i++) {
        if (convertir(swr, 1024, &extra) < 0) return 1;
        somme += extra;
    }
    printf("somme des echantillons en trop sur 8 trames AAC : %d\n", somme);
    swr_free(&swr);
    return 0;
}
