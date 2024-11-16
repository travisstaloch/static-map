const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
pub const StringContext2 = std.array_hash_map.StringContext;

pub const StringContext1 = struct {
    pub fn hash(_: StringContext1, s: []const u8) u32 {
        return hashString1(s);
    }

    pub fn eql(_: StringContext1, a: []const u8, b: []const u8, b_index: u32) bool {
        _ = b_index;
        return eqlString1(a, b);
    }
};

pub fn hashString1(s: []const u8) u32 {
    var pos = s.ptr;
    var h: u32 = 0;
    const end = s.ptr + s.len;
    while (pos != end) : (pos += 1) {
        h = (h *% 31) +% pos[0];
    }
    return h;
}

pub fn eqlString1(a: []const u8, b: []const u8) bool {
    return mem.eql(u8, a, b);
}

pub fn StaticStringMap(comptime V: type, comptime capacity: u32) type {
    return StaticStringMapContext(V, capacity, StringContext1);
}

pub fn StaticStringMapContext(comptime V: type, comptime capacity: u32, comptime Context: type) type {
    return StaticMap([]const u8, V, capacity, Context);
}

pub fn StaticStringSet(comptime capacity: u32) type {
    return StaticStringSetContext(capacity, StringContext1);
}

pub fn StaticStringSetContext(comptime capacity: u32, comptime Context: type) type {
    return StaticMap([]const u8, void, capacity, Context);
}

pub fn AutoStaticMap(comptime K: type, comptime V: type, comptime capacity: u32) type {
    return StaticMap(K, V, capacity, std.array_hash_map.AutoContext(K));
}

pub fn AutoStaticSet(comptime K: type, comptime capacity: u32) type {
    return StaticMap(K, void, capacity, std.array_hash_map.AutoContext(K));
}

/// A key, value map backed by static key and value arrays with a bitset.
/// `capacity` should be chosen so that the map will be around 50% to 75% full.
/// `capacity` can be any number and does NOT need to be a power of 2.
///
/// This API is somewhat similar to std.ArrayHashMap and can use
/// `std.array_hash_map.AutoContext(K)`
pub fn StaticMap(
    comptime K: type,
    comptime V: type,
    comptime capacity: u32,
    comptime Context: type,
) type {
    return struct {
        bitset: BitSet,
        keys: [capacity]Key,
        values: [capacity]Value,
        ctx: Context,

        const BitSet = std.StaticBitSet(capacity);
        const Self = @This();
        const is_pow2 = std.math.isPowerOfTwo(capacity);
        const is_ctx_zero_sized = @sizeOf(Context) == 0;
        const is_value_zero_sized = @sizeOf(Value) == 0;

        pub const Key = K;
        pub const Value = V;

        pub fn init() Self {
            assert(is_ctx_zero_sized); // if assert fails use initContext();
            return initContext(undefined);
        }

        pub fn initContext(ctx: Context) Self {
            return .{
                .keys = undefined,
                .values = undefined,
                .bitset = BitSet.initEmpty(),
                .ctx = ctx,
            };
        }

        pub inline fn initComptime(comptime kvs_list: anytype) Self {
            comptime {
                assert(is_ctx_zero_sized); // if assert fails use initComptimeContext();
                return initComptimeContext(kvs_list, undefined);
            }
        }

        pub inline fn initComptimeContext(comptime kvs_list: anytype, ctx: Context) Self {
            comptime {
                // a linear bound should be fine
                assert(capacity >= kvs_list.len);
                const capf: f32 = @floatFromInt(capacity);
                const lenf: f32 = @floatFromInt(kvs_list.len);
                const ratio = capf / lenf;
                const quota = 50 * std.math.pow(f32, lenf, ratio);
                @setEvalBranchQuota(@intFromFloat(quota));
                var map = initContext(ctx);
                for (0..kvs_list.len) |i| {
                    const key = switch (@typeInfo(@TypeOf(kvs_list[i]))) {
                        .@"struct" => kvs_list[i].@"0",
                        else => kvs_list[i],
                    };
                    const gop = map.getOrPut(key);
                    assert(gop.status == .new);
                    if (!is_value_zero_sized) gop.value_ptr.* = kvs_list[i].@"1";
                }
                return map;
            }
        }

        pub const GetOrPutResult = struct {
            status: Status,
            value_ptr: *Value,
            /// Do not modify the key unless it results in the same hash
            /// or you call map.rehash() afterward.
            key_ptr: *Key,
            index: u32,

            pub const Status = enum {
                /// the key was not found and has been added.  `value_ptr`
                /// points to an undefined value.
                new,
                /// the key was found.  `value_ptr` points to an existing value.
                existing,
                /// the map is full and the key has not been added.
                /// `value_ptr`, `key_ptr` and `index` are undefined.
                map_full,
            };
        };

        /// insert `key` into first available slot if not found.
        /// returns key and value pointers and status indicating whether or not
        /// the key was found.  When status == .map_full, pointers and index are
        /// undefined;
        pub fn getOrPut(map: *Self, key: Key) GetOrPutResult {
            var result: GetOrPutResult = .{
                .status = .new,
                .index = if (is_pow2)
                    map.ctx.hash(key) & (capacity - 1)
                else
                    map.ctx.hash(key) % capacity,
                .key_ptr = undefined,
                .value_ptr = undefined,
            };
            for (0..capacity) |_| {
                // std.debug.print("h {} set {}\n", .{ h, map.bits.isSet(h) });
                if (!map.bitset.isSet(result.index)) {
                    map.keys[result.index] = key;
                    break;
                }
                if (map.ctx.eql(key, map.keys[result.index], result.index)) {
                    result.status = .existing;
                    break;
                }
                result.index = if (is_pow2)
                    (result.index + 1) & (capacity - 1)
                else
                    (result.index + 1) % capacity;
            } else return .{
                .status = .map_full,
                .value_ptr = undefined,
                .key_ptr = undefined,
                .index = undefined,
            };

            map.bitset.set(result.index);
            result.value_ptr = &map.values[result.index];
            result.key_ptr = &map.keys[result.index];
            return result;
        }

        pub fn put(map: *Self, key: Key, value: Value) !void {
            const gop = map.getOrPut(key);
            if (gop.status == .map_full) return error.MapFull;
            gop.value_ptr.* = value;
        }

        /// asserts that the map is not full
        pub fn putAssumeCapacity(map: *Self, key: Key, value: Value) void {
            const gop = map.getOrPut(key);
            assert(gop.status != .map_full);
            gop.value_ptr.* = value;
        }

        /// asserts that the key is new
        pub fn putNoClobber(map: *Self, key: Key, value: Value) void {
            const gop = map.getOrPut(key);
            assert(gop.status == .new);
            gop.value_ptr.* = value;
        }

        /// return the index where `key` is found in `map.keys` or else null.
        /// this index can also be used for `map.values`.
        pub fn getIndex(map: *const Self, key: Key) ?u32 {
            var h = if (is_pow2)
                map.ctx.hash(key) & (capacity - 1)
            else
                map.ctx.hash(key) % capacity;
            for (0..capacity) |_| {
                const is_set = map.bitset.isSet(h);
                // std.debug.print("h {}\n", .{h});
                if (is_set and map.ctx.eql(key, map.keys[h], h)) {
                    // std.debug.print("{} {s}\n", .{ i, k });
                    return h;
                } else if (!is_set) break;
                h = if (is_pow2)
                    (h + 1) & (capacity - 1)
                else
                    (h + 1) % capacity;
            }

            return null;
        }

        /// return a value pointer for `key` or else null
        pub fn getPtr(map: *Self, key: Key) ?*Value {
            return if (map.getIndex(key)) |i| &map.values[i] else null;
        }

        /// return a value for `key` or else null
        pub fn get(map: *const Self, key: Key) ?Value {
            return if (map.getIndex(key)) |i| map.values[i] else null;
        }

        pub fn contains(map: *const Self, key: Key) bool {
            return (map.getIndex(key) != null);
        }

        /// returns the removed value if `key` is found otherwise null.
        ///
        /// this method is slow because it calls rehash() when `key` is found.
        pub fn remove(map: *Self, key: Key) ?V {
            if (map.getIndex(key)) |i| {
                map.bitset.unset(i);
                map.keys[i] = undefined;
                const v = map.values[i];
                map.values[i] = undefined;
                // TODO skip rehash() if no indices will change
                map.rehash();
                return v;
            }
            return null;
        }

        pub fn clear(map: *Self) void {
            map.bitset = BitSet.initEmpty();
            @memset(&map.keys, undefined);
            @memset(&map.values, undefined);
        }

        pub fn rehash(map: *Self) void {
            var m = initContext(map.ctx);
            var iter = map.bitset.iterator(.{});
            while (iter.next()) |i| {
                const gop = m.getOrPut(map.keys[i]);
                assert(gop.status == .new);
                gop.value_ptr.* = map.values[i];
            }
            map.* = m;
        }

        pub fn count(map: *const Self) u32 {
            return @truncate(map.bitset.count());
        }

        pub const KV = struct { key: Key, value: Value };
        pub const KVPtr = struct { key: *Key, value: *Value };

        pub const Iterator = struct {
            map: *Self,
            inner: BitSet.Iterator(.{}),

            pub fn next(iter: *Iterator) ?KV {
                const i = iter.inner.next() orelse return null;
                return .{ .key = iter.map.keys[i], .value = iter.map.values[i] };
            }

            pub fn nextIndex(iter: *Iterator) ?u32 {
                const i = iter.inner.next() orelse return null;
                return @truncate(i);
            }

            pub fn nextPtr(iter: *Iterator) ?KVPtr {
                const i = iter.inner.next() orelse return null;
                return .{ .key = &iter.map.keys[i], .value = &iter.map.values[i] };
            }
        };

        pub fn iterator(map: *Self) Iterator {
            return .{
                .map = map,
                .inner = map.bitset.iterator(.{}),
            };
        }
    };
}
