const std = @import("std");
const net = std.net;
const mqtt = @import("mqtt.zig");
const connect = @import("handle_connect.zig");
const config = @import("config.zig");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const PacketReaderError = error{
    AllocatedBufferTooSmall,
    LengthTooSmall,
    BufferTooSmall,
    InvalidCommand,
    InvalidProtocolName,
    InvalidProtocolLevel,
    MalformedPacket,
    InvalidRemainingLength,
    InvalidLength,
};

pub const PacketWriterError = error{
    StreamWriteError,
    BufferTooSmall,
    NoPacketStarted,
};

// PacketError stores an error with additional context when reading a packet
pub const PacketError = struct {
    err: anyerror,
    byte_position: usize,
};

pub const Reader = struct {
    buffer: []u8,
    pos: usize,
    previous_pos: usize,
    length: usize,

    pub fn init(buffer: []u8) Reader {
        return Reader{
            .buffer = buffer,
            .pos = 0,
            .previous_pos = 0,
            .length = 0,
        };
    }

    pub fn getContextForError(self: *Reader, err: anyerror) PacketError {
        return PacketError{
            .err = err,
            .byte_position = self.previous_pos,
        };
    }

    pub fn start(self: *Reader, length: usize) !void {
        if (length < 2) {
            return PacketReaderError.MalformedPacket;
        }

        if (length > self.buffer.len) {
            return PacketReaderError.AllocatedBufferTooSmall;
        }

        self.pos = 0;
        self.length = length;
        self.previous_pos = 0;
    }

    fn ensureRemainingBytes(self: *Reader, bytes: usize) !void {
        if (self.pos + bytes > self.length) {
            return PacketReaderError.BufferTooSmall;
        }
    }

    pub fn peekCommand(self: *Reader, position: usize) !mqtt.Command {
        try ensureRemainingBytes(self, 1);
        const control_byte = self.buffer[position];

        // Attempt to convert the packet type to an enum value
        return std.meta.intToEnum(mqtt.Command, control_byte >> 4) catch {
            std.debug.print("unknown packet type hex:{X} int:{d}\n", .{ control_byte >> 4, control_byte >> 4 });
            return PacketReaderError.InvalidCommand;
        };
    }

    pub fn readCommand(self: *Reader) !mqtt.Command {
        const cmd = try self.peekCommand(self.pos);
        self.previous_pos = self.pos;
        self.pos = self.pos + 1;
        return cmd;
    }

    pub fn readRemainingLength(self: *Reader) !usize {
        if (self.pos >= self.length - 1) {
            // std.debug.print("+++ readRemainingLength> error: self.pos ({d}) > self.length ({d})\n", .{ self.pos, self.length });
            return PacketReaderError.BufferTooSmall;
        }

        const remaining_packet_length = try parseRemainingLength(self.buffer[self.pos..]);
        // std.debug.print("+++ readRemainingLength> remaining packet length: {any}\n", .{remaining_packet_length});
        const bytes_used_for_remaining_length = remainingLengthSize(remaining_packet_length);
        // std.debug.print("+++ readRemainingLength> number of bytes used for length: {any}\n", .{bytes_used_for_remaining_length});

        if (bytes_used_for_remaining_length + self.pos > self.length) {
            return PacketReaderError.MalformedPacket;
        }

        self.previous_pos = self.pos;
        self.pos = self.pos + bytes_used_for_remaining_length;

        return remaining_packet_length;
    }

    pub fn peekByte(self: *Reader, position: usize) !u8 {
        if (position >= self.length) {
            return PacketReaderError.BufferTooSmall;
        }
        return self.buffer[position];
    }

    pub fn readByte(self: *Reader) !u8 {
        try ensureRemainingBytes(self, 1);
        const byte = self.buffer[self.pos];
        self.previous_pos = self.pos;
        self.pos = self.pos + 1;
        return byte;
    }

    pub fn readTwoBytes(self: *Reader) !u16 {
        try ensureRemainingBytes(self, 2);

        const msb = self.buffer[self.pos];
        const lsb = self.buffer[self.pos + 1];

        self.previous_pos = self.pos;
        self.pos = self.pos + 2;

        return @as(u16, msb) << 8 | lsb;
    }

    //  readUTF8String handles situations where zero-length strings are permitted (like for the client identifier in MQTT v3.1.1).
    pub fn readUTF8String(self: *Reader, allow_zero_length: bool) PacketReaderError!?[]u8 {
        if (self.buffer.len < self.pos + 2) return PacketReaderError.BufferTooSmall;

        std.debug.print("> readUTF8String, pos: {} allow_zero_length: {}\n", .{ self.pos, allow_zero_length });

        const length = std.mem.readInt(u16, self.buffer[self.pos..][0..2], .big);
        self.previous_pos = self.pos;
        self.pos = self.pos + 2;

        // std.debug.print(">> pos: {}, length: {d}\n", .{ self.pos, length });

        // Handle zero-length strings
        if (length == 0) {
            std.debug.print("> readUTF8String, found a zero length string\n", .{});
            if (allow_zero_length) {
                return null;
            } else {
                return null;
            }
        }

        // Sanity check
        if (self.pos + length > self.length) {
            std.debug.print(">> self.pos {} + length {} is GREATER than length {}\n", .{ self.pos, self.length, self.length });
            return PacketReaderError.LengthTooSmall;
        }

        if (self.pos + length > self.buffer.len) {
            std.debug.print(">> self.pos {} + length {} is GREATER than buffer length {}\n", .{ self.pos, self.length, self.buffer.len });
            return PacketReaderError.BufferTooSmall;
        }

        const expected_buffer = self.buffer[self.pos..][0..length];
        // std.debug.print(">> expected buffer: {s} {any}\n", .{ expected_buffer, expected_buffer });

        self.previous_pos = self.pos;
        self.pos = self.pos + length;

        return expected_buffer;
    }

    pub fn readClientId(self: *Reader) PacketReaderError!?[]u8 {
        std.debug.print("Reading cient id\n", .{});
        return self.readUTF8String(true);
    }

    pub fn readUserName(self: *Reader) PacketReaderError!?[]u8 {
        std.debug.print("Reading username\n", .{});
        return self.readUTF8String(false);
    }

    pub fn readPassword(self: *Reader) PacketReaderError!?[]u8 {
        std.debug.print("Reading password\n", .{});
        return self.readUTF8String(false);
    }

    // Parses the packet length of an MQTT packet
    pub fn parseRemainingLength(buffer: []const u8) PacketReaderError!usize {
        assert(buffer.len > 0);

        var multiplier: usize = 1;
        var value: usize = 0;
        var i: usize = 0;

        while (true) {
            if (i >= buffer.len) return PacketReaderError.InvalidRemainingLength;
            const byte = buffer[i];
            value += @as(usize, byte & 127) * multiplier;
            if (multiplier > 128 * 128 * 128) return PacketReaderError.InvalidRemainingLength;
            multiplier *= 128;
            i += 1;
            if (byte & 128 == 0) break;
        }

        return value;
    }

    // Calculates the size of the remaining length field for an MQTT packet
    pub fn remainingLengthSize(length: usize) usize {
        assert(length >= 0);

        if (length < 128) return 1;
        if (length < 16384) return 2;
        if (length < 2097152) return 3;
        return 4;
    }
};

pub const Writer = struct {
    buffer: []u8,
    pos: usize,
    length_pos: ?usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*Writer {
        // TODO: make the  buffers longer, e.g. 2097152 max packet size to handle large payloads, etc.
        const write_buffer = try allocator.alloc(u8, config.WRITE_BUFFER_SIZE);

        const writer = try allocator.create(Writer);
        writer.* = .{
            .allocator = allocator,
            .buffer = write_buffer,
            .pos = 0,
            .length_pos = null,
        };

        return writer;
    }

    pub fn deinit(self: *Writer) void {
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    pub fn len(self: *Writer) usize {
        return self.pos;
    }

    pub fn writeControlByte(self: *Writer, cmd: mqtt.Command) !void {
        if (self.pos >= self.buffer.len) {
            return PacketWriterError.BufferTooSmall;
        }
        self.buffer[self.pos] = @intFromEnum(cmd) << 4;
        self.pos += 1;
    }

    pub fn startPacket(self: *Writer, cmd: mqtt.Command) !void {
        self.reset();
        try self.writeControlByte(cmd);
        self.length_pos = self.pos;
        // Reserve space for the maximum possible length (4 bytes)
        self.pos += 4;
    }

    pub fn finishPacket(self: *Writer) !void {
        if (self.length_pos) |length_pos| {
            const content_length = self.pos - length_pos - 4;
            const length_bytes = try encodeLengthBytes(content_length);
            const actual_length = std.mem.indexOfScalar(u8, &length_bytes, 0) orelse 4;

            // Shift the content to make room for the actual length
            std.mem.copyBackwards(u8, self.buffer[length_pos + actual_length ..], self.buffer[length_pos + 4 .. self.pos]);

            // Write the actual length
            @memcpy(self.buffer[length_pos..][0..actual_length], length_bytes[0..actual_length]);

            // Adjust the position
            self.pos -= 4 - actual_length;

            self.length_pos = null;
            // std.debug.print("content_length: {any}\n", .{content_length});
            // std.debug.print("length_bytes: {any}\n", .{length_bytes[0..actual_length]});
            // std.debug.print("self.buffer: {any}\n", .{self.buffer[0..self.pos]});
        } else {
            return PacketWriterError.NoPacketStarted;
        }
    }

    pub fn writeByte(self: *Writer, byte: u8) !void {
        if (self.pos >= self.buffer.len) {
            return PacketWriterError.BufferTooSmall;
        }
        self.buffer[self.pos] = byte;
        self.pos += 1;
    }

    pub fn writeTwoBytes(self: *Writer, value: u16) !void {
        if (self.pos + 2 > self.buffer.len) {
            return PacketWriterError.BufferTooSmall;
        }
        self.buffer[self.pos] = @intCast((value >> 8) & 0xFF);
        self.buffer[self.pos + 1] = @intCast(value & 0xFF);
        self.pos += 2;
    }

    pub fn writeUTF8String(self: *Writer, string: []const u8) !void {
        if (self.pos + 2 + string.len > self.buffer.len) {
            return PacketWriterError.BufferTooSmall;
        }
        try self.writeTwoBytes(@intCast(string.len));
        std.mem.copy(u8, self.buffer[self.pos..], string);
        self.pos += string.len;
    }

    fn encodeLengthBytes(length: usize) ![4]u8 {
        var result: [4]u8 = [_]u8{0} ** 4;
        var index: usize = 0;
        var value = length;

        if (value == 0) {
            return result;
        }

        while (true) {
            var byte: u8 = @intCast(value % 128);
            value /= 128;
            if (value > 0) {
                byte |= 128;
            }
            result[index] = byte;
            index += 1;
            if (value == 0 or index == 4) break;
        }

        return result;
    }

    pub fn writeToStream(self: *Writer, stream: *net.Stream) !void {
        const written = try stream.write(self.buffer[0..self.pos]);
        if (written != self.pos) {
            return PacketWriterError.StreamWriteError;
        }
    }

    fn reset(self: *Writer) void {
        self.pos = 0;
        self.length_pos = null;
    }

    pub fn getWrittenLength(self: *Writer) usize {
        return self.pos;
    }
};
