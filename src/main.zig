const std = @import("std");
const RespParser = @import("./RespParser.zig");
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

const HandlerError = error{ ConnectioReadFailed, BufferFull };

fn handle_client(stdout: anytype, connection: net.Server.Connection) !void {
    defer connection.stream.close();

    try stdout.print("accepted new connection\n", .{});

    const reader = connection.stream.reader();
    var buf: [128]u8 = undefined;

    var offset: usize = 0;
    while (true) {
        std.debug.print("reading.\n", .{});
        // Read into buffer slice from offset to end
        const bytes_read = reader.read(buf[offset..]) catch |err| {
            std.debug.print("ERROR: {}", .{err});
            return HandlerError.ConnectioReadFailed;
        };

        if (bytes_read == 0) {
            std.debug.print("No bytes read. Possible EOF.\n", .{});
            break;
        }

        std.debug.print("read: {} bytes.\n", .{bytes_read});
        std.debug.print("Buffer: {s}\n", .{buf});

        if ((bytes_read == 0) and (offset == 0)) {
            // We haven't read anything. This is an error
            return HandlerError.ConnectioReadFailed;
        }

        offset += bytes_read;

        if (offset >= buf.len) {
            std.debug.print("Buffer full. Increase buffer size.\n", .{});
            return HandlerError.BufferFull;
        }

        // Try parsing
        std.debug.print("Read buffer: {s}\n\n", .{buf});

        var parser = RespParser.RespParser.init(&buf);
        _ = parser.parse();

        switch (try parser.matchCommand()) {
            RespParser.Command.Ping => {
                try connection.stream.writeAll("+PONG\r\n");
            },
            RespParser.Command.Echo => |payload| {
                std.debug.print("ECHO: {s}\n\n", .{payload});
                try connection.stream.writer().print("${}\r\n{s}\r\n", .{ payload.len, payload });
            },
            else => {
                std.debug.print("NO MATCH!!!\n", .{});
                unreachable;
            },
        }
    }
}
