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
        if (map.getKey(word)) |key| {
            try set.put(key, void{});
        }
    }

    var result: [][]const u8 = try allocator.alloc([]const u8, set.count());

    var idx: usize = 0;

    for (set.keys()) |key| {
        result[idx] = key;
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
    defer {
        for (ed1) |e1| {
            allocator.free(e1);
        }
        allocator.free(ed1);
    }
    const e1 = try known(allocator, map, ed1);
    if (e1.len > 0) {
        return e1;
    }

    const ed2 = try edits2(allocator, word);
    defer {
        for (ed2) |e2| {
            allocator.free(e2);
        }
        allocator.free(ed2);
    }
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
    try result.ensureTotalCapacity((word_len+1) * 54);

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

    return result.toOwnedSlice();
}

fn edits2(allocator: mem.Allocator, word: []const u8) ![][]const u8 {
    var result: std.ArrayList([]const u8) = std.ArrayList([]const u8).init(allocator);
    try result.ensureTotalCapacity(54 * 54 * (word.len + 1) * (word.len + 1));

    const ed1 = try edits1(allocator, word);
    defer {
        for (ed1) |e1| {
            allocator.free(e1);
        }

        allocator.free(ed1);
    }

    for (ed1) |e1| {
        const ed2 = try edits1(allocator, e1);
        try result.appendSlice(ed2);
        allocator.free(ed2);
    }

    return result.toOwnedSlice();
}

fn correction(allocator: mem.Allocator, map: *const HashMap(u32), word: []const u8) ![]const u8 {
    const cd = try candidates(allocator, map, word);
    defer {
        allocator.free(cd);
    }

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

fn read_test_file(allocator: mem.Allocator, file_name: []const u8) ![][2][]const u8 {
    const file = try os.open(file_name, std.os.O.RDONLY, 0);
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

    var result: std.ArrayList([2][]const u8) = std.ArrayList([2][]const u8).init(allocator);
    defer result.deinit();

    var buffer: [1024]u8 = undefined;
    var word_idx: usize = 0;

    var correct_word: [1024]u8 = undefined;
    var correct_len: usize = 0;

    for (file_contents) |c| {
        if (c >= 'a' and c <= 'z') {
            buffer[word_idx] = c;
            word_idx += 1;
        } else if (c == ':') {
            std.mem.copyForwards(u8, correct_word[0..word_idx], buffer[0..word_idx]);
            correct_len = word_idx;
            word_idx = 0;
        } else if (c == ' ' or c == '\n') {
            if (word_idx > 0) {
                const wrong_word = buffer[0..word_idx];
                const entry = try allocator.create([2][]const u8);
                entry[0] = try allocator.dupe(u8, correct_word[0..correct_len]);
                entry[1] = try allocator.dupe(u8, wrong_word);

                try result.append(entry.*);
            }
            word_idx = 0;
        }
    }

    return result.toOwnedSlice();
}

fn run_test_set(test_set: [][2][]const u8, map: *const HashMap(u32)) !void {
    const start = std.time.timestamp();
    var good: u32 = 0;
    var unknown: u32 = 0;
    const n = test_set.len;

    for (test_set) |item| {
        const right = item[0];
        const wrong = item[1];

        const w = try correction(std.testing.allocator, map, wrong);
        if (std.mem.eql(u8, w, right)) {
            good += 1;
        } else {
            if (!map.contains(right)) {
                std.debug.print("Unknown: {s}\n", .{right});
                unknown += 1;
            }
        }
    }

    const dt = std.time.timestamp() - start;
    std.debug.print("{d}% of {d} correct ({d}% unknown) at {d} words per second\n", .{
        (@as(f64, @floatFromInt(good)) * 100.0) / @as(f64, @floatFromInt(n)),
        n,
        @as(f64, @floatFromInt(unknown)) * 100.0 / @as(f64, @floatFromInt(n)),
        @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(dt)),
    });
}

test "spellchecker" {
    var generalPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = generalPurposeAllocator.allocator();
    defer _ = generalPurposeAllocator.deinit();

    var words = HashMap(u32).init(gpa);
    try read_file_and_process_words(gpa, &words);
    defer deinitKeysAndMap(gpa, &words);

    assert(words.count() == 29157);

    const incorrect: [9][]const u8 = [_][]const u8{
        "speling",
        "korrectud",
        "bycycle",
        "inconvient",
        "arrainged",
        "peotry",
        "peotryy",
        "word",
        "quintessential",
    };

    const correct: [9][]const u8 = [_][]const u8{
        "spelling",
        "corrected",
        "bicycle",
        "inconvenient",
        "arranged",
        "poetry",
        "poetry",
        "word",
        "quintessential",
    };

    for (correct, incorrect) |c, i| {
        const corr = try correction(gpa, &words, i);
        assert(std.mem.eql(u8, corr, c));
        gpa.free(corr);
    }
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

test "test_sets" {
    var generalPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = generalPurposeAllocator.allocator();
    defer _ = generalPurposeAllocator.deinit();

    var words = HashMap(u32).init(gpa);
    try read_file_and_process_words(gpa, &words);
    defer deinitKeysAndMap(gpa, &words);

    assert(words.count() == 29157);

    const test_set_1 = try read_test_file(gpa, "../common/spell-testset1.txt");
    try run_test_set(test_set_1, &words);
    defer {
        for (test_set_1) |item| {
            gpa.free(item[0]);
            gpa.free(item[1]);
            gpa.destroy(&item);
        }
        gpa.free(test_set_1);
    }
    // 74.81481481481481% of 270 correct (5.555555555555555% unknown) at 135 words per second

    const test_set_2 = try read_test_file(gpa, "../common/spell-testset2.txt");
    try run_test_set(test_set_2, &words);
    defer {
        for (test_set_2) |item| {
            gpa.free(item[0]);
            gpa.free(item[1]);
            gpa.destroy(&item);
        }
        gpa.free(test_set_2);
    }
    // 67.5% of 400 correct (10.75% unknown) at 100 words per second
}
