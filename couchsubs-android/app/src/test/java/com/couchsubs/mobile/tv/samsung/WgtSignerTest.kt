// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.mobile.tv.samsung

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import javax.xml.parsers.DocumentBuilderFactory
import org.apache.xml.security.Init
import org.apache.xml.security.signature.XMLSignature
import org.apache.xml.security.signature.XMLSignatureInput
import org.apache.xml.security.utils.resolver.ResourceResolverContext
import org.apache.xml.security.utils.resolver.ResourceResolverSpi

/**
 * Paket imzası: Apache Santuario'nun XML imza doğrulayıcısı (yalnız testlerde) imzayı, bütün dosya özetlerini ve
 * `#prop` nesnesinin C14N 1.1 özetini kabul etmeli. Böylece elle üretilen kanonik biçim bağımsız olarak denetlenir.
 */
class WgtSignerTest {
    private val files = linkedMapOf(
        "config.xml" to "<?xml version=\"1.0\"?>\n<widget id=\"x\"><name>CouchSubs</name></widget>\n".toByteArray(),
        "index.html" to "<!doctype html><script src=\"\$WEBAPIS/webapis/webapis.js\"></script>".toByteArray(),
        "app.js" to "var a = 1 & 2 < 3;\r\n".toByteArray(),
        "icon.png" to ByteArray(3000) { (it * 7).toByte() },
    )

    private fun wgt(extra: Map<String, ByteArray> = emptyMap()): ByteArray {
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            for ((name, data) in files + extra) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(data)
                zip.closeEntry()
            }
        }
        return out.toByteArray()
    }

    private val authorKey = TestCertificates.rsa()
    private val author = TestCertificates.issue("CN=CouchSubs", authorKey.public)
    private val distributor = TestCertificates.issue("CN=TizenSDK", authorKey.public)

    /** İmzalı paketin bütün dosyaları, sırasıyla (readEntries imza dosyalarını atladığı için zip baştan okunur). */
    private fun signed(input: ByteArray = wgt()): List<WgtSigner.Entry> {
        val output = WgtSigner.sign(input,
            WgtSigner.Signer(authorKey.private, listOf(author, TestCertificates.ca)),
            WgtSigner.Signer(authorKey.private, listOf(distributor, TestCertificates.ca)))
        val all = ArrayList<WgtSigner.Entry>()
        java.util.zip.ZipInputStream(ByteArrayInputStream(output)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                all.add(WgtSigner.Entry(entry.name, zip.readBytes()))
            }
        }
        return all
    }

    @Test
    fun signaturesComeFirstAndOriginalOrderIsKept() {
        val names = signed().map { it.name }
        assertEquals(listOf("author-signature.xml", "signature1.xml") + files.keys, names)
    }

    @Test
    fun authorAndDistributorSignaturesValidate() {
        val entries = signed().associate { it.name to it.data }
        val authorRefs = validate(entries.getValue("author-signature.xml"), author, entries)
        assertEquals(files.keys.toList() + "#prop", authorRefs)
        val distributorRefs = validate(entries.getValue("signature1.xml"), distributor, entries)
        assertEquals(listOf("author-signature.xml") + files.keys + "#prop", distributorRefs)
    }

    @Test
    fun oldSignaturesAreReplaced() {
        val stale = mapOf("author-signature.xml" to "eski".toByteArray(), "signature1.xml" to "eski".toByteArray())
        val entries = signed(wgt(stale))
        assertEquals(2, entries.count { it.name.endsWith(".xml") && it.name != "config.xml" })
        val map = entries.associate { it.name to it.data }
        validate(map.getValue("signature1.xml"), distributor, map)
    }

    @Test
    fun signatureXmlHasTizenRolesAndChainWithoutRoot() {
        val entries = signed().associate { it.name to String(it.data, Charsets.UTF_8) }
        val authorXml = entries.getValue("author-signature.xml")
        val distributorXml = entries.getValue("signature1.xml")
        assertTrue(authorXml.startsWith("<Signature xmlns=\"http://www.w3.org/2000/09/xmldsig#\" Id=\"AuthorSignature\">"))
        assertTrue(authorXml.contains("<dsp:Role URI=\"http://www.w3.org/ns/widgets-digsig#role-author\"></dsp:Role>"))
        assertTrue(distributorXml.contains("Id=\"DistributorSignature\""))
        assertTrue(distributorXml.contains("#role-distributor"))
        assertFalse(authorXml.startsWith("<?xml"))
        // Zincir verildiği gibi yazılır (yaprak önce); çağıran kökü koymaz (SamsungCertificates.chain).
        val document = parse(authorXml.toByteArray())
        val certificates = document.getElementsByTagNameNS("http://www.w3.org/2000/09/xmldsig#", "X509Certificate")
        assertEquals(2, certificates.length)
        val first = CertificateFactory.getInstance("X.509").generateCertificate(
            ByteArrayInputStream(Base64.getMimeDecoder().decode(certificates.item(0).textContent.trim()))) as X509Certificate
        assertEquals(author, first)
        assertTrue(certificates.item(0).textContent.startsWith("\n"))
    }

    @Test
    fun attributeEscapingFollowsCanonicalXml() {
        assertEquals("a&amp;b&lt;c&quot;d&#x9;&#xA;&#xD;>", WgtSigner.attr("a&b<c\"d\t\n\r>"))
    }

    /** İmzayı doğrular; doğrulanan referansların URI'leri döner. */
    private fun validate(xml: ByteArray, certificate: X509Certificate, entries: Map<String, ByteArray>): List<String> {
        val document = parse(xml)
        val root = document.documentElement
        val prop = root.getElementsByTagNameNS("http://www.w3.org/2000/09/xmldsig#", "Object").item(0) as Element
        prop.setIdAttributeNS(null, "Id", true)
        Init.init()
        val signature = XMLSignature(root, "", false)
        // Paketin dosyaları (URI = zip'teki ad) testteki haritadan okunur; "#prop" Santuario'nun kendi çözücüsüyle.
        signature.addResourceResolver(object : ResourceResolverSpi() {
            override fun engineCanResolveURI(context: ResourceResolverContext) =
                context.uriToResolve != null && !context.uriToResolve.startsWith("#") && context.uriToResolve in entries
            override fun engineResolveURI(context: ResourceResolverContext) =
                XMLSignatureInput(entries.getValue(context.uriToResolve))
        })
        val valid = signature.checkSignatureValue(certificate.publicKey)
        val info = signature.signedInfo
        val uris = (0 until info.length).map { info.item(it).uri }
        val broken = (0 until info.length).filter { runCatching { !info.getVerificationResult(it) }.getOrDefault(true) }.map { uris[it] }
        assertTrue("imza geçersiz; bozuk referanslar: $broken", valid)
        return uris
    }

    private fun parse(xml: ByteArray) = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }
        .newDocumentBuilder().parse(ByteArrayInputStream(xml))
}
