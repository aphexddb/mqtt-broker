const std = @import("std");
const net = std.net;
const time = std.time;
const Allocator = std.mem.Allocator;

const QoS = @import("mqtt.zig").QoS;
const ProtocolVersion = @import("mqtt.zig").ProtocolVersion;

pub const ClientError = error{
    ClientReadError,
    ClientNotFound,
};

// Client represents a MQTT client connected to the broker
pub const Client = struct {
    allocator: Allocator,

    // Basic client information
    id: u64,
    identifer: []u8,
    protocol_version: ?ProtocolVersion = null,
    stream: net.Stream,
    address: net.Address,

    // Connection state
    is_connected: bool,
    connect_time: i64,
    last_activity: i64,

    // MQTT session properties
    clean_start: bool,
    session_expiry_interval: u32,

    // Keep alive
    keep_alive: u16,

    // Authentication
    username: ?[]const u8,
    password: ?[]const u8,

    // Will message
    will_topic: ?[]const u8,
    will_payload: ?[]const u8,
    will_qos: QoS,
    will_retain: bool,
    will_delay_interval: u32,

    // Subscriptions
    subscriptions: std.ArrayList(Subscription),

    // Message queues
    incoming_queue: std.ArrayList(Message),
    outgoing_queue: std.ArrayList(Message),

    // Flow control
    receive_maximum: u16,
    maximum_packet_size: u32,
    topic_alias_maximum: u16,

    // Other MQTT 5.0 properties
    user_properties: std.StringHashMap([]const u8),

    // Packet tracking
    packet_id_counter: u16,
    inflight_messages: std.AutoHashMap(u16, Message),

    pub const Subscription = struct {
        topic_filter: []const u8,
        qos: QoS,
        no_local: bool,
        retain_as_published: bool,
        retain_handling: RetainHandling,
        subscription_identifier: ?u32,

        pub const RetainHandling = enum(u2) {
            SendRetained = 0,
            SendRetainedForNewSubscription = 1,
            DoNotSendRetained = 2,
        };
    };

    pub const Message = struct {
        topic: []const u8,
        payload: []const u8,
        qos: QoS,
        retain: bool,
        packet_id: ?u16,
        dup: bool,
        expiry_interval: ?u32,
        topic_alias: ?u16,
        response_topic: ?[]const u8,
        correlation_data: ?[]const u8,
        user_properties: std.StringHashMap([]const u8),
        subscription_identifiers: ?std.ArrayList(u32),
        content_type: ?[]const u8,
    };

    pub fn init(allocator: Allocator, id: u64, protocol_version: ProtocolVersion, stream: net.Stream, address: net.Address) !*Client {
        const client = try allocator.create(Client);
        client.* = .{
            .allocator = allocator,
            .id = id,
            .identifer = undefined,
            .protocol_version = protocol_version,
            .stream = stream,
            .address = address,
            .is_connected = false,
            .connect_time = 0,
            .last_activity = 0,
            .clean_start = true,
            .session_expiry_interval = 0,
            .keep_alive = 0,
            .username = null,
            .password = null,
            .will_topic = null,
            .will_payload = null,
            .will_qos = .AtMostOnce,
            .will_retain = false,
            .will_delay_interval = 0,
            .subscriptions = std.ArrayList(Subscription).init(allocator),
            .incoming_queue = std.ArrayList(Message).init(allocator),
            .outgoing_queue = std.ArrayList(Message).init(allocator),
            .receive_maximum = 65535,
            .maximum_packet_size = 268435455, // Default to 256 MiB
            .topic_alias_maximum = 0,
            .user_properties = std.StringHashMap([]const u8).init(allocator),
            .packet_id_counter = 0,
            .inflight_messages = std.AutoHashMap(u16, Message).init(allocator),
        };
        return client;
    }

    pub fn deinit(self: *Client) void {
        self.stream.close();
        if (self.username) |username| self.allocator.free(username);
        if (self.password) |password| self.allocator.free(password);
        if (self.will_topic) |topic| self.allocator.free(topic);
        if (self.will_payload) |payload| self.allocator.free(payload);
        // self.allocator.free(self.identifer);
        self.subscriptions.deinit();
        self.incoming_queue.deinit();
        self.outgoing_queue.deinit();
        self.user_properties.deinit();
        self.inflight_messages.deinit();
        self.allocator.destroy(self);
    }

    pub fn connect(self: *Client, identifer: []u8, protocol_version: ?ProtocolVersion, clean_start: bool, session_expiry_interval: u32, keep_alive: u16) void {
        self.identifer = identifer;
        self.protocol_version = protocol_version;
        self.clean_start = clean_start;
        self.is_connected = true;
        self.connect_time = time.milliTimestamp();
        self.last_activity = self.connect_time;
        self.session_expiry_interval = session_expiry_interval;
        self.keep_alive = keep_alive;
    }

    pub fn nextPacketId(self: *Client) u16 {
        self.packet_id_counter +%= 1;
        if (self.packet_id_counter == 0) self.packet_id_counter = 1;
        return self.packet_id_counter;
    }

    pub fn addSubscription(self: *Client, subscription: Subscription) !void {
        try self.subscriptions.append(subscription);
        std.log.info("Client {s} subscribed to {s}", .{ self.identifer, subscription.topic_filter });
    }
    pub fn removeSubscription(self: *Client, topic_filter: []const u8) void {
        var i: usize = self.subscriptions.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.subscriptions.items[i].topic_filter, topic_filter)) {
                _ = self.subscriptions.swapRemove(i);
                break;
            }
        }
        std.log.info("Client {s} unsubscribed to {s}", .{ self.identifer, topic_filter });
    }

    pub fn queueMessage(self: *Client, message: Message) !void {
        try self.outgoing_queue.append(message);
    }

    pub fn acknowledgeMessage(self: *Client, packet_id: u16) void {
        _ = self.inflight_messages.remove(packet_id);
    }

    pub fn updateActivity(self: *Client) void {
        self.last_activity = time.milliTimestamp();
    }

    pub fn debugPrint(self: *Client) void {
        std.debug.print("----- CLIENT {any} -----\n", .{self.id});
        std.debug.print("Protocol Version: {any}\n", .{self.protocol_version});
        std.debug.print("Address: {any}\n", .{self.address});
        std.debug.print("Is Connected: {any}\n", .{self.is_connected});
        std.debug.print("Connect Time: {}\n", .{self.connect_time});
        std.debug.print("Last Activity: {}\n", .{self.last_activity});
        std.debug.print("Clean Start: {}\n", .{self.clean_start});
        std.debug.print("Session Expiry Interval: {}\n", .{self.session_expiry_interval});
        std.debug.print("Keep Alive: {d}\n", .{self.keep_alive});
        std.debug.print("Username: {?s}\n", .{self.username});
        std.debug.print("Password: {?s}\n", .{self.password});
        std.debug.print("Will Topic: {?s}\n", .{self.will_topic});
        std.debug.print("Will Payload: {?s}\n", .{self.will_payload});
        std.debug.print("Will QoS: {}\n", .{self.will_qos});
        std.debug.print("Will Retain: {}\n", .{self.will_retain});
        std.debug.print("Will Delay Interval: {}\n", .{self.will_delay_interval});
        // std.debug.print("Subscriptions: {}\n", .{self.subscriptions});
        // std.debug.print("Incoming Queue: {}\n", .{self.incoming_queue});
        // std.debug.print("Outgoing Queue: {}\n", .{self.outgoing_queue});
        std.debug.print("Receive Maximum: {}\n", .{self.receive_maximum});
        std.debug.print("Maximum Packet Size: {}\n", .{self.maximum_packet_size});
        std.debug.print("Topic Alias Maximum: {}\n", .{self.topic_alias_maximum});
        // std.debug.print("User Properties: {}\n", .{self.user_properties});
        std.debug.print("Packet ID Counter: {}\n", .{self.packet_id_counter});
        // std.debug.print("Inflight Messages: {}\n", .{self.inflight_messages});
        std.debug.print("----------\n", .{});
    }
};

// [MQTT-3.1.3-5] length and chars
pub fn isValidClientId(client_id: []const u8) bool {
    // Check if the length is between 1 and 23 bytes
    if (client_id.len < 1 or client_id.len > 23) {
        return false;
    }

    // Check if all characters are valid
    for (client_id) |char| {
        switch (char) {
            '0'...'9', 'a'...'z', 'A'...'Z' => continue,
            else => return false,
        }
    }

    // Check if the client_id is valid UTF-8
    return std.unicode.utf8ValidateSlice(client_id);
}

test "isValidClientId" {
    const expect = std.testing.expect;

    try expect(isValidClientId("validClientId123"));
    try expect(isValidClientId("a"));
    try expect(isValidClientId("ABCDEFGHIJKLMNOPQRSTUVW"));
    try expect(!isValidClientId(""));
    try expect(!isValidClientId("tooLongClientIdAAAAAAAAA"));
    try expect(!isValidClientId("invalid-client-id"));
    try expect(!isValidClientId("emoji😊"));
}
