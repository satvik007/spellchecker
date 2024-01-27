const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const os = std.os;

const HashMap = std.StringHashMap;

pub fn main() !void {}

fn read_file_and_process_words(allocator: mem.Allocator, map: *HashMap(u32)) !void {
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

    try process_words(allocator, file_contents[0..], map);

    std.debug.print("words.count: {}\n", .{map.count()});
}

fn process_words(allocator: mem.Allocator, input: []const u8, map: *HashMap(u32)) !void {
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
}

fn deinitKeysAndMap(allocator: mem.Allocator, map: *HashMap(u32)) void {
    var it = map.keyIterator();
    while (it.next()) |key_ptr| {
        allocator.free(key_ptr.*);
    }
    map.deinit();
}

fn known(allocator: mem.Allocator, map: *const HashMap(u32), words: []const []const u8) ![][]const u8 {
    var set: std.StringArrayHashMap(void) = std.StringArrayHashMap(void).init(allocator);
    defer set.deinit();

    for (words) |word| {
        if (map.contains(word)) {
            try set.put(word, void{});
        }
    }

    var result: [][]const u8 = try allocator.alloc([]const u8, set.count());

    var idx: usize = 0;

    for (set.keys()) |key| {
        const word = try allocator.dupe(u8, key);
        result[idx] = word;
        idx += 1;
    }

    return result;
}

fn candidates(allocator: mem.Allocator, map: *const HashMap(u32), word: []const u8) ![][]const u8 {
    if (map.contains(word)) {
        const result = try allocator.alloc([]const u8, 1);
        result[0] = word;
        return result;
    }

    const ed1 = try edits1(allocator, word);
    defer allocator.free(ed1);
    const e1 = try known(allocator, map, ed1);
    if (e1.len > 0) {
        return e1;
    }

    const ed2 = try edits2(allocator, word);
    defer allocator.free(ed2);
    const e2 = try known(allocator, map, ed2);
    if (e2.len > 0) {
        return e2;
    }

    const result = try allocator.alloc([]const u8, 1);
    result[0] = word;
    return result;
}

fn edits1(allocator: mem.Allocator, word: []const u8) ![][]const u8 {
    var result: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(allocator);

    const word_len = word.len;

    for (0..word_len + 1) |i| {
        const word_prefix = word[0..i];
        const word_suffix = word[i..];

        // deletes = [L + R[1:]               for L, R in splits if R]
        if (word_suffix.len > 0) {
            const delete = try allocator.alloc(u8, word_len - 1);

            mem.copyForwards(u8, delete[0..i], word_prefix);
            mem.copyForwards(u8, delete[i..], word_suffix[1..]);

            try result.append(delete);
        }

        // transposes = [L + R[1] + R[0] + R[2:] for L, R in splits if len(R)>1]
        if (word_suffix.len > 1) {
            const transpose = try allocator.alloc(u8, word_len);

            mem.copyForwards(u8, transpose[0..i], word_prefix);
            transpose[i] = word_suffix[1];
            transpose[i + 1] = word_suffix[0];
            mem.copyForwards(u8, transpose[i + 2 ..], word_suffix[2..]);

            try result.append(transpose);
        }

        // replaces  = [L + c + R[1:]           for L, R in splits if R for c in letters]
        if (word_suffix.len > 0) {
            for ('a'..'z') |c| {
                const replace = try allocator.alloc(u8, word_len);

                mem.copyForwards(u8, replace[0..i], word_prefix);
                replace[i] = @intCast(c);
                mem.copyForwards(u8, replace[i + 1 ..], word_suffix[1..]);

                try result.append(replace);
            }
        }

        // inserts   = [L + c + R               for L, R in splits for c in letters]
        for ('a'..'z') |c| {
            const insert = try allocator.alloc(u8, word_len + 1);

            mem.copyForwards(u8, insert[0..i], word_prefix);
            insert[i] = @intCast(c);
            mem.copyForwards(u8, insert[i + 1 ..], word_suffix);

            try result.append(insert);
        }
    }

    return result.items;
}

fn edits2(allocator: mem.Allocator, word: []const u8) ![][]const u8 {
    var result: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(allocator);

    const e1r = try edits1(allocator, word);
    defer allocator.free(e1r);

    for (e1r) |e1| {
        for (try edits1(allocator, e1)) |e2| {
            try result.append(e2);
        }
    }

    return result.items;
}

fn correction(allocator: mem.Allocator, map: *const HashMap(u32), word: []const u8) ![]const u8 {
    const cd = try candidates(allocator, map, word);
    defer allocator.free(cd);

    if (cd.len == 1) {
        return allocator.dupe(u8, cd[0]);
    }

    var max_key: []const u8 = undefined;
    var max_value: u32 = 0;

    for (cd) |key| {
        const can_val = map.get(key).?;
        if (can_val > max_value) {
            max_value = can_val;
            max_key = key;
        }
    }

    return allocator.dupe(u8, max_key);
}

test "spellchecker" {
    var generalPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = generalPurposeAllocator.allocator();
    defer _ = generalPurposeAllocator.deinit();

    var words = HashMap(u32).init(gpa);
    try read_file_and_process_words(gpa, &words);
    defer deinitKeysAndMap(gpa, &words);

    assert(words.count() == 29157);

    assert(std.mem.eql(u8, try correction(gpa, &words, "speling"), "spelling"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "korrectud"), "corrected"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "bycycle"), "bicycle"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "inconvient"), "inconvenient"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "arrainged"), "arranged"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "peotry"), "poetry"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "peotry"), "poetry"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "word"), "word"));
    assert(std.mem.eql(u8, try correction(gpa, &words, "quintessential"), "quintessential"));
}

test "process_words" {
    var generalPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = generalPurposeAllocator.allocator();
    defer _ = generalPurposeAllocator.deinit();

    var words = HashMap(u32).init(gpa);
    try process_words(gpa, "This is a TEST.", &words);
    defer deinitKeysAndMap(gpa, &words);

    var vec: [4][]const u8 = undefined;
    var idx: usize = 0;
    var it = words.keyIterator();
    while (it.next()) |ptr| {
        vec[idx] = ptr.*;
        idx += 1;
    }

    std.sort.insertion([]const u8, &vec, .{}, cmpStr);

    assert(idx == 4);
    assert(std.mem.eql(u8, vec[0], "a"));
    assert(std.mem.eql(u8, vec[1], "is"));
    assert(std.mem.eql(u8, vec[2], "test"));
    assert(std.mem.eql(u8, vec[3], "this"));

    var words2 = HashMap(u32).init(gpa);
    try process_words(gpa, "This is a test. 123; A TEST this is.", &words2);
    defer deinitKeysAndMap(gpa, &words2);

    assert(words2.count() == 4);
    assert(words2.get("a").? == 2);
    assert(words2.get("is").? == 2);
    assert(words2.get("test").? == 2);
    assert(words2.get("this").? == 2);
}

fn cmpStr(_x: @TypeOf(.{}), a: []const u8, b: []const u8) bool {
    _ = _x;
    var i: usize = 0;

    while (i < @min(a.len, b.len)) {
        if (a[i] < b[i]) {
            return true;
        } else if (a[i] > b[i]) {
            return false;
        }

        i += 1;
    }

    return a.len <= b.len;
}
