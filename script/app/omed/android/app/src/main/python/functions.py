
import sys


def is_android():
    # Chaquopy fournit cette fonction sur Android.
    return hasattr(sys, "getandroidapilevel")


async def handle_message(data: dict, play_soundfont_note=None) -> dict:
    command = data.get("command")

    if command == "playSound":
        instrument = data.get("instrument", 0)
        note = data.get("note", 60)
        duration = data.get("duration", 500)

        # Le son via FluidSynth est réservé au PC.
        if not is_android() and play_soundfont_note is not None:
            play_soundfont_note(instrument, note, duration)

        return {
            "command": "playSound",
            "bank": 1,
            "result": "ok",
            "instrument": instrument,
            "note": note,
            "duration": duration,
        }

    return {
        "command": command,
        "result": "error",
        "message": "Commande inconnue",
    }
