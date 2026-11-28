import java.net.DatagramPacket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.MulticastSocket;
import java.net.NetworkInterface;
import java.nio.charset.StandardCharsets;
import java.util.Enumeration;

/** Pont réseau du récepteur émulé ; répond uniquement aux vrais M-SEARCH. */
public final class SsdpResponder {
    public static void main(String[] arguments) throws Exception {
        boolean lan = arguments.length == 1 && arguments[0].equals("slirp");
        String location = "http://" + (lan ? "10.0.2.2" : "127.0.0.1") + ":18999/device.xml";
        MulticastSocket socket = new MulticastSocket(null);
        socket.setReuseAddress(true);
        socket.bind(new InetSocketAddress(1900));
        InetSocketAddress group = new InetSocketAddress("239.255.255.250", 1900);
        Enumeration<NetworkInterface> interfaces = NetworkInterface.getNetworkInterfaces();
        while (interfaces.hasMoreElements()) {
            NetworkInterface network = interfaces.nextElement();
            if (!network.isUp()) continue;
            try {
                socket.joinGroup(group, network);
                System.out.println("SSDP joined " + network.getName());
            } catch (Exception error) {
                System.out.println("SSDP skipped " + network.getName() + ": " + error);
            }
        }
        System.out.println("SSDP responder ready: " + location);
        byte[] response = ("HTTP/1.1 200 OK\r\n"
            + "CACHE-CONTROL: max-age=120\r\nEXT:\r\n"
            + "LOCATION: " + location + "\r\n"
            + "SERVER: Android/14 UPnP/1.0 NOVATUBE-QA-Receiver/1.0\r\n"
            + "ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n"
            + "USN: uuid:0bbcae01-7ca8-453b-a2ea-202611220001::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n")
            .getBytes(StandardCharsets.US_ASCII);
        while (true) {
            DatagramPacket packet = new DatagramPacket(new byte[8192], 8192);
            socket.receive(packet);
            String message = new String(packet.getData(), 0, packet.getLength(), StandardCharsets.US_ASCII);
            if (!message.startsWith("M-SEARCH ")) continue;
            System.out.println("M-SEARCH from " + packet.getAddress() + ":" + packet.getPort());
            socket.send(new DatagramPacket(response, response.length, packet.getAddress(), packet.getPort()));
        }
    }
}
