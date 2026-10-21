package com.example.sleepclone.net

import com.example.sleepclone.data.InsightsDto
import com.example.sleepclone.data.PaywallDto
import com.example.sleepclone.data.RemoteConfigDto
import com.example.sleepclone.data.SessionUploadRequest
import com.example.sleepclone.data.SessionUploadResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST

/**
 * Retrofit surface mirrored from the reverse-engineered app
 * (Retrofit2 + OkHttp were confirmed in the DEX). Point baseUrl at the local
 * mock-api (http://10.0.2.2:8787 from the emulator) during the rebuild.
 *
 * Observed backend split in the original:
 *   - auth / client-auth.sdk.sleepcycle.com  -> Ory Kratos + Hydra
 *   - teratron-*.run.app                      -> session upload
 *   - syndicate-*.run.app                     -> insights
 *   - resources.sdk.sleepcycle.com            -> remote config / dynamic paywall
 * The original signs requests natively (libsigner.so); implement your own
 * signing interceptor instead of reusing theirs.
 */
interface SleepCloudApi {

    @GET("sessions/whoami")
    suspend fun whoami(): Map<String, Any?>

    @GET("v1/config")
    suspend fun remoteConfig(): RemoteConfigDto

    @GET("v1/paywall")
    suspend fun paywall(): PaywallDto

    @POST("v1/sessions")
    suspend fun uploadSession(@Body req: SessionUploadRequest): SessionUploadResponse

    @GET("v1/insights")
    suspend fun insights(): InsightsDto
}
