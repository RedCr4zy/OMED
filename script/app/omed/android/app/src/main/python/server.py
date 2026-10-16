#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import asyncio
import websockets
import threading
import queue
import sys
import json

from functions import handle_message

import platform

try:
    import pyfluidsynth
    _synth = pyfluidsynth.Synth()
    _sf_id = _synth.sfload("FluidR3_GM.sf2")  # chemin vers ton .sf2
    _synth.start()
    print("FluidSynth initialisé")
except Exception as e:
    print(f"FluidSynth indisponible : {e}")
    _synth = None
    _sf_id = None


def play_soundfont_note(instrument, note, duration_ms=500):
    """Joue une note via FluidSynth (Linux/Windows)."""
    if _synth is None:
        print("Pas de synthé dispo")
        return
    _synth.soundsfont_select(_sf_id)
    _synth.program_select(0, _sf_id, 0, instrument)
    _synth.note_on(0, note, 100)
    import time
    time.sleep(duration_ms / 1000)
    _synth.note_off(0, note)

# ❌ SUPPRIMÉS : import numpy, import sounddevice
# (on les importe à la demande dans play_beep)


def play_beep(freq=440, duration=0.3, volume=0.5):
    """Joue un beep sinusoïdal (non-bloquant)."""
    try:
        import numpy as np
        import sounddevice as sd
    except ImportError:
        print("sounddevice/numpy non disponibles (Android ?)")
        return

    t = np.linspace(0, duration, int(44100 * duration), False)
    wave = (volume * np.sin(2 * np.pi * freq * t)).astype(np.float32)
    sd.play(wave, 44100)
    sd.wait()

# ❌ SUPPRIMÉE la ligne qui jouait un beep à l'import


# ============================================================
# Logs
# ============================================================

log_queue = queue.Queue()


class ConsoleOutput:
    def __init__(self, original):
        self.original = original

    def write(self, text):
        self.original.write(text)
        if text.strip():
            log_queue.put(text.rstrip())

    def flush(self):
        self.original.flush()


sys.stdout = ConsoleOutput(sys.stdout)
sys.stderr = ConsoleOutput(sys.stderr)


# ============================================================
# WebSocket
# ============================================================

async def handle_client(websocket):
    print("Client connecté")

    try:
        await websocket.send(json.dumps({"status": "connected"}))

        async for message in websocket:
            print("Message reçu :", message)

            data = json.loads(message)
            response = await handle_message(data, play_soundfont_note)
            print(json.dumps(response))
            await websocket.send(json.dumps(response))

    except websockets.exceptions.ConnectionClosed:
        print("Client déconnecté")


async def main():
    async with websockets.serve(
        handle_client,
        "127.0.0.1",
        8765
    ):
        print("Serveur WebSocket en écoute sur ws://127.0.0.1:8765")
        await asyncio.Future()


# ============================================================
# Gestion du serveur
# ============================================================

server_thread = None
server_running = False


def run_server():
    global server_running

    try:
        asyncio.run(main())
    except OSError as error:
        print(f"Impossible de démarrer le serveur : {error}")
    except Exception as error:
        print(f"Erreur serveur : {error}")
    finally:
        server_running = False


def start_server():
    global server_thread
    global server_running

    if server_running:
        print("Le serveur est déjà lancé.")
        return

    print("Démarrage du serveur Python...")
    server_running = True

    server_thread = threading.Thread(target=run_server, daemon=True)
    server_thread.start()


def get_logs():
    logs = []
    while not log_queue.empty():
        logs.append(log_queue.get())
    return logs


# ============================================================
# Lancement direct : Linux / Windows
# ============================================================

if __name__ == "__main__":
    start_server()
    server_thread.join()