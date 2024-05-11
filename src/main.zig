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

    try stdout.print("accepted new connection\n", .{});

    const reader = connection.stream.reader();
    var buf: [128]u8 = undefined;

    while (reader.read(&buf)) |bytes_read| {
        if (bytes_read == 0) {
            std.debug.print("No bytes read. Possible EOF. Closing connection..\n", .{});
            break;
        }

        // Print the contents of the buffer as ASCII characters
        std.debug.print("Read {} bytes: <{s}", .{ bytes_read, buf[0..bytes_read] });
        std.debug.print("Checking for PING substring..\n", .{});

        const found_ping = std.mem.indexOf(u8, buf[0..bytes_read], "PING");
        if (found_ping) |index| {
            std.debug.print("+Found PING at {}! Responding..\n", .{index});
        } else {
            std.debug.print("-Not found. Moving on..\n", .{});
        }
        try connection.stream.writeAll("+PONG\r\n");
    } else |err| {
        try stdout.print("Error reading: {}", .{err});
    }
}
