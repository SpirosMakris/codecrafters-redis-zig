const std = @import("std");
const RespParser = @import("parser.zig");
const net = std.net;

const State = struct {
    hash_map: *std.StringArrayHashMap([]const u8),
    mutex: *std.Thread.Mutex,
};

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("Ziggy Redis\n", .{});

    const allocator = std.heap.page_allocator;

    // Create hash map
    var hash_map = std.StringArrayHashMap([]const u8).init(allocator);
    defer hash_map.deinit();

    // Create mutex
    var mutex = std.Thread.Mutex{};
    var state = State{
        .hash_map = &hash_map,
        .mutex = &mutex,
    };

    const address = try net.Address.resolveIp("127.0.0.1", 6379);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    while (true) {
        // We'll close the connection, inside the handler function
        const connection = try listener.accept();

        _ = try std.Thread.spawn(.{}, handle_client, .{ stdout, connection, &state });
    }
}

const HandlerError = error{ ConnectioReadFailed, BufferFull };

fn handle_client(stdout: anytype, connection: net.Server.Connection, state: *State) !void {
    std.debug.print("*****************\n", .{});

    defer connection.stream.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    try stdout.print("accepted new connection\n", .{});

    const reader = connection.stream.reader();
    var buf: [128]u8 = undefined;

    var offset: usize = 0;
    while (true) {
        std.debug.print("======> reading.\n", .{});
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
        std.debug.print("Buffer: {s}\n\n\n", .{buf});

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

        var parser = RespParser.RespParser.init(allocator, &buf);
        try parser.parse();

        switch (parser.commands[0]) {
            RespParser.Command.Ping => {
                try connection.stream.writeAll("+PONG\r\n");
            },
            RespParser.Command.Echo => |payload| {
                std.debug.print("ECHO: {s}\n\n", .{payload});
                try connection.stream.writer().print("${d}\r\n{s}\r\n", .{ payload.len, payload });
            },
            RespParser.Command.Set => |payload| {
                std.debug.print("SET: {any}\n\n", .{payload});

                state.mutex.lock();
                defer state.mutex.unlock();

                try state.hash_map.put(payload.key, payload.value);
                try connection.stream.writeAll("+OK\r\n");
            },
            RespParser.Command.Get => |payload| {
                std.debug.print("GET: {s}\n\n", .{payload.key});

                state.mutex.lock();
                defer state.mutex.unlock();

                const value = state.hash_map.get(payload.key);

                if (value == null) {
                    try connection.stream.writeAll("$-1\r\n");
                } else {
                    try connection.stream.writer().print("${d}\r\n{s}\r\n", .{ value.?.len, value.? });
                }
            },
            else => {
                std.debug.print("NO MATCH!!!\n", .{});
                unreachable;
            },
        }
    }
}
