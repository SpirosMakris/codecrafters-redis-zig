const std = @import("std");

pub const Command = union(enum) { Ping, Echo: []const u8, Set: struct { key: []const u8, value: []const u8, px: ?i64 }, Get: struct { key: []const u8 }, Generic: struct { name: []const u8, args: [][]const u8 } };

pub const DataType = union(enum) { Array_t: usize, BString_t: usize, Payload_t };

pub const State = enum {
    Array,
    Command,
    Done,
};

const NUM_CMDS = 10;
const NUM_ARGS = 10;

const ParseResult = struct {
    command: Command,
    consumed_bytes: usize,
};

pub const RespParser = struct {
    allocator: std.mem.Allocator,
    buf: []const u8,
    state: State,
    commands: []Command,
    command_count: usize,
    temp_args: [][]const u8,
    temp_lens: [NUM_ARGS]usize, // store declared lengths of bulk strings
    num_elems: usize,
    curr_arg_index: usize,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) RespParser {
        return RespParser{ .allocator = allocator, .buf = input, .state = .Array, .commands = allocator.alloc(Command, NUM_CMDS) catch unreachable, .temp_args = allocator.alloc([]const u8, NUM_ARGS) catch unreachable, .temp_lens = [_]usize{0} ** NUM_ARGS, .num_elems = 0, .curr_arg_index = 0, .command_count = 0 };
    }

    pub fn parse(self: *RespParser) !?ParseResult {
        var tokens = std.mem.tokenize(u8, self.buf, "\r\n");
        var consumed_bytes: usize = 0;

        while (tokens.next()) |token| {
            consumed_bytes += token.len + 2; // include /r/n

            switch (self.state) {
                .Array => {
                    switch (try parse_data_type(token)) {
                        .Array_t => |len| {
                            self.num_elems = len;
                            self.state = .Command;
                        },
                        else => return error.InvalidFormat,
                    }
                },
                .Command => {
                    switch (try parse_data_type(token)) {
                        .BString_t => |len| {
                            // Store the expected length of the bulk string
                            self.temp_lens[self.curr_arg_index] = len;
                            self.state = .Command; // Remaining in Command state, gotta parse more
                        },
                        .Payload_t => {
                            self.temp_args[self.curr_arg_index] = token;
                            self.curr_arg_index += 1;

                            // Check if we parsed all elements of the command array
                            if (self.curr_arg_index == self.num_elems) {
                                // Ready to process parse command now
                                try self.process_command();

                                // Reset for subsequent runs
                                self.curr_arg_index = 0;

                                self.state = .Array;

                                return ParseResult{
                                    .command = self.commands[self.command_count - 1],
                                    .consumed_bytes = consumed_bytes,
                                };
                            }
                        },
                        else => return error.InvalidFormat,
                    }
                },
                .Done => {},
            }
        }

        return null; // Indicates incomplete command
    }

    fn process_command(self: *RespParser) !void {
        if (self.num_elems == 0) return error.InvalidFormat;

        const cmd_name = self.temp_args[0]; // the 0-th arg in our args slice is the actual command name
        if (std.mem.eql(u8, cmd_name, "PING")) {
            self.commands[self.command_count] = Command{ .Ping = {} };
        } else if (std.mem.eql(u8, cmd_name, "ECHO")) {
            if (self.num_elems != 2) return error.InvalidNumArgsForEcho;

            self.commands[self.command_count] = Command{ .Echo = self.temp_args[1] };
        } else if (std.mem.eql(u8, cmd_name, "GET")) {
            if (self.num_elems != 2) return error.InvalidNumArgsForGet;
            self.commands[self.command_count] = Command{ .Get = .{ .key = self.temp_args[1] } };
        } else if (std.mem.eql(u8, cmd_name, "SET")) {
            if (self.num_elems != 3) return error.InvalidNumArgsForSet;

            var px: ?i64 = null;
            if (self.num_elems == 5 and std.mem.eql(u8, self.temp_args[3], "PX")) {
                px = try std.fmt.parseInt(i64, self.temp_args[4], 10);
            }

            self.commands[self.command_count] = Command{ .Set = .{
                .key = self.temp_args[1],
                .value = self.temp_args[2],
                .px = px,
            } };
        } else {
            self.commands[self.command_count] = Command{ .Generic = .{
                .name = cmd_name,
                .args = self.temp_args[1..self.num_elems],
            } };
        }

        self.command_count += 1;
    }

    pub fn parse_data_type(token_t: []const u8) !DataType {
        switch (token_t[0]) {
            '*' => {
                const array_len = std.fmt.parseInt(usize, token_t[1..], 10) catch return error.FailedParseArrayLen;
                return DataType{ .Array_t = array_len };
            },
            '$' => {
                const bstring_len = std.fmt.parseInt(usize, token_t[1..], 10) catch return error.FailedParseBStringLen;
                return DataType{ .BString_t = bstring_len };
            },
            // else => return error.UnknownDataType,
            else => return DataType{ .Payload_t = {} },
        }
    }
};

test "ping" {
    const testing = std.testing;

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer _ = gpa.deinit();
    // const allocator = gpa.allocator();

    const data_ping: []const u8 = "*1\r\n$4\r\nPING\r\n";
    var ping_parser = RespParser.init(std.heap.page_allocator, data_ping);
    defer ping_parser.deinit();

    try ping_parser.parse();

    std.debug.print("{any}\n\n", .{ping_parser.commands});

    try testing.expectEqual(Command{ .Ping = {} }, ping_parser.commands[0]);

    std.debug.print("================\n", .{});
}

test "echo" {
    const testing = std.testing;

    const data_echo: []const u8 = "*2\r\n$4\r\nECHO\r\n$7\r\nlalakia\r\n";
    var echo_parser = RespParser.init(std.heap.page_allocator, data_echo);
    defer echo_parser.deinit();

    try echo_parser.parse();

    std.debug.print("{any}\n\n", .{echo_parser.commands});

    const arg_start = std.mem.indexOf(u8, data_echo, "lalakia").?;
    const arg_end = arg_start + "lalakia".len;
    const arg = data_echo[arg_start..arg_end];

    try testing.expectEqual(Command{ .Echo = arg }, echo_parser.commands[0]);
}

test "set" {}
