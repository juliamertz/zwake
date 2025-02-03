const std = @import("std");
const net = @import("net.zig");
const clap = @import("clap");

const parsers = .{
    .string = clap.parsers.string,
    .port = clap.parsers.enumeration(net.Port),
};

const params = clap.parseParamsComptime(
    \\-h, --help            Display this help and exit.
    \\-m, --mac  <string>   48-bit mac address
    \\-i, --ip   <string>   Broadcast IP address
    \\-p, --port <port>     Port to target, one of: [discard, echo, reserved]
);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const stderr = std.io.getStdErr().writer();
    var diag = clap.Diagnostic{};
    const parse_options = clap.ParseOptions{
        .allocator = gpa.allocator(),
        .diagnostic = &diag,
    };
    var res = clap.parse(clap.Help, &params, parsers, parse_options) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) return clap.help(stderr, clap.Help, &params, .{});
    if (res.args.mac == null or res.args.ip == null) {
        std.log.err("Invalid usage,\nTo display help information run '--help'\n", .{});
        std.process.exit(1);
    }

    const socket = try net.openSocket();
    defer std.posix.close(socket);

    const mac = try net.MacAddress.parse(res.args.mac.?);
    const packet = net.MagicPacket.init(mac.addr);

    const port = res.args.port orelse net.Port.discard;
    const ip = try std.net.Address.parseIp4(res.args.ip.?, @intFromEnum(port));

    try packet.broadcast(socket, ip);
}
