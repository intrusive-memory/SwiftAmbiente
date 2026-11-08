# Graph Report - .  (2026-11-08)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 900 nodes · 1656 edges · 51 communities (44 shown, 7 thin omitted)
- Extraction: 95% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 73 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `43b6804f`
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
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]

## God Nodes (most connected - your core abstractions)
1. `CodingKeys` - 26 edges
2. `StableAudioGenerator` - 22 edges
3. `StableAudioGenerator` - 21 edges
4. `StableAudioDiT` - 18 edges
5. `AGENTS.md — SwiftAmbiente` - 18 edges
6. `MLXArray` - 17 edges
7. `withResolvedAcervoModelsDirectory()` - 17 edges
8. `StableAudioSAMESDecoder` - 16 edges
9. `MLXArray` - 15 edges
10. `T5GemmaTextEncoder` - 15 edges

## Surprising Connections (you probably didn't know these)
- `README — SwiftAmbiente` --semantically_similar_to--> `AGENTS.md — SwiftAmbiente`  [INFERRED] [semantically similar]
  README.md → AGENTS.md
- `Verify with counsel — open licensing ambiguities` --conceptually_related_to--> `SwiftAcervo (shared models / CDN download)`  [AMBIGUOUS]
  README.md → AGENTS.md
- `Configuring model downloads (ACERVO_CDN_BASE_URL)` --references--> `AmbienteEngine`  [EXTRACTED]
  README.md → AGENTS.md
- `Tests workflow (unit tests)` --references--> `ProceduralAmbienteGenerator`  [EXTRACTED]
  .github/workflows/tests.yml → AGENTS.md
- `StableAudioGenerator` --calls--> `StableAudioLatentGenerator`  [INFERRED]
  AGENTS.md → Sources/SwiftAmbiente/StableAudio/STRATEGY.md

## Import Cycles
- None detected.

## Communities (51 total, 7 thin omitted)

### Community 0 - "Acervo Test Directory Gate"
Cohesion: 0.05
Nodes (33): CheckedContinuation, Int32, Never, AcervoModelsDirectoryGate, withResolvedAcervoModelsDirectory(), withTempAcervoModelsDirectory(), AmbienteModelManagerTests, LatentSamplerFixture (+25 more)

### Community 1 - "Model Config Types"
Cohesion: 0.07
Nodes (20): AmbienteCommand, AmbienteRootCommand, AmbienteModelManager, AsyncParsableCommand, Bool, Double, Int, StableAudioModelRepo (+12 more)

### Community 2 - "Golden Audio Comparison"
Cohesion: 0.11
Nodes (23): CaseIterable, RenderRecord, StableAudioModelRepo, Data, Date, GlosaCore, URL, Void (+15 more)

### Community 3 - "Stable Audio DiT"
Cohesion: 0.11
Nodes (25): CustomStringConvertible, Error, Hashable, Pair, Bool, Int, String, URL (+17 more)

### Community 4 - "Gemma BPE Tokenizer"
Cohesion: 0.14
Nodes (15): AmbienceRenderTests, exists(), FailingGenerator, makeTempDirectory(), note(), StubGenerator, WriteFailure, Bool (+7 more)

### Community 5 - "T5Gemma Text Encoder"
Cohesion: 0.11
Nodes (19): AudioSpectralDelta, AudioSpectralDelta, ParseError, badTag, notPCM16, sizeMismatch, tooShort, PCMWAV (+11 more)

### Community 6 - "Procedural Ambient Generator"
Cohesion: 0.11
Nodes (14): AmbienteConfig, R, AmbienteConfig, Bool, Data, Double, GenerationSettings, R (+6 more)

### Community 7 - "Config Coding Keys"
Cohesion: 0.22
Nodes (11): Double, Float, Int, MLXArray, StableAudioModelConfig, String, StableAudioDiT, StableAudioDiTConfig (+3 more)

### Community 8 - "Stable Audio Generator"
Cohesion: 0.12
Nodes (26): AmbienteModelManagerTests, PCMWAV parser, ProceduralGeneratorTests, StableAudioGeneratorTests, AmbienceModel.resolve, AmbienteConfig, AmbienteEngine, AmbienteEngine.resolveGenerator (+18 more)

### Community 9 - "Stable Audio Pipeline"
Cohesion: 0.21
Nodes (13): AmbienceRenderState, AmbienceRenderStatus, G, GlosaDiagnostic, Set, Bool, GlosaCore, Int (+5 more)

### Community 10 - "SAMES Audio Decoder"
Cohesion: 0.20
Nodes (12): Decodable, Float, Int, MLXArray, URL, Block, RawConfig, T5GemmaEncoderConfig (+4 more)

### Community 11 - "Ambiente Engine"
Cohesion: 0.19
Nodes (11): C, AmbientBedTests, channel(), rms(), SplitMix64, Takes, Double, Float (+3 more)

### Community 12 - "Latent Generation"
Cohesion: 0.12
Nodes (11): AmbienteGenerator, AmbienteConfig, Bool, Data, Float, GenerationSettings, String, UInt64 (+3 more)

### Community 13 - "Core Library Overview"
Cohesion: 0.14
Nodes (18): CodingKey, Encoder, GlosaJSONValue, Data, Date, Decoder, GlosaCore, Int (+10 more)

### Community 14 - "Model Asset Loading"
Cohesion: 0.19
Nodes (12): RandomNumberGenerator, Substring, AmbiencePlannerTests, isSeedOrOutputKeyLine(), lineDifference(), makeTempDirectory(), SeededGenerator, write() (+4 more)

### Community 15 - "Golden Parity Strategy"
Cohesion: 0.19
Nodes (22): Codable, ConditionerConfig, Conditioning, Diffusion, DiffusionConfig, Equatable, ModelBlock, Pretransform (+14 more)

### Community 16 - "CLI Command"
Cohesion: 0.18
Nodes (12): AmbiencePlan, AmbiencePlanEntry, AmbienceRenderOutcome, failed, rendered, wouldRender, AmbienteRenderCommand, Bool (+4 more)

### Community 17 - "Audio Conditioning Embedders"
Cohesion: 0.09
Nodes (23): CodingKeys, audioChannels, condDim, conditioning, condTokenDim, config, configs, depth (+15 more)

### Community 18 - "CI Model Integration"
Cohesion: 0.12
Nodes (21): AmbienteEngineTests, StableAudioGoldenParityTests, StableAudioModelRepo, acervo ship stabilityai/stable-audio-3-small-sfx, CDN slug stabilityai_stable-audio-3-small-sfx, COMPLETE_SwiftAmbiente.md (completion log), EXECUTION_PLAN.md — Operation Phantom Foley, ElevenLabs SFX (rejected) (+13 more)

### Community 19 - "Model Manager"
Cohesion: 0.13
Nodes (20): AmbiencePlanner.plan, AmbienceRendering.renderState, AmbientBed.fill, AGENTS.md — SwiftAmbiente, GlosaCore (glosa-av), GlosaCore.Ambience note, GlosaFountainNotes, GlosaParser (+12 more)

### Community 20 - "Project Docs and Licensing"
Cohesion: 0.16
Nodes (12): AmbienteConfig, Data, Double, Float, GenerationSettings, Int, MLXArray, String (+4 more)

### Community 21 - "Mission Planning Docs"
Cohesion: 0.27
Nodes (6): Int, MLXArray, String, BlockWeights, DyTWeights, StableAudioSAMESDecoder

### Community 22 - "T5Gemma Text Conditioner"
Cohesion: 0.15
Nodes (7): AmbienteRenderCommandTests, AmbienteSubcommandParsingTests, makeProject(), snapshot(), Data, String, URL

### Community 23 - "Flow Sampler"
Cohesion: 0.15
Nodes (14): Double, Float, GenerationSettings, Int, MLXArray, StableAudioModelConfig, String, URL (+6 more)

### Community 24 - "Acervo Test Trait"
Cohesion: 0.11
Nodes (19): StableAudioLatentSamplerTests, ACERVO_CDN_BASE_URL requirement, AmbienteCommand (generate), AmbienteRootCommand (ambiente CLI), AmbienteSceneDescriptor, GenerationSettings, cfg 7.0→1.0 re-record rationale, Golden fixture reproducibility note (+11 more)

### Community 25 - "Model CDN Distribution"
Cohesion: 0.28
Nodes (9): DType, Double, Float, Int, MLXArray, String, Assembled, SecondsTotalEmbedder (+1 more)

### Community 26 - "CLI Command Tests"
Cohesion: 0.18
Nodes (13): LocalizedError, Data, Double, Float, Int, String, DecodeError, invalidHeader (+5 more)

### Community 27 - "Audio File Writer"
Cohesion: 0.19
Nodes (20): ACCEPTANCE.md — Stable Audio integration, ambiente CLI, mlx-swift_Cmlx.bundle (Metal library bundle), SwiftAcervo (shared models / CDN download), User-owned license-acceptance checklist, acervo-ci-cache-key.sh / acervo-ci-prime.sh, TEST_RUNNER_ACERVO_MODELS_DIR forwarding, Integration Tests workflow (real models) (+12 more)

### Community 28 - "WAV Encoding"
Cohesion: 0.30
Nodes (7): Double, Float, Int, PCMAudio, String, AmbientBed, TimeInterval

### Community 29 - "Config Tests"
Cohesion: 0.22
Nodes (8): AcervoError, AmbienteError, AmbienteConfig, AmbienteGenerator, Bool, StableAudioModelRepo, URL, AmbienteModelManager

### Community 30 - "CI Model Primer Script"
Cohesion: 0.24
Nodes (8): GemmaBPETokenizer, Int, MLXArray, String, URL, T5GemmaConditioning, T5GemmaTextConditioner, T5GemmaTextEncoder

### Community 31 - "CLI Version"
Cohesion: 0.26
Nodes (8): Bool, Double, Float, Int, MLXArray, UInt64, Void, StableAudioFlowSampler

### Community 32 - "CI Cache Key Script"
Cohesion: 0.20
Nodes (8): Self, SuiteTrait, AcervoEnvironmentTrait, Trait, Test, Bool, Sendable, TestScoping

### Community 33 - "Stable Audio Backend"
Cohesion: 0.18
Nodes (10): String, AmbienteError, audioExportFailed, generationFailed, invalidAmbience, invalidDuration, modelNotAvailable, takeTooLong (+2 more)

### Community 35 - "CLI Entry Point"
Cohesion: 0.28
Nodes (9): DiT flow-matching sampler, Google Gemma Terms of Use, SAME-S decoder, Stability AI Community License, Stable Audio 3 Small SFX model, T5Gemma encoder, README Licensing section, MIT LICENSE (SwiftAmbiente code) (+1 more)

### Community 37 - "Community 37"
Cohesion: 0.36
Nodes (6): Int, AmbienteConfig, AudioOutputFormat, aiff, caf, wav

### Community 39 - "Community 39"
Cohesion: 0.38
Nodes (4): AudioFileWriter, AudioOutputFormat, Data, String

### Community 40 - "Community 40"
Cohesion: 0.33
Nodes (4): Decoder, Data, Decoder, URL

### Community 41 - "Community 41"
Cohesion: 0.47
Nodes (3): Identifiable, String, AmbienteSceneDescriptor

### Community 42 - "Community 42"
Cohesion: 0.53
Nodes (4): Double, Int, UInt64, GenerationSettings

### Community 43 - "Community 43"
Cohesion: 0.33
Nodes (4): Data, Float, Int, WAVWriter

### Community 45 - "Community 45"
Cohesion: 0.60
Nodes (3): fetch(), prime_one(), acervo-ci-prime.sh script

## Ambiguous Edges - Review These
- `AGENTS.md — SwiftAmbiente` → `StableAudioGenerator`  [AMBIGUOUS]
  AGENTS.md · relation: references
- `ambiente CLI` → `ACCEPTANCE.md — Stable Audio integration`  [AMBIGUOUS]
  docs/ACCEPTANCE.md · relation: references
- `ambiente CLI` → `SUPERVISOR_STATE.md`  [AMBIGUOUS]
  docs/complete/phantom-foley-01/SUPERVISOR_STATE.md · relation: references
- `SwiftAcervo (shared models / CDN download)` → `Verify with counsel — open licensing ambiguities`  [AMBIGUOUS]
  README.md · relation: conceptually_related_to
- `Release workflow` → `ACCEPTANCE.md — Stable Audio integration`  [AMBIGUOUS]
  docs/ACCEPTANCE.md · relation: references

## Knowledge Gaps
- **177 isolated node(s):** `acervo-ci-cache-key.sh script`, `Bool`, `Double`, `UInt64`, `Int` (+172 more)
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
- **What is the exact relationship between `SwiftAcervo (shared models / CDN download)` and `Verify with counsel — open licensing ambiguities`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Release workflow` and `ACCEPTANCE.md — Stable Audio integration`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **Why does `AmbienteEngine` connect `Model Config Types` to `Golden Parity Strategy`?**
  _High betweenness centrality (0.098) - this node is a cross-community bridge._
- **Why does `withResolvedAcervoModelsDirectory()` connect `Acervo Test Directory Gate` to `Model Config Types`, `T5Gemma Text Encoder`, `Procedural Ambient Generator`?**
  _High betweenness centrality (0.065) - this node is a cross-community bridge._