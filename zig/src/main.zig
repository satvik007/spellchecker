const std = @import("std");
const mem = std.mem;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const os = std.os;

pub fn main() !void {
    var general_purpose_allocator = GeneralPurposeAllocator(.{}){};
    const gpa = general_purpose_allocator.allocator();
    defer _ =
        general_purpose_allocator.deinit();

    const words = try read_file_and_process_words(gpa);
    defer deinitKeysAndMap(gpa, words);

    std.debug.print("words.count: {}\n", .{words.count()});
}

const HashMap = std.StringHashMap;

fn read_file_and_process_words(allocator: mem.Allocator) !*HashMap(u32) {
    const file = try os.open("../common/big.txt", std.os.O.RDONLY, 0);
    defer std.os.close(file);

    const file_stat = try std.os.fstat(file);
    const file_size: usize = @intCast(file_stat.size);

    // convert file_size to usize
    const file_contents = try allocator.alloc(u8, file_size);
    defer allocator.free(file_contents);

    const read_size = try os.read(file, file_contents);
    if (read_size != file_size) {
        std.log.warn("Failed to read entire file\n", .{});
    }

    const map = try process_words(allocator, file_contents[0..]);

    std.debug.print("words.count: {}\n", .{map.count()});

    return map;
}

fn process_words(allocator: mem.Allocator, input: []const u8) !*HashMap(u32) {
    var map = HashMap(u32).init(allocator);

    var buffer: [1024]u8 = undefined;
    var word_idx: usize = 0;

    for (input) |c| {
        if (c >= 'a' and c <= 'z') {
            buffer[word_idx] = c;
            word_idx += 1;
        } else if (c >= 'A' and c <= 'Z') {
            buffer[word_idx] = c + ('a' - 'A');
            word_idx += 1;
        } else {
            if (word_idx > 0) {
                const key = buffer[0..word_idx];

                if (map.getPtr(key)) |entry| {
                    entry.* += 1;
                } else {
                    const word = try allocator.dupe(u8, key);
                    try map.putNoClobber(word, 1);
                }
                word_idx = 0;
            }
        }

        if (word_idx == 1024) {
            std.debug.print("word: {s}\n", .{buffer});
        }
    }

    std.debug.print("map.count: {}\n", .{map.count()});

    return &map;
}

fn deinitKeysAndMap(allocator: mem.Allocator, map: *HashMap(u32)) void {
    var it = map.keyIterator();
    while (it.next()) |key_ptr| {
        allocator.free(key_ptr.*);
    }
    map.deinit();
}
