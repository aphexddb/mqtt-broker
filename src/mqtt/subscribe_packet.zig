const std = @import("std");
const Allocator = std.mem.Allocator;
const mqtt = @import("../mqtt.zig");

pub const SubscribePacket = struct {
    packet_id: u16,
    subscription_identifier: ?u32,
    user_properties: std.ArrayList(UserProperty),
    topics: std.ArrayList(SubscribeTopic),

    pub fn init(allocator: Allocator, packet_id: u16) SubscribePacket {
        return .{
            .packet_id = packet_id,
            .subscription_identifier = null,
            .user_properties = std.ArrayList(UserProperty).init(allocator),
            .topics = std.ArrayList(SubscribeTopic).init(allocator),
        };
    }

    pub fn deinit(self: *SubscribePacket) void {
        self.user_properties.deinit();
        self.topics.deinit();
    }

    pub const UserProperty = struct {
        key: []const u8,
        value: []const u8,
    };

    pub const SubscriptionOptions = packed struct {
        reserved: u2 = 0,
        retain_handling: u2,
        retain_as_published: bool,
        no_local: bool,
        qos: mqtt.QoS,
    };

    pub const SubscribeTopic = struct {
        filter: []const u8,
        options: SubscriptionOptions,
    };
};
