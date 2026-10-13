package app.winters.octo.sound

import org.junit.Assert.assertEquals
import org.junit.Test

// The output music goes to keeps one key however Android lists it, so its
// settings follow it.
class AudioOutputTest {
    private fun bt(name: String, address: String) = OutputDevice(OutputKind.Bluetooth, name, address)

    @Test
    fun earbudsListedTwiceAreOneOutputInEitherOrder() {
        val left = bt("Enco X3", "AA:01")
        val right = bt("Enco X3", "AA:02")
        val speaker = OutputDevice(OutputKind.Other, "Phone", "")
        val one = outputFor(listOf(speaker, left, right))
        val other = outputFor(listOf(right, speaker, left))
        assertEquals("bluetooth:Enco X3", one.key)
        assertEquals(one, other)
        assertEquals("Enco X3", one.label)
        assertEquals(listOf("bluetooth:AA:01", "bluetooth:AA:02"), one.formerKeys)
    }

    @Test
    fun aNamelessDeviceIsKnownByItsAddress() {
        val out = outputFor(listOf(bt("", "BB:02"), bt("", "BB:01")))
        assertEquals("bluetooth:BB:01", out.key)
        assertEquals("Bluetooth", out.label)
        assertEquals(listOf("bluetooth:BB:02"), out.formerKeys)
    }

    @Test
    fun bluetoothComesBeforeUsbAndACable() {
        val devices = listOf(
            OutputDevice(OutputKind.Wired, "", ""),
            OutputDevice(OutputKind.Usb, "DAC", ""),
            bt("Car", "CC:01"),
        )
        assertEquals("bluetooth:Car", outputFor(devices).key)
        assertEquals(AudioOutput("usb:DAC", "DAC"), outputFor(devices.dropLast(1)))
        assertEquals(AudioOutput("wired", "Headphones"), outputFor(devices.take(1)))
    }

    @Test
    fun withNothingConnectedItIsTheSpeaker() {
        assertEquals(PhoneSpeaker, outputFor(emptyList()))
        assertEquals(PhoneSpeaker, outputFor(listOf(OutputDevice(OutputKind.Other, "Earpiece", ""))))
    }

    @Test
    fun onlyWornOutputsCountAsHeadphones() {
        assertEquals(false, PhoneSpeaker.headphones)
        assertEquals(true, outputFor(listOf(bt("Enco X3", "AA:01"))).headphones)
        assertEquals(true, outputFor(listOf(OutputDevice(OutputKind.Usb, "DAC", ""))).headphones)
        assertEquals(true, outputFor(listOf(OutputDevice(OutputKind.Wired, "", ""))).headphones)
        val speaker = OutputDevice(OutputKind.Bluetooth, "Boom", "DD:01", speaker = true)
        assertEquals(false, outputFor(listOf(speaker)).headphones)
    }

    @Test
    fun settingsSavedUnderAnOldAddressAreFound() {
        val out = outputFor(listOf(bt("Enco X3", "AA:01"), bt("Enco X3", "AA:02")))
        assertEquals(7, savedFor(mapOf("bluetooth:AA:02" to 7), out))
        // The output's own key wins over an old one.
        assertEquals(9, savedFor(mapOf("bluetooth:AA:02" to 7, "bluetooth:Enco X3" to 9), out))
        assertEquals(null, savedFor(mapOf("bluetooth:ZZ:99" to 7), out))
    }
}
