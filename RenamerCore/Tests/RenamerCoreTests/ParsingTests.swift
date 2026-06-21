import Testing
@testable import RenamerCore

/// Parity tests: every case here mirrors one from the original Python engine's
/// `tests/test_renamer.py`, so the Swift port is provably equivalent on the
/// parsing layer. The Python suite is the behavioural oracle.
@Suite("Parsing parity with the Python engine")
struct ParsingTests {

    // MARK: - movie()

    @Test func canonicalForm() {
        #expect(MediaParser.movie("Inception (2010).mkv")?.title == "Inception (2010)")
    }

    @Test func sceneFormPTP() {
        #expect(MediaParser.movie("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv")?.title
                == "The Matrix (1999)")
    }

    @Test func akaStripping() {
        #expect(MediaParser.movie("Foreign.Title.AKA.Real.Title.2015.1080p.WEB-DL.mkv")?.title
                == "Real Title (2015)")
    }

    @Test func yearInTitleTrapPicksReleaseYear() {
        // 2001 leads the title; 1968 is the actual release year.
        let p = MediaParser.movie("2001.A.Space.Odyssey.1968.1080p.BluRay.mkv")
        #expect(p?.title.hasSuffix("(1968)") == true)
        #expect(p?.title.contains("2001") == true)
    }

    @Test func mashAcronymBaseline() {
        // Documents the baseline: dots split M.A.S.H into letters, single 'A'
        // is treated as the stopword 'a' and lowercased mid-title.
        let p = MediaParser.movie("M.A.S.H.1970.1080p.BluRay.mkv", acronyms: ["MASH": "MASH"])
        #expect(p?.title == "M a S H (1970)")
    }

    @Test func preservedStopwordsCarried() {
        let p = MediaParser.movie("Wicked.For.Good.2025.1080p.WEB-DL.mkv")
        #expect(p?.title == "Wicked For Good (2025)")
        #expect(p?.preservedStopwords.contains("For") == true)
    }

    @Test func movieNoYearReturnsNil() {
        #expect(MediaParser.movie("random.untagged.file.mkv") == nil)
    }

    // MARK: - tv()

    @Test func tvStandard() {
        let p = MediaParser.tv("Show.Name.S01E01.1080p.mkv")
        #expect(p?.title == "Show Name")
        #expect(p?.episodeCode == "S01E01")
        #expect(p?.season == 1)
    }

    @Test func tvLowercaseFourDigitSeason() {
        let p = MediaParser.tv("show.name.s2024e05.web.mkv")
        #expect(p?.episodeCode == "S2024E05")
        #expect(p?.season == 2024)
        #expect(p?.title == "Show Name")
    }

    @Test func tvMultiEpisodeDouble() {
        let p = MediaParser.tv("Show.S01E01E02.mkv")
        #expect(p?.season == 1)
        #expect(p?.episodeCode == "S01E01E02")
    }

    @Test func tvMultiEpisodeRange() {
        let p = MediaParser.tv("Show.S01E01-E02.mkv")
        #expect(p?.season == 1)
        #expect(p?.episodeCode == "S01E01-E02")
    }

    @Test func tvNoEpisodeReturnsNil() {
        #expect(MediaParser.tv("Inception.2010.1080p.mkv") == nil)
    }

    // MARK: - releaseYear()

    @Test func yearParensWins() {
        let name = "Inception (2010) 1999.1080p.BluRay"
        #expect(MediaParser.releaseYear(name).map { String(name[$0]) } == "2010")
    }

    @Test func yearSceneRightmostKnownToken() {
        let name = "Blade.Runner.2049.2017.2160p.UHD.BluRay.x265-GROUP"
        #expect(MediaParser.releaseYear(name).map { String(name[$0]) } == "2017")
    }

    @Test func yearFallbackRightmost() {
        let name = "Some.Title.1998.SomethingObscure"
        #expect(MediaParser.releaseYear(name).map { String(name[$0]) } == "1998")
    }

    @Test func yearNone() {
        #expect(MediaParser.releaseYear("Just.A.Name.With.No.Year") == nil)
    }

    // MARK: - titleCase() / normalise()

    @Test func titleBasicEdge() {
        #expect(TitleFormatter.titleCase("the matrix") == "The Matrix")
    }

    @Test func titleMidStopwordsLowercased() {
        #expect(TitleFormatter.titleCase("lord of the rings") == "Lord of the Rings")
    }

    @Test func titleAcronymLookup() {
        #expect(TitleFormatter.titleCase("nasa story", acronyms: ["NASA": "NASA"]) == "NASA Story")
    }

    @Test func titlePreserveExplicitCapital() {
        #expect(TitleFormatter.titleCase("Wicked For Good") == "Wicked For Good")
    }

    @Test func titleColonSanitised() {
        #expect(TitleFormatter.normalise("X: Men") == "X - Men")
    }

    /// Swift-side divergence from the oracle: 4-letter prepositions and the
    /// remaining coordinating conjunctions are lowercased mid-title so canonical
    /// media titles match TVDB/Plex casing. Edge words stay capitalised.
    @Test func titleLongConnectorsLowercased() {
        #expect(TitleFormatter.titleCase("last week tonight with john oliver")
                == "Last Week Tonight with John Oliver")
        #expect(TitleFormatter.titleCase("how to get away with murder")
                == "How to Get Away with Murder")
        #expect(TitleFormatter.titleCase("from dusk till dawn")        // edge "from" capitalised
                == "From Dusk Till Dawn")
    }

    /// Contractions and possessives keep their lowercase tail — the apostrophe
    /// no longer splits the word into a re-capitalised fragment (the reported
    /// "I Don'T Feel..." bug). Covers a tail at the title edge ("She's") and a
    /// trailing apostrophe ("Cowboys'").
    @Test func titleContractionsAndPossessives() {
        #expect(TitleFormatter.titleCase("I Don't Feel at Home in This World Anymore")
                == "I Don't Feel at Home in This World Anymore")
        #expect(TitleFormatter.titleCase("ocean's eleven") == "Ocean's Eleven")
        #expect(TitleFormatter.titleCase("she's all that") == "She's All That")
        #expect(TitleFormatter.titleCase("cowboys' hat") == "Cowboys' Hat")
    }

    /// A curly apostrophe (U+2019) is handled identically to the straight one.
    @Test func titleContractionCurlyApostrophe() {
        #expect(TitleFormatter.titleCase("don\u{2019}t look up") == "Don\u{2019}t Look Up")
    }

    /// Swift-side divergence from the oracle: an accented word stays one token
    /// (the ASCII-only word regex used to split on the accent and re-capitalise
    /// the tail — "amélie" → "AméLie"). Covers precomposed (NFC) and decomposed
    /// (NFD) forms, an accent mid-word and word-final, and a multi-word title.
    @Test func titleAccentedWordsStayWhole() {
        #expect(TitleFormatter.titleCase("amélie") == "Amélie")
        #expect(TitleFormatter.titleCase("les misérables") == "Les Misérables")
        #expect(TitleFormatter.titleCase("pokémon detective pikachu") == "Pokémon Detective Pikachu")
        #expect(TitleFormatter.titleCase("café society") == "Café Society")
        // NFD: "amelie" with a combining acute (U+0301) after the first "e" —
        // the mark must stay attached to its base letter, not split the word.
        // (Swift String == uses canonical equivalence, so this equals "Amélie".)
        #expect(TitleFormatter.titleCase("ame\u{0301}lie") == "Amélie")
    }

    /// An acronym possessive keeps the mapped acronym AND a lowercase tail.
    /// Guards against widening the word regex (which would merge "BBC's" into one
    /// token, miss the "BBC" key, and yield "Bbc's").
    @Test func titleAcronymPossessive() {
        #expect(TitleFormatter.titleCase("bbc's documentary", acronyms: ["BBC": "BBC"])
                == "BBC's Documentary")
    }

    /// A leading apostrophe particle is NOT a contraction tail (no letter before
    /// the apostrophe), so it stays capitalised.
    @Test func titleLeadingApostropheParticle() {
        #expect(TitleFormatter.titleCase("'tis the season") == "'Tis the Season")
    }

    /// Documented, accepted limitation: leading-particle names lose their
    /// internal capital because `capitalizeWord` (str.capitalize semantics)
    /// lowercases the tail. Pinned so the regression stays intentional.
    @Test func titleApostropheNameLimitation() {
        #expect(TitleFormatter.titleCase("o'brien") == "O'brien")
    }

    // MARK: - preservedStopwords()

    @Test func stopwordsFlagsMidCapital() {
        #expect(TitleFormatter.preservedStopwords("Wicked For Good") == ["For"])
    }

    @Test func stopwordsIgnoresEdges() {
        #expect(TitleFormatter.preservedStopwords("Of Mice and Men") == [])
    }

    @Test func stopwordsIgnoresAllCaps() {
        #expect(TitleFormatter.preservedStopwords("Word FOR Other") == [])
    }

    @Test func stopwordsOnlyTitlecaseForm() {
        #expect(TitleFormatter.preservedStopwords("Wicked for Good") == [])
    }

    // MARK: - classify()

    @Test func classifyTV() {
        #expect(MediaParser.classify("Show.S01E01.mkv") == .tv)
        #expect(MediaParser.classify("show.s2024e05.mkv") == .tv)
    }

    @Test func classifyMovie() {
        #expect(MediaParser.classify("Inception.2010.1080p.BluRay.mkv") == .movie)
        #expect(MediaParser.classify("Inception (2010).mkv") == .movie)
    }

    @Test func classifyUnknown() {
        #expect(MediaParser.classify("random.untagged.file.mkv") == .unknown)
    }

    // MARK: - Sidecars.languageSuffix()

    @Test func langEng() {
        #expect(Sidecars.languageSuffix("Movie.2010.eng.srt") == ".eng")
    }

    @Test func langNone() {
        #expect(Sidecars.languageSuffix("Movie.2010.srt") == "")
    }

    @Test func langUnknownDropped() {
        #expect(Sidecars.languageSuffix("Movie.2010.wat.srt") == "")
    }

    @Test func langCompoundPtBr() {
        #expect(Sidecars.languageSuffix("Movie.2010.pt-br.srt") == ".pt-br")
    }
}
