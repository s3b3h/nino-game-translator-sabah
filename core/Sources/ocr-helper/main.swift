// SPDX-License-Identifier: AGPL-3.0-only

// Nino: yedek okuyucunun (ayrı süreçte yazı tanıma, `OcrHelper`) testlerde kullanılan çalıştırılabilir hâli.
// Uygulamada yardımcı, uygulamanın kendi dosyasıdır (`--ocr-helper`).

import CouchSubsCore
import Foundation

#if os(macOS)
OcrHelper.runAsHelper()
#endif
