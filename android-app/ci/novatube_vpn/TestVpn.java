package test.novatube.vpn;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Intent;
import android.net.IpPrefix;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** VPN de banc entre l'émulateur et le runner. Aucune bibliothèque du lecteur n'est chargée ici. */
public final class TestVpn extends VpnService {
    private static final String TAG = "NovaVpnQA";
    private static final int MTU = 1280;
    private volatile ParcelFileDescriptor tun;
    private volatile DatagramSocket socket;
    private boolean starting;

    @Override public int onStartCommand(Intent intent, int flags, int id) {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("qa", "VPN de test", NotificationManager.IMPORTANCE_LOW));
        startForeground(1, new Notification.Builder(this, "qa").setContentTitle("VPN de test NovaTube")
                .setSmallIcon(android.R.drawable.stat_notify_sync).build());
        if (!starting && intent != null) {
            starting = true;
            new Thread(() -> establishTunnel(intent), "nova-vpn-start").start();
        }
        return START_NOT_STICKY;
    }

    private void establishTunnel(Intent intent) {
        try {
            String app = intent.getStringExtra("app");
            byte[] key = intent.getStringExtra("key").getBytes(StandardCharsets.US_ASCII);
            if (key.length != 32 || !app.startsWith("com.sevenmotion.novatube.tv.lab.")) {
                throw new IllegalArgumentException("Paramètres du banc invalides");
            }
            socket = new DatagramSocket();
            // Seule l'enveloppe du tunnel doit sortir vers la passerelle de l'émulateur.
            if (!protect(socket)) throw new IOException("Impossible de préparer le transport du VPN");
            socket.connect(InetAddress.getByName("10.0.2.2"), 21923);
            Builder builder = new Builder().setSession("NovaTube VPN QA").setMtu(MTU)
                    .addAddress("192.0.2.2", 30).addRoute("0.0.0.0", 0)
                    .addDnsServer(intent.getStringExtra("dns")).addAllowedApplication(app)
                    .setBlocking(true);
            if ("allow".equals(intent.getStringExtra("lan"))) {
                if (Build.VERSION.SDK_INT < 33) throw new IOException("LAN de test : API 33 requise");
                builder.excludeRoute(new IpPrefix(InetAddress.getByName("10.0.2.0"), 24));
                builder.excludeRoute(new IpPrefix(InetAddress.getByName("239.255.255.250"), 32));
                builder.excludeRoute(new IpPrefix(InetAddress.getByName("224.0.0.251"), 32));
            }
            tun = builder.establish();
            if (tun == null) throw new IOException("VPN non autorisé");
            final DatagramSocket link = socket;
            final FileInputStream input = new FileInputStream(tun.getFileDescriptor());
            final FileOutputStream output = new FileOutputStream(tun.getFileDescriptor());
            link.send(new DatagramPacket(key, key.length));
            new Thread(() -> {
                byte[] frame = Arrays.copyOf(key, key.length + MTU);
                try {
                    int size;
                    while ((size = input.read(frame, key.length, MTU)) > 0) {
                        link.send(new DatagramPacket(frame, key.length + size));
                    }
                } catch (IOException e) { if (!link.isClosed()) Log.e(TAG, "Lecture du tunnel", e); }
            }, "nova-vpn-out").start();
            new Thread(() -> {
                byte[] frame = new byte[MTU + key.length];
                DatagramPacket packet = new DatagramPacket(frame, frame.length);
                try {
                    while (!link.isClosed()) {
                        packet.setLength(frame.length);
                        link.receive(packet);
                        if (packet.getLength() > key.length && Arrays.equals(key, Arrays.copyOf(frame, key.length))) {
                            output.write(frame, key.length, packet.getLength() - key.length);
                        }
                    }
                } catch (IOException e) { if (!link.isClosed()) Log.e(TAG, "Écriture du tunnel", e); }
            }, "nova-vpn-in").start();
            Log.i(TAG, "VPN actif pour " + app);
        } catch (Exception e) {
            Log.e(TAG, "Initialisation VPN échouée", e);
            stopSelf();
        }
    }

    @Override public void onDestroy() {
        if (socket != null) socket.close();
        if (tun != null) try { tun.close(); } catch (IOException ignored) {}
        super.onDestroy();
    }
}
