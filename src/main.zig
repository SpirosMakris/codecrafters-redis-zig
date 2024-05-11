const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Ziggy Redis\n", .{});

    const address = try net.Address.resolveIp("127.0.0.1", 6379);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        const connection = try listener.accept();
        // This will close the connection, after the CURRENT loop iteration
        // is finished.
        defer connection.stream.close();

        // Note the !void return of `ping_response()`. We need to use try
        // to propagate errors upward
        try ping_response(connection);
    }
}

fn ping_response(connection: net.Server.Connection) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("accepted new connection", .{});

    try connection.stream.writeAll("+PONG\r\n");
}
