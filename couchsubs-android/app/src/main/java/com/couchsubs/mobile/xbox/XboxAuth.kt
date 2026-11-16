// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı. Akış (Microsoft cihaz kodu girişi → Xbox Live → XSTS → xHome jetonu)
// açık kaynak xal-node ve Greenlight'tan (MIT, UnknownSKL) öğrenildi; bkz. THIRD-PARTY-NOTICES.md.
package com.couchsubs.mobile.xbox

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.net.URLEncoder

/** Telefonda gösterilen giriş kodu: kullanıcı [verificationUri] adresine gidip [userCode]'u yazar. */
data class DeviceCode(val userCode: String, val deviceCode: String, val verificationUri: String, val expiresInSeconds: Int, val intervalSeconds: Int)

/** Microsoft hesabının uzun ömürlü jetonu (kaydedilir) ve kısa ömürlü erişim jetonu. */
data class MicrosoftTokens(val accessToken: String, val refreshToken: String, val expiresAt: Long)

/** Ev yayını için gereken her şey: bölge sunucusu ve yayın jetonu. */
data class StreamHost(val baseUri: String, val token: String, val expiresAt: Long)

/** Kodu bekleme sonucu. */
sealed class DeviceCodePoll {
    data object Pending : DeviceCodePoll()
    data object SlowDown : DeviceCodePoll()
    data class Done(val tokens: MicrosoftTokens) : DeviceCodePoll()
    /** Süre doldu ya da kullanıcı reddetti; yeni kod alınmalı. */
    data class Failed(val reason: String) : DeviceCodePoll()
}

/**
 * Microsoft hesabı ile Xbox ev yayını izni. Şifre Nino'ya hiç girilmez: telefon bir kod gösterir, kullanıcı
 * microsoft.com/link sayfasında (istediği cihazda) kodu yazıp kendi hesabıyla onaylar.
 */
class XboxAuth(private val http: XboxHttp = XboxHttp.system, private val clock: () -> Long = System::currentTimeMillis) {
    companion object {
        // Xbox uygulamalarının herkese açık istemci kimliği (xal-node/Greenlight'taki değer). Nino'nun kendi Azure
        // uygulaması olmadığı için bunu kullanır; bkz. docs/nino/xbox-arastirma.md › Riskler.
        const val CLIENT_ID = "1f907974-e22b-4810-a9de-d9647380c97e"
        private const val SCOPE = "xboxlive.signin openid profile offline_access"
        private const val LOGIN = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
        private const val TRANSFER_SCOPE = "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"
        const val GSSV_RELYING_PARTY = "http://gssv.xboxlive.com/"
        const val HOME_OFFERING = "xhome"

        private val form = mapOf("Content-Type" to "application/x-www-form-urlencoded")
        private val xboxHeaders = mapOf(
            "Content-Type" to "application/json", "Accept" to "application/json", "x-xbl-contract-version" to "1",
            "Cache-Control" to "no-cache", "Origin" to "https://www.xbox.com", "Referer" to "https://www.xbox.com/",
        )

        fun encode(items: List<Pair<String, String>>) =
            items.joinToString("&") { URLEncoder.encode(it.first, "UTF-8") + "=" + URLEncoder.encode(it.second, "UTF-8") }

        /** Bölgelerden varsayılanı (yoksa ilki). */
        fun defaultRegion(regions: JSONArray?): String? {
            if (regions == null || regions.length() == 0) return null
            for (i in 0 until regions.length()) {
                val region = regions.optJSONObject(i) ?: continue
                if (region.optBoolean("isDefault")) return region.optString("baseUri").takeIf { it.isNotEmpty() }
            }
            return regions.optJSONObject(0)?.optString("baseUri")?.takeIf { it.isNotEmpty() }
        }
    }

    fun requestDeviceCode(): DeviceCode {
        val reply = http.send("POST", "$LOGIN/devicecode", form, encode(listOf("client_id" to CLIENT_ID, "scope" to SCOPE)))
        val json = parse(reply, XboxStep.SIGN_IN)
        return try {
            DeviceCode(json.getString("user_code"), json.getString("device_code"), json.optString("verification_uri", "https://www.microsoft.com/link"),
                json.optInt("expires_in", 900), json.optInt("interval", 5).coerceAtLeast(1))
        } catch (error: JSONException) {
            throw XboxException(XboxStep.SIGN_IN, reply.status, "bad device code response")
        }
    }

    /** Kullanıcı kodu onayladı mı? Bir kez sorar; çağıran [DeviceCode.intervalSeconds] arayla yineler. */
    fun pollDeviceCode(code: DeviceCode): DeviceCodePoll {
        val reply = http.send("POST", "$LOGIN/token", form, encode(listOf(
            "grant_type" to "urn:ietf:params:oauth:grant-type:device_code", "client_id" to CLIENT_ID, "device_code" to code.deviceCode)))
        val json = try { JSONObject(reply.body) } catch (error: JSONException) { JSONObject() }
        if (reply.ok) return DeviceCodePoll.Done(tokens(json))
        return when (val error = json.optString("error")) {
            "authorization_pending" -> DeviceCodePoll.Pending
            "slow_down" -> DeviceCodePoll.SlowDown
            "" -> DeviceCodePoll.Failed("HTTP ${reply.status}")
            else -> DeviceCodePoll.Failed(error)
        }
    }

    /** Kayıtlı uzun ömürlü jetondan yeni erişim jetonu. Jeton geçersizse [XboxStep.SIGNED_OUT]. */
    fun refresh(refreshToken: String): MicrosoftTokens {
        val reply = http.send("POST", "$LOGIN/token", form, encode(listOf(
            "client_id" to CLIENT_ID, "grant_type" to "refresh_token", "refresh_token" to refreshToken, "scope" to SCOPE)))
        if (reply.status == 400 || reply.status == 401) throw XboxException(XboxStep.SIGNED_OUT, reply.status, errorText(reply.body))
        return tokens(parse(reply, XboxStep.SIGN_IN), fallbackRefresh = refreshToken)
    }

    /** Microsoft erişim jetonundan Xbox Live kullanıcı jetonu, oradan ev yayını (xHome) jetonu ve bölge sunucusu. */
    fun streamHost(accessToken: String): StreamHost {
        val user = http.send("POST", "https://user.auth.xboxlive.com/user/authenticate", xboxHeaders, JSONObject()
            .put("Properties", JSONObject().put("AuthMethod", "RPS").put("RpsTicket", "d=$accessToken").put("SiteName", "user.auth.xboxlive.com"))
            .put("RelyingParty", "http://auth.xboxlive.com").put("TokenType", "JWT").toString())
        val userToken = parse(user, XboxStep.XBOX_LIVE).optString("Token").ifEmpty { throw XboxException(XboxStep.XBOX_LIVE, user.status, "no user token") }
        val xsts = http.send("POST", "https://xsts.auth.xboxlive.com/xsts/authorize", xboxHeaders, JSONObject()
            .put("Properties", JSONObject().put("SandboxId", "RETAIL").put("UserTokens", JSONArray().put(userToken)))
            .put("RelyingParty", GSSV_RELYING_PARTY).put("TokenType", "JWT").toString())
        // 401 + XErr: hesapta Xbox profili yok ya da çocuk hesabı izni gerekiyor.
        val gssv = parse(xsts, XboxStep.XBOX_LIVE).optString("Token").ifEmpty { throw XboxException(XboxStep.XBOX_LIVE, xsts.status, "no xsts token") }
        val login = http.send("POST", "https://$HOME_OFFERING.gssv-play-prod.xboxlive.com/v2/login/user",
            mapOf("Content-Type" to "application/json", "Cache-Control" to "no-store, must-revalidate, no-cache", "x-gssv-client" to "XboxComBrowser"),
            JSONObject().put("token", gssv).put("offeringId", HOME_OFFERING).toString())
        val json = parse(login, XboxStep.STREAMING)
        val token = json.optString("gsToken").ifEmpty { throw XboxException(XboxStep.STREAMING, login.status, "no gsToken") }
        val base = defaultRegion(json.optJSONObject("offeringSettings")?.optJSONArray("regions"))
            ?: throw XboxException(XboxStep.STREAMING, login.status, "no region")
        return StreamHost(base.trimEnd('/'), token, clock() + json.optLong("durationInSeconds", 3600) * 1000)
    }

    /** Konsolun "bağlan" adımı için tek kullanımlık aktarım jetonu (login.live.com). */
    fun transferToken(refreshToken: String): String {
        val reply = http.send("POST", "https://login.live.com/oauth20_token.srf", form, encode(listOf(
            "client_id" to CLIENT_ID, "scope" to TRANSFER_SCOPE, "grant_type" to "refresh_token", "refresh_token" to refreshToken)))
        if (reply.status == 400 || reply.status == 401) throw XboxException(XboxStep.SIGNED_OUT, reply.status, errorText(reply.body))
        return parse(reply, XboxStep.SESSION).optString("access_token").ifEmpty { throw XboxException(XboxStep.SESSION, reply.status, "no transfer token") }
    }

    private fun tokens(json: JSONObject, fallbackRefresh: String? = null): MicrosoftTokens {
        val access = json.optString("access_token").ifEmpty { throw XboxException(XboxStep.SIGN_IN, null, "no access token") }
        val refresh = json.optString("refresh_token").ifEmpty { fallbackRefresh ?: throw XboxException(XboxStep.SIGN_IN, null, "no refresh token") }
        return MicrosoftTokens(access, refresh, clock() + json.optLong("expires_in", 3600) * 1000)
    }

    private fun parse(reply: HttpReply, step: XboxStep): JSONObject {
        if (!reply.ok) throw XboxException(step, reply.status, errorText(reply.body))
        return try { JSONObject(reply.body) } catch (error: JSONException) { throw XboxException(step, reply.status, "not json") }
    }

    private fun errorText(body: String): String? = try {
        val json = JSONObject(body)
        json.optString("error_description").ifEmpty { json.optString("error") }.ifEmpty { json.optString("XErr") }.ifEmpty { null }
    } catch (error: JSONException) {
        body.take(120).ifEmpty { null }
    }
}
