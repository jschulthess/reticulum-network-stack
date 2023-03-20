package io.reticulum.utils;

import io.reticulum.Transport;
import io.reticulum.destination.Destination;
import io.reticulum.link.Link;
import io.reticulum.packet.Packet;
import lombok.extern.slf4j.Slf4j;

import static io.reticulum.constant.LinkConstant.ECPUBSIZE;
import static io.reticulum.constant.LinkConstant.ESTABLISHMENT_TIMEOUT_PER_HOP;
import static java.util.Arrays.copyOfRange;

@Slf4j
public class LinkUtils {
    public static Link validateRequest(Destination owner, byte[] data, Packet packet) {
        if (data.length == ECPUBSIZE) {
            try {
                var link = new Link(owner, copyOfRange(data, 0, ECPUBSIZE / 2), copyOfRange(data, ECPUBSIZE / 2, ECPUBSIZE));
                link.setLinkId(packet);
                link.setDestination(packet.getDestination());
                link.establishmentTimeout(ESTABLISHMENT_TIMEOUT_PER_HOP + Math.max(1, packet.getHops()));
                link.addEstablishmentCost(packet.getRaw().length);
                log.info("Validating link request {}", link.getLinkId());
                link.handshake();
                link.setAttachedInterface(packet.getReceivingInterface());
                link.prove();
                link.setRequestTime(System.currentTimeMillis());
                Transport.getInstance().registerLink(link);
                link.setLastInbound(System.currentTimeMillis());
                link.startWatchdog();

                log.info("Incoming link request {}  accepted", link);

                return link;
            } catch (Exception e) {
                log.error("Validating link request failed", e);
            }
        } else {
            log.error("Invalid link request payload size, dropping request");
        }

        return null;
    }
}