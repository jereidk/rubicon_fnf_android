class_name ResultsData
extends RefCounted
## Static singleton to pass score data from song scene to results screen.
## Access via ResultsData.song_name, ResultsData.score, etc.

static var song_name: String = ""
static var score: int = 0
static var accuracy: float = 100.0
static var hits_perfect: int = 0
static var hits_great: int = 0
static var hits_good: int = 0
static var hits_okay: int = 0
static var hits_bad: int = 0
static var hits_miss: int = 0
