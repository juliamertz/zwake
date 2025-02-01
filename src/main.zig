// reference used: https://wiki.wireshark.org/WakeOnLAN

const std = @import("std");
const clap = @import("clap");
const posix = std.posix;
const net = std.net;

/// Different ports that accept magic packets
/// The default is `discard` or port 9
const Port = enum(u8) {
    discard = 9,
    echo = 7,
    reserved = 0,
};

const MagicPacket = struct {
    sync: [6]u8 = .{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF },
    payload: [96]u8,

    const Self = @This();

    fn init(mac_address: [6]u8) Self {
        return Self{
            .payload = mac_address ** 16,
        };
    }

    /// Attemp to broadcast a packet on given socket and network address
    fn broadcast(self: Self, socket: posix.socket_t, address: std.net.Address) !void {
        const port = std.mem.bigToNative(u16, address.getPort());
        const dest_address_in = posix.sockaddr.in{
            .family = posix.AF.INET,
            .port = port,
            .addr = address.in.sa.addr,
        };

        _ = try posix.sendto(
            socket,
            &self.payload,
            0,
            @ptrCast(&dest_address_in),
            @sizeOf(posix.sockaddr.in),
        );
    }
};

const MacAddress = struct {
    addr: [6]u8,

    const Self = @This();

    /// Parse mac address from string of assumed size 12
    fn parse(addr: []const u8) !Self {
        const clean = cleanAddress(addr);
        var parts: [6]u8 = undefined;

        var i: usize = 0;
        while (i < 6) {
            const start = (i * 2);
            const end = start + 2;
            if (end > clean.len) return error.OutOfBounds;
            const part = clean[start..end];
            parts[i] = try std.fmt.parseInt(u8, part, 16);
            i += 1;
        }

        return Self{ .addr = parts };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help           Display this help and exit.
        \\-m, --mac <string>   48-bit mac address
        \\-i, --ip  <string>   Broadcast IP address
    );

    const stderr = std.io.getStdErr().writer();
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .allocator = gpa.allocator(),
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) return clap.help(stderr, clap.Help, &params, .{});
    if (res.args.mac == null or res.args.ip == null) {
        std.log.err("Invalid usage,\nTo display help information run '--help'\n", .{});
        std.process.exit(1);
    }

    const socket = try openSocket();
    defer posix.close(socket);

    const port = @intFromEnum(Port.discard);
    const address = try net.Address.parseIp4(res.args.ip.?, port);

    const mac = try MacAddress.parse(res.args.mac.?);
    const packet = MagicPacket.init(mac.addr);

    try packet.broadcast(socket, address);
}

/// Open UDP socket with necessary options for broadcasting a magic packet
fn openSocket() !posix.socket_t {
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

/// Remove `:` and '-' from mac address string
fn cleanAddress(addr: []const u8) [12]u8 {
    var buff: [12]u8 = undefined;

    var i: usize = 0;
    for (addr) |ch| {
        if (ch == ':' or ch == '-') continue;
        buff[i] = ch;
        i += 1;
    }

    return buff;
}
