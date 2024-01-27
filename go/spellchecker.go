package spellchecker

import (
	"bytes"
	"fmt"
	"os"
	"regexp"
	"slices"
	"time"
)

func readFileAndProcessWords() map[string]int {
	contents, err := os.ReadFile("../common/big.txt")
	if err != nil {
		panic(err)
	}

	return processWords(contents)
}

func processWords(contents []byte) map[string]int {
	m := make(map[string]int)

	for _, word := range regexp.MustCompile("[a-z]+").FindAll(bytes.ToLower(contents), -1) {
		m[string(word)]++
	}

	return m
}

func readTestFile(fileName string) [][2]string {
	contents, err := os.ReadFile(fileName)
	if err != nil {
		panic(err)
	}

	var testSet [][2]string

	for _, line := range bytes.Split(contents, []byte("\n")) {
		if len(line) == 0 {
			continue
		}

		split := bytes.Split(line, []byte(": "))
		for _, word := range bytes.Split(split[1], []byte(" ")) {
			testSet = append(testSet, [2]string{string(split[0]), string(word)})
		}
	}

	return testSet
}

func runTestSet(testSet [][2]string, words map[string]int, verbose bool) {
	start := time.Now()
	good := 0
	unknown := 0
	n := len(testSet)

	for _, pair := range testSet {
		right, wrong := pair[0], pair[1]
		w := correction(words, wrong)
		if w == right {
			good++
		} else {
			if _, ok := words[right]; !ok {
				unknown++
			}
			if verbose {
				fmt.Printf("correct(%s) = %s, expected %s\n", wrong, w, right)
			}
		}
	}

	dt := time.Since(start).Seconds()
	fmt.Printf("%.0f%% of %d correct (%.0f%% unknown) at %.0f words per second\n", float64(good)*100.0/float64(n), n, float64(unknown)*100.0/float64(n), float64(n)/dt)
}

func max(m map[string]int) Count {
	maxKey := ""
	maxValue := 0

	for key, value := range m {
		if value > maxValue {
			maxKey = key
			maxValue = value
		}
	}

	return Count{maxKey, maxValue}
}

type Count struct {
	key   string
	value int
}

func mostCommon(m map[string]int, num int) []Count {
	var vec []Count

	for key, value := range m {
		vec = append(vec, Count{key, value})
	}

	slices.SortFunc(vec, func(a, b Count) int {
		return b.value - a.value
	})

	if len(vec) > num {
		vec = vec[:num]
	}

	return vec
}

func edits1(word string) []string {
	letters := "abcdefghijklmnopqrstuvwxyz"

	var splits [][2]string
	for i := 0; i <= len(word); i++ {
		splits = append(splits, [2]string{word[:i], word[i:]})
	}

	var deletes []string
	for _, split := range splits {
		if len(split[1]) > 0 {
			deletes = append(deletes, split[0]+split[1][1:])
		}
	}

	var transposes []string
	for _, split := range splits {
		if len(split[1]) > 1 {
			transposes = append(transposes, split[0]+string(split[1][1])+string(split[1][0])+split[1][2:])
		}
	}

	var replaces []string
	for _, split := range splits {
		if len(split[1]) > 0 {
			for _, letter := range letters {
				replaces = append(replaces, split[0]+string(letter)+split[1][1:])
			}
		}
	}

	var inserts []string
	for _, split := range splits {
		for _, letter := range letters {
			inserts = append(inserts, split[0]+string(letter)+split[1])
		}
	}

	var vec []string
	vec = append(vec, deletes...)
	vec = append(vec, transposes...)
	vec = append(vec, replaces...)
	vec = append(vec, inserts...)

	return vec
}

func edits2(word string) []string {
	var vec []string
	for _, edit1 := range edits1(word) {
		for _, edit2 := range edits1(edit1) {
			vec = append(vec, edit2)
		}
	}
	return vec
}

func p(words map[string]int, word string) float64 {
	n := 0
	for _, value := range words {
		n += value
	}
	count, ok := words[word]
	if !ok {
		count = 0
	}
	return float64(count) / float64(n)
}

func known(words []string, wordsMap map[string]int) []string {
	var vec []string
	for _, word := range words {
		if _, ok := wordsMap[word]; ok {
			vec = append(vec, word)
		}
	}
	return vec
}

func candidates(word string, wordsMap map[string]int) []string {
	if _, ok := wordsMap[word]; ok {
		return []string{word}
	}

	e1 := known(edits1(word), wordsMap)
	if len(e1) > 0 {
		return e1
	}

	e2 := known(edits2(word), wordsMap)
	if len(e2) > 0 {
		return e2
	}

	return []string{word}
}

func correction(words map[string]int, word string) string {
	candidates := candidates(word, words)
	if len(candidates) == 1 {
		return candidates[0]
	}

	maxKey := ""
	maxValue := 0

	for _, key := range candidates {
		value := words[key]
		if value > maxValue {
			maxValue = value
			maxKey = key
		}
	}

	return maxKey
}
