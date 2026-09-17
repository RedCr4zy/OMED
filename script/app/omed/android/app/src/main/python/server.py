#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Serveur Python WebSocket pour le projet OMED.
"""

import asyncio
import websockets
import threading
import queue
import sys


# ============================================================
# >>> AJOUT : système de console
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
# <<< FIN AJOUT : système de console
# ============================================================


async def handle_client(websocket):
    print("Client connecté")

    try:
        await websocket.send(
            "Connection réussie pour client -> serveur !"
        )

        async for message in websocket:
            print("Message reçu :", message)

            await websocket.send("Message reçu !")

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
# >>> AJOUT : lancement du serveur depuis Android
# ============================================================

server_thread = None


def start_server():
    global server_thread

    if server_thread is not None and server_thread.is_alive():
        print("Le serveur est déjà lancé.")
        return

    print("Démarrage du serveur Python...")

    server_thread = threading.Thread(
        target=lambda: asyncio.run(main()),
        daemon=True
    )

    server_thread.start()


def get_logs():
    logs = []

    while not log_queue.empty():
        logs.append(log_queue.get())

    return logs


# ============================================================
# <<< FIN AJOUT : lancement du serveur depuis Android
# ============================================================