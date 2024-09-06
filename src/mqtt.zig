const std = @import("std");

/// ProtocolVersion represents the various MQTT protocol versions
pub const ProtocolVersion = enum(u8) {
    Invalid = 0,
    V3_1 = 3,
    V3_1_1 = 4,
    V5_0 = 5,

    /// Returns a human-readable string representation of the protocol version
    pub fn toString(self: ProtocolVersion) []const u8 {
        return switch (self) {
            .Invalid => "Invalid",
            .V3_1 => "MQTT 3.1",
            .V3_1_1 => "MQTT 3.1.1",
            .V5_0 => "MQTT 5.0",
        };
    }

    /// Returns the protocol name used in the CONNECT packet
    pub fn protocolName(self: ProtocolVersion) []const u8 {
        return switch (self) {
            .V3_1 => "MQIsdp",
            .V3_1_1, .V5_0 => "MQTT",
        };
    }

    /// Checks if the version supports a specific feature
    pub fn supportsFeature(self: ProtocolVersion, feature: Feature) bool {
        return switch (feature) {
            .WillRetain => true,
            .WillQoS => true,
            .WillProperties => self == .V5_0,
            .SubscriptionIdentifiers => self == .V5_0,
            .SharedSubscriptions => self == .V5_0,
            .ServerRedirect => self == .V5_0,
            .EnhancedAuth => self == .V5_0,
        };
    }

    /// Represents features that may or may not be supported by different protocol versions
    pub const Feature = enum {
        WillRetain,
        WillQoS,
        WillProperties,
        SubscriptionIdentifiers,
        SharedSubscriptions,
        ServerRedirect,
        EnhancedAuth,
    };

    /// Attempts to create a ProtocolVersion from a raw u8 value
    pub fn fromU8(value: u8) ?ProtocolVersion {
        return switch (value) {
            0 => .Invalid,
            3 => .V3_1,
            4 => .V3_1_1,
            5 => .V5_0,
            else => null,
        };
    }
};

/// Command represents a MQTT control packet command
pub const Command = enum(u8) {
    Reserved0 = 0,
    CONNECT = 1,
    CONNACK = 2,
    PUBLISH = 3,
    PUBACK = 4,
    PUBREC = 5,
    PUBREL = 6,
    PUBCOMP = 7,
    SUBSCRIBE = 8,
    SUBACK = 9,
    UNSUBSCRIBE = 10,
    UNSUBACK = 11,
    PINGREQ = 12,
    PINGRESP = 13,
    DISCONNECT = 14,
    Reserved15 = 15,

    pub fn description(self: Command) []const u8 {
        return switch (self) {
            .Reserved0 => "Reserved (forbidden)",
            .CONNECT => "Client request to connect to Server",
            .CONNACK => "Connect acknowledgment",
            .PUBLISH => "Publish message",
            .PUBACK => "Publish acknowledgment",
            .PUBREC => "Publish received (assured delivery part 1)",
            .PUBREL => "Publish release (assured delivery part 2)",
            .PUBCOMP => "Publish complete (assured delivery part 3)",
            .SUBSCRIBE => "Client subscribe request",
            .SUBACK => "Subscribe acknowledgment",
            .UNSUBSCRIBE => "Unsubscribe request",
            .UNSUBACK => "Unsubscribe acknowledgment",
            .PINGREQ => "PING request",
            .PINGRESP => "PING response",
            .DISCONNECT => "Client is disconnecting",
            .Reserved15 => "Reserved (forbidden)",
        };
    }

    pub fn directionOfFlow(self: Command) []const u8 {
        return switch (self) {
            .Reserved0, .Reserved15 => "Forbidden",
            .CONNECT, .SUBSCRIBE, .UNSUBSCRIBE => "Client to Server",
            .CONNACK, .SUBACK, .UNSUBACK, .PINGRESP => "Server to Client",
            .PUBLISH, .PUBACK, .PUBREC, .PUBREL, .PUBCOMP, .PINGREQ, .DISCONNECT => "Client to Server or Server to Client",
        };
    }

    pub fn fromU8(value: u8) !Command {
        return try std.meta.intToEnum(Command, value);
    }
};

/// QoS represents the Quality of Service levels in MQTT
pub const QoS = enum(u2) {
    AtMostOnce = 0,
    AtLeastOnce = 1,
    ExactlyOnce = 2,

    /// Returns a human-readable string representation of the QoS level
    pub fn toString(self: QoS) []const u8 {
        return switch (self) {
            .AtMostOnce => "At most once (0)",
            .AtLeastOnce => "At least once (1)",
            .ExactlyOnce => "Exactly once (2)",
        };
    }

    /// Returns a brief description of the QoS level
    pub fn description(self: QoS) []const u8 {
        return switch (self) {
            .AtMostOnce => "Fire and forget",
            .AtLeastOnce => "Acknowledged delivery",
            .ExactlyOnce => "Assured delivery",
        };
    }

    /// Attempts to create a QoS from a raw u8 value
    pub fn fromU8(value: u8) ?QoS {
        return switch (value) {
            0 => .AtMostOnce,
            1 => .AtLeastOnce,
            2 => .ExactlyOnce,
            else => null,
        };
    }

    /// Returns the maximum number of message transmissions for this QoS level
    pub fn maxTransmissions(self: QoS) u8 {
        return switch (self) {
            .AtMostOnce => 1,
            .AtLeastOnce => 2,
            .ExactlyOnce => 4, // PUBLISH, PUBREC, PUBREL, PUBCOMP
        };
    }

    /// Checks if this QoS level requires packet persistence
    pub fn requiresPersistence(self: QoS) bool {
        return self != .AtMostOnce;
    }
};

/// ReasonCode indicates the result of an operation.
/// Reason Codes less than 0x80 indicate successful completion of an operation.
/// The normal Reason Code for success is 0. Reason Code values of 0x80 or greater indicate failure.
/// The CONNACK, PUBACK, PUBREC, PUBREL, PUBCOMP, DISCONNECT and AUTH Control Packets have a single Reason Code
/// as part of the Variable Header. The SUBACK and UNSUBACK packets contain a list of one or more Reason Codes
/// in the Payload.
pub const ReasonCode = enum(u8) {
    Success = 0x00,
    GrantedQoS1 = 0x01,
    GrantedQoS2 = 0x02,
    DisconnectWithWillMessage = 0x04,
    NoMatchingSubscribers = 0x10,
    NoSubscriptionExisted = 0x11,
    ContinueAuthentication = 0x18,
    ReAuthenticate = 0x19,
    UnspecifiedError = 0x80,
    MalformedPacket = 0x81,
    ProtocolError = 0x82,
    ImplementationSpecificError = 0x83,
    UnsupportedProtocolVersion = 0x84,
    ClientIdentifierNotValid = 0x85,
    BadUserNameOrPassword = 0x86,
    NotAuthorized = 0x87,
    ServerUnavailable = 0x88,
    ServerBusy = 0x89,
    Banned = 0x8A,
    ServerShuttingDown = 0x8B,
    BadAuthenticationMethod = 0x8C,
    KeepAliveTimeout = 0x8D,
    SessionTakenOver = 0x8E,
    TopicFilterInvalid = 0x8F,
    TopicNameInvalid = 0x90,
    PacketIdentifierInUse = 0x91,
    PacketIdentifierNotFound = 0x92,
    ReceiveMaximumExceeded = 0x93,
    TopicAliasInvalid = 0x94,
    PacketTooLarge = 0x95,
    MessageRateTooHigh = 0x96,
    QuotaExceeded = 0x97,
    AdministrativeAction = 0x98,
    PayloadFormatInvalid = 0x99,
    RetainNotSupported = 0x9A,
    QoSNotSupported = 0x9B,
    UseAnotherServer = 0x9C,
    ServerMoved = 0x9D,
    SharedSubscriptionsNotSupported = 0x9E,
    ConnectionRateExceeded = 0x9F,
    MaximumConnectTime = 0xA0,
    SubscriptionIdentifiersNotSupported = 0xA1,
    WildcardSubscriptionsNotSupported = 0xA2,

    // error union that represents a subset of reason codes used for malformed packet and protocol errors
    pub const MalformedPacketOrProtocolError =
        .MalformedPacket ||
        .ProtocolError ||
        .ReceiveMaximumExceeded ||
        .PacketTooLarge ||
        .RetainNotSupported ||
        .QoSNotSupported ||
        .SharedSubscriptionsNotSupported ||
        .SubscriptionIdentifiersNotSupported ||
        .WildcardSubscriptionsNotSupported ||
        .UnspecifiedError;

    pub fn description(self: ReasonCode) []const u8 {
        return switch (self) {
            .Success => "Success",
            .GrantedQoS1 => "Granted QoS 1",
            .GrantedQoS2 => "Granted QoS 2",
            .DisconnectWithWillMessage => "Disconnect with Will Message",
            .NoMatchingSubscribers => "No matching subscribers",
            .NoSubscriptionExisted => "No subscription existed",
            .ContinueAuthentication => "Continue authentication",
            .ReAuthenticate => "Re-authenticate",
            .UnspecifiedError => "Unspecified error",
            .MalformedPacket => "Malformed Packet",
            .ProtocolError => "Protocol Error",
            .ImplementationSpecificError => "Implementation specific error",
            .UnsupportedProtocolVersion => "Unsupported Protocol Version",
            .ClientIdentifierNotValid => "Client Identifier not valid",
            .BadUserNameOrPassword => "Bad User Name or Password",
            .NotAuthorized => "Not authorized",
            .ServerUnavailable => "Server unavailable",
            .ServerBusy => "Server busy",
            .Banned => "Banned",
            .ServerShuttingDown => "Server shutting down",
            .BadAuthenticationMethod => "Bad authentication method",
            .KeepAliveTimeout => "Keep Alive timeout",
            .SessionTakenOver => "Session taken over",
            .TopicFilterInvalid => "Topic Filter invalid",
            .TopicNameInvalid => "Topic Name invalid",
            .PacketIdentifierInUse => "Packet Identifier in use",
            .PacketIdentifierNotFound => "Packet Identifier not found",
            .ReceiveMaximumExceeded => "Receive Maximum exceeded",
            .TopicAliasInvalid => "Topic Alias invalid",
            .PacketTooLarge => "Packet too large",
            .MessageRateTooHigh => "Message rate too high",
            .QuotaExceeded => "Quota exceeded",
            .AdministrativeAction => "Administrative action",
            .PayloadFormatInvalid => "Payload format invalid",
            .RetainNotSupported => "Retain not supported",
            .QoSNotSupported => "QoS not supported",
            .UseAnotherServer => "Use another server",
            .ServerMoved => "Server moved",
            .SharedSubscriptionsNotSupported => "Shared Subscriptions not supported",
            .ConnectionRateExceeded => "Connection rate exceeded",
            .MaximumConnectTime => "Maximum connect time",
            .SubscriptionIdentifiersNotSupported => "Subscription Identifiers not supported",
            .WildcardSubscriptionsNotSupported => "Wildcard Subscriptions not supported",
        };
    }

    pub fn isV5Specific(self: ReasonCode) bool {
        return switch (self) {
            .DisconnectWithWillMessage, .NoMatchingSubscribers, .NoSubscriptionExisted, .ContinueAuthentication, .ReAuthenticate, .ServerBusy, .Banned, .BadAuthenticationMethod, .KeepAliveTimeout, .SessionTakenOver, .TopicFilterInvalid, .TopicNameInvalid, .PacketIdentifierInUse, .PacketIdentifierNotFound, .ReceiveMaximumExceeded, .TopicAliasInvalid, .PacketTooLarge, .MessageRateTooHigh, .QuotaExceeded, .AdministrativeAction, .PayloadFormatInvalid, .RetainNotSupported, .QoSNotSupported, .UseAnotherServer, .ServerMoved, .SharedSubscriptionsNotSupported, .ConnectionRateExceeded, .MaximumConnectTime, .SubscriptionIdentifiersNotSupported, .WildcardSubscriptionsNotSupported => true,
            else => false,
        };
    }
    pub fn longDescription(self: ReasonCode, buffer: []u8) std.fmt.BufPrintError![]const u8 {
        const version = if (self.isV5Specific()) "v5" else "v3.1.1 and v5";
        return std.fmt.bufPrint(buffer, "{X} {s} ({s})", .{
            @intFromEnum(self),
            self.description(),
            version,
        });
    }
};

// DisconnectProperty represents the DISCONNECT packet properties
pub const DisconnectProperty = enum(u8) {
    SessionExpiryInterval = 0x11,
    ReasonString = 0x1F,
    UserProperty = 0x26,
    ServerReference = 0x1C,

    pub fn fromU8(value: u8) DisconnectProperty {
        return switch (value) {
            0x11 => .SessionExpiryInterval,
            0x1F => .ReasonString,
            0x26 => .UserProperty,
            0x1C => .ServerReference,
            else => @enumFromInt(value),
        };
    }
};
