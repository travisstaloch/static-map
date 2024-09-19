const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const talloc = std.testing.allocator;

const static_map = @import("static-map");

fn expectKV(comptime Map: type, map: *Map, k: Map.Key, v: Map.Value) !void {
    const gop = map.getOrPut(k);
    try testing.expectEqual(.new, gop.status);
    gop.value_ptr.* = v;

    // std.debug.print("{b:0>2}\n", .{map.found_bits.mask});
    const gop2 = map.getOrPut(k);
    try testing.expectEqual(.existing, gop2.status);
    try testing.expectEqual(v, gop2.value_ptr.*);
}

test "basic" {
    const Map = static_map.StaticStringMap(u8, 2);
    var map = Map.init();

    try expectKV(Map, &map, "foo", 1);
    try expectKV(Map, &map, "bar", 2);
    try testing.expectEqual(.map_full, map.getOrPut("baz").status);
}

test {
    const keys: []const []const u8 = &.{
        "bool", "c_int", "c_long", "c_longdouble", "t20",
        "t19",  "t18",   "t17",    "t16",          "t15",
        "t14",  "t13",   "t12",    "t11",          "t10",
        "t9",   "t8",    "t7",     "t6",           "t5",
        "t4",   "t3",    "t2",     "t1",
    };
    const values: []const u32 = &std.simd.iota(u32, keys.len);
    const Map = static_map.StaticStringMap(u32, keys.len);
    // init map
    var map = Map.init();
    for (keys, values) |k, v| {
        const gop = map.getOrPut(k);
        try std.testing.expectEqual(gop.status, .new);
        gop.value_ptr.* = v;
    }
    // check all keys and values present
    for (keys, values) |k, v| {
        const idx = map.getIndex(k) orelse return error.Unexpected;
        try std.testing.expectEqual(v, map.values[idx]);
        try std.testing.expectEqual(v, map.get(k).?);
        try std.testing.expectEqual(v, map.getPtr(k).?.*);
    }
    // remove all keys and verify
    for (keys, values) |k, v| {
        // std.debug.print("{s}\n", .{k});
        const removed = map.remove(k) orelse return error.Unexpected;
        try std.testing.expectEqual(v, removed);
    }
    for (keys) |k| {
        try std.testing.expect(map.get(k) == null);
    }
    try std.testing.expectEqual(0, map.count());
}

fn testType(comptime Map: type, keys: []const Map.Key, values: []const Map.Value) !void {
    var map = Map.init();
    for (keys, 0..) |k, i| {
        const gop = map.getOrPut(k);
        try testing.expectEqual(.new, gop.status);
        if (Map.Value != void)
            gop.value_ptr.* = values[i];
    }
    for (keys, 0..) |k, i| {
        const v = map.get(k) orelse return error.Unexpected;
        if (Map.Value != void)
            try testing.expectEqual(values[i], v);
    }
    for (keys, 0..) |k, i| {
        const v = map.remove(k) orelse return error.Unexpected;
        if (Map.Value != void)
            try testing.expectEqual(values[i], v);
    }
    for (keys) |k| {
        try std.testing.expect(map.get(k) == null);
    }
    try std.testing.expectEqual(0, map.count());
}

test "various map types, random keys" {
    const cap = 1000;
    const str_key_len = 5;
    const str_keys = try talloc.alloc([]u8, cap);
    defer {
        for (str_keys) |k| talloc.free(k);
        talloc.free(str_keys);
    }
    var prng = std.Random.DefaultPrng.init(0);
    const random = prng.random();
    for (0..cap) |i| {
        str_keys[i] = try talloc.alloc(u8, str_key_len);
        for (0..str_key_len) |j| str_keys[i][j] = random.int(u8);
    }
    const int_keys = try talloc.alloc(u32, cap);
    defer talloc.free(int_keys);
    for (0..cap) |i| {
        int_keys[i] = random.int(u32);
    }

    try testType(static_map.StaticStringMap(u32, cap), str_keys, int_keys);
    try testType(static_map.StaticStringSet(cap), str_keys, &.{});
    try testType(static_map.AutoStaticMap(u32, u32, cap), int_keys, int_keys);
    try testType(static_map.AutoStaticSet(u32, cap), int_keys, &.{});
}

test "iterator" {
    const Map = static_map.StaticStringMap(u8, 10);
    var map = Map.init();
    {
        var iter = map.iterator();
        try testing.expectEqual(null, iter.next());
        try testing.expectEqual(null, iter.nextIndex());
    }
    try map.put("foo", 1);
    map.putAssumeCapacity("bar", 2);
    map.putNoClobber("baz", 3);
    {
        var iter = map.iterator();
        try testing.expectEqual(Map.KV{ .key = "foo", .value = 1 }, iter.next());
        try testing.expectEqual(Map.KV{ .key = "baz", .value = 3 }, iter.next());
        try testing.expectEqual(Map.KV{ .key = "bar", .value = 2 }, iter.next());
        try testing.expectEqual(null, iter.next());
    }
    map.clear();
    {
        var iter = map.iterator();
        try testing.expectEqual(null, iter.nextPtr());
    }
}
