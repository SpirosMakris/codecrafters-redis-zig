const std = @import("std");
const RespParser = @import("parser.zig");
const net = std.net;

const State = struct {
    hash_map: *std.StringArrayHashMap(MapEntry),
    mutex: *std.Thread.Mutex,
};

const MapEntry = struct { value: []const u8, added_at: i64, px: ?i64 };

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Ziggy Redis\n", .{});

    const allocator = std.heap.page_allocator;
    var hash_map = std.StringArrayHashMap(MapEntry).init(allocator);
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
            std.debug.print("L: {}", .{fifo.readableLength()});
            var parser = RespParser.RespParser.init(allocator, fifo.readableSliceOfLen(bytes_read));
            const parse_result = try parser.parse();
            if (parse_result == null) break; // Incomplete command, wait for more data to be read

            const result = parse_result.?;
            handle_command(result.command, connection.stream, state) catch |err| {
                std.debug.print("Handling command: {}\n\n", .{err});
                break;
            };
            fifo.discard(bytes_read);
            const num_left = fifo.readableLength();
            std.debug.print("Rem: {}\n", .{num_left});
            if (num_left == 0) break;
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

            const map_entry = MapEntry{
                .value = payload.value,
                .added_at = std.time.milliTimestamp(),
                .px = payload.px,
            };

            try state.hash_map.put(payload.key, map_entry);
            try stream.writeAll("+OK\r\n");

            std.debug.print("WROTE OK\n", .{});
        },
        RespParser.Command.Get => |payload| {
            state.mutex.lock();
            defer state.mutex.unlock();

            const entry: ?MapEntry = state.hash_map.get(payload.key);
            if (entry == null) {
                try stream.writeAll("$-1\r\n");
            } else {
                const now = std.time.milliTimestamp();
                const added_at = entry.?.added_at;
                const px = entry.?.px;
                if (px == null or now < (added_at + px.?)) {
                    const len = entry.?.value.len;
                    const value = entry.?.value;

                    try stream.writer().print("${d}\r\n{s}\r\n", .{ len, value });
                } else {
                    try stream.writeAll("$-1\r\n");
                }
            }
        },
        else => {
            try stream.writeAll("-ERR unknown command\r\n");
        },
    }
}
