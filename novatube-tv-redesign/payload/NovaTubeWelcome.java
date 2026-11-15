package com.manthefew.direct;

import android.app.Activity;
import android.app.AlertDialog;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/** Simple source-entry screen. It never grants a licence or creates a video view.
 * Activation, device identity and playback remain owned by the existing bridge.
 */
final class NovaTubeWelcome {
    private final Activity activity;
    private final TextView state, explanation, identity, assistance, offer, sources;
    private final Button continueButton, addButton, xtreamButton, storedButton, activateButton, refreshButton;
    private AlertDialog helpDialog;

    NovaTubeWelcome(final Activity activity) {
        this.activity = activity;
        AtlasAppearance.Theme theme = AtlasAppearance.welcomeTheme(activity);
        NovaTubeAtmosphere background = new NovaTubeAtmosphere(activity, theme);
        background.setTag("novatube.commercial.welcome");
        ScrollView scroll = new ScrollView(activity);
        scroll.setFillViewport(true);
        scroll.setClipToPadding(false);
        scroll.setPadding(dp(26), dp(18), dp(26), dp(18));
        LinearLayout content = new LinearLayout(activity);
        content.setOrientation(LinearLayout.VERTICAL);
        scroll.addView(content, new ScrollView.LayoutParams(-1, -2));
        int width = Math.min(dp(920), activity.getResources().getDisplayMetrics().widthPixels);
        background.addView(scroll, new FrameLayout.LayoutParams(width, -1, Gravity.CENTER));

        content.addView(background.wordmark(), new LinearLayout.LayoutParams(-1, dp(52)));
        content.addView(text("Votre télévision, simplement.", 18, theme.muted), row(4));
        TextView instruction = text("Ajoutez la liste de votre fournisseur pour commencer.", 16, theme.text);
        content.addView(instruction, row(18));

        LinearLayout choices = new LinearLayout(activity);
        final boolean wide = activity.getResources().getConfiguration().screenWidthDp >= 600;
        choices.setOrientation(wide ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        addButton = action("Ajouter un lien M3U", theme);
        addButton.setContentDescription("Ajouter une liste M3U, adresse HTTP ou HTTPS");
        addButton.setOnClickListener(v -> DirectSources.showWelcomeEditor(activity, true));
        xtreamButton = action("Se connecter avec Xtream", theme);
        xtreamButton.setContentDescription("Connexion Xtream Codes avec serveur, identifiant et mot de passe");
        xtreamButton.setOnClickListener(v -> DirectSources.showWelcomeEditor(activity, false));
        if (wide) {
            choices.addView(addButton, new LinearLayout.LayoutParams(0, dp(76), 1f));
            LinearLayout.LayoutParams second = new LinearLayout.LayoutParams(0, dp(76), 1f);
            second.leftMargin = dp(14);
            choices.addView(xtreamButton, second);
            addButton.setNextFocusRightId(xtreamButton.getId());
            xtreamButton.setNextFocusLeftId(addButton.getId());
        } else {
            choices.addView(addButton, new LinearLayout.LayoutParams(-1, dp(64)));
            LinearLayout.LayoutParams second = new LinearLayout.LayoutParams(-1, dp(64));
            second.topMargin = dp(10);
            choices.addView(xtreamButton, second);
            addButton.setNextFocusDownId(xtreamButton.getId());
            xtreamButton.setNextFocusUpId(addButton.getId());
        }
        content.addView(choices, row(12));

        storedButton = action("Mes listes", theme);
        storedButton.setOnClickListener(v -> DirectSources.showWelcomeSources(activity));
        content.addView(storedButton, row(10));
        continueButton = action("Regarder ma liste", theme);
        continueButton.setOnClickListener(v -> AtlasActivation.openFromWelcome(activity));
        content.addView(continueButton, row(10));

        LinearLayout statusCard = new LinearLayout(activity);
        statusCard.setOrientation(LinearLayout.VERTICAL);
        statusCard.setPadding(dp(18), dp(12), dp(18), dp(12));
        GradientDrawable statusBackground = new GradientDrawable();
        statusBackground.setColor(theme.surface);
        statusBackground.setCornerRadius(dp(12));
        statusBackground.setStroke(dp(1), AtlasAppearance.mix(theme.surface, theme.accent, 25));
        statusCard.setBackground(statusBackground);
        content.addView(statusCard, row(16));
        state = text("Vérification de votre accès…", 17, theme.text);
        state.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        statusCard.addView(state, row(0));
        explanation = text("Vous pouvez déjà enregistrer votre liste.", 14, theme.muted);
        statusCard.addView(explanation, row(5));
        offer = text("", 14, theme.muted);
        statusCard.addView(offer, row(5));
        sources = text("", 14, theme.muted);
        statusCard.addView(sources, row(5));

        activateButton = action("Demander l’activation · 9,99 €", theme);
        activateButton.setOnClickListener(v -> AtlasActivation.openPurchase(activity));
        content.addView(activateButton, row(10));
        refreshButton = action("Actualiser mon accès", theme);
        refreshButton.setOnClickListener(v -> AtlasActivation.refreshNow());
        content.addView(refreshButton, row(10));

        identity = text("", 15, theme.text);
        content.addView(identity, row(16));
        assistance = text("", 14, theme.muted);
        assistance.setTextIsSelectable(true);
        content.addView(assistance, row(5));
        content.addView(text("NovaTube est un lecteur : aucune chaîne ni aucun abonnement TV n’est fourni.",
                13, theme.muted), row(8));
        activity.setContentView(background);
        updateFocusPaths();
        addButton.requestFocus();
    }

    void update(String title, String message, String mac, String helpCode,
                boolean allowed, boolean paid, boolean offerVisible, String trialLabel, String durationLabel,
                boolean checkout, int sourceCount) {
        state.setText(title);
        explanation.setText(message);
        identity.setText("Code de l’appareil : " + (mac == null ? "…" : mac));
        assistance.setText(helpCode == null ? "" : "Code d’assistance temporaire : " + helpCode);
        assistance.setVisibility(helpCode == null ? View.GONE : View.VISIBLE);
        offer.setVisibility(paid || !offerVisible ? View.GONE : View.VISIBLE);
        offer.setText((trialLabel.length() > 0 ? trialLabel : "10 jours d’essai pour les nouveaux appareils")
                + " · " + (durationLabel.length() > 0 ? durationLabel : "Activation")
                + " à 9,99 € · Sans prélèvement automatique.");
        sources.setVisibility(sourceCount > 0 ? View.VISIBLE : View.GONE);
        sources.setText(sourceCount + (sourceCount == 1 ? " liste enregistrée" : " listes enregistrées"));
        continueButton.setVisibility(allowed && sourceCount > 0 ? View.VISIBLE : View.GONE);
        storedButton.setVisibility(sourceCount > 0 ? View.VISIBLE : View.GONE);
        activateButton.setVisibility(paid || !offerVisible ? View.GONE : View.VISIBLE);
        activateButton.setText(checkout ? "Activer NovaTube · 9,99 €" : "Demander l’activation · 9,99 €");
        updateFocusPaths();
        // Do not steal focus during a background licence refresh or while an editor is open.
    }

    /** Skip hidden optional actions; no focus scaling, animation or video-side listener. */
    private void updateFocusPaths() {
        Button[] buttons = {addButton, xtreamButton, storedButton, continueButton, activateButton, refreshButton};
        Button previous = null;
        for (Button button : buttons) {
            button.setNextFocusDownId(View.NO_ID);
            button.setNextFocusUpId(View.NO_ID);
            button.setNextFocusForwardId(View.NO_ID);
        }
        boolean wide = activity.getResources().getConfiguration().screenWidthDp >= 600;
        for (Button button : buttons) {
            if (button.getVisibility() != View.VISIBLE) continue;
            if (previous != null) {
                previous.setNextFocusForwardId(button.getId());
                if (!(wide && previous == addButton && button == xtreamButton)) {
                    previous.setNextFocusDownId(button.getId());
                    button.setNextFocusUpId(previous.getId());
                }
            }
            previous = button;
        }
        if (wide) {
            for (int i = 2; i < buttons.length; i++) {
                if (buttons[i].getVisibility() == View.VISIBLE) {
                    addButton.setNextFocusDownId(buttons[i].getId());
                    break;
                }
            }
        }
        // A disappearing CTA must not leave the remote focus stranded.
        View current = activity.getCurrentFocus();
        if (current != null && !current.isShown()) addButton.requestFocus();
    }

    void purchaseHelp(String mac, String helpCode, String durationLabel) {
        if (helpDialog != null && helpDialog.isShowing()) return;
        String body = (durationLabel.length() > 0 ? durationLabel : "Activation NovaTube") + " : 9,99 €.\n\n"
                + "Le paiement en ligne n’est pas encore disponible. Contactez votre assistance avec le code de cet appareil pour connaître les modalités d’activation.\n\n"
                + "Code de l’appareil : " + (mac == null ? "…" : mac);
        if (helpCode != null) body += "\nCode d’assistance : " + helpCode;
        helpDialog = new AlertDialog.Builder(activity).setTitle("Activer NovaTube")
                .setMessage(body).setPositiveButton("Fermer", null).create();
        helpDialog.show();
        AtlasAppearance.styleDialog(activity, helpDialog);
    }

    void close() {
        if (helpDialog != null && helpDialog.isShowing()) helpDialog.dismiss();
        helpDialog = null;
    }

    void checkoutFallback(String url) {
        close();
        helpDialog = new AlertDialog.Builder(activity).setTitle("Paiement NovaTube")
                .setMessage("Ouvrez ce lien sécurisé sur votre téléphone :\n\n" + url)
                .setPositiveButton("Fermer", null).create();
        helpDialog.show();
        View message = helpDialog.findViewById(android.R.id.message);
        if (message instanceof TextView) ((TextView) message).setTextIsSelectable(true);
        AtlasAppearance.styleDialog(activity, helpDialog);
    }

    private Button action(String label, AtlasAppearance.Theme theme) {
        Button button = AtlasAppearance.button(activity, label, theme);
        button.setId(View.generateViewId());
        button.setMinHeight(dp(48));
        button.setTextSize(17f);
        button.setAllCaps(false);
        return button;
    }
    private TextView text(String value, int size, int color) {
        TextView view = new TextView(activity);
        view.setText(value); view.setTextColor(color); view.setTextSize(size);
        view.setLineSpacing(dp(3), 1f);
        return view;
    }
    private LinearLayout.LayoutParams row(int margin) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(-1, -2);
        params.topMargin = dp(margin);
        return params;
    }
    private int dp(int value) { return Math.round(value * activity.getResources().getDisplayMetrics().density); }
}
