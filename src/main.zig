const std = @import("std");
const posix = std.posix;
const net = std.net;

const Port = enum(usize) {
    reserved = 0,
    echo = 7,
    discard = 9,
};

const MagicPacket = struct {
    payload: [102]u8,

    const sync = [6]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };

    pub fn init(mac_addr: [6]u8) MagicPacket {
        return MagicPacket{
            .payload = sync ++ mac_addr ** 16,
        };
    }
};

/// Open socket with options for broadcasting a wake on lan packet
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
        &std.mem.toBytes(@as(c_int, 1)),
    );

    return socket;
}

pub fn main() !void {
    const port = @intFromEnum(Port.discard);
    const address = try net.Address.parseIp4("192.168.0.255", port);

    const socket = try openSocket();
    defer posix.close(socket);

    const opt_cast = &std.mem.toBytes(@as(c_int, 1));
    try posix.setsockopt(
        socket,
        posix.SOL.SOCKET,
        posix.SO.BROADCAST,
        opt_cast,
    );

    // 04:7c:16:eb:df:9b
    const packet = MagicPacket.init(
        [6]u8{ 0x04, 0x7c, 0x16, 0xeb, 0xdf, 0x9b },
    );
    // const packet = MagicPacket.init([6]u8{ 0, 0, 0, 0, 0, 0 });

    const dest_address_in = posix.sockaddr.in{
        .family = posix.AF.INET,
        .port = std.mem.bigToNative(u16, port),
        .addr = address.in.sa.addr,
    };

    _ = try posix.sendto(
        socket,
        &packet.payload,
        0,
        @ptrCast(&dest_address_in),
        @sizeOf(posix.sockaddr.in),
    );

    std.process.exit(0);

    std.debug.print("address: {any}, socket: {any}, packet: {any}\n", .{ address, socket, packet });
    // try posix.bind(socket, &address.any, address.getOsSockLen());
}
