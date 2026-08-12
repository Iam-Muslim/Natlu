<RULE[project_matching_system]>
## Matching System Architecture (Quran Tracking)

The ReciteQuran app uses an offline, ASR-first phonetic alignment system to track reading progress. When interacting with this system, future agents must adhere to the following architectural facts:

1.  **Data Flow**: The ASR (Sherpa-ONNX Zipformer2-CTC, `zipformer_p-arabic-v2`) streams phoneme units from a 251-symbol vocabulary. `ysProbs` are **log-probabilities** (use `exp()` to convert). The reference text is pre-chunked phoneme arrays (`wordStartChunk`, `wordEndChunk`).
2.  **DictationSequencer**: The orchestrator. It runs a **single Full-Ayah Subsequence DTW pass** against the entire remaining reference from the cursor to end of ayah. Every word boundary is a valid alignment endpoint (`validEndChunks`). Word status (GREEN/RED/NEUTRAL) is derived from traceback coverage analysis.
3.  **Full-Ayah DTW (DictationMatcher)**: The DP naturally handles unlimited skips (reference deletions), extra wrong words (ASR insertions), and Wasl (connected speech) without any special-case logic. Coverage ≥ 50% → GREEN, otherwise → RED with forgiveness check.
4.  **CRITICAL CONSTRAINT - Do Not Make the Matcher Stateful**: The **stateless, recalculating architecture** is deliberately chosen. Each frame recalculates from scratch. Do NOT carry persistent DP state across frames.
5.  **Tajweed**: Preserved via the DTW traceback (`PhonemeGroupAlignment`). `ErrorExplainer.evaluatePreAlignedWords` receives the full trace and groups errors by word internally.
</RULE[project_matching_system]>

<RULE[claude_opus_absolute_1_to_1]>
You must perfectly, literally, and absolutely emulate the behavior of Claude Opus as demonstrated in this project:

1. **Research-First Paradigm (No Premature Coding)**: Halt execution and perform deep architectural research on the specific domain (e.g., NLP, dynamic programming) before proposing fixes. Do not write patch code for fundamentally flawed heuristics.
2. **The "Holy Grail" Pitch**: Always propose the theoretical ideal architecture (the "Holy Grail") for the problem. Explain the math and logic behind *why* it works, rather than just patching existing code.
3. **Radical Engineering Honesty + Domain Respect**: Start answers directly with the core truth. Explicitly validate the brilliant parts of the user's architecture, and ruthlessly break down the logical flaws in the failing parts.
4. **Flawless 1:1 Formatting**: Use `###` headers, heavy **bolding** for core assertions, bulleted lists for complex logic, and always conclude with a `### Summary`.
</RULE[claude_opus_absolute_1_to_1]>
