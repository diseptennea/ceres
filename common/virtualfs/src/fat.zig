//! Implements FAT family of file systems.

pub inline fn FatFileSystem(
    comptime Context: type,
    comptime ReadError: type,
    comptime WriteError: type,
    comptime SeekError: type,
    comptime readFn: fn (context: Context, buffer: []u8) ReadError!usize,
    comptime writeFn: fn (context: Context, bytes: []const u8) WriteError!usize,
    comptime seekFn: fn (context: Context, whence: ?SeekWhence) SeekError!usize,
) type {
    const std = @import("std");
    const Reader = std.io.GenericReader(Context, ReadError, readFn);
    const Writer = std.io.Writer(Context, WriteError, writeFn);
    _ = Reader;
    _ = Writer;

    return struct {
        context: Context,

        pub const IoError = ReadError || WriteError || SeekError;
        pub const FsError = error{
            InvalidBootCodeSize,
            InvalidBytesPerSector,
            InvalidSectorsPerCluster,
            InvalidTotalClustersCount,
        };
        pub const Error = IoError || FsError;

        pub const FatFormatConfig = struct {
            const MAX_CLUSTERS: usize = 268435445;

            /// Total number of clusters.
            total_clusters: u32,

            /// LBA of the starting volume.
            number_of_hidden_sectors: u32 = 0,

            /// Bytes per sector.
            bytes_per_sector: u16 = 512,

            /// Sectors per cluster.
            sectors_per_cluster: u8 = 1,

            /// Bootcode
            boot_code: ?[]const u8 = null,

            pub inline fn check(self: FatFormatConfig) FsError!void {
                if (self.total_clusters < 1 or self.total_clusters > MAX_CLUSTERS)
                    return error.InvalidTotalClustersCount;
                if (self.bytes_per_sector < 512 or !std.math.isPowerOfTwo(self.bytes_per_sector))
                    return error.InvalidBytesPerSector;
                if (self.sectors_per_cluster < 1)
                    return error.InvalidSectorsPerCluster;
            }
        };

        /// Formats the given device with the given configuration.
        pub fn formatWithConfig(self: Self, config: FatFormatConfig) Error!void {
            // TODO Add sanity checks
            return switch (config.total_clusters) {
                0...4085 => try self.formatForFat12(config),
                4086...65525 => try self.formatForFat16(config),
                _ => try self.formatForFat32(config),
            };
        }

        /// Formats the given device for FAT12.
        fn formatForFat12(self: Self, config: FatFormatConfig) Error!void {
            const BOOTCODE_SIZE = 448;

            try config.check();
            try self.seek(.{ .beginning = config.bytes_per_sector * config.number_of_hidden_sectors });

            const jmp_code = jmp_code: {
                const JMP_CODE_BOOTABLE = [3]u8{ 0xEB, 0x3C, 0x90 };
                const JMP_CODE_NONBOOT = [3]u8{ 0xEB, 0xFE, 0x90 };
                break :jmp_code if (config.boot_code) JMP_CODE_BOOTABLE else JMP_CODE_NONBOOT;
            };

            const n_reserved_sectors = n_reserved_sectors: {
                // If there is no bootcode, there is no need to reserve extra sectors.
                const boot_code = config.boot_code orelse break :n_reserved_sectors 1;

                // Reserve sectors until the whole bootcode can be stored in them.
                var n_current_reserved: usize = 1;
                var cb_current_scanned: usize = BOOTCODE_SIZE + 2; // 2 for signature.
                while (cb_current_scanned < boot_code.len) : (n_current_reserved += 1) {
                    cb_current_scanned += config.bytes_per_sector;
                }

                break :n_reserved_sectors n_current_reserved;
            };

            const n_root_dirent = n_root_dirent: {};

            const bpb = BPB{
                .jmp_code = jmp_code,
                .oem_identifier = [8]u8{"MSWIN4.1"},
                .bytes_per_sector = config.bytes_per_sector,
                .sectors_per_cluster = config.sectors_per_cluster,
                .reserved_sectors = n_reserved_sectors,
                .number_of_fats = 2,
            };
            _ = bpb;
        }

        fn seek(self: Self, whence: SeekWhence) SeekError!void {
            _ = try seekFn(self.context, whence);
        }

        fn tell(self: Self) SeekError!usize {
            return try seekFn(self.context, null);
        }

        const Self = @This();
    };
}

/// **BIOS Parameter Block**: The boot record (the first sector of the volume)
/// contains both code and data mixed together, the non-code portion being the
/// BPB. Note that the values shall be encoded in little-endian convention, keep
/// in mind.
const BPB = packed struct {
    /// This encodes a `jmp` instruction in x86, which should jump directly to
    /// the bootloader code located inside the bootsector, skipping disk format
    /// information. The bootsector is always loaded into RAM at location
    /// `0x0000:0x7C00` by the BIOS, without this jump, the CPU would attempt to
    /// execute data that isn't code. Major OSes do check whether the first byte
    /// of this field to be `0xE9` or `0xEB`, keep in mind while implementing a
    /// FAT file system driver.
    ///
    /// The content of this field can be set according to bootability:
    /// - `EB 3C 90`: Disassembles to `JMP SHORT 3C NOP`, which jumps to the
    ///     bootloader code inside the bootsector. The 3C can change accordingly.
    /// - `EB FE 90`: Disassembles to an infinite loop, useful for non-bootable
    ///     volumes.
    ///
    /// The recommended formats are: `EB __ 90` and `E9 __ __`.
    jmp_code: [3]u8 = .{ 0xEB, 0xFE, 0x90 },

    /// OEM identifier. The official FAT specification says this field is not
    /// very meaningful, and is not checked by MS FAT drivers. Nonetheless, the
    /// recommended value for this field is `MSWIN4.1`. If the string is less
    /// than 8 characters, pad with spaces.
    oem_identifier: [8]u8 = @as([8]u8, "MSWIN4.1"),

    /// Bytes per sector. The default value is 512 bytes, which is standard.
    /// Recommended values are 512, 1024, 2048, 4096. These values are properly
    /// handled by the MS FAT drivers, but opt for 512 for maximum compatibility
    /// with other FAT FS implementations.
    bytes_per_sector: u16 = 512,

    /// Sectors per cluster. The smallest unit of allocation in FAT file systems
    /// is a cluster. Another good alternative default value is 8 sectors/cluster,
    /// which corresponds to 4K per cluster, matching default page size of the most
    /// common flash storages (assuming 512 b/sector).
    ///
    /// Note: The value must be a power of 2. Keep the cluster size 32KiB or less for
    /// compatibility with older systems.
    sectors_per_cluster: u8 = 8,

    /// Number of reserved sectors. Note that the boot sectors are included in this
    /// number. Default is 1, which corresponds to a boot sector of 512 bytes, assuming
    /// 512 bytes per sector. Change accordingly if the boot code needs more sectors
    /// to be reserved. Use 1 sectors for maximum compatibility with older FAT12/16
    /// drivers. The typical for FAT32 is 32. This field must be positive.
    reserved_sectors: u16 = 32,

    /// Number of FATs (file allocation tables) on the storage media. 2 FATs are recommended.
    number_of_fats: u8 = 2,

    /// Number of root directory entries. Required to be set in a way that ensures the
    /// root directory is aligned to the 2-sector boundary, `number_of_root_dirents * 32`
    /// becomes a multiple of `bytes_per_sector`. For maximum compatibility, set this
    /// field to 512 for FAT12/16, and 0 for FAT32.
    number_of_root_dirents: u16 = 0,

    /// The total sectors in the logical volume. If 0, there are 65536+ sectors in the
    /// volume, and the actual number is stored in the large sector count. For FAT32, this
    /// field must be 0 regardless of the total sector count.
    total_sectors_small: u16 = 0,

    /// Media descriptor type. The valid values for this field is 0xF0, 0xF8, 0xF9, 0xFA,
    /// 0xFB, 0xFC, 0xFD, 0xFE and 0xFF. 0xF8 is the standard value for non-removable
    /// disks and 0xF0 is often used for non partitioned removable disks. Other
    /// important point is that the same value must be put in the lower 8-bits of FAT[0].
    /// This comes from the media determination of MS-DOS Ver.1 and never used for any
    /// purpose any longer.
    media_descriptor: u8 = 0xF8,

    /// Number of sectors per FAT. For FAT12 and FAT16 only. For FAT32, set to 0. The
    /// `sectors_per_fat_large` is used in case of FAT32.
    sectors_per_fat_small: u16 = 0,

    /// Number of sectors per track. This field is relevant only for media that have
    /// geometry and used for only disk BIOS of IBM PC.
    sectors_per_track: u16 = 0,

    /// Number of heads/sides on the storage media. This field is relevant only for
    /// media that have geometry and used for only disk BIOS of IBM PC.
    number_of_heads: u16 = 0,

    /// Number of hidden physical sectors preceding the FAT volume. It is generally
    /// related to storage accessed by disk BIOS of IBM PC, and what kind of value
    /// is set is platform dependent. This field should always be 0 if the volume
    /// starts at the beginning of the storage, e.g. non-partitioned disks, such
    /// as floppy disk.
    number_of_hidden_sectors: u32 = 0,

    /// Large sector count. Set only when the total sector count > 65535.
    total_sectors_large: u32 = 0,
};

/// Extended BPB for FAT12/16. The EBPB is placed right next to the BPB.
/// The layout of the EBPB is dependent on the FAT variant. Use EBPB32 for
/// FAT32.
const EBPB1216 = packed struct {
    /// Drive number used by disk BIOS of IBM PC. This field is used in
    /// MS-DOS bootstrap, 0x00 for floppy disk and 0x80 for fixed disk.
    /// Actually it depends on the OS. The value here should be identical
    /// to the value returned by BIOS interrupt 0x13, or passed in the DL
    /// register; i.e. 0x00 for a floppy disk and 0x80 for hard disks.
    /// This number is useless because the media is likely to be moved to
    /// another machine and inserted in a drive with a different drive
    /// number.
    drive_number: u8 = 0x80,

    /// Flags used by Windows(R) NT. Reserved.
    nt_flags: u8 = 0x00,

    /// Extended boot signature. This is a signature byte indicates that
    /// the following three fields are present.
    signature: u8 = 0x29,

    /// VolumeID 'Serial' number. Used for tracking volumes between
    /// computers. You can ignore this if you want.
    serial_number: u32,

    /// Volume label string. This field is padded with spaces. This field
    /// is the 11-byte volume label and it matches volume label recorded
    /// in the root directory. FAT driver should update this field when
    /// the volume label in the root directory is changed. MS-DOS does it,
    /// but Windows does not do it. When volume label is not present,
    /// "NO NAME " should be set in this field.
    volume_label: [11]u8 = @as([11]u8, "NO NAME    "),

    /// "FAT12   ", "FAT16   " or "FAT     ". Many people think that this
    /// string has some effect in determination of the FAT type, but it
    /// is clearly a misrecognization. From the name of this field, you
    /// will find that this is not a part of BPB. Since this string is
    /// often incorrect or not set, Microsoft's FAT driver does not use
    /// this field to determine the FAT type. However, some old FAT drivers
    /// use this string to determine the FAT type, so that it should be
    /// set based on the FAT type of the volume to avoid compatibility
    /// problems.
    file_system_type: [8]u8 = @as([8]u8, "FAT     "),

    /// Bootstrap program. It is platform dependent and filled with zero
    /// when not used.
    bootcode: [448]u8 = [_]u8{0} ** 448,

    /// `0xAA55` if this is a valid boot sector.
    bootsign: u16 = 0x0000,
};

pub const SeekWhence = union(enum) {
    /// From the first byte of the whole device/volume.
    beginning: usize,
    /// From the current position.
    relative: isize,
    /// From the end of the whole volume, negated.
    ending: usize,
};
