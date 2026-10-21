package com.example.sleepclone.data

/**
 * DTOs matching the mock-api (mock-api/server.js). Sleep-phase vocabulary
 * (awake / light / deep / rem) mirrors what the original surfaces in
 * ui.statistics / ui.journal.
 */

data class RemoteConfigDto(
    val features: Map<String, Boolean>,
    val experiments: Map<String, String>,
)

data class PaywallDto(
    val id: String,
    val products: List<Product>,
) {
    data class Product(val sku: String, val price: String, val trialDays: Int)
}

data class SessionUploadRequest(
    val startedAt: Long,
    val endedAt: Long,
    val phases: List<PhasePoint>,
    val snorePercent: Int,
    val movementSamples: Int,
)

data class SessionUploadResponse(val id: String, val status: String)

data class InsightsDto(
    val sleepScore: Int,
    val timeAsleepMin: Int,
    val snorePercent: Int,
    val phases: List<PhasePoint>,
)

data class PhasePoint(val t: Int, val phase: String)

enum class SleepPhase { AWAKE, LIGHT, DEEP, REM }
