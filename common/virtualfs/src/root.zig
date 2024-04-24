const std = @import("std");
const testing = std.testing;
const fat = @import("./fat.zig");

pub const SeekWhence = union(enum) {
    /// From the first byte of the whole device/volume.
    beginning: usize,
    /// From the current position.
    relative: isize,
    /// From the end of the whole volume, negated.
    ending: usize,
};
