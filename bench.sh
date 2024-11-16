set -xe
args="std_static_string_map this_static_string_map this_static_string_map2 squeek502_hand_rolled"
build_args=-Dbench-file=src/bench2.zig
# zig build bench $build_args -- $args
# zig build bench -Doptimize=ReleaseSafe $build_args -- $args
# zig build bench -Doptimize=ReleaseSmall $build_args -- $args
zig build bench -Doptimize=ReleaseFast $build_args -- $args

