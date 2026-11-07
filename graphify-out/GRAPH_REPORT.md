# Graph Report - .  (2026-11-07)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 602 nodes · 1028 edges · 37 communities (31 shown, 6 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 58 edges (avg confidence: 0.81)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `71d530de`
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

## God Nodes (most connected - your core abstractions)
1. `CodingKeys` - 26 edges
2. `StableAudioDiT` - 18 edges
3. `MLXArray` - 17 edges
4. `withResolvedAcervoModelsDirectory()` - 17 edges
5. `StableAudioSAMESDecoder` - 16 edges
6. `MLXArray` - 15 edges
7. `T5GemmaTextEncoder` - 15 edges
8. `AmbienteCommand` - 14 edges
9. `StableAudioGenerator` - 14 edges
10. `ProceduralAmbienteGenerator` - 13 edges

## Surprising Connections (you probably didn't know these)
- `Tests workflow (unit tests)` --references--> `ProceduralAmbienteGenerator`  [EXTRACTED]
  .github/workflows/tests.yml → AGENTS.md
- `ACCEPTANCE.md — Stable Audio integration` --references--> `ambiente CLI`  [AMBIGUOUS]
  docs/ACCEPTANCE.md → AGENTS.md
- `T5GemmaTextEncoder` --conceptually_related_to--> `Google Gemma Terms of Use`  [INFERRED]
  Sources/SwiftAmbiente/StableAudio/STRATEGY.md → README.md
- `ACCEPTANCE.md — Stable Audio integration` --references--> `Release workflow`  [AMBIGUOUS]
  docs/ACCEPTANCE.md → .github/workflows/release.yml
- `AGENTS.md — SwiftAmbiente` --references--> `STRATEGY.md — MLX Swift vs CoreML decision`  [EXTRACTED]
  AGENTS.md → Sources/SwiftAmbiente/StableAudio/STRATEGY.md

## Import Cycles
- None detected.

## Communities (37 total, 6 thin omitted)

### Community 0 - "Acervo Test Directory Gate"
Cohesion: 0.05
Nodes (33): CheckedContinuation, Int32, Never, AcervoModelsDirectoryGate, withResolvedAcervoModelsDirectory(), withTempAcervoModelsDirectory(), AmbienteModelManagerTests, LatentSamplerFixture (+25 more)

### Community 1 - "Model Config Types"
Cohesion: 0.07
Nodes (41): CaseIterable, Codable, ConditionerConfig, Conditioning, Decoder, Diffusion, DiffusionConfig, Equatable (+33 more)

### Community 2 - "Golden Audio Comparison"
Cohesion: 0.11
Nodes (19): AudioSpectralDelta, AudioSpectralDelta, ParseError, badTag, notPCM16, sizeMismatch, tooShort, PCMWAV (+11 more)

### Community 3 - "Stable Audio DiT"
Cohesion: 0.22
Nodes (11): Double, Float, Int, MLXArray, StableAudioModelConfig, String, StableAudioDiT, StableAudioDiTConfig (+3 more)

### Community 4 - "Gemma BPE Tokenizer"
Cohesion: 0.11
Nodes (22): CustomStringConvertible, Error, Hashable, LocalizedError, Pair, String, Bool, Int (+14 more)

### Community 5 - "T5Gemma Text Encoder"
Cohesion: 0.20
Nodes (12): Decodable, Float, Int, MLXArray, URL, Block, RawConfig, T5GemmaEncoderConfig (+4 more)

### Community 6 - "Procedural Ambient Generator"
Cohesion: 0.12
Nodes (11): AmbienteGenerator, AmbienteConfig, Bool, Data, Float, GenerationSettings, String, UInt64 (+3 more)

### Community 7 - "Config Coding Keys"
Cohesion: 0.08
Nodes (24): CodingKey, CodingKeys, audioChannels, condDim, conditioning, condTokenDim, config, configs (+16 more)

### Community 8 - "Stable Audio Generator"
Cohesion: 0.13
Nodes (11): AmbienteConfig, Bool, Data, GenerationSettings, R, String, URL, PipelineCache (+3 more)

### Community 9 - "Stable Audio Pipeline"
Cohesion: 0.16
Nodes (12): AmbienteConfig, Data, Double, Float, GenerationSettings, Int, MLXArray, String (+4 more)

### Community 10 - "SAMES Audio Decoder"
Cohesion: 0.27
Nodes (6): Int, MLXArray, String, BlockWeights, DyTWeights, StableAudioSAMESDecoder

### Community 11 - "Ambiente Engine"
Cohesion: 0.15
Nodes (11): AmbienteModelManager, AmbienteConfig, AmbienteGenerator, Data, Double, StableAudioModelRepo, String, UInt64 (+3 more)

### Community 12 - "Latent Generation"
Cohesion: 0.15
Nodes (14): Double, Float, GenerationSettings, Int, MLXArray, StableAudioModelConfig, String, URL (+6 more)

### Community 13 - "Core Library Overview"
Cohesion: 0.16
Nodes (17): PCMWAV parser, ProceduralGeneratorTests, StableAudioGeneratorTests, StableAudioLatentSamplerTests, AmbienteConfig, AmbienteGenerator (backend protocol), GenerationSettings, ProceduralAmbienteGenerator (+9 more)

### Community 14 - "Model Asset Loading"
Cohesion: 0.24
Nodes (11): Int, MLXArray, StableAudioModelConfig, String, URL, StableAudioModelAssets, StableAudioModelLoaderError, configNotFound (+3 more)

### Community 15 - "Golden Parity Strategy"
Cohesion: 0.15
Nodes (16): StableAudioGoldenParityTests, cfg 7.0→1.0 re-record rationale, Golden fixture reproducibility note, golden-rain-on-tin-roof-seed42.wav, GoldenAudioComparison.swift, APG guidance (default 1.0), CoreML conversion (rejected), STRATEGY.md — MLX Swift vs CoreML decision (+8 more)

### Community 16 - "CLI Command"
Cohesion: 0.17
Nodes (8): AmbienteCommand, AsyncParsableCommand, Bool, Double, Int, StableAudioModelRepo, String, UInt64

### Community 17 - "Audio Conditioning Embedders"
Cohesion: 0.28
Nodes (9): DType, Double, Float, Int, MLXArray, String, Assembled, SecondsTotalEmbedder (+1 more)

### Community 18 - "CI Model Integration"
Cohesion: 0.20
Nodes (15): ACCEPTANCE.md — Stable Audio integration, ambiente CLI, AmbienteSceneDescriptor, mlx-swift_Cmlx.bundle (Metal library bundle), SwiftAcervo (shared models / CDN download), acervo-ci-cache-key.sh / acervo-ci-prime.sh, TEST_RUNNER_ACERVO_MODELS_DIR forwarding, Integration Tests workflow (real models) (+7 more)

### Community 19 - "Model Manager"
Cohesion: 0.22
Nodes (8): AcervoError, AmbienteError, AmbienteConfig, AmbienteGenerator, Bool, StableAudioModelRepo, URL, AmbienteModelManager

### Community 20 - "Project Docs and Licensing"
Cohesion: 0.25
Nodes (12): AGENTS.md — SwiftAmbiente, Produciesta (consumer app), Package.swift sibling() helper, SwiftVoxAlta (sibling package), Never swift build/test; use Makefile/xcodebuild, User-owned license-acceptance checklist, Verify-with-counsel licensing ambiguities, README.md — SwiftAmbiente (+4 more)

### Community 21 - "Mission Planning Docs"
Cohesion: 0.21
Nodes (10): AmbienteEngineTests, AmbienteEngine.resolveGenerator, COMPLETE_SwiftAmbiente.md (completion log), EXECUTION_PLAN.md — Operation Phantom Foley, ElevenLabs SFX (rejected), OPERATION PHANTOM FOLEY mission, Stability-AI/stable-audio-3 optimized/mlx reference, T5GemmaTextEncoder (+2 more)

### Community 22 - "T5Gemma Text Conditioner"
Cohesion: 0.24
Nodes (8): GemmaBPETokenizer, Int, MLXArray, String, URL, T5GemmaConditioning, T5GemmaTextConditioner, T5GemmaTextEncoder

### Community 23 - "Flow Sampler"
Cohesion: 0.26
Nodes (8): Bool, Double, Float, Int, MLXArray, UInt64, Void, StableAudioFlowSampler

### Community 24 - "Acervo Test Trait"
Cohesion: 0.20
Nodes (8): Self, SuiteTrait, AcervoEnvironmentTrait, Trait, Test, Bool, Sendable, TestScoping

### Community 25 - "Model CDN Distribution"
Cohesion: 0.22
Nodes (9): AmbienteModelManagerTests, AmbienteEngine, AmbienteError, AmbienteModelManager, StableAudioModelRepo, acervo ship stabilityai/stable-audio-3-small-sfx, CDN slug stabilityai_stable-audio-3-small-sfx, Stable Audio 3 Small SFX model (stabilityai/stable-audio-3-small-sfx) (+1 more)

### Community 27 - "Audio File Writer"
Cohesion: 0.38
Nodes (4): AudioFileWriter, AudioOutputFormat, Data, String

### Community 28 - "WAV Encoding"
Cohesion: 0.33
Nodes (4): Data, Float, Int, WAVWriter

### Community 30 - "CI Model Primer Script"
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
- **137 isolated node(s):** `acervo-ci-cache-key.sh script`, `Bool`, `Double`, `UInt64`, `Int` (+132 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

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
- **Why does `AmbienteEngine` connect `Ambiente Engine` to `CLI Command`, `Model Config Types`?**
  _High betweenness centrality (0.139) - this node is a cross-community bridge._
- **Why does `withResolvedAcervoModelsDirectory()` connect `Acervo Test Directory Gate` to `Stable Audio Generator`, `Golden Audio Comparison`, `Ambiente Engine`?**
  _High betweenness centrality (0.098) - this node is a cross-community bridge._
- **Why does `StableAudioGenerator` connect `Stable Audio Generator` to `Model Manager`, `Procedural Ambient Generator`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._