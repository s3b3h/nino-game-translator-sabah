// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.content.Context;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;

/** TV'nin HDMI girişleri; uygulama içi mod ve katman modu ortak kullanır. */
final class HdmiInputs {
    private HdmiInputs() {}

    /**
     * TV'nin HDMI girişleri, port numarasına göre sıralı. Girişin numarası sıradaki yeridir.
     * HDMI-CEC ile bağlı cihazlar (PS5 gibi) bazı TV'lerde girişin "alt girişi" olarak ayrıca listelenir; onlar sayılmaz,
     * yoksa numaralar kayar ve iki bağlı giriş görünür. Kimlikler sayısal sıralanır ("HW10", "HW2"den sonra gelir).
     */
    static List<TvInputInfo> list(Context context) {
        List<TvInputInfo> inputs = new ArrayList<>();
        TvInputManager manager = manager(context);
        if (manager == null) return inputs;
        for (TvInputInfo input : manager.getTvInputList()) {
            if (input.getType() == TvInputInfo.TYPE_HDMI && input.isPassthroughInput() && input.getParentId() == null) {
                inputs.add(input);
            }
        }
        Collections.sort(inputs, Comparator.comparingLong((TvInputInfo input) -> lastNumber(input.getId()))
                .thenComparing(TvInputInfo::getId));
        return inputs;
    }

    /** 1'den başlayan numaraya karşılık gelen HDMI girişinin kimliği, yoksa null. */
    static String idForPort(Context context, int port) {
        List<TvInputInfo> inputs = list(context);
        return port >= 1 && port <= inputs.size() ? inputs.get(port - 1).getId() : null;
    }

    /** Giriş seçicide bir satır: numara, kimlik, CEC'in bildirdiği cihaz adı (ör. "PS5"; yoksa null), cihaz bağlı mı. */
    static final class Choice {
        final int port;
        final String id;
        final String device;
        final boolean connected;

        Choice(int port, String id, String device, boolean connected) {
            this.port = port;
            this.id = id;
            this.device = device;
            this.connected = connected;
        }
    }

    /** Giriş seçici için TV'nin HDMI girişleri. Liste boşsa TV HDMI girişlerini uygulamalara açmıyordur. */
    static List<Choice> choices(Context context) {
        List<Choice> choices = new ArrayList<>();
        TvInputManager manager = manager(context);
        if (manager == null) return choices;
        List<TvInputInfo> inputs = list(context);
        for (int i = 0; i < inputs.size(); i++) {
            String id = inputs.get(i).getId();
            boolean connected;
            try {
                connected = manager.getInputState(id) == TvInputManager.INPUT_STATE_CONNECTED;
            } catch (RuntimeException e) {
                connected = false;
            }
            choices.add(new Choice(i + 1, id, deviceName(context, manager, id), connected));
        }
        return choices;
    }

    /**
     * PS5'in girişinin numarası, bulunamazsa 0. Önce HDMI-CEC'in bildirdiği cihaz adına bakılır ("PS5", "PlayStation 5"):
     * birden çok giriş "bağlı" görünen TV'lerde de doğru girişi verir. Ad yoksa tek bağlı HDMI girişi alınır.
     */
    static int consolePort(Context context) {
        TvInputManager manager = manager(context);
        if (manager == null) return 0;
        List<TvInputInfo> inputs = list(context);
        for (int i = 0; i < inputs.size(); i++) {
            if (looksLikeConsole(deviceName(context, manager, inputs.get(i).getId()))) return i + 1;
        }
        int found = 0;
        for (int i = 0; i < inputs.size(); i++) {
            if (manager.getInputState(inputs.get(i).getId()) != TvInputManager.INPUT_STATE_CONNECTED) continue;
            if (found != 0) return 0;
            found = i + 1;
        }
        return found;
    }

    /**
     * Nino: PS5'in hangi HDMI'de olduğu, ekranda "HDMI n'e geçin" demek için. Önce kullanıcının TV'de girişe verdiği ad
     * ("PS5", "PlayStation"), sonra tek bağlı giriş; bilinmiyorsa port 0 (ekranda numara yazılmaz, tahmin edilmez).
     * Sonuç JSON: {"port": n, "label": "…"}.
     */
    static String consoleHint(Context context) {
        List<TvInputInfo> inputs = list(context);
        for (int i = 0; i < inputs.size(); i++) {
            String label = labelOf(context, inputs.get(i));
            String plain = label.toLowerCase(java.util.Locale.ROOT).replace(" ", "");
            if (plain.contains("ps5") || plain.contains("playstation")) return hint(i + 1, label);
        }
        return hint(consolePort(context), "");
    }

    private static String labelOf(Context context, TvInputInfo input) {
        try {
            CharSequence custom = input.loadCustomLabel(context);
            if (custom != null && custom.length() > 0) return custom.toString();
        } catch (RuntimeException ignored) { /* bazı TV'ler desteklemez */ }
        return "";
    }

    private static String hint(int port, String label) {
        String safe = label.replace("\\", "").replace("\"", "");
        return "{\"port\":" + port + ",\"label\":\"" + safe + "\"}";
    }

    /** Girişte bir cihaz var mı; TV bunu bildirmiyorsa var sayılır. */
    static boolean hasSource(Context context, String id) {
        TvInputManager manager = manager(context);
        if (manager == null || id == null) return true;
        try {
            return manager.getInputState(id) != TvInputManager.INPUT_STATE_DISCONNECTED;
        } catch (RuntimeException e) {
            return true;
        }
    }

    /** Girişin altında HDMI-CEC ile görünen cihazın adı (alt girişin etiketi), yoksa null. */
    private static String deviceName(Context context, TvInputManager manager, String parentId) {
        try {
            for (TvInputInfo input : manager.getTvInputList()) {
                if (!parentId.equals(input.getParentId())) continue;
                CharSequence label = input.loadLabel(context);
                if (label != null && label.toString().trim().length() > 0) return label.toString().trim();
            }
        } catch (RuntimeException ignored) {
        }
        return null;
    }

    /** CEC cihaz adı bir PlayStation mı ("PS5", "PlayStation 5", "SONY PS5"). */
    static boolean looksLikeConsole(String name) {
        if (name == null) return false;
        String plain = name.toLowerCase(Locale.ROOT).replace(" ", "");
        return plain.contains("ps5") || plain.contains("playstation");
    }

    private static TvInputManager manager(Context context) {
        return (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
    }

    /** Kimliğin sonundaki sayı ("…/HW15" → 15); yoksa en sona konur. */
    static long lastNumber(String id) {
        int end = id.length();
        while (end > 0 && !Character.isDigit(id.charAt(end - 1))) end--;
        int start = end;
        while (start > 0 && Character.isDigit(id.charAt(start - 1))) start--;
        if (start == end) return Long.MAX_VALUE;
        try { return Long.parseLong(id.substring(start, end)); } catch (NumberFormatException e) { return Long.MAX_VALUE; }
    }
}
