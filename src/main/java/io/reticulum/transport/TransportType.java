package io.reticulum.transport;

import lombok.Getter;
import lombok.RequiredArgsConstructor;

import java.util.Arrays;

@Getter
@RequiredArgsConstructor
public enum TransportType {

    BROADCAST((byte) 0x00),
    TRANSPORT((byte) 0x01),
    RELAY((byte) 0x02),
    TUNNEL((byte) 0x03);

    private final byte value;

    public static TransportType fromValue(final byte value) {
        return Arrays.stream(values())
                .filter(type -> type.getValue() == value)
                .findFirst()
                .orElseThrow();
    }
}
