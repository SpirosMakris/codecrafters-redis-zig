//! Parser for resp(Redis protocol) commands
pub const State = enum {
    start,
    array_len,
    array_r,
    array_n,
    bstring_len,
    bstring_len_r,
    bstring_copy,
    bstring_copy_r,
    bstring_copy_n,
    invalid,
};

pub const RespParser = struct {
    state: State = .start,
    buf: []const u8,
    elems: [2][128]u8,
    array_num_elems: u8,
    curr_elem: u8,
    curr_elem_len: u8,
    curr_elem_cp_idx: usize,

    // Initializes the parser with a provide buffer `buf`
    pub fn init(input: []const u8) RespParser {
        return .{
            .buf = input,
            .array_num_elems = 0,
            .curr_elem = 0,
            .curr_elem_len = 0,
            .curr_elem_cp_idx = 0,
            .elems = undefined,
        };
    }

    const ParsedResult = struct { cmd: Command, position: u64 };

    pub fn parse(p: *RespParser) ParsedResult {
        for (p.buf, 0..) |c, i| switch (p.state) {
            .start => switch (c) {
                '*' => {
                    p.state = .array_len;
                },
                else => {
                    p.state = .invalid;
                    return ParsedResult{ .cmd = Command{ .Invalid = {} }, .position = i };
                },
            },
            .array_len => {
                const digit = switch (c) {
                    '0'...'9' => |b| b - '0',
                    '\r' => {
                        p.state = .array_r;
                        continue;
                    },
                    else => {
                        p.state = .invalid;
                        continue;
                    },
                };

                p.array_num_elems = p.array_num_elems * 10 + digit;
            },
            .array_r => switch (c) {
                '\n' => {
                    p.state = .array_n;
                },
                else => {
                    p.state = .invalid;
                },
            },
            .array_n => switch (c) {
                '$' => {
                    p.state = .bstring_len;
                },
                else => {
                    p.state = .invalid;
                },
            },
            .bstring_len => {
                const digit = switch (c) {
                    '0'...'9' => |b| b - '0',
                    '\r' => {
                        p.state = .bstring_len_r;
                        continue;
                    },
                    else => {
                        p.state = .invalid;
                        continue;
                    },
                };

                p.curr_elem_len = p.curr_elem_len * 10 + digit;
            },
            .bstring_len_r => switch (c) {
                '\n' => p.state = .bstring_copy,
                else => {
                    p.state = .invalid;
                },
            },
            .bstring_copy => {
                const char = switch (c) {
                    '0'...'9' => |b| b - '0',
                    'A'...'Z' => |b| b,
                    'a'...'z' => |b| b,
                    '\r' => {
                        p.state = .bstring_copy_r;
                        p.elems[p.curr_elem][p.curr_elem_cp_idx] = 0;

                        continue;
                    },
                    else => {
                        p.state = .invalid;
                        continue;
                    },
                };

                p.elems[p.curr_elem][p.curr_elem_cp_idx] = char;
                p.curr_elem_cp_idx += 1;
            },
            .bstring_copy_r => switch (c) {
                '\n' => p.state = .bstring_copy_n,
                else => p.state = .invalid,
            },
            .bstring_copy_n => switch (c) {
                '$' => {
                    // Advance current elem and reset relevant indices
                    p.curr_elem += 1;
                    p.curr_elem_len = 0;
                    p.curr_elem_cp_idx = 0;

                    p.state = .bstring_len;
                },

                else => {
                    p.state = .invalid;
                },
            },
            .invalid => {
                return ParsedResult{ .cmd = Command{ .Invalid = {} }, .position = i };
            },
        };

        return ParsedResult{ .cmd = .Incomplete, .position = 0 };
    }

    // Function to check if a buffer matches a command
    fn matchesCommand(buffer: []u8, command: []const u8) bool {
        return buffer.len >= command.len and std.mem.eql(u8, buffer[0..command.len], command);
    }

    const ParserError = error{MatchFailed};

    pub fn matchCommand(p: *RespParser) !Command {
        // Match commands on number of array elements found during parsing

        switch (p.array_num_elems) {
            1 => {
                // PING
                if (matchesCommand(&p.elems[0], "PING")) return Command{ .Ping = {} };
            },
            2 => {
                // ECHO
                if (matchesCommand(&p.elems[0], "ECHO")) {
                    const payload = p.elems[1][0..p.curr_elem_cp_idx];

                    std.debug.print("Found ECHO with payload: {s}\n", .{payload});

                    return Command{ .Echo = payload };
                }
            },
            else => unreachable,
        }

        return ParserError.MatchFailed;
    }
};

pub const Command = union(enum) {
    Ping: void,
    Echo: []const u8,
    Invalid: void,
    Incomplete: void, // Represents an incomplete command that needs more data @TODO
};

const std = @import("std");

test "parse PING command" {
    const testing = std.testing;

    const data_ping: []const u8 = "*1\r\n$4\r\nPING\r\n";
    var r = RespParser.init(data_ping);

    _ = r.parse();

    const res = try r.matchCommand();

    try testing.expectEqual(Command{ .Ping = {} }, res);
}

test "parse ECHO command" {
    const testing = std.testing;

    const data_echo: []const u8 = "*2\r\n$4\r\nECHO\r\n$7\r\nlalakia\r\n";

    var r = RespParser.init(data_echo);

    _ = r.parse();

    const res = try r.matchCommand();

    try testing.expectEqual(Command{ .Echo = &r.elems[1] }, res);
}
