package test.novatube.vpn;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.os.Bundle;
import android.util.Log;

/** Point d'entrée de l'émulateur jetable. Le test prépare l'autorisation VPN Android. */
public final class StartTunnel extends Activity {
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        if (VpnService.prepare(this) != null) {
            Log.e("NovaVpnQA", "Autorisation VPN du banc absente");
        } else {
            Intent service = new Intent(this, TestVpn.class);
            service.putExtras(getIntent());
            startForegroundService(service);
        }
        finish();
    }
}
