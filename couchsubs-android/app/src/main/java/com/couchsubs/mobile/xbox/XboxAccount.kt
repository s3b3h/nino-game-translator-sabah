// SPDX-License-Identifier: AGPL-3.0-only
// Nino: bu dosya Nino için sıfırdan yazıldı.
package com.couchsubs.mobile.xbox

/** Kayıtlı Microsoft girişi ve seçili Xbox; [AppSettings] bunu gizli depoda (Keystore) tutar. */
interface XboxStore {
    var xboxRefreshToken: String?
    var xboxConsole: XboxConsole?
}

/**
 * Uzun ömürlü Microsoft jetonundan bir oturumluk her şeyi üretir. Microsoft yenileme jetonunu her kullanımda
 * değiştirebilir; yenisi hemen kaydedilir (eskisi bir süre sonra geçersiz olur).
 */
class XboxAccount(private val store: XboxStore, private val auth: XboxAuth = XboxAuth()) {
    val signedIn get() = !store.xboxRefreshToken.isNullOrEmpty()

    /** Giriş kodu onaylanınca. */
    fun save(tokens: MicrosoftTokens) {
        store.xboxRefreshToken = tokens.refreshToken
    }

    fun signOut() {
        store.xboxRefreshToken = null
        store.xboxConsole = null
    }

    /** Bölge sunucusu ve yayın jetonu (bloklar). Giriş geçersizse kayıt silinir ve [XboxStep.SIGNED_OUT] atılır. */
    fun streamHost(): StreamHost {
        val tokens = refresh()
        return auth.streamHost(tokens.accessToken)
    }

    /** Konsolun "bağlan" adımı için aktarım jetonu. */
    fun transferToken(): String {
        val refresh = store.xboxRefreshToken ?: throw XboxException(XboxStep.SIGNED_OUT)
        return try {
            auth.transferToken(refresh)
        } catch (error: XboxException) {
            if (error.step == XboxStep.SIGNED_OUT) store.xboxRefreshToken = null
            throw error
        }
    }

    fun consoles(): List<XboxConsole> = XboxApi(streamHost()).consoles()

    private fun refresh(): MicrosoftTokens {
        val refresh = store.xboxRefreshToken ?: throw XboxException(XboxStep.SIGNED_OUT)
        return try {
            auth.refresh(refresh).also { if (it.refreshToken != refresh) store.xboxRefreshToken = it.refreshToken }
        } catch (error: XboxException) {
            if (error.step == XboxStep.SIGNED_OUT) store.xboxRefreshToken = null
            throw error
        }
    }
}
