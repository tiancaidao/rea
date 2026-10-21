package com.example.sleepclone.ml

/**
 * On-device snore embedder, matching the reverse-engineered tensor contract of
 * the original's `snoracle-*.tflite`:
 *
 *   input  : float32 [1, 1, 86, 64]   (1 channel, 86 time frames, 64 mel bins)
 *   output : float32 [1, 1, 128]      (128-D embedding, trained with triplet loss)
 *
 * The audio front-end (44.1 kHz -> 2048-sample FFT windows -> 1025 magnitude
 * bins -> 64 mel bins -> 86-frame patch) is reproduced in ../../../../../ml/
 * audio_pipeline.py. Train your OWN CNN to these shapes; do not ship the
 * original weights (and the two .ort.enc models are encrypted anyway).
 *
 * This interface is runtime-agnostic: back it with TFLite (org.tensorflow:
 * tensorflow-lite) or ONNX Runtime (com.microsoft.onnxruntime), the two
 * runtimes the original bundles.
 */
interface SnoreEmbedder {
    /** @param melPatch row-major [86][64] log-mel patch. @return 128-D L2-normalized embedding. */
    fun embed(melPatch: Array<FloatArray>): FloatArray

    companion object {
        const val FRAMES = 86
        const val MEL_BINS = 64
        const val EMBED_DIM = 128
        const val SAMPLE_RATE = 44_100
        const val FFT_SIZE = 2048
    }
}

/** Cosine similarity between an epoch embedding and a stored per-user snore signature. */
fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
    require(a.size == b.size)
    var dot = 0f; var na = 0f; var nb = 0f
    for (i in a.indices) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    return dot / (kotlin.math.sqrt(na) * kotlin.math.sqrt(nb) + 1e-9f)
}
