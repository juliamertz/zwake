// reference used: https://wiki.wireshark.org/WakeOnLAN

const std = @import("std");
const posix = std.posix;

/// Different ports that accept magic packets
/// The default is `discard` or port 9
pub const Port = enum(u8) {
    discard = 9,
    echo = 7,
    reserved = 0,
};

pub const MagicPacket = struct {
    /// Synchronization Stream
    sync: [6]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
    /// Target MAC Address repeated 16 times
    target: [96]u8,

    const Self = @This();

    pub fn init(mac_address: [6]u8) Self {
        return Self{
            .target = mac_address ** 16,
        };
    }

    /// Attemp to broadcast a packet on given socket and network address
    pub fn broadcast(self: Self, socket: posix.socket_t, address: std.net.Address) !void {
        const payload = self.sync ++ self.target;
        const port = std.mem.bigToNative(u16, address.getPort());
        const dest_address_in = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = port,
            .addr = address.in.sa.addr,
        };

        _ = try posix.sendto(
            socket,
            &payload,
            0,
            @ptrCast(&dest_address_in),
            @sizeOf(posix.sockaddr.in),
        );
    }
};

pub const MacAddress = struct {
    addr: [6]u8,

    const Self = @This();

    /// Parse 48-bit mac address from string
    pub fn parse(addr: []const u8) !Self {
        var result: [6]u8 = undefined;
        var i: usize = 0;

        var buff: [2]u8 = undefined;
        var j: usize = 0;

        for (addr) |ch| {
            buff[j] = ch;

            if (ch == ':' or ch == '-') continue;

            if (j == buff.len - 1) {
                result[i] = try std.fmt.parseInt(u8, &buff, 16);
                i += 1;
                j = 0;
            } else {
                j += 1;
            }
        }

        return Self{ .addr = result };
    }
};

/// Open UDP socket with necessary options for broadcasting a magic packet
pub fn openSocket() !posix.socket_t {
    const socket = try posix.socket(
        posix.AF.INET,
        posix.SOCK.DGRAM,
        posix.IPPROTO.UDP,
    );

    try posix.setsockopt(
        socket,
        posix.SOL.SOCKET,
        posix.SO.BROADCAST,
        // TODO: figure out what this does?
        &std.mem.toBytes(@as(c_int, 1)),
    );

    return socket;
}

const expectEq = std.testing.expectEqual;

test "Parse mac address" {
    const expected: [6]u8 = .{ 0x1A, 0x2B, 0x3C, 0xD4, 0xE5, 0xF6 };

    try expectEq(expected, (try MacAddress.parse("1A:2B:3C:D4:E5:F6")).addr);
    try expectEq(expected, (try MacAddress.parse("1A2B:3C:D4:E5F6")).addr);
    try expectEq(expected, (try MacAddress.parse("1A-2B-3C-D4-E5-F6")).addr);
}
