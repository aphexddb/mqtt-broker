pub const ConnackPackets = struct {
    // MQTT 3.1.1 style CONNACK packets
    pub const v3_success = [_]u8{
        0x20, 0x02, // Fixed header (CONNACK packet type + Remaining Length)
        0x00, // Connect Acknowledge Flags (all flags set to 0)
        0x00, // Connect Return Code (0x00 = Connection Accepted)
    };

    pub const v3_unacceptable_protocol_version = [_]u8{
        0x20, 0x02, // Fixed header
        0x00, // Connect Acknowledge Flags
        0x01, // Connect Return Code (0x01 = Unacceptable protocol version)
    };

    pub const v3_identifier_rejected = [_]u8{
        0x20, 0x02, // Fixed header
        0x00, // Connect Acknowledge Flags
        0x02, // Connect Return Code (0x02 = Identifier rejected)
    };

    // MQTT 5.0 style CONNACK packets
    pub const v5_success = [_]u8{
        0x20, 0x03, // Fixed header (CONNACK packet type + Remaining Length)
        0x00, // Connect Acknowledge Flags (all flags set to 0)
        0x00, // Reason Code (0x00 = Success)
        0x00, // Properties Length (0 = No properties)
    };

    pub const v5_unspecified_error = [_]u8{
        0x20, 0x03, // Fixed header
        0x00, // Connect Acknowledge Flags
        0x80, // Reason Code (0x80 = Unspecified error)
        0x00, // Properties Length
    };

    pub const v5_malformed_packet = [_]u8{
        0x20, 0x03, // Fixed header
        0x00, // Connect Acknowledge Flags
        0x81, // Reason Code (0x81 = Malformed Packet)
        0x00, // Properties Length
    };

    pub const v5_with_properties = [_]u8{
        0x20, 0x0C, // Fixed header (CONNACK packet type + Remaining Length)
        0x01, // Connect Acknowledge Flags (Session Present flag set)
        0x00, // Reason Code (0x00 = Success)
        0x09, // Properties Length
        0x11, 0x00, 0x00, 0x00, 0x0A, // Session Expiry Interval (10 seconds)
        0x21, 0x00, 0x02, 0x05, 0xDC, // Receive Maximum (1500)
    };
};

// test "parse connect packet" {
//     var buf: [1024]u8 = undefined;

//     const bytes = [_]u8{
//         0x10, 0x2A, // Fixed header
//         0x00, 0x04, 'M', 'Q', 'T', 'T', // Protocol name
//         0x04, // Protocol level
//         0b11010110, // Connect flags
//         0x00, 0x3C, // Keep alive
//         0x00, 0x0A, 'T', 'e', 's', 't', 'C', 'l', 'i', 'e', 'n', 't', // Client ID
//         0x00, 0x05, 'h', 'e', 'l', 'l', 'o', // Will topic
//         0x00, 0x05, 'w', 'o', 'r', 'l', 'd', // Will message
//         0x00, 0x04, 'u', 's', 'e', 'r', // Username
//         0x00, 0x04, 'p', 'a', 's', 's', // Password
//     };

//     @memcpy(buf[0..bytes.len], &bytes);

//     var reader = try packet.Reader.init(buf[0..], bytes.len);

//     try read(&reader, 1);

//     // while (pr.getPosition() < pr.length) {
//     //     const byte = try pr.readByte();
//     //     std.debug.print("position {d} - ", .{pr.getPosition()});

//     //     if (pr.getPosition() == 0x01) {
//     //         std.debug.print("packet length: {}\n", .{byte});
//     //     } else if (pr.getPosition() == 0x02) {
//     //         std.debug.print("protocol name: {}\n", .{byte});
//     //     } else {
//     //         std.debug.print(" {d} {X} {b}\n", .{ byte, byte, byte });
//     //     }
//     // }
// }
