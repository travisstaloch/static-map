set -xe
args="std_static_string_map static_map static_map_case_insensitive squeek502_hand_rolled"
build_args=-Dbench-file=src/bench2.zig
# zig build bench $build_args -- $args
# zig build bench -Doptimize=ReleaseSafe $build_args -- $args
# zig build bench -Doptimize=ReleaseSmall $build_args -- $args
zig build bench -Doptimize=ReleaseFast $build_args -- $args


zig build -Doptimize=ReleaseFast -Dbench-file=src/bench2.zig
poop -d 1000 'zig-out/bin/bench std_static_string_map' 'zig-out/bin/bench static_map' 'zig-out/bin/bench squeek502_hand_rolled' 'zig-out/bin/bench static_map_case_insensitive'