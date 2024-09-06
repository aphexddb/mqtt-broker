const std = @import("std");
const net = std.net;
const posix = std.posix;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const packet = @import("packet.zig");
const config = @import("config.zig");
const mqtt = @import("mqtt.zig");
const ConnectPacket = @import("mqtt/connect_packet.zig").ConnectPacket;
const Client = @import("client.zig").Client;
const isValidClientId = @import("client.zig").isValidClientId;

pub const ConnectError = error{
    InvalidPacket,
    InvalidWillQoS,
    WillQosMustBeZero,
    WillTopicMustBePresent,
    WillMessageMustBePresent,
    PasswordMustBePresent,
    UsernameMustBePresent,
    PasswordMustNotBeSet,
    UsernameFieldMismatch,
    PasswordFieldMismatch,
    InvalidClientId,
    ClientIdTooShort,
    ClientIdTooLong,
    ClientIdNotUTF8,
    ProtocolNameNotMQTT,
    ProtocolVersionInvalid,
    MalformedPacket,
    EmptyClientIdWithoutCleanSession,
    UnsupportedVersion,
    IncompleteWillInformation,
    UnexpectedExtraData,
};

// connect flag bit masks
const FlagBitMask = struct {
    pub const username = 0b10000000; // 7
    pub const password = 0b01000000; // 6
    pub const willRetain = 0b00100000; // 5
    pub const willQoS = 0b00011000; // The willQoS flag uses two bits (4 and 3)
    pub const willFlag = 0b00000100; // 2
    pub const cleanStart = 0b00000010; // 1
    pub const reserved = 0b00000001; // 0
};

pub fn read(reader: *packet.Reader, allocator: Allocator) !*ConnectPacket {
    const cp = try ConnectPacket.init(allocator);
    errdefer cp.deinit();

    std.debug.print("--- CONNECT packet ---\n", .{});

    // Protocol Name
    std.debug.print("Reading protocol name\n", .{});
    cp.protocol_name = try reader.readUTF8String(false) orelse "";
    if (!std.mem.eql(u8, "MQTT", cp.protocol_name)) {
        try cp.addError(reader.getContextForError(ConnectError.ProtocolNameNotMQTT));
    }
    std.debug.print("Protocol name: '{s}'\n", .{cp.protocol_name});

    // Protocol version
    cp.protocol_version = try reader.readByte();
    const version = mqtt.ProtocolVersion.fromU8(cp.protocol_version) orelse blk: {
        try cp.addError(reader.getContextForError(ConnectError.ProtocolVersionInvalid));
        break :blk null;
    };
    if (version) |v| {
        std.debug.print("Protocol version: {X} ({s})\n", .{ cp.protocol_version, v.toString() });
    }

    // version specific checks
    if (version == .V3_1_1) {
        // MQTT v3.1.1 specific checks
    } else if (version == .V5_0) {
        // MQTT v5.0 specific checks
    } else {
        try cp.addError(reader.getContextForError(ConnectError.UnsupportedVersion));
    }

    // Connect flags
    cp.flags = try reader.readByte();
    cp.connect_flags = .{
        .username = (cp.flags & FlagBitMask.username) != 0,
        .password = (cp.flags & FlagBitMask.password) != 0,
        .will_retain = (cp.flags & FlagBitMask.willRetain) != 0,
        .will_qos = @truncate((cp.flags & FlagBitMask.willQoS) >> 3),
        .will = (cp.flags & FlagBitMask.willFlag) != 0,
        .clean_session = (cp.flags & FlagBitMask.cleanStart) != 0,
        .reserved = (cp.flags & FlagBitMask.reserved) != 0,
    };

    std.debug.print("Connect flags: {X} ({b})\n", .{ cp.flags, cp.flags });

    // flag value - Clean session
    if (cp.connect_flags.clean_session) {
        std.debug.print("Flag: clean session set\n", .{});
    }

    // flag value - Will retain
    if (cp.connect_flags.will_retain) {
        std.debug.print("Flag: will retain flag set\n", .{});
    }

    // flag value - Will flag
    if (cp.connect_flags.will) {
        std.debug.print("Flag: will flag set\n", .{});
    }

    // flag value - will QoS
    if ((cp.flags & FlagBitMask.willQoS) != 0) {
        // u8 flag to u2:
        // perform bitwise AND to isolate bits 4 and 3
        // right-shift the result by 3 to move  Will QoS bits to least significant positions
        // truncate result to u2
        std.debug.print("Flag: will QoS: {d}\n", .{cp.connect_flags.will_qos});
    }

    // flag value - username
    if (cp.connect_flags.username) {
        std.debug.print("Flag: username flag set\n", .{});
    }

    // flag value - password
    if (cp.connect_flags.password) {
        std.debug.print("Flag: password flag set\n", .{});
    }

    // flag value - reserved
    if (cp.connect_flags.reserved) {
        std.debug.print("Flag: reserved flag set\n", .{});
        //  [MQTT-3.1.2-3]
        const reserved: u1 = @truncate((cp.flags & FlagBitMask.reserved) >> 3);
        if (reserved != 0) try cp.addError(reader.getContextForError(ConnectError.MalformedPacket));
    }

    // Keep Alive
    const keep_alive = try reader.readTwoBytes();
    cp.keep_alive = keep_alive;
    std.debug.print("Keep Alive: {d}\n", .{cp.keep_alive});

    // [MQTT-3.1.3-1] Payload processing based on flags set, the fields MUST appear in the order:
    // Client Identifier
    // Will Topic
    // Will Message
    // User Name
    // Password

    // Client ID
    cp.client_identifier = try reader.readClientId() orelse "";
    std.debug.print("Client ID: '{s}'\n", .{cp.client_identifier});

    // [MQTT-3.1.3-4] check if the client_id is valid UTF-8
    if (!std.unicode.utf8ValidateSlice(cp.client_identifier)) {
        try cp.addError(reader.getContextForError(ConnectError.ClientIdNotUTF8));
    }
    // [MQTT-3.1.3-5]
    if (!isValidClientId(cp.client_identifier)) {
        // This server allows 2 char client ID min

        if (cp.client_identifier.len < 2) {
            try cp.addError(reader.getContextForError(ConnectError.ClientIdTooShort));
        }
        // We also allow more than 23 characters for the client ID
        if (cp.client_identifier.len > config.MAX_CLIENT_ID_LEN) {
            try cp.addError(reader.getContextForError(ConnectError.ClientIdTooLong));
        }
    }

    if (cp.client_identifier.len == 0 and !cp.connect_flags.clean_session) {
        try cp.addError(reader.getContextForError(ConnectError.EmptyClientIdWithoutCleanSession));
    }

    // Will is set
    if (cp.connect_flags.will) {
        // Ensure that if the Will flag is set, both Will Topic and Will Message are present and non-empty:
        if (cp.will_topic == null or cp.will_topic.?.len == 0 or cp.will_payload == null or cp.will_payload.?.len == 0) {
            try cp.addError(reader.getContextForError(ConnectError.IncompleteWillInformation));
        }

        // [MQTT-3.1.2-14]
        switch (cp.connect_flags.will_qos) {
            0, 1, 2 => {},
            else => try cp.addError(reader.getContextForError(ConnectError.InvalidWillQoS)),
        }

        // Will Topic
        const will_topic = try reader.readUTF8String(false) orelse "";
        //  [MQTT-3.1.2-9]
        if (will_topic.len == 0) {
            try cp.addError(reader.getContextForError(ConnectError.WillTopicMustBePresent));
        }
        cp.will_topic = will_topic;
        std.debug.print("Will topic: '{?s}'\n", .{cp.will_topic});

        // Will Message
        const will_message = try reader.readUTF8String(false) orelse "";

        // [MQTT-3.1.2-9]
        if (will_message.len == 0) {
            try cp.addError(reader.getContextForError(ConnectError.WillMessageMustBePresent));
        }
        cp.will_payload = will_message;
        std.debug.print("Will payload: '{?s}'\n", .{cp.will_payload});
    } else {
        // [MQTT-3.1.2-13]
        if (cp.connect_flags.will_qos != 0) try cp.addError(reader.getContextForError(ConnectError.WillQosMustBeZero));
    }

    // [MQTT-3.1.2-22]
    if (!cp.connect_flags.username and cp.connect_flags.password) {
        try cp.addError(reader.getContextForError(ConnectError.PasswordMustNotBeSet));
    }

    // other flag Validation
    if (cp.connect_flags.username != (cp.username != null)) {
        try cp.addError(reader.getContextForError(ConnectError.UsernameFieldMismatch));
    }
    if (cp.connect_flags.password != (cp.password != null)) {
        try cp.addError(reader.getContextForError(ConnectError.PasswordFieldMismatch));
    }

    // Username
    if (cp.connect_flags.username) {
        cp.username = try reader.readUserName() orelse blk: {
            cp.addError(reader.getContextForError(ConnectError.UsernameMustBePresent)) catch |err| {
                std.log.err("Error reading username: {s}", .{@errorName(err)});
            };
            break :blk "null";
        };

        // [MQTT-3.1.2-19]
        if (cp.username == null or cp.username.?.len == 0) try cp.addError(reader.getContextForError(ConnectError.UsernameMustBePresent));

        std.debug.print("Username: '{?s}'\n", .{cp.username});
    }

    // Password
    if (cp.connect_flags.password) {
        cp.password = try reader.readPassword();

        // [MQTT-3.1.2-21]
        if (cp.password == null or cp.password.?.len == 0) try cp.addError(reader.getContextForError(ConnectError.PasswordMustBePresent));

        std.debug.print("Password: '{?s}'\n", .{cp.password});
    }

    // After parsing all expected fields, check if there's any unexpected extra data in the packet:
    if (reader.pos < reader.length) {
        try cp.addError(reader.getContextForError(ConnectError.UnexpectedExtraData));
    }

    std.debug.print("----------------\n", .{});

    return cp;
}

pub fn connack(writer: *packet.Writer, stream: *net.Stream, reason_code: mqtt.ReasonCode) (packet.PacketWriterError || ConnectError || posix.WriteError)!void {
    std.debug.print("--- CONNACK packet ---\n", .{});

    try writer.startPacket(mqtt.Command.CONNACK);

    // connection acknowledge
    var connect_acknowledge: u8 = 0x00;
    const session_present_bit = false;
    const connect_acknowledge_flags: u8 = 0x00;
    if (session_present_bit) {
        connect_acknowledge = 1 << 0 | connect_acknowledge_flags;
    } else {
        connect_acknowledge = connect_acknowledge_flags;
    }
    try writer.writeByte(connect_acknowledge);
    std.debug.print("Connection acknowledge: {X}\n", .{connect_acknowledge});

    // connection return / reason code
    try writer.writeByte(@intFromEnum(reason_code));
    var buffer: [1024]u8 = undefined;
    std.debug.print("Reason Code: {s}\n", .{try reason_code.longDescription(&buffer)});

    try writer.finishPacket();

    try writer.writeToStream(stream);

    std.debug.print("----------------\n", .{});
}

pub fn disconnect(writer: *packet.Writer, stream: *net.Stream, reason_code: mqtt.ReasonCode) (packet.PacketWriterError || ConnectError || posix.WriteError)!void {
    try writer.startPacket(mqtt.Command.DISCONNECT);

    // Disconnect Reason Code
    try writer.writeByte(@intFromEnum(reason_code));

    // Property length
    try writer.writeByte(0x00);

    try writer.finishPacket();

    try writer.writeToStream(stream);
}
