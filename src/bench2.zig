const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");

const static_map = @import("static-map");

const MapKind = enum {
    std_static_string_map,
    static_map,
    static_map_case_insensitive,
    squeek502_hand_rolled,
    const len = blk: {
        var l: usize = 0;
        for (@typeInfo(MapKind).@"enum".fields) |f| {
            l = @max(l, f.name.len);
        }
        break :blk l;
    };
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
    const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const MapCaseInsensitive = static_map.StaticMap([]const u8, Country, alpha2_codes.len * 3, struct {
        pub fn hash(_: @This(), k: []const u8) u32 {
            std.debug.assert(k.len == 2);
            const lowers: [2]u8 = .{
                (k[0] | 32),
                (k[1] | 32),
            };
            return @as(u16, @bitCast(lowers));
        }
        pub fn eql(_: @This(), a: []const u8, b: []const u8, b_idx: usize) bool {
            _ = b_idx;
            return hash(undefined, a) == hash(undefined, b);
        }
    });

    const iterations = 100_000;
    const map_insensitive = MapCaseInsensitive.initComptime(alpha2_codes, .{ .eval_branch_quota = 5000 });
    var buf: [2]u8 = undefined;
    const validate_maps = false;
    if (validate_maps) {
        for (0..iterations) |_| {
            buf[0] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            buf[1] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            const expected = Country.fromAlpha2(&buf) catch .invalid;
            const actual = map_insensitive.get(&buf) orelse .invalid;
            if (expected != actual) {
                std.log.err("key '{s}' expected {s} got {s}", .{ buf, @tagName(expected), @tagName(actual) });
                return error.Invalid;
            }
        }
    }

    const show_timings = true;
    if (show_timings)
        try std.io.getStdOut().writer().writeAll("iters      map                         time(ns)\n--------\n");

    // bench
    if (kinds.contains(.std_static_string_map)) {
        const Map = std.StaticStringMap(Country);
        const map = Map.initComptime(alpha2_codes);
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            buf[0] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            buf[1] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            std.mem.doNotOptimizeAway(map.get(&buf));
        }
        if (show_timings)
            outputResult(.std_static_string_map, iterations, timer.lap());
    }

    if (kinds.contains(.static_map)) {
        const cap = alpha2_codes.len * 2;
        const Map = static_map.StaticMap([]const u8, Country, cap, static_map.StringContext2);
        const map = Map.initComptime(alpha2_codes, .{});
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            buf[0] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            buf[1] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            std.mem.doNotOptimizeAway(map.get(&buf));
        }
        if (show_timings)
            outputResult(.static_map, iterations, timer.lap());
    }

    if (kinds.contains(.static_map_case_insensitive)) {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            buf[0] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            buf[1] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            std.mem.doNotOptimizeAway(map_insensitive.get(&buf));
        }
        if (show_timings)
            outputResult(.static_map_case_insensitive, iterations, timer.lap());
    }

    if (kinds.contains(.squeek502_hand_rolled)) {
        var timer = try std.time.Timer.start();
        for (0..iterations) |_| {
            buf[0] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            buf[1] = alphabet[random.intRangeLessThan(u8, 0, alphabet.len)];
            std.mem.doNotOptimizeAway(Country.fromAlpha2(&buf));
        }
        if (show_timings)
            outputResult(.squeek502_hand_rolled, iterations, timer.lap());
    }
}

fn outputResult(mode: MapKind, iterations: comptime_int, ns: u64) void {
    // std.io.getStdOut().writer().print("{s}\t{d: >4}\t{s}\t{}\n", .{ @tagName(builtin.mode), cap, @tagName(mode), ns }) catch unreachable;
    std.io.getStdOut().writer().print("{d: <10} {s: <[2]} {3}\n", .{ iterations, @tagName(mode), MapKind.len, ns }) catch unreachable;
}

// from https://gist.github.com/squeek502/bf453a6ebbbd9eef8ad16ca43df78f1a

pub fn alpha2_to_lookup_id(alpha2_code: []const u8) error{InvalidAlpha2Code}!usize {
    if (alpha2_code.len != 2) return error.InvalidAlpha2Code;
    const a = try alpha2_digit(alpha2_code[0]);
    const b = try alpha2_digit(alpha2_code[1]);
    return @as(u16, a) * 26 + b;
}

fn alpha2_digit(c: u8) error{InvalidAlpha2Code}!u8 {
    return switch (c) {
        'a'...'z' => c - 'a',
        'A'...'Z' => c - 'A',
        else => return error.InvalidAlpha2Code,
    };
}

const alpha2_lookup = lookup: {
    // The maximum possible 2-length alpha codes is small enough
    // that we can just create an array element for each possibility,
    // and set all the unspecified indexes to `.invalid`
    const max_2_digit_alpha_codes = 26 * 26;
    var lookup = [_]Country{.invalid} ** max_2_digit_alpha_codes;
    for (alpha2_codes) |alpha_code_mapping| {
        const alpha_code = alpha_code_mapping.@"0";
        const country = alpha_code_mapping.@"1";
        const lookup_id = alpha2_to_lookup_id(alpha_code) catch unreachable;
        lookup[lookup_id] = country;
    }
    break :lookup lookup;
};

pub const Country = enum {
    afghanistan,
    aland_islands,
    albania,
    algeria,
    american_samoa,
    andorra,
    angola,
    anguilla,
    antarctica,
    antigua_and_barbuda,
    argentina,
    armenia,
    aruba,
    australia,
    austria,
    azerbaijan,
    bahamas_the,
    bahrain,
    bangladesh,
    barbados,
    belarus,
    belgium,
    belize,
    benin,
    bermuda,
    bhutan,
    bolivia_plurinational_state_of,
    bonaire_sint_eustatius_and_saba,
    bosnia_and_herzegovina,
    botswana,
    bouvet_island,
    brazil,
    british_indian_ocean_territory_the,
    brunei_darussalam,
    bulgaria,
    burkina_faso,
    burundi,
    cabo_verde,
    cambodia,
    cameroon,
    canada,
    cayman_islands_the,
    central_african_republic_the,
    chad,
    chile,
    china,
    christmas_island,
    cocos_keeling_islands_the,
    colombia,
    comoros_the,
    congo_the_democratic_republic_of_the,
    congo_the,
    cook_islands_the,
    costa_rica,
    cote_divoire,
    croatia,
    cuba,
    curacao,
    cyprus,
    czechia,
    denmark,
    djibouti,
    dominica,
    dominican_republic_the,
    ecuador,
    egypt,
    el_salvador,
    equatorial_guinea,
    eritrea,
    estonia,
    eswatini,
    ethiopia,
    falkland_islands_the_malvinas,
    faroe_islands_the,
    fiji,
    finland,
    france,
    french_guiana,
    french_polynesia,
    french_southern_territories_the,
    gabon,
    gambia_the,
    georgia,
    germany,
    ghana,
    gibraltar,
    greece,
    greenland,
    grenada,
    guadeloupe,
    guam,
    guatemala,
    guernsey,
    guinea,
    guinea_bissau,
    guyana,
    haiti,
    heard_island_and_mcdonald_islands,
    holy_see_the,
    honduras,
    hong_kong,
    hungary,
    iceland,
    india,
    indonesia,
    iran_islamic_republic_of,
    iraq,
    ireland,
    isle_of_man,
    israel,
    italy,
    jamaica,
    japan,
    jersey,
    jordan,
    kazakhstan,
    kenya,
    kiribati,
    korea_the_democratic_peoples_republic_of,
    korea_the_republic_of,
    kuwait,
    kyrgyzstan,
    lao_peoples_democratic_republic_the,
    latvia,
    lebanon,
    lesotho,
    liberia,
    libya,
    liechtenstein,
    lithuania,
    luxembourg,
    macao,
    north_macedonia,
    madagascar,
    malawi,
    malaysia,
    maldives,
    mali,
    malta,
    marshall_islands_the,
    martinique,
    mauritania,
    mauritius,
    mayotte,
    mexico,
    micronesia_federated_states_of,
    moldova_the_republic_of,
    monaco,
    mongolia,
    montenegro,
    montserrat,
    morocco,
    mozambique,
    myanmar,
    namibia,
    nauru,
    nepal,
    netherlands_the,
    new_caledonia,
    new_zealand,
    nicaragua,
    niger_the,
    nigeria,
    niue,
    norfolk_island,
    northern_mariana_islands_the,
    norway,
    oman,
    pakistan,
    palau,
    palestine_state_of,
    panama,
    papua_new_guinea,
    paraguay,
    peru,
    philippines_the,
    pitcairn,
    poland,
    portugal,
    puerto_rico,
    qatar,
    reunion,
    romania,
    russian_federation_the,
    rwanda,
    saint_barthelemy,
    saint_helena_ascension_island_and_tristan_da_cunha,
    saint_kitts_and_nevis,
    saint_lucia,
    saint_martin_french_part,
    saint_pierre_and_miquelon,
    saint_vincent_and_the_grenadines,
    samoa,
    san_marino,
    sao_tome_and_principe,
    saudi_arabia,
    senegal,
    serbia,
    seychelles,
    sierra_leone,
    singapore,
    sint_maarten_dutch_part,
    slovakia,
    slovenia,
    solomon_islands,
    somalia,
    south_africa,
    south_georgia_and_the_south_sandwich_islands,
    south_sudan,
    spain,
    sri_lanka,
    sudan_the,
    suriname,
    svalbard_and_jan_mayen,
    sweden,
    switzerland,
    syrian_arab_republic_the,
    taiwan_province_of_china,
    tajikistan,
    tanzania_the_united_republic_of,
    thailand,
    timor_leste,
    togo,
    tokelau,
    tonga,
    trinidad_and_tobago,
    tunisia,
    turkiye,
    turkmenistan,
    turks_and_caicos_islands_the,
    tuvalu,
    uganda,
    ukraine,
    united_arab_emirates_the,
    united_kingdom_of_great_britain_and_northern_ireland_the,
    united_states_minor_outlying_islands_the,
    united_states_of_america_the,
    uruguay,
    uzbekistan,
    vanuatu,
    venezuela_bolivarian_republic_of,
    viet_nam,
    virgin_islands_british,
    virgin_islands_us,
    wallis_and_futuna,
    western_sahara,
    yemen,
    zambia,
    zimbabwe,

    /// Only intended for internal use for the alpha2 lookup
    invalid,

    /// Case-insensitive alpha2 code -> country lookup
    pub fn fromAlpha2(alpha2_code: []const u8) error{InvalidAlpha2Code}!Country {
        const lookup_id = try alpha2_to_lookup_id(alpha2_code);
        const country = alpha2_lookup[lookup_id];
        if (country == .invalid) return error.InvalidAlpha2Code;
        return country;
    }
};

const alpha2_codes = [_]struct { []const u8, Country }{
    .{ "af", .afghanistan },
    .{ "ax", .aland_islands },
    .{ "al", .albania },
    .{ "dz", .algeria },
    .{ "as", .american_samoa },
    .{ "ad", .andorra },
    .{ "ao", .angola },
    .{ "ai", .anguilla },
    .{ "aq", .antarctica },
    .{ "ag", .antigua_and_barbuda },
    .{ "ar", .argentina },
    .{ "am", .armenia },
    .{ "aw", .aruba },
    .{ "au", .australia },
    .{ "at", .austria },
    .{ "az", .azerbaijan },
    .{ "bs", .bahamas_the },
    .{ "bh", .bahrain },
    .{ "bd", .bangladesh },
    .{ "bb", .barbados },
    .{ "by", .belarus },
    .{ "be", .belgium },
    .{ "bz", .belize },
    .{ "bj", .benin },
    .{ "bm", .bermuda },
    .{ "bt", .bhutan },
    .{ "bo", .bolivia_plurinational_state_of },
    .{ "bq", .bonaire_sint_eustatius_and_saba },
    .{ "ba", .bosnia_and_herzegovina },
    .{ "bw", .botswana },
    .{ "bv", .bouvet_island },
    .{ "br", .brazil },
    .{ "io", .british_indian_ocean_territory_the },
    .{ "bn", .brunei_darussalam },
    .{ "bg", .bulgaria },
    .{ "bf", .burkina_faso },
    .{ "bi", .burundi },
    .{ "cv", .cabo_verde },
    .{ "kh", .cambodia },
    .{ "cm", .cameroon },
    .{ "ca", .canada },
    .{ "ky", .cayman_islands_the },
    .{ "cf", .central_african_republic_the },
    .{ "td", .chad },
    .{ "cl", .chile },
    .{ "cn", .china },
    .{ "cx", .christmas_island },
    .{ "cc", .cocos_keeling_islands_the },
    .{ "co", .colombia },
    .{ "km", .comoros_the },
    .{ "cd", .congo_the_democratic_republic_of_the },
    .{ "cg", .congo_the },
    .{ "ck", .cook_islands_the },
    .{ "cr", .costa_rica },
    .{ "ci", .cote_divoire },
    .{ "hr", .croatia },
    .{ "cu", .cuba },
    .{ "cw", .curacao },
    .{ "cy", .cyprus },
    .{ "cz", .czechia },
    .{ "dk", .denmark },
    .{ "dj", .djibouti },
    .{ "dm", .dominica },
    .{ "do", .dominican_republic_the },
    .{ "ec", .ecuador },
    .{ "eg", .egypt },
    .{ "sv", .el_salvador },
    .{ "gq", .equatorial_guinea },
    .{ "er", .eritrea },
    .{ "ee", .estonia },
    .{ "sz", .eswatini },
    .{ "et", .ethiopia },
    .{ "fk", .falkland_islands_the_malvinas },
    .{ "fo", .faroe_islands_the },
    .{ "fj", .fiji },
    .{ "fi", .finland },
    .{ "fr", .france },
    .{ "gf", .french_guiana },
    .{ "pf", .french_polynesia },
    .{ "tf", .french_southern_territories_the },
    .{ "ga", .gabon },
    .{ "gm", .gambia_the },
    .{ "ge", .georgia },
    .{ "de", .germany },
    .{ "gh", .ghana },
    .{ "gi", .gibraltar },
    .{ "gr", .greece },
    .{ "gl", .greenland },
    .{ "gd", .grenada },
    .{ "gp", .guadeloupe },
    .{ "gu", .guam },
    .{ "gt", .guatemala },
    .{ "gg", .guernsey },
    .{ "gn", .guinea },
    .{ "gw", .guinea_bissau },
    .{ "gy", .guyana },
    .{ "ht", .haiti },
    .{ "hm", .heard_island_and_mcdonald_islands },
    .{ "va", .holy_see_the },
    .{ "hn", .honduras },
    .{ "hk", .hong_kong },
    .{ "hu", .hungary },
    .{ "is", .iceland },
    .{ "in", .india },
    .{ "id", .indonesia },
    .{ "ir", .iran_islamic_republic_of },
    .{ "iq", .iraq },
    .{ "ie", .ireland },
    .{ "im", .isle_of_man },
    .{ "il", .israel },
    .{ "it", .italy },
    .{ "jm", .jamaica },
    .{ "jp", .japan },
    .{ "je", .jersey },
    .{ "jo", .jordan },
    .{ "kz", .kazakhstan },
    .{ "ke", .kenya },
    .{ "ki", .kiribati },
    .{ "kp", .korea_the_democratic_peoples_republic_of },
    .{ "kr", .korea_the_republic_of },
    .{ "kw", .kuwait },
    .{ "kg", .kyrgyzstan },
    .{ "la", .lao_peoples_democratic_republic_the },
    .{ "lv", .latvia },
    .{ "lb", .lebanon },
    .{ "ls", .lesotho },
    .{ "lr", .liberia },
    .{ "ly", .libya },
    .{ "li", .liechtenstein },
    .{ "lt", .lithuania },
    .{ "lu", .luxembourg },
    .{ "mo", .macao },
    .{ "mk", .north_macedonia },
    .{ "mg", .madagascar },
    .{ "mw", .malawi },
    .{ "my", .malaysia },
    .{ "mv", .maldives },
    .{ "ml", .mali },
    .{ "mt", .malta },
    .{ "mh", .marshall_islands_the },
    .{ "mq", .martinique },
    .{ "mr", .mauritania },
    .{ "mu", .mauritius },
    .{ "yt", .mayotte },
    .{ "mx", .mexico },
    .{ "fm", .micronesia_federated_states_of },
    .{ "md", .moldova_the_republic_of },
    .{ "mc", .monaco },
    .{ "mn", .mongolia },
    .{ "me", .montenegro },
    .{ "ms", .montserrat },
    .{ "ma", .morocco },
    .{ "mz", .mozambique },
    .{ "mm", .myanmar },
    .{ "na", .namibia },
    .{ "nr", .nauru },
    .{ "np", .nepal },
    .{ "nl", .netherlands_the },
    .{ "nc", .new_caledonia },
    .{ "nz", .new_zealand },
    .{ "ni", .nicaragua },
    .{ "ne", .niger_the },
    .{ "ng", .nigeria },
    .{ "nu", .niue },
    .{ "nf", .norfolk_island },
    .{ "mp", .northern_mariana_islands_the },
    .{ "no", .norway },
    .{ "om", .oman },
    .{ "pk", .pakistan },
    .{ "pw", .palau },
    .{ "ps", .palestine_state_of },
    .{ "pa", .panama },
    .{ "pg", .papua_new_guinea },
    .{ "py", .paraguay },
    .{ "pe", .peru },
    .{ "ph", .philippines_the },
    .{ "pn", .pitcairn },
    .{ "pl", .poland },
    .{ "pt", .portugal },
    .{ "pr", .puerto_rico },
    .{ "qa", .qatar },
    .{ "re", .reunion },
    .{ "ro", .romania },
    .{ "ru", .russian_federation_the },
    .{ "rw", .rwanda },
    .{ "bl", .saint_barthelemy },
    .{ "sh", .saint_helena_ascension_island_and_tristan_da_cunha },
    .{ "kn", .saint_kitts_and_nevis },
    .{ "lc", .saint_lucia },
    .{ "mf", .saint_martin_french_part },
    .{ "pm", .saint_pierre_and_miquelon },
    .{ "vc", .saint_vincent_and_the_grenadines },
    .{ "ws", .samoa },
    .{ "sm", .san_marino },
    .{ "st", .sao_tome_and_principe },
    .{ "sa", .saudi_arabia },
    .{ "sn", .senegal },
    .{ "rs", .serbia },
    .{ "sc", .seychelles },
    .{ "sl", .sierra_leone },
    .{ "sg", .singapore },
    .{ "sx", .sint_maarten_dutch_part },
    .{ "sk", .slovakia },
    .{ "si", .slovenia },
    .{ "sb", .solomon_islands },
    .{ "so", .somalia },
    .{ "za", .south_africa },
    .{ "gs", .south_georgia_and_the_south_sandwich_islands },
    .{ "ss", .south_sudan },
    .{ "es", .spain },
    .{ "lk", .sri_lanka },
    .{ "sd", .sudan_the },
    .{ "sr", .suriname },
    .{ "sj", .svalbard_and_jan_mayen },
    .{ "se", .sweden },
    .{ "ch", .switzerland },
    .{ "sy", .syrian_arab_republic_the },
    .{ "tw", .taiwan_province_of_china },
    .{ "tj", .tajikistan },
    .{ "tz", .tanzania_the_united_republic_of },
    .{ "th", .thailand },
    .{ "tl", .timor_leste },
    .{ "tg", .togo },
    .{ "tk", .tokelau },
    .{ "to", .tonga },
    .{ "tt", .trinidad_and_tobago },
    .{ "tn", .tunisia },
    .{ "tr", .turkiye },
    .{ "tm", .turkmenistan },
    .{ "tc", .turks_and_caicos_islands_the },
    .{ "tv", .tuvalu },
    .{ "ug", .uganda },
    .{ "ua", .ukraine },
    .{ "ae", .united_arab_emirates_the },
    .{ "gb", .united_kingdom_of_great_britain_and_northern_ireland_the },
    .{ "um", .united_states_minor_outlying_islands_the },
    .{ "us", .united_states_of_america_the },
    .{ "uy", .uruguay },
    .{ "uz", .uzbekistan },
    .{ "vu", .vanuatu },
    .{ "ve", .venezuela_bolivarian_republic_of },
    .{ "vn", .viet_nam },
    .{ "vg", .virgin_islands_british },
    .{ "vi", .virgin_islands_us },
    .{ "wf", .wallis_and_futuna },
    .{ "eh", .western_sahara },
    .{ "ye", .yemen },
    .{ "zm", .zambia },
    .{ "zw", .zimbabwe },
};
