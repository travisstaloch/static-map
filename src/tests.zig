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
        try testing.expectEqual(gop.status, .new);
        gop.value_ptr.* = v;
    }
    // check all keys and values present
    for (keys, values) |k, v| {
        const idx = map.getIndex(k) orelse return error.Unexpected;
        try testing.expectEqual(v, map.values[idx]);
        try testing.expectEqual(v, map.get(k).?);
        try testing.expectEqual(v, map.getPtr(k).?.*);
    }
    // remove all keys and verify
    for (keys, values) |k, v| {
        // std.debug.print("{s}\n", .{k});
        const removed = map.remove(k) orelse return error.Unexpected;
        try testing.expectEqual(v, removed);
    }
    for (keys) |k| {
        try testing.expect(map.get(k) == null);
    }
    try testing.expectEqual(0, map.count());
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
        try testing.expect(map.get(k) == null);
    }
    try testing.expectEqual(0, map.count());
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

test "usage" {
    // const static_map = @import("static-map");
    // init()
    const Map = static_map.StaticStringMap(u8, 16);
    var map = Map.init();
    // put()/get()/contains()
    try map.put("abc", 1);
    try testing.expect(map.contains("abc"));
    try testing.expectEqual(1, map.get("abc"));
    // getOrPut()
    const gop = map.getOrPut("abc");
    try testing.expectEqual(.existing, gop.status);
    gop.value_ptr.* = 2;
    try testing.expectEqual(2, map.get("abc"));
    // putAssumeCapacity()
    map.putAssumeCapacity("def", 3);
    try testing.expectEqual(3, map.get("def"));
    // putNoClobber()
    map.putNoClobber("ghi", 4);
    try testing.expectEqual(4, map.get("ghi"));
    // getPtr()
    map.getPtr("def").?.* = 5;
    try testing.expectEqual(5, map.get("def"));
    // count()
    try testing.expectEqual(3, map.count());
    // iterator()
    var iter = map.iterator();
    var count: u8 = 0;
    while (iter.next()) |kv| : (count += 1) {
        try std.io.null_writer.print("{s}: {}", .{ kv.key, kv.value });
    }
    try testing.expectEqual(map.count(), count);
}

test "initComptime - Map" {
    const Map = static_map.StaticStringMap(u8, 16);
    const map_kvs1 = .{ .{ "foo", 1 }, .{ "bar", 2 } };
    inline for (.{map_kvs1}) |map_kvs| {
        { // const
            const map = Map.initComptime(map_kvs, .{});
            try testing.expectEqual(2, map.count());
            try testing.expectEqual(1, map.get("foo"));
            try testing.expectEqual(2, map.get("bar"));
        }
        {
            const map = Map.initComptimeContext(map_kvs, .{}, .{});
            try testing.expectEqual(2, map.count());
            try testing.expectEqual(1, map.get("foo"));
            try testing.expectEqual(2, map.get("bar"));
        }
        { // var
            var map = Map.initComptime(map_kvs, .{});
            map.putNoClobber("baz", 1);
            try testing.expectEqual(3, map.count());
        }
    }
    // array kvs
    const Map2 = static_map.AutoStaticMap(u32, u32, 16);
    const map2_kvs1: []const [2]u32 = &.{ .{ 1, 2 }, .{ 3, 4 } };
    inline for (.{map2_kvs1}) |map_kvs| {
        { // const
            const map = Map2.initComptime(map_kvs, .{});
            try testing.expectEqual(2, map.count());
            try testing.expectEqual(2, map.get(1));
            try testing.expectEqual(4, map.get(3));
        }
        {
            const map = Map2.initComptimeContext(map_kvs, .{}, .{});
            try testing.expectEqual(2, map.count());
            try testing.expectEqual(2, map.get(1));
            try testing.expectEqual(4, map.get(3));
        }
        { // var
            var map = Map2.initComptime(map_kvs, .{});
            map.putNoClobber(4, 5);
            try testing.expectEqual(3, map.count());
        }
    }

    // slice kvs
    const Map3 = static_map.AutoStaticMap(u32, u32, 16);
    const map3_kvs1: []const []const u32 = &.{ &.{ 1, 2 }, &.{ 3, 4 } };
    inline for (.{map3_kvs1}) |map_kvs| {
        {
            const map = Map3.initComptime(map_kvs, .{});
            try testing.expectEqual(2, map.count());
            try testing.expectEqual(2, map.get(1));
            try testing.expectEqual(4, map.get(3));
        }
    }

    // non-string u8 slice kvs
    const Map4 = static_map.AutoStaticMap(u8, u8, 16);
    const map4_kvs1: []const []const u8 = &.{ &.{ 1, 2 }, &.{ 3, 4 } };
    inline for (.{map4_kvs1}) |map_kvs| {
        {
            const map = Map4.initComptime(map_kvs, .{});
            try testing.expectEqual(2, map.count());
            try testing.expectEqual(2, map.get(1));
            try testing.expectEqual(4, map.get(3));
        }
    }
}

test "initComptime - Set" {
    const Set = static_map.StaticStringSet(16);
    const set_kvs1 = .{ .{"foo"}, .{"bar"} };
    const set_kvs2 = .{ "foo", "bar" };
    inline for (.{ set_kvs1, set_kvs2 }) |set_kvs| {
        {
            const set = Set.initComptime(set_kvs, .{});
            try testing.expectEqual(2, set.count());
            try testing.expectEqual({}, set.get("foo"));
            try testing.expectEqual({}, set.get("bar"));
        }
        {
            const set = Set.initComptimeContext(set_kvs, .{}, .{});
            try testing.expectEqual(2, set.count());
            try testing.expectEqual({}, set.get("foo"));
            try testing.expectEqual({}, set.get("bar"));
        }
    }
}

test "initComptime - many keys don't exceed @evalBranchQuota" {
    const keys = comptime std.zig.Token.keywords.keys();
    const values = comptime std.zig.Token.keywords.values();
    const cap: usize = @intFromFloat(@floor(@as(comptime_float, @floatFromInt(keys.len)) * 1.6));
    const Map = static_map.StaticStringMap(std.zig.Token.Tag, cap);
    comptime var kvs: [keys.len]struct { Map.Key, Map.Value } = undefined;
    comptime for (0..kvs.len) |i| {
        kvs[i] = .{ keys[i], values[i] };
    };
    const keywords = Map.initComptime(kvs, .{ .eval_branch_quota = 2000 });
    for (keys, values) |k, v| {
        try testing.expectEqual(v, keywords.get(k));
    }
}
