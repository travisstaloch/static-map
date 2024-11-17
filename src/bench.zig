const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");

const static_map = @import("static-map");

const MapKind = enum {
    std_static_string_map,
    this_static_string_map,
    this_static_string_map2,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();

    // parse args
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    var kinds = std.enums.EnumSet(MapKind).initEmpty();
    for (args[1..]) |arg| {
        kinds.insert(std.meta.stringToEnum(MapKind, arg) orelse
            return error.InvalidModeArg);
    }
    const pow2_lens = .{ 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192 };
    const str_key_len_min = 3;
    const str_key_len_max = 10;

    // allocate and assign keys and values
    const max_cap = pow2_lens[pow2_lens.len - 1];
    const str_keys = try alloc.alloc([]u8, max_cap);
    defer {
        for (str_keys) |k| alloc.free(k);
        alloc.free(str_keys);
    }
    for (0..max_cap) |i| {
        const len = random.intRangeAtMost(u8, str_key_len_min, str_key_len_max);
        str_keys[i] = try alloc.alloc(u8, len);
        for (0..len) |j| str_keys[i][j] = random.int(u8);
    }
    const int_keys = try alloc.alloc(u32, max_cap);
    defer alloc.free(int_keys);
    for (0..max_cap) |i| {
        int_keys[i] = random.int(u32);
    }

    // bench
    inline for (pow2_lens) |_cap| {
        const cap = _cap;
        if (kinds.contains(.std_static_string_map)) {
            const kvs = try alloc.alloc(struct { []const u8 }, cap);
            defer alloc.free(kvs);
            for (0..cap) |i| {
                kvs[i][0] = str_keys[i];
            }
            const Map = std.StaticStringMap(void);
            var map = try Map.init(kvs, alloc);
            defer map.deinit(alloc);
            var timer = try std.time.Timer.start();
            for (0..cap) |i| {
                std.mem.doNotOptimizeAway(map.get(str_keys[i]));
            }
            outputResult(.std_static_string_map, cap, timer.lap());
        }

        const this_cap = @floor(cap * 1.5); //cap * 2;

        if (kinds.contains(.this_static_string_map)) {
            const Map = static_map.StaticStringSet(this_cap);
            var map = Map.init();
            for (str_keys[0..cap]) |k| map.putNoClobber(k, {});
            var timer = try std.time.Timer.start();
            for (0..cap) |i| {
                std.mem.doNotOptimizeAway(map.get(str_keys[i]));
            }
            outputResult(.this_static_string_map, cap, timer.lap());
        }

        if (kinds.contains(.this_static_string_map2)) {
            const Map = static_map.StaticMap([]const u8, void, this_cap, static_map.StringContext2);
            var map = Map.init();
            for (str_keys[0..cap]) |k| map.putNoClobber(k, {});
            var timer = try std.time.Timer.start();
            for (0..cap) |i| {
                std.mem.doNotOptimizeAway(map.get(str_keys[i]));
            }
            outputResult(.this_static_string_map2, cap, timer.lap());
        }
    }
}

fn outputResult(mode: MapKind, cap: comptime_int, ns: u64) void {
    // std.io.getStdOut().writer().print("{s}\t{d: >4}\t{s}\t{}\n", .{ @tagName(builtin.mode), cap, @tagName(mode), ns }) catch unreachable;
    std.io.getStdOut().writer().print("{d}\t{s}\t{}\n", .{ cap, @tagName(mode), ns }) catch unreachable;
}
