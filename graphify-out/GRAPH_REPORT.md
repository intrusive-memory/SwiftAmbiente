# Graph Report - .  (2026-11-08)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 984 nodes · 1867 edges · 48 communities (41 shown, 7 thin omitted)
- Extraction: 95% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 81 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `141af689`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Acervo Test Directory Gate|Acervo Test Directory Gate]]
- [[_COMMUNITY_Model Config Types|Model Config Types]]
- [[_COMMUNITY_Golden Audio Comparison|Golden Audio Comparison]]
- [[_COMMUNITY_Stable Audio DiT|Stable Audio DiT]]
- [[_COMMUNITY_Gemma BPE Tokenizer|Gemma BPE Tokenizer]]
- [[_COMMUNITY_T5Gemma Text Encoder|T5Gemma Text Encoder]]
- [[_COMMUNITY_Procedural Ambient Generator|Procedural Ambient Generator]]
- [[_COMMUNITY_Config Coding Keys|Config Coding Keys]]
- [[_COMMUNITY_Stable Audio Generator|Stable Audio Generator]]
- [[_COMMUNITY_Stable Audio Pipeline|Stable Audio Pipeline]]
- [[_COMMUNITY_SAMES Audio Decoder|SAMES Audio Decoder]]
- [[_COMMUNITY_Ambiente Engine|Ambiente Engine]]
- [[_COMMUNITY_Latent Generation|Latent Generation]]
- [[_COMMUNITY_Core Library Overview|Core Library Overview]]
- [[_COMMUNITY_Model Asset Loading|Model Asset Loading]]
- [[_COMMUNITY_Golden Parity Strategy|Golden Parity Strategy]]
- [[_COMMUNITY_CLI Command|CLI Command]]
- [[_COMMUNITY_Audio Conditioning Embedders|Audio Conditioning Embedders]]
- [[_COMMUNITY_CI Model Integration|CI Model Integration]]
- [[_COMMUNITY_Model Manager|Model Manager]]
- [[_COMMUNITY_Project Docs and Licensing|Project Docs and Licensing]]
- [[_COMMUNITY_Mission Planning Docs|Mission Planning Docs]]
- [[_COMMUNITY_T5Gemma Text Conditioner|T5Gemma Text Conditioner]]
- [[_COMMUNITY_Flow Sampler|Flow Sampler]]
- [[_COMMUNITY_Acervo Test Trait|Acervo Test Trait]]
- [[_COMMUNITY_Model CDN Distribution|Model CDN Distribution]]
- [[_COMMUNITY_CLI Command Tests|CLI Command Tests]]
- [[_COMMUNITY_Audio File Writer|Audio File Writer]]
- [[_COMMUNITY_WAV Encoding|WAV Encoding]]
- [[_COMMUNITY_Config Tests|Config Tests]]
- [[_COMMUNITY_CI Model Primer Script|CI Model Primer Script]]
- [[_COMMUNITY_CLI Version|CLI Version]]
- [[_COMMUNITY_CI Cache Key Script|CI Cache Key Script]]
- [[_COMMUNITY_Stable Audio Backend|Stable Audio Backend]]
- [[_COMMUNITY_Library Version|Library Version]]
- [[_COMMUNITY_CLI Entry Point|CLI Entry Point]]
- [[_COMMUNITY_Package Manifest|Package Manifest]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]

## God Nodes (most connected - your core abstractions)
1. `CodingKeys` - 26 edges
2. `StableAudioGenerator` - 22 edges
3. `StableAudioGenerator` - 22 edges
4. `AGENTS.md — SwiftAmbiente` - 21 edges
5. `StableAudioDiT` - 18 edges
6. `MLXArray` - 17 edges
7. `withResolvedAcervoModelsDirectory()` - 17 edges
8. `StableAudioSAMESDecoder` - 16 edges
9. `write()` - 16 edges
10. `note()` - 16 edges

## Surprising Connections (you probably didn't know these)
- `README — SwiftAmbiente` --semantically_similar_to--> `AGENTS.md — SwiftAmbiente`  [INFERRED] [semantically similar]
  README.md → AGENTS.md
- `ambiente CLI` --semantically_similar_to--> `AmbienteRootCommand (ambiente CLI)`  [INFERRED] [semantically similar]
  README.md → AGENTS.md
- `Tests workflow (unit tests)` --references--> `ProceduralAmbienteGenerator`  [EXTRACTED]
  .github/workflows/tests.yml → AGENTS.md
- `StableAudioGenerator` --calls--> `StableAudioLatentGenerator`  [INFERRED]
  AGENTS.md → Sources/SwiftAmbiente/StableAudio/STRATEGY.md
- `StableAudioGenerator` --calls--> `T5GemmaTextConditioner`  [INFERRED]
  AGENTS.md → Sources/SwiftAmbiente/StableAudio/STRATEGY.md

## Import Cycles
- None detected.

## Communities (48 total, 7 thin omitted)

### Community 0 - "Acervo Test Directory Gate"
Cohesion: 0.06
Nodes (52): AmbienceRenderState, AmbienceRenderStatus, Codable, ConditionerConfig, Conditioning, Diffusion, DiffusionConfig, Equatable (+44 more)

### Community 1 - "Model Config Types"
Cohesion: 0.06
Nodes (40): CaseIterable, RenderRecord, StableAudioModelRepo, Data, Date, GlosaCore, RenderRecord, URL (+32 more)

### Community 2 - "Golden Audio Comparison"
Cohesion: 0.05
Nodes (33): CheckedContinuation, Int32, Never, AcervoModelsDirectoryGate, withResolvedAcervoModelsDirectory(), withTempAcervoModelsDirectory(), AmbienteModelManagerTests, LatentSamplerFixture (+25 more)

### Community 3 - "Stable Audio DiT"
Cohesion: 0.06
Nodes (37): CustomStringConvertible, Error, Hashable, Pair, Bool, Int, String, URL (+29 more)

### Community 4 - "Gemma BPE Tokenizer"
Cohesion: 0.07
Nodes (20): AmbienteCommand, AmbienteRootCommand, AmbienteModelManager, AsyncParsableCommand, Bool, Double, Int, StableAudioModelRepo (+12 more)

### Community 5 - "T5Gemma Text Encoder"
Cohesion: 0.13
Nodes (17): AmbienteGenerator, AmbienceRenderTests, exists(), FailingGenerator, makeTempDirectory(), note(), StubGenerator, WriteFailure (+9 more)

### Community 6 - "Procedural Ambient Generator"
Cohesion: 0.11
Nodes (19): AudioSpectralDelta, AudioSpectralDelta, ParseError, badTag, notPCM16, sizeMismatch, tooShort, PCMWAV (+11 more)

### Community 7 - "Config Coding Keys"
Cohesion: 0.11
Nodes (24): CodingKey, Decoder, Encoder, GlosaJSONValue, Data, Date, Decoder, GlosaCore (+16 more)

### Community 8 - "Stable Audio Generator"
Cohesion: 0.11
Nodes (14): AmbienteConfig, R, AmbienteConfig, Bool, Data, Double, GenerationSettings, R (+6 more)

### Community 9 - "Stable Audio Pipeline"
Cohesion: 0.18
Nodes (13): RandomNumberGenerator, Substring, AmbiencePlannerTests, isSeedOrOutputKeyLine(), lineDifference(), makeTempDirectory(), SeededGenerator, write() (+5 more)

### Community 10 - "SAMES Audio Decoder"
Cohesion: 0.22
Nodes (11): Double, Float, Int, MLXArray, StableAudioModelConfig, String, StableAudioDiT, StableAudioDiTConfig (+3 more)

### Community 11 - "Ambiente Engine"
Cohesion: 0.12
Nodes (26): AmbienteEngineTests, AmbienteModelManagerTests, PCMWAV parser, ProceduralGeneratorTests, StableAudioGeneratorTests, AmbienceModel.resolve, AmbienteConfig, AmbienteEngine (+18 more)

### Community 12 - "Latent Generation"
Cohesion: 0.15
Nodes (15): AmbiencePlan, AmbiencePlanEntry, AmbienceRenderOutcome, failed, rendered, wouldRender, AmbienteRenderCommand, FoleyPlanEntry (+7 more)

### Community 13 - "Core Library Overview"
Cohesion: 0.12
Nodes (11): AmbienteRenderCommandTests, AmbienteSubcommandParsingTests, FakeGenerator, makeFoleyProject(), makeProject(), snapshot(), Bool, Data (+3 more)

### Community 14 - "Model Asset Loading"
Cohesion: 0.20
Nodes (12): Decodable, Float, Int, MLXArray, URL, Block, RawConfig, T5GemmaEncoderConfig (+4 more)

### Community 15 - "Golden Parity Strategy"
Cohesion: 0.09
Nodes (23): LocalizedError, String, Data, Double, Float, Int, String, AmbienteError (+15 more)

### Community 16 - "CLI Command"
Cohesion: 0.19
Nodes (11): C, AmbientBedTests, channel(), rms(), SplitMix64, Takes, Double, Float (+3 more)

### Community 17 - "Audio Conditioning Embedders"
Cohesion: 0.13
Nodes (10): AmbienteConfig, Bool, Data, Float, GenerationSettings, String, UInt64, ProceduralAmbienteGenerator (+2 more)

### Community 18 - "CI Model Integration"
Cohesion: 0.16
Nodes (14): ambienceRecordFixture(), CountingStubGenerator, exists(), foley(), FoleyRenderTests, makeTempDirectory(), Bool, Data (+6 more)

### Community 19 - "Model Manager"
Cohesion: 0.14
Nodes (18): StableAudioGoldenParityTests, StableAudioModelRepo, acervo ship stabilityai/stable-audio-3-small-sfx, CDN slug stabilityai_stable-audio-3-small-sfx, COMPLETE_SwiftAmbiente.md (completion log), EXECUTION_PLAN.md — Operation Phantom Foley, ElevenLabs SFX (rejected), OPERATION PHANTOM FOLEY mission (+10 more)

### Community 20 - "Project Docs and Licensing"
Cohesion: 0.16
Nodes (12): AmbienteConfig, Data, Double, Float, GenerationSettings, Int, MLXArray, String (+4 more)

### Community 21 - "Mission Planning Docs"
Cohesion: 0.27
Nodes (6): Int, MLXArray, String, BlockWeights, DyTWeights, StableAudioSAMESDecoder

### Community 22 - "T5Gemma Text Conditioner"
Cohesion: 0.15
Nodes (14): Double, Float, GenerationSettings, Int, MLXArray, StableAudioModelConfig, String, URL (+6 more)

### Community 23 - "Flow Sampler"
Cohesion: 0.24
Nodes (11): Int, MLXArray, StableAudioModelConfig, String, URL, StableAudioModelAssets, StableAudioModelLoaderError, configNotFound (+3 more)

### Community 24 - "Acervo Test Trait"
Cohesion: 0.20
Nodes (16): AmbiencePlanner.plan, AmbienceRendering.renderState, AmbientBed.fill, GlosaCore (glosa-av), GlosaCore.Ambience note, GlosaCore Foley note, GlosaFountainNotes, GlosaParser (+8 more)

### Community 25 - "Model CDN Distribution"
Cohesion: 0.28
Nodes (9): DType, Double, Float, Int, MLXArray, String, Assembled, SecondsTotalEmbedder (+1 more)

### Community 26 - "CLI Command Tests"
Cohesion: 0.22
Nodes (15): ACCEPTANCE.md — Stable Audio integration, ambiente CLI, mlx-swift_Cmlx.bundle (Metal library bundle), SwiftAcervo (shared models / CDN download), acervo-ci-cache-key.sh / acervo-ci-prime.sh, TEST_RUNNER_ACERVO_MODELS_DIR forwarding, Integration Tests workflow (real models), SwiftAcervo fatalError without CDN URL (+7 more)

### Community 27 - "Audio File Writer"
Cohesion: 0.14
Nodes (15): StableAudioLatentSamplerTests, AmbienteSceneDescriptor, GenerationSettings, cfg 7.0→1.0 re-record rationale, Golden fixture reproducibility note, APG guidance (default 1.0), GemmaBPETokenizer, Threefry seed RNG parity (MLXRandom) (+7 more)

### Community 28 - "WAV Encoding"
Cohesion: 0.19
Nodes (13): AGENTS.md — SwiftAmbiente, graphify-out codemap, Phantom Foley requirements (stable audio integration), Package.swift sibling() helper, StableAudio STRATEGY.md, Never swift build/test; use Makefile/xcodebuild, User-owned license-acceptance checklist, README.md — SwiftAmbiente (+5 more)

### Community 29 - "Config Tests"
Cohesion: 0.30
Nodes (7): Double, Float, Int, PCMAudio, String, AmbientBed, TimeInterval

### Community 30 - "CI Model Primer Script"
Cohesion: 0.22
Nodes (8): AcervoError, AmbienteError, AmbienteConfig, AmbienteGenerator, Bool, StableAudioModelRepo, URL, AmbienteModelManager

### Community 31 - "CLI Version"
Cohesion: 0.23
Nodes (14): DiT flow-matching sampler, Google Gemma Terms of Use, SAME-S decoder, Stability AI Community License, Stable Audio 3 Small SFX model, T5Gemma encoder, Gemma §3.1 pass-through to end users, LICENSE (MIT) (+6 more)

### Community 32 - "CI Cache Key Script"
Cohesion: 0.24
Nodes (8): GemmaBPETokenizer, Int, MLXArray, String, URL, T5GemmaConditioning, T5GemmaTextConditioner, T5GemmaTextEncoder

### Community 33 - "Stable Audio Backend"
Cohesion: 0.26
Nodes (8): Bool, Double, Float, Int, MLXArray, UInt64, Void, StableAudioFlowSampler

### Community 34 - "Library Version"
Cohesion: 0.24
Nodes (11): ACERVO_CDN_BASE_URL requirement, AmbienteSceneDescriptor, AmbienteCommand (generate), AmbienteRenderCommand (render), AmbienteRootCommand (ambiente CLI), render has no procedural fallback (digest would read current), render has no procedural fallback (fallback take would carry matching digest), Scene presets (room-tone, rain, forest, city, ocean, cafe, night) (+3 more)

### Community 35 - "CLI Entry Point"
Cohesion: 0.20
Nodes (8): Self, SuiteTrait, AcervoEnvironmentTrait, Trait, Test, Bool, Sendable, TestScoping

### Community 38 - "Community 38"
Cohesion: 0.38
Nodes (4): AudioFileWriter, AudioOutputFormat, Data, String

### Community 39 - "Community 39"
Cohesion: 0.33
Nodes (4): Data, Float, Int, WAVWriter

### Community 41 - "Community 41"
Cohesion: 0.60
Nodes (3): fetch(), prime_one(), acervo-ci-prime.sh script

## Ambiguous Edges - Review These
- `AGENTS.md — SwiftAmbiente` → `StableAudioGenerator`  [AMBIGUOUS]
  AGENTS.md · relation: references
- `ambiente CLI` → `ACCEPTANCE.md — Stable Audio integration`  [AMBIGUOUS]
  docs/ACCEPTANCE.md · relation: references
- `ambiente CLI` → `SUPERVISOR_STATE.md`  [AMBIGUOUS]
  docs/complete/phantom-foley-01/SUPERVISOR_STATE.md · relation: references
- `Release workflow` → `ACCEPTANCE.md — Stable Audio integration`  [AMBIGUOUS]
  docs/ACCEPTANCE.md · relation: references

## Knowledge Gaps
- **198 isolated node(s):** `acervo-ci-cache-key.sh script`, `Bool`, `Double`, `UInt64`, `Int` (+193 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `AGENTS.md — SwiftAmbiente` and `StableAudioGenerator`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `ambiente CLI` and `ACCEPTANCE.md — Stable Audio integration`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `ambiente CLI` and `SUPERVISOR_STATE.md`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `Release workflow` and `ACCEPTANCE.md — Stable Audio integration`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **Why does `AmbienteEngine` connect `Gemma BPE Tokenizer` to `Acervo Test Directory Gate`?**
  _High betweenness centrality (0.087) - this node is a cross-community bridge._
- **Why does `CountingStubGenerator` connect `CI Model Integration` to `Acervo Test Directory Gate`, `T5Gemma Text Encoder`?**
  _High betweenness centrality (0.073) - this node is a cross-community bridge._
- **Why does `StableAudioGenerator` connect `Stable Audio Generator` to `Model Config Types`, `T5Gemma Text Encoder`, `CI Model Primer Script`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._