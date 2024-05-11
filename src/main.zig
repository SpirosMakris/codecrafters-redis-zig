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
        // We'll close the connection, inside the handler function

        _ = try std.Thread.spawn(.{}, handle_client, .{ stdout, connection });
    }
}

fn handle_client(stdout: anytype, connection: net.Server.Connection) !void {
    defer connection.stream.close();

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
