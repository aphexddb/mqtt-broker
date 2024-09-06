const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const PacketError = @import("../packet.zig").PacketError;

pub const ConnectPacket = struct {
    allocator: Allocator,

    // packet processing
    errors: ArrayList(PacketError),

    // Fixed header
    flags: u8 = 0,

    // Variable header
    protocol_name: []const u8 = "MQTT",
    protocol_version: u8 = 5,
    connect_flags: struct {
        username: bool,
        password: bool,
        will_retain: bool,
        will_qos: u2,
        will: bool,
        clean_session: bool,
        reserved: bool,
    },
    keep_alive: u16,

    // Properties
    session_expiry_interval: ?u32 = null,
    receive_maximum: ?u16 = null,
    maximum_packet_size: ?u32 = null,
    topic_alias_maximum: ?u16 = null,
    request_response_information: ?bool = null,
    request_problem_information: ?bool = null,
    user_properties: std.ArrayList(UserProperty),
    authentication_method: ?[]const u8 = null,
    authentication_data: ?[]const u8 = null,

    // Payload
    client_identifier: []u8,
    will_properties: ?WillProperty = null,
    will_topic: ?[]const u8 = null,
    will_payload: ?[]const u8 = null,
    username: ?[]const u8 = null,
    password: ?[]const u8 = null,

    pub fn init(
        allocator: Allocator,
    ) !*ConnectPacket {
        const connect_packet = try allocator.create(ConnectPacket);
        connect_packet.* = .{
            .errors = ArrayList(PacketError).init(allocator),
            .allocator = allocator,
            .connect_flags = .{
                .username = false,
                .password = false,
                .will_retain = false,
                .will_qos = 0,
                .will = false,
                .clean_session = false,
                .reserved = false,
            },
            .keep_alive = 60,
            .user_properties = std.ArrayList(UserProperty).init(allocator),
            .client_identifier = "",
        };

        return connect_packet;
    }

    pub const UserProperty = struct {
        key: []const u8,
        value: []const u8,
    };

    pub const WillProperty = struct {
        will_delay_interval: ?u32,
        payload_format_indicator: ?bool,
        message_expiry_interval: ?u32,
        content_type: ?[]const u8,
        response_topic: ?[]const u8,
        correlation_data: ?[]const u8,
        user_properties: std.ArrayList(UserProperty),
    };

    pub fn deinit(self: *ConnectPacket) void {
        std.debug.print("Deinitializing ConnectPacket\n", .{});
        self.user_properties.deinit();
        if (self.will_properties) |*will_props| {
            will_props.user_properties.deinit();
        }
        self.errors.deinit();
        self.allocator.destroy(self);
    }

    pub fn addError(self: *ConnectPacket, err: PacketError) !void {
        try self.errors.append(err);
    }

    pub fn getErrors(self: *const ConnectPacket) []const PacketError {
        return self.errors.items;
    }
};
