/// Implementing https://norvig.com/spell-correct.html in rust
/// Author: Satvik Choudhary
/// Date: 2024-01-27
///
/// Run with `cargo test --release` to see the results of the tests.

use std::collections::{HashMap, HashSet};
use std::fs;
use regex::Regex;

fn read_file_and_process_words() -> HashMap<String, u32> {
    let input = fs::read_to_string("big.txt").expect("File big.txt is not in current directory.");

    process_words(&input)
}

fn process_words(input: &str) -> HashMap<String, u32> {
    let mut map: HashMap<String, u32> = HashMap::new();

    let re = Regex::new(r"[a-z]+").unwrap();
    re.find_iter(input.to_lowercase().as_str()).
        for_each(|m| {
            let count = map.entry(m.as_str().to_string()).or_insert(0);
            *count += 1;
        });

    map
}

fn read_test_file(file_name: &str) -> Vec<(String, String)> {
    let input = fs::read_to_string(file_name).expect(&format!("File {file_name} is not in current directory."));

    input
        .lines()
        .flat_map(|line| {
            let mut split = line.split(": ");
            let first = split.next().unwrap();
            let second = split.next().unwrap();

            second.split_whitespace()
                .map(move |word| (first.to_string(), word.to_string()))
        })
        .collect()
}

fn run_test_set(test_set: Vec<(String, String)>, words: &HashMap<String, u32>, verbose: bool) {
    let start = std::time::Instant::now();
    let mut good = 0;
    let mut unknown = 0;
    let n = test_set.len();

    for (right, wrong) in test_set {
        let w = words.correction(&wrong);
        if w == right {
            good += 1;
        } else {
            if !words.contains_key(&right) {
                unknown += 1;
            }
            if verbose {
                println!("correction({}) => {} ({}); expected {} ({})", wrong, w, words.get(&w).unwrap_or(&0), right, words.get(&right).unwrap_or(&0));
            }
        }
    }

    let dt = start.elapsed().as_secs_f64();
    println!("{:.0}% of {} correct ({:.0}% unknown) at {:.0} words per second", (good as f64 * 100.0) / n as f64, n, (unknown as f64 * 100.0) / n as f64, n as f64 / dt);
}

trait Counter {
    fn max(&self) -> (String, u32);
    fn most_common(&self, num: usize) -> Vec<(String, u32)>;
}

impl Counter for HashMap<String, u32> {
    fn max(&self) -> (String, u32) {
        let mut max_value = 0;
        let mut max_key = String::new();

        for (key, value) in self.iter() {
            if *value > max_value {
                max_value = *value;
                max_key = key.to_string();
            }
        }

        (max_key, max_value)
    }

    fn most_common(&self, num: usize) -> Vec<(String, u32)> {
        let mut vec: Vec<(String, u32)> = self.iter().map(|(k, v)| (k.to_string(), *v)).collect();
        vec.sort_by(|a, b| b.1.cmp(&a.1));
        vec.truncate(num);
        vec
    }
}

fn edits1(word: &str) -> Vec<String> {
    let letters = "abcdefghijklmnopqrstuvwxyz";

    // splits     = [(word[:i], word[i:])    for i in range(len(word) + 1)]
    let splits = (0..word.len() + 1)
        .map(|i| (word[..i].to_string(), word[i..].to_string()));

    // deletes    = [L + R[1:]               for L, R in splits if R]
    let deletes: Vec<String> = splits
        .clone()
        .filter(|(_, r)| r.len() > 0)
        .map(|(l, r)| l + &r[1..])
        .collect();

    // transposes = [L + R[1] + R[0] + R[2:] for L, R in splits if len(R)>1]
    let transposes: Vec<String> = splits
        .clone()
        .filter(|(_, r)| r.len() > 1)
        .map(|(l, r)| l + &r[1..2] + &r[0..1] + &r[2..])
        .collect();

    // replaces   = [L + c + R[1:]           for L, R in splits if R for c in letters]
    let replaces: Vec<String> = splits
        .clone()
        .filter(|(_, r)| r.len() > 0)
        .flat_map(|(l, r)| letters.chars().map(move |c| l.clone() + &c.to_string() + &r[1..]))
        .collect();

    // inserts    = [L + c + R               for L, R in splits for c in letters]
    let inserts: Vec<String> = splits
        .flat_map(|(l, r)| letters.chars().map(move |c| l.clone() + &c.to_string() + &r))
        .collect();

    let mut vec = Vec::new();
    vec.extend(deletes);
    vec.extend(transposes);
    vec.extend(replaces);
    vec.extend(inserts);

    vec
}

fn edits2(word: &str) -> Vec<String> {
    edits1(word)
        .iter()
        .flat_map(|x| edits1(x))
        .collect()
}

trait SpellChecker {
    fn p(&self, word: &str) -> f64;
    fn known(&self, words: Vec<String>) -> Vec<String>;
    fn candidates(&self, word: &str) -> Vec<String>;
    fn correction(&self, word: &str) -> String;
}

impl SpellChecker for HashMap<String, u32> {
    fn p(&self, word: &str) -> f64 {
        let n = self.values().sum::<u32>() as f64;
        let count = self.get(word).unwrap_or(&0);
        (*count as f64) / n
    }

    fn known(&self, words: Vec<String>) -> Vec<String> {
        words
            .into_iter()
            .filter(|word| self.contains_key(word))
            .collect::<HashSet<_>>()
            .into_iter()
            .collect()
    }

    fn candidates(&self, word: &str) -> Vec<String> {
        if self.contains_key(word) {
            return vec![word.to_string()];
        }

        let e1 = self.known(edits1(word));
        if e1.len() > 0 {
            return e1;
        }

        let e2 = self.known(edits2(word));
        if e2.len() > 0 {
            return e2;
        }

        vec![word.to_string()]
    }

    fn correction(&self, word: &str) -> String {
        let candidates = self.candidates(word);
        if candidates.len() == 1 {
            return candidates[0].to_string();
        }

        let mut max_key = String::new();
        let mut max_value = 0;

        for key in candidates.iter() {
            let can_val = self.get(key).unwrap();

            if *can_val > max_value {
                max_value = *can_val;
                max_key = key.to_string();
            }
        }

        max_key
    }
}

fn main() {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_spellchecker() {
        let words = read_file_and_process_words();

        assert_eq!(29157, words.len());
        assert_eq!((String::from("the"), 80030), words.max());
        assert_eq!(0.0, words.p("quintessential"));

        let the = words.p("the");
        assert!(0.07 <= the && the <= 0.08);

        assert_eq!(Vec::from([
            (String::from("the"), 80030),
            (String::from("of"), 40025),
            (String::from("and"), 38313),
            (String::from("to"), 28766),
            (String::from("in"), 22050),
            (String::from("a"), 21155),
            (String::from("that"), 12512),
            (String::from("he"), 12401),
            (String::from("was"), 11410),
            (String::from("it"), 10681),
        ]), words.most_common(10));

        assert_eq!("spelling", words.correction("speling"));        // insert
        assert_eq!("corrected", words.correction("korrectud"));     // replace 2
        assert_eq!("bicycle", words.correction("bycycle"));         // replace
        assert_eq!("inconvenient", words.correction("inconvient")); // insert 2
        assert_eq!("arranged", words.correction("arrainged"));      // delete
        assert_eq!("poetry", words.correction("peotry"));           // transpose
        assert_eq!("poetry", words.correction("peotry"));           // transpose + delete
        assert_eq!("word", words.correction("word"));               // known
        assert_eq!("quintessential", words.correction("quintessential")) // unknown
    }

    #[test]
    fn test_process() {
        let words = process_words("This is a TEST.");

        let mut vec = words
            .keys()
            .into_iter()
            .collect::<Vec<_>>();
        vec.sort_by(|a, b| a.cmp(b));
        assert_eq!(vec!["a", "is", "test", "this"], vec);

        let words = process_words("This is a test. 123; A TEST this is.");

        assert_eq!(HashMap::from([
            (String::from("a"), 2),
            (String::from("is"), 2),
            (String::from("test"), 2),
            (String::from("this"), 2),
        ]), words);
    }

    #[test]
    fn test_sets() {
        let words = read_file_and_process_words();

        let test_set_1 = read_test_file("spell-testset1.txt");
        run_test_set(test_set_1, &words, true);
        // 75% of 270 correct at 41 words per second

        let test_set_2 = read_test_file("spell-testset2.txt");
        run_test_set(test_set_2, &words, true);
        // 68% of 400 correct at 35 words per second
    }
}
