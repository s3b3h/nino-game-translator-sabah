// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class HdmiInputsTest {
    @Test
    public void cecNamesOfThePs5AreRecognised() {
        assertTrue(HdmiInputs.looksLikeConsole("PS5"));
        assertTrue(HdmiInputs.looksLikeConsole("PlayStation 5"));
        assertTrue(HdmiInputs.looksLikeConsole("SONY PS 5"));
        assertFalse(HdmiInputs.looksLikeConsole("Soundbar"));
        assertFalse(HdmiInputs.looksLikeConsole(null));
    }

    @Test
    public void inputsAreOrderedByTheirNumber() {
        assertEquals(2, HdmiInputs.lastNumber("com.mediatek.tvinput/.hdmi.HDMIInputService/HW2"));
        assertEquals(10, HdmiInputs.lastNumber("…/HW10"));
        assertEquals(Long.MAX_VALUE, HdmiInputs.lastNumber("hdmi"));
    }
}
