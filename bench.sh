# set -xe
args="std_static_string_map this_static_string_map this_static_string_map2"
# zig build bench -- $args
# zig build bench -Doptimize=ReleaseSafe -- $args
# zig build bench -Doptimize=ReleaseSmall -- $args
zig build bench -Doptimize=ReleaseFast -- $args

