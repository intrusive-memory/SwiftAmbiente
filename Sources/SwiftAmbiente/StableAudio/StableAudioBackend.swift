// StableAudioBackend.swift
//
// Namespace placeholder for the Stable Audio 3 Small SFX backend (WU2).
//
// Sortie 5 committed the execution strategy: translate Stability AI's official
// Python-MLX reference into MLX Swift (see STRATEGY.md). This file exists only to
// prove the newly added `ml-explore/mlx-swift` products link into the StableAudio
// module. The actual network (config loading, T5Gemma encoder, DiT sampler,
// SAME-S decoder, generator conformance) lands in Sorties 6–10 — do NOT implement
// inference logic here.

import MLX
import MLXFFT
import MLXNN
import MLXRandom

/// Namespace for the Stable Audio backend. Intentionally empty at Sortie 5;
/// populated by Sorties 6–10.
public enum StableAudioBackend {}
