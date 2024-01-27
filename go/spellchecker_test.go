package spellchecker

import (
	"slices"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestSpellchecker(t *testing.T) {
	words := readFileAndProcessWords()

	assert.Equal(t, 29157, len(words))
	assert.Equal(t, Count{"the", 80030}, max(words))
	assert.Equal(t, 0.0, p(words, "quintessential"))
	the := p(words, "the")
	assert.True(t, 0.07 <= the && the <= 0.08)

	assert.Equal(t, []Count{{"the", 80030}, {"of", 40025}, {"and", 38313},
		{"to", 28766}, {"in", 22050}, {"a", 21155}, {"that", 12512},
		{"he", 12401}, {"was", 11410}, {"it", 10681}}, mostCommon(words, 10))

	assert.Equal(t, "spelling", correction(words, "speling"))              // insert
	assert.Equal(t, "corrected", correction(words, "korrectud"))           // replace 2
	assert.Equal(t, "bicycle", correction(words, "bycycle"))               // replace
	assert.Equal(t, "inconvenient", correction(words, "inconvient"))       // insert 2
	assert.Equal(t, "arranged", correction(words, "arrainged"))            // delete
	assert.Equal(t, "poetry", correction(words, "peotry"))                 // transpose
	assert.Equal(t, "poetry", correction(words, "peotry"))                 // transpose + delete
	assert.Equal(t, "word", correction(words, "word"))                     // known
	assert.Equal(t, "quintessential", correction(words, "quintessential")) // unknown
}

func TestProcess(t *testing.T) {
	words := processWords([]byte("This is a TEST."))

	var keys []string
	for k := range words {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	assert.Equal(t, []string{"a", "is", "test", "this"}, keys)

	words = processWords([]byte("This is a test. 123; A TEST this is."))

	assert.Equal(t, map[string]int{"a": 2, "is": 2, "test": 2, "this": 2}, words)
}

func TestSets(t *testing.T) {
	words := readFileAndProcessWords()

	testSet1 := readTestFile("../common/spell-testset1.txt")
	runTestSet(testSet1, words, true)
	// 75% of 270 correct (6% unknown) at 110 words per second

	testSet2 := readTestFile("../common/spell-testset2.txt")
	runTestSet(testSet2, words, true)
	// 68% of 400 correct (11% unknown) at 92 words per second
}
