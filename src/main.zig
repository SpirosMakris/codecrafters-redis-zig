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
    var hash_map = std.StringArrayHashMap([]const u8).init(allocator);
    defer hash_map.deinit();

    var mutex = std.Thread.Mutex{};
    var state = State{
        .hash_map = &hash_map,
        .mutex = &mutex,
    };

    const address = try net.Address.resolveIp("127.0.0.1", 6379);
    var listener = try address.listen(.{ .reuse_address = true });
    defer listener.deinit();

    while (true) {
        const connection = try listener.accept();
        _ = try std.Thread.spawn(.{}, handle_client, .{ stdout, connection, &state });
    }
}

const HandlerError = error{ ConnectioReadFailed, BufferFull };

fn handle_client(stdout: anytype, connection: net.Server.Connection, state: *State) !void {
    try stdout.print("accepted new connection\n", .{});
    defer connection.stream.close();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const reader = connection.stream.reader();

    var fifo_buff: [1024]u8 = undefined;
    const fifo_type = std.fifo.LinearFifo(u8, .Slice);
    var fifo = fifo_type.init(fifo_buff[0..]);

    defer fifo.deinit();

    while (true) {
        const buf = try fifo.writableWithSize(256);
        const bytes_read = reader.read(buf) catch |err| {
            std.debug.print("ERROR: {}\n", .{err});
            return HandlerError.ConnectioReadFailed;
        };
        fifo.update(bytes_read);

        if (bytes_read == 0) break;

        // Try to parse all commands that have been read.
        // break out on partial command input
        while (true) {
            var parser = RespParser.RespParser.init(allocator, fifo.readableSliceOfLen(bytes_read));
            const parse_result = try parser.parse();
            if (parse_result == null) break; // Incomplete command, wait for more data to be read

            const result = parse_result.?;
            handle_command(result.command, connection.stream, state) catch |err| {
                std.debug.print("Handling command: {}\n\n", .{err});
                break;
            };
        }
    }
}

fn handle_command(command: RespParser.Command, stream: anytype, state: *State) !void {
    switch (command) {
        RespParser.Command.Ping => {
            try stream.writeAll("+PONG\r\n");
        },
        RespParser.Command.Echo => |payload| {
            try stream.writer().print("${d}\r\n{s}\r\n", .{ payload.len, payload });
        },
        RespParser.Command.Set => |payload| {
            state.mutex.lock();
            defer state.mutex.unlock();

            try state.hash_map.put(payload.key, payload.value);
            try stream.writeAll("+OK\r\n");
        },
        RespParser.Command.Get => |payload| {
            state.mutex.lock();
            defer state.mutex.unlock();

            const value = state.hash_map.get(payload.key);
            if (value == null) {
                try stream.writeAll("$-1\r\n");
            } else {
                try stream.writer().print("${d}\r\n{s}\r\n", .{ value.?.len, value.? });
            }
        },
        else => {
            try stream.writeAll("-ERR unknown command\r\n");
        },
    }
}
